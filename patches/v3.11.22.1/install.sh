#!/bin/bash
###############################################
#  v3.11.22.1 hot-fix installer
#  修 api_deep_check.py hardcode INSPECTION_HOME=/seclog/AI/inspection 的 bug
#  改為 auto-detect (優先 env var, 後備 /opt/inspection or /seclog/AI/inspection)
#
#  Usage: sudo ./install.sh
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

# 自動偵測 inspection home
if [ -n "${INSPECTION_HOME:-}" ]; then
    HOME_DIR="$INSPECTION_HOME"
elif [ -f "/opt/inspection/data/version.json" ]; then
    HOME_DIR="/opt/inspection"
elif [ -f "/seclog/AI/inspection/data/version.json" ]; then
    HOME_DIR="/seclog/AI/inspection"
else
    fail "找不到 inspection home (試過 /opt/inspection 和 /seclog/AI/inspection)"
fi

BACKUP_DIR="/var/backups/inspection/pre_v3.11.22.1_${TS}"

echo ""
echo -e "${CYAN}+====================================================+${NC}"
echo -e "${CYAN}|  v3.11.22.1 hot-fix (PermissionError /seclog/AI)    |${NC}"
echo -e "${CYAN}+====================================================+${NC}"
info "目標: $HOME_DIR"

# ========== [0] 前置 ==========
echo -e "${BOLD}[0/4] 前置檢查${NC}"
[ "$(id -u)" -eq 0 ] || fail "需 root / sudo"
[ -f "$SRC_DIR/webapp/routes/api_deep_check.py" ] || fail "缺 api_deep_check.py"
[ -f "$SRC_DIR/data/version.json" ] || fail "缺 version.json"
CUR_VER=$(cat "$HOME_DIR/data/version.json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])' 2>/dev/null || echo "unknown")
info "目前版本: $CUR_VER"
ok "就緒"

# ========== [1] 備份 ==========
echo -e "${BOLD}[1/4] 備份${NC}"
mkdir -p "$BACKUP_DIR"
cp -p "$HOME_DIR/webapp/routes/api_deep_check.py" "$BACKUP_DIR/" 2>/dev/null && ok "api_deep_check.py → 備份"
cp -p "$HOME_DIR/data/version.json" "$BACKUP_DIR/" && ok "version.json → 備份"
info "備份: $BACKUP_DIR"

# ========== [2] 複製新檔 ==========
echo -e "${BOLD}[2/4] 複製新檔${NC}"
OWNER=$(stat -c "%U:%G" "$HOME_DIR/webapp/app.py")
cp "$SRC_DIR/webapp/routes/api_deep_check.py" "$HOME_DIR/webapp/routes/api_deep_check.py" || fail "api_deep_check.py"
chown "$OWNER" "$HOME_DIR/webapp/routes/api_deep_check.py"
ok "api_deep_check.py (owner: $OWNER)"

cp "$SRC_DIR/data/version.json" "$HOME_DIR/data/version.json" || fail "version.json"
chown "$OWNER" "$HOME_DIR/data/version.json"
ok "version.json → 3.11.22.1"

# 語法驗證
python3 -c "import ast; ast.parse(open('$HOME_DIR/webapp/routes/api_deep_check.py').read())" 2>&1 || fail "api_deep_check.py 語法錯誤"
ok "語法通過"

# ========== [3] Restart Flask ==========
echo -e "${BOLD}[3/4] 重啟 Flask${NC}"
for svc in itagent-web inspection inspection-web; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" && ok "systemctl restart $svc" && break
    fi
done
sleep 2

# ========== [4] 驗證 ==========
echo -e "${BOLD}[4/4] 驗證${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5000/api/deep-check/reports" 2>/dev/null || echo "000")
case "$HTTP_CODE" in
    200|302|401) ok "API endpoint 回應 $HTTP_CODE" ;;
    *)           warn "API 回應 $HTTP_CODE" ;;
esac

NEW_VERSION=$(cat "$HOME_DIR/data/version.json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])' 2>/dev/null || echo "?")
[ "$NEW_VERSION" = "3.11.22.1" ] && ok "版本 $NEW_VERSION" || warn "版本異常: $NEW_VERSION"

echo ""
echo -e "${GREEN}${BOLD}===========================================${NC}"
echo -e "${GREEN}${BOLD}  v3.11.22.1 hot-fix 安裝完成!${NC}"
echo -e "${GREEN}${BOLD}===========================================${NC}"
echo ""
echo -e "${BOLD}測試${NC}: 瀏覽器 Ctrl+F5 /report → 點深度檢查 (011T 或 014T) → 應正常執行"
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo "  sudo cp -p $BACKUP_DIR/api_deep_check.py $HOME_DIR/webapp/routes/"
echo "  sudo cp -p $BACKUP_DIR/version.json $HOME_DIR/data/"
echo "  sudo systemctl restart itagent-web"
