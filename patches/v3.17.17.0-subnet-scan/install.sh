#!/bin/bash
# v3.17.17.0 - Subnet Scan
#
# Changes:
#   - Subnet scan (ping sweep CIDR) in batch onboard modal
#   - Tool priority: nmap -> fping -> parallel ping (always works)
#   - Select live hosts + "全選未加入" shortcut -> add to system
#   - Max /22 (1022 IPs) to avoid runaway scans
#
# Baseline: v3.17.16.0
# Usage:    sudo bash install.sh
#
# Note on nmap:
#   nmap provides the fastest and most accurate scan.
#   If not installed, fping is tried next, then parallel ping fallback.
#   To install on RHEL/Rocky: yum install -y nmap
#   To install on Debian/Ubuntu: apt-get install -y nmap
#   The feature works without nmap (fallback always available).
set -e

PATCH_VER="3.17.17.0"
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
if ! echo "$CUR_VER" | grep -qE '^3\.17\.16\.'; then
    echo "[WARN] Expected baseline 3.17.16.x, found $CUR_VER - proceed? (y/N)"
    read -r ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 1
fi

# ---------- 3. Optional: install nmap ----------
if ! command -v nmap >/dev/null 2>&1; then
    echo "[INFO] nmap not found. Trying to install..."
    if command -v yum >/dev/null 2>&1; then
        yum install -y nmap 2>/dev/null && echo "[OK] nmap installed via yum" || echo "[WARN] nmap install failed - fallback (parallel ping) will be used"
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get install -y nmap 2>/dev/null && echo "[OK] nmap installed via apt" || echo "[WARN] nmap install failed - fallback (parallel ping) will be used"
    else
        echo "[WARN] Cannot install nmap - fallback (parallel ping) will be used"
    fi
else
    echo "[OK] nmap already installed: $(command -v nmap)"
fi

# ---------- 4. Backup ----------
backup() { [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}" && echo "[BACKUP] $1"; }
backup "$INSPECTION_HOME/webapp/routes/api_admin.py"
backup "$INSPECTION_HOME/webapp/static/js/admin.js"
backup "$INSPECTION_HOME/webapp/templates/admin.html"

# ---------- 5. Apply files ----------
echo "[INFO] Applying api_admin.py (scan-subnet endpoint)"
cp -v "$HERE/files/api_admin.py" "$INSPECTION_HOME/webapp/routes/api_admin.py"

echo "[INFO] Applying admin.js (subnet scan JS)"
cp -v "$HERE/files/admin.js" "$INSPECTION_HOME/webapp/static/js/admin.js"

echo "[INFO] Applying admin.html (scan tab in batch modal)"
cp -v "$HERE/files/admin.html" "$INSPECTION_HOME/webapp/templates/admin.html"

# ---------- 6. Update version.json ----------
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
    ": Subnet scan (nmap/fping/parallel-ping fallback) + select to onboard")
with open(path, 'w', encoding='utf-8') as f:
    json.dump(j, f, ensure_ascii=False, indent=2)
print("[OK] version.json -> " + ver)
PY_EOF
fi

# ---------- 7. Restart webapp ----------
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
echo "  v3.17.17.0 install complete"
echo "========================================"
echo "Verify:"
echo "  Admin -> Host Management tab"
echo "  -> 批次上線主機 -> 網段掃描 tab"
echo "  -> Enter CIDR (e.g. 10.92.198.0/24) -> 掃描"
echo "  -> 勾選主機 -> 加入已選取"
echo ""
echo "nmap status: $(command -v nmap 2>/dev/null || echo 'not installed (parallel ping fallback active)')"
