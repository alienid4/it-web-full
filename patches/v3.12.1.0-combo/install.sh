#!/bin/bash
###############################################
#  v3.12.1.0 COMBO installer
#  一條命令裝完 VMware tab 全套 (prereq → w1 → collector)
#
#  內含 3 顆 patch:
#    01_prereq    = v3.12.0.0-vmware-prereq    (pyvmomi + python-ldap)
#    02_w1        = v3.12.0.0-vmware-tab-w1    (UI tab + mock fallback)
#    03_collector = v3.12.1.0-vmware-collector (接真 VC + 8H cron)
#
#  各子 install.sh 都是 idempotent, 重跑安全。
#  任一步失敗 → 立即 stop + 印 rollback 提示。
#
#  Usage: sudo ./install.sh
###############################################
set -u
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}OK${NC}   $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; exit 1; }
info() { echo -e "  ${CYAN}-->${NC}  $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)

# ========== [0] 前置 ==========
echo ""
echo -e "${CYAN}+============================================================+${NC}"
echo -e "${CYAN}|  v3.12.1.0 COMBO  (VMware tab 全套, 3 顆 patch 一次裝)     |${NC}"
echo -e "${CYAN}+============================================================+${NC}"
[ "$(id -u)" -eq 0 ] || fail "需 root / sudo"

# 偵測 inspection home
if [ -n "${INSPECTION_HOME:-}" ]; then
    HOME_DIR="$INSPECTION_HOME"
elif [ -f "/opt/inspection/data/version.json" ]; then
    HOME_DIR="/opt/inspection"
elif [ -f "/seclog/AI/inspection/data/version.json" ]; then
    HOME_DIR="/seclog/AI/inspection"
else
    fail "找不到 inspection home"
fi
info "inspection home: $HOME_DIR"

CUR_VER=$(python3 -c "import json; print(json.load(open('$HOME_DIR/data/version.json'))['version'])" 2>/dev/null || echo "unknown")
info "目前版本: $CUR_VER"
info "目標版本: 3.12.1.0"

# 檢查 3 個子目錄齊全
for sub in 01_prereq 02_w1 03_collector; do
    [ -f "$SCRIPT_DIR/$sub/install.sh" ] || fail "缺子 patch: $sub/install.sh"
done
ok "3 顆子 patch 齊全"

LOG_DIR="/var/log/inspection-combo-${TS}"
mkdir -p "$LOG_DIR"
info "子 install.sh log 寫到: $LOG_DIR"

# ========== [1] 跑 prereq ==========
echo ""
echo -e "${BOLD}═══ [1/3] v3.12.0.0-vmware-prereq (pyvmomi + python-ldap) ═══${NC}"
cd "$SCRIPT_DIR/01_prereq" || fail "cd 01_prereq 失敗"
if bash install.sh 2>&1 | tee "$LOG_DIR/01_prereq.log"; then
    ok "[1/3] prereq 完成"
else
    fail "[1/3] prereq 失敗, log: $LOG_DIR/01_prereq.log"
fi

# ========== [2] 跑 w1 ==========
echo ""
echo -e "${BOLD}═══ [2/3] v3.12.0.0-vmware-tab-w1 (UI tab + mock) ═══${NC}"
cd "$SCRIPT_DIR/02_w1" || fail "cd 02_w1 失敗"
if bash install.sh 2>&1 | tee "$LOG_DIR/02_w1.log"; then
    ok "[2/3] w1 完成"
else
    fail "[2/3] w1 失敗, log: $LOG_DIR/02_w1.log
       還原: 看 $LOG_DIR/02_w1.log 末尾的 Rollback 段落"
fi

# ========== [3] 跑 collector ==========
echo ""
echo -e "${BOLD}═══ [3/3] v3.12.1.0-vmware-collector (接真 VC + 8H cron) ═══${NC}"
cd "$SCRIPT_DIR/03_collector" || fail "cd 03_collector 失敗"
if bash install.sh 2>&1 | tee "$LOG_DIR/03_collector.log"; then
    ok "[3/3] collector 完成"
else
    fail "[3/3] collector 失敗, log: $LOG_DIR/03_collector.log"
fi

# ========== 完工 ==========
NEW_VER=$(python3 -c "import json; print(json.load(open('$HOME_DIR/data/version.json'))['version'])" 2>/dev/null || echo "?")
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  v3.12.1.0 COMBO 完成!  $CUR_VER → $NEW_VER${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}下一步 (人工)${NC}:"
echo "  1. cd $HOME_DIR/data/vmware"
echo "  2. cp vcenters.yaml.sample vcenters.yaml && vi vcenters.yaml  (填 5 VC IP)"
echo "  3. ansible-vault create vc_credentials.vault --vault-password-file $HOME_DIR/.vault_pass"
echo "  4. dry-run: sudo -u sysinfra python3 $HOME_DIR/collector/vcenter_collector.py --only 板橋 --dry-run -v"
echo "  5. 真跑: sudo -u sysinfra python3 $HOME_DIR/collector/vcenter_collector.py"
echo ""
echo -e "${BOLD}子 install.sh log 全部留在${NC}: $LOG_DIR"
echo -e "${BOLD}詳細 SOP${NC}: notes/2026-04-27/ (1015 vault, 1030 first real collect)"
