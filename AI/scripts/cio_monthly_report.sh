#!/bin/bash
# 每月 1 號產 CIO PDF 月報
# cron: 0 9 1 * * /opt/inspection/scripts/cio_monthly_report.sh
# (每月 1 號早上 9 點)

INSPECTION_HOME="/opt/inspection"
REPORTS_DIR="${INSPECTION_HOME}/data/cio_reports"
LOG_FILE="${INSPECTION_HOME}/logs/cio_monthly_$(date +%Y%m).log"

mkdir -p "${REPORTS_DIR}"

# 產上個月的 PDF (date --date='last month')
LAST_MONTH=$(date --date='last month' +%Y-%m)
LAST_MONTH_FILE="${REPORTS_DIR}/cio_monthly_${LAST_MONTH}.pdf"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 產製 $LAST_MONTH 月度報告..." | tee "${LOG_FILE}"

cd "${INSPECTION_HOME}/webapp" && python3 -c "
import sys
sys.path.insert(0, '.')
from services import cio_pdf
from datetime import datetime, timedelta

# last month
now = datetime.now()
if now.month == 1:
    y, m = now.year - 1, 12
else:
    y, m = now.year, now.month - 1

# NOTE: build_for_current_month() 其實只能抓當前, 理想情況要參數化
# 先用當前 snapshot 當上月代表 (資料保真取決於 snapshot 累積)
pdf = cio_pdf.build_for_current_month()
out = '${REPORTS_DIR}/cio_monthly_' + f'{y:04d}-{m:02d}' + '.pdf'
open(out, 'wb').write(pdf)
print(f'saved {out}, size={len(pdf)}')
" 2>&1 | tee -a "${LOG_FILE}"

# Email (optional - 若 CIO_EMAIL_TO 有設)
if [ -n "${CIO_EMAIL_TO}" ] && command -v mail >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 寄給 ${CIO_EMAIL_TO}" | tee -a "${LOG_FILE}"
    echo "請查收 $LAST_MONTH 月度 IT 監控月報 (附件)。" | \
        mail -s "IT 監控月報 $LAST_MONTH" -a "${LAST_MONTH_FILE}" "${CIO_EMAIL_TO}" 2>&1 | tee -a "${LOG_FILE}"
fi

# 清理 >12 個月的舊 PDF
find "${REPORTS_DIR}" -name "cio_monthly_*.pdf" -mtime +365 -delete 2>/dev/null

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 完成" | tee -a "${LOG_FILE}"
