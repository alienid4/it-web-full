#!/bin/bash
###############################################
#  sync_221_to_v3.11.21.sh
#  在 221 (家裡 secansible) 上執行
#  把 v3.11.6.0 整碼同步到 v3.11.21.0
#
#  使用方式 (2 擇 1):
#    [A] 在 221 直接 git clone (需 GitHub SSH key 或 PAT):
#        bash sync_221_to_v3.11.21.sh git
#
#    [B] 從 Windows 拉好 tarball 再 scp 上去:
#        # Windows bash:
#        #   cd "C:/Users/User/OneDrive/2025 Data/AI LAB/claude code"
#        #   tar czf /tmp/it-web-latest.tar.gz -C . AI
#        #   scp /tmp/it-web-latest.tar.gz root@192.168.1.221:/tmp/
#        #   scp scripts/sync_221_to_v3.11.21.sh root@192.168.1.221:/tmp/
#        # 221 bash:
#        bash /tmp/sync_221_to_v3.11.21.sh tarball /tmp/it-web-latest.tar.gz
###############################################
set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

INSPECTION_HOME="${INSPECTION_HOME:-/opt/inspection}"
TS=$(date +%Y%m%d_%H%M)
MODE="${1:-}"
TARBALL="${2:-/tmp/it-web-latest.tar.gz}"
WORK_DIR="/tmp/it-web-sync-${TS}"

ok()   { echo -e "  ${GREEN}OK${NC}   $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; exit 1; }
info() { echo -e "  ${CYAN}-->${NC}  $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }

echo ""
echo -e "${CYAN}+=====================================================+${NC}"
echo -e "${CYAN}|  221 整碼同步 v3.11.6.0 --> v3.11.21.0              |${NC}"
echo -e "${CYAN}+=====================================================+${NC}"
echo ""

# ========== 0. 參數檢查 ==========
if [ -z "$MODE" ]; then
    echo "Usage:"
    echo "  $0 git                         # 在 221 用 git clone"
    echo "  $0 tarball <path-to-tar.gz>    # 用本地 tarball (Windows 先 scp 上來)"
    exit 1
fi

# ========== 1. 前置檢查 ==========
echo -e "${BOLD}[1/7] 前置檢查${NC}"
[ "$(id -u)" -eq 0 ] || fail "請用 root 或 sudo 執行"
[ -d "$INSPECTION_HOME" ] || fail "找不到 $INSPECTION_HOME"
CUR_VERSION=$(cat ${INSPECTION_HOME}/data/version.json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])' 2>/dev/null || echo "unknown")
info "目前版本: $CUR_VERSION"
ok "root + $INSPECTION_HOME 存在"

# ========== 2. 備份 ==========
echo ""
echo -e "${BOLD}[2/7] 備份 /opt/inspection${NC}"
BACKUP_DIR="/opt/inspection.bak.${TS}"
if [ -d "$BACKUP_DIR" ]; then
    warn "備份目錄已存在: $BACKUP_DIR (跳過)"
else
    cp -a "$INSPECTION_HOME" "$BACKUP_DIR" || fail "備份失敗"
    ok "備份至 $BACKUP_DIR ($(du -sh $BACKUP_DIR | cut -f1))"
fi

# ========== 3. 取得最新碼 ==========
echo ""
echo -e "${BOLD}[3/7] 取得最新碼 (mode: $MODE)${NC}"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

case "$MODE" in
    git)
        info "git clone alienid4/it-web-full (私人 repo, 需要 SSH key 或 PAT)"
        if ! git clone --depth 1 https://github.com/alienid4/it-web-full.git it-web-latest 2>/dev/null; then
            fail "git clone 失敗, 請改用 tarball 模式"
        fi
        SRC="$WORK_DIR/it-web-latest/AI"
        ok "clone 成功"
        ;;
    tarball)
        [ -f "$TARBALL" ] || fail "找不到 tarball: $TARBALL"
        info "解壓 $TARBALL"
        tar xzf "$TARBALL" -C "$WORK_DIR" || fail "tarball 解壓失敗"
        SRC="$WORK_DIR/AI"
        ok "解壓成功"
        ;;
    *) fail "未知模式: $MODE (支援 git / tarball)" ;;
esac

[ -d "$SRC" ] || fail "找不到 AI/ 目錄於 $SRC"
NEW_VERSION=$(cat ${SRC}/data/version.json | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])' 2>/dev/null || echo "unknown")
info "新版本: $NEW_VERSION"

# ========== 4. 覆蓋 webapp / scripts / ansible ==========
echo ""
echo -e "${BOLD}[4/7] 覆蓋 webapp + scripts + ansible${NC}"

for sub in webapp scripts ansible; do
    if [ -d "$SRC/$sub" ]; then
        info "覆蓋 $sub"
        rsync -a --delete \
              --exclude='__pycache__' \
              "$SRC/$sub/" "$INSPECTION_HOME/$sub/" || fail "rsync $sub 失敗"
        ok "$sub 完成"
    else
        warn "$SRC/$sub 不存在, 跳過"
    fi
done

# ========== 5. 保留 runtime data, 只更新 version.json ==========
echo ""
echo -e "${BOLD}[5/7] 更新 data/version.json (保留其他 data)${NC}"
info "僅更新 version.json, 保留 reports/ hosts.json hosts.db inspection.json 等"
cp "$SRC/data/version.json" "$INSPECTION_HOME/data/version.json" || fail "version.json 更新失敗"
ok "version.json 更新為 $NEW_VERSION"

# ========== 6. 修權限 ==========
echo ""
echo -e "${BOLD}[6/7] 修權限${NC}"
chown -R sysinfra:itagent "$INSPECTION_HOME/webapp" "$INSPECTION_HOME/scripts" "$INSPECTION_HOME/ansible" "$INSPECTION_HOME/data/version.json" 2>/dev/null || warn "chown 部分失敗 (可能是 user/group 名字不同, 檢查一下)"
find "$INSPECTION_HOME/scripts" -name "*.sh" -exec chmod 750 {} \; 2>/dev/null
ok "權限修正"

# ========== 7. Restart Flask ==========
echo ""
echo -e "${BOLD}[7/7] Restart Flask${NC}"
if systemctl list-units --type=service | grep -q "inspection.service"; then
    systemctl restart inspection && ok "systemctl restart inspection 成功" || fail "systemctl restart inspection 失敗"
elif pgrep -f "python3 app.py" >/dev/null; then
    info "找到 python3 app.py 行程, 重啟中"
    pkill -f "python3 app.py" 2>/dev/null
    sleep 1
    cd "$INSPECTION_HOME/webapp" && nohup sudo -u sysinfra python3 app.py >> "$INSPECTION_HOME/logs/flask.log" 2>&1 &
    sleep 2
    pgrep -f "python3 app.py" >/dev/null && ok "Flask 重啟成功" || fail "Flask 沒起來, 看 $INSPECTION_HOME/logs/flask.log"
else
    warn "找不到既有 Flask 行程, 請手動啟動"
fi

echo ""
echo -e "${GREEN}${BOLD}=========================================${NC}"
echo -e "${GREEN}${BOLD}  同步完成! $CUR_VERSION --> $NEW_VERSION${NC}"
echo -e "${GREEN}${BOLD}=========================================${NC}"
echo ""
echo "驗證指令:"
echo "  curl -s http://localhost:5000/api/version | python3 -m json.tool"
echo "  # 或 browser 開 http://192.168.1.221:5000  看右上角版本"
echo ""
echo "若有問題, rollback:"
echo "  systemctl stop inspection"
echo "  mv $INSPECTION_HOME ${INSPECTION_HOME}.failed.${TS}"
echo "  mv $BACKUP_DIR $INSPECTION_HOME"
echo "  systemctl start inspection"
echo ""
