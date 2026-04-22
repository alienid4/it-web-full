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

# === 套件盤點 (v3.8.0.0+) ===
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 開始收集套件盤點..." | tee -a "${LOG_FILE}"
cd "${ANSIBLE_DIR}" && ansible-playbook playbooks/collect_packages.yml \
  --vault-password-file /opt/inspection/.vault_pass \
  -i inventory/hosts.yml \
  2>&1 | tee -a "${LOG_FILE}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 套件盤點完成" | tee -a "${LOG_FILE}"

# === 自動匯入 MongoDB ===
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 開始匯入 MongoDB..." | tee -a "${LOG_FILE}"
cd "${WEBAPP_DIR}" && python3 seed_data.py 2>&1 | tee -a "${LOG_FILE}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] MongoDB 匯入完成" | tee -a "${LOG_FILE}"

# 匯入套件盤點 + diff (v3.8.0.0+)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 匯入套件盤點 MongoDB..." | tee -a "${LOG_FILE}"
cd "${WEBAPP_DIR}" && python3 -c "
import sys
sys.path.insert(0, '.')
from services import packages_service
packages_service.ensure_indexes()
r = packages_service.import_packages_from_reports()
print('[packages] imported=' + str(r['imported']) + ' added=' + str(r['added_total']) + ' removed=' + str(r['removed_total']) + ' upgraded=' + str(r['upgraded_total']))
" 2>&1 | tee -a "${LOG_FILE}"

# === 效能月報 nmon 收集 (v3.9.0.0+) ===
# 從 MongoDB 抓 nmon_enabled=true 主機清單, 產成 --limit 格式
NMON_HOSTS=$(cd "${WEBAPP_DIR}" && python3 -c "
import sys
sys.path.insert(0, '.')
from services import nmon_service
print(':'.join(h['hostname'] for h in nmon_service.list_enabled_hosts()))
" 2>/dev/null)
if [ -n "${NMON_HOSTS}" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 開始收集 nmon 效能資料 (主機: ${NMON_HOSTS})..." | tee -a "${LOG_FILE}"
    cd "${ANSIBLE_DIR}" && ansible-playbook playbooks/collect_nmon.yml \
      --vault-password-file /opt/inspection/.vault_pass \
      -i inventory/hosts.yml \
      --limit "${NMON_HOSTS}" \
      2>&1 | tee -a "${LOG_FILE}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] nmon 收集完成, 匯入 MongoDB..." | tee -a "${LOG_FILE}"
    cd "${WEBAPP_DIR}" && python3 -c "
import sys
sys.path.insert(0, '.')
from services import nmon_service
r = nmon_service.import_nmon_files()
print('[nmon] scanned=' + str(r['scanned']) + ' imported=' + str(r['imported']) + ' skipped=' + str(r['skipped']) + ' failed=' + str(len(r['failed'])))
" 2>&1 | tee -a "${LOG_FILE}"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 無 nmon_enabled 主機, 跳過效能採集" | tee -a "${LOG_FILE}"
fi

# === CIO 合規率每日 snapshot (v3.11.x+) ===
echo "[$(date '+%Y-%m-%d %H:%M:%S')] CIO: snapshot 合規率..." | tee -a "${LOG_FILE}"
cd "${WEBAPP_DIR}" && python3 -c "
import sys
sys.path.insert(0, '.')
from services import cio_service
d = cio_service.snapshot_twgcb_daily()
print('[cio] snapshot date=' + d['date'] + ' rate=' + str(d['rate']) + '% pass=' + str(d['pass_checks']) + '/' + str(d['total_checks']))
" 2>&1 | tee -a "${LOG_FILE}"

# 清理舊檔案
find "${LOG_DIR}"    -name "*.log"  -mtime +30 -delete 2>/dev/null
find "${REPORT_DIR}" -name "*.html" -mtime +90 -delete 2>/dev/null
find "${REPORT_DIR}" -name "*.json" -mtime +90 -delete 2>/dev/null

exit ${EXIT_CODE}
