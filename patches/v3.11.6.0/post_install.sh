#!/bin/bash
# v3.11.6.0 post_install — 重建 inventory 套用新 ansible_user 邏輯
set -u

R=$'\e[0;31m'; G=$'\e[0;32m'; Y=$'\e[1;33m'; C=$'\e[0;36m'; N=$'\e[0m'
ok()   { echo -e "    ${G}OK${N} $1"; }
fail() { echo -e "    ${R}FAIL${N} $1"; }
warn() { echo -e "    ${Y}WARN${N} $1"; }
info() { echo -e "    ${C}-->${N} $1"; }

ITAGENT_HOME="${ITAGENT_HOME:-/opt/inspection}"

echo -e "${C}--- v3.11.6.0 post_install ---${N}"

# 1. 確認 group_vars/all.yml 就位
if [ -f "$ITAGENT_HOME/ansible/group_vars/all.yml" ]; then
    ok "group_vars/all.yml 已部署"
    info "預設 ansible_user:"
    grep "^ansible_user:" "$ITAGENT_HOME/ansible/group_vars/all.yml" | sed 's/^/        /'
else
    fail "group_vars/all.yml 不見"
fi

# 2. 確認 generate_inventory.py 已更新
if grep -q "v3.11.6.0" "$ITAGENT_HOME/scripts/generate_inventory.py" 2>/dev/null; then
    ok "generate_inventory.py 已更新"
else
    warn "generate_inventory.py 沒看到 v3.11.6.0 標記（可能是手動補過的）"
fi

# 3. 重建 inventory
echo -e "${C}--- 重建 ansible inventory ---${N}"
if command -v python3 >/dev/null 2>&1; then
    if sudo -u sysinfra python3 "$ITAGENT_HOME/scripts/generate_inventory.py" 2>&1 | sed 's/^/    /'; then
        ok "inventory 已重建"
    else
        warn "以 sysinfra 跑 generate_inventory 失敗，改用 root"
        python3 "$ITAGENT_HOME/scripts/generate_inventory.py" 2>&1 | sed 's/^/    /'
    fi
fi

# 4. 驗證：inventory 產出的 hosts.yml 有沒有正確的 ansible_user
echo -e "${C}--- 驗證 hosts.yml 內容 ---${N}"
HOSTS_YML="$ITAGENT_HOME/ansible/inventory/hosts.yml"
if [ -f "$HOSTS_YML" ]; then
    info "前 30 行:"
    head -30 "$HOSTS_YML" | sed 's/^/        /'
fi

# 5. ansible ping 測試（self host）
echo -e "${C}--- 測試 ansible 連線 (self-host local) ---${N}"
SELF_HOSTNAME=$(hostname)
cd "$ITAGENT_HOME/ansible" 2>/dev/null && \
    sudo -u sysinfra ansible "$SELF_HOSTNAME" -m ping 2>&1 | head -10 | sed 's/^/        /'

echo ""
echo -e "${G}post_install 完成${N}"
echo ""
echo "後續建議："
echo "  1. UI/admin 重新觸發 TWGCB 掃描 → 現在應該以 sysinfra 連，不會再 'root@... denied'"
echo "  2. 若某台主機要用別的 SSH user：到 hosts_config.json 或 UI 改主機欄位 ssh_user=<user>"
