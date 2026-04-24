#!/bin/bash
###############################################
#  v3.11.26.0 combo installer
#  一次從 22.2 升到 26.0 (包含 23.0 / 23.1 / 24.0 / 25.0 / 26.0 全部改動)
#
#  內含:
#    - 視覺化 hero + 9 矩陣 (23.0)
#    - PASS/WARN/FAIL/SKIP 彩色 badge (23.1)
#    - 建議動作知識庫 (24.0)
#    - 歷史瀏覽 (25.0) + _detect_inspection_home bugfix
#    - 版本對照 (26.0)
#    - 180 天報告自動清 cron (23.0)
#
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
SRC_DIR="$SCRIPT_DIR/files"
TS=$(date +%Y%m%d_%H%M%S)

if [ -n "${INSPECTION_HOME:-}" ]; then
    HOME_DIR="$INSPECTION_HOME"
elif [ -f "/opt/inspection/data/version.json" ]; then
    HOME_DIR="/opt/inspection"
elif [ -f "/seclog/AI/inspection/data/version.json" ]; then
    HOME_DIR="/seclog/AI/inspection"
else
    fail "找不到 inspection home"
fi

BACKUP_DIR="/var/backups/inspection/pre_v3.11.26.0_combo_${TS}"
CRON_FILE="/etc/cron.d/inspection-deep-check-cleanup"

echo ""
echo -e "${CYAN}+====================================================+${NC}"
echo -e "${CYAN}|  v3.11.26.0 Combo (22.2 一次升到 26.0)              |${NC}"
echo -e "${CYAN}|  視覺化 + badge + 知識庫 + 歷史 + 對照 + 保留 cron  |${NC}"
echo -e "${CYAN}+====================================================+${NC}"
info "目標: $HOME_DIR"

# ========== [0] 前置 ==========
echo -e "${BOLD}[0/7] 前置檢查${NC}"
[ "$(id -u)" -eq 0 ] || fail "需 root / sudo"

for f in \
    "$SRC_DIR/webapp/routes/api_deep_check.py" \
    "$SRC_DIR/webapp/routes/remedy_kb.py" \
    "$SRC_DIR/webapp/templates/report.html" \
    "$SRC_DIR/data/version.json"; do
    [ -f "$f" ] || fail "缺檔: $f"
done
ok "patch 檔案齊全"

CUR_VER=$(cat "$HOME_DIR/data/version.json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])' 2>/dev/null || echo "unknown")
info "目前版本: $CUR_VER"

# 檢查是否已是 26.0 以上 (idempotent skip)
case "$CUR_VER" in
    3.11.26.*|3.11.27.*|3.11.28.*|3.11.29.*|3.11.3*|3.1[2-9].*|3.[2-9]*)
        warn "已在 >= 26.0 版本 ($CUR_VER), combo 會覆蓋成 26.0 精確版, 確定繼續? (5 秒後繼續, Ctrl+C 中止)"
        sleep 5
        ;;
esac

# 檢查深度檢查功能已裝 (需 22.0+)
[ -f "$HOME_DIR/webapp/routes/api_deep_check.py" ] || fail "未偵測到 api_deep_check.py. 請先套 v3.11.22.0 以上"
ok "前置條件滿足"

# ========== [1] 備份 ==========
echo -e "${BOLD}[1/7] 備份${NC}"
mkdir -p "$BACKUP_DIR"
cp -p "$HOME_DIR/webapp/routes/api_deep_check.py" "$BACKUP_DIR/" 2>/dev/null && ok "api_deep_check.py → bak"
cp -p "$HOME_DIR/webapp/routes/remedy_kb.py" "$BACKUP_DIR/" 2>/dev/null && ok "remedy_kb.py → bak"
cp -p "$HOME_DIR/webapp/templates/report.html" "$BACKUP_DIR/" 2>/dev/null && ok "report.html → bak"
cp -p "$HOME_DIR/data/version.json" "$BACKUP_DIR/" && ok "version.json → bak"
[ -f "$CRON_FILE" ] && cp -p "$CRON_FILE" "$BACKUP_DIR/" 2>/dev/null && ok "舊 cron → bak"
info "備份: $BACKUP_DIR"

# ========== [2] 複製新檔 ==========
echo -e "${BOLD}[2/7] 複製新檔${NC}"
OWNER=$(stat -c "%U:%G" "$HOME_DIR/webapp/app.py")
info "檔案 owner: $OWNER"

cp "$SRC_DIR/webapp/routes/api_deep_check.py" "$HOME_DIR/webapp/routes/" && chown "$OWNER" "$HOME_DIR/webapp/routes/api_deep_check.py" && ok "api_deep_check.py"
cp "$SRC_DIR/webapp/routes/remedy_kb.py" "$HOME_DIR/webapp/routes/" && chown "$OWNER" "$HOME_DIR/webapp/routes/remedy_kb.py" && ok "remedy_kb.py (新檔)"
cp "$SRC_DIR/webapp/templates/report.html" "$HOME_DIR/webapp/templates/" && chown "$OWNER" "$HOME_DIR/webapp/templates/report.html" && ok "report.html"
cp "$SRC_DIR/data/version.json" "$HOME_DIR/data/version.json" && chown "$OWNER" "$HOME_DIR/data/version.json" && ok "version.json → 3.11.26.0"

# ========== [3] 語法驗證 ==========
echo -e "${BOLD}[3/7] Python 語法驗證${NC}"
python3 -c "import ast; ast.parse(open('$HOME_DIR/webapp/routes/remedy_kb.py').read())" 2>&1 || fail "remedy_kb.py 語法錯誤"
python3 -c "import ast; ast.parse(open('$HOME_DIR/webapp/routes/api_deep_check.py').read())" 2>&1 || fail "api_deep_check.py 語法錯誤"
ok "py 語法通過"

# ========== [4] 報告 / 進度目錄 ==========
echo -e "${BOLD}[4/7] 建報告/進度目錄 (首次套 23.0 用)${NC}"
mkdir -p "$HOME_DIR/data/deep_check_reports" "$HOME_DIR/data/deep_check_progress"
chown "$OWNER" "$HOME_DIR/data/deep_check_reports" "$HOME_DIR/data/deep_check_progress"
chmod 755 "$HOME_DIR/data/deep_check_reports" "$HOME_DIR/data/deep_check_progress"
ok "deep_check_reports / _progress 目錄就位"

# ========== [5] 180 天保留 cron ==========
echo -e "${BOLD}[5/7] 裝 180 天保留 cron${NC}"
cat > "$CRON_FILE" <<EOF
# v3.11.23.0: 每天 03:00 清 180 天前的深度檢查報告
0 3 * * * root find $HOME_DIR/data/deep_check_reports -name 'ts_*_*.txt' -type f -mtime +180 -delete 2>/dev/null
EOF
chmod 644 "$CRON_FILE"
ok "cron 已裝 $CRON_FILE"

# ========== [6] 重啟 Flask ==========
echo -e "${BOLD}[6/7] 重啟 Flask${NC}"
RESTARTED=0
for svc in itagent-web inspection inspection-web; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" && ok "systemctl restart $svc" && RESTARTED=1 && break
    fi
done
[ "$RESTARTED" -eq 1 ] || warn "沒偵測到 Flask service, 請手動重啟"
sleep 3

# ========== [7] 驗證 ==========
echo -e "${BOLD}[7/7] 驗證${NC}"
NEW_VERSION=$(cat "$HOME_DIR/data/version.json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])' 2>/dev/null || echo "?")
[ "$NEW_VERSION" = "3.11.26.0" ] && ok "版本 $NEW_VERSION ✅" || warn "版本異常: $NEW_VERSION"

HTTP_REP=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5000/api/deep-check/reports" 2>/dev/null || echo "000")
HTTP_HIS=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5000/api/deep-check/history" 2>/dev/null || echo "000")

case "$HTTP_REP" in 200|302|401) ok "/reports $HTTP_REP" ;; *) warn "/reports $HTTP_REP" ;; esac
case "$HTTP_HIS" in 200|302|401) ok "/history $HTTP_HIS (新 endpoint 載入成功)" ;; *) warn "/history $HTTP_HIS" ;; esac

# Python import 測試 (blueprint 真的載入)
sudo -u "$(echo $OWNER | cut -d: -f1)" bash -c "cd $HOME_DIR/webapp && python3 -c 'from routes.api_deep_check import bp; from routes.remedy_kb import match_remedies, REMEDY_KB; print(\"endpoints:\", len([r for r in bp.deferred_functions]), \"remedies:\", len(REMEDY_KB))'" 2>&1 | grep -q "endpoints:" && ok "blueprint + knowledge base import 通過" || warn "import 測試異常"

echo ""
echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  v3.11.26.0 Combo 完成! $CUR_VER → 3.11.26.0${NC}"
echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}瀏覽器測試${NC} (Ctrl+Shift+R 強制重載):"
echo "  1. /report → 點任一 Linux 卡片「🔍 深度檢查」"
echo "  2. 若之前跑過 → modal 上方應見「📋 最近跑過」歷史列表"
echo "  3. 跑完後: hero 大燈 + 4 KPI + 9 矩陣 + WARN 項自動展開"
echo "  4. 展開 WARN: [PASS] 彩色 badge + 📖 指令/風險/驗證 知識庫區塊"
echo "  5. 完成畫面底下點「📊 對照其他」→ 選歷史版本 → 並列 9 面向"
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo "  cd $BACKUP_DIR"
echo "  sudo cp -p api_deep_check.py $HOME_DIR/webapp/routes/"
echo "  sudo cp -p report.html $HOME_DIR/webapp/templates/"
echo "  sudo cp -p version.json $HOME_DIR/data/"
echo "  sudo rm -f $HOME_DIR/webapp/routes/remedy_kb.py"
echo "  sudo rm -f $CRON_FILE"
echo "  sudo systemctl restart itagent-web"
