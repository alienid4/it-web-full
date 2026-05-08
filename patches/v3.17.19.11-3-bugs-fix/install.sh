#!/bin/bash
set -e
PATCH_VER="3.17.19.11"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && exit 1
echo "[INFO] INSPECTION_HOME=$INSPECTION_HOME"

# 1. fix backup dir 權限
mkdir -p "$INSPECTION_HOME/data/backups"
chown -R sysinfra:itagent "$INSPECTION_HOME/data/backups" 2>/dev/null || true
chmod -R u+w "$INSPECTION_HOME/data/backups"
echo "[OK] backup dir permissions fixed"

# 2. 推 JS + app.py 修
backup() { [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}"; }
backup "$INSPECTION_HOME/webapp/static/js/admin.js"
backup "$INSPECTION_HOME/webapp/app.py"
cp -v "$HERE/files/admin.js" "$INSPECTION_HOME/webapp/static/js/admin.js"
cp -v "$HERE/files/app.py" "$INSPECTION_HOME/webapp/app.py"
python3 -c "import py_compile; py_compile.compile('$INSPECTION_HOME/webapp/app.py', doraise=True)" || exit 1
which node >/dev/null 2>&1 && node --check "$INSPECTION_HOME/webapp/static/js/admin.js" && echo "[OK] JS pass"

python3 - "$INSPECTION_HOME/data/version.json" "$PATCH_VER" <<'PY_EOF'
import json, sys, datetime
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f: j = json.load(f)
j['version'] = ver; j['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
j.setdefault('changelog', []).insert(0, ver + ': 3 bugs fix')
with open(path, 'w') as f: json.dump(j, f, ensure_ascii=False, indent=2)
PY_EOF
systemctl restart itagent-web 2>/dev/null && sleep 5
python3 "$INSPECTION_HOME/scripts/smoke_dashboard.py" || exit 1
echo "[OK] v3.17.19.11"
