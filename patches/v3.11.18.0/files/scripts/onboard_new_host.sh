#!/bin/bash
###############################################
#  新主機一鍵 Onboarding 腳本
#  v3.11.18.0 (2026-04-23)
#  Usage: sudo /opt/inspection/scripts/onboard_new_host.sh <hostname>
#
#  前提: UI /admin#hosts 已新增主機, SSH key 已分發
#  會做: 重建 inventory -> ansible ping -> 完整巡檢 ->
#       TWGCB 掃描 -> 啟用 nmon (5min 間隔)
###############################################
set -u

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"
CYAN="\033[0;36m"; BOLD="\033[1m"; NC="\033[0m"

INSPECTION_HOME="${INSPECTION_HOME:-/opt/inspection}"
ANSIBLE_DIR="${INSPECTION_HOME}/ansible"
VAULT_PASS="${INSPECTION_HOME}/.vault_pass"
NMON_INTERVAL="${NMON_INTERVAL:-5}"

ok()   { echo -e "  ${GREEN}OK${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; exit 1; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }
info() { echo -e "  ${CYAN}-->${NC} $1"; }

# ========== Usage ==========
if [ $# -lt 1 ]; then
    echo "Usage: $0 <hostname>"
    echo ""
    echo "範例: $0 SECSVR198-012T"
    echo ""
    echo "前提:"
    echo "  1. 已透過 UI /admin#hosts 新增該主機"
    echo "  2. 新主機 sysinfra 帳號 + SSH authorized_keys 已分發"
    echo ""
    echo "會做:"
    echo "  [1/5] 驗證主機在 DB"
    echo "  [2/5] generate_inventory 重建 hosts.yml"
    echo "  [3/5] ansible ping 驗證 SSH 通"
    echo "  [4/5] run_inspection.sh (完整巡檢 + packages + seed + CIO snapshot)"
    echo "  [4.5] TWGCB 合規掃描 (--limit 單台)"
    echo "  [5/5] 啟用 nmon 效能採集 (${NMON_INTERVAL}min 間隔)"
    exit 1
fi

NEWHOST="$1"

echo ""
echo -e "${CYAN}+==========================================+${NC}"
echo -e "${CYAN}|  新主機 Onboarding: ${BOLD}${NEWHOST}${NC}"
echo -e "${CYAN}+==========================================+${NC}"
echo ""

# ========== [1/5] 驗證主機在 DB ==========
echo -e "${CYAN}--- Step 1/5 驗證主機在 DB ---${NC}"
EXIST=$(mongosh inspection --quiet --eval "db.hosts.countDocuments({hostname: '$NEWHOST'})" 2>/dev/null || echo "0")
EXIST=$(echo "$EXIST" | tr -d '[:space:]')
if [ "$EXIST" != "1" ]; then
    fail "DB 找不到 $NEWHOST, 請先到 UI /admin#hosts 新增主機"
fi
ok "主機在 DB hosts collection"

# ========== [2/5] 重建 inventory ==========
echo ""
echo -e "${CYAN}--- Step 2/5 重建 ansible inventory ---${NC}"
cd "${INSPECTION_HOME}/scripts" 2>/dev/null || fail "找不到 ${INSPECTION_HOME}/scripts"
if sudo -u sysinfra python3 generate_inventory.py >/tmp/onboard_inv_$$.log 2>&1; then
    ok "inventory 重建"
else
    warn "generate_inventory.py 有錯 (log: /tmp/onboard_inv_$$.log)"
    tail -10 /tmp/onboard_inv_$$.log | sed 's/^/    /'
fi

if grep -q "$NEWHOST" "${ANSIBLE_DIR}/inventory/hosts.yml" 2>/dev/null; then
    ok "hosts.yml 含 $NEWHOST"
else
    fail "hosts.yml 沒 $NEWHOST, 檢查 DB 的 hostname 欄位"
fi

# ========== [3/5] ansible ping ==========
echo ""
echo -e "${CYAN}--- Step 3/5 ansible ping 驗證 SSH ---${NC}"
cd "$ANSIBLE_DIR"
VAULT_ARG=""
[ -f "$VAULT_PASS" ] && VAULT_ARG="--vault-password-file $VAULT_PASS"
if sudo -u sysinfra ansible "$NEWHOST" -i inventory/hosts.yml -m ping $VAULT_ARG > /tmp/onboard_ping_$$.log 2>&1; then
    ok "ping pong"
else
    warn "ansible ping 失敗, 查原因:"
    tail -20 /tmp/onboard_ping_$$.log | sed 's/^/    /'
    echo ""
    echo -e "  ${YELLOW}常見原因${NC}:"
    echo "    - UI 填的 ssh_user/ssh_port/ssh_key 不對"
    echo "    - 新主機 authorized_keys 沒放 13 sysinfra 的 pub key"
    echo "    - 新主機防火牆擋 port 22"
    fail "ping 失敗, 修好再重跑"
fi

# ========== [4/5] 完整巡檢 ==========
echo ""
echo -e "${CYAN}--- Step 4/5 完整巡檢 (run_inspection.sh) ---${NC}"
info "會跑 site.yml + collect_packages + seed_data + CIO snapshot"
info "新主機資料會寫進 inspections / account_audit / host_packages collection"
info "預計 2~5 分鐘..."
if sudo -u sysinfra "${INSPECTION_HOME}/run_inspection.sh" > /tmp/onboard_insp_$$.log 2>&1; then
    ok "run_inspection.sh 結束"
    tail -15 /tmp/onboard_insp_$$.log | sed 's/^/    /'
else
    warn "run_inspection.sh 回傳非 0, 但繼續 (部分結果可能已寫入 DB)"
    tail -15 /tmp/onboard_insp_$$.log | sed 's/^/    /'
fi

# ========== [4.5] TWGCB 掃描 ==========
echo ""
echo -e "${CYAN}--- Step 4.5 TWGCB 合規掃描 (--limit $NEWHOST) ---${NC}"
cd "$ANSIBLE_DIR"
if sudo -u sysinfra ansible-playbook playbooks/twgcb_scan.yml \
        -i inventory/hosts.yml --limit "$NEWHOST" $VAULT_ARG \
        > /tmp/onboard_twgcb_$$.log 2>&1; then
    ok "TWGCB 掃描完成"
    # 觸發 TWGCB 匯入 (api_twgcb.scan endpoint 會自動 _import_results, 但 CLI 跑要手動)
    curl -s -o /dev/null -X POST "http://127.0.0.1:5000/api/twgcb/import" 2>/dev/null && ok "TWGCB 結果已匯入 MongoDB"
else
    warn "TWGCB 掃描有錯 (不 block, 可事後 UI 觸發):"
    tail -10 /tmp/onboard_twgcb_$$.log | sed 's/^/    /'
fi

# ========== [5/5] 啟用 nmon ==========
echo ""
echo -e "${CYAN}--- Step 5/5 啟用 nmon 效能採集 (${NMON_INTERVAL}min 間隔) ---${NC}"
NMON_RESULT=$(mongosh inspection --quiet --eval "
const r = db.hosts.updateOne(
  {hostname: '$NEWHOST'},
  {\$set: {nmon_enabled: true, nmon_interval_min: ${NMON_INTERVAL}}}
);
print('matched=' + r.matchedCount + ' modified=' + r.modifiedCount);
" 2>&1)
echo "    $NMON_RESULT"
ok "nmon_enabled=true (下次 run_inspection.sh 會自動採 nmon)"

# ========== 完成 ==========
echo ""
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}  ${BOLD}${NEWHOST}${GREEN} onboard 完成!${NC}"
echo -e "${GREEN}===========================================${NC}"
echo ""
echo -e "  ${BOLD}驗證${NC}:"
echo -e "    Dashboard  : http://$(hostname -I | awk '{print $1}'):5000/"
echo -e "    今日報告   : http://$(hostname -I | awk '{print $1}'):5000/report"
echo -e "    帳號盤點   : http://$(hostname -I | awk '{print $1}'):5000/audit"
echo -e "    TWGCB 合規 : http://$(hostname -I | awk '{print $1}'):5000/twgcb"
echo -e "    軟體盤點   : http://$(hostname -I | awk '{print $1}'):5000/packages"
echo -e "    效能月報   : http://$(hostname -I | awk '{print $1}'):5000/perf  ${YELLOW}(nmon 需等 5~15 分鐘)${NC}"
echo ""
echo -e "  ${BOLD}Log 檔${NC} (debug 用):"
echo -e "    /tmp/onboard_inv_$$.log"
echo -e "    /tmp/onboard_ping_$$.log"
echo -e "    /tmp/onboard_insp_$$.log"
echo -e "    /tmp/onboard_twgcb_$$.log"
echo ""
