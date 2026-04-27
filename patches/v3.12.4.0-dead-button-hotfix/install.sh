#!/bin/bash
###############################################
#  v3.12.4.0-dead-button-hotfix installer
#
#  目的: admin#backups 有 4 個 dead button (createDbDump/importDbDump/
#        uploadPatch/rollbackPatch) JS 從沒實作, 點下去 ReferenceError.
#        v3.13.0.0 會補完, 在那之前先把它們灰掉避免使用者誤點.
#
#  動作:
#    1. admin.html 4 個 dead button 加 disabled + 灰掉樣式 + tooltip "Phase 2 開發中"
#    2. dbbackup-list / patch-history「載入中...」改 "📅 Phase 2 開發中 — 預計 v3.13.0.0"
#    3. version.json → 3.12.4.0
#    4. 重啟 itagent-web
#
#  Idempotent: 偵測 data-v3.12.4.0="disabled" attr → skip
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
echo -e "${CYAN}|  v3.12.4.0 dead button hot-fix (灰掉避免點下去報錯)        |${NC}"
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

ADMIN_HTML="$HOME_DIR/webapp/templates/admin.html"
VERSION_JSON="$HOME_DIR/data/version.json"

[ -f "$ADMIN_HTML" ]   || fail "缺檔: $ADMIN_HTML"
[ -f "$VERSION_JSON" ] || fail "缺檔: $VERSION_JSON"

CUR_VER=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['version'])" 2>/dev/null || echo "?")
info "目前版本: $CUR_VER"

BACKUP_DIR="/var/backups/inspection/pre_v3.12.4.0_${TS}"
mkdir -p "$BACKUP_DIR"

# ========== [1] 備份 ==========
echo -e "${BOLD}[1/4] 備份${NC}"
cp -p "$ADMIN_HTML"   "$BACKUP_DIR/" && ok "admin.html → bak"
cp -p "$VERSION_JSON" "$BACKUP_DIR/" && ok "version.json → bak"
info "備份: $BACKUP_DIR"

OWNER=$(stat -c "%U:%G" "$ADMIN_HTML")

# ========== [2] 改 admin.html (灰掉 4 button + 2 loader) ==========
echo -e "${BOLD}[2/4] 灰掉 admin.html dead button${NC}"
ADMIN_HTML_PATH="$ADMIN_HTML" python3 <<'PYEOF' || fail "admin.html 改寫失敗"
import os, sys
p = os.environ["ADMIN_HTML_PATH"]
s = open(p, encoding="utf-8").read()

if 'data-v3.12.4.0="disabled"' in s:
    print("  v3.12.4.0 marker 已存在, skip")
    sys.exit(0)

TIP = "Phase 2 開發中 (預計 v3.13.0.0 補上)"
DISABLED_STYLE = "opacity:0.5;cursor:not-allowed;"

# === 1. createDbDump 按鈕 ===
old1 = '<button class="btn btn-primary" onclick="createDbDump()">立即 Dump</button>'
new1 = f'<button class="btn btn-primary" disabled style="{DISABLED_STYLE}" title="{TIP}" data-v3.12.4.0="disabled">立即 Dump</button>'
if old1 not in s:
    raise SystemExit("找不到 createDbDump button")
s = s.replace(old1, new1, 1)
print("  createDbDump button 已 disable")

# === 2. importDbDump (匯入 Dump button - 觸發 file input) ===
old2 = '<button class="btn" style="background:var(--g2);color:white;" onclick="document.getElementById(\'dbimport-upload\').click()">匯入 Dump</button>'
new2 = f'<button class="btn" style="background:var(--c4);color:white;{DISABLED_STYLE}" disabled title="{TIP}" data-v3.12.4.0="disabled">匯入 Dump</button>'
if old2 not in s:
    raise SystemExit("找不到 匯入 Dump button")
s = s.replace(old2, new2, 1)
print("  匯入 Dump button 已 disable")

# === 3. 上傳 Patch button (橘色, 觸發 patch-upload file input) ===
old3 = '<button class="btn" style="background:var(--orange);color:white;" onclick="document.getElementById(\'patch-upload\').click()">上傳 Patch</button>'
new3 = f'<button class="btn" style="background:var(--c4);color:white;{DISABLED_STYLE}" disabled title="{TIP}" data-v3.12.4.0="disabled">上傳 Patch</button>'
if old3 not in s:
    raise SystemExit("找不到 上傳 Patch button")
s = s.replace(old3, new3, 1)
print("  上傳 Patch button 已 disable")

# === 4. rollbackPatch 按鈕 ===
old4 = '<button class="btn btn-danger" onclick="rollbackPatch()">回滾上一版</button>'
new4 = f'<button class="btn btn-danger" disabled style="{DISABLED_STYLE}" title="{TIP}" data-v3.12.4.0="disabled">回滾上一版</button>'
if old4 not in s:
    raise SystemExit("找不到 rollbackPatch button")
s = s.replace(old4, new4, 1)
print("  回滾上一版 button 已 disable")

# === 5. applyPatch 按鈕 (在 hidden patch-preview 內, 萬一被顯示也擋掉) ===
old5 = '<button class="btn btn-primary" onclick="applyPatch()">確認套用</button>'
new5 = f'<button class="btn btn-primary" disabled style="{DISABLED_STYLE}" title="{TIP}" data-v3.12.4.0="disabled">確認套用</button>'
if old5 in s:
    s = s.replace(old5, new5, 1)
    print("  確認套用 button 已 disable")
else:
    print("  (找不到 applyPatch button, skip - 可能 hidden preview 結構變了)")

# === 6. dbbackup-list loader (永遠停在「載入中」) ===
PHASE2_MSG = ('<div style="color:var(--c3);padding:12px;background:var(--bg);'
              'border-radius:6px;text-align:center;font-size:13px;">'
              '📅 Phase 2 開發中 — 預計 v3.13.0.0 上線'
              '</div>')

old6 = '<div id="dbbackup-list">載入中...</div>'
new6 = f'<div id="dbbackup-list" data-v3.12.4.0="placeholder">{PHASE2_MSG}</div>'
if old6 in s:
    s = s.replace(old6, new6, 1)
    print("  dbbackup-list 載入中... → Phase 2 占位符")
else:
    print("  (找不到 dbbackup-list 載入中, skip)")

# === 7. patch-history loader ===
old7 = '<div id="patch-history">載入中...</div>'
new7 = f'<div id="patch-history" data-v3.12.4.0="placeholder">{PHASE2_MSG}</div>'
if old7 in s:
    s = s.replace(old7, new7, 1)
    print("  patch-history 載入中... → Phase 2 占位符")
else:
    print("  (找不到 patch-history 載入中, skip)")

open(p, 'w', encoding="utf-8").write(s)
print("  admin.html 已寫回")
PYEOF
chown "$OWNER" "$ADMIN_HTML"
ok "admin.html 改寫完成"

# ========== [3] version.json ==========
echo -e "${BOLD}[3/4] 更新 version.json → 3.12.4.0${NC}"
VERSION_JSON_PATH="$VERSION_JSON" CHANGELOG_FILE="$SCRIPT_DIR/CHANGELOG_ENTRY.txt" python3 <<'PYEOF' || fail "version.json 更新失敗"
import json, datetime, os
p = os.environ["VERSION_JSON_PATH"]
d = json.load(open(p))
new_entry = open(os.environ["CHANGELOG_FILE"]).read().strip()
if any(e.startswith("3.12.4.0 ") for e in d.get("changelog", [])):
    print("  changelog 已含 3.12.4.0, skip prepend")
else:
    d.setdefault("changelog", []).insert(0, new_entry)
d["version"] = "3.12.4.0"
d["updated_at"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
print("  version.json → 3.12.4.0")
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
[ "$NEW_VER" = "3.12.4.0" ] && ok "版本 $NEW_VER ✅" || warn "版本異常"

DIS_COUNT=$(grep -c 'data-v3.12.4.0="disabled"' "$ADMIN_HTML" 2>/dev/null || echo 0)
echo "  disabled button 數量: $DIS_COUNT (預期 4-5)"

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  v3.12.4.0 完成! $CUR_VER → $NEW_VER${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}測試${NC}: 強制 reload /admin#backups"
echo "  - 立即 Dump / 匯入 Dump / 上傳 Patch / 回滾上一版 4 顆按鈕應變灰色不可點"
echo "  - 滑鼠 hover 應顯示 'Phase 2 開發中 (預計 v3.13.0.0 補上)'"
echo "  - 「載入中...」改成「📅 Phase 2 開發中 — 預計 v3.13.0.0 上線」"
echo "  - 「立即備份」(createBackup) 仍然可用 (這個有實作)"
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo "  sudo cp -p $BACKUP_DIR/admin.html $ADMIN_HTML"
echo "  sudo cp -p $BACKUP_DIR/version.json $VERSION_JSON"
echo "  sudo systemctl restart itagent-web"
