#!/usr/bin/env python3
"""匯入現有 JSON 報告與主機資料到 MongoDB"""
import json, glob, os, sys
from datetime import datetime
from pymongo import MongoClient

INSPECTION_HOME = "/opt/inspection"
client = MongoClient("localhost", 27017)
db = client["inspection"]

def import_hosts():
    """從 hosts_config.json 匯入主機資料"""
    fp = os.path.join(INSPECTION_HOME, "data/hosts_config.json")
    if not os.path.exists(fp):
        print(f"SKIP: {fp} not found")
        return 0
    with open(fp, encoding="utf-8") as f:
        hosts = json.load(f)
    if isinstance(hosts, dict):
        hosts = hosts.get("hosts", [hosts])
    count = 0
    for h in hosts:
        h.setdefault("imported_at", datetime.now().isoformat())
        h.setdefault("updated_at", datetime.now().isoformat())
        db.hosts.update_one({"hostname": h["hostname"]}, {"$set": h}, upsert=True)
        count += 1
    print(f"hosts: {count} 筆匯入/更新")
    return count

def import_inspections():
    """從 data/reports/*.json 匯入巡檢結果

    接受兩種檔名格式:
      (1) inspection_YYYYMMDD_HHMMSS_hostname.json   # v3.11.9.0+ 新格式
      (2) YYYYMMDD_HHMMSS_hostname.json              # 舊格式, 向後相容
    避免誤吃 twgcb_*.json / packages_*.json / nmon_*.json / security_audit_*.json / network_*.json
    """
    import re
    TS_RE = re.compile(r"^(?:inspection_)?\d{8}_\d{6}_")
    pattern = os.path.join(INSPECTION_HOME, "data/reports/*.json")
    files = sorted(fp for fp in glob.glob(pattern)
                   if TS_RE.match(os.path.basename(fp)))
    count = 0
    for fp in files:
        if fp.endswith("_report.json"):
            continue
        try:
            with open(fp, encoding="utf-8") as f:
                doc = json.load(f)
        except Exception as e:
            print(f"SKIP: {fp}: {e}")
            continue
        # 轉換現有格式到 MongoDB schema
        # 從檔名抓 timestamp: 去掉 inspection_ 前綴(若有), 取前 2 段 (YYYYMMDD_HHMMSS)
        fname = os.path.basename(fp)
        if fname.startswith("inspection_"):
            fname = fname[len("inspection_"):]
        ts = fname.split("_")[0] + "_" + fname.split("_")[1]
        hostname = doc.get("hostname", os.path.basename(fp).rsplit("_", 1)[-1].replace(".json", ""))
        run_date = ts[:4] + "-" + ts[4:6] + "-" + ts[6:8] if len(ts) >= 8 else datetime.now().strftime("%Y-%m-%d")
        run_time = ts[9:11] + ":" + ts[11:13] + ":" + ts[13:15] if len(ts) >= 15 else "00:00:00"

        mongo_doc = {
            "hostname": hostname,
            "run_id": ts,
            "run_date": run_date,
            "run_time": run_time,
            "overall_status": doc.get("overall_status", "ok").strip(),
            "ip": doc.get("ip", ""),
            "os": doc.get("os", ""),
            "results": doc.get("results", {}),
            "created_at": datetime.now().isoformat(),
        }
        # 展開 results 到頂層欄位以符合 schema
        r = doc.get("results", {})
        if "disk" in r:
            mongo_doc["disk"] = r["disk"]
        if "cpu" in r:
            mongo_doc["cpu"] = r["cpu"]
        if "service" in r:
            mongo_doc["service"] = r["service"]
        if "account" in r:
            mongo_doc["account"] = r["account"]
        if "error_log" in r:
            mongo_doc["error_log"] = r["error_log"]

        db.inspections.update_one(
            {"hostname": hostname, "run_id": ts},
            {"$set": mongo_doc},
            upsert=True
        )
        count += 1

        # v3.11.17.0: 把 results.account_audit 拆出來單獨寫進 account_audit collection
        # (api_audit.py _get_audit_data 讀這個 collection, 之前 seed_data 漏匯導致帳號盤點頁永遠空)
        accts = r.get("account_audit", []) or []
        if isinstance(accts, list):
            run_date = ts[:4] + "-" + ts[4:6] + "-" + ts[6:8] if len(ts) >= 8 else datetime.now().strftime("%Y-%m-%d")
            for a in accts:
                if not isinstance(a, dict):
                    continue
                user = a.get("user") or a.get("User") or ""
                if not user:
                    continue
                acct_doc = dict(a)
                acct_doc["hostname"] = hostname
                acct_doc["run_date"] = run_date
                acct_doc["imported_at"] = datetime.now().isoformat()
                db.account_audit.update_one(
                    {"hostname": hostname, "user": user, "run_date": run_date},
                    {"$set": acct_doc},
                    upsert=True,
                )

    print(f"inspections: {count} 筆匯入/更新")
    try:
        print(f"account_audit: {db.account_audit.count_documents({})} 筆 (累計)")
    except Exception:
        pass
    return count

def import_settings():
    """從 settings.json 匯入設定"""
    fp = os.path.join(INSPECTION_HOME, "data/settings.json")
    if not os.path.exists(fp):
        print("SKIP: settings.json not found")
        return
    with open(fp, encoding="utf-8") as f:
        settings = json.load(f)
    # 將 thresholds 存為獨立 key
    if "thresholds" in settings:
        db.settings.update_one(
            {"key": "thresholds"},
            {"$set": {"key": "thresholds", "value": settings["thresholds"]}},
            upsert=True
        )
    # 其他設定
    for k, v in settings.items():
        if k != "thresholds":
            db.settings.update_one(
                {"key": k}, {"$set": {"key": k, "value": v}}, upsert=True
            )
    print(f"settings: 匯入完成")

if __name__ == "__main__":
    print("=== 開始匯入資料到 MongoDB ===")
    import_hosts()
    import_inspections()
    import_settings()
    print(f"\n=== 匯入完成 ===")
    print(f"hosts: {db.hosts.count_documents({})} 筆")
    print(f"inspections: {db.inspections.count_documents({})} 筆")
    print(f"settings: {db.settings.count_documents({})} 筆")
