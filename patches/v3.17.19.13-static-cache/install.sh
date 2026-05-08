#!/bin/bash
set -e
PATCH_VER="3.17.19.13"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && exit 1
backup() { [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}"; }
backup "$INSPECTION_HOME/webapp/app.py"
cp -v "$HERE/files/app.py" "$INSPECTION_HOME/webapp/app.py"
python3 -c "import py_compile; py_compile.compile('$INSPECTION_HOME/webapp/app.py', doraise=True)" || exit 1
python3 - "$INSPECTION_HOME/data/version.json" "$PATCH_VER" <<'PY_EOF'
import json, sys, datetime
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f: j = json.load(f)
j['version'] = ver; j['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
j.setdefault('changelog', []).insert(0, ver + ': static cache')
with open(path, 'w') as f: json.dump(j, f, ensure_ascii=False, indent=2)
PY_EOF
systemctl restart itagent-web 2>/dev/null && sleep 4
echo "[verify] /static/css/cathay.css cache-control:"
curl -sI http://127.0.0.1:5000/static/css/cathay.css | grep -i cache-control
python3 "$INSPECTION_HOME/scripts/smoke_dashboard.py" || exit 1
echo "[OK] v3.17.19.13"
