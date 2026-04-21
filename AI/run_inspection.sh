#!/bin/bash
# 金融業 IT 每日巡檢 - 每日執行腳本
# Cron: 30 6,13,17 * * * /opt/inspection/run_inspection.sh

INSPECTION_HOME="/opt/inspection"
ANSIBLE_DIR="${INSPECTION_HOME}/ansible"
LOG_DIR="${INSPECTION_HOME}/logs"
REPORT_DIR="${INSPECTION_HOME}/data/reports"
WEBAPP_DIR="${INSPECTION_HOME}/webapp"
PID_FILE="${LOG_DIR}/inspection.pid"

TS=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/${TS}_run.log"

mkdir -p "${LOG_DIR}" "${REPORT_DIR}"

# PID 檔防止重複執行
if [ -f "${PID_FILE}" ]; then
    OLD_PID=$(cat "${PID_FILE}")
    if kill -0 "${OLD_PID}" 2>/dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 巡檢已在執行中 (PID=${OLD_PID})，跳過" | tee "${LOG_FILE}"
        exit 0
    fi
fi
echo $$ > "${PID_FILE}"
trap "rm -f ${PID_FILE}" EXIT

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ===== 巡檢開始 ${TS} =====" | tee "${LOG_FILE}"

cd "${ANSIBLE_DIR}" || { echo "ERROR: cd failed"; exit 1; }

ansible-playbook playbooks/site.yml --vault-password-file /opt/inspection/.vault_pass \
  -i inventory/hosts.yml \
  2>&1 | tee -a "${LOG_FILE}"

EXIT_CODE=${PIPESTATUS[0]}

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ===== 巡檢完成 exit=${EXIT_CODE} =====" | tee -a "${LOG_FILE}"

# === 自動匯入 MongoDB ===
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 開始匯入 MongoDB..." | tee -a "${LOG_FILE}"
cd "${WEBAPP_DIR}" && python3 seed_data.py 2>&1 | tee -a "${LOG_FILE}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] MongoDB 匯入完成" | tee -a "${LOG_FILE}"

# 清理舊檔案
find "${LOG_DIR}"    -name "*.log"  -mtime +30 -delete 2>/dev/null
find "${REPORT_DIR}" -name "*.html" -mtime +90 -delete 2>/dev/null
find "${REPORT_DIR}" -name "*.json" -mtime +90 -delete 2>/dev/null

exit ${EXIT_CODE}
