#!/bin/bash
###############################################
#  apply_v3.11.22.0_to_221.sh
#  在 221 (家裡 secansible) 上套用 v3.11.22.0 深度檢查功能
#  Usage: sudo bash apply_v3.11.22.0_to_221.sh /tmp/deep_check_drop.tar.gz
###############################################
set -u
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}OK${NC}   $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; exit 1; }
info() { echo -e "  ${CYAN}-->${NC}  $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }

TARBALL="${1:-/tmp/deep_check_drop.tar.gz}"
INSPECTION_HOME="/seclog/AI/inspection"
TS=$(date +%Y%m%d_%H%M%S)
STAGING="/tmp/dc_staging_${TS}"
BACKUP_DIR="/var/backups/inspection/pre_v3.11.22.0_${TS}"

echo ""
echo -e "${CYAN}+====================================================+${NC}"
echo -e "${CYAN}|  v3.11.22.0 深度檢查套用 (家裡 221 測試場)          |${NC}"
echo -e "${CYAN}+====================================================+${NC}"

# ========== [0] 前置檢查 ==========
echo -e "${BOLD}[0/7] 前置檢查${NC}"
[ "$(id -u)" -eq 0 ] || fail "需 root / sudo"
[ -d "$INSPECTION_HOME" ] || fail "找不到 $INSPECTION_HOME"
[ -f "$TARBALL" ] || fail "找不到 tarball: $TARBALL"
ok "root / 路徑 / tarball 就緒"

# ========== [1] 解 tarball ==========
echo -e "${BOLD}[1/7] 解壓 tarball 到 staging${NC}"
mkdir -p "$STAGING"
tar xzf "$TARBALL" -C "$STAGING" || fail "tar xzf 失敗"
for f in api_deep_check.py deep_check.yml report.html version.json; do
    find "$STAGING" -name "$f" -print | head -1 | grep -q . || fail "tarball 缺 $f"
done
find "$STAGING" -maxdepth 4 -type d -name "smit_menu" | head -1 | grep -q . || fail "tarball 缺 smit_menu/"
ok "tarball 內容齊全"

DROP_API="$(find $STAGING -name 'api_deep_check.py' | head -1)"
DROP_YML="$(find $STAGING -name 'deep_check.yml' | head -1)"
DROP_HTML="$(find $STAGING -name 'report.html' | head -1)"
DROP_VER="$(find $STAGING -name 'version.json' | head -1)"
DROP_SMIT="$(find $STAGING -type d -name 'smit_menu' | head -1)"
info "API:  $DROP_API"
info "YML:  $DROP_YML"
info "HTML: $DROP_HTML"
info "VER:  $DROP_VER"
info "SMIT: $DROP_SMIT ($(find $DROP_SMIT -type f | wc -l) files)"

# ========== [2] 備份會被動的檔案 ==========
echo -e "${BOLD}[2/7] 備份現有檔案${NC}"
mkdir -p "$BACKUP_DIR"
cp -p "$INSPECTION_HOME/webapp/app.py" "$BACKUP_DIR/app.py" 2>/dev/null && ok "app.py → 備份"
cp -p "$INSPECTION_HOME/webapp/templates/report.html" "$BACKUP_DIR/report.html" 2>/dev/null && ok "report.html → 備份"
cp -p "$INSPECTION_HOME/data/version.json" "$BACKUP_DIR/version.json" 2>/dev/null && ok "version.json → 備份"
info "備份目錄：$BACKUP_DIR"

# ========== [3] 複製新檔 ==========
echo -e "${BOLD}[3/7] 複製新檔到 ${INSPECTION_HOME}${NC}"

# api_deep_check.py
cp "$DROP_API" "$INSPECTION_HOME/webapp/routes/api_deep_check.py" || fail "複製 api_deep_check.py 失敗"
ok "webapp/routes/api_deep_check.py"

# deep_check.yml
cp "$DROP_YML" "$INSPECTION_HOME/ansible/playbooks/deep_check.yml" || fail "複製 deep_check.yml 失敗"
ok "ansible/playbooks/deep_check.yml"

# report.html (整檔替換)
cp "$DROP_HTML" "$INSPECTION_HOME/webapp/templates/report.html" || fail "複製 report.html 失敗"
ok "webapp/templates/report.html"

# smit_menu 整包
rm -rf "$INSPECTION_HOME/scripts/smit_menu"
cp -r "$DROP_SMIT" "$INSPECTION_HOME/scripts/smit_menu" || fail "複製 smit_menu 失敗"
find "$INSPECTION_HOME/scripts/smit_menu" -name "*.sh" -exec chmod 750 {} \;
ok "scripts/smit_menu ($(find $INSPECTION_HOME/scripts/smit_menu -type f | wc -l) files)"

# version.json
cp "$DROP_VER" "$INSPECTION_HOME/data/version.json" || fail "複製 version.json 失敗"
ok "data/version.json → v3.11.22.0"

# ========== [4] 修 app.py (idempotent) ==========
echo -e "${BOLD}[4/7] 修 app.py (加入 deep_check blueprint)${NC}"
APP_PY="$INSPECTION_HOME/webapp/app.py"

# [4a] import 行
if grep -q "from routes.api_deep_check import bp as deep_check_bp" "$APP_PY"; then
    info "import 行已存在, 跳過"
else
    # 在 api_cio import 的下一行加入
    sed -i '/^from routes\.api_cio import bp as cio_bp/a from routes.api_deep_check import bp as deep_check_bp' "$APP_PY" \
        && ok "import 行已加入"
    grep -q "from routes.api_deep_check import bp as deep_check_bp" "$APP_PY" || fail "import 行插入失敗"
fi

# [4b] register_blueprint 行
if grep -q "app.register_blueprint(deep_check_bp)" "$APP_PY"; then
    info "register 行已存在, 跳過"
else
    # 在 cio_bp register 下一行加入
    sed -i '/^app\.register_blueprint(cio_bp)/a app.register_blueprint(deep_check_bp)' "$APP_PY" \
        && ok "register 行已加入"
    grep -q "app.register_blueprint(deep_check_bp)" "$APP_PY" || fail "register 行插入失敗"
fi

# [4c] 語法檢查
python3 -c "import ast; ast.parse(open('$APP_PY').read())" 2>&1 || fail "app.py 語法錯誤, 請檢查"
ok "app.py 語法通過"

# ========== [5] 修權限 ==========
echo -e "${BOLD}[5/7] 修權限${NC}"
chown -R sysinfra:itagent \
    "$INSPECTION_HOME/webapp/routes/api_deep_check.py" \
    "$INSPECTION_HOME/webapp/templates/report.html" \
    "$INSPECTION_HOME/webapp/app.py" \
    "$INSPECTION_HOME/ansible/playbooks/deep_check.yml" \
    "$INSPECTION_HOME/scripts/smit_menu" \
    "$INSPECTION_HOME/data/version.json" 2>&1 | head -5
mkdir -p "$INSPECTION_HOME/data/deep_check_reports" "$INSPECTION_HOME/data/deep_check_progress"
chown sysinfra:itagent "$INSPECTION_HOME/data/deep_check_reports" "$INSPECTION_HOME/data/deep_check_progress"
chmod 755 "$INSPECTION_HOME/data/deep_check_reports" "$INSPECTION_HOME/data/deep_check_progress"
ok "權限修正 + 報告目錄已建"

# ========== [6] 重啟 gunicorn ==========
echo -e "${BOLD}[6/7] 重啟 gunicorn${NC}"
OLD_PIDS=$(pgrep -f "gunicorn.*app:app" || true)
if [ -n "$OLD_PIDS" ]; then
    info "找到既有 gunicorn: $OLD_PIDS"
    kill $OLD_PIDS 2>/dev/null || true
    sleep 3
    # 確認真的死掉
    REMAIN=$(pgrep -f "gunicorn.*app:app" || true)
    [ -n "$REMAIN" ] && { kill -9 $REMAIN 2>/dev/null || true; sleep 1; }
    ok "舊 gunicorn 已停"
else
    warn "沒找到既有 gunicorn"
fi

mkdir -p "$INSPECTION_HOME/logs"
chown sysinfra:itagent "$INSPECTION_HOME/logs"

# 用原本的啟動參數 (從 ps 抓到的)
sudo -u sysinfra nohup /usr/local/bin/gunicorn \
    -w 4 -b 127.0.0.1:5000 \
    --timeout 300 --graceful-timeout 30 \
    --chdir "$INSPECTION_HOME/webapp" \
    --access-logfile "$INSPECTION_HOME/logs/gunicorn_access.log" \
    --error-logfile "$INSPECTION_HOME/logs/gunicorn_error.log" \
    app:app >> "$INSPECTION_HOME/logs/gunicorn.log" 2>&1 &
sleep 3

NEW_PID=$(pgrep -f "gunicorn.*app:app" | head -1)
if [ -n "$NEW_PID" ]; then
    ok "gunicorn 已重啟 (master pid=$NEW_PID)"
else
    fail "gunicorn 沒起來, 看 $INSPECTION_HOME/logs/gunicorn_error.log"
fi

# ========== [7] 驗證 ==========
echo -e "${BOLD}[7/7] 驗證${NC}"
sleep 2
# [7a] /api/deep-check/reports (應回 200 或 401)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5000/api/deep-check/reports")
case "$HTTP_CODE" in
    200|302|401) ok "API endpoint 回應 $HTTP_CODE (blueprint 已載入)" ;;
    404)         warn "API endpoint 404 — blueprint 可能未載入, 看 error log" ;;
    *)           warn "API 回應 $HTTP_CODE (預期 200/302/401)" ;;
esac

# [7b] 看 error log 有沒有 import 錯誤
if grep -q "ImportError\|SyntaxError\|ModuleNotFoundError" "$INSPECTION_HOME/logs/gunicorn_error.log" 2>/dev/null; then
    warn "gunicorn_error.log 有 import/syntax 錯誤:"
    grep -E "ImportError|SyntaxError|ModuleNotFoundError" "$INSPECTION_HOME/logs/gunicorn_error.log" | tail -5
fi

# [7c] version.json
NEW_VERSION=$(cat "$INSPECTION_HOME/data/version.json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])')
[ "$NEW_VERSION" = "3.11.22.0" ] && ok "版本顯示 $NEW_VERSION" || warn "版本異常: $NEW_VERSION"

echo ""
echo -e "${GREEN}${BOLD}=========================================${NC}"
echo -e "${GREEN}${BOLD}  v3.11.22.0 套用完成!${NC}"
echo -e "${GREEN}${BOLD}=========================================${NC}"
echo ""
echo "瀏覽器測試:"
echo "  http://192.168.1.221:5000/report (登入後看今日報告)"
echo "  Linux 卡片右下應有 [🔍 深度檢查] 按鈕"
echo ""
echo "Rollback (若有問題):"
echo "  sudo bash -c '"
echo "    cp -p $BACKUP_DIR/app.py $INSPECTION_HOME/webapp/app.py"
echo "    cp -p $BACKUP_DIR/report.html $INSPECTION_HOME/webapp/templates/report.html"
echo "    cp -p $BACKUP_DIR/version.json $INSPECTION_HOME/data/version.json"
echo "    rm -f $INSPECTION_HOME/webapp/routes/api_deep_check.py"
echo "    rm -f $INSPECTION_HOME/ansible/playbooks/deep_check.yml"
echo "    rm -rf $INSPECTION_HOME/scripts/smit_menu"
echo "    kill \$(pgrep -f gunicorn.*app:app); sleep 2"
echo "    # 手動重啟 gunicorn (見 script 中 [6] 的啟動指令)"
echo "  '"
echo ""
