#!/usr/bin/env python3
"""
IT 監控系統 — 資料庫初始化 (bootstrap)
用途: 空的 MongoDB 第一次部署時, 建帳號/索引/預設值

用法:
    cd /opt/inspection/webapp
    python3 ../scripts/bootstrap.py           # 互動式 (問預設密碼)
    python3 ../scripts/bootstrap.py --auto    # 全用預設值 (密碼=changeme123)
    python3 ../scripts/bootstrap.py --reset   # 清空所有資料重建 (危險!)
"""
import os
import sys
import argparse
from datetime import datetime

# 使 script 從任何目錄都能找到 webapp 模組
_here = os.path.dirname(os.path.abspath(__file__))
_webapp = os.path.join(_here, "..", "webapp")
if os.path.isdir(_webapp):
    sys.path.insert(0, _webapp)

try:
    from werkzeug.security import generate_password_hash
    from pymongo import MongoClient
except ImportError as e:
    print(f"缺套件: {e}")
    print("請先: pip install flask pymongo")
    sys.exit(1)


MONGO_HOST = os.environ.get("MONGO_HOST", "127.0.0.1")
MONGO_PORT = int(os.environ.get("MONGO_PORT", "27017"))
DB_NAME = os.environ.get("DB_NAME", "inspection")


def hash_password(password):
    return generate_password_hash(password)


def seed_users(db, default_password):
    col = db["users"]
    if col.count_documents({}) > 0:
        print(f"  users: 已有 {col.count_documents({})} 筆, 跳過")
        return
    users = [
        {"username": "superadmin", "password_hash": hash_password(default_password),
         "role": "superadmin", "display_name": "Super Admin",
         "must_change_password": True, "created_at": datetime.now().isoformat()},
        {"username": "admin", "password_hash": hash_password(default_password),
         "role": "admin", "display_name": "系統管理員",
         "must_change_password": True, "created_at": datetime.now().isoformat()},
        {"username": "oper", "password_hash": hash_password(default_password),
         "role": "oper", "display_name": "訪客 (唯讀)",
         "must_change_password": True, "created_at": datetime.now().isoformat()},
    ]
    col.insert_many(users)
    col.create_index("username", unique=True)
    print(f"  users: 建 3 個帳號 (superadmin/admin/oper, 密碼={default_password})")


def seed_feature_flags(db):
    col = db["feature_flags"]
    col.create_index("key", unique=True)
    defaults = [
        {"key": "audit",          "name": "帳號盤點",     "description": "/audit 頁 + admin 帳號盤點 tab", "enabled": True},
        {"key": "packages",       "name": "軟體盤點",     "description": "/packages 頁 + Ansible 套件收集", "enabled": True},
        {"key": "perf",           "name": "效能月報",     "description": "/perf 頁 + nmon 採樣", "enabled": True},
        {"key": "twgcb",          "name": "TWGCB 合規",   "description": "/twgcb 系列頁 + 合規報告", "enabled": True},
        {"key": "summary",        "name": "異常總結",     "description": "/summary 頁", "enabled": True},
        {"key": "security_audit", "name": "系統安全稽核", "description": "admin 稽核專區", "enabled": True},
    ]
    added = 0
    for f in defaults:
        if not col.find_one({"key": f["key"]}):
            col.insert_one(f)
            added += 1
    print(f"  feature_flags: {added} 新增 / {len(defaults) - added} 已存在")


def seed_settings(db):
    col = db["settings"]
    col.create_index("key", unique=True)
    defaults = [
        {"key": "nmon_interval_min", "value": 5, "updated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")},
        {"key": "system_name", "value": "IT 監控系統", "updated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")},
        {"key": "report_company", "value": "", "updated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")},
    ]
    added = 0
    for s in defaults:
        if not col.find_one({"key": s["key"]}):
            col.insert_one(s)
            added += 1
    print(f"  settings: {added} 新增 / {len(defaults) - added} 已存在")


def _detect_local_os():
    """從 /etc/os-release 偵測系統"""
    os_name = "Linux"
    os_group = "linux"
    try:
        with open("/etc/os-release", encoding="utf-8") as f:
            info = {}
            for line in f:
                if "=" in line:
                    k, v = line.strip().split("=", 1)
                    info[k] = v.strip('"')
        os_name = info.get("PRETTY_NAME", "Linux")
        os_id = info.get("ID", "linux").lower()
        if os_id in ("rocky", "rhel", "centos", "fedora"):
            os_group = "rocky"
        elif os_id in ("debian", "ubuntu"):
            os_group = os_id
    except Exception:
        pass
    return os_name, os_group


def _sync_hosts_config_json(db):
    """寫出 /opt/inspection/data/hosts_config.json"""
    import json
    hosts = list(db["hosts"].find({}, {"_id": 0}))
    inspection_home = os.environ.get("INSPECTION_HOME", "/opt/inspection")
    config_path = os.path.join(inspection_home, "data/hosts_config.json")
    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump({"hosts": hosts}, f, indent=2, ensure_ascii=False, default=str)
    print(f"  hosts_config.json: 已同步 ({len(hosts)} 台) → {config_path}")


def _regen_inventory():
    """呼叫 scripts/generate_inventory.py 重建 ansible inventory"""
    import subprocess
    inspection_home = os.environ.get("INSPECTION_HOME", "/opt/inspection")
    script = os.path.join(inspection_home, "scripts/generate_inventory.py")
    if not os.path.exists(script):
        print(f"  inventory: 跳過（找不到 {script}）")
        return
    try:
        r = subprocess.run(["python3", script], capture_output=True, text=True, timeout=30)
        if r.returncode == 0:
            print(f"  inventory: 重建完成")
        else:
            print(f"  inventory: 重建失敗 - {r.stderr[:200]}")
    except Exception as e:
        print(f"  inventory: 重建異常 - {e}")


def seed_hosts(db):
    import socket
    col = db["hosts"]
    col.create_index("hostname", unique=True)
    if col.count_documents({}) > 0:
        print(f"  hosts: 已有 {col.count_documents({})} 筆, 跳過 (如要重建請用 --reset)")
        # 即使不 seed 也確保 sync + inventory（解決舊裝環境沒 json 的情況）
        _sync_hosts_config_json(db)
        _regen_inventory()
        return
    hostname = socket.gethostname() or "ansible-host"
    os_name, os_group = _detect_local_os()
    self_host = {
        "hostname": hostname,
        "ip": "127.0.0.1",
        "os": os_name,
        "os_group": os_group,
        "status": "使用中",
        "connection": "local",
        "system_name": "",
        "tier": "",
        "ap_owner": "",
        "department": "",
        "note": "ansible 控制節點本機（bootstrap 自動建立）",
        "imported_at": datetime.now().isoformat(),
        "updated_at": datetime.now().isoformat(),
    }
    col.insert_one(self_host)
    print(f"  hosts: 建 1 台本機主機 {hostname} (127.0.0.1, ansible_connection=local)")
    _sync_hosts_config_json(db)
    _regen_inventory()


def create_indexes(db):
    """建立全部 collection 索引 (依現有 code 實際用到的欄位)"""
    index_map = {
        "twgcb_results": [("hostname", 1)],
        "twgcb_config": [("check_id", 1)],
        "twgcb_exceptions": [("hostname", 1), ("check_id", 1)],
        "twgcb_fix_status": [("hostname", 1)],
        "twgcb_daily_stats": [("date", 1)],  # unique
        "inspections": [("hostname", 1), ("created_at", -1)],
        "account_audit": [("hostname", 1), ("username", 1)],
        "host_packages": [("hostname", 1)],       # unique
        "host_packages_changes": [("changed_at", -1)],
        "nmon_daily": [("hostname", 1), ("date", 1)],  # unique
        "admin_worklog": [("timestamp", -1)],
        "login_attempts": [("username", 1)],
        "cache": [("_id", 1)],
        "fix_locks": [("_id", 1)],
    }
    unique_indexes = {
        ("twgcb_daily_stats", "date"),
        ("host_packages", "hostname"),
        ("nmon_daily", "hostname+date"),
    }
    for col_name, idx in index_map.items():
        db[col_name].create_index(idx)
    # unique
    db["twgcb_daily_stats"].create_index("date", unique=True)
    db["host_packages"].create_index("hostname", unique=True)
    db["nmon_daily"].create_index([("hostname", 1), ("date", 1)], unique=True)
    print(f"  indexes: 建 {len(index_map)} 個 collection 的索引 (3 unique)")


def reset_all(db):
    print("⚠️  --reset 會清空所有 collection, 10 秒後開始...")
    import time
    for i in range(10, 0, -1):
        sys.stdout.write(f"\r  倒數 {i} 秒 (Ctrl+C 取消) ")
        sys.stdout.flush()
        time.sleep(1)
    print()
    for name in db.list_collection_names():
        db.drop_collection(name)
        print(f"  drop: {name}")


def main():
    p = argparse.ArgumentParser(description="IT 監控系統 DB bootstrap")
    p.add_argument("--auto", action="store_true", help="不問, 用預設密碼 changeme123")
    p.add_argument("--password", default=None, help="預設帳號密碼")
    p.add_argument("--reset", action="store_true", help="清空所有資料 (危險)")
    args = p.parse_args()

    print(f"連線: mongodb://{MONGO_HOST}:{MONGO_PORT}/{DB_NAME}")
    client = MongoClient(MONGO_HOST, MONGO_PORT, serverSelectionTimeoutMS=5000)
    try:
        client.admin.command("ping")
    except Exception as e:
        print(f"❌ MongoDB 連不到: {e}")
        print("確認: systemctl status mongod (或 podman ps | grep mongodb)")
        sys.exit(2)
    db = client[DB_NAME]

    if args.reset:
        confirm = input("真的要清空? 輸入 YES 繼續: ") if not args.auto else "YES"
        if confirm != "YES":
            print("已取消")
            sys.exit(0)
        reset_all(db)

    # 取預設密碼
    if args.password:
        default_pw = args.password
    elif args.auto:
        default_pw = "changeme123"
    else:
        default_pw = input("預設帳號密碼 [changeme123]: ").strip() or "changeme123"

    if len(default_pw) < 8:
        print("⚠️  密碼太短 (<8 字元)")
        sys.exit(3)

    print()
    print("初始化中...")
    seed_users(db, default_pw)
    seed_feature_flags(db)
    seed_settings(db)
    seed_hosts(db)
    create_indexes(db)

    print()
    print("✓ bootstrap 完成")
    print()
    print(f"登入網址: http://{MONGO_HOST}:5000/login")
    print(f"帳號: superadmin / admin / oper")
    print(f"密碼: {default_pw} (首次登入會強制改)")
    print()
    print("下一步:")
    print("  1. systemctl start itagent-web (或 cd webapp && python3 app.py)")
    print("  2. 開網站, 用 superadmin 登入改密碼")
    print("  3. 系統管理 → 主機管理 匯入真正的 hosts CSV")
    print("  4. 執行第一次巡檢驗證")


if __name__ == "__main__":
    main()
