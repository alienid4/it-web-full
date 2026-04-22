#!/bin/bash
# v3.11.4.1 post_install — 驗證 ansible roles 路徑抓得到
set -u

R="\033[0;31m"; G="\033[0;32m"; Y="\033[1;33m"; C="\033[0;36m"; N="\033[0m"
ok()   { echo -e "    ${G}OK${N} $1"; }
warn() { echo -e "    ${Y}WARN${N} $1"; }

ITAGENT_HOME="${ITAGENT_HOME:-/opt/inspection}"

echo -e "${C}--- v3.11.4.1 post_install ---${N}"

# 1. ansible.cfg 就位檢查
if [ -f "${ITAGENT_HOME}/ansible/ansible.cfg" ]; then
    ok "ansible.cfg 已就位"
else
    warn "ansible.cfg 不存在（patch 套用異常？）"
fi

# 2. 快速試 syntax-check collect_packages.yml 驗證 role 抓得到
cd "${ITAGENT_HOME}/ansible" 2>/dev/null || { warn "ansible 目錄不存在"; exit 0; }
if ansible-playbook playbooks/collect_packages.yml --syntax-check >/dev/null 2>&1; then
    ok "collect_packages.yml syntax + role 驗證通過"
else
    warn "collect_packages.yml 還有問題，請看 ansible-playbook playbooks/collect_packages.yml --syntax-check"
fi

# 3. run_inspection.sh 權限
if [ -x "${ITAGENT_HOME}/run_inspection.sh" ]; then
    ok "run_inspection.sh 可執行"
else
    chmod +x "${ITAGENT_HOME}/run_inspection.sh" 2>/dev/null && ok "已修 run_inspection.sh 執行權"
fi

echo -e "${G}post_install 完成${N}"
echo "現在可以重跑: sudo ${ITAGENT_HOME}/run_inspection.sh"
