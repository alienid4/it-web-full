#!/bin/bash
# v3.17.19.9 - CSP whitelist + favicon
set -e
PATCH_VER="3.17.19.9"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && exit 1
echo "[INFO] INSPECTION_HOME=$INSPECTION_HOME"
backup() { [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}"; }
backup "$INSPECTION_HOME/webapp/app.py"
backup "$INSPECTION_HOME/webapp/templates/base.html"
cp -v "$HERE/files/app.py" "$INSPECTION_HOME/webapp/app.py"
cp -v "$HERE/files/base.html" "$INSPECTION_HOME/webapp/templates/base.html"
cp -v "$HERE/files/favicon.ico" "$INSPECTION_HOME/webapp/static/favicon.ico"
chown sysinfra:itagent "$INSPECTION_HOME/webapp/static/favicon.ico" 2>/dev/null
chmod 644 "$INSPECTION_HOME/webapp/static/favicon.ico"
python3 -c "import py_compile; py_compile.compile('$INSPECTION_HOME/webapp/app.py', doraise=True)" || exit 1
python3 - "$INSPECTION_HOME/data/version.json" "$PATCH_VER" <<'PY_EOF'
import json, sys, datetime
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f: j = json.load(f)
j['version'] = ver; j['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
j.setdefault('changelog', []).insert(0, ver + ': CSP + favicon')
with open(path, 'w') as f: json.dump(j, f, ensure_ascii=False, indent=2)
PY_EOF
systemctl restart itagent-web 2>/dev/null && sleep 4
curl -sI http://127.0.0.1:5000/favicon.ico | head -1
echo "[OK] v3.17.19.9 done"
