#!/bin/bash
###############################################
#  v3.13.0.1-mongodb-autodetect installer (SUPERSEDES v3.13.0.0)
#
#  bug: v3.13.0.0 PREREQ 寫死要 podman 容器 mongodb, 13 上 mongo 是 RPM native 裝, fail.
#
#  修法:
#    - install.sh PREREQ: 偵測 local mongodump OR podman 容器 mongodb, 兩者擇一
#    - api_admin.py create_db_backup: runtime 自動偵測, 優先用 local mongodump,
#      沒 local 才走 podman exec mongodb mongodump
#
#  此 patch 包含 v3.13.0.0 全部功能 (匯出/列表/下載/刪除), 不需先裝 v3.13.0.0.
#  Idempotent: 偵測 _v3.13.0.1_get_mongodump_cmd marker → skip
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
echo -e "${CYAN}|  v3.13.0.1 DB Dump (auto-detect local mongodump / podman) |${NC}"
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
ADMIN_HTML="$HOME_DIR/webapp/templates/admin.html"
ADMIN_JS="$HOME_DIR/webapp/static/js/admin.js"
VERSION_JSON="$HOME_DIR/data/version.json"

for f in "$API_ADMIN" "$ADMIN_HTML" "$ADMIN_JS" "$VERSION_JSON"; do
    [ -f "$f" ] || fail "缺檔: $f"
done

# 偵測 mongodump (local 優先 / podman 後備)
MONGO_MODE="?"
if command -v mongodump >/dev/null 2>&1; then
    MONGO_MODE="local"
    ok "本機 mongodump 可用 (RPM 安裝)"
elif command -v podman >/dev/null 2>&1 && podman ps --format '{{.Names}}' 2>/dev/null | grep -q "^mongodb$"; then
    MONGO_MODE="podman"
    ok "podman 容器 mongodb 可用"
else
    fail "找不到 mongodump:
   - 本機: dnf install mongodb-database-tools (Rocky 9)
   - podman: 確認 mongodb 容器在跑"
fi
info "MongoDB mode: $MONGO_MODE"

CUR_VER=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['version'])" 2>/dev/null || echo "?")
info "目前版本: $CUR_VER"

BACKUP_DIR="/var/backups/inspection/pre_v3.13.0.1_${TS}"
mkdir -p "$BACKUP_DIR"

# ========== [1] 備份 ==========
echo -e "${BOLD}[1/5] 備份${NC}"
cp -p "$API_ADMIN"    "$BACKUP_DIR/" && ok "api_admin.py → bak"
cp -p "$ADMIN_HTML"   "$BACKUP_DIR/" && ok "admin.html → bak"
cp -p "$ADMIN_JS"     "$BACKUP_DIR/" && ok "admin.js → bak"
cp -p "$VERSION_JSON" "$BACKUP_DIR/" && ok "version.json → bak"

OWNER=$(stat -c "%U:%G" "$ADMIN_JS")

# ========== [2] api_admin.py: 加 helper + 4 routes (含 auto-detect) ==========
echo -e "${BOLD}[2/5] api_admin.py: helper + 4 routes (auto-detect)${NC}"
API_ADMIN_PATH="$API_ADMIN" python3 <<'PYEOF' || fail "api_admin.py 改寫失敗"
import re, os, sys
p = os.environ["API_ADMIN_PATH"]
s = open(p, encoding="utf-8").read()

if "_v3_13_0_1_get_mongodump_cmd" in s:
    print("  v3.13.0.1 marker 已存在, skip")
    sys.exit(0)

# === 補 import send_file ===
if "send_file" not in s:
    old_imp = "from flask import Blueprint, request, jsonify, session"
    if old_imp not in s:
        raise SystemExit("找不到 flask import 行")
    s = s.replace(old_imp, "from flask import Blueprint, request, jsonify, session, send_file", 1)
    print("  補 import send_file")

# === 移除舊 v3.13.0.0 routes (若存在) ===
# 從 # v3.13.0.0 DB Dump routes 到 # ========== Backups ========== 之間整段刪除
import re as _re
old_block_re = _re.compile(
    r'# v3\.13\.0\.0 DB Dump routes\s*\n.*?(?=# ========== Backups ==========)',
    _re.DOTALL
)
if old_block_re.search(s):
    s = old_block_re.sub("", s, count=1)
    print("  移除舊 v3.13.0.0 routes 區塊")

# === 加 helper + 4 routes (auto-detect 版) ===
new_block = '''# v3.13.0.1 DB Dump routes (auto-detect local / podman)
DB_BACKUP_DIR = "/var/backups/inspection/db"


def _v3_13_0_1_get_mongodump_cmd():
    """偵測 mongodump 環境: local RPM 優先, podman 容器後備. 回傳 subprocess 用的 cmd list 或 None"""
    import shutil as _shutil
    if _shutil.which("mongodump"):
        return ["mongodump", "--db", "inspection", "--archive", "--gzip"]
    try:
        r = subprocess.run(["podman", "ps", "--format", "{{.Names}}"],
                          capture_output=True, text=True, timeout=5)
        if "mongodb" in r.stdout.split():
            return ["podman", "exec", "-T", "mongodb",
                    "mongodump", "--db", "inspection", "--archive", "--gzip"]
    except Exception:
        pass
    return None


def _v3_13_0_1_get_mongorestore_cmd():
    """同 _get_mongodump_cmd 但給 mongorestore 用 (v3.13.1.0 會用到)"""
    import shutil as _shutil
    if _shutil.which("mongorestore"):
        return ["mongorestore", "--archive", "--gzip", "--drop", "--db", "inspection"]
    try:
        r = subprocess.run(["podman", "ps", "--format", "{{.Names}}"],
                          capture_output=True, text=True, timeout=5)
        if "mongodb" in r.stdout.split():
            return ["podman", "exec", "-T", "-i", "mongodb",
                    "mongorestore", "--archive", "--gzip", "--drop", "--db", "inspection"]
    except Exception:
        pass
    return None


@bp.route("/db-backups", methods=["GET"])
@admin_required
def list_db_backups():
    """v3.13.0.1: 列 mongo dump 檔案"""
    os.makedirs(DB_BACKUP_DIR, exist_ok=True)
    backups = []
    try:
        for fn in sorted(os.listdir(DB_BACKUP_DIR), reverse=True):
            fp = os.path.join(DB_BACKUP_DIR, fn)
            if os.path.isfile(fp) and fn.startswith("mongo_") and fn.endswith(".archive.gz"):
                st = os.stat(fp)
                backups.append({
                    "name": fn,
                    "size_mb": round(st.st_size / 1024 / 1024, 2),
                    "created": datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M:%S"),
                })
    except Exception:
        pass
    return jsonify({"success": True, "data": backups})


@bp.route("/db-backups", methods=["POST"])
@admin_required
def create_db_backup():
    """v3.13.0.1: mongodump --archive --gzip → DB_BACKUP_DIR (auto-detect local / podman)"""
    cmd = _v3_13_0_1_get_mongodump_cmd()
    if not cmd:
        return jsonify({"success": False,
                        "error": "找不到 mongodump (本機 dnf install mongodb-database-tools 或 podman 容器 mongodb)"}), 500
    os.makedirs(DB_BACKUP_DIR, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_file = os.path.join(DB_BACKUP_DIR, f"mongo_{ts}.archive.gz")
    try:
        with open(out_file, "wb") as f:
            result = subprocess.run(cmd, stdout=f, stderr=subprocess.PIPE, timeout=600)
        if result.returncode != 0:
            try: os.remove(out_file)
            except Exception: pass
            return jsonify({"success": False,
                            "error": f"mongodump 失敗 (exit {result.returncode}): {result.stderr.decode('utf-8','ignore')[:500]}"}), 500
        size_mb = round(os.stat(out_file).st_size / 1024 / 1024, 2)
        log_action(session["username"], "db_backup",
                   f"建立 {os.path.basename(out_file)} ({size_mb} MB) via {cmd[0]}",
                   request.remote_addr)
        return jsonify({"success": True,
                        "message": f"備份完成 {os.path.basename(out_file)} ({size_mb} MB)",
                        "file": os.path.basename(out_file)})
    except subprocess.TimeoutExpired:
        try: os.remove(out_file)
        except Exception: pass
        return jsonify({"success": False, "error": "mongodump timeout (>10 min)"}), 500
    except Exception as e:
        try: os.remove(out_file)
        except Exception: pass
        return jsonify({"success": False, "error": f"{type(e).__name__}: {e}"}), 500


@bp.route("/db-backups/<filename>/download", methods=["GET"])
@admin_required
def download_db_backup(filename):
    """v3.13.0.1: 下載 mongo dump 檔"""
    if "/" in filename or ".." in filename or not filename.endswith(".archive.gz"):
        return jsonify({"success": False, "error": "filename 含非法字元或副檔名"}), 400
    p = os.path.join(DB_BACKUP_DIR, filename)
    if not os.path.exists(p):
        return jsonify({"success": False, "error": "找不到檔案"}), 404
    log_action(session["username"], "db_backup_download", filename, request.remote_addr)
    return send_file(p, as_attachment=True, download_name=filename, mimetype="application/gzip")


@bp.route("/db-backups/<filename>", methods=["DELETE"])
@admin_required
def delete_db_backup(filename):
    """v3.13.0.1: 刪 mongo dump 檔"""
    if "/" in filename or ".." in filename or not filename.endswith(".archive.gz"):
        return jsonify({"success": False, "error": "filename 含非法字元或副檔名"}), 400
    p = os.path.join(DB_BACKUP_DIR, filename)
    if not os.path.exists(p):
        return jsonify({"success": False, "error": "找不到檔案"}), 404
    os.remove(p)
    log_action(session["username"], "db_backup_delete", filename, request.remote_addr)
    return jsonify({"success": True, "message": f"已刪除 {filename}"})


'''

marker = "# ========== Backups =========="
if marker not in s:
    raise SystemExit(f"找不到 marker: {marker}")
s = s.replace(marker, new_block + marker, 1)
open(p, 'w', encoding="utf-8").write(s)
print("  helper + 4 routes 已新增 (auto-detect 版)")
PYEOF
chown "$OWNER" "$API_ADMIN"
python3 -c "import ast; ast.parse(open('$API_ADMIN').read())" || fail "api_admin.py 語法錯! 從 $BACKUP_DIR 還原"
ok "api_admin.py 改寫 + 語法 OK"

# ========== [3] admin.html (re-enable createDbDump button) ==========
echo -e "${BOLD}[3/5] admin.html: re-enable createDbDump button + dbbackup-list${NC}"
ADMIN_HTML_PATH="$ADMIN_HTML" python3 <<'PYEOF' || fail "admin.html 改寫失敗"
import re, os
p = os.environ["ADMIN_HTML_PATH"]
s = open(p, encoding="utf-8").read()

new_btn = '<button class="btn btn-primary" onclick="createDbDump()" data-v3.13.0.x="enabled">立即 Dump</button>'
btn_re = re.compile(r'<button[^>]*?>立即 Dump</button>')
m = btn_re.search(s)
if not m:
    raise SystemExit("找不到 立即 Dump button")
matched = m.group()
if 'data-v3.13.0' in matched:
    print("  立即 Dump 已 re-enabled, skip")
else:
    s = btn_re.sub(new_btn, s, count=1)
    print("  立即 Dump button re-enabled")

new_div = '<div id="dbbackup-list">載入中...</div>'
db_list_re = re.compile(r'<div id="dbbackup-list"[^>]*?>.*?</div>', re.DOTALL)
m2 = db_list_re.search(s)
if m2 and m2.group() != new_div:
    s = db_list_re.sub(new_div, s, count=1)
    print("  dbbackup-list 改回 「載入中...」")

open(p, 'w', encoding="utf-8").write(s)
PYEOF
chown "$OWNER" "$ADMIN_HTML"
ok "admin.html 改寫完成"

# ========== [4] admin.js (3 funcs + loadBackupsTab 注入) ==========
echo -e "${BOLD}[4/5] admin.js: 3 函式 + loadBackupsTab 注入${NC}"
ADMIN_JS_PATH="$ADMIN_JS" python3 <<'PYEOF' || fail "admin.js 改寫失敗"
import os, sys
p = os.environ["ADMIN_JS_PATH"]
s = open(p, encoding="utf-8").read()

if "function loadDbBackups" in s:
    print("  loadDbBackups 已存在, skip")
    sys.exit(0)

old_load = "function loadBackupsTab() {\n"
new_load = 'function loadBackupsTab() {\n  loadDbBackups(); /* v3.13.0.1 */\n'
if old_load not in s:
    raise SystemExit("找不到 loadBackupsTab")
s = s.replace(old_load, new_load, 1)

new_funcs = '''

/* v3.13.0.1 DB Dump (auto-detect local / podman) */
function createDbDump() {
  if (!confirm("確定要建立 MongoDB Dump?\\n後端會自動選 local mongodump 或 podman exec mongodb mongodump\\n約 1 分鐘 (依資料量)")) return;
  var btn = (typeof event !== "undefined") ? event.target : null;
  if (btn) { btn.disabled = true; btn.textContent = "Dumping..."; }
  fetch("/api/admin/db-backups", {method:"POST", credentials:"include"})
    .then(function(r){return r.json();})
    .then(function(res){
      if (btn) { btn.disabled = false; btn.textContent = "立即 Dump"; }
      alert(res.success ? "✅ " + res.message : "❌ " + (res.error||"失敗"));
      if (res.success) loadDbBackups();
    })
    .catch(function(e){
      if (btn) { btn.disabled = false; btn.textContent = "立即 Dump"; }
      alert("❌ 請求失敗: " + e);
    });
}

function loadDbBackups() {
  fetch("/api/admin/db-backups", {credentials:"include"}).then(function(r){return r.json();}).then(function(res){
    var c = document.getElementById("dbbackup-list");
    if (!c) return;
    if (!res.success) { c.innerHTML = '<div class="no-data">載入失敗: ' + (res.error||"") + '</div>'; return; }
    if (!res.data || !res.data.length) { c.innerHTML = '<div class="no-data" style="color:var(--c3);padding:12px;">無 dump 檔案</div>'; return; }
    var html = '<table style="width:100%;"><thead><tr><th>檔案</th><th>大小</th><th>建立時間</th><th>操作</th></tr></thead><tbody>';
    res.data.forEach(function(b){
      html += '<tr><td style="font-family:JetBrains Mono,monospace;font-size:12px;">' + b.name + '</td>';
      html += '<td>' + b.size_mb + ' MB</td>';
      html += '<td>' + b.created + '</td>';
      html += '<td>';
      html += '<a href="/api/admin/db-backups/' + b.name + '/download" class="btn btn-sm btn-primary" download>下載</a> ';
      html += '<button class="btn btn-sm btn-danger" onclick="deleteDbBackup(\\''+b.name+'\\')">刪除</button>';
      html += '</td></tr>';
    });
    html += '</tbody></table>';
    c.innerHTML = html;
  });
}

function deleteDbBackup(name) {
  if (!confirm("確定要刪 " + name + " ?\\n刪除後無法還原")) return;
  fetch("/api/admin/db-backups/" + encodeURIComponent(name), {method:"DELETE", credentials:"include"})
    .then(function(r){return r.json();})
    .then(function(res){
      alert(res.success ? "✅ " + res.message : "❌ " + (res.error||"失敗"));
      loadDbBackups();
    });
}
'''
s = s + new_funcs
open(p, 'w', encoding="utf-8").write(s)
print("  3 函式已 append + loadBackupsTab 注入")
PYEOF
chown "$OWNER" "$ADMIN_JS"
ok "admin.js 改寫完成"

# ========== [5] DB_BACKUP_DIR + version.json + restart ==========
echo -e "${BOLD}[5/5] DB_BACKUP_DIR + version.json + restart${NC}"
mkdir -p /var/backups/inspection/db
chown "$OWNER" /var/backups/inspection/db
chmod 750 /var/backups/inspection/db
ok "DB_BACKUP_DIR 就緒"

VERSION_JSON_PATH="$VERSION_JSON" CHANGELOG_FILE="$SCRIPT_DIR/CHANGELOG_ENTRY.txt" python3 <<'PYEOF' || fail "version.json 更新失敗"
import json, datetime, os
p = os.environ["VERSION_JSON_PATH"]
d = json.load(open(p))
new_entry = open(os.environ["CHANGELOG_FILE"]).read().strip()
if any(e.startswith("3.13.0.1 ") for e in d.get("changelog", [])):
    print("  changelog 已含 3.13.0.1, skip prepend")
else:
    d.setdefault("changelog", []).insert(0, new_entry)
d["version"] = "3.13.0.1"
d["updated_at"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
print("  version.json → 3.13.0.1")
PYEOF
chown "$OWNER" "$VERSION_JSON"

RESTARTED=0
for svc in itagent-web inspection inspection-web; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" && ok "systemctl restart $svc" && RESTARTED=1 && break
    fi
done
[ "$RESTARTED" -eq 1 ] || warn "沒偵測到 Flask service, 請手動重啟"
sleep 3

NEW_VER=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['version'])" 2>/dev/null || echo "?")
[ "$NEW_VER" = "3.13.0.1" ] && ok "版本 $NEW_VER ✅" || warn "版本異常"

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  v3.13.0.1 完成! $CUR_VER → $NEW_VER  (mode: $MONGO_MODE)${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}測試${NC}: /admin#backups → 立即 Dump → 應產生 mongo_TS.archive.gz"
echo -e "${BOLD}手動 Restore${NC}:"
if [ "$MONGO_MODE" = "local" ]; then
    echo "  mongorestore --archive --gzip --drop --db inspection < /var/backups/inspection/db/mongo_TS.archive.gz"
else
    echo "  podman exec -T -i mongodb mongorestore --archive --gzip --drop --db inspection < /var/backups/inspection/db/mongo_TS.archive.gz"
fi
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo "  sudo cp -p $BACKUP_DIR/* 各對應目錄 (api_admin.py / admin.html / admin.js / version.json)"
echo "  sudo systemctl restart itagent-web"
