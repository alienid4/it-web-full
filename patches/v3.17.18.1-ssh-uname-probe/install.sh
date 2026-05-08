#!/bin/bash
# v3.17.18.1 - Subnet Scan + SSH uname Probe
#
# Changes:
#   - Banner generic + sysinfra key 可用 -> 真實 SSH 跑 uname -s
#   - AIX 主機可被準確識別 (uname -s = "AIX")
#
# Baseline: v3.17.18.0
# Usage:    sudo bash install.sh
set -e

PATCH_VER="3.17.18.1"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)

# ---------- 1. Find INSPECTION_HOME ----------
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
if [ -z "$INSPECTION_HOME" ]; then
    echo "[FAIL] Cannot find inspection directory"
    exit 1
fi
echo "[INFO] INSPECTION_HOME=$INSPECTION_HOME"

# ---------- 2. Check baseline ----------
CUR_VER=$(python3 -c "import json; print(json.load(open('$INSPECTION_HOME/data/version.json'))['version'])" 2>/dev/null || echo "unknown")
echo "[INFO] Current version: $CUR_VER"
if ! echo "$CUR_VER" | grep -qE '^3\.17\.18\.'; then
    echo "[WARN] Expected baseline 3.17.18.x, found $CUR_VER - proceed? (y/N)"
    read -r ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 1
fi

# ---------- 3. Verify sysinfra key ----------
SSH_KEY="/home/sysinfra/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
    echo "[WARN] sysinfra key not found at $SSH_KEY"
    echo "       SSH probe will silently skip - banner-only detection still works"
fi

# ---------- 4. Backup + apply ----------
backup() { [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}" && echo "[BACKUP] $1"; }
backup "$INSPECTION_HOME/webapp/routes/api_admin.py"
cp -v "$HERE/files/api_admin.py" "$INSPECTION_HOME/webapp/routes/api_admin.py"

# ---------- 5. Update version.json ----------
VERSION_JSON="$INSPECTION_HOME/data/version.json"
cp "$VERSION_JSON" "${VERSION_JSON}.bak.${TS}"
python3 - "$VERSION_JSON" "$PATCH_VER" <<'PY_EOF'
import json, sys, datetime
path, ver = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    j = json.load(f)
j['version'] = ver
j['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
j.setdefault('changelog', []).insert(0,
    ver + " - " + datetime.datetime.now().strftime('%Y-%m-%d') +
    ": Subnet scan SSH uname probe (AIX 100% accurate via sysinfra key)")
with open(path, 'w', encoding='utf-8') as f:
    json.dump(j, f, ensure_ascii=False, indent=2)
print("[OK] version.json -> " + ver)
PY_EOF

# ---------- 6. Restart webapp ----------
echo "[INFO] Restarting itagent-web"
if systemctl is-active itagent-web >/dev/null 2>&1; then
    systemctl restart itagent-web
    ok=0
    for i in 1 2 3 4 5; do
        sleep 2
        HTTP=$(curl -sI -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:5000/login 2>/dev/null || echo 000)
        if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then ok=1; break; fi
    done
    [ $ok -eq 1 ] && echo "[OK] itagent-web running (HTTP $HTTP)" || { echo "[FAIL] itagent-web not responding"; exit 1; }
fi

echo
echo "========================================"
echo "  v3.17.18.1 install complete"
echo "========================================"
echo "AIX 主機現在會被正確識別："
echo "  - SSH banner generic -> ssh sysinfra@host 'uname -s'"
echo "  - uname=AIX -> 'AIX (uname)' 紫色 badge"
echo "  - uname=Linux -> 'Linux (uname)'"
echo "需要 sysinfra key 已分發到目標主機"
