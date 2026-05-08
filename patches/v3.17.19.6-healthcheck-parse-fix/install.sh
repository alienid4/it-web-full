#!/bin/bash
# v3.17.19.6 - Health Check Parse Fix
# Bug: health_check 截 body[:300] 才 _json.loads → 長 response (system_status ~400 字) 解析失敗 → 誤判 success=false
# Fix: parse 完整 body, 只 preview 截 150 字
set -e
PATCH_VER="3.17.19.6"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && exit 1
echo "[INFO] INSPECTION_HOME=$INSPECTION_HOME"
backup() { [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}"; }
backup "$INSPECTION_HOME/webapp/routes/api_admin.py"
cp -v "$HERE/files/api_admin.py" "$INSPECTION_HOME/webapp/routes/api_admin.py"
python3 -c "import py_compile; py_compile.compile('$INSPECTION_HOME/webapp/routes/api_admin.py', doraise=True)" || exit 1
python3 - "$INSPECTION_HOME/data/version.json" "$PATCH_VER" <<'PY_EOF'
import json, sys, datetime
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f: j = json.load(f)
j['version'] = ver; j['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
j.setdefault('changelog', []).insert(0, ver + ': 修 health-check parse JSON bug')
with open(path, 'w') as f: json.dump(j, f, ensure_ascii=False, indent=2)
PY_EOF
systemctl restart itagent-web 2>/dev/null && sleep 2
[ -f "$INSPECTION_HOME/scripts/smoke_dashboard.py" ] && python3 "$INSPECTION_HOME/scripts/smoke_dashboard.py"
echo "[OK] v3.17.19.6 done"
