#!/bin/bash
# v3.17.19.5 - Dashboard Real Fix + Smoke Test
#
# Changes:
#   - system_info: 改用 Python import / file read 代替 subprocess CLI
#       - import ansible (取版本) ← 取代 'ansible --version' (省 400ms)
#       - read /etc/os-release (取 OS 名稱)
#       - read /proc/uptime (取 boot time + uptime)
#       - socket.gethostname() (instant)
#   - 加 scripts/smoke_dashboard.py 端到端驗證腳本
#       - 內部 test_client 直接打 8 個關鍵 endpoint
#       - 檢查 HTTP / json.success / 必備欄位
#       - 標記 SLOW (>800ms) / FAIL
#       - 部署完自動跑，過了才算成功
#
# Effect:
#   - system/info  cold 488ms → 10ms (48x)
#   - health-check cold 568ms → 124ms (4.5x)
#
# Baseline: v3.17.19.4
set -e

PATCH_VER="3.17.19.5"
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
    echo "[WARN] baseline 3.17.19.x expected (y/N)?"; read -r ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 1
fi

backup() { [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}" && echo "[BACKUP] $1"; }
backup "$INSPECTION_HOME/webapp/routes/api_admin.py"
backup "$INSPECTION_HOME/scripts/smoke_dashboard.py"

cp -v "$HERE/files/api_admin.py" "$INSPECTION_HOME/webapp/routes/api_admin.py"
cp -v "$HERE/files/smoke_dashboard.py" "$INSPECTION_HOME/scripts/smoke_dashboard.py"
chmod +x "$INSPECTION_HOME/scripts/smoke_dashboard.py"

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
    ver + ': dashboard 真正加速 (system/info 488ms->10ms) + smoke_dashboard.py 自動驗證')
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
echo "========================================"
echo "  Running automated dashboard smoke test"
echo "========================================"
INSPECTION_HOME=$INSPECTION_HOME python3 $INSPECTION_HOME/scripts/smoke_dashboard.py
SMOKE_RC=$?
echo
if [ $SMOKE_RC -eq 0 ]; then
    echo "[OK] v3.17.19.5 install + smoke ALL PASS"
else
    echo "[WARN] v3.17.19.5 installed but smoke 有 FAIL，請查 log"
    exit $SMOKE_RC
fi
