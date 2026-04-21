#!/usr/bin/env bash
# ============================================================================
#  金融業 IT 每日自動巡檢系統 — Linux 環境準備腳本
#  setup_environment.sh
#
#  用途：在全新 Linux 主機上一鍵安裝所有前置套件、建立目錄、帳號、
#        MongoDB 容器、Systemd 服務、防火牆、Cron 排程。
#
#  支援 OS：Rocky Linux 9.x（主要）/ RHEL 8-9 / AlmaLinux 8-9
#           Debian 11-12 / Ubuntu 22.04-24.04
#
#  執行方式：
#    chmod +x setup_environment.sh
#    sudo ./setup_environment.sh
#
#  ⚠ 必須以 root 執行
# ============================================================================

set -euo pipefail

# ===================== 可調參數（修改這裡即可）========================
INSTALL_DIR="/seclog/AI/inspection"        # 系統安裝根目錄
BACKUP_DIR="/seclog/backup"                # 備份目錄
WORKLOG_DIR="/root/AI/AI_worklog"          # 工作日誌目錄
FLASK_PORT=5000                            # Flask 監聽埠
MONGO_PORT=27017                           # MongoDB 埠
MONGO_BIND="127.0.0.1"                    # MongoDB 只綁定本機
ADMIN_USER="admin"                         # 預設管理員帳號
ADMIN_PASS="ChangeMe@2026"                # 預設管理員密碼（首次登入強制改）
ANSIBLE_SVC_USER="ansible_svc"            # Ansible 服務帳號
CRON_TIMES=("06 30" "13 30" "17 30")       # 巡檢排程（小時 分鐘）
PYTHON_MIN_VERSION="3.9"                   # 最低 Python 版本
# ======================================================================

# ---------- 顏色定義 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------- 輔助函式 ----------
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
section() { echo -e "\n${CYAN}${BOLD}════════════════════════════════════════${NC}"; echo -e "${CYAN}${BOLD}  $*${NC}"; echo -e "${CYAN}${BOLD}════════════════════════════════════════${NC}"; }
ok()      { echo -e "  ${GREEN}✓${NC} $*"; }
fail()    { echo -e "  ${RED}✗${NC} $*"; }

TOTAL_STEPS=10
CURRENT_STEP=0
step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    section "Step ${CURRENT_STEP}/${TOTAL_STEPS}: $*"
}

# ---------- OS 偵測 ----------
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION="${VERSION_ID}"
        OS_NAME="${PRETTY_NAME}"
    else
        error "無法偵測作業系統（找不到 /etc/os-release）"
        exit 1
    fi

    case "${OS_ID}" in
        rocky|rhel|centos|almalinux|ol)
            PKG_MGR="dnf"
            PKG_FAMILY="rhel"
            ;;
        debian|ubuntu)
            PKG_MGR="apt-get"
            PKG_FAMILY="debian"
            ;;
        *)
            error "不支援的作業系統: ${OS_NAME}"
            error "支援: Rocky/RHEL/CentOS/AlmaLinux 8-9, Debian 11-12, Ubuntu 22.04-24.04"
            exit 1
            ;;
    esac

    info "偵測到 OS: ${OS_NAME} (${OS_ID} ${OS_VERSION})"
    info "套件管理器: ${PKG_MGR}"
}

# ============================================================================
#  前置檢查
# ============================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  金融業 IT 每日自動巡檢系統 — 環境準備腳本                ║"
echo "║  Inspection System Environment Setup                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# root 檢查
if [ "$(id -u)" -ne 0 ]; then
    error "本腳本必須以 root 執行！"
    echo "  請使用: sudo $0"
    exit 1
fi

detect_os

# ============================================================================
#  Step 1: 安裝系統套件
# ============================================================================
step "安裝系統套件"

if [ "${PKG_FAMILY}" = "rhel" ]; then
    info "更新套件快取..."
    dnf makecache -q 2>/dev/null || true

    info "安裝必要套件..."
    dnf install -y \
        podman \
        python3 \
        python3-pip \
        python3-devel \
        openldap-devel \
        gcc \
        make \
        sysstat \
        net-snmp-utils \
        sshpass \
        openssh-clients \
        ansible-core \
        git \
        tar \
        gzip \
        cronie \
        firewalld \
        jq \
        curl \
        wget \
        2>&1 | tail -5

    # EPEL（部分套件需要）
    dnf install -y epel-release 2>/dev/null || true

elif [ "${PKG_FAMILY}" = "debian" ]; then
    info "更新套件快取..."
    apt-get update -qq

    info "安裝必要套件..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        podman \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        libldap2-dev \
        libsasl2-dev \
        gcc \
        make \
        sysstat \
        snmp \
        snmp-mibs-downloader \
        sshpass \
        openssh-client \
        ansible \
        git \
        tar \
        gzip \
        cron \
        ufw \
        jq \
        curl \
        wget \
        2>&1 | tail -5
fi

# 驗證安裝
for cmd in podman python3 pip3 ansible git; do
    if command -v ${cmd} &>/dev/null; then
        ok "${cmd} $(${cmd} --version 2>&1 | head -1)"
    else
        fail "${cmd} 安裝失敗"
    fi
done

# ============================================================================
#  Step 2: 檢查 Python 版本
# ============================================================================
step "檢查 Python 版本"

PYTHON_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
info "Python 版本: ${PYTHON_VER}"

if python3 -c "import sys; exit(0 if sys.version_info >= (3,9) else 1)"; then
    ok "Python ${PYTHON_VER} >= ${PYTHON_MIN_VERSION}"
else
    error "Python 版本 ${PYTHON_VER} 太舊，需要 >= ${PYTHON_MIN_VERSION}"
    exit 1
fi

# ============================================================================
#  Step 3: 安裝 Python 套件
# ============================================================================
step "安裝 Python 套件"

info "安裝 Flask 及相關套件..."
pip3 install --upgrade pip 2>&1 | tail -1

pip3 install \
    flask==3.0.3 \
    pymongo==4.7.3 \
    python-ldap==3.4.4 \
    gunicorn==22.0.0 \
    bcrypt \
    2>&1 | tail -5

# 選裝（Windows 遠端管理 + SNMP）
pip3 install pywinrm pysnmp 2>/dev/null || warn "pywinrm/pysnmp 安裝失敗（非必要）"

# 驗證
for pkg in flask pymongo ldap gunicorn bcrypt; do
    if python3 -c "import ${pkg}" 2>/dev/null; then
        ok "Python 套件 ${pkg} ✓"
    else
        fail "Python 套件 ${pkg} 安裝失敗"
    fi
done

# ============================================================================
#  Step 4: 建立目錄結構
# ============================================================================
step "建立目錄結構"

DIRS=(
    # 主程式目錄
    "${INSTALL_DIR}"
    "${INSTALL_DIR}/webapp"
    "${INSTALL_DIR}/webapp/routes"
    "${INSTALL_DIR}/webapp/services"
    "${INSTALL_DIR}/webapp/models"
    "${INSTALL_DIR}/webapp/templates"
    "${INSTALL_DIR}/webapp/static/css"
    "${INSTALL_DIR}/webapp/static/js"
    "${INSTALL_DIR}/webapp/static/img"

    # 資料目錄
    "${INSTALL_DIR}/data"
    "${INSTALL_DIR}/data/reports"
    "${INSTALL_DIR}/data/snapshots"
    "${INSTALL_DIR}/data/security_audit_reports"
    "${INSTALL_DIR}/data/linux_init_reports"
    "${INSTALL_DIR}/data/audit_progress"

    # Ansible 目錄
    "${INSTALL_DIR}/ansible"
    "${INSTALL_DIR}/ansible/inventory"
    "${INSTALL_DIR}/ansible/inventory/group_vars"
    "${INSTALL_DIR}/ansible/inventory/host_vars"
    "${INSTALL_DIR}/ansible/playbooks"
    "${INSTALL_DIR}/ansible/roles"

    # 日誌目錄
    "${INSTALL_DIR}/logs"

    # MongoDB 資料目錄
    "${INSTALL_DIR}/container"
    "${INSTALL_DIR}/container/mongodb_data"

    # 腳本目錄
    "${INSTALL_DIR}/scripts"

    # SSH 金鑰目錄
    "${INSTALL_DIR}/.ssh"

    # 備份目錄
    "${BACKUP_DIR}"
    "${BACKUP_DIR}/twgcb"
    "${BACKUP_DIR}/db_dumps"

    # 工作日誌
    "${WORKLOG_DIR}"
)

for dir in "${DIRS[@]}"; do
    mkdir -p "${dir}"
    ok "${dir}"
done

# ============================================================================
#  Step 5: 建立服務帳號與權限設定
# ============================================================================
step "建立服務帳號與權限設定"

# --- Ansible 服務帳號（用於 SSH 連線受監控主機）---
if ! id "${ANSIBLE_SVC_USER}" &>/dev/null; then
    useradd -r -m -s /bin/bash \
        -c "Ansible Service Account for Inspection System" \
        "${ANSIBLE_SVC_USER}"
    ok "建立帳號: ${ANSIBLE_SVC_USER}"
else
    ok "帳號已存在: ${ANSIBLE_SVC_USER}"
fi

# 加入 systemd-journal 群組（Rocky/RHEL 可讀 journalctl）
if getent group systemd-journal &>/dev/null; then
    usermod -aG systemd-journal "${ANSIBLE_SVC_USER}" 2>/dev/null || true
    ok "${ANSIBLE_SVC_USER} 加入 systemd-journal 群組"
fi

# --- SSH 金鑰（若不存在則建立）---
SSH_KEY="${INSTALL_DIR}/.ssh/ansible_svc_key"
if [ ! -f "${SSH_KEY}" ]; then
    ssh-keygen -t ed25519 -f "${SSH_KEY}" -N "" -C "ansible_svc@ansible-host"
    ok "產生 SSH 金鑰: ${SSH_KEY}"
else
    ok "SSH 金鑰已存在: ${SSH_KEY}"
fi

# --- 檔案權限設定 ---
info "設定檔案權限..."

# 敏感檔案 — 僅 root 可讀寫
chmod 600 "${SSH_KEY}" 2>/dev/null || true
chmod 600 "${SSH_KEY}.pub" 2>/dev/null || true
ok "SSH 金鑰: 600 (僅 root)"

# .ssh 目錄
chmod 700 "${INSTALL_DIR}/.ssh"
ok ".ssh 目錄: 700"

# 日誌目錄
chmod 755 "${INSTALL_DIR}/logs"
ok "日誌目錄: 755"

# MongoDB 資料目錄（Podman 需寫入）
chmod 777 "${INSTALL_DIR}/container/mongodb_data"
ok "MongoDB 資料目錄: 777"

# 建立稍後需要的空設定檔（防止程式找不到）
touch "${INSTALL_DIR}/data/settings.json"
echo '{}' > "${INSTALL_DIR}/data/settings.json"
chmod 600 "${INSTALL_DIR}/data/settings.json"
ok "settings.json: 600 (僅 root)"

# .env 檔案模板
if [ ! -f "${INSTALL_DIR}/webapp/.env" ]; then
    cat > "${INSTALL_DIR}/webapp/.env" << 'ENVEOF'
# 敏感環境變數 — 請勿提交至 Git
SMTP_PASSWORD=your_smtp_password_here
LDAP_PASSWORD=your_ldap_password_here
ENVEOF
    chmod 600 "${INSTALL_DIR}/webapp/.env"
    ok "建立 .env 模板: 600"
fi

# ============================================================================
#  Step 6: 啟動 MongoDB 容器
# ============================================================================
step "啟動 MongoDB 容器"

# 檢查是否有離線映像檔
if [ -f "${INSTALL_DIR}/mongodb6.tar" ]; then
    info "載入離線 MongoDB 映像..."
    podman load -i "${INSTALL_DIR}/mongodb6.tar"
    ok "離線映像載入完成"
else
    info "拉取 MongoDB 6 映像（需要網路）..."
    podman pull docker.io/library/mongo:6
    ok "映像拉取完成"
fi

# 停止舊容器（如有）
podman stop mongodb 2>/dev/null || true
podman rm mongodb 2>/dev/null || true

# 啟動新容器
info "啟動 MongoDB 容器..."
podman run -d \
    --name mongodb \
    -p ${MONGO_BIND}:${MONGO_PORT}:27017 \
    -v "${INSTALL_DIR}/container/mongodb_data:/data/db:Z" \
    --restart=always \
    docker.io/library/mongo:6

# 等待 MongoDB 就緒
info "等待 MongoDB 就緒..."
for i in $(seq 1 30); do
    if podman exec mongodb mongosh --eval "db.runCommand({ping:1})" --quiet 2>/dev/null; then
        ok "MongoDB 已就緒（等待 ${i} 秒）"
        break
    fi
    sleep 1
    if [ $i -eq 30 ]; then
        error "MongoDB 30 秒內未就緒"
        exit 1
    fi
done

# ============================================================================
#  Step 7: 初始化 MongoDB 資料庫
# ============================================================================
step "初始化 MongoDB 資料庫"

info "建立 inspection 資料庫、Collections 與索引..."

python3 << PYEOF
import sys
from pymongo import MongoClient
from datetime import datetime

try:
    client = MongoClient("${MONGO_BIND}", ${MONGO_PORT}, serverSelectionTimeoutMS=5000)
    client.server_info()  # 測試連線
except Exception as e:
    print(f"  ✗ MongoDB 連線失敗: {e}")
    sys.exit(1)

db = client["inspection"]

# --- 建立 Collections 與索引 ---
# hosts
db.hosts.create_index("hostname", unique=True)
print("  ✓ Collection: hosts (索引: hostname unique)")

# inspections
db.inspections.create_index([("hostname", 1), ("run_date", -1), ("run_time", -1)])
db.inspections.create_index("run_date")
db.inspections.create_index("overall_status")
print("  ✓ Collection: inspections (索引: hostname+date+time, run_date, status)")

# filter_rules
db.filter_rules.create_index("rule_id")
print("  ✓ Collection: filter_rules")

# settings (插入預設值)
defaults = {
    "thresholds": {
        "disk_warn": 85, "disk_crit": 95,
        "cpu_warn": 80, "cpu_crit": 95,
        "mem_warn": 80, "mem_crit": 95
    },
    "disk_exclude_mounts": ["/dev", "/run", "/sys", "/proc", "/tmp"],
    "disk_exclude_prefixes": ["/run/", "/dev/", "/sys/", "/proc/", "/var/lib/containers/"],
    "cpu_sample_minutes": 10,
    "error_log_max_entries": 50,
    "error_log_hours": 24,
    "service_check_list": ["sshd", "crond"]
}
for key, value in defaults.items():
    db.settings.update_one({"key": key}, {"\$set": {"value": value}}, upsert=True)
print("  ✓ Collection: settings (預設門檻已寫入)")

# users (預設管理員)
import bcrypt
pw_hash = bcrypt.hashpw("${ADMIN_PASS}".encode(), bcrypt.gensalt()).decode()
db.users.create_index("username", unique=True)
db.users.update_one(
    {"username": "${ADMIN_USER}"},
    {"\$set": {
        "username": "${ADMIN_USER}",
        "password_hash": pw_hash,
        "display_name": "系統管理員",
        "role": "admin",
        "must_change_password": True,
        "last_seen": None,
        "last_ip": None,
        "email": ""
    }},
    upsert=True
)
print("  ✓ Collection: users (預設管理員: ${ADMIN_USER})")

# admin_worklog
db.admin_worklog.create_index([("timestamp", -1)])
print("  ✓ Collection: admin_worklog")

# alert_acks
print("  ✓ Collection: alert_acks")

# twgcb_results
db.twgcb_results.create_index([("hostname", 1), ("scan_time", -1)])
print("  ✓ Collection: twgcb_results")

# twgcb_backups
print("  ✓ Collection: twgcb_backups")

# hr_users
db.hr_users.create_index("ad_account", unique=True)
print("  ✓ Collection: hr_users")

# account_notes
print("  ✓ Collection: account_notes")

print("  ✓ MongoDB 初始化完成（11 個 Collections）")
client.close()
PYEOF

# ============================================================================
#  Step 8: 建立 Systemd 服務
# ============================================================================
step "建立 Systemd 服務"

# --- MongoDB 容器服務 ---
info "建立 MongoDB 服務: itagent-db.service"
cat > /etc/systemd/system/itagent-db.service << 'SVCEOF'
[Unit]
Description=ITAgent MongoDB (Podman Container)
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStartPre=/usr/bin/podman start mongodb
ExecStart=/bin/bash -c 'until /usr/bin/podman exec mongodb mongosh --eval "db.runCommand({ping:1})" --quiet 2>/dev/null; do sleep 1; done'
ExecStop=/usr/bin/podman stop -t 10 mongodb
ExecReload=/usr/bin/podman restart mongodb
RemainAfterExit=yes
Restart=on-failure
RestartSec=5
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
SVCEOF
ok "itagent-db.service 建立完成"

# --- Flask Web 服務 ---
info "建立 Flask 服務: itagent-web.service"
cat > /etc/systemd/system/itagent-web.service << SVCEOF
[Unit]
Description=ITAgent Inspection Web Application (Flask)
After=itagent-db.service
Requires=itagent-db.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}/webapp
ExecStart=/usr/bin/gunicorn --workers=4 --bind=0.0.0.0:${FLASK_PORT} --timeout=120 app:app
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SVCEOF
ok "itagent-web.service 建立完成"

# 重新載入 Systemd
systemctl daemon-reload
ok "systemctl daemon-reload 完成"

# 啟用開機自動啟動
systemctl enable itagent-db.service
systemctl enable itagent-web.service
ok "服務已設定開機自動啟動"

# ============================================================================
#  Step 9: 防火牆與 SELinux 設定
# ============================================================================
step "防火牆與 SELinux 設定"

# --- 防火牆 ---
if [ "${PKG_FAMILY}" = "rhel" ]; then
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --add-port=${FLASK_PORT}/tcp --permanent
        firewall-cmd --reload
        ok "firewalld: 開放 port ${FLASK_PORT}/tcp"
    else
        warn "firewalld 未啟動，跳過防火牆設定"
    fi
elif [ "${PKG_FAMILY}" = "debian" ]; then
    if command -v ufw &>/dev/null; then
        ufw allow ${FLASK_PORT}/tcp 2>/dev/null || true
        ok "ufw: 開放 port ${FLASK_PORT}/tcp"
    else
        warn "ufw 未安裝，跳過防火牆設定"
    fi
fi

info "MongoDB 僅監聽 ${MONGO_BIND}:${MONGO_PORT}，無需開放防火牆"

# --- SELinux ---
if command -v getenforce &>/dev/null; then
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Disabled")
    info "SELinux 狀態: ${SELINUX_STATUS}"
    if [ "${SELINUX_STATUS}" = "Enforcing" ]; then
        # 允許 Podman 容器存取掛載目錄
        setsebool -P container_manage_cgroup on 2>/dev/null || true
        ok "SELinux: container_manage_cgroup=on"
    fi
else
    info "SELinux 未安裝（Debian/Ubuntu 通常使用 AppArmor）"
fi

# ============================================================================
#  Step 10: 設定 Cron 排程
# ============================================================================
step "設定 Cron 排程"

CRON_FILE="/var/spool/cron/root"
if [ "${PKG_FAMILY}" = "debian" ]; then
    CRON_FILE="/var/spool/cron/crontabs/root"
fi

# 建立 run_inspection.sh 佔位腳本（實際內容由開發者填入）
cat > "${INSTALL_DIR}/run_inspection.sh" << 'RUNEOF'
#!/usr/bin/env bash
# ============================================================================
# 每日巡檢啟動器 — 由 Cron 觸發
# ============================================================================
set -euo pipefail

INSPECTION_HOME="/seclog/AI/inspection"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${INSPECTION_HOME}/logs/${TIMESTAMP}_run.log"
LOCK_FILE="/tmp/inspection_run.lock"

# PID 鎖定（防止併行執行）
if [ -f "${LOCK_FILE}" ]; then
    PID=$(cat "${LOCK_FILE}")
    if kill -0 "${PID}" 2>/dev/null; then
        echo "[$(date)] 巡檢正在執行中 (PID: ${PID})，跳過" >> "${LOG_FILE}"
        exit 0
    fi
fi
echo $$ > "${LOCK_FILE}"
trap 'rm -f ${LOCK_FILE}' EXIT

echo "[$(date)] === 開始巡檢 ===" >> "${LOG_FILE}"

# 1. 執行 Ansible Playbook
cd "${INSPECTION_HOME}/ansible"
ansible-playbook playbooks/site.yml -i inventory/hosts.yml \
    --vault-password-file "${INSPECTION_HOME}/.vault_pass" \
    >> "${LOG_FILE}" 2>&1 || true

# 2. 匯入 MongoDB
cd "${INSPECTION_HOME}/webapp"
python3 seed_data.py >> "${LOG_FILE}" 2>&1 || true

# 3. 自動清理舊資料
find "${INSPECTION_HOME}/logs" -name "*.log" -mtime +30 -delete 2>/dev/null || true
find "${INSPECTION_HOME}/data/reports" -name "*.html" -mtime +90 -delete 2>/dev/null || true
find "${INSPECTION_HOME}/data/reports" -name "*.json" -mtime +90 -delete 2>/dev/null || true

echo "[$(date)] === 巡檢完成 ===" >> "${LOG_FILE}"
RUNEOF

chmod +x "${INSTALL_DIR}/run_inspection.sh"
ok "run_inspection.sh 建立完成"

# 寫入 Cron 排程
info "設定巡檢排程..."
# 先移除舊的巡檢排程
crontab -l 2>/dev/null | grep -v "run_inspection.sh" > /tmp/cron_clean 2>/dev/null || true

for time_pair in "${CRON_TIMES[@]}"; do
    read -r HOUR MIN <<< "${time_pair}"
    echo "${MIN} ${HOUR} * * * ${INSTALL_DIR}/run_inspection.sh >> ${INSTALL_DIR}/logs/cron.log 2>&1" >> /tmp/cron_clean
    ok "排程: 每日 ${HOUR}:${MIN}"
done

crontab /tmp/cron_clean
rm -f /tmp/cron_clean
ok "Cron 排程已寫入"

# ============================================================================
#  產生 config.py 模板
# ============================================================================
info "產生 config.py 模板..."

SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_hex(32))')

cat > "${INSTALL_DIR}/webapp/config.py" << CFGEOF
# -*- coding: utf-8 -*-
# 巡檢系統組態檔 — 由 setup_environment.sh 自動產生
# 產生時間: $(date '+%Y-%m-%d %H:%M:%S')

import os

# --- 路徑設定 ---
INSPECTION_HOME = "${INSTALL_DIR}"
SETTINGS_FILE   = os.path.join(INSPECTION_HOME, "data", "settings.json")
REPORTS_DIR     = os.path.join(INSPECTION_HOME, "data", "reports")
HOSTS_CONFIG    = os.path.join(INSPECTION_HOME, "data", "hosts_config.json")
SNAPSHOTS_DIR   = os.path.join(INSPECTION_HOME, "data", "snapshots")
LOG_DIR         = os.path.join(INSPECTION_HOME, "logs")
BACKUP_DIR      = "${BACKUP_DIR}"

# --- MongoDB ---
MONGO_CONFIG = {
    "host": "${MONGO_BIND}",
    "port": ${MONGO_PORT},
    "db": "inspection"
}

# --- LDAP/AD（目前 Mock 模式）---
LDAP_CONFIG = {
    "server": "ldap://your-ad-server.company.com",
    "base_dn": "DC=company,DC=com",
    "bind_dn": "CN=svc_ldap,OU=Service,DC=company,DC=com",
    "bind_password": os.getenv("LDAP_PASSWORD", ""),
    "mock_mode": True,
    "cache_ttl": 3600
}

# --- Flask ---
FLASK_HOST  = "0.0.0.0"
FLASK_PORT  = ${FLASK_PORT}
FLASK_DEBUG = False
SECRET_KEY  = "${SECRET_KEY}"
CFGEOF

chmod 600 "${INSTALL_DIR}/webapp/config.py"
ok "config.py 產生完成（SECRET_KEY 已隨機產生）"

# ============================================================================
#  產生 requirements.txt
# ============================================================================
cat > "${INSTALL_DIR}/webapp/requirements.txt" << 'REQEOF'
flask==3.0.3
pymongo==4.7.3
python-ldap==3.4.4
gunicorn==22.0.0
bcrypt
REQEOF
ok "requirements.txt 產生完成"

# ============================================================================
#  產生 Ansible Vault 密碼檔
# ============================================================================
if [ ! -f "${INSTALL_DIR}/.vault_pass" ]; then
    python3 -c 'import secrets; print(secrets.token_hex(32))' > "${INSTALL_DIR}/.vault_pass"
    chmod 600 "${INSTALL_DIR}/.vault_pass"
    ok "Ansible Vault 密碼檔產生完成"
else
    ok "Ansible Vault 密碼檔已存在"
fi

# ============================================================================
#  最終驗證
# ============================================================================
section "環境準備完成 — 驗證結果"

echo ""
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│  元件驗證                                                      │"
echo "├─────────────────────────────────────────────────────────────────┤"

# 逐項驗證
check_item() {
    local name=$1
    local cmd=$2
    if eval "${cmd}" &>/dev/null; then
        printf "│  %-15s │  %-43s │\n" "${name}" "$(echo -e "${GREEN}✓ OK${NC}")"
    else
        printf "│  %-15s │  %-43s │\n" "${name}" "$(echo -e "${RED}✗ FAIL${NC}")"
    fi
}

check_item "Python 3.9+"    "python3 -c 'import sys; exit(0 if sys.version_info>=(3,9) else 1)'"
check_item "Flask"          "python3 -c 'import flask'"
check_item "PyMongo"        "python3 -c 'import pymongo'"
check_item "bcrypt"         "python3 -c 'import bcrypt'"
check_item "Gunicorn"       "command -v gunicorn"
check_item "Podman"         "command -v podman"
check_item "MongoDB"        "podman exec mongodb mongosh --eval 'db.runCommand({ping:1})' --quiet"
check_item "Ansible"        "command -v ansible"
check_item "Git"            "command -v git"
check_item "安裝目錄"       "test -d ${INSTALL_DIR}/webapp"
check_item "備份目錄"       "test -d ${BACKUP_DIR}"
check_item "SSH 金鑰"       "test -f ${INSTALL_DIR}/.ssh/ansible_svc_key"
check_item "config.py"      "test -f ${INSTALL_DIR}/webapp/config.py"
check_item "Vault 密碼"     "test -f ${INSTALL_DIR}/.vault_pass"
check_item "itagent-db"     "test -f /etc/systemd/system/itagent-db.service"
check_item "itagent-web"    "test -f /etc/systemd/system/itagent-web.service"

echo "└─────────────────────────────────────────────────────────────────┘"
echo ""

# 摘要資訊
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  環境資訊摘要                                              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                            ║"
printf "║  %-14s %-44s ║\n" "安裝目錄:" "${INSTALL_DIR}"
printf "║  %-14s %-44s ║\n" "備份目錄:" "${BACKUP_DIR}"
printf "║  %-14s %-44s ║\n" "MongoDB:" "${MONGO_BIND}:${MONGO_PORT} (inspection)"
printf "║  %-14s %-44s ║\n" "Web URL:" "http://${LOCAL_IP}:${FLASK_PORT}"
printf "║  %-14s %-44s ║\n" "Admin URL:" "http://${LOCAL_IP}:${FLASK_PORT}/admin"
printf "║  %-14s %-44s ║\n" "管理帳號:" "${ADMIN_USER}"
printf "║  %-14s %-44s ║\n" "管理密碼:" "${ADMIN_PASS} (首次登入須修改)"
printf "║  %-14s %-44s ║\n" "SSH 金鑰:" "${INSTALL_DIR}/.ssh/ansible_svc_key"
printf "║  %-14s %-44s ║\n" "Vault 密碼:" "${INSTALL_DIR}/.vault_pass"
echo "║                                                            ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  巡檢排程 (Cron)                                           ║"
echo "╠══════════════════════════════════════════════════════════════╣"
for time_pair in "${CRON_TIMES[@]}"; do
    read -r HOUR MIN <<< "${time_pair}"
    printf "║    每日 %02d:%02d                                              ║\n" "${HOUR}" "${MIN}"
done
echo "║                                                            ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  下一步                                                    ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                            ║"
echo "║  1. 將 webapp 程式碼放入:                                  ║"
printf "║     %-54s ║\n" "${INSTALL_DIR}/webapp/"
echo "║                                                            ║"
echo "║  2. 將 Ansible roles/playbooks 放入:                       ║"
printf "║     %-54s ║\n" "${INSTALL_DIR}/ansible/"
echo "║                                                            ║"
echo "║  3. 啟動 Web 服務:                                        ║"
echo "║     systemctl start itagent-web                            ║"
echo "║                                                            ║"
echo "║  4. 檢查服務狀態:                                         ║"
echo "║     systemctl status itagent-db itagent-web                ║"
echo "║                                                            ║"
echo "║  5. 查看日誌:                                             ║"
echo "║     journalctl -u itagent-web -f                           ║"
echo "║                                                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
info "環境準備完成！可以開始部署應用程式了。"
