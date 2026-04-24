#!/bin/bash
###############################################
#  v3.11.22.2 hot-fix installer
#  修 playbook 第二層 hardcode INSPECTION_HOME
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

# auto-detect inspection home
if [ -n "${INSPECTION_HOME:-}" ]; then
    HOME_DIR="$INSPECTION_HOME"
elif [ -f "/opt/inspection/data/version.json" ]; then
    HOME_DIR="/opt/inspection"
elif [ -f "/seclog/AI/inspection/data/version.json" ]; then
    HOME_DIR="/seclog/AI/inspection"
else
    fail "找不到 inspection home"
fi

BACKUP_DIR="/var/backups/inspection/pre_v3.11.22.2_${TS}"

echo ""
echo -e "${CYAN}+====================================================+${NC}"
echo -e "${CYAN}|  v3.11.22.2 hot-fix (playbook hardcode INSPECTION)  |${NC}"
echo -e "${CYAN}+====================================================+${NC}"
info "目標: $HOME_DIR"

# [0] 前置
[ "$(id -u)" -eq 0 ] || fail "需 root / sudo"
[ -f "$SRC_DIR/webapp/routes/api_deep_check.py" ] || fail "缺 api_deep_check.py"
[ -f "$SRC_DIR/ansible/playbooks/deep_check.yml" ] || fail "缺 deep_check.yml"

# [1] 備份
mkdir -p "$BACKUP_DIR"
cp -p "$HOME_DIR/webapp/routes/api_deep_check.py" "$BACKUP_DIR/" 2>/dev/null && ok "api_deep_check.py → bak"
cp -p "$HOME_DIR/ansible/playbooks/deep_check.yml" "$BACKUP_DIR/" 2>/dev/null && ok "deep_check.yml → bak"
cp -p "$HOME_DIR/data/version.json" "$BACKUP_DIR/" && ok "version.json → bak"
info "備份: $BACKUP_DIR"

# [2] 清可能殘留在 /seclog/AI/inspection/data/ 的 deep_check 殘檔 (若 /seclog 是誤建的)
if [ -d "/seclog/AI/inspection/data/deep_check_reports" ] && [ "$HOME_DIR" != "/seclog/AI/inspection" ]; then
    SECLOG_RESIDUAL=$(ls /seclog/AI/inspection/data/deep_check_reports/ 2>/dev/null | wc -l)
    if [ "$SECLOG_RESIDUAL" -gt 0 ]; then
        info "發現 /seclog/AI/inspection/data/deep_check_reports 有 ${SECLOG_RESIDUAL} 個殘檔 (疑似第一次誤寫)"
        info "搬到 $HOME_DIR/data/deep_check_reports/ 保留歷史..."
        mkdir -p "$HOME_DIR/data/deep_check_reports"
        mv /seclog/AI/inspection/data/deep_check_reports/* "$HOME_DIR/data/deep_check_reports/" 2>/dev/null || true
    fi
fi

# [3] 複製新檔
OWNER=$(stat -c "%U:%G" "$HOME_DIR/webapp/app.py")
cp "$SRC_DIR/webapp/routes/api_deep_check.py" "$HOME_DIR/webapp/routes/api_deep_check.py" && chown "$OWNER" "$HOME_DIR/webapp/routes/api_deep_check.py" && ok "api_deep_check.py"
cp "$SRC_DIR/ansible/playbooks/deep_check.yml" "$HOME_DIR/ansible/playbooks/deep_check.yml" && chown "$OWNER" "$HOME_DIR/ansible/playbooks/deep_check.yml" && ok "deep_check.yml"
cp "$SRC_DIR/data/version.json" "$HOME_DIR/data/version.json" && chown "$OWNER" "$HOME_DIR/data/version.json" && ok "version.json → 3.11.22.2"

# [4] 語法 / yaml 驗證
python3 -c "import ast; ast.parse(open('$HOME_DIR/webapp/routes/api_deep_check.py').read())" 2>&1 || fail "py syntax"
python3 -c "import yaml; yaml.safe_load(open('$HOME_DIR/ansible/playbooks/deep_check.yml'))" 2>&1 || fail "yaml syntax"
ok "py + yaml 語法通過"

# [5] restart
for svc in itagent-web inspection inspection-web; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" && ok "systemctl restart $svc" && break
    fi
done
sleep 2

# [6] 驗證
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5000/api/deep-check/reports" 2>/dev/null || echo "000")
case "$HTTP_CODE" in
    200|302|401) ok "API 回應 $HTTP_CODE" ;;
    *)           warn "API 回應 $HTTP_CODE" ;;
esac

NEW_VERSION=$(cat "$HOME_DIR/data/version.json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])' 2>/dev/null || echo "?")
[ "$NEW_VERSION" = "3.11.22.2" ] && ok "版本 $NEW_VERSION" || warn "版本: $NEW_VERSION"

echo ""
echo -e "${GREEN}v3.11.22.2 hot-fix 安裝完成!${NC}"
echo "瀏覽器 Ctrl+F5 /report → 再點深度檢查 (011T 或 014T) 試試"
echo ""
echo "Rollback:"
echo "  sudo cp -p $BACKUP_DIR/api_deep_check.py $HOME_DIR/webapp/routes/"
echo "  sudo cp -p $BACKUP_DIR/deep_check.yml $HOME_DIR/ansible/playbooks/"
echo "  sudo cp -p $BACKUP_DIR/version.json $HOME_DIR/data/"
echo "  sudo systemctl restart itagent-web"
