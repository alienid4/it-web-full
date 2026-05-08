#!/bin/bash
# v3.17.19.17 Full Bundle - 一次升級到 v3.17.19.17
# Baseline: 任何 v3.17.18.0+ 都可以裝, 一個 install.sh 蓋掉 17 個 patch
#
# 包含的累積改進:
#   v3.17.18.0  AIX 巡檢支援 + 網段掃描 OS 偵測 + check_disk schema 修
#   v3.17.18.1  網段掃描 SSH uname probe (sysinfra key)
#   v3.17.18.2  AIX port 657/199 heuristic
#   v3.17.19.0  批次上線主機重設計 (一頁三步候選池)
#   v3.17.19.1  主機刪除增強 (重建 inventory + 可選清歷史)
#   v3.17.19.2  online-users + health-check + 防靜默失敗
#   v3.17.19.3  系統健康檢查按鈕
#   v3.17.19.4  Dashboard cache TTL
#   v3.17.19.5  system_info 用 Python import (488ms->10ms)
#   v3.17.19.6  health-check JSON parse fix
#   v3.17.19.7  smart healthcheck (不硬性要求 success:true)
#   v3.17.19.8  ping-all 預熱 (2022ms->2.6ms)
#   v3.17.19.9  CSP + favicon
#   v3.17.19.10 batch onboard 詳細錯誤
#   v3.17.19.11 probe_os 權限 + JS null + CSP jsdelivr
#   v3.17.19.12 版本 inline render
#   v3.17.19.13 static cache (4167ms->294ms)
#   v3.17.19.14 inventory windows.windows recursion fix
#   v3.17.19.15 seed_data 不誤匯 twgcb_/network_*.json
#   v3.17.19.16 系統診斷 tab + sanitized download
#   v3.17.19.17 UX 老花友善 (字加大加深 + active group 自動展開)

set -e
PATCH_VER="3.17.19.17a"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)

# ---------- 1. Find INSPECTION_HOME ----------
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
if [ -z "$INSPECTION_HOME" ]; then
    echo "[FAIL] Cannot find inspection directory"; exit 1
fi
echo "[INFO] INSPECTION_HOME=$INSPECTION_HOME"

# ---------- 2. Check baseline ----------
CUR_VER=$(python3 -c "import json; print(json.load(open('$INSPECTION_HOME/data/version.json'))['version'])" 2>/dev/null || echo "unknown")
echo "[INFO] Current version: $CUR_VER"
if ! echo "$CUR_VER" | grep -qE '^3\.17\.(15|16|17|18|19)\.'; then
    echo "[WARN] Expected baseline 3.17.15+ ~ 3.17.19, found $CUR_VER"
    echo "       此 bundle 整合 17 patches, 一次升到 3.17.19.17a. 強制繼續? (y/N)"
    read -r ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 1
fi

# ---------- 3. Backup all overwritten files ----------
backup() { [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}" && echo "[BACKUP] $1"; }
echo "[INFO] Backing up..."
backup "$INSPECTION_HOME/webapp/app.py"
backup "$INSPECTION_HOME/webapp/templates/admin.html"
backup "$INSPECTION_HOME/webapp/templates/base.html"
backup "$INSPECTION_HOME/webapp/static/js/admin.js"
backup "$INSPECTION_HOME/webapp/static/css/admin.css"
backup "$INSPECTION_HOME/webapp/static/favicon.ico"
backup "$INSPECTION_HOME/webapp/routes/api_admin.py"
backup "$INSPECTION_HOME/webapp/seed_data.py"
backup "$INSPECTION_HOME/scripts/probe_os.py"
backup "$INSPECTION_HOME/scripts/generate_inventory.py"
backup "$INSPECTION_HOME/ansible/roles/check_disk/tasks/aix.yml"

# ---------- 4. Apply files ----------
echo "[INFO] Applying webapp..."
cp -v "$HERE/files/webapp/app.py"                   "$INSPECTION_HOME/webapp/app.py"
cp -v "$HERE/files/webapp/templates/admin.html"     "$INSPECTION_HOME/webapp/templates/admin.html"
cp -v "$HERE/files/webapp/templates/base.html"      "$INSPECTION_HOME/webapp/templates/base.html"
cp -v "$HERE/files/webapp/static/js/admin.js"       "$INSPECTION_HOME/webapp/static/js/admin.js"
cp -v "$HERE/files/webapp/static/css/admin.css"     "$INSPECTION_HOME/webapp/static/css/admin.css"
cp -v "$HERE/files/webapp/static/favicon.ico"       "$INSPECTION_HOME/webapp/static/favicon.ico"
cp -v "$HERE/files/webapp/routes/api_admin.py"      "$INSPECTION_HOME/webapp/routes/api_admin.py"
cp -v "$HERE/files/webapp/seed_data.py"             "$INSPECTION_HOME/webapp/seed_data.py"

echo "[INFO] Applying scripts..."
cp -v "$HERE/files/scripts/probe_os.py"             "$INSPECTION_HOME/scripts/probe_os.py"
cp -v "$HERE/files/scripts/generate_inventory.py"   "$INSPECTION_HOME/scripts/generate_inventory.py"
cp -v "$HERE/files/scripts/smoke_dashboard.py"      "$INSPECTION_HOME/scripts/smoke_dashboard.py"
cp -v "$HERE/files/scripts/check_inspection.py"    "$INSPECTION_HOME/scripts/check_inspection.py"
cp -v "$HERE/files/scripts/deep_test.py"            "$INSPECTION_HOME/scripts/deep_test.py"
chmod +x "$INSPECTION_HOME/scripts/smoke_dashboard.py"
chmod +x "$INSPECTION_HOME/scripts/check_inspection.py"
chmod +x "$INSPECTION_HOME/scripts/deep_test.py"

echo "[INFO] Applying ansible role fix..."
cp -v "$HERE/files/ansible/roles/check_disk/tasks/aix.yml" "$INSPECTION_HOME/ansible/roles/check_disk/tasks/aix.yml"

# ---------- 5. Fix permissions (probe_os backup dir) ----------
echo "[INFO] Fixing permissions..."
mkdir -p "$INSPECTION_HOME/data/backups"
chown -R sysinfra:itagent "$INSPECTION_HOME/data/backups" 2>/dev/null || true
chmod -R u+w "$INSPECTION_HOME/data/backups"
# favicon perms
chown sysinfra:itagent "$INSPECTION_HOME/webapp/static/favicon.ico" 2>/dev/null || true
chmod 644 "$INSPECTION_HOME/webapp/static/favicon.ico"

# ---------- 6. Syntax check ----------
echo "[INFO] Syntax check..."
python3 -c "import py_compile; py_compile.compile('$INSPECTION_HOME/webapp/app.py', doraise=True)" \
    && echo "[OK] app.py" || { echo "[FAIL] app.py syntax error"; exit 1; }
python3 -c "import py_compile; py_compile.compile('$INSPECTION_HOME/webapp/routes/api_admin.py', doraise=True)" \
    && echo "[OK] api_admin.py" || { echo "[FAIL] api_admin.py syntax error"; exit 1; }
which node >/dev/null 2>&1 && node --check "$INSPECTION_HOME/webapp/static/js/admin.js" \
    && echo "[OK] admin.js" || echo "[WARN] node 未安裝, 跳過 JS syntax check"

# ---------- 7. Clean known bad data (from old seed_data bug) ----------
echo "[INFO] Cleaning bad inspection records (from old seed_data bug)..."
podman exec mongodb mongosh inspection --quiet --eval '
var r = db.inspections.deleteMany({run_date: {$not: {$regex: "^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]"}}});
print("deleted bad records:", r.deletedCount);' 2>/dev/null || \
  echo "[WARN] mongo cleanup skipped (podman/mongo 不可用)"

# ---------- 8. Update version.json ----------
VERSION_JSON="$INSPECTION_HOME/data/version.json"
cp "$VERSION_JSON" "${VERSION_JSON}.bak.${TS}"
python3 - "$VERSION_JSON" "$PATCH_VER" <<'PY_EOF'
import json, sys, datetime
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f: j = json.load(f)
j['version'] = ver
j['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
j.setdefault('changelog', []).insert(0,
    ver + " - " + datetime.datetime.now().strftime('%Y-%m-%d') +
    ": Full bundle (17 patches consolidated)")
with open(path, 'w') as f: json.dump(j, f, ensure_ascii=False, indent=2)
print("[OK] version.json -> " + ver)
PY_EOF

# ---------- 9. Restart webapp ----------
echo "[INFO] Restarting itagent-web..."
if systemctl is-active itagent-web >/dev/null 2>&1; then
    systemctl restart itagent-web
    ok=0
    for i in 1 2 3 4 5 6 7; do
        sleep 2
        HTTP=$(curl -sI -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:5000/login 2>/dev/null || echo 000)
        if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then ok=1; break; fi
    done
    [ $ok -eq 1 ] && echo "[OK] itagent-web running (HTTP $HTTP)" \
        || { echo "[FAIL] itagent-web 沒有回應"; exit 1; }
else
    echo "[SKIP] itagent-web service not active"
fi

# ---------- 10. Run smoke test ----------
echo
echo "========================================"
echo "  Auto smoke test (10 endpoints)"
echo "========================================"
INSPECTION_HOME="$INSPECTION_HOME" python3 "$INSPECTION_HOME/scripts/smoke_dashboard.py" 2>&1 | grep -v UserWarning | grep -v "warnings.warn" | grep -v jinja2
SMOKE_RC=${PIPESTATUS[0]}

echo
echo "========================================"
echo "  Inspection health check"
echo "========================================"
INSPECTION_HOME="$INSPECTION_HOME" python3 "$INSPECTION_HOME/scripts/check_inspection.py" 2>&1 | grep -v UserWarning | grep -v "warnings.warn" | grep -v jinja2

echo
echo "========================================"
echo "  v3.17.19.17 Full Bundle install complete"
echo "========================================"
echo "新功能 / 改進總覽:"
echo "  • AIX 巡檢支援"
echo "  • 網段掃描 OS 偵測 (SSH banner + uname probe + port heuristic)"
echo "  • 批次上線主機重設計 (一頁三步流程)"
echo "  • 主機刪除可選清歷史"
echo "  • 系統管理 → 🩺 系統診斷 (獨立 tab + 可下載 sanitized 報告)"
echo "  • Dashboard 加速 (system_info 488ms->10ms)"
echo "  • Static cache 1 小時 (頁面 4167ms->294ms)"
echo "  • UX 老花友善 (版本字加大加深 + nav active group 自動展開)"
echo "  • 多項 bug 修復 (CSP / probe_os 權限 / JS null / inventory 自包)"
echo
echo "工具腳本:"
echo "  python3 $INSPECTION_HOME/scripts/check_inspection.py    # 巡檢健康診斷"
echo "  python3 $INSPECTION_HOME/scripts/smoke_dashboard.py     # API smoke"
echo "  python3 $INSPECTION_HOME/scripts/deep_test.py           # 深度測試"
echo
[ $SMOKE_RC -eq 0 ] && echo "[OK] Smoke ALL PASS — Bundle install 成功" \
    || { echo "[WARN] Smoke 有失敗項目, 請查 log"; exit $SMOKE_RC; }
