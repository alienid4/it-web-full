#!/bin/bash
# v3.17.19.8 - Pre-warm Ping-All Cache
# 找到「主管儀表板展開慢 2 秒」的真兇: /api/admin/hosts/ping-all 冷啟動 2022ms
# Fix: 1) ping timeout -W 2 -> -W 1 (LAN 1 秒夠)  2) startup 背景預熱
set -e
PATCH_VER="3.17.19.8"
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
j.setdefault('changelog', []).insert(0, ver + ': ping-all prewarm + timeout reduction')
with open(path, 'w') as f: json.dump(j, f, ensure_ascii=False, indent=2)
PY_EOF
systemctl restart itagent-web 2>/dev/null && sleep 5
python3 "$INSPECTION_HOME/scripts/smoke_dashboard.py" || { echo "[FAIL] smoke 有失敗"; exit 1; }
echo "[OK] v3.17.19.8 install + smoke ALL PASS"
