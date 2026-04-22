#!/bin/bash
# v3.11.4.0 patch 後安裝腳本
# 已部署系統自動修復：seed self + sync hosts_config.json + chown data/ + regen inventory
set -u

R="\033[0;31m"; G="\033[0;32m"; Y="\033[1;33m"; C="\033[0;36m"; N="\033[0m"
ok()   { echo -e "    ${G}OK${N} $1"; }
warn() { echo -e "    ${Y}WARN${N} $1"; }
info() { echo -e "    ${C}-->${N} $1"; }

ITAGENT_HOME="${ITAGENT_HOME:-/opt/inspection}"
FLASK_USER="${FLASK_USER:-sysinfra}"

echo -e "${C}--- v3.11.4.0 post_install ---${N}"

# Step 1: Python 做 seed + sync + regen
INSPECTION_HOME="$ITAGENT_HOME" python3 - <<'PYEOF'
import sys, os, json, socket, subprocess
from datetime import datetime

INSPECTION_HOME = os.environ["INSPECTION_HOME"]
sys.path.insert(0, os.path.join(INSPECTION_HOME, "webapp"))

try:
    from pymongo import MongoClient
except ImportError:
    print("    [FAIL] pymongo 沒裝，跳過 DB 修復")
    sys.exit(0)

try:
    db = MongoClient("127.0.0.1", 27017, serverSelectionTimeoutMS=3000)["inspection"]
    db.command("ping")
except Exception as e:
    print(f"    [FAIL] MongoDB 連不到: {e}")
    sys.exit(0)

col = db["hosts"]

# 1) 如 hosts 為空 → seed self
if col.count_documents({}) == 0:
    hostname = socket.gethostname() or "ansible-host"
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
        "note": "ansible 控制節點本機（v3.11.4.0 patch 自動建立）",
        "imported_at": datetime.now().isoformat(),
        "updated_at": datetime.now().isoformat(),
    }
    col.insert_one(self_host)
    print(f"    [SEED] 建立本機主機: {hostname} (127.0.0.1, connection=local)")
else:
    print(f"    [SKIP] hosts 已有 {col.count_documents({})} 筆, 不 seed")

# 2) 強制重建 hosts_config.json
hosts = list(col.find({}, {"_id": 0}))
config_path = os.path.join(INSPECTION_HOME, "data/hosts_config.json")
os.makedirs(os.path.dirname(config_path), exist_ok=True)
with open(config_path, "w", encoding="utf-8") as f:
    json.dump({"hosts": hosts}, f, indent=2, ensure_ascii=False, default=str)
print(f"    [SYNC] hosts_config.json 產生 ({len(hosts)} 台)")

# 3) 重建 inventory
gen_script = os.path.join(INSPECTION_HOME, "scripts/generate_inventory.py")
if os.path.exists(gen_script):
    r = subprocess.run(["python3", gen_script], capture_output=True, text=True, timeout=30)
    if r.returncode == 0:
        print(f"    [INV] inventory 重建成功")
    else:
        print(f"    [INV] 重建失敗: {r.stderr.strip()[:200]}")
else:
    print(f"    [INV] 跳過（找不到 {gen_script}）")
PYEOF

# Step 2: 修 data/ 目錄 owner（讓 Flask 跑的 user 寫得進去）
if id "$FLASK_USER" >/dev/null 2>&1; then
    chown -R "${FLASK_USER}:${FLASK_USER}" "${ITAGENT_HOME}/data" 2>/dev/null && \
        ok "data/ 目錄 owner 設為 ${FLASK_USER}" || \
        warn "chown 失敗（非 root 執行？）"
else
    info "使用者 ${FLASK_USER} 不存在，跳過 chown（若 Flask 服務有讀寫異常請手動修正）"
fi

echo -e "${G}post_install 完成${N}"
