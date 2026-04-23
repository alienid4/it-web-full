#!/bin/bash
###############################################
#  v3.11.21.0 combo pack installer
#  裝 onboard_new_host.sh + 更新 version.json + restart
#  Usage: sudo ./install.sh
###############################################
set -u

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"
CYAN="\033[0;36m"; BOLD="\033[1m"; NC="\033[0m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSPECTION_HOME="${INSPECTION_HOME:-/opt/inspection}"
TS=$(date +%Y%m%d_%H%M)

ok()   { echo -e "  ${GREEN}OK${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; exit 1; }
info() { echo -e "  ${CYAN}-->${NC} $1"; }

echo ""
echo -e "${CYAN}+==========================================+${NC}"
echo -e "${CYAN}|  v3.11.21.0 combo pack installer         |${NC}"
echo -e "${CYAN}+==========================================+${NC}"
echo ""
info "來源: $SCRIPT_DIR/files/"
info "目標: $INSPECTION_HOME"
echo ""

# ========== 1. onboard_new_host.sh ==========
echo -e "${CYAN}--- [1/3] onboard_new_host.sh ---${NC}"
SRC_ONBOARD="$SCRIPT_DIR/files/scripts/onboard_new_host.sh"
DST_ONBOARD="$INSPECTION_HOME/scripts/onboard_new_host.sh"
[ -f "$SRC_ONBOARD" ] || fail "找不到 $SRC_ONBOARD"

# 驗證來源是新版 (含「方案 X」字樣)
if ! grep -q "方案 X" "$SRC_ONBOARD"; then
    fail "來源 onboard_new_host.sh 不含『方案 X』字樣, tarball 可能損毀"
fi
info "來源驗證通過 (含方案 X)"

# 備份舊版 (若有)
if [ -f "$DST_ONBOARD" ]; then
    sudo cp "$DST_ONBOARD" "${DST_ONBOARD}.bak.${TS}"
    info "舊版備份: ${DST_ONBOARD}.bak.${TS}"
fi

# 覆蓋
sudo cp "$SRC_ONBOARD" "$DST_ONBOARD"
sudo chown sysinfra:itagent "$DST_ONBOARD"
sudo chmod 750 "$DST_ONBOARD"

# 驗證目的地
if grep -q "方案 X" "$DST_ONBOARD"; then
    ok "onboard_new_host.sh v3.11.20.0+ 已就緒"
else
    fail "覆蓋後目的地仍不含『方案 X』, 請檢查權限"
fi

# ========== 2. version.json ==========
echo ""
echo -e "${CYAN}--- [2/3] version.json ---${NC}"
SRC_VER="$SCRIPT_DIR/files/data/version.json"
DST_VER="$INSPECTION_HOME/data/version.json"
[ -f "$SRC_VER" ] || fail "找不到 $SRC_VER"

NEW_VER=$(grep '"version"' "$SRC_VER" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
info "新版本號: $NEW_VER"

sudo cp "$DST_VER" "${DST_VER}.bak.${TS}"
sudo cp "$SRC_VER" "$DST_VER"
sudo chown sysinfra:itagent "$DST_VER"
ok "version.json 已更新 (UI 右下角將顯示 $NEW_VER)"

# ========== 3. restart Flask ==========
echo ""
echo -e "${CYAN}--- [3/3] restart itagent-web ---${NC}"
info "讓 _APP_VER context processor 重讀 version.json..."
sudo systemctl restart itagent-web
sleep 3

HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5000/ 2>/dev/null || echo "000")
if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then
    ok "Flask running (HTTP $HTTP)"
else
    echo -e "  ${YELLOW}WARN${NC} HTTP $HTTP, 可能還沒好, 看: journalctl -u itagent-web -n 30"
fi

# ========== 完成 ==========
echo ""
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}  v3.11.21.0 安裝完成!${NC}"
echo -e "${GREEN}===========================================${NC}"
echo ""
echo -e "${BOLD}驗證${NC}:"
echo -e "  # onboard Usage 應有『方案 X』+ 6 步 (0-6)"
echo -e "  sudo $DST_ONBOARD"
echo ""
echo -e "  # UI 版本號 (右下角)"
echo -e "  開啟 http://\$(hostname -I | awk '{print \$1}'):5000/"
echo ""
echo -e "${BOLD}加第 3 台主機${NC}:"
echo -e "  sudo $DST_ONBOARD <hostname> <ip>"
echo -e "  範例: sudo $DST_ONBOARD SECSVR198-012T 10.92.198.12"
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo -e "  sudo cp ${DST_ONBOARD}.bak.${TS} $DST_ONBOARD"
echo -e "  sudo cp ${DST_VER}.bak.${TS} $DST_VER"
echo -e "  sudo systemctl restart itagent-web"
echo ""
