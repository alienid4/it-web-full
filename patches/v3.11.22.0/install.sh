#!/bin/bash
###############################################
#  v3.11.22.0 深度檢查功能 installer
#  Usage: sudo ./install.sh
#
#  前置條件: /opt/inspection 或 /seclog/AI/inspection 已裝到 v3.11.21.0+
###############################################
set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}OK${NC}   $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; exit 1; }
info() { echo -e "  ${CYAN}-->${NC}  $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/files"
TS=$(date +%Y%m%d_%H%M%S)

# 自動偵測 inspection home (優先 /opt/inspection, 後備 /seclog/AI/inspection)
if [ -n "${INSPECTION_HOME:-}" ]; then
    HOME_DIR="$INSPECTION_HOME"
elif [ -f "/opt/inspection/data/version.json" ]; then
    HOME_DIR="/opt/inspection"
elif [ -f "/seclog/AI/inspection/data/version.json" ]; then
    HOME_DIR="/seclog/AI/inspection"
else
    fail "找不到 inspection home (試過 /opt/inspection 和 /seclog/AI/inspection, 可用 INSPECTION_HOME= 覆蓋)"
fi

BACKUP_DIR="/var/backups/inspection/pre_v3.11.22.0_${TS}"

echo ""
echo -e "${CYAN}+====================================================+${NC}"
echo -e "${CYAN}|  v3.11.22.0 深度檢查功能 installer                  |${NC}"
echo -e "${CYAN}+====================================================+${NC}"
info "來源: $SRC_DIR"
info "目標: $HOME_DIR"
echo ""

# ========== [0] 前置檢查 ==========
echo -e "${BOLD}[0/8] 前置檢查${NC}"
[ "$(id -u)" -eq 0 ] || fail "需 root / sudo"
[ -d "$SRC_DIR" ] || fail "找不到 files/ 目錄: $SRC_DIR"
[ -d "$HOME_DIR" ] || fail "找不到 $HOME_DIR"
[ -f "$HOME_DIR/webapp/app.py" ] || fail "找不到 $HOME_DIR/webapp/app.py"

CUR_VER=$(cat "$HOME_DIR/data/version.json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])' 2>/dev/null || echo "unknown")
info "目前版本: $CUR_VER"
ok "root / 路徑 / version.json 就緒"

# ========== [1] 內容檢查 ==========
echo -e "${BOLD}[1/8] Patch 內容完整性${NC}"
for f in \
    "$SRC_DIR/webapp/routes/api_deep_check.py" \
    "$SRC_DIR/webapp/templates/report.html" \
    "$SRC_DIR/ansible/playbooks/deep_check.yml" \
    "$SRC_DIR/data/version.json"; do
    [ -f "$f" ] || fail "缺檔: $f"
done
[ -d "$SRC_DIR/scripts/smit_menu" ] || fail "缺目錄: $SRC_DIR/scripts/smit_menu"
SMIT_COUNT=$(find "$SRC_DIR/scripts/smit_menu" -type f | wc -l)
[ "$SMIT_COUNT" -ge 25 ] || fail "smit_menu 檔案不足 (僅 $SMIT_COUNT 個, 預期 25+)"
ok "patch 檔案齊全 (smit_menu: $SMIT_COUNT files)"

# ========== [2] 備份 ==========
echo -e "${BOLD}[2/8] 備份會被動的檔案${NC}"
mkdir -p "$BACKUP_DIR"
cp -p "$HOME_DIR/webapp/app.py" "$BACKUP_DIR/app.py" && ok "app.py → 備份"
cp -p "$HOME_DIR/webapp/templates/report.html" "$BACKUP_DIR/report.html" 2>/dev/null && ok "report.html → 備份"
cp -p "$HOME_DIR/data/version.json" "$BACKUP_DIR/version.json" && ok "version.json → 備份"
info "備份目錄: $BACKUP_DIR"

# ========== [3] 複製新檔 ==========
echo -e "${BOLD}[3/8] 複製新檔${NC}"

cp "$SRC_DIR/webapp/routes/api_deep_check.py" "$HOME_DIR/webapp/routes/api_deep_check.py" || fail "api_deep_check.py"
ok "webapp/routes/api_deep_check.py"

cp "$SRC_DIR/ansible/playbooks/deep_check.yml" "$HOME_DIR/ansible/playbooks/deep_check.yml" || fail "deep_check.yml"
ok "ansible/playbooks/deep_check.yml"

cp "$SRC_DIR/webapp/templates/report.html" "$HOME_DIR/webapp/templates/report.html" || fail "report.html"
ok "webapp/templates/report.html"

rm -rf "$HOME_DIR/scripts/smit_menu"
cp -r "$SRC_DIR/scripts/smit_menu" "$HOME_DIR/scripts/smit_menu" || fail "smit_menu"
find "$HOME_DIR/scripts/smit_menu" -name "*.sh" -exec chmod 750 {} \;
ok "scripts/smit_menu ($(find $HOME_DIR/scripts/smit_menu -type f | wc -l) files)"

cp "$SRC_DIR/data/version.json" "$HOME_DIR/data/version.json" || fail "version.json"
ok "data/version.json → v3.11.22.0"

# ========== [4] 修 app.py (idempotent) ==========
echo -e "${BOLD}[4/8] 修 app.py (加入 deep_check blueprint, idempotent)${NC}"
APP_PY="$HOME_DIR/webapp/app.py"

# [4a] import 行
if grep -q "from routes.api_deep_check import bp as deep_check_bp" "$APP_PY"; then
    info "import 行已存在, 跳過"
else
    # 找 api_cio 的 import 行, 在下面插入
    if grep -q "^from routes\.api_cio import bp as cio_bp" "$APP_PY"; then
        sed -i '/^from routes\.api_cio import bp as cio_bp/a from routes.api_deep_check import bp as deep_check_bp' "$APP_PY"
    else
        # 後備: 插在最後一個 from routes. import 後面
        LAST_IMPORT_LINE=$(grep -n "^from routes\." "$APP_PY" | tail -1 | cut -d: -f1)
        [ -n "$LAST_IMPORT_LINE" ] || fail "找不到任何 'from routes.' import 行"
        sed -i "${LAST_IMPORT_LINE}a from routes.api_deep_check import bp as deep_check_bp" "$APP_PY"
    fi
    grep -q "from routes.api_deep_check import bp as deep_check_bp" "$APP_PY" || fail "import 行插入失敗"
    ok "import 行已加入"
fi

# [4b] register_blueprint 行
if grep -q "app.register_blueprint(deep_check_bp)" "$APP_PY"; then
    info "register 行已存在, 跳過"
else
    if grep -q "^app\.register_blueprint(cio_bp)" "$APP_PY"; then
        sed -i '/^app\.register_blueprint(cio_bp)/a app.register_blueprint(deep_check_bp)' "$APP_PY"
    else
        LAST_REG_LINE=$(grep -n "^app\.register_blueprint(" "$APP_PY" | tail -1 | cut -d: -f1)
        [ -n "$LAST_REG_LINE" ] || fail "找不到任何 'app.register_blueprint(' 行"
        sed -i "${LAST_REG_LINE}a app.register_blueprint(deep_check_bp)" "$APP_PY"
    fi
    grep -q "app.register_blueprint(deep_check_bp)" "$APP_PY" || fail "register 行插入失敗"
    ok "register 行已加入"
fi

# [4c] 語法檢查
python3 -c "import ast; ast.parse(open('$APP_PY').read())" 2>&1 || fail "app.py 語法錯誤"
ok "app.py 語法通過"

# ========== [5] 修權限 ==========
echo -e "${BOLD}[5/8] 修權限${NC}"
# 自動偵測 owner 從現有檔案
OWNER=$(stat -c "%U:%G" "$HOME_DIR/webapp/app.py")
info "檔案 owner: $OWNER"
chown "$OWNER" \
    "$HOME_DIR/webapp/routes/api_deep_check.py" \
    "$HOME_DIR/webapp/templates/report.html" \
    "$HOME_DIR/webapp/app.py" \
    "$HOME_DIR/ansible/playbooks/deep_check.yml" \
    "$HOME_DIR/data/version.json" 2>/dev/null
chown -R "$OWNER" "$HOME_DIR/scripts/smit_menu" 2>/dev/null
mkdir -p "$HOME_DIR/data/deep_check_reports" "$HOME_DIR/data/deep_check_progress"
chown "$OWNER" "$HOME_DIR/data/deep_check_reports" "$HOME_DIR/data/deep_check_progress"
chmod 755 "$HOME_DIR/data/deep_check_reports" "$HOME_DIR/data/deep_check_progress"
ok "權限 + 報告/進度目錄已建"

# ========== [6] 重啟 Flask ==========
echo -e "${BOLD}[6/8] 重啟 Flask${NC}"
RESTARTED=0
for svc in itagent-web inspection inspection-web; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" && ok "systemctl restart $svc" && RESTARTED=1 && break
    fi
done

if [ "$RESTARTED" -eq 0 ]; then
    # 沒 systemd service, 直接 kill + relaunch gunicorn
    OLD_PIDS=$(pgrep -f "gunicorn.*app:app" || true)
    if [ -n "$OLD_PIDS" ]; then
        info "kill 舊 gunicorn: $OLD_PIDS"
        kill $OLD_PIDS 2>/dev/null || true
        sleep 3
        REMAIN=$(pgrep -f "gunicorn.*app:app" || true)
        [ -n "$REMAIN" ] && { kill -9 $REMAIN 2>/dev/null || true; sleep 1; }
        # 從原本 ps 抓啟動參數 (簡化版)
        OWNER_USER=$(echo "$OWNER" | cut -d: -f1)
        mkdir -p "$HOME_DIR/logs"; chown "$OWNER_USER" "$HOME_DIR/logs"
        sudo -u "$OWNER_USER" bash -c "cd $HOME_DIR/webapp && nohup /usr/local/bin/gunicorn -w 4 -b 127.0.0.1:5000 --timeout 300 --graceful-timeout 30 --access-logfile - --error-logfile - app:app > $HOME_DIR/logs/gunicorn.log 2>&1 &"
        sleep 3
        NEW_PID=$(pgrep -f "gunicorn.*app:app" | head -1)
        [ -n "$NEW_PID" ] && ok "gunicorn 已重啟 (pid=$NEW_PID)" || warn "gunicorn 沒起來, 看 $HOME_DIR/logs/gunicorn.log"
    else
        warn "沒 systemd service 也沒 gunicorn 在跑, 請手動啟動 Flask"
    fi
fi

sleep 2

# ========== [7] 驗證 ==========
echo -e "${BOLD}[7/8] 驗證${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5000/api/deep-check/reports" 2>/dev/null || echo "000")
case "$HTTP_CODE" in
    200|302|401) ok "API endpoint 回應 $HTTP_CODE (blueprint 已載入)" ;;
    404)         warn "API endpoint 404 — blueprint 可能未載入, 看 error log" ;;
    000)         warn "Flask 未回應, 手動啟動看看" ;;
    *)           warn "API 回應 $HTTP_CODE (預期 200/302/401)" ;;
esac

NEW_VERSION=$(cat "$HOME_DIR/data/version.json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])' 2>/dev/null || echo "?")
[ "$NEW_VERSION" = "3.11.22.0" ] && ok "版本顯示 $NEW_VERSION" || warn "版本異常: $NEW_VERSION"

# ========== [8] 完成 ==========
echo ""
echo -e "${GREEN}${BOLD}====================================================${NC}"
echo -e "${GREEN}${BOLD}  v3.11.22.0 深度檢查功能 安裝完成!${NC}"
echo -e "${GREEN}${BOLD}====================================================${NC}"
echo ""
echo -e "${BOLD}驗證方式${NC}:"
echo "  1. 瀏覽器 http://\$(hostname -I | awk '{print \$1}'):5000/report"
echo "  2. 今日報告頁 Linux 卡片右下應有 [🔍 深度檢查] 按鈕"
echo "  3. 點按鈕 → Modal → 執行 → 30-60 秒後顯示 summary 預覽"
echo ""
echo -e "${BOLD}已知限制${NC}:"
echo "  - Controller 自身 (安裝此系統的主機) 無法深度檢查, 按鈕不顯示"
echo "  - 受監控主機需有 passwordless sudo 給 sysinfra (onboarding 標配)"
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo "  sudo cp $BACKUP_DIR/app.py $HOME_DIR/webapp/app.py"
echo "  sudo cp $BACKUP_DIR/report.html $HOME_DIR/webapp/templates/report.html"
echo "  sudo cp $BACKUP_DIR/version.json $HOME_DIR/data/version.json"
echo "  sudo rm -f $HOME_DIR/webapp/routes/api_deep_check.py"
echo "  sudo rm -f $HOME_DIR/ansible/playbooks/deep_check.yml"
echo "  sudo rm -rf $HOME_DIR/scripts/smit_menu"
echo "  # 重啟 Flask (systemctl restart itagent-web 或其他)"
echo ""
