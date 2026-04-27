#!/bin/bash
###############################################
#  v3.12.3.0-mail-auto-trigger installer
#
#  動作: run_inspection.sh 結尾 (在 exit ${EXIT_CODE} 之前) 接 generate_report.py:
#        1. 找最新一批 inspection_*_*.json (或舊格式 YYYYMMDD_HHMMSS_*.json)
#        2. python3 scripts/generate_report.py <prefix>
#        3. generate_report.py 自己讀 settings.json notify_email + 算 overall +
#           符合 send_on 條件就 SMTP 寄 HTML 報告給 to[] 全部收件人
#
#  PREREQ: settings.json notify_email 已設好 (enabled=true, smtp_host/port/tls 對, to 填)
#          v3.12.2.x 以上 (設定 UI + 測試 SMTP 已通)
#
#  Idempotent: 偵測 # v3.12.3.0 email-report marker → skip
#  Usage: sudo ./install.sh
###############################################
set -u
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}OK${NC}   $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; exit 1; }
info() { echo -e "  ${CYAN}-->${NC}  $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)

echo ""
echo -e "${CYAN}+============================================================+${NC}"
echo -e "${CYAN}|  v3.12.3.0 mail auto-trigger (run_inspection.sh → 寄信)    |${NC}"
echo -e "${CYAN}+============================================================+${NC}"
[ "$(id -u)" -eq 0 ] || fail "需 root / sudo"

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

RUN_SH="$HOME_DIR/run_inspection.sh"
GEN_PY="$HOME_DIR/scripts/generate_report.py"
VERSION_JSON="$HOME_DIR/data/version.json"

[ -f "$RUN_SH" ]       || fail "缺檔: $RUN_SH"
[ -f "$GEN_PY" ]       || fail "缺檔: $GEN_PY"
[ -f "$VERSION_JSON" ] || fail "缺檔: $VERSION_JSON"

CUR_VER=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['version'])" 2>/dev/null || echo "?")
info "目前版本: $CUR_VER"

BACKUP_DIR="/var/backups/inspection/pre_v3.12.3.0_${TS}"

# ========== [1] 備份 ==========
echo -e "${BOLD}[1/3] 備份${NC}"
mkdir -p "$BACKUP_DIR"
cp -p "$RUN_SH"       "$BACKUP_DIR/" && ok "run_inspection.sh → bak"
cp -p "$VERSION_JSON" "$BACKUP_DIR/" && ok "version.json → bak"
info "備份: $BACKUP_DIR"

# ========== [2] 注入 email block ==========
echo -e "${BOLD}[2/3] 注入 mail report block 到 run_inspection.sh${NC}"

if grep -q "# v3.12.3.0 email-report" "$RUN_SH"; then
    info "已注入過, skip"
else
    # 在 exit ${EXIT_CODE} 前插入 email block
    python3 <<PYEOF || fail "注入失敗"
p = "$RUN_SH"
s = open(p).read()

inject = '''
# === v3.12.3.0 email-report (巡檢結束自動寄報告 HTML 給 notify_email.to) ===
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 產生報告 + SMTP 寄信..." | tee -a "\${LOG_FILE}"
LATEST_JSON=\$(ls -t "\${REPORT_DIR}"/inspection_*_*.json "\${REPORT_DIR}"/*[0-9]_*.json 2>/dev/null | grep -vE 'twgcb_|packages_|nmon_|network_' | head -1)
if [ -n "\${LATEST_JSON}" ]; then
    PREFIX=\$(echo "\${LATEST_JSON}" | sed 's|_[^_/]*\\.json\$||')
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] generate_report.py prefix=\${PREFIX}" | tee -a "\${LOG_FILE}"
    python3 "\${INSPECTION_HOME}/scripts/generate_report.py" "\${PREFIX}" 2>&1 | tee -a "\${LOG_FILE}"
else
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 找不到 inspection_*.json, skip 寄信" | tee -a "\${LOG_FILE}"
fi

'''

# 找 exit \${EXIT_CODE} 並插在它之前
marker = "exit \${EXIT_CODE}"
if marker not in s:
    raise SystemExit("找不到 exit \${EXIT_CODE} marker")
s = s.replace(marker, inject + marker, 1)
open(p, 'w').write(s)
print("  注入成功")
PYEOF
    ok "run_inspection.sh 已注入 email block"
fi

# 驗證 bash 語法
bash -n "$RUN_SH" 2>&1 || fail "run_inspection.sh 語法錯! 從 $BACKUP_DIR 還原"
ok "run_inspection.sh bash 語法 OK"

# ========== [3] version.json ==========
echo -e "${BOLD}[3/3] 更新 version.json → 3.12.3.0${NC}"
VERSION_JSON_PATH="$VERSION_JSON" CHANGELOG_FILE="$SCRIPT_DIR/CHANGELOG_ENTRY.txt" python3 <<'PYEOF' || fail "version.json 更新失敗"
import json, datetime, os
p = os.environ["VERSION_JSON_PATH"]
d = json.load(open(p))
new_entry = open(os.environ["CHANGELOG_FILE"]).read().strip()
if any(e.startswith("3.12.3.0 ") for e in d.get("changelog", [])):
    print("  changelog 已含 3.12.3.0, skip prepend")
else:
    d.setdefault("changelog", []).insert(0, new_entry)
d["version"] = "3.12.3.0"
d["updated_at"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
print("  version.json → 3.12.3.0")
PYEOF
ok "version.json OK"

# Flask 不需重啟 (script 改動, cron 下次跑就吃新版)
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  v3.12.3.0 完成! $CUR_VER → 3.12.3.0${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}下一次巡檢觸發時 (cron 06:30 / 13:30 / 17:30) 會${NC}:"
echo "  1. 跑完 ansible playbook + 套件盤點 + nmon"
echo "  2. python3 generate_report.py <最新 prefix>"
echo "  3. generate_report.py 算 overall 狀態"
echo "  4. 對照 settings.json notify_email.send_on (預設 [error, warn])"
echo "  5. 符合條件 + enabled=true → SMTP 寄 HTML 報告給 to[] 全部收件人"
echo ""
echo -e "${BOLD}馬上手動測試 (不等 cron)${NC}:"
echo "  sudo $RUN_SH"
echo "  # 看 log: $HOME_DIR/logs/<TS>_run.log"
echo "  # 找 'Email sent to:' 或 'Email failed:' 字樣"
echo ""
echo -e "${BOLD}關掉自動寄信${NC}: admin#settings → Email 通知設定 → 觸發條件清空 → 儲存"
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo "  sudo cp -p $BACKUP_DIR/run_inspection.sh $RUN_SH"
echo "  sudo cp -p $BACKUP_DIR/version.json $VERSION_JSON"
