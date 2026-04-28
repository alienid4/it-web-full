#!/usr/bin/env bash
# 系統聯通圖 - 採集 wrapper (給 cron 用)
# v3.15.4.0+
#
# 流程: ansible-playbook collect_connections.yml → dependency_seed_collect.py → log
# log 寫到 ${INSPECTION_HOME}/logs/dep_collect_cron.log (附時戳)
#
# 用法:
#   /seclog/AI/inspection/scripts/run_dep_collect.sh
#
# cron 範例 (寫在 sysinfra crontab):
#   */10 9-18 * * 1-5 /seclog/AI/inspection/scripts/run_dep_collect.sh

set -uo pipefail
export INSPECTION_HOME="${INSPECTION_HOME:-/opt/inspection}"
# auto-detect home (家裡 221 vs 公司 13)
if [ ! -f "${INSPECTION_HOME}/data/version.json" ]; then
    for cand in /seclog/AI/inspection /opt/inspection; do
        if [ -f "${cand}/data/version.json" ]; then
            INSPECTION_HOME="${cand}"
            break
        fi
    done
fi
export INSPECTION_HOME

LOG_DIR="${INSPECTION_HOME}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/dep_collect_cron.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

echo "==== ${TS} START dep_collect (INSPECTION_HOME=${INSPECTION_HOME}) ====" >> "${LOG_FILE}"

# 跑 ansible playbook (限定 Linux 主機,Windows 採集走 Stage 3b)
LIMIT_HOSTS="${DEP_COLLECT_LIMIT:-secansible:secclient1:sec9c2}"

cd "${INSPECTION_HOME}/ansible" || { echo "[ERR] cd ansible 失敗" >> "${LOG_FILE}"; exit 1; }

ansible-playbook -i inventory/hosts.yml playbooks/collect_connections.yml \
    --limit "${LIMIT_HOSTS}" \
    -e "inspection_home_override=${INSPECTION_HOME}" \
    >> "${LOG_FILE}" 2>&1
RC1=$?

if [ "${RC1}" != "0" ]; then
    echo "==== ${TS} ansible-playbook 失敗 rc=${RC1},中止 ====" >> "${LOG_FILE}"
    exit "${RC1}"
fi

# 跑 import
python3 "${INSPECTION_HOME}/scripts/dependency_seed_collect.py" >> "${LOG_FILE}" 2>&1
RC2=$?

TS2=$(date '+%Y-%m-%d %H:%M:%S')
if [ "${RC2}" = "0" ]; then
    echo "==== ${TS2} END OK ====" >> "${LOG_FILE}"
else
    echo "==== ${TS2} seed_collect 失敗 rc=${RC2} ====" >> "${LOG_FILE}"
fi

# 限制 log 大小 (保留最近 2000 行)
if [ -f "${LOG_FILE}" ]; then
    LINES=$(wc -l < "${LOG_FILE}")
    if [ "${LINES}" -gt 2000 ]; then
        tail -n 1500 "${LOG_FILE}" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "${LOG_FILE}"
    fi
fi

exit "${RC2}"
