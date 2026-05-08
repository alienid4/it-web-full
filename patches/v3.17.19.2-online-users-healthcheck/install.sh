#!/bin/bash
# v3.17.19.2 - online-users + health-check + 防靜默失敗
#
# Changes:
#   - 補上缺失的 /api/admin/online-users (JS 早就在 fetch 但 server 沒 route)
#   - 新增 /api/admin/health-check 端到端檢查所有 dashboard endpoint
#   - dashboard JS 改成「防靜默失敗」: HTTP error 直接顯示「⚠ XXX 載入失敗」+ 診斷連結
#   - 點診斷連結觸發 runHealthCheck() 列出所有 endpoint 狀態
#
# Baseline: v3.17.19.1
# Usage:    sudo bash install.sh
#
# 為什麼補這個:
#   之前 dashboard 卡片「載入中...」永久不變，是因為 JS 對 401/error 採「if (!res.success) return」
#   靜默退出。本版加 catch 顯示明確錯誤，並提供 health-check 一鍵列出所有問題端點。
set -e

PATCH_VER="3.17.19.2"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)

INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "[FAIL] Cannot find inspection directory"; exit 1; }
echo "[INFO] INSPECTION_HOME=$INSPECTION_HOME"

CUR_VER=$(python3 -c "import json; print(json.load(open('$INSPECTION_HOME/data/version.json'))['version'])" 2>/dev/null || echo "unknown")
echo "[INFO] Current version: $CUR_VER"
if ! echo "$CUR_VER" | grep -qE '^3\.17\.19\.'; then
    echo "[WARN] Expected baseline 3.17.19.x, found $CUR_VER - proceed? (y/N)"
    read -r ans; [ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 1
fi

backup() { [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}" && echo "[BACKUP] $1"; }
backup "$INSPECTION_HOME/webapp/routes/api_admin.py"
backup "$INSPECTION_HOME/webapp/static/js/admin.js"

cp -v "$HERE/files/api_admin.py" "$INSPECTION_HOME/webapp/routes/api_admin.py"
cp -v "$HERE/files/admin.js"     "$INSPECTION_HOME/webapp/static/js/admin.js"

python3 -c "import py_compile; py_compile.compile('$INSPECTION_HOME/webapp/routes/api_admin.py', doraise=True)" \
    && echo "[OK] api_admin.py syntax pass" \
    || { echo "[FAIL] api_admin.py syntax error"; exit 1; }

VERSION_JSON="$INSPECTION_HOME/data/version.json"
cp "$VERSION_JSON" "${VERSION_JSON}.bak.${TS}"
python3 - "$VERSION_JSON" "$PATCH_VER" <<'PY_EOF'
import json, sys, datetime
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f: j = json.load(f)
j['version'] = ver
j['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
j.setdefault('changelog', []).insert(0,
    ver + ' - ' + datetime.datetime.now().strftime('%Y-%m-%d') +
    ': 補 /api/admin/online-users + /api/admin/health-check + dashboard 防靜默失敗')
with open(path, 'w') as f: json.dump(j, f, ensure_ascii=False, indent=2)
print('[OK] version.json -> ' + ver)
PY_EOF

if systemctl is-active itagent-web >/dev/null 2>&1; then
    systemctl restart itagent-web
    ok=0
    for i in 1 2 3 4 5; do
        sleep 2
        HTTP=$(curl -sI -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:5000/login 2>/dev/null || echo 000)
        [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ] && ok=1 && break
    done
    [ $ok -eq 1 ] && echo "[OK] itagent-web running (HTTP $HTTP)" || { echo "[FAIL] itagent-web not responding"; exit 1; }
fi

echo
echo "========================================"
echo "  v3.17.19.2 install complete"
echo "========================================"
echo "在線使用者卡片現在應該有資料了"
echo ""
echo "新增的健康檢查機制:"
echo "  GET /api/admin/health-check (需登入)"
echo "  → 端到端檢查 6 個關鍵 dashboard endpoint"
echo "  → 任何端點 fail 都會在 dashboard 顯示明確錯誤+診斷連結"
echo ""
echo "Dashboard 從此不會靜默卡在「載入中...」"
