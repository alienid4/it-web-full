from pymongo import MongoClient
from config import MONGO_CONFIG

_client = None
_db = None


def get_db():
    global _client, _db
    if _db is None:
        _client = MongoClient(MONGO_CONFIG["host"], MONGO_CONFIG["port"])
        _db = _client[MONGO_CONFIG["db"]]
    return _db


def get_collection(name):
    return get_db()[name]


def get_hosts_col():
    """主機/資產清單 collection. 未來若 collection 改名 (hosts → assets), 只改這一行"""
    return get_hosts_col()


# --- hosts ---
def get_all_hosts(query=None, page=1, per_page=50):
    col = get_hosts_col()
    q = query or {}
    skip = (page - 1) * per_page
    total = col.count_documents(q)
    docs = list(col.find(q, {"_id": 0}).skip(skip).limit(per_page))
    return {"data": docs, "total": total, "page": page, "per_page": per_page}


def get_host(hostname):
    return get_hosts_col().find_one({"hostname": hostname}, {"_id": 0})


def upsert_host(doc):
    col = get_hosts_col()
    col.update_one({"hostname": doc["hostname"]}, {"$set": doc}, upsert=True)


def get_hosts_summary():
    col = get_collection("inspections")
    pipeline = [
        {"$sort": {"created_at": -1}},
        {"$group": {
            "_id": "$hostname",
            "latest_status": {"$first": "$overall_status"},
        }},
        {"$group": {
            "_id": "$latest_status",
            "count": {"$sum": 1},
        }},
    ]
    results = list(col.aggregate(pipeline))
    summary = {"ok": 0, "warn": 0, "error": 0, "total": 0}
    for r in results:
        s = r["_id"].strip() if r["_id"] else "ok"
        if s in summary:
            summary[s] = r["count"]
    summary["total"] = summary["ok"] + summary["warn"] + summary["error"]
    return summary


# --- inspections ---
def get_latest_inspections():
    col = get_collection("inspections")
    pipeline = [
        {"$sort": {"run_date": -1, "run_time": -1}},
        {"$group": {
            "_id": "$hostname",
            "doc": {"$first": "$$ROOT"},
        }},
        {"$replaceRoot": {"newRoot": "$doc"}},
        {"$project": {"_id": 0}},
    ]
    results = list(col.aggregate(pipeline))
    hosts_map = {h["hostname"]: h for h in get_hosts_col().find(
        {}, {"_id": 0, "hostname": 1, "ip": 1, "custodian": 1}
    )}
    for r in results:
        info = hosts_map.get(r.get("hostname"), {})
        if not r.get("ip"):
            r["ip"] = info.get("ip", "")
        if not r.get("custodian"):
            r["custodian"] = info.get("custodian", "")
    return results


def get_host_latest_inspection(hostname):
    col = get_collection("inspections")
    return col.find_one({"hostname": hostname}, {"_id": 0}, sort=[("run_date", -1), ("run_time", -1)])


def get_host_history(hostname, days=7):
    from datetime import datetime, timedelta
    col = get_collection("inspections")
    since = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
    docs = list(col.find(
        {"hostname": hostname, "run_date": {"$gte": since}},
        {"_id": 0}
    ).sort("run_date", 1))
    return docs


def get_abnormal_inspections():
    col = get_collection("inspections")
    pipeline = [
        {"$sort": {"run_date": -1, "run_time": -1}},
        {"$group": {"_id": "$hostname", "doc": {"$first": "$$ROOT"}}},
        {"$replaceRoot": {"newRoot": "$doc"}},
        {"$match": {"overall_status": {"$in": ["warn", "error"]}}},
        {"$project": {"_id": 0}},
    ]
    return list(col.aggregate(pipeline))


def get_trend(days=7):
    from datetime import datetime, timedelta
    col = get_collection("inspections")
    since = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
    pipeline = [
        {"$match": {"run_date": {"$gte": since}}},
        {"$group": {
            "_id": {"date": "$run_date", "status": "$overall_status"},
            "count": {"$sum": 1},
        }},
        {"$sort": {"_id.date": 1}},
    ]
    results = list(col.aggregate(pipeline))
    trend = {}
    for r in results:
        d = r["_id"]["date"]
        s = r["_id"]["status"].strip() if r["_id"]["status"] else "ok"
        if d not in trend:
            trend[d] = {"date": d, "ok": 0, "warn": 0, "error": 0}
        if s in trend[d]:
            trend[d][s] = r["count"]
    return sorted(trend.values(), key=lambda x: x["date"])


# --- filter_rules ---
def get_all_rules():
    return list(get_collection("filter_rules").find({}, {"_id": 0}))


def add_rule(doc):
    from bson import ObjectId
    doc["rule_id"] = str(ObjectId())
    doc.setdefault("hit_count", 0)
    doc.setdefault("enabled", True)
    get_collection("filter_rules").insert_one(doc)
    return doc["rule_id"]


def update_rule(rule_id, updates):
    get_collection("filter_rules").update_one({"rule_id": rule_id}, {"$set": updates})


def delete_rule(rule_id):
    get_collection("filter_rules").delete_one({"rule_id": rule_id})


def toggle_rule(rule_id):
    col = get_collection("filter_rules")
    rule = col.find_one({"rule_id": rule_id})
    if rule:
        col.update_one({"rule_id": rule_id}, {"$set": {"enabled": not rule.get("enabled", True)}})
        return not rule.get("enabled", True)
    return None


# --- settings ---
def get_all_settings():
    docs = list(get_collection("settings").find({}, {"_id": 0}))
    return {d["key"]: d["value"] for d in docs}


def update_setting(key, value):
    get_collection("settings").update_one(
        {"key": key}, {"$set": {"key": key, "value": value}}, upsert=True
    )


def get_summary_report():
    """產生異常總結報告：依嚴重度排序，含原因、建議、負責人、趨勢比較"""
    from datetime import datetime, timedelta
    col = get_collection("inspections")
    hosts_col = get_hosts_col()

    # 最新巡檢
    pipeline = [
        {"$sort": {"run_date": -1, "run_time": -1}},
        {"$group": {"_id": "$hostname", "doc": {"$first": "$$ROOT"}}},
        {"$replaceRoot": {"newRoot": "$doc"}},
        {"$project": {"_id": 0}},
    ]
    latest = list(col.aggregate(pipeline))

    # 昨天的巡檢（用於趨勢比較）
    yesterday = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
    yesterday_pipeline = [
        {"$match": {"run_date": yesterday}},
        {"$sort": {"run_time": -1}},
        {"$group": {"_id": "$hostname", "doc": {"$first": "$$ROOT"}}},
        {"$replaceRoot": {"newRoot": "$doc"}},
        {"$project": {"_id": 0}},
    ]
    yesterday_data = {d["hostname"]: d for d in col.aggregate(yesterday_pipeline)}

    severity_order = {"error": 0, "warn": 1, "ok": 2}
    report_items = []

    for h in latest:
        s = (h.get("overall_status") or "ok").strip()
        if s == "ok":
            continue

        hostname = h.get("hostname", "")
        host_info = hosts_col.find_one({"hostname": hostname}, {"_id": 0}) or {}
        disk = h.get("disk") or h.get("results", {}).get("disk") or {}
        cpu = h.get("cpu") or h.get("results", {}).get("cpu") or {}
        svc = h.get("service") or h.get("results", {}).get("service") or {}
        acct = h.get("account") or h.get("results", {}).get("account") or {}
        elog = h.get("error_log") or h.get("results", {}).get("error_log") or {}

        # 找出異常原因
        issues = []
        suggestions = []

        # 磁碟
        for p in disk.get("partitions", []):
            pct = int(float(p.get("percent", 0)))
            ps = (p.get("status") or "ok").strip()
            if ps in ("warn", "error"):
                issues.append({"category": "磁碟", "severity": ps, "detail": f"{p['mount']} 使用率 {pct}% ({p.get('used','')}/{p.get('size','')})"})
                if ps == "error":
                    suggestions.append(f"立即清理 {p['mount']}，使用率已達 {pct}%")
                else:
                    suggestions.append(f"規劃清理 {p['mount']}，使用率 {pct}% 接近警戒")

        # CPU
        cpu_pct = int(float(cpu.get("cpu_percent") or cpu.get("percent") or 0))
        cpu_s = (cpu.get("status") or cpu.get("cpu_status") or "ok").strip()
        if cpu_s in ("warn", "error"):
            issues.append({"category": "CPU", "severity": cpu_s, "detail": f"CPU 使用率 {cpu_pct}%"})
            suggestions.append(f"檢查高 CPU 程序：top -b -n1 | head -20")

        mem_pct = int(float(cpu.get("mem_percent") or 0))
        mem_s = (cpu.get("mem_status") or "ok").strip()
        if mem_s in ("warn", "error"):
            issues.append({"category": "記憶體", "severity": mem_s, "detail": f"Memory 使用率 {mem_pct}%"})
            suggestions.append(f"檢查記憶體：free -h && ps aux --sort=-%mem | head -10")

        # 服務
        for sv in svc.get("services", []):
            sv_s = (sv.get("status") or "active").strip()
            if sv_s not in ("active", "ok"):
                issues.append({"category": "服務", "severity": "error", "detail": f"{sv['name']} 狀態: {sv_s}"})
                suggestions.append(f"重啟服務：systemctl restart {sv['name']}")

        # 帳號
        acct_s = (acct.get("status") or "ok").strip()
        added = acct.get("accounts_added") or []
        uid0 = acct.get("uid0_alert") or False
        if acct_s in ("warn", "error") or uid0:
            sev = "error" if uid0 else acct_s
            detail = "帳號異動"
            if added:
                names = ", ".join(a if isinstance(a, str) else a.get("name", str(a)) for a in added)
                detail = f"新增帳號: {names}"
            if uid0:
                detail += " [UID=0 高危警示]"
            issues.append({"category": "帳號", "severity": sev, "detail": detail})
            if uid0:
                suggestions.append("立即確認 UID=0 帳號是否為授權變更")
            else:
                suggestions.append("確認帳號異動是否經過授權")

        # 錯誤日誌
        err_count = int(float(str(elog.get("error_count") or elog.get("count") or 0)))
        elog_s = (elog.get("status") or "ok").strip()
        if elog_s in ("warn", "error"):
            issues.append({"category": "錯誤日誌", "severity": elog_s, "detail": f"{err_count} 筆錯誤"})
            suggestions.append(f"查看日誌：journalctl -p err --since today")

        # 趨勢比較
        prev = yesterday_data.get(hostname)
        trend = "new"
        if prev:
            prev_s = (prev.get("overall_status") or "ok").strip()
            if prev_s == "ok" and s != "ok":
                trend = "degraded"
            elif prev_s == s:
                trend = "unchanged"
            elif severity_order.get(s, 2) < severity_order.get(prev_s, 2):
                trend = "worsened"
            else:
                trend = "improved"

        report_items.append({
            "hostname": hostname,
            "ip": h.get("ip") or host_info.get("ip", ""),
            "os": h.get("os") or host_info.get("os", ""),
            "overall_status": s,
            "run_date": h.get("run_date", ""),
            "run_time": h.get("run_time", ""),
            "custodian": host_info.get("custodian", "-"),
            "custodian_ad": host_info.get("custodian_ad", ""),
            "department": host_info.get("department", "-"),
            "issues": issues,
            "suggestions": suggestions,
            "trend": trend,
            "issue_count": len(issues),
        })

    # 依嚴重度排序：error 優先，再依 issue 數量
    report_items.sort(key=lambda x: (severity_order.get(x["overall_status"], 2), -x["issue_count"]))

    total_hosts = len(latest)
    abnormal_count = len(report_items)
    ok_count = total_hosts - abnormal_count

    return {
        "generated_at": datetime.now().isoformat(),
        "total_hosts": total_hosts,
        "ok_count": ok_count,
        "abnormal_count": abnormal_count,
        "items": report_items,
    }
