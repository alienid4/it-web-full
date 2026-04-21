#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
巡檢系統測試種子資料
在開發環境中執行此腳本，將測試資料寫入 MongoDB，
讓前端頁面有資料可以顯示。

執行方式：
    python3 seed_test_data.py

前提：MongoDB 已在 localhost:27017 運行
"""

from pymongo import MongoClient
from datetime import datetime, timedelta
import random
import bcrypt
import json

client = MongoClient("localhost", 27017)
db = client["inspection"]

print("=" * 60)
print("  巡檢系統 — 測試種子資料產生器")
print("=" * 60)


# ============================================================
# 1. 主機清單 (hosts)
# ============================================================
hosts_data = [
    {
        "hostname": "SECSVR001",
        "ip": "10.0.0.XX",
        "os": "Rocky Linux 9.7",
        "os_group": "rocky",
        "status": "使用中",
        "environment": "正式",
        "group": "Web Servers",
        "has_python": True,
        "asset_seq": "AST-2024-0001",
        "asset_name": "券商前台 Web",
        "division": "資訊處",
        "department": "系統部",
        "owner": "系統部",
        "custodian": "王大明",
        "custodian_ad": "dmwang",
        "system_type": "gold",
        "ap_owner": "陳小華",
    },
    {
        "hostname": "SECSVR002",
        "ip": "10.0.0.XX",
        "os": "Red Hat Enterprise Linux 8.9",
        "os_group": "rhel",
        "status": "使用中",
        "environment": "正式",
        "group": "DB Servers",
        "has_python": True,
        "asset_seq": "AST-2024-0002",
        "asset_name": "Oracle 資料庫",
        "division": "資訊處",
        "department": "系統部",
        "owner": "系統部",
        "custodian": "李小龍",
        "custodian_ad": "xllee",
        "system_type": "gold",
        "ap_owner": "張三",
    },
    {
        "hostname": "SECSVR003",
        "ip": "10.0.0.XX",
        "os": "Debian 12.5",
        "os_group": "debian",
        "status": "使用中",
        "environment": "正式",
        "group": "App Servers",
        "has_python": True,
        "asset_seq": "AST-2024-0003",
        "asset_name": "後台 API 服務",
        "division": "資訊處",
        "department": "開發部",
        "owner": "開發部",
        "custodian": "林美玲",
        "custodian_ad": "mllin",
        "system_type": "silver",
        "ap_owner": "王五",
    },
    {
        "hostname": "SECSVR004",
        "ip": "10.0.0.XX",
        "os": "Rocky Linux 9.7",
        "os_group": "rocky",
        "status": "使用中",
        "environment": "測試",
        "group": "Dev Servers",
        "has_python": True,
        "asset_seq": "AST-2024-0004",
        "asset_name": "開發測試機",
        "division": "資訊處",
        "department": "開發部",
        "owner": "開發部",
        "custodian": "趙六",
        "custodian_ad": "lzhao",
        "system_type": "bronze",
        "ap_owner": "趙六",
    },
    {
        "hostname": "SECWIN001",
        "ip": "10.0.0.XX",
        "os": "Windows Server 2022",
        "os_group": "windows",
        "status": "使用中",
        "environment": "正式",
        "group": "Windows Servers",
        "has_python": False,
        "asset_seq": "AST-2024-0005",
        "asset_name": "AD 網域控制器",
        "division": "資訊處",
        "department": "網路部",
        "owner": "網路部",
        "custodian": "周七",
        "custodian_ad": "qzhou",
        "system_type": "gold",
        "ap_owner": "周七",
    },
    {
        "hostname": "SECSVR005",
        "ip": "10.0.0.XX",
        "os": "Red Hat Enterprise Linux 9.3",
        "os_group": "rhel",
        "status": "停用",
        "environment": "正式",
        "group": "Retired",
        "has_python": True,
        "asset_seq": "AST-2023-0010",
        "asset_name": "舊版報表伺服器",
        "division": "資訊處",
        "department": "系統部",
        "owner": "系統部",
        "custodian": "吳八",
        "custodian_ad": "bwu",
        "system_type": "bronze",
        "ap_owner": "吳八",
    },
]

now = datetime.utcnow().isoformat()
for h in hosts_data:
    h["imported_at"] = now
    h["updated_at"] = now
    db.hosts.update_one(
        {"hostname": h["hostname"]},
        {"$set": h},
        upsert=True,
    )
print(f"[OK] hosts: {len(hosts_data)} 筆")


# ============================================================
# 2. 巡檢結果 (inspections) — 產生過去 7 天資料
# ============================================================
active_hosts = [h for h in hosts_data if h["status"] == "使用中"]
services_list = ["sshd", "crond", "httpd"]
inspection_count = 0

for day_offset in range(7, -1, -1):
    dt = datetime.utcnow() - timedelta(days=day_offset)
    run_date = dt.strftime("%Y-%m-%d")

    for run_hour in ["06:30:00", "13:30:00", "17:30:00"]:
        run_id = dt.strftime("%Y%m%d") + "_" + run_hour.replace(":", "")

        for host in active_hosts:
            # 隨機產生巡檢數據
            disk_pct = random.randint(30, 98)
            cpu_pct = round(random.uniform(5, 99), 1)
            mem_pct = round(random.uniform(20, 95), 1)
            swap_pct = round(random.uniform(0, 30), 1)
            io_busy = round(random.uniform(0, 50), 1)
            err_count = random.choice([0, 0, 0, 0, 1, 2, 3, 5])
            fail_login_count = random.choice([0, 0, 0, 5, 10, 20])
            uid0_alert = random.random() < 0.03  # 3% 機率

            disk_status = "ok" if disk_pct < 85 else ("warn" if disk_pct < 95 else "error")
            cpu_status = "ok" if cpu_pct < 80 else ("warn" if cpu_pct < 95 else "error")
            svc_stopped = random.random() < 0.05

            inspection = {
                "hostname": host["hostname"],
                "run_id": run_id,
                "run_date": run_date,
                "run_time": run_hour,
                "ip": host["ip"],
                "os": host["os"],
                "disk": {
                    "status": disk_status,
                    "warn_threshold": 85,
                    "crit_threshold": 95,
                    "partitions": [
                        {"mount": "/", "size": "50G", "used": f"{disk_pct // 2}G", "free": f"{50 - disk_pct // 2}G", "percent": disk_pct, "status": disk_status},
                        {"mount": "/home", "size": "100G", "used": "30G", "free": "70G", "percent": 30, "status": "ok"},
                        {"mount": "/var", "size": "30G", "used": f"{random.randint(5, 25)}G", "free": f"{random.randint(5, 25)}G", "percent": random.randint(20, 80), "status": "ok"},
                    ],
                },
                "cpu": {
                    "status": cpu_status,
                    "cpu_percent": cpu_pct,
                    "mem_percent": mem_pct,
                    "warn_threshold": 80,
                    "crit_threshold": 95,
                },
                "service": {
                    "status": "error" if svc_stopped else "ok",
                    "services": [
                        {"name": "sshd", "status": "running"},
                        {"name": "crond", "status": "stopped" if svc_stopped else "running"},
                    ],
                },
                "account": {
                    "status": "error" if uid0_alert else "ok",
                    "diff": "No changes",
                    "uid0_alert": uid0_alert,
                    "accounts_added": ["testuser"] if random.random() < 0.05 else [],
                    "accounts_removed": [],
                },
                "error_log": {
                    "status": "warn" if err_count > 0 else "ok",
                    "count": err_count,
                    "max_entries": 50,
                    "entries": [
                        {"time": f"{run_date} {run_hour}", "level": random.choice(["WARNING", "ERROR"]), "message": random.choice([
                            "disk space low on /",
                            "failed to rotate log",
                            "high swap usage detected",
                            "connection refused",
                            "segfault in process",
                        ])}
                        for _ in range(min(err_count, 5))
                    ],
                },
                "system": {
                    "status": "ok",
                    "swap_percent": swap_pct,
                    "io_busy": io_busy,
                    "load_average": {
                        "1min": round(random.uniform(0.1, 4.0), 2),
                        "5min": round(random.uniform(0.1, 3.0), 2),
                        "15min": round(random.uniform(0.1, 2.0), 2),
                    },
                    "uptime_seconds": random.randint(86400, 8640000),
                    "online_users": random.randint(1, 5),
                    "failed_login": {
                        "count": fail_login_count,
                        "top_offenders": [
                            {
                                "user": "root",
                                "count": fail_login_count,
                                "status": "locked" if fail_login_count > 10 else "ok",
                                "unlock_cmds": ["faillock --user root --reset"] if fail_login_count > 10 else [],
                            }
                        ] if fail_login_count > 0 else [],
                    },
                },
                "created_at": dt.isoformat(),
            }

            # 計算 overall_status
            statuses = [
                inspection["disk"]["status"],
                inspection["cpu"]["status"],
                inspection["service"]["status"],
                inspection["account"]["status"],
                inspection["error_log"]["status"],
            ]
            if "error" in statuses:
                inspection["overall_status"] = "error"
            elif "warn" in statuses:
                inspection["overall_status"] = "warn"
            else:
                inspection["overall_status"] = "ok"

            db.inspections.update_one(
                {"hostname": host["hostname"], "run_id": run_id},
                {"$set": inspection},
                upsert=True,
            )
            inspection_count += 1

print(f"[OK] inspections: {inspection_count} 筆 (5 主機 x 8 天 x 3 次/天)")


# ============================================================
# 3. 過濾規則 (filter_rules)
# ============================================================
rules = [
    {
        "rule_id": "rule_001",
        "name": "已知的日誌輪替錯誤",
        "type": "keyword",
        "pattern": "failed to rotate log",
        "apply_to": "all",
        "enabled": True,
        "is_known_issue": True,
        "known_issue_reason": "logrotate 設定問題，已排入下次維護窗口修復",
        "hit_count": 42,
        "created_at": now,
        "updated_at": now,
    },
    {
        "rule_id": "rule_002",
        "name": "開發機 CPU 高負載",
        "type": "keyword",
        "pattern": "cpu_percent",
        "apply_to": "SECSVR004",
        "enabled": True,
        "is_known_issue": True,
        "known_issue_reason": "開發機跑 CI/CD 編譯時 CPU 會飆高，屬正常現象",
        "hit_count": 15,
        "created_at": now,
        "updated_at": now,
    },
]

for r in rules:
    db.filter_rules.update_one({"rule_id": r["rule_id"]}, {"$set": r}, upsert=True)
print(f"[OK] filter_rules: {len(rules)} 筆")


# ============================================================
# 4. 系統設定 (settings)
# ============================================================
settings = {
    "thresholds": {"disk_warn": 85, "disk_crit": 95, "cpu_warn": 80, "cpu_crit": 95, "mem_warn": 80, "mem_crit": 95},
    "disk_exclude_mounts": ["/dev", "/run", "/sys", "/proc", "/tmp"],
    "disk_exclude_prefixes": ["/run/", "/dev/", "/sys/", "/proc/", "/var/lib/containers/"],
    "cpu_sample_minutes": 10,
    "error_log_max_entries": 50,
    "error_log_hours": 24,
    "service_check_list": ["sshd", "crond"],
}

for key, value in settings.items():
    db.settings.update_one({"key": key}, {"$set": {"key": key, "value": value}}, upsert=True)
print(f"[OK] settings: {len(settings)} 筆")


# ============================================================
# 5. 使用者帳號 (users)
# ============================================================
users = [
    {"username": "admin", "display_name": "系統管理員", "role": "admin", "password": "admin"},
    {"username": "superadmin", "display_name": "超級管理員", "role": "superadmin", "password": "superadmin"},
    {"username": "operator", "display_name": "操作員", "role": "oper", "password": "operator"},
]

for u in users:
    pw_hash = bcrypt.hashpw(u["password"].encode(), bcrypt.gensalt()).decode()
    db.users.update_one(
        {"username": u["username"]},
        {"$set": {
            "username": u["username"],
            "password_hash": pw_hash,
            "display_name": u["display_name"],
            "role": u["role"],
            "must_change_password": False,
            "last_seen": None,
            "last_ip": None,
            "email": f"{u['username']}@company.com",
        }},
        upsert=True,
    )
print(f"[OK] users: {len(users)} 筆 (admin/superadmin/operator，密碼同帳號)")


# ============================================================
# 6. TWGCB 合規結果 (twgcb_results)
# ============================================================
twgcb_checks = [
    {"check_id": "PWD-001", "category": "密碼政策", "level": "L1", "title": "密碼最小長度", "expected": ">=12"},
    {"check_id": "PWD-002", "category": "密碼政策", "level": "L1", "title": "密碼複雜度", "expected": "minclass>=3"},
    {"check_id": "PWD-003", "category": "密碼政策", "level": "L1", "title": "密碼歷史記錄", "expected": "remember>=5"},
    {"check_id": "PWD-004", "category": "密碼政策", "level": "L2", "title": "密碼最大使用天數", "expected": "<=90"},
    {"check_id": "ACCT-001", "category": "帳號管理", "level": "L1", "title": "帳號鎖定閾值", "expected": "deny<=5"},
    {"check_id": "ACCT-002", "category": "帳號管理", "level": "L1", "title": "帳號鎖定時間", "expected": "unlock_time>=900"},
    {"check_id": "SSH-001", "category": "SSH 安全", "level": "L1", "title": "SSH Protocol", "expected": "2"},
    {"check_id": "SSH-002", "category": "SSH 安全", "level": "L1", "title": "PermitRootLogin", "expected": "no"},
    {"check_id": "SSH-003", "category": "SSH 安全", "level": "L2", "title": "MaxAuthTries", "expected": "<=4"},
    {"check_id": "SEL-001", "category": "SELinux", "level": "L2", "title": "SELinux 模式", "expected": "Enforcing"},
    {"check_id": "FW-001", "category": "防火牆", "level": "L1", "title": "firewalld 啟用", "expected": "active"},
    {"check_id": "AUD-001", "category": "稽核日誌", "level": "L1", "title": "auditd 啟用", "expected": "active"},
    {"check_id": "AUD-002", "category": "稽核日誌", "level": "L2", "title": "日誌保留天數", "expected": ">=90"},
    {"check_id": "FILE-001", "category": "檔案權限", "level": "L1", "title": "/etc/shadow 權限", "expected": "0000"},
    {"check_id": "NET-001", "category": "網路安全", "level": "L1", "title": "IP 轉發關閉", "expected": "0"},
    {"check_id": "NET-002", "category": "網路安全", "level": "L2", "title": "SYN Cookie", "expected": "1"},
]

for host in active_hosts:
    if host["os_group"] in ("rocky", "rhel", "debian"):
        checks = []
        for chk in twgcb_checks:
            result = random.choice(["pass", "pass", "pass", "fail", "na"])
            actual = chk["expected"] if result == "pass" else random.choice(["未設定", "不符合", "disabled", "8", "3"])
            checks.append({**chk, "actual": actual, "result": result})

        db.twgcb_results.update_one(
            {"hostname": host["hostname"]},
            {"$set": {
                "hostname": host["hostname"],
                "os": host["os"],
                "scan_time": now,
                "checks": checks,
                "imported_at": now,
            }},
            upsert=True,
        )
print(f"[OK] twgcb_results: {sum(1 for h in active_hosts if h['os_group'] in ('rocky','rhel','debian'))} 筆")


# ============================================================
# 7. HR 員工資料 (hr_users)
# ============================================================
hr_data = [
    {"ad_account": "dmwang", "name": "王大明", "emp_id": "E20210001", "department": "系統部", "title": "資深工程師", "email": "dmwang@company.com", "phone": "02-2345-6789"},
    {"ad_account": "xllee", "name": "李小龍", "emp_id": "E20210002", "department": "系統部", "title": "DBA", "email": "xllee@company.com", "phone": "02-2345-6790"},
    {"ad_account": "mllin", "name": "林美玲", "emp_id": "E20220001", "department": "開發部", "title": "工程師", "email": "mllin@company.com", "phone": "02-2345-6791"},
    {"ad_account": "lzhao", "name": "趙六", "emp_id": "E20220002", "department": "開發部", "title": "工程師", "email": "lzhao@company.com", "phone": "02-2345-6792"},
    {"ad_account": "qzhou", "name": "周七", "emp_id": "E20200001", "department": "網路部", "title": "主管", "email": "qzhou@company.com", "phone": "02-2345-6793"},
    {"ad_account": "bwu", "name": "吳八", "emp_id": "E20190001", "department": "系統部", "title": "工程師", "email": "bwu@company.com", "phone": "02-2345-6794"},
    {"ad_account": "resigned_user", "name": "已離職員工", "emp_id": "E20180001", "department": "前系統部", "title": "前工程師", "email": "resigned@company.com", "phone": ""},
]

for hr in hr_data:
    db.hr_users.update_one({"ad_account": hr["ad_account"]}, {"$set": hr}, upsert=True)
print(f"[OK] hr_users: {len(hr_data)} 筆")


# ============================================================
# 8. 管理操作日誌 (admin_worklog)
# ============================================================
worklogs = [
    {"username": "admin", "action": "login", "details": "管理員登入", "timestamp": now, "ip_address": "<ADMIN_HOST>"},
    {"username": "admin", "action": "backup_create", "details": "建立系統備份", "timestamp": now, "ip_address": "<ADMIN_HOST>"},
    {"username": "superadmin", "action": "login", "details": "超級管理員登入", "timestamp": now, "ip_address": "10.0.0.XX"},
]

for wl in worklogs:
    db.admin_worklog.insert_one(wl)
print(f"[OK] admin_worklog: {len(worklogs)} 筆")


# ============================================================
# 完成
# ============================================================
print()
print("=" * 60)
print("  種子資料產生完成！")
print("=" * 60)
print()
print("  測試帳號：")
print("    admin      / admin       (管理員)")
print("    superadmin / superadmin  (超級管理員)")
print("    operator   / operator    (操作員)")
print()
print(f"  主機數：    {len(hosts_data)} 台（{len(active_hosts)} 台使用中）")
print(f"  巡檢記錄： {inspection_count} 筆")
print(f"  過濾規則： {len(rules)} 筆")
print(f"  TWGCB：    {sum(1 for h in active_hosts if h['os_group'] in ('rocky','rhel','debian'))} 台")
print(f"  HR 員工：  {len(hr_data)} 筆")
print()
print("  啟動 Flask 後瀏覽 http://localhost:5000 即可看到資料")

client.close()
