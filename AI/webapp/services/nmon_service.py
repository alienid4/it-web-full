"""
nmon 效能分析 Service
Collections:
  - nmon_daily   : 每台 x 每日聚合 (peak/avg)
"""
import os
import glob
import re
from datetime import datetime
from services.mongo_service import get_db, get_collection

NMON_DIR = os.environ.get("INSPECTION_HOME", "/opt/inspection") + "/data/nmon"


# ---------- low-level parser ----------
def _parse_nmon(path):
    """把一個 .nmon 解析成 dict; 只取 CPU_ALL / MEM / DISKBUSY / NET 四類 + ZZZZ 時戳"""
    result = {
        "path": path,
        "hostname": None,
        "date": None,   # YYYY-MM-DD
        "os": None,
        "snapshots": 0,
        "headers": {},   # {"CPU_ALL": ["User%", "Sys%", ...], ...}
        "zzzz": {},      # T0001 -> "HH:MM:SS"
        "cpu": [],       # list of (time, busy_pct)
        "mem": [],       # list of (time, used_pct)
        "disk": [],      # list of (time, max_busy_pct, max_disk_name)
        "net": [],       # list of (time, total_read_kbps, total_write_kbps)
    }

    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except Exception as e:
        result["error"] = f"read fail: {e}"
        return result

    for ln in lines:
        ln = ln.rstrip("\n").rstrip("\r")
        if not ln:
            continue
        parts = ln.split(",")
        tag = parts[0]

        if tag == "AAA":
            if len(parts) >= 3 and parts[1] == "host":
                result["hostname"] = parts[2]
            elif len(parts) >= 3 and parts[1] == "date":
                # "20-APR-2026"
                try:
                    result["date"] = datetime.strptime(parts[2], "%d-%b-%Y").strftime("%Y-%m-%d")
                except Exception:
                    result["date"] = parts[2]
            elif len(parts) >= 3 and parts[1] == "OS":
                result["os"] = ",".join(parts[2:])[:80]
            elif len(parts) >= 3 and parts[1] == "snapshots":
                try:
                    result["snapshots"] = int(parts[2])
                except Exception:
                    pass

        elif tag == "ZZZZ" and len(parts) >= 3:
            # ZZZZ,T0001,HH:MM:SS,DD-MMM-YYYY
            result["zzzz"][parts[1]] = parts[2]

        elif tag in ("CPU_ALL", "MEM", "DISKBUSY", "NET"):
            # header row: CPU_ALL,CPU Total <host>,User%,Sys%,Wait%,Idle%,Steal%,Busy,CPUs
            # data row: CPU_ALL,T0001,2.7,2.3,0.5,94.6,0.0,,2
            if len(parts) < 3:
                continue
            second = parts[1]
            if not re.match(r"^T\d+$", second):
                # header
                result["headers"][tag] = parts[2:]
                continue
            # data row
            tstamp = result["zzzz"].get(second, second)
            if tag == "CPU_ALL":
                # columns: User%, Sys%, Wait%, Idle%, [Steal%, Busy, CPUs]
                try:
                    idle = float(parts[5]) if len(parts) > 5 and parts[5] else 0.0
                    busy = round(100.0 - idle, 2)
                    result["cpu"].append((tstamp, busy))
                except Exception:
                    pass
            elif tag == "MEM":
                # Linux columns: memtotal,hightotal,lowtotal,swaptotal,memfree,highfree,lowfree,swapfree,memshared,cached,active,bigfree,buffers,swapcached,inactive
                hdrs = result["headers"].get("MEM", [])
                row = {}
                for i, h in enumerate(hdrs):
                    idx = 2 + i
                    if idx < len(parts):
                        try:
                            row[h] = float(parts[idx]) if parts[idx] not in ("", "-") else 0.0
                        except Exception:
                            row[h] = 0.0
                total = row.get("memtotal", 0)
                if total > 0:
                    free = row.get("memfree", 0)
                    cached = row.get("cached", 0)
                    buffers = row.get("buffers", 0)
                    used = total - free - cached - buffers
                    pct = round(used / total * 100, 2)
                    result["mem"].append((tstamp, pct))
            elif tag == "DISKBUSY":
                # columns: disk names e.g. sda,sda1,...
                hdrs = result["headers"].get("DISKBUSY", [])
                max_b, max_d = 0.0, None
                for i, h in enumerate(hdrs):
                    idx = 2 + i
                    if idx >= len(parts) or not parts[idx]:
                        continue
                    try:
                        v = float(parts[idx])
                        if v > max_b:
                            max_b = v
                            max_d = h
                    except Exception:
                        continue
                result["disk"].append((tstamp, round(max_b, 2), max_d or "-"))
            elif tag == "NET":
                # read + write KB/s across interfaces; skip 'lo'
                hdrs = result["headers"].get("NET", [])
                total_kbps = 0.0
                for i, h in enumerate(hdrs):
                    if h.startswith("lo-"):
                        continue
                    idx = 2 + i
                    if idx >= len(parts) or not parts[idx]:
                        continue
                    try:
                        total_kbps += float(parts[idx])
                    except Exception:
                        pass
                result["net"].append((tstamp, round(total_kbps, 2)))

    return result


def _aggregate_daily(parsed):
    """把 parsed file 壓縮成一天的 peak/avg + 保留 timeseries"""
    def _peak_avg(series, value_idx=1):
        if not series:
            return {"peak": 0, "avg": 0, "peak_time": None}
        vals = [row[value_idx] for row in series]
        peak_i = max(range(len(vals)), key=lambda i: vals[i])
        return {
            "peak": vals[peak_i],
            "avg": round(sum(vals) / len(vals), 2),
            "peak_time": series[peak_i][0],
        }

    disk_stats = _peak_avg(parsed["disk"], 1)
    if parsed["disk"]:
        peak_i = max(range(len(parsed["disk"])), key=lambda i: parsed["disk"][i][1])
        disk_stats["peak_disk"] = parsed["disk"][peak_i][2]
    else:
        disk_stats["peak_disk"] = None

    # 建 timeseries: 把 4 種 metric merge by time
    ts_map = {}
    for t, v in parsed["cpu"]:
        ts_map.setdefault(t, {})["cpu"] = v
    for t, v in parsed["mem"]:
        ts_map.setdefault(t, {})["mem"] = v
    for row in parsed["disk"]:
        t, v = row[0], row[1]
        ts_map.setdefault(t, {})["disk"] = v
    for t, v in parsed["net"]:
        ts_map.setdefault(t, {})["net_kbps"] = v
    timeseries = [{"time": t, **ts_map[t]} for t in sorted(ts_map.keys())]

    return {
        "hostname": parsed["hostname"],
        "date": parsed["date"],
        "os": parsed.get("os"),
        "snapshots": parsed["snapshots"],
        "cpu": _peak_avg(parsed["cpu"]),
        "mem": _peak_avg(parsed["mem"]),
        "disk": disk_stats,
        "net_kbps": _peak_avg(parsed["net"]),
        "timeseries": timeseries,
    }


# ---------- import ----------
def import_nmon_files(hostname=None, max_age_days=45):
    """
    掃 data/nmon/<host>/*.nmon → 解析 → upsert nmon_daily (唯一鍵: hostname+date)
    """
    col = get_collection("nmon_daily")
    col.create_index([("hostname", 1), ("date", 1)], unique=True)

    pattern = os.path.join(NMON_DIR, hostname if hostname else "*", "*.nmon")
    files = sorted(glob.glob(pattern))
    summary = {"scanned": 0, "imported": 0, "skipped": 0, "failed": []}

    for fp in files:
        summary["scanned"] += 1
        try:
            parsed = _parse_nmon(fp)
            if not parsed.get("hostname") or not parsed.get("date"):
                summary["skipped"] += 1
                continue
            if parsed["snapshots"] < 1 or not parsed["cpu"]:
                summary["skipped"] += 1
                continue
            daily = _aggregate_daily(parsed)
            hostname = daily["hostname"]
            date = daily["date"]

            # 5-min cron 產很多小檔, 同一天要合併 timeseries
            existing = col.find_one({"hostname": hostname, "date": date},
                                    {"_id": 0, "timeseries": 1, "source_files": 1})
            new_ts_times = {pt["time"] for pt in daily["timeseries"]}
            if existing:
                # 合併: 保留既有, 加入新 time (去重 by time)
                merged = [pt for pt in (existing.get("timeseries") or []) if pt["time"] not in new_ts_times]
                merged.extend(daily["timeseries"])
                merged.sort(key=lambda p: p["time"])
                daily["timeseries"] = merged

                # 重算 peak/avg 於合併後的 timeseries
                def _stats(key):
                    vs = [p.get(key) for p in merged if p.get(key) is not None]
                    if not vs:
                        return {"peak": 0, "avg": 0, "peak_time": None}
                    pi = max(range(len(vs)), key=lambda i: vs[i])
                    return {
                        "peak": vs[pi],
                        "avg": round(sum(vs) / len(vs), 2),
                        "peak_time": merged[pi]["time"],
                    }

                daily["cpu"] = _stats("cpu")
                daily["mem"] = _stats("mem")
                # disk: keep the peak_disk from whichever source has higher disk
                disk_stats = _stats("disk")
                # try preserve peak_disk
                if daily["disk"].get("peak_disk") and daily["disk"]["peak"] >= (existing.get("disk") or {}).get("peak", 0):
                    disk_stats["peak_disk"] = daily["disk"]["peak_disk"]
                else:
                    disk_stats["peak_disk"] = (existing.get("disk") or {}).get("peak_disk")
                daily["disk"] = disk_stats
                daily["net_kbps"] = _stats("net_kbps")
                daily["snapshots"] = len(merged)
                daily["source_files"] = (existing.get("source_files") or []) + [os.path.basename(fp)]
                daily["source_files"] = list(dict.fromkeys(daily["source_files"]))[-50:]  # 去重, 留最新 50
            else:
                daily["source_files"] = [os.path.basename(fp)]

            daily["imported_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            daily.pop("source_file", None)

            col.update_one(
                {"hostname": hostname, "date": date},
                {"$set": daily},
                upsert=True,
            )
            summary["imported"] += 1
        except Exception as e:
            summary["failed"].append({"file": os.path.basename(fp), "error": str(e)})

    return summary


def _delta(cur, prev):
    if prev is None or prev == 0:
        return None
    return round((cur or 0) - prev, 2)


def _host_meta(hostname):
    return get_collection("hosts").find_one({"hostname": hostname}, {
        "_id": 0, "hostname": 1, "ip": 1, "os": 1,
        "system_name": 1, "tier": 1,
    }) or {"hostname": hostname}


def get_day_report(hostname, date):
    """?date=YYYY-MM-DD → 當日 timeseries + peak/avg + 昨日比較 + 事件亮點"""
    from datetime import datetime, timedelta
    col = get_collection("nmon_daily")
    doc = col.find_one({"hostname": hostname, "date": date}, {"_id": 0})

    # 昨日
    prev_date = (datetime.strptime(date, "%Y-%m-%d") - timedelta(days=1)).strftime("%Y-%m-%d")
    prev = col.find_one({"hostname": hostname, "date": prev_date},
                        {"_id": 0, "cpu": 1, "mem": 1, "disk": 1, "net_kbps": 1}) or {}

    def _gv(d, k, sub):
        return ((d or {}).get(k) or {}).get(sub)

    compare = {
        "cpu":      _delta(_gv(doc, "cpu", "avg"),      _gv(prev, "cpu", "avg")),
        "mem":      _delta(_gv(doc, "mem", "avg"),      _gv(prev, "mem", "avg")),
        "disk":     _delta(_gv(doc, "disk", "avg"),     _gv(prev, "disk", "avg")),
        "net_kbps": _delta(_gv(doc, "net_kbps", "avg"), _gv(prev, "net_kbps", "avg")),
    }
    prev_avg = {
        "cpu": _gv(prev, "cpu", "avg"),
        "mem": _gv(prev, "mem", "avg"),
        "disk": _gv(prev, "disk", "avg"),
        "net_kbps": _gv(prev, "net_kbps", "avg"),
    }

    # 事件亮點: 掃當日 timeseries 看有無超門檻片段
    events = []
    ts = (doc or {}).get("timeseries") or []
    if ts:
        # CPU > 80, Mem > 85, Disk > 70
        thresholds = [("cpu", 80, "🔴", "CPU"), ("mem", 85, "🟠", "記憶體"),
                      ("disk", 70, "🟠", "磁碟")]
        for key, thr, icon, label in thresholds:
            over = [pt for pt in ts if (pt.get(key) or 0) >= thr]
            if over:
                # 取最高 1 個
                top = max(over, key=lambda p: p.get(key) or 0)
                events.append({
                    "level": "warn",
                    "icon": icon,
                    "text": f"{label} 峰值超 {thr}% @ {top['time']} ({top.get(key):.1f}%)",
                })
        # 若全正常, 顯示最高峰
        if not events:
            if _gv(doc, "cpu", "peak"):
                events.append({
                    "level": "ok", "icon": "✅",
                    "text": f"CPU 最高峰 {_gv(doc,'cpu','peak_time')} {_gv(doc,'cpu','peak'):.1f}% (未超過 80% 門檻)",
                })

    return {
        "host": _host_meta(hostname),
        "date": date,
        "daily": doc,
        "prev_date": prev_date,
        "compare": compare,
        "prev_day_avg": prev_avg,
        "events": events,
    }


def get_week_report(hostname, start_date):
    """start_date=YYYY-MM-DD → 7 天 + 上週比較 + 事件亮點"""
    from datetime import datetime, timedelta
    d0 = datetime.strptime(start_date, "%Y-%m-%d")
    end = d0 + timedelta(days=6)
    col = get_collection("nmon_daily")
    dailies = list(col.find(
        {"hostname": hostname, "date": {"$gte": start_date, "$lte": end.strftime("%Y-%m-%d")}},
        {"_id": 0, "timeseries": 0},
    ).sort("date", 1))

    # 上週
    pw_start = (d0 - timedelta(days=7)).strftime("%Y-%m-%d")
    pw_end = (d0 - timedelta(days=1)).strftime("%Y-%m-%d")
    prev_dailies = list(col.find(
        {"hostname": hostname, "date": {"$gte": pw_start, "$lte": pw_end}},
        {"_id": 0, "timeseries": 0},
    ))

    def _avg_peak(dlist, key):
        vals = [(d.get(key) or {}).get("peak") for d in dlist if (d.get(key) or {}).get("peak") is not None]
        if not vals:
            return None
        return round(sum(vals) / len(vals), 2)

    cur_avg = {
        "cpu": _avg_peak(dailies, "cpu"),
        "mem": _avg_peak(dailies, "mem"),
        "disk": _avg_peak(dailies, "disk"),
        "net_kbps": _avg_peak(dailies, "net_kbps"),
    }
    prev_avg = {
        "cpu": _avg_peak(prev_dailies, "cpu"),
        "mem": _avg_peak(prev_dailies, "mem"),
        "disk": _avg_peak(prev_dailies, "disk"),
        "net_kbps": _avg_peak(prev_dailies, "net_kbps"),
    }
    compare = {k: _delta(cur_avg[k], prev_avg[k]) for k in cur_avg}

    # 事件亮點
    events = []
    thresholds = [("cpu", 80, "🔴", "CPU"), ("mem", 85, "🟠", "記憶體"),
                  ("disk", 70, "🟠", "磁碟")]
    for key, thr, icon, label in thresholds:
        hot_days = [d for d in dailies if ((d.get(key) or {}).get("peak") or 0) >= thr]
        if hot_days:
            best = max(hot_days, key=lambda d: (d.get(key) or {}).get("peak") or 0)
            more = (f" 等 {len(hot_days)} 天" if len(hot_days) > 1 else "")
            events.append({
                "level": "warn", "icon": icon,
                "text": f"{label} 峰值超 {thr}%: {best['date']} {best.get(key,{}).get('peak',0):.1f}%{more}",
            })
    if not events and dailies:
        # 顯示本週最高峰
        best_cpu = max(dailies, key=lambda d: (d.get("cpu") or {}).get("peak") or 0)
        if (best_cpu.get("cpu") or {}).get("peak"):
            events.append({
                "level": "ok", "icon": "✅",
                "text": f"本週最高 CPU {best_cpu['date']} {best_cpu['cpu']['peak']:.1f}% (未超過 80% 門檻)",
            })

    return {
        "host": _host_meta(hostname),
        "start": start_date,
        "end": end.strftime("%Y-%m-%d"),
        "dailies": dailies,
        "prev_week": {"start": pw_start, "end": pw_end, "days": len(prev_dailies)},
        "cur_avg": cur_avg,
        "prev_week_avg": prev_avg,
        "compare": compare,
        "events": events,
    }


# ---------- query ----------
def list_enabled_hosts():
    """回傳 nmon_enabled=True 的主機清單 (加 ip/os/system_name/tier)"""
    col = get_collection("hosts")
    docs = list(col.find(
        {"nmon_enabled": True},
        {"_id": 0, "hostname": 1, "ip": 1, "os": 1, "os_group": 1, "system_name": 1, "tier": 1, "ap_owner": 1},
    ).sort("hostname", 1))
    return docs


def get_monthly_report(hostname, year, month):
    """
    year=2026, month=4 → 回傳該月所有 daily + 月級統計 + 上月比較
    """
    from calendar import monthrange
    m_start = f"{year:04d}-{month:02d}-01"
    _, last_day = monthrange(year, month)
    m_end = f"{year:04d}-{month:02d}-{last_day:02d}"

    # previous month
    if month == 1:
        pm_year, pm_month = year - 1, 12
    else:
        pm_year, pm_month = year, month - 1

    col = get_collection("nmon_daily")
    dailies = list(col.find(
        {"hostname": hostname, "date": {"$gte": m_start, "$lte": m_end}},
        {"_id": 0},
    ).sort("date", 1))

    def _overall(metric_key, sub_key="peak"):
        vals = [d[metric_key][sub_key] for d in dailies if d.get(metric_key) and d[metric_key].get(sub_key) is not None]
        if not vals:
            return {"peak": 0, "avg": 0}
        return {"peak": round(max(vals), 2), "avg": round(sum(vals) / len(vals), 2)}

    stats = {
        "cpu": _overall("cpu"),
        "mem": _overall("mem"),
        "disk": _overall("disk"),
        "net_kbps": _overall("net_kbps"),
    }

    # peak day+time lookup
    def _find_peak_day(metric_key):
        if not dailies:
            return None
        best = max(dailies, key=lambda d: (d.get(metric_key) or {}).get("peak", 0) or 0)
        return {
            "date": best["date"],
            "value": (best.get(metric_key) or {}).get("peak", 0),
            "peak_time": (best.get(metric_key) or {}).get("peak_time"),
            "peak_disk": (best.get(metric_key) or {}).get("peak_disk"),
        }

    peak_days = {
        "cpu": _find_peak_day("cpu"),
        "mem": _find_peak_day("mem"),
        "disk": _find_peak_day("disk"),
        "net_kbps": _find_peak_day("net_kbps"),
    }

    # previous month comparison
    pm_start = f"{pm_year:04d}-{pm_month:02d}-01"
    _, pm_last = monthrange(pm_year, pm_month)
    pm_end = f"{pm_year:04d}-{pm_month:02d}-{pm_last:02d}"
    pm_dailies = list(col.find(
        {"hostname": hostname, "date": {"$gte": pm_start, "$lte": pm_end}},
        {"_id": 0, "cpu": 1, "mem": 1, "disk": 1, "net_kbps": 1},
    ))

    def _pm_avg(metric_key):
        vals = [d[metric_key]["peak"] for d in pm_dailies if d.get(metric_key)]
        if not vals:
            return None
        return round(sum(vals) / len(vals), 2)

    prev = {
        "cpu": _pm_avg("cpu"),
        "mem": _pm_avg("mem"),
        "disk": _pm_avg("disk"),
        "net_kbps": _pm_avg("net_kbps"),
    }

    # compute delta (this vs prev)
    def _delta(cur, pm):
        if pm is None or pm == 0:
            return None
        return round(cur - pm, 2)

    compare = {
        "cpu": _delta(stats["cpu"]["avg"], prev["cpu"]),
        "mem": _delta(stats["mem"]["avg"], prev["mem"]),
        "disk": _delta(stats["disk"]["avg"], prev["disk"]),
        "net_kbps": _delta(stats["net_kbps"]["avg"], prev["net_kbps"]),
    }

    # host meta
    host_col = get_collection("hosts")
    host_doc = host_col.find_one({"hostname": hostname}, {
        "_id": 0, "hostname": 1, "ip": 1, "os": 1,
        "system_name": 1, "tier": 1, "ap_owner": 1,
    }) or {"hostname": hostname}

    return {
        "host": host_doc,
        "period": {"year": year, "month": month, "start": m_start, "end": m_end},
        "dailies": dailies,
        "stats": stats,
        "peak_days": peak_days,
        "compare_prev_month": compare,
        "prev_month_avg": prev,
        "days_with_data": len(dailies),
    }
