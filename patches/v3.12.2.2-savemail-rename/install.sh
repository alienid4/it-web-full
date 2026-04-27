#!/bin/bash
###############################################
#  v3.12.2.2-savemail-rename installer
#
#  Bug fix: admin.js 的 saveEmail (SMTP 通知設定) 與 admin.html 的 saveEmail (帳號 Modal Email)
#           同名衝突, admin.html inline script 後載入會覆蓋 admin.js, 導致點「儲存通知設定」
#           實際跑的是帳號 modal 的 saveEmail (找 acct-email 結果 null → 錯誤).
#
#  動作:
#    1. admin.js: function saveEmail (v3.12.2.1) → function saveNotifyEmail
#    2. admin.js: Email block button onclick="saveEmail()" → onclick="saveNotifyEmail()"
#    3. version.json → 3.12.2.2
#    4. 重啟 itagent-web + 驗證
#
#  不動 admin.html 的 saveEmail (帳號 modal 早就存在的, 維持原名相容)
#
#  PREREQ: 必須先裝 v3.12.2.1 (admin.js 內已有 /* v3.12.2.1 saveEmail */ marker)
#  Idempotent: 偵測 saveNotifyEmail 已存在 → skip
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
echo -e "${CYAN}|  v3.12.2.2 hot-fix: saveEmail rename → saveNotifyEmail     |${NC}"
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

ADMIN_JS="$HOME_DIR/webapp/static/js/admin.js"
VERSION_JSON="$HOME_DIR/data/version.json"

[ -f "$ADMIN_JS" ]    || fail "缺檔: $ADMIN_JS"
[ -f "$VERSION_JSON" ] || fail "缺檔: $VERSION_JSON"

CUR_VER=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['version'])" 2>/dev/null || echo "?")
info "目前版本: $CUR_VER"

# PREREQ check: 必須有 v3.12.2.1 saveEmail marker
if ! grep -q "/\* v3.12.2.1 saveEmail \*/" "$ADMIN_JS" && ! grep -q "function saveNotifyEmail" "$ADMIN_JS"; then
    fail "前置: 必須先裝 v3.12.2.1 (admin.js 缺 v3.12.2.1 saveEmail marker)"
fi

BACKUP_DIR="/var/backups/inspection/pre_v3.12.2.2_${TS}"

# ========== [1] 備份 ==========
echo -e "${BOLD}[1/4] 備份${NC}"
mkdir -p "$BACKUP_DIR"
cp -p "$ADMIN_JS"     "$BACKUP_DIR/" && ok "admin.js → bak"
cp -p "$VERSION_JSON" "$BACKUP_DIR/" && ok "version.json → bak"
info "備份: $BACKUP_DIR"

OWNER=$(stat -c "%U:%G" "$ADMIN_JS")

# ========== [2] rename ==========
echo -e "${BOLD}[2/4] rename saveEmail → saveNotifyEmail (admin.js)${NC}"
ADMIN_JS_PATH="$ADMIN_JS" python3 <<'PYEOF' || fail "admin.js rename 失敗"
import os
p = os.environ["ADMIN_JS_PATH"]
s = open(p, encoding="utf-8").read()

if "function saveNotifyEmail" in s:
    print("  saveNotifyEmail 已存在, skip")
    raise SystemExit(0)

# 1) function saveEmail() { /* v3.12.2.1 saveEmail */ → function saveNotifyEmail() { /* v3.12.2.2 saveNotifyEmail */
old1 = "function saveEmail() { /* v3.12.2.1 saveEmail */"
new1 = "function saveNotifyEmail() { /* v3.12.2.2 saveNotifyEmail */"
if old1 not in s:
    raise SystemExit(f"找不到 marker: {old1!r}")
s = s.replace(old1, new1, 1)
print("  function 簽名 已 rename")

# 2) Email 區塊 button onclick="saveEmail()">儲存通知設定 → onclick="saveNotifyEmail()">儲存通知設定
old2 = "onclick=\"saveEmail()\">儲存通知設定"
new2 = "onclick=\"saveNotifyEmail()\">儲存通知設定"
cnt = s.count(old2)
if cnt == 0:
    raise SystemExit(f"找不到 button onclick (預期 1, 實際 0)")
if cnt > 1:
    print(f"  警告: button onclick marker 出現 {cnt} 次, 全部 replace")
s = s.replace(old2, new2)
print(f"  button onclick 已 rename ({cnt} 處)")

open(p, 'w', encoding="utf-8").write(s)
PYEOF
chown "$OWNER" "$ADMIN_JS"
ok "admin.js rename 完成"

# ========== [3] version.json ==========
echo -e "${BOLD}[3/4] 更新 version.json → 3.12.2.2${NC}"
VERSION_JSON_PATH="$VERSION_JSON" CHANGELOG_FILE="$SCRIPT_DIR/CHANGELOG_ENTRY.txt" python3 <<'PYEOF' || fail "version.json 更新失敗"
import json, datetime, os
p = os.environ["VERSION_JSON_PATH"]
d = json.load(open(p))
new_entry = open(os.environ["CHANGELOG_FILE"]).read().strip()

if any(e.startswith("3.12.2.2 ") for e in d.get("changelog", [])):
    print("  changelog 已含 3.12.2.2, skip prepend")
else:
    d.setdefault("changelog", []).insert(0, new_entry)

d["version"] = "3.12.2.2"
d["updated_at"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
print("  version.json → 3.12.2.2")
PYEOF
chown "$OWNER" "$VERSION_JSON"
ok "version.json OK"

# ========== [4] 重啟 + 驗證 ==========
echo -e "${BOLD}[4/4] 重啟 + 驗證${NC}"
RESTARTED=0
for svc in itagent-web inspection inspection-web; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" && ok "systemctl restart $svc" && RESTARTED=1 && break
    fi
done
[ "$RESTARTED" -eq 1 ] || warn "沒偵測到 Flask service, 請手動重啟"
sleep 2

NEW_VER=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['version'])" 2>/dev/null || echo "?")
[ "$NEW_VER" = "3.12.2.2" ] && ok "版本 $NEW_VER ✅" || warn "版本異常: $NEW_VER"

if grep -q "function saveNotifyEmail" "$ADMIN_JS"; then ok "admin.js 含 saveNotifyEmail"; else warn "admin.js 缺 saveNotifyEmail"; fi
if ! grep -q "function saveEmail() { /\* v3.12.2.1 saveEmail \*/" "$ADMIN_JS"; then ok "舊 saveEmail (v3.12.2.1) marker 已消失"; else warn "舊 saveEmail marker 還在 (rename 沒生效?)"; fi

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  v3.12.2.2 完成! $CUR_VER → $NEW_VER${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}測試${NC}:"
echo "  1. 強制 reload /admin#settings (Ctrl+Shift+R 清 JS cache)"
echo "  2. 點「儲存通知設定」應正常儲存 (不再噴錯)"
echo "  3. 點導覽列「帳號設定」→ 設好 Email → 儲存"
echo "  4. 回 admin#settings 點「📨 測試 SMTP」應寄出測試信"
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo "  sudo cp -p $BACKUP_DIR/admin.js     $ADMIN_JS"
echo "  sudo cp -p $BACKUP_DIR/version.json $VERSION_JSON"
echo "  sudo systemctl restart itagent-web"
