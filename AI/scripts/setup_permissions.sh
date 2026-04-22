#!/usr/bin/env bash
# setup_permissions.sh — 巡檢系統檔案權限架構升級
# 目的：建立 itagent group、設定 sysinfra:itagent 所有權、setgid 繼承
# 用法：sudo ./setup_permissions.sh           # 互動確認
#       sudo ./setup_permissions.sh --yes     # 不問直接跑
#       sudo ./setup_permissions.sh --dry     # 只印不做
#       sudo ./setup_permissions.sh --rollback  # 回滾到全 root:root

set -u

R=$'\e[1;31m'; G=$'\e[1;32m'; Y=$'\e[1;33m'
C=$'\e[1;36m'; B=$'\e[1;34m'; N=$'\e[0m'

ITAGENT_HOME="${ITAGENT_HOME:-/opt/inspection}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/inspection}"
AP_GROUP="${AP_GROUP:-itagent}"
SVC_USER="${SVC_USER:-sysinfra}"
CALLER="${SUDO_USER:-$(whoami)}"

DRY_RUN=0
AUTO_YES=0
ROLLBACK=0

for arg in "$@"; do
    case "$arg" in
        --dry|--dry-run) DRY_RUN=1 ;;
        --yes|-y) AUTO_YES=1 ;;
        --rollback) ROLLBACK=1 ;;
        -h|--help)
            sed -n '2,6p' "$0" | sed 's/^# *//'
            exit 0 ;;
    esac
done

LOG_FILE="/tmp/setup_permissions_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

ok()    { echo -e "  ${G}OK${N} $1"; }
fail()  { echo -e "  ${R}FAIL${N} $1"; }
warn()  { echo -e "  ${Y}WARN${N} $1"; }
info()  { echo -e "  ${C}-->${N} $1"; }
step()  { echo -e "\n${B}== $1 ==${N}"; }

run() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [DRY] $*"
    else
        eval "$@"
    fi
}

# ========== 前置檢查 ==========
if [ "$EUID" -ne 0 ] && [ "$DRY_RUN" = "0" ]; then
    fail "請用 sudo 執行"
    exit 1
fi

echo -e "${B}============================================${N}"
echo -e "${B}  巡檢系統權限架構升級${N}"
echo -e "${B}============================================${N}"
echo "  目標目錄: $ITAGENT_HOME"
echo "  備份目錄: $BACKUP_DIR"
echo "  AP Group: $AP_GROUP"
echo "  Service user: $SVC_USER"
echo "  呼叫者: $CALLER"
echo "  模式: $([ $DRY_RUN = 1 ] && echo DRY-RUN || echo EXECUTE)$([ $ROLLBACK = 1 ] && echo ' / ROLLBACK')"
echo "  LOG: $LOG_FILE"
echo ""

# ========== ROLLBACK 分支 ==========
if [ "$ROLLBACK" = "1" ]; then
    step "ROLLBACK — 回滾到全 root:root"
    if [ "$AUTO_YES" != "1" ]; then
        read -r -p "  確定回滾？(y/N) " ans
        [ "$ans" != "y" ] && { warn "已取消"; exit 0; }
    fi
    run "chown -R root:root '$ITAGENT_HOME'"
    run "chmod -R u+rwX,go+rX,go-w '$ITAGENT_HOME'"
    run "chmod 755 '$ITAGENT_HOME'"
    [ -d "$BACKUP_DIR" ] && run "chown -R root:root '$BACKUP_DIR'"
    ok "Rollback 完成"
    echo ""
    echo "  注意：itagent group 沒刪（如要刪: groupdel $AP_GROUP）"
    exit 0
fi

# ========== 0. 檢查 sysinfra 帳號 ==========
step "[0/10] 檢查 $SVC_USER 帳號"
if ! id "$SVC_USER" >/dev/null 2>&1; then
    fail "找不到 $SVC_USER 帳號"
    info "建帳號: useradd -r -m -s /bin/bash $SVC_USER"
    exit 2
fi
ok "$SVC_USER 存在: $(id "$SVC_USER")"

# ========== 1. 建 AP group ==========
step "[1/10] 建立 $AP_GROUP group"
if getent group "$AP_GROUP" >/dev/null 2>&1; then
    ok "$AP_GROUP 已存在"
else
    run "groupadd -r '$AP_GROUP'"
    ok "$AP_GROUP 已建立"
fi

# ========== 2. 加 sysinfra 到 group ==========
step "[2/10] 將 $SVC_USER 加入 $AP_GROUP"
if id -nG "$SVC_USER" | tr ' ' '\n' | grep -qx "$AP_GROUP"; then
    ok "$SVC_USER 已在 $AP_GROUP"
else
    run "usermod -aG '$AP_GROUP' '$SVC_USER'"
    ok "$SVC_USER 已加入 $AP_GROUP"
fi

# ========== 3. 加呼叫者到 group ==========
step "[3/10] 將呼叫者 $CALLER 加入 $AP_GROUP"
if [ "$CALLER" = "root" ]; then
    info "呼叫者是 root，不加入 group（root 本就能存取）"
elif id -nG "$CALLER" | tr ' ' '\n' | grep -qx "$AP_GROUP"; then
    ok "$CALLER 已在 $AP_GROUP"
else
    run "usermod -aG '$AP_GROUP' '$CALLER'"
    ok "$CALLER 已加入 $AP_GROUP"
    warn "需要 newgrp $AP_GROUP 或重新登入才生效（當下 shell 還是舊 group list）"
fi

# ========== 4. 備份目錄建立 ==========
step "[4/10] 確保備份目錄存在"
if [ ! -d "$BACKUP_DIR" ]; then
    run "mkdir -p '$BACKUP_DIR'"
    ok "建立 $BACKUP_DIR"
else
    ok "$BACKUP_DIR 已存在"
fi

# ========== 5. 主目錄 chown ==========
step "[5/10] 主目錄所有權改 $SVC_USER:$AP_GROUP"
if [ ! -d "$ITAGENT_HOME" ]; then
    fail "找不到 $ITAGENT_HOME"
    exit 3
fi
run "chown -R '$SVC_USER:$AP_GROUP' '$ITAGENT_HOME'"
run "chown -R '$SVC_USER:$AP_GROUP' '$BACKUP_DIR'"
ok "chown 完成"

# ========== 6. 主目錄 chmod 750 ==========
step "[6/10] 主目錄權限 750"
run "chmod 750 '$ITAGENT_HOME'"
for d in webapp ansible scripts; do
    [ -d "$ITAGENT_HOME/$d" ] && run "chmod -R u+rwX,g+rX,g-w,o-rwx '$ITAGENT_HOME/$d'" && run "find '$ITAGENT_HOME/$d' -type d -exec chmod 750 {} +"
done
ok "webapp/ ansible/ scripts/ 權限設好"

# ========== 7. 可寫目錄 2770 (setgid) ==========
step "[7/10] 可寫目錄 2770 + setgid（新檔繼承 group）"
for d in "$ITAGENT_HOME/data" "$ITAGENT_HOME/logs" "$BACKUP_DIR"; do
    if [ -d "$d" ]; then
        run "chmod 2770 '$d'"
        # 對現有子目錄也套用，且所有檔案要 group 可讀寫
        run "find '$d' -type d -exec chmod 2770 {} +"
        run "find '$d' -type f -exec chmod 660 {} + 2>/dev/null || true"
        ok "$d → 2770 (setgid)"
    else
        warn "$d 不存在，建立中..."
        run "mkdir -p '$d'"
        run "chown '$SVC_USER:$AP_GROUP' '$d'"
        run "chmod 2770 '$d'"
    fi
done

# ========== 8. 機密檔案保護 ==========
step "[8/10] 機密檔案 600 獨占"
for f in "$ITAGENT_HOME/.vault_pass" "$ITAGENT_HOME/.env" "$ITAGENT_HOME/webapp/config.py"; do
    if [ -f "$f" ]; then
        run "chown '$SVC_USER:$SVC_USER' '$f'"
        run "chmod 600 '$f'"
        ok "$f → 600 sysinfra:sysinfra"
    fi
done
# SSH key（若存在）
for kd in /home/$SVC_USER/.ssh $ITAGENT_HOME/.ssh; do
    if [ -d "$kd" ]; then
        run "chown -R '$SVC_USER:$SVC_USER' '$kd'"
        run "chmod 700 '$kd'"
        run "find '$kd' -type f ! -name '*.pub' -exec chmod 600 {} + 2>/dev/null || true"
        run "find '$kd' -type f -name '*.pub' -exec chmod 644 {} + 2>/dev/null || true"
        ok "$kd SSH key 權限修正"
    fi
done

# ========== 9. 執行腳本 750 ==========
step "[9/10] 執行腳本 750"
for f in "$ITAGENT_HOME"/*.sh "$ITAGENT_HOME/scripts"/*.sh "$ITAGENT_HOME/scripts"/*.py; do
    [ -f "$f" ] && run "chmod 750 '$f'"
done
ok "腳本執行權限設好"

# ========== 10. container/ 保留 root ==========
step "[10/10] container/ 保留 root（podman rootful 不動）"
if [ -d "$ITAGENT_HOME/container" ]; then
    run "chown -R root:root '$ITAGENT_HOME/container'"
    run "chmod 755 '$ITAGENT_HOME/container'"
    ok "container/ → root:root (podman 資料，不受本腳本影響)"
fi

# ========== 環境檔（/etc/default/itagent）==========
if [ -f /etc/default/itagent ]; then
    step "[Extra] /etc/default/itagent 權限"
    run "chown root:'$AP_GROUP' /etc/default/itagent"
    run "chmod 640 /etc/default/itagent"
    ok "/etc/default/itagent → root:$AP_GROUP 640"
fi

# ========== 驗證 ==========
step "驗證"
echo ""
echo "  ${C}頂層目錄:${N}"
ls -la "$ITAGENT_HOME" | head -15
echo ""
echo "  ${C}setgid 設定（應看到 s in group bit, 例 drwxrws---）:${N}"
ls -lad "$ITAGENT_HOME/data" "$ITAGENT_HOME/logs" "$BACKUP_DIR" 2>/dev/null
echo ""
echo "  ${C}機密檔案:${N}"
ls -la "$ITAGENT_HOME/.vault_pass" "$ITAGENT_HOME/.env" "$ITAGENT_HOME/webapp/config.py" 2>/dev/null

# Setgid 繼承測試
if [ "$DRY_RUN" = "0" ]; then
    echo ""
    echo "  ${C}setgid 繼承測試（用 $SVC_USER 建檔）:${N}"
    TEST_FILE="$ITAGENT_HOME/data/.perm_test_$$"
    sudo -u "$SVC_USER" touch "$TEST_FILE" 2>/dev/null && {
        GROUP_OF_FILE=$(stat -c '%G' "$TEST_FILE")
        if [ "$GROUP_OF_FILE" = "$AP_GROUP" ]; then
            ok "新檔繼承 group = $AP_GROUP ✓"
        else
            fail "新檔 group = $GROUP_OF_FILE (預期 $AP_GROUP) — setgid 沒生效？"
        fi
        rm -f "$TEST_FILE"
    } || warn "setgid 測試失敗（$SVC_USER 無法寫入）"
fi

echo ""
echo -e "${G}============================================${N}"
echo -e "${G}  權限架構升級完成${N}"
echo -e "${G}============================================${N}"
echo ""
echo "  LOG: $LOG_FILE"
echo ""
echo "  ${Y}重要提醒${N}:"
echo "  1. 如果你剛被加入 $AP_GROUP，需要: ${C}newgrp $AP_GROUP${N} 或重新登入"
echo "  2. 目前服務還是 root 跑（無變動）。要改服務 user 走下一個 patch (v3.11.5.0)"
echo "  3. 回滾: sudo $0 --rollback"
