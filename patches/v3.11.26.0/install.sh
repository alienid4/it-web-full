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

BACKUP_DIR="/var/backups/inspection/pre_v3.11.26.0_${TS}"
[ "$(id -u)" -eq 0 ] || fail "需 root"
info "目標: $HOME_DIR"

mkdir -p "$BACKUP_DIR"
cp -p "$HOME_DIR/webapp/templates/report.html" "$BACKUP_DIR/" && ok "report.html → bak"
cp -p "$HOME_DIR/data/version.json" "$BACKUP_DIR/" && ok "version.json → bak"

OWNER=$(stat -c "%U:%G" "$HOME_DIR/webapp/app.py")
cp "$SRC_DIR/webapp/templates/report.html" "$HOME_DIR/webapp/templates/" && chown "$OWNER" "$HOME_DIR/webapp/templates/report.html" && ok "report.html"
cp "$SRC_DIR/data/version.json" "$HOME_DIR/data/version.json" && chown "$OWNER" "$HOME_DIR/data/version.json" && ok "version.json → 3.11.26.0"

for svc in itagent-web inspection inspection-web; do
    systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service" && systemctl restart "$svc" && ok "restart $svc" && break
done

echo ""
echo -e "${GREEN}v3.11.26.0 安裝完成!${NC}"
echo "測試: Ctrl+Shift+R /report → 深度檢查 → 查看任一歷史 → 點「📊 對照其他」→ 挑另一版 → 看並列對照"
echo ""
echo "Rollback:"
echo "  sudo cp -p $BACKUP_DIR/report.html $HOME_DIR/webapp/templates/"
echo "  sudo cp -p $BACKUP_DIR/version.json $HOME_DIR/data/"
echo "  sudo systemctl restart itagent-web"
