#!/usr/bin/env python3
"""
IT Inspection System - 架構驗證工具
驗證 Flask + MongoDB + Ansible + 常用模組 是否全部可用。

用法：
    python3 verify_stack.py          # 只做環境檢查
    python3 verify_stack.py --serve  # 跑一個最小 Flask 在 :5000
"""
import sys
import subprocess
import os
import importlib

GREEN, RED, YELLOW, CYAN, NC = "\033[32m", "\033[31m", "\033[33m", "\033[36m", "\033[0m"


def ok(msg):   print(f"  {GREEN}OK{NC}    {msg}")
def bad(msg):  print(f"  {RED}FAIL{NC}  {msg}")
def warn(msg): print(f"  {YELLOW}WARN{NC}  {msg}")
def step(msg): print(f"\n{CYAN}=== {msg} ==={NC}")


failures = 0


def check_import(name, attr=None):
    global failures
    try:
        mod = importlib.import_module(name)
        version = getattr(mod, "__version__", "?")
        ok(f"{name} ({version})")
        return mod
    except ImportError as e:
        bad(f"{name} - import 失敗: {e}")
        failures += 1
        return None


def check_command(cmd, args=None):
    global failures
    try:
        result = subprocess.run(
            [cmd] + (args or ["--version"]),
            capture_output=True, text=True, timeout=5,
        )
        first = result.stdout.splitlines()[0] if result.stdout else result.stderr.splitlines()[0]
        ok(f"{cmd}: {first[:70]}")
        return True
    except FileNotFoundError:
        bad(f"{cmd} - 找不到指令")
        failures += 1
        return False
    except Exception as e:
        warn(f"{cmd} - {e}")
        return False


# ============================================
# Step 1: Python 模組
# ============================================
step("Python 模組")
check_import("flask")
check_import("pymongo")
check_import("bcrypt")
check_import("gunicorn")
check_import("jinja2")
check_import("werkzeug")
check_import("ldap")         # 來自 python3-ldap RPM
check_import("pywinrm")
check_import("requests")
check_import("cryptography")
check_import("dns")          # dnspython
# pysnmp 被跳過，不檢查

# ============================================
# Step 2: 指令列工具
# ============================================
step("指令列工具")
check_command("python3")
check_command("pip3")
check_command("ansible")
check_command("git")
check_command("mongosh", ["--version"])
check_command("mongod", ["--version"])
check_command("systemctl", ["--version"])

# ============================================
# Step 3: MongoDB 連線
# ============================================
step("MongoDB 連線")
try:
    from pymongo import MongoClient
    client = MongoClient("mongodb://127.0.0.1:27017/", serverSelectionTimeoutMS=3000)
    ping = client.admin.command("ping")
    if ping.get("ok") == 1.0:
        ok(f"MongoDB ping OK  ({client.server_info().get('version')})")
    else:
        bad(f"MongoDB ping 回傳異常: {ping}")
        failures += 1

    # 試寫入/讀出
    db = client["inspection_verify"]
    db.test.insert_one({"hello": "world"})
    count = db.test.count_documents({})
    ok(f"MongoDB 寫入/讀取 OK (測試集合 count={count})")
    client.drop_database("inspection_verify")
    ok("測試集合已清除")
except Exception as e:
    bad(f"MongoDB 連線失敗: {e}")
    failures += 1

# ============================================
# Step 4: Ansible 快速測試
# ============================================
step("Ansible 本機連線")
try:
    result = subprocess.run(
        ["ansible", "localhost", "-m", "ping", "-c", "local"],
        capture_output=True, text=True, timeout=10,
    )
    if "SUCCESS" in result.stdout and '"ping": "pong"' in result.stdout:
        ok("ansible localhost ping → pong")
    else:
        bad(f"ansible ping 失敗:\n{result.stdout}\n{result.stderr}")
        failures += 1
except Exception as e:
    bad(f"ansible 執行失敗: {e}")
    failures += 1

# ============================================
# 總結
# ============================================
print()
if failures == 0:
    print(f"{GREEN}  ════════════════════════════════════")
    print(f"  ✓ 架構驗證全部通過（0 失敗）")
    print(f"  ════════════════════════════════════{NC}")
else:
    print(f"{RED}  ════════════════════════════════════")
    print(f"  ✗ 架構驗證有 {failures} 個失敗")
    print(f"  ════════════════════════════════════{NC}")
    sys.exit(1)

# ============================================
# 可選：啟一個最小 Flask
# ============================================
if "--serve" in sys.argv:
    step("啟動最小 Flask 在 :5000")
    from flask import Flask, jsonify
    from pymongo import MongoClient

    app = Flask(__name__)

    @app.route("/")
    def index():
        return jsonify({
            "status": "ok",
            "message": "IT Inspection System - skeleton alive",
            "stack": ["flask", "pymongo", "ansible"]
        })

    @app.route("/health")
    def health():
        try:
            MongoClient(serverSelectionTimeoutMS=2000).admin.command("ping")
            mongo = "ok"
        except Exception as e:
            mongo = f"fail: {e}"
        return jsonify({"mongo": mongo, "flask": "ok"})

    print(f"{CYAN}  網址: http://<本機 IP>:5000/      health: http://.../health{NC}")
    print(f"  按 Ctrl+C 結束")
    app.run(host="0.0.0.0", port=5000, debug=False)
