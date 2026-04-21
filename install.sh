#!/bin/bash
###############################################
#  IT Inspection System - 離線安裝腳本
#  版本: v3.5.0.0-testenv
#  適用: Rocky Linux 9 / RHEL 8-9 / CentOS 8-9
#  模式: RPM 原生 MongoDB（無需 Podman）
#
#  使用方式:
#    sudo ./install.sh                         # 自動搜尋套件來源
#    sudo ./install.sh --deps-dir=/path/to/pkg # 指定套件目錄
#
#  套件搜尋順序（找到即停）:
#    1. ./packages/                            # install.sh 同目錄
#    2. /tmp/upload/packages/                  # 使用者上傳位置
#    3. --deps-dir=<path> 參數指定
###############################################
set -e

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"
CYAN="\033[0;36m"; BOLD="\033[1m"; NC="\033[0m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="3.5.0.0-testenv"
STEP=0; TOTAL=8

# 解析命令列參數
DEPS_DIR=""
for arg in "$@"; do
    case $arg in
        --deps-dir=*) DEPS_DIR="${arg#*=}" ;;
    esac
done

step()  { STEP=$((STEP+1)); echo -e "\n${CYAN}━━━ 步驟 ${STEP}/${TOTAL}：$1 ━━━${NC}\n"; }
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }

clear
echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║     IT Inspection System - 離線安裝         ║"
echo "  ║     v${VERSION}  (RPM 模式，無需容器)            ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================
# Step 1: 環境檢查
# ============================================
step "檢查環境"

[ "$(id -u)" -ne 0 ] && fail "請用 root 執行"
ok "Root 權限"

. /etc/os-release 2>/dev/null
ok "系統: ${PRETTY_NAME:-Unknown}"

# 檢查是否為 RHEL 系列
IS_RHEL=false
if echo "$ID $ID_LIKE" | grep -qiE "rhel|centos|rocky|fedora|almalinux"; then
    IS_RHEL=true
    ok "RHEL 系列 OS 確認"
else
    warn "非 RHEL 系列 (${ID})，RPM 安裝可能不相容"
    read -rp "  是否繼續？(y/n) " ans
    [[ ! "$ans" =~ ^[Yy]$ ]] && exit 1
fi

# 解析套件目錄：優先 --deps-dir、否則 ./packages/、再退到 /tmp/upload/packages/
PKG_ROOT=""
for candidate in "$DEPS_DIR" "$SCRIPT_DIR/packages" "/tmp/upload/packages"; do
    [ -n "$candidate" ] || continue
    if [ -d "$candidate/rpm" ] && [ -d "$candidate/pip" ]; then
        PKG_ROOT="$candidate"
        break
    fi
done

if [ -z "$PKG_ROOT" ]; then
    echo -e "${RED}"
    echo "  找不到離線套件目錄。請執行以下其中一種方式："
    echo ""
    echo "  方式 A: 解壓到 /tmp/upload/"
    echo "    mkdir -p /tmp/upload"
    echo "    tar xzf inspection_deps_v3.5.0.0-testenv.tar.gz -C /tmp/upload/"
    echo ""
    echo "  方式 B: 解壓到 install.sh 同目錄"
    echo "    tar xzf inspection_deps_v3.5.0.0-testenv.tar.gz -C $SCRIPT_DIR/"
    echo ""
    echo "  方式 C: 明確指定路徑"
    echo "    sudo ./install.sh --deps-dir=/your/path"
    echo -e "${NC}"
    exit 1
fi
ok "離線套件目錄: $PKG_ROOT"

# 驗證 SHA256（若 versions.txt 存在）
if [ -f "$PKG_ROOT/versions.txt" ]; then
    BAD=0
    for type in rpm pip; do
        cd "$PKG_ROOT/$type" 2>/dev/null && {
            grep -E "^[a-f0-9]{64} " "$PKG_ROOT/versions.txt" | while read line; do
                sha=$(echo "$line" | awk '{print $1}')
                file=$(echo "$line" | sed 's/^[a-f0-9]* \*//')
                [ -f "$file" ] || continue
                actual=$(sha256sum "$file" | awk '{print $1}')
                [ "$sha" = "$actual" ] || { echo "  BAD_CHECKSUM: $file"; BAD=$((BAD+1)); }
            done
            cd - >/dev/null
        }
    done
    [ $BAD -eq 0 ] && ok "套件 SHA256 驗證通過" || warn "有 $BAD 個套件 checksum 不符（可能已替換）"
fi

# 檢查程式碼是否在 SCRIPT_DIR（git clone 或解壓後的根目錄）
[ -f "$SCRIPT_DIR/package.json" ] || [ -d "$SCRIPT_DIR/app" ] || fail "$SCRIPT_DIR 下沒有找到程式碼，請確認你在正確的專案根目錄執行"
ok "程式碼目錄確認"

# ============================================
# Step 2: 引導式設定
# ============================================
step "安裝設定"

echo -e "  ${BOLD}請設定以下參數（直接按 Enter 使用預設值）${NC}\n"

read -rp "  安裝目錄 [/opt/inspection]: " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-/opt/inspection}

read -rp "  備份目錄 [/var/backups/inspection]: " BACKUP_DIR
BACKUP_DIR=${BACKUP_DIR:-/var/backups/inspection}

read -rp "  Flask Port [5000]: " FLASK_PORT
FLASK_PORT=${FLASK_PORT:-5000}

read -rp "  MongoDB Port [27017]: " MONGO_PORT
MONGO_PORT=${MONGO_PORT:-27017}

# 互動式密碼設定
while true; do
    read -rsp "  管理員密碼（至少 6 碼）: " ADMIN_PW
    echo
    if [ ${#ADMIN_PW} -lt 6 ]; then
        warn "密碼太短，請至少 6 碼"
        continue
    fi
    read -rsp "  確認密碼: " ADMIN_PW2
    echo
    if [ "$ADMIN_PW" = "$ADMIN_PW2" ]; then
        ok "密碼已設定"
        break
    else
        warn "密碼不一致，請重新輸入"
    fi
done

read -rp "  巡檢排程 HH:MM（多個用逗號）[06:30,13:30,17:30]: " CRON_TIMES
CRON_TIMES=${CRON_TIMES:-06:30,13:30,17:30}

echo ""
echo -e "  ${BOLD}═══ 確認安裝設定 ═══${NC}"
echo -e "  安裝目錄:   ${CYAN}${INSTALL_DIR}${NC}"
echo -e "  備份目錄:   ${CYAN}${BACKUP_DIR}${NC}"
echo -e "  Flask Port: ${CYAN}${FLASK_PORT}${NC}"
echo -e "  MongoDB:    ${CYAN}127.0.0.1:${MONGO_PORT}${NC}"
echo -e "  巡檢排程:   ${CYAN}${CRON_TIMES}${NC}"
echo ""
read -rp "  確認開始安裝？(y/n) " ans
[[ ! "$ans" =~ ^[Yy]$ ]] && echo "取消安裝" && exit 0

# ============================================
# Step 3: 安裝離線 RPM 套件
# ============================================
step "安裝離線 RPM 套件"

RPM_DIR="$PKG_ROOT/rpm"
if ls "$RPM_DIR"/*.rpm &>/dev/null; then
    rpm -Uvh --force --nodeps "$RPM_DIR"/*.rpm 2>/dev/null || true

    command -v mongod &>/dev/null && ok "mongod $(mongod --version 2>/dev/null | head -1 | grep -oP 'v[\d.]+')" || warn "mongod 未就緒"
    command -v mongosh &>/dev/null && ok "mongosh" || warn "mongosh 未安裝"
    command -v ansible &>/dev/null && ok "ansible $(ansible --version 2>/dev/null | head -1 | grep -oP '[\d.]+')" || warn "ansible 未安裝"
    command -v pip3 &>/dev/null && ok "pip3" || warn "pip3 未安裝"
    command -v iostat &>/dev/null && ok "sysstat (iostat)" || warn "sysstat 未安裝"
else
    fail "RPM 目錄為空"
fi

# ============================================
# Step 4: 安裝離線 Python 套件
# ============================================
step "安裝離線 Python 套件"

PIP_DIR="$PKG_ROOT/pip"
if [ -d "$PIP_DIR" ] && ls "$PIP_DIR"/*.whl &>/dev/null; then
    pip3 install --no-index --find-links="$PIP_DIR/" \
        flask pymongo openpyxl bcrypt gunicorn pywinrm pysnmp 2>/dev/null && ok "Python 套件安裝完成" || warn "部分套件未安裝"
else
    fail "找不到 pip wheel 檔案"
fi

# ============================================
# Step 5: 部署程式碼
# ============================================
step "部署程式碼"

mkdir -p "$(dirname "$INSTALL_DIR")"

if [ -d "$INSTALL_DIR" ]; then
    warn "目標目錄已存在，備份中..."
    BACKUP_TS=$(date +%Y%m%d_%H%M%S)
    mkdir -p "$BACKUP_DIR"
    mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.${BACKUP_TS}"
    ok "舊版已備份到 ${INSTALL_DIR}.bak.${BACKUP_TS}"
fi

# 部署整個 repo（排除安裝腳本與套件目錄）
mkdir -p "$INSTALL_DIR"
if command -v rsync &>/dev/null; then
    rsync -a \
        --exclude='.git/' --exclude='.github/' --exclude='.vscode/' \
        --exclude='install.sh' --exclude='first_run.sh' --exclude='itagent.sh' \
        --exclude='packages/' --exclude='tmp_install_work/' --exclude='deps_build/' \
        --exclude='node_modules/' --exclude='__pycache__/' --exclude='*.pyc' \
        --exclude='inspection_deploy_v*' --exclude='inspection_deps_v*' \
        "$SCRIPT_DIR/" "$INSTALL_DIR/"
else
    (cd "$SCRIPT_DIR" && tar cf - \
        --exclude='.git' --exclude='.vscode' \
        --exclude='install.sh' --exclude='first_run.sh' --exclude='itagent.sh' \
        --exclude='packages' --exclude='tmp_install_work' --exclude='deps_build' \
        --exclude='node_modules' --exclude='__pycache__' --exclude='*.pyc' \
        --exclude='inspection_deploy_v*' --exclude='inspection_deps_v*' \
        .) | tar xf - -C "$INSTALL_DIR/"
fi
ok "程式碼部署到 $INSTALL_DIR"

# 建立必要子目錄
mkdir -p "$INSTALL_DIR"/{logs,reports,data/reports,data/uploads,data/security_audit_reports,data/audit_progress,data/notes,data/snapshots,.ssh}
chmod 700 "$INSTALL_DIR/.ssh"
mkdir -p "$BACKUP_DIR"
ok "建立必要目錄"

# 複製 itagent.sh 管理工具
cp "$SCRIPT_DIR/itagent.sh" "$INSTALL_DIR/itagent.sh"
chmod +x "$INSTALL_DIR/itagent.sh"
ln -sf "$INSTALL_DIR/itagent.sh" /usr/local/bin/itagent
ok "itagent 管理工具已安裝"

# 複製 first_run.sh（若存在）
if [ -f "$SCRIPT_DIR/first_run.sh" ]; then
    cp "$SCRIPT_DIR/first_run.sh" "$INSTALL_DIR/first_run.sh"
    chmod +x "$INSTALL_DIR/first_run.sh"
fi

# 自動產生 ansible SSH key（不從套件帶入）
if [ ! -f "$INSTALL_DIR/.ssh/ansible_svc_key" ]; then
    ssh-keygen -t ed25519 -C "ansible_svc@$(hostname)" -f "$INSTALL_DIR/.ssh/ansible_svc_key" -N "" -q
    date -u +%Y-%m-%dT%H:%M:%SZ > "$INSTALL_DIR/.ssh/key_created_date"
    chmod 600 "$INSTALL_DIR/.ssh/ansible_svc_key"
    chmod 644 "$INSTALL_DIR/.ssh/ansible_svc_key.pub"
    ok "Ansible SSH key 已產生（$INSTALL_DIR/.ssh/ansible_svc_key.pub）"
else
    ok "既有 SSH key 保留"
fi

# ============================================
# Step 6: 建立環境設定與 systemd 服務
# ============================================
step "建立系統服務"

# 環境變數
cat > /etc/default/itagent << ENVEOF
ITAGENT_HOME=${INSTALL_DIR}
ENVEOF
ok "/etc/default/itagent"

# MongoDB 資料目錄
mkdir -p /var/lib/mongo /var/log/mongodb
chown mongod:mongod /var/lib/mongo /var/log/mongodb 2>/dev/null || true

# itagent-db: native mongod
cat > /etc/systemd/system/itagent-db.service << 'SVC1'
[Unit]
Description=ITAgent MongoDB (Native RPM)
After=network.target

[Service]
Type=forking
User=mongod
Group=mongod
ExecStart=/usr/bin/mongod --dbpath /var/lib/mongo --bind_ip 127.0.0.1 --port MONGO_PORT_PLACEHOLDER --fork --logpath /var/log/mongodb/mongod.log
ExecStop=/usr/bin/mongod --shutdown --dbpath /var/lib/mongo
Restart=on-failure
RestartSec=5
LimitNOFILE=64000

[Install]
WantedBy=multi-user.target
SVC1
sed -i "s/MONGO_PORT_PLACEHOLDER/${MONGO_PORT}/" /etc/systemd/system/itagent-db.service
ok "itagent-db.service (MongoDB)"

# wait-mongo 腳本
cat > /usr/local/bin/wait-mongo.sh << 'WAIT'
#!/bin/bash
for i in $(seq 1 30); do
    mongosh --eval "db.runCommand({ping:1})" --quiet 2>/dev/null | grep -q '"ok" : 1' && exit 0
    sleep 2
done
echo "MongoDB not ready after 60s, proceeding anyway"
WAIT
chmod +x /usr/local/bin/wait-mongo.sh

# itagent-web: Flask
cat > /etc/systemd/system/itagent-web.service << SVC2
[Unit]
Description=ITAgent Flask Web Application
After=itagent-db.service network.target
Wants=itagent-db.service

[Service]
Type=simple
User=root
EnvironmentFile=/etc/default/itagent
ExecStartPre=/usr/local/bin/wait-mongo.sh
ExecStart=/bin/bash -c 'cd ${INSTALL_DIR}/webapp && /usr/bin/python3 app.py'
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SVC2
ok "itagent-web.service (Flask)"

# itagent-tunnel: Cloudflare（可選）
cat > /etc/systemd/system/itagent-tunnel.service << SVC3
[Unit]
Description=ITAgent Cloudflare Quick Tunnel
After=itagent-web.service
Wants=itagent-web.service

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --url http://127.0.0.1:${FLASK_PORT}
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC3
ok "itagent-tunnel.service (Cloudflare, 可選)"

# ============================================
# Step 7: 啟動服務 + 初始化資料庫
# ============================================
step "啟動服務並初始化"

systemctl daemon-reload
systemctl enable itagent-db itagent-web 2>/dev/null
ok "服務已設為開機自啟"

# 啟動 MongoDB
systemctl start itagent-db && ok "MongoDB 已啟動" || fail "MongoDB 啟動失敗"
sleep 3

# 初始化 MongoDB
python3 << PYINIT
import sys
try:
    from pymongo import MongoClient
    import bcrypt, datetime, json, os

    client = MongoClient("127.0.0.1", ${MONGO_PORT}, serverSelectionTimeoutMS=5000)
    client.admin.command("ping")
    db = client["inspection"]

    # 匯入預設設定
    settings_path = "${INSTALL_DIR}/data/settings.json"
    if os.path.exists(settings_path):
        with open(settings_path) as f:
            settings = json.load(f)
        if "thresholds" in settings:
            db.settings.update_one({"key": "thresholds"}, {"\$set": {"key": "thresholds", "value": settings["thresholds"]}}, upsert=True)
        for k, v in settings.items():
            if k != "thresholds":
                db.settings.update_one({"key": k}, {"\$set": {"key": k, "value": v}}, upsert=True)
        print("  \033[32m✓\033[0m 匯入設定檔")

    # 建立 superadmin 帳號
    if not db.users.find_one({"username": "superadmin"}):
        hashed = bcrypt.hashpw("${ADMIN_PW}".encode(), bcrypt.gensalt()).decode()
        db.users.insert_one({
            "username": "superadmin",
            "password": hashed,
            "role": "superadmin",
            "display_name": "超級管理員",
            "created_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        })
        print("  \033[32m✓\033[0m superadmin 帳號已建立")
    else:
        print("  \033[32m✓\033[0m superadmin 帳號已存在")

    # 建立 oper 唯讀帳號
    if not db.users.find_one({"username": "oper"}):
        hashed = bcrypt.hashpw("oper".encode(), bcrypt.gensalt()).decode()
        db.users.insert_one({
            "username": "oper",
            "password": hashed,
            "role": "oper",
            "display_name": "唯讀檢視",
            "created_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        })
        print("  \033[32m✓\033[0m oper 唯讀帳號已建立 (密碼: oper)")
    else:
        print("  \033[32m✓\033[0m oper 帳號已存在")

    # 建立 MongoDB 索引
    db.hosts.create_index("hostname", unique=True)
    db.inspections.create_index([("hostname", 1), ("run_date", -1)])
    db.inspections.create_index("run_id")
    db.users.create_index("username", unique=True)
    print("  \033[32m✓\033[0m MongoDB 索引已建立")

except Exception as e:
    print(f"  \033[31m✗\033[0m 初始化失敗: {e}")
    sys.exit(1)
PYINIT

# 啟動 Flask
systemctl start itagent-web && ok "Flask 已啟動" || fail "Flask 啟動失敗"

# 等待 HTTP 回應
HTTP_OK=false
for i in $(seq 1 15); do
    if curl -s -o /dev/null http://127.0.0.1:${FLASK_PORT}/ 2>/dev/null; then
        ok "HTTP 200 OK (port ${FLASK_PORT})"
        HTTP_OK=true
        break
    fi
    sleep 2
done
$HTTP_OK || warn "HTTP 尚未回應，請稍後檢查: systemctl status itagent-web"

# ============================================
# Step 8: 設定排程與防火牆
# ============================================
step "設定排程與防火牆"

# 建立巡檢排程
CRON_ENTRIES=""
IFS=',' read -ra TIMES <<< "${CRON_TIMES}"
for t in "${TIMES[@]}"; do
    t=$(echo "$t" | xargs)
    HOUR=$(echo "$t" | cut -d: -f1)
    MIN=$(echo "$t" | cut -d: -f2)
    CRON_ENTRIES="${CRON_ENTRIES}${MIN} ${HOUR} * * * ${INSTALL_DIR}/run_inspection.sh >> ${INSTALL_DIR}/logs/cron.log 2>&1\n"
done
(crontab -l 2>/dev/null | grep -v run_inspection; echo -e "${CRON_ENTRIES}") | crontab -
ok "巡檢排程: ${CRON_TIMES}"

# 防火牆（如果有 firewalld）
if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
    firewall-cmd --add-port=${FLASK_PORT}/tcp --permanent 2>/dev/null
    firewall-cmd --reload 2>/dev/null
    ok "防火牆已開放 port ${FLASK_PORT}"
else
    warn "firewalld 未啟動，跳過防火牆設定"
fi

# ============================================
# 安裝完成
# ============================================
echo ""
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ 安裝完成！v${VERSION}${NC}"
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo ""
echo -e "  管理網址:   ${CYAN}http://${IP}:${FLASK_PORT}${NC}"
echo -e "  管理後台:   ${CYAN}http://${IP}:${FLASK_PORT}/admin${NC}"
echo -e "  管理帳號:   ${BOLD}superadmin${NC} / (您設定的密碼)"
echo -e "  唯讀帳號:   ${BOLD}oper${NC} / ${BOLD}oper${NC}"
echo -e "  服務管理:   ${BOLD}itagent status${NC}"
echo ""
echo -e "  安裝目錄:   ${INSTALL_DIR}"
echo -e "  備份目錄:   ${BACKUP_DIR}"
echo -e "  巡檢排程:   ${CRON_TIMES}"
echo ""
echo -e "  ${BOLD}下一步（建議流程）：${NC}"
echo -e "  1. ${BOLD}匯入主機清單${NC}："
echo -e "     cp ${INSTALL_DIR}/data/hosts_config.template.json ${INSTALL_DIR}/data/hosts_config.json"
echo -e "     vi ${INSTALL_DIR}/data/hosts_config.json   # 填入你的主機"
echo -e "  2. ${BOLD}分發 SSH 公鑰到目標主機${NC}："
echo -e "     ssh-copy-id -i ${INSTALL_DIR}/.ssh/ansible_svc_key.pub ansible_svc@<目標主機>"
echo -e "  3. ${BOLD}執行首次啟動引導${NC}："
echo -e "     ${INSTALL_DIR}/first_run.sh"
echo ""
echo -e "  ${YELLOW}⚠ 請立即修改 oper 預設密碼（Admin UI → 使用者管理）${NC}"
echo ""
