#!/bin/bash
###############################################
#  v3.11.23.0 深度檢查視覺化 + 180 天保留
#  Usage: sudo ./install.sh
###############################################
set -u
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}OK${NC}   $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; exit 1; }
info() { echo -e "  ${CYAN}-->${NC}  $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/files"
TS=$(date +%Y%m%d_%H%M%S)

if [ -n "${INSPECTION_HOME:-}" ]; then
    HOME_DIR="$INSPECTION_HOME"
elif [ -f "/opt/inspection/data/version.json" ]; then
    HOME_DIR="/opt/inspection"
elif [ -f "/seclog/AI/inspection/data/version.json" ]; then
    HOME_DIR="/seclog/AI/inspection"
else
    fail "找不到 inspection home"
fi

BACKUP_DIR="/var/backups/inspection/pre_v3.11.23.0_${TS}"
CRON_FILE="/etc/cron.d/inspection-deep-check-cleanup"

echo ""
echo -e "${CYAN}+====================================================+${NC}"
echo -e "${CYAN}|  v3.11.23.0 深度檢查視覺化 + 180 天保留             |${NC}"
echo -e "${CYAN}+====================================================+${NC}"
info "目標: $HOME_DIR"

# [0] 前置
[ "$(id -u)" -eq 0 ] || fail "需 root / sudo"
[ -f "$SRC_DIR/webapp/routes/api_deep_check.py" ] || fail "缺 api_deep_check.py"
[ -f "$SRC_DIR/webapp/templates/report.html" ] || fail "缺 report.html"

# [1] 備份
mkdir -p "$BACKUP_DIR"
cp -p "$HOME_DIR/webapp/routes/api_deep_check.py" "$BACKUP_DIR/" 2>/dev/null && ok "api_deep_check.py → bak"
cp -p "$HOME_DIR/webapp/templates/report.html" "$BACKUP_DIR/" 2>/dev/null && ok "report.html → bak"
cp -p "$HOME_DIR/data/version.json" "$BACKUP_DIR/" && ok "version.json → bak"
[ -f "$CRON_FILE" ] && cp -p "$CRON_FILE" "$BACKUP_DIR/" && ok "舊 cron → bak"
info "備份: $BACKUP_DIR"

# [2] 複製新檔
OWNER=$(stat -c "%U:%G" "$HOME_DIR/webapp/app.py")
cp "$SRC_DIR/webapp/routes/api_deep_check.py" "$HOME_DIR/webapp/routes/" && chown "$OWNER" "$HOME_DIR/webapp/routes/api_deep_check.py" && ok "api_deep_check.py"
cp "$SRC_DIR/webapp/templates/report.html" "$HOME_DIR/webapp/templates/" && chown "$OWNER" "$HOME_DIR/webapp/templates/report.html" && ok "report.html"
cp "$SRC_DIR/data/version.json" "$HOME_DIR/data/version.json" && chown "$OWNER" "$HOME_DIR/data/version.json" && ok "version.json → 3.11.23.0"

# 語法驗證
python3 -c "import ast; ast.parse(open('$HOME_DIR/webapp/routes/api_deep_check.py').read())" 2>&1 || fail "py syntax"
ok "py 語法通過"

# [3] 180 天保留 cron
cat > "$CRON_FILE" <<EOF
# v3.11.23.0: 每天 03:00 清 180 天前的深度檢查報告
# (summary.txt + detail.txt 兩種檔名 pattern)
0 3 * * * root find $HOME_DIR/data/deep_check_reports -name 'ts_*_*.txt' -type f -mtime +180 -delete 2>/dev/null
EOF
chmod 644 "$CRON_FILE"
ok "cron 已裝: $CRON_FILE (每天 03:00 清 180 天前)"

# [4] restart
for svc in itagent-web inspection inspection-web; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" && ok "systemctl restart $svc" && break
    fi
done
sleep 2

# [5] 驗證
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5000/api/deep-check/reports" 2>/dev/null || echo "000")
case "$HTTP_CODE" in
    200|302|401) ok "API 回應 $HTTP_CODE" ;;
    *)           warn "API 回應 $HTTP_CODE" ;;
esac

NEW_VERSION=$(cat "$HOME_DIR/data/version.json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])' 2>/dev/null || echo "?")
[ "$NEW_VERSION" = "3.11.23.0" ] && ok "版本 $NEW_VERSION" || warn "版本: $NEW_VERSION"

echo ""
echo -e "${GREEN}v3.11.23.0 安裝完成!${NC}"
echo ""
echo -e "${CYAN}測試${NC}:"
echo "  1. 瀏覽器 Ctrl+F5 /report"
echo "  2. 點任一 Linux 卡片「🔍 深度檢查」→ 開始執行"
echo "  3. 完成後 modal 應顯示: 大燈狀態 + 4 KPI + 9 矩陣 (WARN/FAIL 自動展開)"
echo "  4. 點任一項目展開看 檢查範圍/基準/實測/建議動作"
echo "  5. 底下仍可下載 raw summary/detail"
echo ""
echo -e "${CYAN}Cron${NC}:"
echo "  $CRON_FILE"
echo "  每天 03:00 清 $HOME_DIR/data/deep_check_reports 底下 180 天前的舊報告"
echo ""
echo -e "${CYAN}Rollback${NC}:"
echo "  sudo cp -p $BACKUP_DIR/api_deep_check.py $HOME_DIR/webapp/routes/"
echo "  sudo cp -p $BACKUP_DIR/report.html $HOME_DIR/webapp/templates/"
echo "  sudo cp -p $BACKUP_DIR/version.json $HOME_DIR/data/"
echo "  sudo rm -f $CRON_FILE"
echo "  sudo systemctl restart itagent-web"
