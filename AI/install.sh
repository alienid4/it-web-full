#!/bin/bash
# ============================================================
# Example Corp IT 每日巡檢系統 - 引導式安裝腳本
# 版本：v3.0.1.0
# 用途：從 GitHub ZIP 或 git clone 後，引導完成全部設定
# ============================================================

set -e

# 顏色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR=""
STEP=0
TOTAL_STEPS=10

banner() {
  clear
  echo -e "${GREEN}"
  echo "  ╔══════════════════════════════════════════════════╗"
  echo "  ║     Example Corp IT 每日巡檢系統 - 安裝引導         ║"
  echo "  ║     v3.0.1.0                                    ║"
  echo "  ╚══════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

step() {
  STEP=$((STEP+1))
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  步驟 ${STEP}/${TOTAL_STEPS}：$1${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
info() { echo -e "  ${CYAN}ℹ${NC} $1"; }

ask() {
  echo -en "  ${BOLD}$1${NC} "
  read -r REPLY
}

confirm() {
  echo -en "  ${BOLD}$1 [Y/n]${NC} "
  read -r REPLY
  [[ -z "$REPLY" || "$REPLY" =~ ^[Yy] ]]
}

pause() {
  echo ""
  echo -en "  按 Enter 繼續..."
  read -r
}

# ============================================================
banner

echo "  歡迎使用巡檢系統安裝引導。"
echo "  本腳本會帶你完成以下設定："
echo ""
echo "    1.  確認系統環境"
echo "    2.  設定安裝路徑"
echo "    3.  安裝系統套件"
echo "    4.  安裝 Python 套件"
echo "    5.  部署 MongoDB（Podman 容器）"
echo "    6.  設定環境變數（.env）"
echo "    7.  設定 Ansible Vault 密碼"
echo "    8.  設定受管主機（Inventory）"
echo "    9.  初始化資料庫"
echo "   10.  啟動服務 + 驗證"
echo ""

if ! confirm "準備好了嗎？開始安裝？"; then
  echo "  取消安裝。"
  exit 0
fi

# ============================================================
step "確認系統環境"

# OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  ok "作業系統：$PRETTY_NAME"
else
  warn "無法偵測作業系統"
fi

# Root
if [ "$(id -u)" -eq 0 ]; then
  ok "以 root 身份執行"
else
  fail "請以 root 執行此腳本：sudo bash install.sh"
  exit 1
fi

# Python
if command -v python3 &>/dev/null; then
  PY_VER=$(python3 --version 2>&1)
  ok "Python：$PY_VER"
else
  fail "找不到 python3，請先安裝"
  info "RHEL/Rocky: dnf install -y python3"
  info "Debian/Ubuntu: apt install -y python3"
  exit 1
fi

# Podman or Docker
if command -v podman &>/dev/null; then
  ok "容器引擎：Podman $(podman --version | awk '{print $3}')"
  CONTAINER_CMD="podman"
elif command -v docker &>/dev/null; then
  ok "容器引擎：Docker $(docker --version | awk '{print $3}')"
  CONTAINER_CMD="docker"
else
  warn "找不到 Podman 或 Docker"
  if confirm "要自動安裝 Podman 嗎？"; then
    if command -v dnf &>/dev/null; then
      dnf install -y podman
    elif command -v apt &>/dev/null; then
      apt install -y podman
    fi
    CONTAINER_CMD="podman"
    ok "Podman 安裝完成"
  else
    fail "需要 Podman 或 Docker 來執行 MongoDB"
    exit 1
  fi
fi

# Ansible
if command -v ansible &>/dev/null; then
  ok "Ansible：$(ansible --version | head -1)"
else
  warn "Ansible 未安裝（稍後會安裝）"
fi

pause

# ============================================================
step "設定安裝路徑"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_DIR="/opt/inspection"

info "腳本所在目錄：$SCRIPT_DIR"
echo ""

if [ "$SCRIPT_DIR" = "$DEFAULT_DIR" ]; then
  INSTALL_DIR="$DEFAULT_DIR"
  ok "已在預設安裝路徑：$INSTALL_DIR"
else
  echo "  預設安裝路徑：$DEFAULT_DIR"
  ask "安裝路徑 [按 Enter 使用預設]:"
  INSTALL_DIR="${REPLY:-$DEFAULT_DIR}"

  if [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
    info "將檔案從 $SCRIPT_DIR 複製到 $INSTALL_DIR"
    mkdir -p "$(dirname "$INSTALL_DIR")"
    cp -r "$SCRIPT_DIR" "$INSTALL_DIR"
    ok "檔案已複製到 $INSTALL_DIR"
  fi
fi

cd "$INSTALL_DIR"
ok "工作目錄：$(pwd)"

pause

# ============================================================
step "安裝系統套件"

if command -v dnf &>/dev/null; then
  PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
  PKG_MGR="yum"
elif command -v apt &>/dev/null; then
  PKG_MGR="apt"
else
  warn "無法偵測套件管理員，跳過系統套件安裝"
  PKG_MGR=""
fi

if [ -n "$PKG_MGR" ]; then
  info "使用 $PKG_MGR 安裝必要套件..."

  if [ "$PKG_MGR" = "apt" ]; then
    apt update -y
    apt install -y python3-pip python3-dev libldap2-dev gcc sysstat ansible-core openssh-server
  else
    $PKG_MGR install -y python3-pip python3-devel openldap-devel gcc sysstat ansible-core openssh-server
  fi
  ok "系統套件安裝完成"
fi

pause

# ============================================================
step "安裝 Python 套件"

if [ -f "$INSTALL_DIR/webapp/requirements.txt" ]; then
  pip3 install -r "$INSTALL_DIR/webapp/requirements.txt"
  pip3 install openpyxl
  ok "Python 套件安裝完成"
else
  warn "找不到 requirements.txt"
  pip3 install flask pymongo python-ldap gunicorn openpyxl
  ok "手動安裝 Python 套件完成"
fi

pause

# ============================================================
step "部署 MongoDB（Podman 容器）"

# 檢查是否已在運行
if $CONTAINER_CMD ps 2>/dev/null | grep -q mongodb; then
  ok "MongoDB 容器已在運行"
else
  info "準備啟動 MongoDB 容器..."

  # 資料目錄
  MONGO_DATA="$INSTALL_DIR/container/mongodb_data"
  mkdir -p "$MONGO_DATA"

  # 檢查是否有離線 image
  if $CONTAINER_CMD images | grep -q mongo; then
    ok "找到 MongoDB 映像檔"
  else
    info "拉取 MongoDB 映像檔（需要網路）..."
    if $CONTAINER_CMD pull docker.io/library/mongo:6; then
      ok "MongoDB 映像檔拉取完成"
    else
      fail "無法拉取映像檔。如果是離線環境，請先載入映像檔："
      info "$CONTAINER_CMD load -i mongodb_6.tar"
      pause
    fi
  fi

  # 啟動容器
  $CONTAINER_CMD run -d --name mongodb \
    -p 127.0.0.1:27017:27017 \
    -v "$MONGO_DATA:/data/db:Z" \
    --restart=always \
    docker.io/library/mongo:6

  sleep 3

  if $CONTAINER_CMD ps | grep -q mongodb; then
    ok "MongoDB 容器啟動成功（127.0.0.1:27017）"
  else
    fail "MongoDB 啟動失敗，請檢查日誌：$CONTAINER_CMD logs mongodb"
  fi
fi

# 設定開機自啟動
if command -v systemctl &>/dev/null && [ "$CONTAINER_CMD" = "podman" ]; then
  mkdir -p /etc/systemd/system
  cat > /etc/systemd/system/mongodb-container.service << 'SVCEOF'
[Unit]
Description=MongoDB Container (Podman)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/podman start -a mongodb
ExecStop=/usr/bin/podman stop mongodb
Restart=always

[Install]
WantedBy=multi-user.target
SVCEOF
  systemctl daemon-reload
  systemctl enable mongodb-container 2>/dev/null
  ok "MongoDB 開機自啟動已設定"
fi

pause

# ============================================================
step "設定環境變數（.env）"

ENV_FILE="$INSTALL_DIR/webapp/.env"

if [ -f "$ENV_FILE" ]; then
  warn ".env 已存在，跳過（如需修改請手動編輯 $ENV_FILE）"
else
  info "建立 .env 設定檔..."

  # SECRET_KEY
  SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")

  echo ""
  echo "  SMTP 郵件設定（用於告警通知，可稍後再設定）："
  ask "SMTP 伺服器 [留空跳過]:"
  SMTP_SERVER="${REPLY}"
  SMTP_PORT=""
  SMTP_USER=""
  SMTP_PASS=""

  if [ -n "$SMTP_SERVER" ]; then
    ask "SMTP Port [587]:"
    SMTP_PORT="${REPLY:-587}"
    ask "SMTP 帳號:"
    SMTP_USER="${REPLY}"
    ask "SMTP 密碼:"
    SMTP_PASS="${REPLY}"
  fi

  cat > "$ENV_FILE" << ENVEOF
# Flask
FLASK_SECRET_KEY=$SECRET_KEY
FLASK_DEBUG=False

# SMTP
SMTP_SERVER=${SMTP_SERVER}
SMTP_PORT=${SMTP_PORT:-587}
SMTP_USER=${SMTP_USER}
SMTP_PASSWORD=${SMTP_PASS}

# MongoDB
MONGO_HOST=127.0.0.1
MONGO_PORT=27017
MONGO_DB=inspection
ENVEOF

  chmod 600 "$ENV_FILE"
  ok ".env 已建立（權限 600）"
fi

pause

# ============================================================
step "設定 Ansible Vault 密碼"

VAULT_FILE="$INSTALL_DIR/.vault_pass"

if [ -f "$VAULT_FILE" ]; then
  warn "Vault 密碼檔已存在"
else
  info "Ansible Vault 用於加密主機密碼（Windows SSH 等）"
  ask "請輸入 Vault 密碼（或按 Enter 自動產生）:"

  if [ -z "$REPLY" ]; then
    VAULT_PW=$(python3 -c "import secrets; print(secrets.token_hex(16))")
    echo "$VAULT_PW" > "$VAULT_FILE"
    ok "自動產生 Vault 密碼：$VAULT_PW"
    warn "請記下此密碼！"
  else
    echo "$REPLY" > "$VAULT_FILE"
    ok "Vault 密碼已設定"
  fi

  chmod 600 "$VAULT_FILE"
fi

pause

# ============================================================
step "設定受管主機（Inventory）"

HOSTS_FILE="$INSTALL_DIR/ansible/inventory/hosts.yml"

info "目前的主機清單："
echo ""
if [ -f "$HOSTS_FILE" ]; then
  cat "$HOSTS_FILE"
else
  warn "找不到 hosts.yml"
fi

echo ""
info "你可以在安裝完成後，透過 Web 管理介面新增/編輯主機"
info "或直接編輯 $HOSTS_FILE"

if confirm "要現在新增本機（localhost）到巡檢清單嗎？"; then
  HOSTNAME_LOCAL=$(hostname)
  info "本機名稱：$HOSTNAME_LOCAL"

  # 確認 hosts.yml 有 local
  if grep -q "$HOSTNAME_LOCAL" "$HOSTS_FILE" 2>/dev/null; then
    ok "本機已在清單中"
  else
    info "將本機加入 inventory（之後可從 Web 管理）"
  fi
fi

pause

# ============================================================
step "初始化資料庫"

info "匯入初始設定到 MongoDB..."

cd "$INSTALL_DIR/webapp"

# 測試 MongoDB 連線
if python3 -c "from pymongo import MongoClient; c=MongoClient('mongodb://127.0.0.1:27017', serverSelectionTimeoutMS=3000); c.server_info(); print('OK')" 2>/dev/null; then
  ok "MongoDB 連線成功"
else
  fail "無法連線 MongoDB，請確認容器已啟動"
  pause
fi

# 匯入種子資料
if python3 seed_data.py 2>/dev/null; then
  ok "種子資料匯入完成"
else
  warn "種子資料匯入失敗（可能已存在，不影響使用）"
fi

# 建立管理員帳號
echo ""
info "建立系統管理員帳號（用於登入 /admin）"
ask "管理員帳號 [admin]:"
ADMIN_USER="${REPLY:-admin}"
ask "管理員密碼 [P@ssw0rd]:"
ADMIN_PASS="${REPLY:-P@ssw0rd}"

python3 -c "
from pymongo import MongoClient
from hashlib import sha256
c = MongoClient('mongodb://127.0.0.1:27017')
db = c.inspection
pw_hash = sha256('${ADMIN_PASS}'.encode()).hexdigest()
db.users.update_one(
    {'username': '${ADMIN_USER}'},
    {'\$set': {'username': '${ADMIN_USER}', 'password': pw_hash, 'role': 'admin'}},
    upsert=True
)
print('OK')
" 2>/dev/null && ok "管理員帳號已建立：${ADMIN_USER}" || warn "建立管理員帳號失敗"

pause

# ============================================================
step "啟動服務 + 驗證"

cd "$INSTALL_DIR/webapp"

info "啟動 Flask..."
nohup python3 app.py > /tmp/flask.log 2>&1 &
FLASK_PID=$!
sleep 3

# 驗證
echo ""
echo -e "  ${BOLD}驗證結果：${NC}"
echo ""

# MongoDB
if $CONTAINER_CMD ps | grep -q mongodb; then
  ok "MongoDB      ：運行中"
else
  fail "MongoDB      ：未運行"
fi

# Flask
if ss -tlnp | grep -q ":5000"; then
  ok "Flask        ：運行中（port 5000）"
else
  fail "Flask        ：未運行（檢查 /tmp/flask.log）"
fi

# Web 頁面
HTTP_CODE=$(curl -so /dev/null -w '%{http_code}' http://localhost:5000/ 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  ok "Web Dashboard：正常（HTTP 200）"
else
  warn "Web Dashboard：HTTP $HTTP_CODE"
fi

# 取得 IP
SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  安裝完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}系統網址：${NC}http://${SERVER_IP}:5000"
echo -e "  ${BOLD}管理後台：${NC}http://${SERVER_IP}:5000/admin"
echo -e "  ${BOLD}管理帳號：${NC}${ADMIN_USER}"
echo ""
echo -e "  ${BOLD}安裝路徑：${NC}${INSTALL_DIR}"
echo -e "  ${BOLD}Flask 日誌：${NC}/tmp/flask.log"
echo -e "  ${BOLD}MongoDB 資料：${NC}${INSTALL_DIR}/container/mongodb_data/"
echo ""
echo "  接下來你可以："
echo "    1. 打開瀏覽器訪問 http://${SERVER_IP}:5000"
echo "    2. 登入管理後台，新增受管主機"
echo "    3. 執行第一次巡檢：${INSTALL_DIR}/run_inspection.sh"
echo ""
echo "  如需協助，參考文件："
echo "    - PROJECT_HANDOFF.md  ：系統功能總覽"
echo "    - DEVLOG.md           ：開發歷程"
echo "    - SPEC_CHANGELOG      ：需求變更紀錄"
echo ""
