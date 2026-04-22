#!/bin/bash
# v3.11.5.0 post_install — root → sysinfra 服務切換
# 安全策略：
#   1. in-place 編輯現有 service file（不覆蓋整份，尊重實際 ExecStart）
#   2. 失敗自動還原 backup
#   3. sudoers 先 visudo -c 驗證才安裝
#   4. 最後驗證服務真的以 sysinfra 執行
set -u

R=$'\e[0;31m'; G=$'\e[0;32m'; Y=$'\e[1;33m'; C=$'\e[0;36m'; N=$'\e[0m'
ok()   { echo -e "    ${G}OK${N} $1"; }
fail() { echo -e "    ${R}FAIL${N} $1"; }
warn() { echo -e "    ${Y}WARN${N} $1"; }
info() { echo -e "    ${C}-->${N} $1"; }

ITAGENT_HOME="${ITAGENT_HOME:-/opt/inspection}"
SVC_FILE="/etc/systemd/system/itagent-web.service"
SUDOERS_FILE="/etc/sudoers.d/sysinfra-inspection"
SVC_USER="sysinfra"
AP_GROUP="itagent"
TS=$(date +%Y%m%d_%H%M%S)

echo -e "${C}=============================================${N}"
echo -e "${C}  v3.11.5.0: 服務切換 root → $SVC_USER${N}"
echo -e "${C}=============================================${N}"

# ========== 1. 前置檢查 ==========
echo -e "\n${C}[1/8] 前置檢查${N}"
if [ "$EUID" -ne 0 ]; then fail "需 root 執行"; exit 1; fi

if ! id "$SVC_USER" >/dev/null 2>&1; then
    fail "$SVC_USER 帳號不存在"
    info "先跑: sudo /opt/inspection/scripts/setup_permissions.sh"
    exit 2
fi
ok "$SVC_USER 帳號存在"

if ! getent group "$AP_GROUP" >/dev/null 2>&1; then
    fail "$AP_GROUP group 不存在"
    info "先跑: sudo /opt/inspection/scripts/setup_permissions.sh"
    exit 3
fi
ok "$AP_GROUP group 存在"

if [ ! -f "$SVC_FILE" ]; then
    fail "找不到 $SVC_FILE"
    exit 4
fi
ok "service file: $SVC_FILE"

# ========== 2. 備份 service file ==========
echo -e "\n${C}[2/8] 備份 service file${N}"
BACKUP="${SVC_FILE}.pre-v3.11.5.0.${TS}.bak"
cp "$SVC_FILE" "$BACKUP"
ok "backup: $BACKUP"

# ========== 3. in-place 加 User/Group ==========
echo -e "\n${C}[3/8] 修改 service file (in-place)${N}"
# 先清掉可能殘留的 User=/Group= (idempotent 重跑也能收斂)
sed -i '/^User=/d' "$SVC_FILE"
sed -i '/^Group=/d' "$SVC_FILE"
# 在 [Service] section 下面加 User= 和 Group=
sed -i "/^\[Service\]/a User=$SVC_USER\nGroup=$AP_GROUP" "$SVC_FILE"
ok "User=$SVC_USER / Group=$AP_GROUP 已加入"

# 顯示差異
echo "    修改後 [Service] section:"
grep -A 3 "^\[Service\]" "$SVC_FILE" | head -5 | sed 's/^/      /'

# ========== 4. 驗證 service file 語法 ==========
echo -e "\n${C}[4/8] systemd 語法驗證${N}"
if systemd-analyze verify "$SVC_FILE" 2>&1 | grep -qi "error\|fail"; then
    fail "service file 驗證失敗，還原中..."
    cp "$BACKUP" "$SVC_FILE"
    exit 5
fi
ok "service file 語法 OK"

# ========== 5. 安裝 sudoers ==========
echo -e "\n${C}[5/8] 安裝 /etc/sudoers.d/sysinfra-inspection${N}"
TMP_SUDO=$(mktemp)
cat > "$TMP_SUDO" <<EOF
# v3.11.5.0 — sysinfra sudo 權限（寬鬆 C 級）
# 重啟自己的服務（patch flow / admin UI 按鈕用）
sysinfra ALL=(root) NOPASSWD: /bin/systemctl restart itagent-web
sysinfra ALL=(root) NOPASSWD: /bin/systemctl start itagent-web
sysinfra ALL=(root) NOPASSWD: /bin/systemctl stop itagent-web
sysinfra ALL=(root) NOPASSWD: /bin/systemctl status itagent-web
# 跑巡檢（UI 手動觸發 / cron 也走這條）
sysinfra ALL=(root) NOPASSWD: $ITAGENT_HOME/run_inspection.sh
EOF

if ! visudo -c -f "$TMP_SUDO" >/dev/null 2>&1; then
    fail "sudoers 語法錯"
    rm -f "$TMP_SUDO"
    exit 6
fi
mv "$TMP_SUDO" "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"
chown root:root "$SUDOERS_FILE"
ok "sudoers 已安裝: $SUDOERS_FILE"

# ========== 6. reload + restart ==========
echo -e "\n${C}[6/8] systemd reload + restart${N}"
systemctl daemon-reload
if systemctl restart itagent-web; then
    ok "服務已重啟"
else
    fail "重啟失敗，還原 service file..."
    cp "$BACKUP" "$SVC_FILE"
    systemctl daemon-reload
    systemctl restart itagent-web
    exit 7
fi
sleep 4

# ========== 7. 驗證 service 確實以 sysinfra 跑 ==========
echo -e "\n${C}[7/8] 驗證執行身分${N}"
PID=$(systemctl show -p MainPID itagent-web | cut -d= -f2)
if [ -z "$PID" ] || [ "$PID" = "0" ]; then
    fail "服務未運作 (PID=0)"
    journalctl -u itagent-web -n 20 --no-pager | tail -15 | sed 's/^/    /'
    warn "自動還原 service file..."
    cp "$BACKUP" "$SVC_FILE"
    systemctl daemon-reload
    systemctl restart itagent-web
    exit 8
fi

ACTUAL_USER=$(ps -o user= -p "$PID" 2>/dev/null | tr -d ' ')
if [ "$ACTUAL_USER" = "$SVC_USER" ]; then
    ok "服務以 $SVC_USER 執行 ✓ (PID=$PID)"
else
    warn "服務 PID=$PID 以 '$ACTUAL_USER' 執行（預期 $SVC_USER）"
    info "可能是 ExecStartPre 還沒結束，sleep 5 再確認..."
    sleep 5
    ACTUAL_USER=$(ps -o user= -p "$(systemctl show -p MainPID itagent-web | cut -d= -f2)" 2>/dev/null | tr -d ' ')
    [ "$ACTUAL_USER" = "$SVC_USER" ] && ok "現在是 $SVC_USER ✓" || warn "仍不是 (實際: $ACTUAL_USER)，手動檢查"
fi

# HTTP ping
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5000/ 2>/dev/null || echo "000")
case "$HTTP" in
    200|302) ok "HTTP ping: $HTTP" ;;
    *) warn "HTTP ping: $HTTP（服務可能還沒好）" ;;
esac

# ========== 8. cron 搬家建議 ==========
echo -e "\n${C}[8/8] root cron 檢查${N}"
ROOT_CRON=$(crontab -u root -l 2>/dev/null | grep -E "/opt/inspection/run_inspection.sh" || true)
if [ -z "$ROOT_CRON" ]; then
    info "root crontab 無 run_inspection.sh（可能沒排程或用別名）"
else
    if echo "$ROOT_CRON" | grep -q "su - sysinfra"; then
        ok "root crontab 已經切 sysinfra"
    else
        warn "root crontab 還是直接跑 run_inspection.sh（以 root 身分跑）"
        echo "    目前: $ROOT_CRON"
        echo ""
        echo "    ${C}建議改成${N}（以 sysinfra 執行）:"
        FREQ=$(echo "$ROOT_CRON" | awk '{print $1, $2, $3, $4, $5}')
        echo "    ${FREQ} su - sysinfra -c '$ITAGENT_HOME/run_inspection.sh >> $ITAGENT_HOME/logs/cron.log 2>&1'"
        echo ""
        echo "    ${Y}手動執行${N}: sudo crontab -e"
    fi
fi

echo ""
echo -e "${G}=============================================${N}"
echo -e "${G}  v3.11.5.0 套用完成${N}"
echo -e "${G}=============================================${N}"
echo ""
echo "  Backup: $BACKUP"
echo "  Sudoers: $SUDOERS_FILE"
echo ""
echo "  ${Y}Rollback 指令（若出事）${N}:"
echo "    sudo cp '$BACKUP' '$SVC_FILE'"
echo "    sudo rm '$SUDOERS_FILE'"
echo "    sudo systemctl daemon-reload && sudo systemctl restart itagent-web"
echo ""
echo "  ${C}後續驗證${N}:"
echo "    ps -o user= -p \$(systemctl show -p MainPID itagent-web | cut -d= -f2)"
echo "    sudo -u sysinfra /opt/inspection/run_inspection.sh  # 測 sysinfra 能不能跑"
