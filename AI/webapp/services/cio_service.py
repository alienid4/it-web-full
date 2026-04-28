"""
CIO / 資訊主管 儀表板 service
彙整: 主機健康 / TWGCB 合規率 / Top 5 高風險主機 / 綜合健康指數 / 事件摘要
"""
from datetime import datetime, timedelta
from services.mongo_service import get_collection, get_hosts_col, get_db


def get_host_health():
    """主機健康卡"""
    hosts_col = get_hosts_col()
    total = hosts_col.count_documents({"status": {"$ne": "停用"}})
    # online 以 ping cache 為準 (如果有), 否則 fallback 所有主機假設 online
    try:
        cache_col = get_collection("cache")
        pd = cache_col.find_one({"_id": "ping_all"})
        if pd and isinstance(pd.get("data"), dict):
            online = sum(1 for v in pd["data"].values() if v)
        else:
            online = total
    except Exception:
        online = total
    return {
        "total": total,
        "online": online,
        "offline": max(0, total - online),
        "rate": round(online / total * 100, 1) if total else 100.0,
    }


def get_twgcb_compliance():
    """TWGCB 全站合規率"""
    col = get_collection("twgcb_results")
    docs = list(col.find({}, {"_id": 0, "hostname": 1, "checks": 1, "os": 1}))
    total_checks, pass_checks, exc_checks = 0, 0, 0
    host_rates = []
    for d in docs:
        checks = d.get("checks") or []
        if not checks:
            continue
        p = sum(1 for c in checks if c.get("status") == "PASS")
        e = sum(1 for c in checks if c.get("exception"))
        total_checks += len(checks)
        pass_checks += p
        exc_checks += e
        rate = round(p / len(checks) * 100, 1)
        host_rates.append({
            "hostname": d.get("hostname"),
            "os": d.get("os", "-"),
            "total": len(checks),
            "pass": p,
            "fail": len(checks) - p,
            "rate": rate,
        })
    return {
        "total_checks": total_checks,
        "pass_checks": pass_checks,
        "fail_checks": total_checks - pass_checks,
        "exception_count": exc_checks,
        "rate": round(pass_checks / total_checks * 100, 1) if total_checks else 0.0,
        "host_rates": host_rates,
    }


def get_top_risk_hosts(limit=5):
    """合規率最低的 Top N 主機 (excluding 100%)"""
    compliance = get_twgcb_compliance()
    risky = [h for h in compliance["host_rates"] if h["rate"] < 100]
    risky.sort(key=lambda x: x["rate"])
    return risky[:limit]


def get_recent_events(limit=5, days=7):
    """最近 7 天的重要事件"""
    try:
        col = get_collection("admin_worklog")
        # 過濾出 高影響動作: login 以外的
        cutoff = (datetime.now() - timedelta(days=days)).isoformat()
        cursor = col.find(
            {"timestamp": {"$gte": cutoff}, "action": {"$nin": ["login"]}},
            {"_id": 0, "user": 1, "action": 1, "detail": 1, "timestamp": 1},
        ).sort("timestamp", -1).limit(limit)
        events = list(cursor)
        for e in events:
            e["timestamp"] = e.get("timestamp", "")[:16].replace("T", " ")
        return events
    except Exception:
        return []


def get_perf_highlights():
    """效能亮點 (nmon): 本月各主機最高峰 + 平均"""
    col = get_collection("nmon_daily")
    today = datetime.now().strftime("%Y-%m-%d")
    month_start = today[:7] + "-01"
    docs = list(col.find(
        {"date": {"$gte": month_start, "$lte": today}},
        {"_id": 0, "hostname": 1, "date": 1, "cpu": 1, "mem": 1, "disk": 1},
    ))
    if not docs:
        return {"available": False, "message": "本月尚無 nmon 資料"}
    # 找出 CPU 最高峰的主機
    best_cpu = max(docs, key=lambda d: (d.get("cpu") or {}).get("peak", 0) or 0)
    best_mem = max(docs, key=lambda d: (d.get("mem") or {}).get("peak", 0) or 0)
    return {
        "available": True,
        "month_start": month_start,
        "days_with_data": len({d["date"] for d in docs}),
        "cpu_peak": {
            "hostname": best_cpu["hostname"],
            "date": best_cpu["date"],
            "value": (best_cpu.get("cpu") or {}).get("peak", 0),
        },
        "mem_peak": {
            "hostname": best_mem["hostname"],
            "date": best_mem["date"],
            "value": (best_mem.get("mem") or {}).get("peak", 0),
        },
    }


def get_security_summary():
    """資安摘要: 套件 CVE (若 pip-audit run 過存 security_audit_reports) + TWGCB A級未修"""
    compliance = get_twgcb_compliance()
    # A 級 FAIL 未修 (TWGCB level A 是最高優先)
    col = get_collection("twgcb_results")
    a_fail = 0
    for d in col.find({}, {"checks": 1}):
        for c in (d.get("checks") or []):
            if c.get("status") == "FAIL" and c.get("level") == "A" and not c.get("exception"):
                a_fail += 1
    return {
        "a_level_fail_open": a_fail,
        "exception_count": compliance["exception_count"],
    }


def get_health_score():
    """綜合健康指數 (0-100)"""
    hh = get_host_health()
    cc = get_twgcb_compliance()
    ss = get_security_summary()

    # weights
    host_score = hh["rate"]  # 0-100
    compliance_score = cc["rate"]
    # security score: 每個 A 級未修扣 5 分 (上限 30 分)
    security_deduct = min(30, ss["a_level_fail_open"] * 5)
    security_score = 100 - security_deduct

    # 綜合 = 主機 0.3 + 合規 0.4 + 資安 0.3
    score = host_score * 0.3 + compliance_score * 0.4 + security_score * 0.3
    score = round(score, 1)
    level = "優良" if score >= 90 else ("良好" if score >= 80 else ("注意" if score >= 70 else "警告"))
    color = "green" if score >= 90 else ("lightgreen" if score >= 80 else ("orange" if score >= 70 else "red"))

    return {
        "score": score,
        "level": level,
        "color": color,
        "components": {
            "host_health": round(host_score, 1),
            "compliance": round(compliance_score, 1),
            "security": round(security_score, 1),
        },
    }


def get_overview():
    """一次打包所有資料 — 給 /api/cio/overview"""
    return {
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "health_score": get_health_score(),
        "host_health": get_host_health(),
        "compliance": {
            k: v for k, v in get_twgcb_compliance().items() if k != "host_rates"
        },
        "top_risks": get_top_risk_hosts(5),
        "security": get_security_summary(),
        "perf": get_perf_highlights(),
        "recent_events": get_recent_events(5),
    }


def get_action_recommendations():
    """下一步行動建議"""
    recs = []
    cc = get_twgcb_compliance()
    risk = [h for h in cc["host_rates"] if h["rate"] < 80]
    if risk:
        recs.append({
            "level": "warn",
            "text": f"{len(risk)} 台主機合規率 < 80%, 建議列入本月改善",
            "hosts": [h["hostname"] for h in risk][:5],
        })
    ss = get_security_summary()
    if ss["a_level_fail_open"] > 0:
        recs.append({
            "level": "error",
            "text": f"{ss['a_level_fail_open']} 項 TWGCB A 級 FAIL 未修 (高優先)",
        })
    try:
        ex_col = get_collection("twgcb_exceptions")
        exc_count = ex_col.count_documents({})
        if exc_count:
            recs.append({
                "level": "info",
                "text": f"目前共 {exc_count} 筆 TWGCB 例外, 建議定期覆核",
            })
    except Exception:
        pass
    if not recs:
        recs.append({"level": "ok", "text": "系統目前無重大風險"})
    return recs



# ===== CIO #2: TWGCB 合規率 daily snapshot + 趨勢 =====
def snapshot_twgcb_daily():
    """每日 1 次 snapshot 當前合規狀態到 twgcb_daily_stats (唯一鍵 date)"""
    today = datetime.now().strftime("%Y-%m-%d")
    cc = get_twgcb_compliance()
    col = get_collection("twgcb_daily_stats")
    col.create_index("date", unique=True)
    doc = {
        "date": today,
        "total_checks": cc["total_checks"],
        "pass_checks": cc["pass_checks"],
        "fail_checks": cc["fail_checks"],
        "exception_count": cc["exception_count"],
        "rate": cc["rate"],
        "host_count": len(cc["host_rates"]),
        "snapshot_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }
    col.update_one({"date": today}, {"$set": doc}, upsert=True)
    return doc


def get_compliance_trend(days=30):
    """近 N 天合規率趨勢"""
    col = get_collection("twgcb_daily_stats")
    cutoff = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
    cursor = col.find({"date": {"$gte": cutoff}}, {"_id": 0}).sort("date", 1)
    data = list(cursor)
    # 若今天還沒 snapshot, 立刻補一次
    if not data or data[-1]["date"] != datetime.now().strftime("%Y-%m-%d"):
        snapshot_twgcb_daily()
        cursor = col.find({"date": {"$gte": cutoff}}, {"_id": 0}).sort("date", 1)
        data = list(cursor)
    return data



# ===== CIO #3: 合規項老化分析 =====
def get_aging_analysis(threshold_days=30):
    """
    哪些 TWGCB FAIL 項目開了很久還沒修?
    沒有歷史 first_failed_at, 以當前 twgcb_results.scan_time 當 last_seen FAIL
    聚合 by 部門 (department) / AP 負責人 (ap_owner)
    """
    from datetime import datetime, timedelta
    twgcb_col = get_collection("twgcb_results")
    hosts_col = get_hosts_col()

    # 抓所有 hostname → {department, ap_owner} map
    meta = {}
    for h in hosts_col.find({}, {"_id": 0, "hostname": 1, "department": 1, "ap_owner": 1, "system_name": 1}):
        meta[h.get("hostname")] = h

    # 掃 twgcb_results 找 FAIL 項 (扣掉 exception)
    now = datetime.now()
    fail_items = []
    for d in twgcb_col.find({}, {"_id": 0}):
        hn = d.get("hostname")
        scan_time = d.get("scan_time") or d.get("imported_at") or ""
        # 嘗試解析 scan_time
        age_days = 0
        try:
            for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"):
                try:
                    st = datetime.strptime(scan_time[:19], fmt)
                    age_days = max(0, (now - st).days)
                    break
                except Exception:
                    continue
        except Exception:
            pass

        m = meta.get(hn, {})
        for c in (d.get("checks") or []):
            if c.get("status") != "FAIL" or c.get("exception"):
                continue
            fail_items.append({
                "hostname": hn,
                "department": m.get("department", "(未分類)"),
                "ap_owner": m.get("ap_owner", "(未指派)"),
                "system_name": m.get("system_name", "(無)"),
                "check_id": c.get("id"),
                "name": c.get("name"),
                "level": c.get("level"),
                "category": c.get("category"),
                "age_days": age_days,
                "over_threshold": age_days >= threshold_days,
            })

    # 聚合 by department
    by_dept = {}
    for i in fail_items:
        k = i["department"]
        by_dept.setdefault(k, {"department": k, "fail_count": 0, "over_threshold": 0, "hosts": set()})
        by_dept[k]["fail_count"] += 1
        by_dept[k]["hosts"].add(i["hostname"])
        if i["over_threshold"]:
            by_dept[k]["over_threshold"] += 1
    for v in by_dept.values():
        v["host_count"] = len(v["hosts"])
        v["hosts"] = sorted(v["hosts"])

    # 聚合 by ap_owner
    by_owner = {}
    for i in fail_items:
        k = i["ap_owner"]
        by_owner.setdefault(k, {"ap_owner": k, "fail_count": 0, "over_threshold": 0, "hosts": set()})
        by_owner[k]["fail_count"] += 1
        by_owner[k]["hosts"].add(i["hostname"])
        if i["over_threshold"]:
            by_owner[k]["over_threshold"] += 1
    for v in by_owner.values():
        v["host_count"] = len(v["hosts"])
        v["hosts"] = sorted(v["hosts"])

    # 聚合 by level
    by_level = {}
    for i in fail_items:
        k = i["level"] or "(無)"
        by_level.setdefault(k, {"level": k, "count": 0, "over_threshold": 0})
        by_level[k]["count"] += 1
        if i["over_threshold"]:
            by_level[k]["over_threshold"] += 1

    # 超老 (>threshold_days) 的前 N 筆
    old_fails = sorted([i for i in fail_items if i["over_threshold"]],
                       key=lambda x: -x["age_days"])[:20]

    return {
        "threshold_days": threshold_days,
        "total_fails": len(fail_items),
        "over_threshold_count": sum(1 for i in fail_items if i["over_threshold"]),
        "by_department": sorted(by_dept.values(), key=lambda x: -x["fail_count"]),
        "by_ap_owner": sorted(by_owner.values(), key=lambda x: -x["fail_count"]),
        "by_level": sorted(by_level.values(), key=lambda x: x["level"]),
        "old_fails_top": old_fails,
    }
