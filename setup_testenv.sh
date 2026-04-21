#!/bin/bash
###############################################
#  IT Inspection System - 測試區首次設定
#  版本: v3.11.2.0-testenv
#
#  用途：部署 AI/ 到目標目錄、產生 config/env/vault、初始化 MongoDB
#
#  前置條件：
#    - 跑 verify_stack.py 已全綠（MongoDB + Python 套件 OK）
#    - 已 git clone / 下載 it-web-full 到 /home/sysinfra/lab/it-web-full-main
#
#  用法：
#    cd /home/sysinfra/lab/it-web-full-main
#    sudo ./setup_testenv.sh
###############################################
set -e

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"
CYAN="\033[0;36m"; BOLD="\033[1m"; NC="\033[0m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

step() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}\n"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }

clear
echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║   IT Inspection System - 測試區首次設定          ║"
echo "  ║   v3.11.2.0-testenv                              ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================
# Step 1: 前置檢查
# ============================================
step "前置檢查"

[ "$(id -u)" -ne 0 ] && fail "請用 root/sudo 執行"
ok "root 權限"

[ -d "$SCRIPT_DIR/AI" ] || fail "找不到 $SCRIPT_DIR/AI/（確認你在 it-web-full-main 目錄）"
ok "AI/ 目錄存在"

systemctl is-active mongod &>/dev/null || fail "mongod 沒跑，先執行 sudo systemctl start mongod"
ok "mongod 運行中"

command -v python3 &>/dev/null || fail "python3 沒裝"
python3 -c "import flask, pymongo, bcrypt" 2>/dev/null || fail "Python 套件缺（flask/pymongo/bcrypt），先跑 verify_stack.py"
ok "Python 套件就緒"

# ============================================
# Step 2: 引導式設定
# ============================================
step "引導式設定"

echo -e "  直接按 Enter 使用預設值。\n"

read -rp "  安裝目錄 [/opt/inspection]: " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-/opt/inspection}

read -rp "  MongoDB host [127.0.0.1]: " MONGO_HOST
MONGO_HOST=${MONGO_HOST:-127.0.0.1}

read -rp "  MongoDB port [27017]: " MONGO_PORT
MONGO_PORT=${MONGO_PORT:-27017}

read -rp "  Flask 監聽 port [5000]: " FLASK_PORT
FLASK_PORT=${FLASK_PORT:-5000}

# 管理員密碼
while true; do
    read -rsp "  superadmin 密碼（至少 8 碼）: " ADMIN_PW; echo
    [ ${#ADMIN_PW} -lt 8 ] && { warn "太短"; continue; }
    read -rsp "  再輸入一次: " ADMIN_PW2; echo
    [ "$ADMIN_PW" = "$ADMIN_PW2" ] && break || warn "不一致"
done
ok "密碼已設定"

read -rp "  SMTP server（直接 Enter 跳過 email 功能）: " SMTP_SERVER
if [ -n "$SMTP_SERVER" ]; then
    read -rp "  SMTP port [587]: " SMTP_PORT; SMTP_PORT=${SMTP_PORT:-587}
    read -rp "  SMTP user: " SMTP_USER
    read -rsp "  SMTP password: " SMTP_PASS; echo
fi

echo ""
echo -e "  ${BOLD}═══ 確認設定 ═══${NC}"
echo -e "  安裝目錄: ${CYAN}${INSTALL_DIR}${NC}"
echo -e "  MongoDB:  ${CYAN}${MONGO_HOST}:${MONGO_PORT}${NC}"
echo -e "  Flask:    ${CYAN}:${FLASK_PORT}${NC}"
echo -e "  SMTP:     ${CYAN}${SMTP_SERVER:-（跳過）}${NC}"
read -rp "  確認開始？(y/n) " ans
[[ ! "$ans" =~ ^[Yy]$ ]] && echo "取消" && exit 0

# ============================================
# Step 3: 產生 secrets
# ============================================
step "產生 secrets"

SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
VAULT_PASS=$(openssl rand -base64 24 2>/dev/null || python3 -c "import secrets; print(secrets.token_urlsafe(24))")

ok "Flask SECRET_KEY 已產生（64 hex）"
ok "Ansible vault 密碼已產生"

# ============================================
# Step 4: 部署 AI/ 到 INSTALL_DIR
# ============================================
step "部署程式碼"

if [ -d "$INSTALL_DIR" ]; then
    TS=$(date +%Y%m%d_%H%M%S)
    BAK="${INSTALL_DIR}.bak.${TS}"
    mv "$INSTALL_DIR" "$BAK"
    warn "舊目錄已備份到 $BAK"
fi

mkdir -p "$INSTALL_DIR"
cp -a "$SCRIPT_DIR/AI/." "$INSTALL_DIR/"
ok "程式碼複製到 $INSTALL_DIR"

# 建執行期目錄
mkdir -p "$INSTALL_DIR"/{logs,reports,data/reports,data/uploads,data/snapshots,data/audit_progress,data/linux_init_progress,data/linux_init_reports,data/security_audit_reports,data/notes,data/nmon,data/cache,.ssh}
chmod 700 "$INSTALL_DIR/.ssh"
ok "執行期目錄建立"

# ============================================
# Step 5: 寫 config.py / .env / .vault_pass
# ============================================
step "寫入設定檔"

# config.py
python3 << PYEOF
import re
path = "${INSTALL_DIR}/webapp/config.py"
with open(path, "r", encoding="utf-8") as f:
    c = f.read()
c = re.sub(r'INSPECTION_HOME\s*=\s*".*"', 'INSPECTION_HOME = "${INSTALL_DIR}"', c)
c = re.sub(r'SECRET_KEY\s*=\s*".*"', 'SECRET_KEY = "${SECRET_KEY}"', c)
c = re.sub(r'"host":\s*"[^"]*"', '"host": "${MONGO_HOST}"', c)
c = re.sub(r'"port":\s*\d+', '"port": ${MONGO_PORT}', c, count=1)
c = re.sub(r'FLASK_PORT\s*=\s*\d+', 'FLASK_PORT = ${FLASK_PORT}', c)
with open(path, "w", encoding="utf-8") as f:
    f.write(c)
print("  config.py 已更新")
PYEOF
chmod 600 "$INSTALL_DIR/webapp/config.py"
ok "config.py (chmod 600)"

# .env
cat > "$INSTALL_DIR/.env" <<ENVEOF
FLASK_SECRET_KEY=${SECRET_KEY}
FLASK_DEBUG=False
MONGO_HOST=${MONGO_HOST}
MONGO_PORT=${MONGO_PORT}
MONGO_DB=inspection
SMTP_SERVER=${SMTP_SERVER}
SMTP_PORT=${SMTP_PORT:-587}
SMTP_USER=${SMTP_USER}
SMTP_PASSWORD=${SMTP_PASS}
ENVEOF
chmod 600 "$INSTALL_DIR/.env"
ok ".env (chmod 600)"

# .vault_pass
echo "$VAULT_PASS" > "$INSTALL_DIR/.vault_pass"
chmod 600 "$INSTALL_DIR/.vault_pass"
ok ".vault_pass (chmod 600)"

# ============================================
# Step 6: 產生 Ansible SSH key
# ============================================
step "產生 Ansible SSH key"

KEY="$INSTALL_DIR/.ssh/ansible_svc_key"
if [ -f "$KEY" ]; then
    warn "SSH key 已存在，保留"
else
    ssh-keygen -t ed25519 -C "ansible_svc@$(hostname)" -f "$KEY" -N "" -q
    date -u +%Y-%m-%dT%H:%M:%SZ > "$INSTALL_DIR/.ssh/key_created_date"
    chmod 600 "$KEY"
    chmod 644 "${KEY}.pub"
    ok "新 key 已產生 → ${KEY}.pub"
fi

# ============================================
# Step 7: 初始化 MongoDB
# ============================================
step "初始化 MongoDB"

python3 << PYEOF
import sys, bcrypt, datetime
from pymongo import MongoClient

try:
    client = MongoClient("${MONGO_HOST}", ${MONGO_PORT}, serverSelectionTimeoutMS=3000)
    client.admin.command("ping")
    db = client["inspection"]

    # 建 superadmin
    if not db.users.find_one({"username": "superadmin"}):
        hashed = bcrypt.hashpw("${ADMIN_PW}".encode(), bcrypt.gensalt()).decode()
        db.users.insert_one({
            "username": "superadmin",
            "password": hashed,
            "role": "superadmin",
            "display_name": "超級管理員",
            "must_change_password": False,
            "created_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        })
        print("  ✓ superadmin 帳號已建立")
    else:
        print("  ✓ superadmin 已存在（跳過）")

    # 建索引
    db.hosts.create_index("hostname", unique=True)
    db.inspections.create_index([("hostname", 1), ("run_date", -1)])
    db.inspections.create_index("run_id")
    db.users.create_index("username", unique=True)
    print("  ✓ 索引建立完成")

except Exception as e:
    print(f"  ✗ 初始化失敗: {e}")
    sys.exit(1)
PYEOF

# ============================================
# Step 8: 建 systemd 服務
# ============================================
step "建立 systemd 服務"

cat > /etc/default/itagent <<ENVEOF
ITAGENT_HOME=${INSTALL_DIR}
ENVEOF

cat > /etc/systemd/system/itagent-web.service <<SVCEOF
[Unit]
Description=ITAgent Flask Web Application
After=mongod.service network.target
Wants=mongod.service

[Service]
Type=simple
User=root
EnvironmentFile=/etc/default/itagent
WorkingDirectory=${INSTALL_DIR}/webapp
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/webapp/app.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable itagent-web &>/dev/null
ok "itagent-web.service 已安裝並設為開機自啟"

# 安裝 itagent 管理工具
if [ -f "$INSTALL_DIR/itagent.sh" ]; then
    chmod +x "$INSTALL_DIR/itagent.sh"
    ln -sf "$INSTALL_DIR/itagent.sh" /usr/local/bin/itagent
    ok "itagent 指令已安裝到 /usr/local/bin/"
fi

# ============================================
# Step 9: 啟動 Flask 並驗證
# ============================================
step "啟動 Flask"

systemctl start itagent-web
sleep 3

HTTP_OK=false
for i in $(seq 1 10); do
    if curl -s -o /dev/null "http://127.0.0.1:${FLASK_PORT}/"; then
        HTTP_OK=true
        break
    fi
    sleep 1
done

if $HTTP_OK; then
    ok "Flask 已起，HTTP 200 (port ${FLASK_PORT})"
else
    warn "HTTP 還沒回應，檢查 journalctl -u itagent-web -n 30"
fi

# ============================================
# 完成
# ============================================
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo ""
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ 首次設定完成${NC}"
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo ""
echo -e "  管理網址:   ${CYAN}http://${IP}:${FLASK_PORT}/${NC}"
echo -e "  管理後台:   ${CYAN}http://${IP}:${FLASK_PORT}/admin${NC}"
echo -e "  登入帳號:   ${BOLD}superadmin${NC} / (你剛設的密碼)"
echo ""
echo -e "  服務管理:   ${BOLD}itagent status | start | stop | log${NC}"
echo -e "  安裝目錄:   ${INSTALL_DIR}"
echo -e "  Ansible key: ${INSTALL_DIR}/.ssh/ansible_svc_key.pub"
echo ""
echo -e "  ${BOLD}下一步：${NC}"
echo -e "  1. 登入後台 → 新增主機"
echo -e "  2. 把 Ansible 公鑰佈到目標主機的 ansible_svc 帳號"
echo -e "  3. 執行第一次巡檢"
echo ""
