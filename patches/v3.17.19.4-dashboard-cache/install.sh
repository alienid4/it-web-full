#!/bin/bash
# v3.17.19.4 - Dashboard 加速
#
# Changes:
#   - system_info / system_status / health_check 加 TTL 記憶體快取
#     - system/info: TTL 60s (這些值幾乎不變)
#     - system/status: TTL 10s (服務狀態可能變)
#     - subprocess 改平行 (ThreadPoolExecutor)
#   - 效果 (test_client 量測):
#     - system/info  cold 511ms → warm 1.8ms (270x)
#     - system/status cold 112ms → warm 2ms  (50x)
#     - health-check cold 669ms → 平行打 6 endpoint
#
# Baseline: v3.17.19.3
# Usage:    sudo bash install.sh
set -e

PATCH_VER="3.17.19.4"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)

INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "[FAIL]"; exit 1; }
echo "[INFO] INSPECTION_HOME=$INSPECTION_HOME"

CUR_VER=$(python3 -c "import json; print(json.load(open('$INSPECTION_HOME/data/version.json'))['version'])" 2>/dev/null || echo "unknown")
echo "[INFO] Current: $CUR_VER"
if ! echo "$CUR_VER" | grep -qE '^3\.17\.19\.'; then
    echo "[WARN] baseline 3.17.19.x expected, found $CUR_VER (y/N)?"
    read -r ans; [ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 1
fi

backup() { [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}" && echo "[BACKUP] $1"; }
backup "$INSPECTION_HOME/webapp/routes/api_admin.py"
cp -v "$HERE/files/api_admin.py" "$INSPECTION_HOME/webapp/routes/api_admin.py"

python3 -c "import py_compile; py_compile.compile('$INSPECTION_HOME/webapp/routes/api_admin.py', doraise=True)" \
    && echo "[OK] py syntax pass" \
    || { echo "[FAIL] py syntax error"; exit 1; }

VERSION_JSON="$INSPECTION_HOME/data/version.json"
cp "$VERSION_JSON" "${VERSION_JSON}.bak.${TS}"
python3 - "$VERSION_JSON" "$PATCH_VER" <<'PY_EOF'
import json, sys, datetime
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f: j = json.load(f)
j['version'] = ver
j['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
j.setdefault('changelog', []).insert(0,
    ver + ': dashboard 加速 (TTL 快取 + 平行 subprocess)')
with open(path, 'w') as f: json.dump(j, f, ensure_ascii=False, indent=2)
print('[OK] version -> ' + ver)
PY_EOF

if systemctl is-active itagent-web >/dev/null 2>&1; then
    systemctl restart itagent-web
    ok=0; for i in 1 2 3 4 5; do sleep 2
        HTTP=$(curl -sI -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:5000/login 2>/dev/null || echo 000)
        [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ] && ok=1 && break
    done
    [ $ok -eq 1 ] && echo "[OK] HTTP $HTTP" || { echo "[FAIL]"; exit 1; }
fi

echo
echo "v3.17.19.4 install complete. Dashboard 卡片從第 2 次起 <5ms."
