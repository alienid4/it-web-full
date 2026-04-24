#!/bin/bash
set -u
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}OK${NC}   $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; exit 1; }
info() { echo -e "  ${CYAN}-->${NC}  $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/files"
TS=$(date +%Y%m%d_%H%M%S)

if [ -n "${INSPECTION_HOME:-}" ]; then HOME_DIR="$INSPECTION_HOME"
elif [ -f /opt/inspection/data/version.json ]; then HOME_DIR=/opt/inspection
elif [ -f /seclog/AI/inspection/data/version.json ]; then HOME_DIR=/seclog/AI/inspection
else fail "找不到 inspection home"; fi

BACKUP_DIR="/var/backups/inspection/pre_v3.11.25.0_${TS}"
[ "$(id -u)" -eq 0 ] || fail "需 root"
info "目標: $HOME_DIR"

mkdir -p "$BACKUP_DIR"
cp -p "$HOME_DIR/webapp/routes/api_deep_check.py" "$BACKUP_DIR/" 2>/dev/null && ok "api_deep_check.py → bak"
cp -p "$HOME_DIR/webapp/templates/report.html" "$BACKUP_DIR/" 2>/dev/null && ok "report.html → bak"
cp -p "$HOME_DIR/data/version.json" "$BACKUP_DIR/" && ok "version.json → bak"

OWNER=$(stat -c "%U:%G" "$HOME_DIR/webapp/app.py")
cp "$SRC_DIR/webapp/routes/api_deep_check.py" "$HOME_DIR/webapp/routes/" && chown "$OWNER" "$HOME_DIR/webapp/routes/api_deep_check.py" && ok "api_deep_check.py"
cp "$SRC_DIR/webapp/templates/report.html" "$HOME_DIR/webapp/templates/" && chown "$OWNER" "$HOME_DIR/webapp/templates/report.html" && ok "report.html"
cp "$SRC_DIR/data/version.json" "$HOME_DIR/data/version.json" && chown "$OWNER" "$HOME_DIR/data/version.json" && ok "version.json → 3.11.25.0"

python3 -c "import ast; ast.parse(open('$HOME_DIR/webapp/routes/api_deep_check.py').read())" 2>&1 || fail "py syntax"
ok "py 語法通過"

for svc in itagent-web inspection inspection-web; do
    systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service" && systemctl restart "$svc" && ok "restart $svc" && break
done
sleep 2

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5000/api/deep-check/history" 2>/dev/null || echo "000")
case "$HTTP_CODE" in
    200|302|401) ok "history API $HTTP_CODE" ;;
    *)           echo -e "  ${YELLOW}WARN${NC} history API $HTTP_CODE" ;;
esac

echo ""
echo -e "${GREEN}v3.11.25.0 安裝完成!${NC}"
echo "測試: Ctrl+Shift+R /report → 點深度檢查 → 確認畫面上方應列出歷史紀錄 (若之前跑過)"
echo ""
echo "Rollback:"
echo "  sudo cp -p $BACKUP_DIR/api_deep_check.py $HOME_DIR/webapp/routes/"
echo "  sudo cp -p $BACKUP_DIR/report.html $HOME_DIR/webapp/templates/"
echo "  sudo cp -p $BACKUP_DIR/version.json $HOME_DIR/data/"
echo "  sudo systemctl restart itagent-web"
