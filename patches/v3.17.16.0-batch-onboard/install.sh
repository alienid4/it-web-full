#!/bin/bash
# v3.17.16.0 - Batch Host Onboard
#
# Changes:
#   - Batch host onboard UI: paste list or CSV upload
#   - Auto rebuild ansible inventory after add
#   - Auto probe OS per host (continue on failure, show log per host)
#
# Baseline: v3.17.15.0a
# Usage:    sudo bash install.sh
set -e

PATCH_VER="3.17.16.0"
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
if ! echo "$CUR_VER" | grep -qE '^3\.17\.15\.'; then
    echo "[WARN] Expected baseline 3.17.15.x, found $CUR_VER - proceed? (y/N)"
    read -r ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 1
fi

# ---------- 3. Backup ----------
backup() { [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}" && echo "[BACKUP] $1"; }
backup "$INSPECTION_HOME/webapp/routes/api_admin.py"
backup "$INSPECTION_HOME/webapp/static/js/admin.js"
backup "$INSPECTION_HOME/webapp/templates/admin.html"

# ---------- 4. Apply files ----------
echo "[INFO] Applying api_admin.py (batch-onboard endpoint)"
cp -v "$HERE/files/api_admin.py" "$INSPECTION_HOME/webapp/routes/api_admin.py"

echo "[INFO] Applying admin.js (batch onboard JS)"
cp -v "$HERE/files/admin.js" "$INSPECTION_HOME/webapp/static/js/admin.js"

echo "[INFO] Applying admin.html (batch onboard button + modal)"
cp -v "$HERE/files/admin.html" "$INSPECTION_HOME/webapp/templates/admin.html"

# ---------- 5. Update version.json ----------
VERSION_JSON="$INSPECTION_HOME/data/version.json"
if [ -f "$VERSION_JSON" ]; then
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
    ": Batch host onboard (paste/CSV + auto inventory + probe OS per host)")
with open(path, 'w', encoding='utf-8') as f:
    json.dump(j, f, ensure_ascii=False, indent=2)
print("[OK] version.json -> " + ver)
PY_EOF
fi

# ---------- 6. Restart webapp ----------
echo "[INFO] Restarting itagent-web"
if systemctl is-active itagent-web >/dev/null 2>&1; then
    systemctl restart itagent-web
    ok=0
    for i in 1 2 3 4 5; do
        sleep 2
        HTTP=$(curl -sI -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:5000/login 2>/dev/null || echo 000)
        if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then ok=1; break; fi
        echo "[INFO] Waiting... ($i/5, http=${HTTP})"
    done
    [ $ok -eq 1 ] && echo "[OK] itagent-web running (HTTP $HTTP)" || { echo "[FAIL] itagent-web not responding"; exit 1; }
else
    echo "[SKIP] itagent-web not active"
fi

echo
echo "========================================"
echo "  v3.17.16.0 install complete"
echo "========================================"
echo "Verify:"
echo "  Admin -> Host Management tab"
echo "  -> New button: 批次上線主機"
echo "  -> Paste hostname/IP list or upload CSV"
echo "  -> Auto rebuild inventory + probe OS"
