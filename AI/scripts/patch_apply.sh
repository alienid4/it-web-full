#!/bin/bash
###############################################
#  ITAgent Patch Apply Script
#  Usage: ./patch_apply.sh
#  Put this script + patch files in same dir
###############################################
set -e

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"
CYAN="\033[0;36m"; BOLD="\033[1m"; NC="\033[0m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ok()   { echo -e "  ${GREEN}OK${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; exit 1; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }

# Read ITAGENT_HOME
if [ -f /etc/default/itagent ]; then
    source /etc/default/itagent
else
    fail "/etc/default/itagent not found. Is ITAgent installed?"
fi

[ -d "$ITAGENT_HOME" ] || fail "ITAGENT_HOME=$ITAGENT_HOME not found"

# Read patch info
[ -f "$SCRIPT_DIR/patch_info.txt" ] || fail "patch_info.txt not found"
PATCH_VER=$(grep "^VERSION=" "$SCRIPT_DIR/patch_info.txt" | cut -d= -f2)
PATCH_DESC=$(grep "^DESC=" "$SCRIPT_DIR/patch_info.txt" | cut -d= -f2-)
PATCH_FILES=$(grep "^FILES=" "$SCRIPT_DIR/patch_info.txt" | cut -d= -f2-)

echo ""
echo -e "${CYAN}+==========================================+${NC}"
echo -e "${CYAN}|  ITAgent Patch Installer                 |${NC}"
echo -e "${CYAN}+==========================================+${NC}"
echo ""
echo -e "  Patch    : ${BOLD}${PATCH_VER}${NC}"
echo -e "  Desc     : ${PATCH_DESC}"
echo -e "  Target   : ${ITAGENT_HOME}"
echo -e "  Files    : ${PATCH_FILES}"
echo ""
read -rp "  Apply patch? (y/n) " ans
[[ ! "$ans" =~ ^[Yy]$ ]] && echo "Cancelled" && exit 0

# Step 1: Backup
echo ""
BACKUP_TS=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/tmp/itagent_pre_patch_${BACKUP_TS}.tar.gz"
echo -e "${CYAN}--- Backup before patch ---${NC}"
tar czf "$BACKUP_FILE" -C "$(dirname "$ITAGENT_HOME")" "$(basename "$ITAGENT_HOME")" 2>/dev/null
ok "Backup: $BACKUP_FILE"

# Step 2: Apply files
echo -e "${CYAN}--- Applying patch files ---${NC}"
if [ -d "$SCRIPT_DIR/files" ]; then
    # Copy patch files preserving directory structure
    cd "$SCRIPT_DIR/files"
    find . -type f | while read f; do
        TARGET="$ITAGENT_HOME/$f"
        mkdir -p "$(dirname "$TARGET")"
        cp "$f" "$TARGET"
        ok "$f"
    done
else
    fail "No files/ directory in patch"
fi

# Step 3: Update version
if [ -f "$ITAGENT_HOME/data/version.json" ]; then
    python3 -c "
import json, datetime
with open('${ITAGENT_HOME}/data/version.json') as f:
    v = json.load(f)
v['version'] = '${PATCH_VER}'
v['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
v['changelog'].append('${PATCH_VER} - ' + datetime.datetime.now().strftime('%Y-%m-%d') + ': ${PATCH_DESC}')
with open('${ITAGENT_HOME}/data/version.json', 'w') as f:
    json.dump(v, f, indent=2, ensure_ascii=False)
print('  \033[32mOK\033[0m version.json updated')
" 2>/dev/null || warn "version.json update failed"
fi

# Step 4: Restart Flask
echo -e "${CYAN}--- Restart Flask ---${NC}"
systemctl restart itagent-web 2>/dev/null && ok "Flask restarted" || warn "Flask restart failed"
sleep 3
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5000/ 2>/dev/null)
[ "$HTTP" = "200" ] || [ "$HTTP" = "302" ] && ok "HTTP $HTTP" || warn "HTTP $HTTP"

# Done
echo ""
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}  Patch ${PATCH_VER} applied!${NC}"
echo -e "${GREEN}===========================================${NC}"
echo ""
echo -e "  Rollback: tar xzf $BACKUP_FILE -C $(dirname "$ITAGENT_HOME")"
echo ""
