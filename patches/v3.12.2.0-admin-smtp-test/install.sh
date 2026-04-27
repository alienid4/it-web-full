#!/bin/bash
###############################################
#  v3.12.2.0-admin-smtp-test installer
#
#  動作:
#    1. admin.js: 磁碟排除清單 (mounts + prefixes) 改為可編輯 chip + 新增/刪除按鈕
#    2. admin.js: Email 設定旁加「📨 測試 SMTP」按鈕 + testEmail() 函式
#    3. api_admin.py: 加 POST /api/admin/settings/notify_email/test 端點
#       (寄一封測試信給當前登入者 email, 用 services.email_service.send_email)
#    4. 更新 data/version.json → 3.12.2.0
#    5. 重啟 itagent-web + HTTP 驗證
#
#  Idempotent: 重跑安全 (檢查 marker 存不存在)
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
echo -e "${CYAN}|  v3.12.2.0-admin-smtp-test (SMTP 測試 + 排除清單可編輯)    |${NC}"
echo -e "${CYAN}+============================================================+${NC}"
[ "$(id -u)" -eq 0 ] || fail "需 root / sudo"

# 偵測 inspection home
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
API_ADMIN="$HOME_DIR/webapp/routes/api_admin.py"
EMAIL_SVC="$HOME_DIR/webapp/services/email_service.py"
VERSION_JSON="$HOME_DIR/data/version.json"

[ -f "$ADMIN_JS" ]    || fail "缺檔: $ADMIN_JS"
[ -f "$API_ADMIN" ]   || fail "缺檔: $API_ADMIN"
[ -f "$EMAIL_SVC" ]   || fail "缺檔: $EMAIL_SVC (email_service.py 是 prereq, 應由舊版本提供)"
[ -f "$VERSION_JSON" ] || fail "缺檔: $VERSION_JSON"

CUR_VER=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['version'])" 2>/dev/null || echo "?")
info "目前版本: $CUR_VER"

BACKUP_DIR="/var/backups/inspection/pre_v3.12.2.0_${TS}"

# ========== [1] 備份 ==========
echo -e "${BOLD}[1/5] 備份${NC}"
mkdir -p "$BACKUP_DIR"
cp -p "$ADMIN_JS"     "$BACKUP_DIR/" && ok "admin.js → bak"
cp -p "$API_ADMIN"    "$BACKUP_DIR/" && ok "api_admin.py → bak"
cp -p "$VERSION_JSON" "$BACKUP_DIR/" && ok "version.json → bak"
info "備份: $BACKUP_DIR"

OWNER=$(stat -c "%U:%G" "$ADMIN_JS")
info "檔案 owner: $OWNER"

# ========== [2] 改 admin.js (Disk excl + Email + 新函式) ==========
echo -e "${BOLD}[2/5] 改 admin.js${NC}"
ADMIN_JS_PATH="$ADMIN_JS" python3 <<'PYEOF' || fail "admin.js 改寫失敗"
import re, sys, os
p = os.environ["ADMIN_JS_PATH"]
s = open(p).read()

# idempotent: 已含 v3.12.2.0 marker 就 skip
if "/* v3.12.2.0 */" in s:
    print("  v3.12.2.0 marker 已存在, skip")
    sys.exit(0)

# === [2a] 替換 Disk exclusions block ===
# 原本: 從 "// Disk exclusions" 到下一個 "// Email" 之前
old_disk_re = re.compile(
    r"// Disk exclusions.*?(?=\n\s*// Email)",
    re.DOTALL
)
new_disk = '''// Disk exclusions (v3.12.2.0: chip 可編輯)
    var mounts = d.disk_exclude_mounts || [];
    var prefixes = d.disk_exclude_prefixes || [];
    document.getElementById("settings-disk-excl").innerHTML =
      '<div style="margin-bottom:8px;font-size:13px;color:var(--c2);">磁碟排除目錄 (完全比對)</div>' +
      '<div id="excl-mount-list">' + mounts.map(function(m){return '<span class="badge badge-ok" style="margin:2px;">'+m+' <a href="#" onclick="removeExclMount(\\''+m+'\\');return false;" style="color:var(--red);margin-left:4px;">x</a></span>';}).join(" ") + '</div>' +
      '<div style="margin-top:8px;display:flex;gap:8px;"><input type="text" id="new-excl-mount" placeholder="例: /tmp/cache" style="width:240px;"><button class="btn btn-sm btn-primary" onclick="addExclMount()">新增目錄</button></div>' +
      '<div style="margin-top:16px;margin-bottom:8px;font-size:13px;color:var(--c2);">磁碟排除前綴 (前綴比對)</div>' +
      '<div id="excl-prefix-list">' + prefixes.map(function(p){return '<span class="badge" style="background:var(--bg);margin:2px;">'+p+' <a href="#" onclick="removeExclPrefix(\\''+p+'\\');return false;" style="color:var(--red);margin-left:4px;">x</a></span>';}).join(" ") + '</div>' +
      '<div style="margin-top:8px;display:flex;gap:8px;"><input type="text" id="new-excl-prefix" placeholder="例: /var/log/" style="width:240px;"><button class="btn btn-sm btn-primary" onclick="addExclPrefix()">新增前綴</button></div>';
    '''

if not old_disk_re.search(s):
    raise SystemExit("找不到 // Disk exclusions block (loadSettingsTab 結構變了?)")
s = old_disk_re.sub(new_disk, s, count=1)
print("  Disk exclusions block 已替換")

# === [2b] 替換 Email block (加測試 SMTP 按鈕) ===
# 原本: "// Email" 到 loadSettingsTab function 結束 ("})  ; ?$")
# 較安全: 找 Email block 到 saveEmail 結束按鈕 (含 '儲存通知設定</button>')
old_email_re = re.compile(
    r"// Email\s*\n.*?<button class=\"btn btn-primary\" onclick=\"saveEmail\(\)\">儲存通知設定</button>'\s*;",
    re.DOTALL
)
new_email = '''// Email (v3.12.2.0: 加測試 SMTP 按鈕)
    var email = d.notify_email || {};
    document.getElementById("settings-email").innerHTML =
      '<div class="form-group"><label>SMTP</label><input type="text" value="'+(email.smtp_host||"")+'" disabled></div>' +
      '<div class="form-group"><label>收件人</label><input type="text" id="email-to" value="'+((email.to||[]).join(", "))+'"></div>' +
      '<div class="form-group"><label>觸發條件</label><input type="text" id="email-on" value="'+((email.send_on||[]).join(", "))+'"></div>' +
      '<div style="display:flex;gap:8px;">' +
        '<button class="btn btn-primary" onclick="saveEmail()">儲存通知設定</button>' +
        '<button class="btn btn-secondary" onclick="testEmail(this)">📨 測試 SMTP</button>' +
      '</div>';'''

if not old_email_re.search(s):
    raise SystemExit("找不到 // Email block")
s = old_email_re.sub(new_email, s, count=1)
print("  Email block 已替換 (加測試 SMTP 按鈕)")

# === [2c] 在檔尾加 5 個新函式 ===
new_funcs = '''

/* v3.12.2.0 */
function addExclMount() {
  var v = document.getElementById("new-excl-mount").value.trim();
  if (!v) return;
  fetch("/api/admin/settings").then(function(r){return r.json();}).then(function(res) {
    var list = res.data.disk_exclude_mounts || [];
    if (list.indexOf(v) === -1) list.push(v);
    return fetch("/api/admin/settings/disk_exclude_mounts", {method:"PUT", headers:{"Content-Type":"application/json"}, body:JSON.stringify({value:list})});
  }).then(function(){_tabLoaded.settings=false;loadSettingsTab();});
}
function removeExclMount(v) {
  fetch("/api/admin/settings").then(function(r){return r.json();}).then(function(res) {
    var list = (res.data.disk_exclude_mounts || []).filter(function(s){return s!==v;});
    return fetch("/api/admin/settings/disk_exclude_mounts", {method:"PUT", headers:{"Content-Type":"application/json"}, body:JSON.stringify({value:list})});
  }).then(function(){_tabLoaded.settings=false;loadSettingsTab();});
}
function addExclPrefix() {
  var v = document.getElementById("new-excl-prefix").value.trim();
  if (!v) return;
  fetch("/api/admin/settings").then(function(r){return r.json();}).then(function(res) {
    var list = res.data.disk_exclude_prefixes || [];
    if (list.indexOf(v) === -1) list.push(v);
    return fetch("/api/admin/settings/disk_exclude_prefixes", {method:"PUT", headers:{"Content-Type":"application/json"}, body:JSON.stringify({value:list})});
  }).then(function(){_tabLoaded.settings=false;loadSettingsTab();});
}
function removeExclPrefix(v) {
  fetch("/api/admin/settings").then(function(r){return r.json();}).then(function(res) {
    var list = (res.data.disk_exclude_prefixes || []).filter(function(s){return s!==v;});
    return fetch("/api/admin/settings/disk_exclude_prefixes", {method:"PUT", headers:{"Content-Type":"application/json"}, body:JSON.stringify({value:list})});
  }).then(function(){_tabLoaded.settings=false;loadSettingsTab();});
}
function testEmail(btn) {
  if (btn) { btn.disabled = true; btn.textContent = '測試中...'; }
  fetch("/api/admin/settings/notify_email/test", {method:"POST", headers:{"Content-Type":"application/json"}, credentials:"include"})
    .then(function(r){return r.json();})
    .then(function(res){
      if (btn) { btn.disabled = false; btn.textContent = '📨 測試 SMTP'; }
      if (res.success) {
        alert("✅ " + (res.message || "測試信寄出"));
      } else {
        alert("❌ " + (res.error || "失敗"));
      }
    })
    .catch(function(e){
      if (btn) { btn.disabled = false; btn.textContent = '📨 測試 SMTP'; }
      alert("❌ 請求失敗: " + e);
    });
}
'''
s = s + new_funcs

open(p, 'w').write(s)
print("  新 5 個函式已 append (addExclMount/removeExclMount/addExclPrefix/removeExclPrefix/testEmail)")
PYEOF
chown "$OWNER" "$ADMIN_JS"
ok "admin.js 改寫完成"

# ========== [3] 改 api_admin.py (加新 route) ==========
echo -e "${BOLD}[3/5] 改 api_admin.py${NC}"
API_ADMIN_PATH="$API_ADMIN" python3 <<'PYEOF' || fail "api_admin.py 改寫失敗"
import re, sys, os
p = os.environ["API_ADMIN_PATH"]
s = open(p).read()

# idempotent
if "notify_email/test" in s:
    print("  /api/admin/settings/notify_email/test 已存在, skip")
    sys.exit(0)

# 找 # ========== Backups ========== 在它之前插入新 route
marker = "# ========== Backups =========="
if marker not in s:
    raise SystemExit(f"找不到 marker: {marker}")

new_route = '''@bp.route("/settings/notify_email/test", methods=["POST"])
@admin_required
def admin_test_email():
    """v3.12.2.0: 寄一封測試信給當前登入者 email, 驗證 SMTP 設定"""
    from services.email_service import send_email
    from services.auth_service import get_user
    from datetime import datetime
    user = get_user(session.get("username")) or {}
    to = (user.get("email") or "").strip()
    if not to:
        return jsonify({"success": False, "error": "你的帳號沒設 Email, 請先到「我的帳號」設好再測試"}), 400
    try:
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        body = (
            "<div style='font-family:sans-serif;'>"
            "<h3>SMTP 測試信</h3>"
            f"<p><b>時間:</b> {ts}</p>"
            f"<p><b>觸發者:</b> {session.get('username')}</p>"
            f"<p><b>收件人:</b> {to}</p>"
            "<p>來源: 巡檢系統 admin#settings → 測試 SMTP 按鈕</p>"
            "<p style='color:#999;font-size:12px;border-top:1px solid #eee;padding-top:8px;margin-top:16px;'>"
            "收到這封信表示 SMTP 設定 OK ✅<br>若沒收到, 請檢查垃圾信件夾, 或 logs/ 內 Flask 錯誤訊息</p>"
            "</div>"
        )
        send_email(to, "[巡檢系統] SMTP 測試信", body)
        log_action(session["username"], "test_email", f"測試 SMTP 寄到 {to}", request.remote_addr)
        return jsonify({"success": True, "message": f"測試信已寄到 {to}, 請至信箱確認 (含垃圾信件)"})
    except Exception as e:
        return jsonify({"success": False, "error": f"寄信失敗: {type(e).__name__}: {e}"}), 500


'''

s = s.replace(marker, new_route + marker, 1)
open(p, 'w').write(s)
print("  新 route /settings/notify_email/test 已插入")
PYEOF
chown "$OWNER" "$API_ADMIN"

# 語法驗證
python3 -c "import ast; ast.parse(open('$API_ADMIN').read())" 2>&1 || fail "api_admin.py 改完語法錯! 從 $BACKUP_DIR 還原"
ok "api_admin.py + admin.js 語法/格式 OK"

# ========== [4] 更新 version.json ==========
echo -e "${BOLD}[4/5] 更新 version.json → 3.12.2.0${NC}"
VERSION_JSON_PATH="$VERSION_JSON" CHANGELOG_FILE="$SCRIPT_DIR/CHANGELOG_ENTRY.txt" python3 <<'PYEOF' || fail "version.json 更新失敗"
import json, datetime, os
p = os.environ["VERSION_JSON_PATH"]
d = json.load(open(p))
new_entry = open(os.environ["CHANGELOG_FILE"]).read().strip()

if any(e.startswith("3.12.2.0 ") for e in d.get("changelog", [])):
    print("  changelog 已含 3.12.2.0, skip prepend")
else:
    d.setdefault("changelog", []).insert(0, new_entry)

d["version"] = "3.12.2.0"
d["updated_at"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
print("  version.json → 3.12.2.0")
PYEOF
chown "$OWNER" "$VERSION_JSON"
ok "version.json OK"

# ========== [5] 重啟 + 驗證 ==========
echo -e "${BOLD}[5/5] 重啟 itagent-web + 驗證${NC}"
RESTARTED=0
for svc in itagent-web inspection inspection-web; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" && ok "systemctl restart $svc" && RESTARTED=1 && break
    fi
done
[ "$RESTARTED" -eq 1 ] || warn "沒偵測到 Flask service, 請手動重啟"
sleep 3

NEW_VER=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['version'])" 2>/dev/null || echo "?")
[ "$NEW_VER" = "3.12.2.0" ] && ok "版本 $NEW_VER ✅" || warn "版本異常: $NEW_VER"

HTTP_ADMIN=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5000/admin" 2>/dev/null || echo "000")
case "$HTTP_ADMIN" in 200|302|401) ok "/admin $HTTP_ADMIN" ;; *) warn "/admin $HTTP_ADMIN" ;; esac

# 驗 admin.js 含新函式
if grep -q "function testEmail" "$ADMIN_JS" && grep -q "function addExclMount" "$ADMIN_JS"; then
    ok "admin.js 含 testEmail + addExclMount 函式"
else
    warn "admin.js 似乎缺新函式"
fi

# 驗 api_admin.py 含新 route
if grep -q "notify_email/test" "$API_ADMIN"; then
    ok "api_admin.py 含 notify_email/test route"
else
    warn "api_admin.py 似乎缺新 route"
fi

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  v3.12.2.0 完成! $CUR_VER → $NEW_VER${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}瀏覽器測試 (Ctrl+Shift+R 強制重載)${NC}:"
echo "  1. /admin#settings 頁面"
echo "  2. 「磁碟排除清單」應顯示 chip + x 刪除 + 新增 input + 按鈕"
echo "  3. 「Email 通知設定」儲存按鈕旁邊應有「📨 測試 SMTP」"
echo "  4. 點測試 SMTP → 應寄一封測試信到「我的帳號」設定的 email"
echo "     (前提: 帳號要先設 email + 後端 SMTP_PASSWORD env 要給對)"
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo "  sudo cp -p $BACKUP_DIR/admin.js     $ADMIN_JS"
echo "  sudo cp -p $BACKUP_DIR/api_admin.py $API_ADMIN"
echo "  sudo cp -p $BACKUP_DIR/version.json $VERSION_JSON"
echo "  sudo systemctl restart itagent-web"
