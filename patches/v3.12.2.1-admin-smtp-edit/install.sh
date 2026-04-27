#!/bin/bash
###############################################
#  v3.12.2.1-admin-smtp-edit installer
#
#  v3.12.2.0 升級 / 從原始 v3.11.x 直升 都能用 (auto-detect)
#
#  動作:
#    1. admin.js: 磁碟排除清單 chip 化 (若還沒)
#    2. admin.js: Email 設定 → 6 SMTP 欄位全部可編輯
#       (host/port/tls/user/from + 收件人/觸發條件)
#    3. admin.js: 密碼分離管理 (主表單不送密碼; 獨立「更改/清除」按鈕)
#    4. admin.js: 加 7 個函式 (addExclMount/removeExclMount/addExclPrefix/removeExclPrefix/testEmail/updateSmtpPassword/clearSmtpPassword)
#    5. api_admin.py: admin_settings GET 把 smtp_pass mask 成 ***SET*** 不外傳
#    6. api_admin.py: admin_update_setting PUT notify_email 時若沒帶 smtp_pass 或 == ***SET*** 就 preserve 原值
#    7. api_admin.py: 加 POST /api/admin/settings/notify_email/test (v3.12.2.0 已加則 skip)
#    8. api_admin.py: 加 POST /api/admin/settings/notify_email/password
#    9. version.json → 3.12.2.1
#    10. 重啟 itagent-web + 驗證
#
#  Idempotent: 偵測 marker /* v3.12.2.1 */ 就 skip
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
echo -e "${CYAN}|  v3.12.2.1-admin-smtp-edit (6 SMTP 欄位可編輯, 無密碼可)   |${NC}"
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
API_ADMIN="$HOME_DIR/webapp/routes/api_admin.py"
EMAIL_SVC="$HOME_DIR/webapp/services/email_service.py"
VERSION_JSON="$HOME_DIR/data/version.json"

[ -f "$ADMIN_JS" ]    || fail "缺檔: $ADMIN_JS"
[ -f "$API_ADMIN" ]   || fail "缺檔: $API_ADMIN"
[ -f "$EMAIL_SVC" ]   || fail "缺檔: $EMAIL_SVC"
[ -f "$VERSION_JSON" ] || fail "缺檔: $VERSION_JSON"

CUR_VER=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['version'])" 2>/dev/null || echo "?")
info "目前版本: $CUR_VER"

BACKUP_DIR="/var/backups/inspection/pre_v3.12.2.1_${TS}"

# ========== [1] 備份 ==========
echo -e "${BOLD}[1/6] 備份${NC}"
mkdir -p "$BACKUP_DIR"
cp -p "$ADMIN_JS"     "$BACKUP_DIR/" && ok "admin.js → bak"
cp -p "$API_ADMIN"    "$BACKUP_DIR/" && ok "api_admin.py → bak"
cp -p "$VERSION_JSON" "$BACKUP_DIR/" && ok "version.json → bak"
info "備份: $BACKUP_DIR"

OWNER=$(stat -c "%U:%G" "$ADMIN_JS")
info "檔案 owner: $OWNER"

# ========== [2] 改 admin.js ==========
echo -e "${BOLD}[2/6] 改 admin.js (Disk excl + Email 6 欄位 + 7 函式)${NC}"
ADMIN_JS_PATH="$ADMIN_JS" python3 <<'PYEOF' || fail "admin.js 改寫失敗"
import re, sys, os
p = os.environ["ADMIN_JS_PATH"]
s = open(p, encoding="utf-8").read()

if "/* v3.12.2.1 */" in s:
    print("  /* v3.12.2.1 */ marker 已存在, 全 skip")
    sys.exit(0)

# === [2a] Disk exclusions block ===
new_disk = '''// Disk exclusions (v3.12.2.1: chip 可編輯)
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

if "// Disk exclusions (v3.12.2.0:" in s or "// Disk exclusions (v3.12.2.1:" in s:
    print("  Disk excl block 已是 v3.12.2.x, skip")
else:
    old_disk_re = re.compile(r"// Disk exclusions\s*\n.*?(?=\n\s*// Email)", re.DOTALL)
    if not old_disk_re.search(s):
        raise SystemExit("找不到原始 // Disk exclusions block")
    s = old_disk_re.sub(new_disk, s, count=1)
    print("  Disk excl block 已替換 → v3.12.2.1")

# === [2b] Email block ===
new_email = '''// Email (v3.12.2.1: 6 SMTP 欄位可編輯 + 密碼分離管理)
    var email = d.notify_email || {};
    var passDisplay = '未設定 (no auth)';
    if (email.smtp_pass) {
      var pv = String(email.smtp_pass);
      if (pv.indexOf('ENV:') === 0) passDisplay = pv;
      else passDisplay = '已設定 (***)';
    }
    document.getElementById("settings-email").innerHTML =
      '<div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;">' +
      '<div class="form-group"><label>SMTP 主機</label><input type="text" id="email-host" value="'+(email.smtp_host||"")+'" placeholder="smtp.gmail.com / 192.168.1.40"></div>' +
      '<div class="form-group"><label>Port</label><input type="number" id="email-port" value="'+(email.smtp_port||25)+'" placeholder="25 / 587 / 465"></div>' +
      '<div class="form-group"><label>STARTTLS</label><select id="email-tls" style="width:100%;"><option value="true"'+(email.smtp_tls!==false?\' selected\':\'\')+\'>啟用 (587 用)</option><option value="false"'+(email.smtp_tls===false?\' selected\':\'\')+\'>不啟用 (25 relay 用)</option></select></div>' +
      '<div class="form-group"><label>寄件帳號 (空白 = 無 AUTH)</label><input type="text" id="email-user" value="'+(email.smtp_user||"")+'" placeholder="留空 = 不認證"></div>' +
      '<div class="form-group"><label>寄件密碼</label><div style="font-size:12px;color:var(--c2);margin-bottom:6px;">'+passDisplay+'</div><div style="display:flex;gap:4px;"><button class="btn btn-sm btn-secondary" onclick="updateSmtpPassword()">更改</button><button class="btn btn-sm" onclick="clearSmtpPassword()" style="background:#fee;color:#c00;border:1px solid #fcc;">清除 (no auth)</button></div></div>' +
      '<div class="form-group"><label>From (寄件人)</label><input type="text" id="email-from" value="'+(email.from||"")+'" placeholder="alien@example.com"></div>' +
      '<div class="form-group"><label>收件人 (逗號分隔)</label><input type="text" id="email-to" value="'+((email.to||[]).join(", "))+'"></div>' +
      '<div class="form-group"><label>觸發條件 (逗號分隔)</label><input type="text" id="email-on" value="'+((email.send_on||[]).join(", "))+'" placeholder="error, warn"></div>' +
      '</div>' +
      '<div style="display:flex;gap:8px;margin-top:8px;">' +
        '<button class="btn btn-primary" onclick="saveEmail()">儲存通知設定</button>' +
        '<button class="btn btn-secondary" onclick="testEmail(this)">📨 測試 SMTP</button>' +
      '</div>';'''

if "// Email (v3.12.2.1:" in s:
    print("  Email block 已是 v3.12.2.1, skip")
elif "// Email (v3.12.2.0:" in s:
    # 從 v3.12.2.0 升級
    old_email_re = re.compile(
        r"// Email \(v3\.12\.2\.0:.*?(?:</div>')\s*;\s*",
        re.DOTALL
    )
    if not old_email_re.search(s):
        raise SystemExit("找不到 v3.12.2.0 Email block (結構變了?)")
    s = old_email_re.sub(new_email, s, count=1)
    print("  Email block 從 v3.12.2.0 升級 → v3.12.2.1")
else:
    # 原始版替換
    old_email_re = re.compile(
        r"// Email\s*\n.*?<button class=\"btn btn-primary\" onclick=\"saveEmail\(\)\">儲存通知設定</button>'\s*;",
        re.DOTALL
    )
    if not old_email_re.search(s):
        raise SystemExit("找不到原始 // Email block")
    s = old_email_re.sub(new_email, s, count=1)
    print("  Email block 從原始版替換 → v3.12.2.1")

# === [2c] 取代 saveEmail 函式 ===
new_save = '''function saveEmail() { /* v3.12.2.1 saveEmail */
  fetch("/api/admin/settings").then(function(r){return r.json();}).then(function(res) {
    var email = res.data.notify_email || {};
    var hostEl = document.getElementById("email-host");
    if (hostEl) email.smtp_host = hostEl.value.trim();
    var portEl = document.getElementById("email-port");
    if (portEl) email.smtp_port = parseInt(portEl.value) || 25;
    var tlsEl = document.getElementById("email-tls");
    if (tlsEl) email.smtp_tls = tlsEl.value === "true";
    var userEl = document.getElementById("email-user");
    if (userEl) email.smtp_user = userEl.value.trim();
    var fromEl = document.getElementById("email-from");
    if (fromEl) email.from = fromEl.value.trim();
    email.to = document.getElementById("email-to").value.split(",").map(function(s){return s.trim();}).filter(function(s){return s;});
    email.send_on = document.getElementById("email-on").value.split(",").map(function(s){return s.trim();}).filter(function(s){return s;});
    email.enabled = true;
    /* 不送 smtp_pass: 後端會 preserve (見 admin_update_setting) */
    return fetch("/api/admin/settings/notify_email", {method:"PUT", headers:{"Content-Type":"application/json"}, body:JSON.stringify({value:email})});
  }).then(function(r){return r.json();}).then(function(res){alert(res.message||"已儲存");_tabLoaded.settings=false;loadSettingsTab();});
}'''

if "/* v3.12.2.1 saveEmail */" in s:
    print("  saveEmail 已是 v3.12.2.1, skip")
else:
    old_save_re = re.compile(r"function saveEmail\(\) \{.*?^\}", re.DOTALL | re.MULTILINE)
    if not old_save_re.search(s):
        raise SystemExit("找不到 function saveEmail() {{ ... }} 區塊")
    s = old_save_re.sub(new_save, s, count=1)
    print("  saveEmail 已替換 → v3.12.2.1")

# === [2d] 加 7 個新函式 ===
funcs_block = '''

/* v3.12.2.1 */
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
function updateSmtpPassword() {
  var p = prompt("輸入新 SMTP 密碼\\n(純密碼; 或寫 ENV:VAR_NAME 走後端環境變數):");
  if (p === null) return;
  fetch("/api/admin/settings/notify_email/password", {method:"POST", headers:{"Content-Type":"application/json"}, credentials:"include", body:JSON.stringify({password:p})})
    .then(function(r){return r.json();})
    .then(function(res){
      alert(res.success ? "✅ " + (res.message||"密碼已更新") : "❌ " + (res.error||"失敗"));
      _tabLoaded.settings=false; loadSettingsTab();
    });
}
function clearSmtpPassword() {
  if (!confirm("確定要清除 SMTP 密碼?\\n清除後 SMTP 走 no-auth (適用 relay / 內網 SMTP)")) return;
  fetch("/api/admin/settings/notify_email/password", {method:"POST", headers:{"Content-Type":"application/json"}, credentials:"include", body:JSON.stringify({password:""})})
    .then(function(r){return r.json();})
    .then(function(res){
      alert(res.success ? "✅ " + (res.message||"密碼已清除 (no-auth)") : "❌ " + (res.error||"失敗"));
      _tabLoaded.settings=false; loadSettingsTab();
    });
}
'''

# 只 append 缺的函式
to_append = []
for fn in ["addExclMount", "removeExclMount", "addExclPrefix", "removeExclPrefix", "testEmail", "updateSmtpPassword", "clearSmtpPassword"]:
    if "function "+fn not in s:
        to_append.append(fn)

if not to_append:
    print("  全部函式已存在, 不 append")
else:
    s = s + funcs_block
    print(f"  函式 block 已 append (覆蓋既有: 後者 wins): {to_append}")

open(p, 'w', encoding="utf-8").write(s)
PYEOF
chown "$OWNER" "$ADMIN_JS"
ok "admin.js 改寫完成"

# ========== [3] 改 api_admin.py ==========
echo -e "${BOLD}[3/6] 改 api_admin.py${NC}"
API_ADMIN_PATH="$API_ADMIN" python3 <<'PYEOF' || fail "api_admin.py 改寫失敗"
import re, sys, os
p = os.environ["API_ADMIN_PATH"]
s = open(p, encoding="utf-8").read()

# === [3a] admin_settings: mask smtp_pass ===
mask_marker = "# v3.12.2.1: mask smtp_pass"
if mask_marker in s:
    print("  admin_settings mask 已加, skip")
else:
    old_settings_re = re.compile(
        r'(@bp\.route\("/settings", methods=\["GET"\]\)\s*\n@admin_required\s*\ndef admin_settings\(\):\s*\n)\s*return jsonify\(\{"success": True, "data": get_all_settings\(\)\}\)\s*\n',
        re.MULTILINE
    )
    new_settings = (
        r'\1    data = get_all_settings()\n'
        r'    # v3.12.2.1: mask smtp_pass 不外傳 (避免 plaintext 從 GET /settings 漏出)\n'
        r'    try:\n'
        r'        ne = data.get("notify_email")\n'
        r'        if isinstance(ne, dict):\n'
        r'            pwd = ne.get("smtp_pass") or ""\n'
        r'            if pwd.startswith("ENV:"):\n'
        r'                pass  # ENV: 變數名可見\n'
        r'            elif pwd:\n'
        r'                ne["smtp_pass"] = "***SET***"\n'
        r'            else:\n'
        r'                ne["smtp_pass"] = ""\n'
        r'    except Exception:\n'
        r'        pass\n'
        r'    return jsonify({"success": True, "data": data})\n'
    )
    if not old_settings_re.search(s):
        raise SystemExit("找不到 admin_settings GET handler")
    s = old_settings_re.sub(new_settings, s, count=1)
    print("  admin_settings 加 mask smtp_pass 邏輯")

# === [3b] admin_update_setting: preserve smtp_pass ===
preserve_marker = "# v3.12.2.1: preserve smtp_pass"
if preserve_marker in s:
    print("  admin_update_setting preserve 已加, skip")
else:
    # 找 def admin_update_setting(key): 的開頭, 在 update_setting(key, value) 前插入 preserve 邏輯
    old_update_re = re.compile(
        r'(def admin_update_setting\(key\):\s*\n\s*data = request\.get_json\(force=True\)\s*\n\s*value = data\.get\("value"\)\s*\n)(\s*# Dual write|\s*update_setting)',
        re.MULTILINE
    )
    new_update = (
        r'\1'
        r'    # v3.12.2.1: preserve smtp_pass — notify_email 收到 missing/***SET*** 就用原值\n'
        r'    if key == "notify_email" and isinstance(value, dict):\n'
        r'        if "smtp_pass" not in value or value.get("smtp_pass") == "***SET***":\n'
        r'            try:\n'
        r'                _cur = (get_all_settings().get("notify_email") or {})\n'
        r'                value["smtp_pass"] = _cur.get("smtp_pass", "")\n'
        r'            except Exception:\n'
        r'                pass\n'
        r'\2'
    )
    if not old_update_re.search(s):
        raise SystemExit("找不到 admin_update_setting 函式 body 開頭")
    s = old_update_re.sub(new_update, s, count=1)
    # 確保 import get_all_settings 已在
    if "from services.mongo_service import" in s and "get_all_settings" not in s.split("from services.mongo_service import")[1].split("\n")[0]:
        # 沒 import — 嘗試補上 (rare)
        s = s.replace(
            "from services.mongo_service import",
            "from services.mongo_service import get_all_settings,",
            1
        )
    print("  admin_update_setting 加 preserve smtp_pass 邏輯")

# === [3c] 新 route /settings/notify_email/test (v3.12.2.0 已有則 skip) ===
if "notify_email/test" in s:
    print("  /settings/notify_email/test 已存在, skip")
else:
    test_route = '''@bp.route("/settings/notify_email/test", methods=["POST"])
@admin_required
def admin_test_email():
    """v3.12.2.x: 寄一封測試信給當前登入者 email"""
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
            "收到這封信表示 SMTP 設定 OK ✅<br>若沒收到, 檢查垃圾信件夾 / Flask logs / SMTP relay log</p>"
            "</div>"
        )
        send_email(to, "[巡檢系統] SMTP 測試信", body)
        log_action(session["username"], "test_email", f"測試 SMTP 寄到 {to}", request.remote_addr)
        return jsonify({"success": True, "message": f"測試信已寄到 {to}, 請至信箱確認 (含垃圾信件)"})
    except Exception as e:
        return jsonify({"success": False, "error": f"寄信失敗: {type(e).__name__}: {e}"}), 500


'''
    marker = "# ========== Backups =========="
    if marker not in s:
        raise SystemExit(f"找不到 marker: {marker}")
    s = s.replace(marker, test_route + marker, 1)
    print("  /settings/notify_email/test 新增")

# === [3d] 新 route /settings/notify_email/password ===
if "notify_email/password" in s:
    print("  /settings/notify_email/password 已存在, skip")
else:
    password_route = '''@bp.route("/settings/notify_email/password", methods=["POST"])
@admin_required
def admin_set_smtp_password():
    """v3.12.2.1: 專用端點修改/清空 SMTP 密碼 (避免主表單 PUT 把 mask 占位符存回)"""
    data = request.get_json(force=True)
    pwd = data.get("password", "")
    try:
        cur = (get_all_settings().get("notify_email") or {})
        cur["smtp_pass"] = pwd
        update_setting("notify_email", cur)
        try:
            with open(SETTINGS_FILE) as f:
                sj = json.load(f)
            sj["notify_email"] = cur
            with open(SETTINGS_FILE, "w") as f:
                json.dump(sj, f, indent=2, ensure_ascii=False)
        except Exception:
            pass
        log_action(session["username"], "set_smtp_password",
                   "清除 SMTP 密碼 (no-auth)" if not pwd else "修改 SMTP 密碼",
                   request.remote_addr)
        msg = "密碼已清除 (no-auth)" if not pwd else "密碼已更新"
        return jsonify({"success": True, "message": msg})
    except Exception as e:
        return jsonify({"success": False, "error": f"{type(e).__name__}: {e}"}), 500


'''
    marker = "# ========== Backups =========="
    s = s.replace(marker, password_route + marker, 1)
    print("  /settings/notify_email/password 新增")

open(p, 'w', encoding="utf-8").write(s)
PYEOF
chown "$OWNER" "$API_ADMIN"
python3 -c "import ast; ast.parse(open('$API_ADMIN').read())" 2>&1 || fail "api_admin.py 語法錯! 從 $BACKUP_DIR 還原"
ok "api_admin.py 改寫完成 + 語法 OK"

# ========== [4] version.json ==========
echo -e "${BOLD}[4/6] 更新 version.json → 3.12.2.1${NC}"
VERSION_JSON_PATH="$VERSION_JSON" CHANGELOG_FILE="$SCRIPT_DIR/CHANGELOG_ENTRY.txt" python3 <<'PYEOF' || fail "version.json 更新失敗"
import json, datetime, os
p = os.environ["VERSION_JSON_PATH"]
d = json.load(open(p))
new_entry = open(os.environ["CHANGELOG_FILE"]).read().strip()

if any(e.startswith("3.12.2.1 ") for e in d.get("changelog", [])):
    print("  changelog 已含 3.12.2.1, skip prepend")
else:
    d.setdefault("changelog", []).insert(0, new_entry)

d["version"] = "3.12.2.1"
d["updated_at"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
print("  version.json → 3.12.2.1")
PYEOF
chown "$OWNER" "$VERSION_JSON"
ok "version.json OK"

# ========== [5] 重啟 ==========
echo -e "${BOLD}[5/6] 重啟 Flask${NC}"
RESTARTED=0
for svc in itagent-web inspection inspection-web; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" && ok "systemctl restart $svc" && RESTARTED=1 && break
    fi
done
[ "$RESTARTED" -eq 1 ] || warn "沒偵測到 Flask service, 請手動重啟"
sleep 3

# ========== [6] 驗證 ==========
echo -e "${BOLD}[6/6] 驗證${NC}"
NEW_VER=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['version'])" 2>/dev/null || echo "?")
[ "$NEW_VER" = "3.12.2.1" ] && ok "版本 $NEW_VER ✅" || warn "版本異常: $NEW_VER"

if grep -q "function updateSmtpPassword" "$ADMIN_JS"; then ok "admin.js 含 updateSmtpPassword"; else warn "admin.js 缺 updateSmtpPassword"; fi
if grep -q "/settings/notify_email/password" "$API_ADMIN"; then ok "api_admin.py 含 /password route"; else warn "api_admin.py 缺 /password route"; fi
if grep -q "v3.12.2.1: mask smtp_pass" "$API_ADMIN"; then ok "api_admin.py 含 mask 邏輯"; else warn "缺 mask"; fi

HTTP_ADMIN=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5000/admin" 2>/dev/null || echo "000")
case "$HTTP_ADMIN" in 200|302|401) ok "/admin $HTTP_ADMIN" ;; *) warn "/admin $HTTP_ADMIN" ;; esac

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  v3.12.2.1 完成! $CUR_VER → $NEW_VER${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}你的 SMTP 設定 (no-auth relay 範例)${NC}:"
echo "  SMTP 主機:   <你的 SMTP relay IP>"
echo "  Port:        25"
echo "  STARTTLS:    不啟用"
echo "  寄件帳號:    (留空)"
echo "  密碼:        點「清除 (no auth)」"
echo "  From:        alien.lee@cathaysec.com.tw  (依需要填)"
echo ""
echo -e "${BOLD}測試流程${NC}:"
echo "  1. /admin#settings 強制 reload (Ctrl+Shift+R)"
echo "  2. 填上面 6 欄位 → 點「儲存通知設定」"
echo "  3. 點「📨 測試 SMTP」 → 應寄到「我的帳號」設定的 email"
echo "  4. 收信箱檢查 (可能在垃圾信件)"
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo "  sudo cp -p $BACKUP_DIR/* $HOME_DIR/webapp/static/js/   # admin.js"
echo "  sudo cp -p $BACKUP_DIR/api_admin.py $HOME_DIR/webapp/routes/"
echo "  sudo cp -p $BACKUP_DIR/version.json $HOME_DIR/data/"
echo "  sudo systemctl restart itagent-web"
