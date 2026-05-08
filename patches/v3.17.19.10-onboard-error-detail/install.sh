#!/bin/bash
set -e
PATCH_VER="3.17.19.10"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && exit 1
cp -av "$INSPECTION_HOME/webapp/static/js/admin.js" "$INSPECTION_HOME/webapp/static/js/admin.js.bak.${TS}" 2>/dev/null
cp -v "$HERE/files/admin.js" "$INSPECTION_HOME/webapp/static/js/admin.js"
node --check "$INSPECTION_HOME/webapp/static/js/admin.js" 2>/dev/null && echo "[OK] JS syntax pass" || true
python3 - "$INSPECTION_HOME/data/version.json" "$PATCH_VER" <<'PY_EOF'
import json, sys, datetime
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f: j = json.load(f)
j['version'] = ver; j['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
j.setdefault('changelog', []).insert(0, ver + ': onboard error detail')
with open(path, 'w') as f: json.dump(j, f, ensure_ascii=False, indent=2)
PY_EOF
systemctl restart itagent-web 2>/dev/null && sleep 4
python3 "$INSPECTION_HOME/scripts/smoke_dashboard.py" || exit 1
echo "[OK] v3.17.19.10 done"
