#!/bin/bash
###############################################
#  IT Inspection System - 一鍵離線安裝
#  版本: v3.11.2.0-testenv
#
#  前置：
#    - RHEL 9 / Rocky Linux 9 / CentOS 9
#    - root 權限
#    - 已 git clone 完整 repo（含 AI/rpms/、AI/whls/）
#
#  用法：
#    cd <repo_root>
#    sudo ./setup_testenv.sh
#
#  會做什麼（全部自動）：
#    1. 環境檢查
#    2. 引導設定（路徑/port/密碼）
#    3. 裝 MongoDB 8 RPM（從 AI/rpms/）
#    4. 裝 Python 套件（從 AI/whls/ 離線）
#    5. 裝 python3-ldap（dnf from Satellite）
#    6. 部署 AI/ → INSTALL_DIR
#    7. 產生 SECRET_KEY、.env、.vault_pass
#    8. 自動 ssh-keygen ansible key
#    9. 初始化 MongoDB（superadmin + indexes）
#   10. 建 systemd 服務並啟動
#   11. 驗證 HTTP 200
###############################################
set -e

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"
CYAN="\033[0;36m"; BOLD="\033[1m"; NC="\033[0m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="3.11.2.0-testenv"
STEP=0; TOTAL=11

step() { STEP=$((STEP+1)); echo -e "\n${CYAN}━━━ 步驟 ${STEP}/${TOTAL}：$1 ━━━${NC}\n"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }

clear
echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║   IT Inspection System - 一鍵離線安裝            ║"
echo "  ║   v${VERSION}                             ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================
# Step 1: 環境檢查
# ============================================
step "環境檢查"

[ "$(id -u)" -ne 0 ] && fail "請用 root/sudo 執行"
ok "root 權限"

. /etc/os-release 2>/dev/null
ok "系統: ${PRETTY_NAME:-Unknown}"
if ! echo "$ID $ID_LIKE" | grep -qiE "rhel|centos|rocky|fedora|almalinux"; then
    warn "非 RHEL 系列，RPM 安裝可能不相容"
    read -rp "  繼續？(y/n) " a; [[ ! "$a" =~ ^[Yy]$ ]] && exit 1
fi

[ -d "$SCRIPT_DIR/AI" ] || fail "找不到 $SCRIPT_DIR/AI/"

# 依賴包從 GitHub Release 下載或手動放置
DEPS_TARBALL="inspection_offline_deps_v${VERSION%-*}.0.tar.gz"
DEPS_URL="https://github.com/alienid4/it-web-full/releases/download/v${VERSION%-*}.0/${DEPS_TARBALL}"

if [ ! -d "$SCRIPT_DIR/AI/rpms" ] || [ ! -d "$SCRIPT_DIR/AI/whls" ]; then
    echo ""
    echo -e "  ${YELLOW}未發現 AI/rpms/ 和 AI/whls/ — 從 Release 取得依賴包${NC}"

    if [ -f "$SCRIPT_DIR/${DEPS_TARBALL}" ]; then
        ok "找到 ${DEPS_TARBALL}（$(du -h "$SCRIPT_DIR/${DEPS_TARBALL}" | cut -f1)）"
    elif [ -f "/tmp/${DEPS_TARBALL}" ]; then
        ln -sf "/tmp/${DEPS_TARBALL}" "$SCRIPT_DIR/${DEPS_TARBALL}"
        ok "用 /tmp/${DEPS_TARBALL}"
    else
        echo -e "  試著從 GitHub Release 下載..."
        if curl -fL --progress-bar -o "$SCRIPT_DIR/${DEPS_TARBALL}" "$DEPS_URL" 2>&1; then
            ok "下載完成"
        else
            fail "下載失敗。請手動下載後放到 $SCRIPT_DIR/：
    $DEPS_URL
  或用 Win10 下載後 FTP 到測試機 $SCRIPT_DIR/${DEPS_TARBALL}"
        fi
    fi

    echo -e "  解壓中..."
    tar -xzf "$SCRIPT_DIR/${DEPS_TARBALL}" -C "$SCRIPT_DIR/AI/" || fail "解壓失敗"
    ok "rpms/ + whls/ 已解到 $SCRIPT_DIR/AI/"
fi

[ -d "$SCRIPT_DIR/AI/rpms" ] || fail "AI/rpms/ 仍不存在"
[ -d "$SCRIPT_DIR/AI/whls" ] || fail "AI/whls/ 仍不存在"
ok "AI/rpms/ ($(ls $SCRIPT_DIR/AI/rpms/*.rpm 2>/dev/null | wc -l) RPM)"
ok "AI/whls/ ($(ls $SCRIPT_DIR/AI/whls/*.whl 2>/dev/null | wc -l) wheel)"

command -v python3 &>/dev/null || fail "python3 沒裝"
ok "python3 $(python3 -V 2>&1 | awk '{print $2}')"

# ============================================
# Step 2: 引導設定
# ============================================
step "引導設定"

echo -e "  直接按 Enter 使用預設值。\n"

read -rp "  安裝目錄 [/opt/inspection]: " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-/opt/inspection}
INSTALL_DIR=${INSTALL_DIR%/}

read -rp "  MongoDB host (本機用 127.0.0.1) [127.0.0.1]: " MONGO_HOST
MONGO_HOST=${MONGO_HOST:-127.0.0.1}

read -rp "  MongoDB port [27017]: " MONGO_PORT
MONGO_PORT=${MONGO_PORT:-27017}

read -rp "  Flask 監聽 port [5000]: " FLASK_PORT
FLASK_PORT=${FLASK_PORT:-5000}

while true; do
    read -rsp "  superadmin 密碼（至少 8 碼）: " ADMIN_PW; echo
    [ ${#ADMIN_PW} -lt 8 ] && { warn "太短"; continue; }
    read -rsp "  再輸入一次: " ADMIN_PW2; echo
    [ "$ADMIN_PW" = "$ADMIN_PW2" ] && break || warn "不一致"
done
ok "密碼已設定"

read -rp "  SMTP server（Enter 跳過 email 功能）: " SMTP_SERVER
if [ -n "$SMTP_SERVER" ]; then
    read -rp "  SMTP port [587]: " SMTP_PORT; SMTP_PORT=${SMTP_PORT:-587}
    read -rp "  SMTP user: " SMTP_USER
    read -rsp "  SMTP password: " SMTP_PASS; echo
fi

echo ""
echo -e "  ${BOLD}═══ 確認 ═══${NC}"
echo -e "  安裝目錄: ${CYAN}${INSTALL_DIR}${NC}"
echo -e "  MongoDB:  ${CYAN}${MONGO_HOST}:${MONGO_PORT}${NC}"
echo -e "  Flask:    ${CYAN}:${FLASK_PORT}${NC}"
echo -e "  SMTP:     ${CYAN}${SMTP_SERVER:-（跳過）}${NC}"
read -rp "  開始？(y/n) " a; [[ ! "$a" =~ ^[Yy]$ ]] && exit 0

# ============================================
# Step 3: 裝 MongoDB RPM（離線）
# ============================================
step "安裝 MongoDB RPM（離線）"

if systemctl is-active mongod &>/dev/null; then
    ok "mongod 已在跑（跳過安裝）"
else
    rpm -Uvh --force --nodeps "$SCRIPT_DIR/AI/rpms/"*.rpm 2>&1 | grep -iE "error|preparing|installing|warning" | head -15 || true
    mkdir -p /var/lib/mongo /var/log/mongodb
    chown -R mongod:mongod /var/lib/mongo /var/log/mongodb 2>/dev/null || true
    systemctl enable --now mongod

    sleep 3
    if systemctl is-active mongod &>/dev/null; then
        ok "mongod 已啟動"
    else
        fail "mongod 啟動失敗，檢查 journalctl -u mongod -n 30"
    fi
fi

# ============================================
# Step 4: 裝 python3-ldap（Satellite dnf）
# ============================================
step "安裝 python3-ldap"

if python3 -c "import ldap" 2>/dev/null; then
    ok "python3-ldap 已裝"
else
    if dnf install -y python3-ldap 2>&1 | tail -5; then
        python3 -c "import ldap" 2>/dev/null && ok "python3-ldap 裝好"
    else
        warn "python3-ldap dnf 失敗（Satellite 沒此套件？），LDAP 功能將不可用"
    fi
fi

# ============================================
# Step 5: 裝 Python 套件（離線，從 AI/whls/）
# ============================================
step "安裝 Python 套件（離線）"

pip3 install --no-index --find-links="$SCRIPT_DIR/AI/whls/" \
    flask pymongo bcrypt gunicorn jinja2 werkzeug blinker click itsdangerous markupsafe \
    pywinrm requests xmltodict requests-ntlm pyspnego cryptography cffi pycparser \
    dnspython matplotlib numpy pillow fonttools contourpy kiwisolver cycler pyparsing \
    python-dateutil six reportlab openpyxl et_xmlfile \
    pysnmp pysmi ply pyasn1 \
    charset-normalizer idna urllib3 certifi typing-extensions importlib-metadata zipp packaging \
    2>&1 | tail -5

# 驗證關鍵套件
MISSING=""
for pkg in flask pymongo bcrypt jinja2 werkzeug ldap winrm dns matplotlib numpy; do
    python3 -c "import $pkg" 2>/dev/null || MISSING="$MISSING $pkg"
done
if [ -z "$MISSING" ]; then
    ok "所有 Python 套件就緒"
else
    fail "缺少套件:$MISSING"
fi

# ============================================
# Step 6: 部署程式碼
# ============================================
step "部署程式碼"

if [ -d "$INSTALL_DIR" ]; then
    TS=$(date +%Y%m%d_%H%M%S)
    mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.${TS}"
    warn "舊目錄備份到 ${INSTALL_DIR}.bak.${TS}"
fi

mkdir -p "$INSTALL_DIR"
# 複製 AI/ 內容（排除 whls 和 rpms，那些只用於安裝）
rsync -a --exclude='whls' --exclude='rpms' "$SCRIPT_DIR/AI/." "$INSTALL_DIR/" 2>/dev/null || \
    (cd "$SCRIPT_DIR/AI" && tar cf - --exclude=whls --exclude=rpms .) | tar xf - -C "$INSTALL_DIR/"

ok "程式碼部署到 $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"/{logs,reports,data/reports,data/uploads,data/snapshots,data/audit_progress,data/linux_init_progress,data/linux_init_reports,data/security_audit_reports,data/notes,data/nmon,data/cache,.ssh}
chmod 700 "$INSTALL_DIR/.ssh"
ok "執行期目錄建立"

# ============================================
# Step 7: 寫 config.py / .env / .vault_pass
# ============================================
step "寫入設定檔"

SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
VAULT_PASS=$(openssl rand -base64 24 2>/dev/null || python3 -c "import secrets; print(secrets.token_urlsafe(24))")

CONFIG_PY="$INSTALL_DIR/webapp/config.py"
CONFIG_EX="$INSTALL_DIR/webapp/config.py.example"
[ ! -f "$CONFIG_PY" ] && [ -f "$CONFIG_EX" ] && cp "$CONFIG_EX" "$CONFIG_PY"
[ -f "$CONFIG_PY" ] || fail "config.py 不存在"

python3 <<PYEOF
import re
path = "${CONFIG_PY}"
with open(path, "r", encoding="utf-8") as f: c = f.read()
c = re.sub(r'INSPECTION_HOME\s*=\s*".*"', 'INSPECTION_HOME = "${INSTALL_DIR}"', c)
c = re.sub(r'SECRET_KEY\s*=\s*".*"', 'SECRET_KEY = "${SECRET_KEY}"', c)
c = re.sub(r'"host":\s*"[^"]*"', '"host": "${MONGO_HOST}"', c, count=1)
c = re.sub(r'"port":\s*\d+', '"port": ${MONGO_PORT}', c, count=1)
c = re.sub(r'FLASK_PORT\s*=\s*\d+', 'FLASK_PORT = ${FLASK_PORT}', c)
with open(path, "w", encoding="utf-8") as f: f.write(c)
PYEOF
chmod 600 "$CONFIG_PY"
ok "config.py (chmod 600)"

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

echo "$VAULT_PASS" > "$INSTALL_DIR/.vault_pass"
chmod 600 "$INSTALL_DIR/.vault_pass"
ok ".vault_pass (chmod 600)"

# ============================================
# Step 8: Ansible SSH key
# ============================================
step "產生 Ansible SSH key"

KEY="$INSTALL_DIR/.ssh/ansible_svc_key"
if [ -f "$KEY" ]; then
    ok "SSH key 已存在（保留）"
else
    ssh-keygen -t ed25519 -C "ansible_svc@$(hostname)" -f "$KEY" -N "" -q
    date -u +%Y-%m-%dT%H:%M:%SZ > "$INSTALL_DIR/.ssh/key_created_date"
    chmod 600 "$KEY"; chmod 644 "${KEY}.pub"
    ok "新 key: ${KEY}.pub"
fi

# ============================================
# Step 9: 初始化 MongoDB
# ============================================
step "初始化 MongoDB"

python3 <<PYEOF
import sys, bcrypt, datetime
from pymongo import MongoClient
try:
    client = MongoClient("${MONGO_HOST}", ${MONGO_PORT}, serverSelectionTimeoutMS=5000)
    client.admin.command("ping")
    db = client["inspection"]
    if not db.users.find_one({"username": "superadmin"}):
        hashed = bcrypt.hashpw("${ADMIN_PW}".encode(), bcrypt.gensalt()).decode()
        db.users.insert_one({
            "username": "superadmin", "password": hashed, "role": "superadmin",
            "display_name": "超級管理員", "must_change_password": False,
            "created_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        })
        print("  ✓ superadmin 建立")
    else:
        print("  ✓ superadmin 已存在")
    db.hosts.create_index("hostname", unique=True)
    db.inspections.create_index([("hostname", 1), ("run_date", -1)])
    db.inspections.create_index("run_id")
    db.users.create_index("username", unique=True)
    print("  ✓ indexes OK")
except Exception as e:
    print(f"  ✗ {e}"); sys.exit(1)
PYEOF

# ============================================
# Step 10: Systemd 服務
# ============================================
step "建 systemd 服務"

cat > /etc/default/itagent <<E
ITAGENT_HOME=${INSTALL_DIR}
E

cat > /etc/systemd/system/itagent-web.service <<E
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
E

systemctl daemon-reload
systemctl enable itagent-web &>/dev/null
ok "itagent-web.service 已裝"

[ -f "$INSTALL_DIR/itagent.sh" ] && {
    chmod +x "$INSTALL_DIR/itagent.sh"
    ln -sf "$INSTALL_DIR/itagent.sh" /usr/local/bin/itagent
    ok "itagent 指令已裝"
}

# 防火牆
if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
    firewall-cmd --add-port=${FLASK_PORT}/tcp --permanent &>/dev/null
    firewall-cmd --reload &>/dev/null
    ok "防火牆已開 ${FLASK_PORT}"
fi

# ============================================
# Step 11: 啟動 + 驗證
# ============================================
step "啟動 Flask 並驗證"

systemctl restart itagent-web
sleep 3

HTTP_OK=false
for i in $(seq 1 15); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${FLASK_PORT}/" 2>/dev/null || echo 000)
    if [[ "$code" =~ ^(200|301|302)$ ]]; then
        ok "HTTP $code OK (port ${FLASK_PORT})"
        HTTP_OK=true
        break
    fi
    sleep 1
done
$HTTP_OK || warn "HTTP 未回應，查 journalctl -u itagent-web -n 40"

# ============================================
# 完成
# ============================================
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo ""
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ 一鍵安裝完成！v${VERSION}${NC}"
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo ""
echo -e "  管理網址: ${CYAN}http://${IP}:${FLASK_PORT}/admin${NC}"
echo -e "  帳號: ${BOLD}superadmin${NC} / (你剛設的密碼)"
echo -e "  安裝目錄: ${INSTALL_DIR}"
echo -e "  SSH 公鑰: ${INSTALL_DIR}/.ssh/ansible_svc_key.pub"
echo -e "  服務管理: ${BOLD}itagent status | log${NC}"
echo ""
echo -e "  ${BOLD}下一步：${NC}"
echo -e "  1. 瀏覽器登入 → 新增主機"
echo -e "  2. ssh-copy-id 分發公鑰到目標主機"
echo -e "  3. 執行第一次巡檢"
echo ""
