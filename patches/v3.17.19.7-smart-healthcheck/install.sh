#!/bin/bash
# v3.17.19.7 - Smart Health Check
# Bug: /api/admin/settings + /api/hosts 風格不同 (只回 {"data":...} 沒 success 欄位) 被誤判失敗
# Fix: 改智能判斷 — HTTP 200 + 合法 JSON + 無 error 欄位 = OK
set -e
PATCH_VER="3.17.19.7"
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
backup "$INSPECTION_HOME/scripts/smoke_dashboard.py"
cp -v "$HERE/files/api_admin.py" "$INSPECTION_HOME/webapp/routes/api_admin.py"
cp -v "$HERE/files/smoke_dashboard.py" "$INSPECTION_HOME/scripts/smoke_dashboard.py"
chmod +x "$INSPECTION_HOME/scripts/smoke_dashboard.py"
python3 -c "import py_compile; py_compile.compile('$INSPECTION_HOME/webapp/routes/api_admin.py', doraise=True)" || exit 1
python3 - "$INSPECTION_HOME/data/version.json" "$PATCH_VER" <<'PY_EOF'
import json, sys, datetime
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f: j = json.load(f)
j['version'] = ver; j['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
j.setdefault('changelog', []).insert(0, ver + ': smart healthcheck')
with open(path, 'w') as f: json.dump(j, f, ensure_ascii=False, indent=2)
PY_EOF
systemctl restart itagent-web 2>/dev/null && sleep 2
python3 "$INSPECTION_HOME/scripts/smoke_dashboard.py" || { echo "[FAIL] smoke 有失敗"; exit 1; }
echo "[OK] v3.17.19.7 install + smoke ALL PASS"
