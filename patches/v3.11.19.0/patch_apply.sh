#!/bin/bash
###############################################
#  ITAgent Patch Apply Script (enhanced)
#  Usage: sudo ./patch_apply.sh
#  Put this script + patch_info.txt + files/ (+ optional whls/, post_install.sh) 同目錄
###############################################
set -u

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"
CYAN="\033[0;36m"; BOLD="\033[1m"; NC="\033[0m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ok()   { echo -e "  ${GREEN}OK${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; exit 1; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }
info() { echo -e "  ${CYAN}-->${NC} $1"; }

# ========== 1. 讀設定 ==========
if [ -f /etc/default/itagent ]; then
    # shellcheck disable=SC1091
    source /etc/default/itagent
fi
: "${ITAGENT_HOME:=/opt/inspection}"
: "${ITAGENT_SERVICE:=itagent-web}"

[ -d "$ITAGENT_HOME" ] || fail "ITAGENT_HOME=$ITAGENT_HOME 找不到"

# ========== 2. 讀 patch_info.txt ==========
[ -f "$SCRIPT_DIR/patch_info.txt" ] || fail "patch_info.txt 不存在"
PATCH_VER=$(grep "^VERSION=" "$SCRIPT_DIR/patch_info.txt" | cut -d= -f2 | tr -d '\r')
PATCH_DESC=$(grep "^DESC=" "$SCRIPT_DIR/patch_info.txt" | cut -d= -f2- | tr -d '\r')
PATCH_FILES=$(grep "^FILES=" "$SCRIPT_DIR/patch_info.txt" | cut -d= -f2- | tr -d '\r')
REQUIRES_RESTART=$(grep "^REQUIRES_RESTART=" "$SCRIPT_DIR/patch_info.txt" | cut -d= -f2 | tr -d '\r')
REQUIRES_RESTART="${REQUIRES_RESTART:-yes}"

# 偵測額外資源
HAS_WHLS=0
HAS_POST=0
WHL_COUNT=0
[ -d "$SCRIPT_DIR/whls" ] && WHL_COUNT=$(find "$SCRIPT_DIR/whls" -name "*.whl" 2>/dev/null | wc -l)
[ "$WHL_COUNT" -gt 0 ] && HAS_WHLS=1
[ -f "$SCRIPT_DIR/post_install.sh" ] && HAS_POST=1

echo ""
echo -e "${CYAN}+==========================================+${NC}"
echo -e "${CYAN}|  ITAgent Patch Installer                 |${NC}"
echo -e "${CYAN}+==========================================+${NC}"
echo ""
echo -e "  Patch      : ${BOLD}${PATCH_VER}${NC}"
echo -e "  Desc       : ${PATCH_DESC}"
echo -e "  Target     : ${ITAGENT_HOME}"
echo -e "  Service    : ${ITAGENT_SERVICE}"
echo -e "  Files      : ${PATCH_FILES:-(看 files/)}"
echo -e "  Whls       : ${WHL_COUNT} 個 whl 檔"
echo -e "  Post hook  : $( [ $HAS_POST = 1 ] && echo yes || echo no )"
echo -e "  Restart    : ${REQUIRES_RESTART}"
echo ""
read -rp "  確定套用此 patch? (y/n) " ans
[[ ! "$ans" =~ ^[Yy]$ ]] && echo "Cancelled" && exit 0

# ========== 3. 備份 ==========
# v3.11.19.0: tar 改用寬容參數 + 不吞 stderr + 失敗時顯示原因 + 可選無備份續跑
echo ""
BACKUP_TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_DIR:-/var/backups/inspection}"
mkdir -p "$BACKUP_DIR" 2>/dev/null
if [ ! -w "$BACKUP_DIR" ]; then
    BACKUP_DIR="/tmp"
fi
BACKUP_FILE="$BACKUP_DIR/itagent_pre_patch_${PATCH_VER}_${BACKUP_TS}.tar.gz"
BACKUP_ERR="/tmp/itagent_backup_err_$$.log"
echo -e "${CYAN}--- Step 1/5 Backup ---${NC}"
info "備份路徑: $BACKUP_FILE"
if tar czf "$BACKUP_FILE" \
        --ignore-failed-read \
        --warning=no-file-ignored \
        --warning=no-file-changed \
        --warning=no-file-removed \
        --exclude="$(basename "$ITAGENT_HOME")/container" \
        --exclude="$(basename "$ITAGENT_HOME")/logs" \
        --exclude="$(basename "$ITAGENT_HOME")/__pycache__" \
        --exclude="*.pyc" \
        --exclude="*.pid" \
        --exclude="*.sock" \
        --exclude="*.swp" \
        -C "$(dirname "$ITAGENT_HOME")" "$(basename "$ITAGENT_HOME")" 2>"$BACKUP_ERR"; then
    ok "Backup: $BACKUP_FILE"
    if [ -s "$BACKUP_ERR" ]; then
        warn "tar 有警告 (已忽略, 見 $BACKUP_ERR)"
    fi
else
    echo -e "  ${RED}FAIL${NC} 備份失敗。tar 實際錯誤訊息:"
    tail -20 "$BACKUP_ERR" | sed 's/^/    /'
    echo ""
    echo -e "  ${YELLOW}常見原因${NC}:"
    echo "    - /tmp 或 $BACKUP_DIR 空間不夠 (df -h)"
    echo "    - 某個 socket/pipe 檔權限 (已 exclude *.sock 仍卡, 貼錯誤給我看)"
    echo "    - container/mongodb_data 權限 UID 999 (已 exclude container)"
    echo ""
    read -rp "  是否『無備份』繼續套 patch? (y=繼續 / 其他=中止) " cont
    if [[ ! "$cont" =~ ^[Yy]$ ]]; then
        exit 1
    fi
    BACKUP_FILE="(使用者選擇無備份繼續)"
    warn "未建立備份, 若要 rollback 需靠 git 或前次備份"
fi

# ========== 4. 套 files/ ==========
echo -e "${CYAN}--- Step 2/5 Apply files ---${NC}"
FILES_APPLIED=0
if [ -d "$SCRIPT_DIR/files" ]; then
    cd "$SCRIPT_DIR/files"
    while IFS= read -r f; do
        TARGET="$ITAGENT_HOME/$f"
        mkdir -p "$(dirname "$TARGET")"
        cp "$f" "$TARGET"
        ok "$f"
        FILES_APPLIED=$((FILES_APPLIED + 1))
    done < <(find . -type f | sed 's|^\./||')
    cd - >/dev/null
    info "共套用 $FILES_APPLIED 個檔案"
else
    warn "無 files/ 目錄，跳過檔案套用"
fi

# ========== 5. 裝 whls/ （離線 pip 安裝）==========
echo -e "${CYAN}--- Step 3/5 Install Python wheels ---${NC}"
if [ "$HAS_WHLS" = "1" ]; then
    PYBIN=$(command -v /usr/bin/python3 || command -v python3)
    info "使用 Python: $PYBIN"
    info "安裝 $WHL_COUNT 個 whl 到 system site-packages..."
    if $PYBIN -m pip install \
        --break-system-packages \
        --no-index --find-links="$SCRIPT_DIR/whls" \
        "$SCRIPT_DIR/whls"/*.whl >/tmp/patch_pip_$$.log 2>&1; then
        ok "pip install 完成"
    else
        warn "pip install 有錯誤，詳見 /tmp/patch_pip_$$.log"
        tail -10 /tmp/patch_pip_$$.log | sed 's/^/    /'
    fi
else
    info "無 whls/ 目錄，跳過 pip 步驟"
fi

# ========== 6. post_install.sh hook ==========
echo -e "${CYAN}--- Step 4/5 Post-install hook ---${NC}"
if [ "$HAS_POST" = "1" ]; then
    chmod +x "$SCRIPT_DIR/post_install.sh"
    info "執行 post_install.sh..."
    if ITAGENT_HOME="$ITAGENT_HOME" "$SCRIPT_DIR/post_install.sh"; then
        ok "post_install.sh 成功"
    else
        warn "post_install.sh 回傳非 0"
    fi
else
    info "無 post_install.sh，跳過"
fi

# ========== 7. 更新 version.json ==========
if [ -f "$ITAGENT_HOME/data/version.json" ]; then
    PATCH_VER="$PATCH_VER" PATCH_DESC="$PATCH_DESC" \
    VJPATH="$ITAGENT_HOME/data/version.json" python3 - <<'PYEOF'
import json, os, datetime
path = os.environ["VJPATH"]
with open(path, encoding="utf-8") as f:
    v = json.load(f)
new_ver = os.environ["PATCH_VER"]
desc = os.environ["PATCH_DESC"]
today = datetime.datetime.now().strftime("%Y-%m-%d")
v["version"] = new_ver
v["updated_at"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
v.setdefault("changelog", []).append(f"{new_ver} - {today}: {desc}")
with open(path, "w", encoding="utf-8") as f:
    json.dump(v, f, indent=2, ensure_ascii=False)
print(f"  version.json -> {new_ver}")
PYEOF
fi

# ========== 8. 重啟 + 驗證 ==========
echo -e "${CYAN}--- Step 5/5 Restart & verify ---${NC}"
if [ "$REQUIRES_RESTART" = "yes" ] || [ "$REQUIRES_RESTART" = "y" ]; then
    if systemctl restart "$ITAGENT_SERVICE" 2>/dev/null; then
        ok "服務已重啟: $ITAGENT_SERVICE"
    else
        warn "systemctl restart 失敗（service 不存在？）"
    fi
    sleep 3
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5000/ 2>/dev/null || echo "000")
    if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then
        ok "HTTP ping: $HTTP"
    else
        warn "HTTP ping: $HTTP（服務可能還沒好，看 journalctl -u $ITAGENT_SERVICE -n 30）"
    fi
else
    info "patch_info.txt REQUIRES_RESTART=no，跳過重啟"
fi

# ========== 完成 ==========
echo ""
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}  Patch ${PATCH_VER} 套用完成！${NC}"
echo -e "${GREEN}===========================================${NC}"
echo ""
echo -e "  ${BOLD}Rollback 指令${NC}:"
echo -e "    systemctl stop $ITAGENT_SERVICE"
echo -e "    tar xzf $BACKUP_FILE -C $(dirname "$ITAGENT_HOME")"
echo -e "    systemctl start $ITAGENT_SERVICE"
echo ""
