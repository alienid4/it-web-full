#!/bin/bash
###############################################
#  v3.12.2.3-test-email-recipient installer
#
#  Bug fix: 測試 SMTP 強迫使用者設個人 Email 不合理
#           應優先用「通知設定收件人」(notify_email.to), fallback user.email
#
#  動作:
#    1. api_admin.py admin_test_email 函式改邏輯:
#       - 優先讀 notify_email.to[0]
#       - to 空 → fallback user.email
#       - 兩者都空 → 才報錯
#       - 訊息顯示寄到哪個 email + 來源 (收件人/帳號 email)
#    2. version.json → 3.12.2.3
#    3. 重啟 + 驗證
#
#  PREREQ: v3.12.2.1 或 v3.12.2.0 已套 (admin_test_email function 必須存在)
#  Idempotent: 偵測 # v3.12.2.3 marker → skip
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
echo -e "${CYAN}|  v3.12.2.3 hot-fix: 測試 SMTP 改用「收件人」清單           |${NC}"
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

API_ADMIN="$HOME_DIR/webapp/routes/api_admin.py"
VERSION_JSON="$HOME_DIR/data/version.json"

[ -f "$API_ADMIN" ]    || fail "缺檔: $API_ADMIN"
[ -f "$VERSION_JSON" ] || fail "缺檔: $VERSION_JSON"

CUR_VER=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['version'])" 2>/dev/null || echo "?")
info "目前版本: $CUR_VER"

# PREREQ check
if ! grep -q "def admin_test_email" "$API_ADMIN"; then
    fail "前置: api_admin.py 缺 admin_test_email function (請先裝 v3.12.2.0/2.1)"
fi

BACKUP_DIR="/var/backups/inspection/pre_v3.12.2.3_${TS}"

# ========== [1] 備份 ==========
echo -e "${BOLD}[1/4] 備份${NC}"
mkdir -p "$BACKUP_DIR"
cp -p "$API_ADMIN"    "$BACKUP_DIR/" && ok "api_admin.py → bak"
cp -p "$VERSION_JSON" "$BACKUP_DIR/" && ok "version.json → bak"
info "備份: $BACKUP_DIR"

OWNER=$(stat -c "%U:%G" "$API_ADMIN")

# ========== [2] 改 admin_test_email ==========
echo -e "${BOLD}[2/4] 改 admin_test_email 邏輯 (notify_email.to → fallback user.email)${NC}"
API_ADMIN_PATH="$API_ADMIN" python3 <<'PYEOF' || fail "api_admin.py 改寫失敗"
import re, os, sys
p = os.environ["API_ADMIN_PATH"]
s = open(p, encoding="utf-8").read()

if "# v3.12.2.3 admin_test_email" in s:
    print("  v3.12.2.3 admin_test_email 已存在, skip")
    sys.exit(0)

new_func = '''@bp.route("/settings/notify_email/test", methods=["POST"])
@admin_required
def admin_test_email():
    """v3.12.2.3 admin_test_email: 優先寄到「收件人」清單; fallback user.email"""
    from services.email_service import send_email
    from services.auth_service import get_user
    from datetime import datetime

    cfg = (get_all_settings().get("notify_email") or {})
    to_list = [t.strip() for t in (cfg.get("to") or []) if t and "@" in t]

    if to_list:
        to = to_list[0]
        source = f"通知設定收件人 ({len(to_list)} 筆中第 1 筆)"
    else:
        user = get_user(session.get("username")) or {}
        to = (user.get("email") or "").strip()
        source = "當前登入者帳號 Email (fallback)"

    if not to:
        return jsonify({
            "success": False,
            "error": "找不到收件 Email — 請在 admin#settings 設「收件人」, 或在「帳號設定」填 Email"
        }), 400

    try:
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        body = (
            "<div style='font-family:sans-serif;'>"
            "<h3>SMTP 測試信</h3>"
            f"<p><b>時間:</b> {ts}</p>"
            f"<p><b>觸發者:</b> {session.get('username')}</p>"
            f"<p><b>收件人:</b> {to}</p>"
            f"<p><b>收件來源:</b> {source}</p>"
            "<p>來源: 巡檢系統 admin#settings → 測試 SMTP 按鈕</p>"
            "<p style='color:#999;font-size:12px;border-top:1px solid #eee;padding-top:8px;margin-top:16px;'>"
            "收到這封信表示 SMTP 設定 OK ✅<br>"
            "若沒收到, 檢查垃圾信件夾 / Flask logs / SMTP relay log</p>"
            "</div>"
        )
        send_email(to, "[巡檢系統] SMTP 測試信", body)
        log_action(session["username"], "test_email",
                   f"測試 SMTP 寄到 {to} (來源: {source})",
                   request.remote_addr)
        return jsonify({
            "success": True,
            "message": f"測試信已寄到 {to} (來源: {source}), 請至信箱確認 (含垃圾信件)"
        })
    except Exception as e:
        return jsonify({"success": False, "error": f"寄信失敗: {type(e).__name__}: {e}"}), 500


'''

# 找原本 admin_test_email function (從 @bp.route 開頭, 到下一個 @bp.route 或 # ========== marker)
old_re = re.compile(
    r'@bp\.route\("/settings/notify_email/test"[^\n]*\n'
    r'@admin_required\s*\n'
    r'def admin_test_email\(\):.*?'
    r'(?=\n@bp\.route\(|\n# ==========)',
    re.DOTALL
)

m = old_re.search(s)
if not m:
    raise SystemExit("找不到原 admin_test_email 函式 block")

# 保留結尾 newlines 一致性: 找到後面緊跟的空行
old_block = m.group()
print(f"  matched: {len(old_block)} bytes ({old_block.count(chr(10))} lines)")

s = s.replace(old_block, new_func, 1)
open(p, 'w', encoding="utf-8").write(s)
print("  admin_test_email 邏輯已替換 → v3.12.2.3")
PYEOF
chown "$OWNER" "$API_ADMIN"
python3 -c "import ast; ast.parse(open('$API_ADMIN').read())" 2>&1 || fail "api_admin.py 語法錯! 從 $BACKUP_DIR 還原"
ok "api_admin.py 改寫 + 語法 OK"

# ========== [3] version.json ==========
echo -e "${BOLD}[3/4] 更新 version.json → 3.12.2.3${NC}"
VERSION_JSON_PATH="$VERSION_JSON" CHANGELOG_FILE="$SCRIPT_DIR/CHANGELOG_ENTRY.txt" python3 <<'PYEOF' || fail "version.json 更新失敗"
import json, datetime, os
p = os.environ["VERSION_JSON_PATH"]
d = json.load(open(p))
new_entry = open(os.environ["CHANGELOG_FILE"]).read().strip()

if any(e.startswith("3.12.2.3 ") for e in d.get("changelog", [])):
    print("  changelog 已含 3.12.2.3, skip prepend")
else:
    d.setdefault("changelog", []).insert(0, new_entry)

d["version"] = "3.12.2.3"
d["updated_at"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
print("  version.json → 3.12.2.3")
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
[ "$NEW_VER" = "3.12.2.3" ] && ok "版本 $NEW_VER ✅" || warn "版本異常: $NEW_VER"

if grep -q "v3.12.2.3 admin_test_email" "$API_ADMIN"; then ok "api_admin.py 含 v3.12.2.3 邏輯"; else warn "缺 v3.12.2.3 marker"; fi

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  v3.12.2.3 完成! $CUR_VER → $NEW_VER${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}測試 (你的場景: relay no-auth)${NC}:"
echo "  1. /admin#settings 強制 reload"
echo "  2. 收件人填 e.g. alien.lee@cathaysec.com.tw"
echo "  3. 點「儲存通知設定」"
echo "  4. 點「📨 測試 SMTP」 → 應寄到收件人 (不再強迫設個人 email)"
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo "  sudo cp -p $BACKUP_DIR/api_admin.py $API_ADMIN"
echo "  sudo cp -p $BACKUP_DIR/version.json $VERSION_JSON"
echo "  sudo systemctl restart itagent-web"
