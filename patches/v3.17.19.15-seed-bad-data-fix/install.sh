#!/bin/bash
set -e
PATCH_VER="3.17.19.15"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && exit 1
backup() { [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}"; }
backup "$INSPECTION_HOME/webapp/seed_data.py"
backup "$INSPECTION_HOME/scripts/check_inspection.py"
cp -v "$HERE/files/seed_data.py" "$INSPECTION_HOME/webapp/seed_data.py"
cp -v "$HERE/files/check_inspection.py" "$INSPECTION_HOME/scripts/check_inspection.py"
chmod +x "$INSPECTION_HOME/scripts/check_inspection.py"
python3 -c "import py_compile; py_compile.compile('$INSPECTION_HOME/webapp/seed_data.py', doraise=True)" || exit 1
python3 -c "import py_compile; py_compile.compile('$INSPECTION_HOME/scripts/check_inspection.py', doraise=True)" || exit 1

echo "[INFO] 清掉現有壞資料 (run_date 不是 YYYY-MM-DD)..."
podman exec mongodb mongosh inspection --quiet --eval '
var r = db.inspections.deleteMany({run_date: {$not: {$regex: "^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]"}}});
print("deleted bad records:", r.deletedCount);'

python3 - "$INSPECTION_HOME/data/version.json" "$PATCH_VER" <<'PY_EOF'
import json, sys, datetime
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f: j = json.load(f)
j['version'] = ver; j['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
j.setdefault('changelog', []).insert(0, ver + ': seed_data + check_inspection fix')
with open(path, 'w') as f: json.dump(j, f, ensure_ascii=False, indent=2)
PY_EOF

systemctl restart itagent-web 2>/dev/null && sleep 3
echo
echo "[VERIFY] 跑 check_inspection.py:"
python3 "$INSPECTION_HOME/scripts/check_inspection.py" 2>&1 | grep -v UserWarning | grep -v warnings.warn
echo "[OK] v3.17.19.15"
