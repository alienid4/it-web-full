#!/bin/bash
# v3.17.18.2 - AIX Port Heuristic
#
# Changes:
#   - SSH probe 失敗 (沒 key) 時，試 port 657 (IBM RMC) + port 199 (SMUX)
#   - 兩個 port 在 AIX 常開、Linux 罕見 → 高機率 AIX
#   - badge 顯示 "AIX? (port 657/199)" 紫色，提示但還沒 100% 確認
#   - 解決「掃描前需要先放 key」的雞生蛋問題
#
# Baseline: v3.17.18.1
# Usage:    sudo bash install.sh
set -e

PATCH_VER="3.17.18.2"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)

INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "[FAIL] Cannot find inspection directory"; exit 1; }
echo "[INFO] INSPECTION_HOME=$INSPECTION_HOME"

CUR_VER=$(python3 -c "import json; print(json.load(open('$INSPECTION_HOME/data/version.json'))['version'])" 2>/dev/null || echo "unknown")
echo "[INFO] Current version: $CUR_VER"
if ! echo "$CUR_VER" | grep -qE '^3\.17\.18\.'; then
    echo "[WARN] Expected baseline 3.17.18.x, found $CUR_VER - proceed? (y/N)"
    read -r ans; [ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 1
fi

backup() { [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}" && echo "[BACKUP] $1"; }
backup "$INSPECTION_HOME/webapp/routes/api_admin.py"
cp -v "$HERE/files/api_admin.py" "$INSPECTION_HOME/webapp/routes/api_admin.py"

VERSION_JSON="$INSPECTION_HOME/data/version.json"
cp "$VERSION_JSON" "${VERSION_JSON}.bak.${TS}"
python3 - "$VERSION_JSON" "$PATCH_VER" <<'PY_EOF'
import json, sys, datetime
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f: j = json.load(f)
j['version'] = ver
j['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
j.setdefault('changelog', []).insert(0,
    ver + ' - ' + datetime.datetime.now().strftime('%Y-%m-%d') +
    ': 網段掃描 AIX port heuristic (657 RMC + 199 SMUX)，無 key 也能猜 AIX')
with open(path, 'w') as f: json.dump(j, f, ensure_ascii=False, indent=2)
print('[OK] version.json -> ' + ver)
PY_EOF

if systemctl is-active itagent-web >/dev/null 2>&1; then
    systemctl restart itagent-web
    ok=0
    for i in 1 2 3 4 5; do
        sleep 2
        HTTP=$(curl -sI -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:5000/login 2>/dev/null || echo 000)
        [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ] && ok=1 && break
    done
    [ $ok -eq 1 ] && echo "[OK] itagent-web running (HTTP $HTTP)" || { echo "[FAIL] itagent-web not responding"; exit 1; }
fi

echo
echo "========================================"
echo "  v3.17.18.2 install complete"
echo "========================================"
echo "現在掃描三層偵測 AIX:"
echo "  1. SSH banner 含 AIX → 'AIX (banner)'"
echo "  2. 有 sysinfra key → ssh uname -s → 'AIX (uname)'"
echo "  3. 沒 key + port 657/199 開 → 'AIX? (port 657/199)' (高機率)"
