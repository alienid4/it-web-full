#!/bin/bash
# v3.17.15.0a - NMON IBM Dual Cron Schedule
#
# Changes:
#   1. Replace configurable nmon interval with IBM fixed dual cron:
#      - Daily/Weekly:  nmon -s 60  -c 1440  (1min x 1440 = 24h)
#      - Monthly cap:   nmon -s 900 -c 96    (15min x 96  = 24h)
#   2. Status check shows both cron lines (daily + monthly)
#   3. Admin schedule UI simplified (remove interval selector)
#   4. Admin info card: data retention policy + scale guide
#
# Baseline: v3.17.14.2
# Usage:    sudo bash install.sh
set -e

PATCH_VER="3.17.15.0a"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)

# ---------- 1. Find INSPECTION_HOME ----------
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
if [ -z "$INSPECTION_HOME" ]; then
    echo "[FAIL] Cannot find inspection directory (version.json missing)"
    exit 1
fi
echo "[INFO] INSPECTION_HOME=$INSPECTION_HOME"

# ---------- 2. Check baseline v3.17.14.x ----------
CUR_VER=$(python3 -c "import json; print(json.load(open('$INSPECTION_HOME/data/version.json'))['version'])" 2>/dev/null || echo "unknown")
echo "[INFO] Current version: $CUR_VER"
if ! echo "$CUR_VER" | grep -qE '^3\.17\.14\.'; then
    echo "[WARN] Expected baseline 3.17.14.x, found $CUR_VER - proceed anyway? (y/N)"
    read -r ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 1
fi

# ---------- 3. Backup ----------
backup() {
    [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}" && echo "[BACKUP] $1"
}
backup "$INSPECTION_HOME/ansible/roles/collect_nmon/tasks/main.yml"
backup "$INSPECTION_HOME/scripts/verify_nmon.py"
backup "$INSPECTION_HOME/webapp/routes/api_nmon.py"
backup "$INSPECTION_HOME/webapp/static/js/admin.js"
backup "$INSPECTION_HOME/webapp/templates/admin.html"

# ---------- 4. Apply files ----------
echo "[INFO] Applying collect_nmon ansible role (IBM dual cron)"
cp -v "$HERE/files/collect_nmon_main.yml" "$INSPECTION_HOME/ansible/roles/collect_nmon/tasks/main.yml"

echo "[INFO] Applying verify_nmon.py (dual cron status check)"
cp -v "$HERE/files/verify_nmon.py" "$INSPECTION_HOME/scripts/verify_nmon.py"

echo "[INFO] Applying api_nmon.py (simplified schedule API)"
cp -v "$HERE/files/api_nmon.py" "$INSPECTION_HOME/webapp/routes/api_nmon.py"

echo "[INFO] Applying admin.js (IBM schedule UI)"
cp -v "$HERE/files/admin.js" "$INSPECTION_HOME/webapp/static/js/admin.js"

echo "[INFO] Applying admin.html (info card + simplified schedule UI)"
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
log_entry = ver + " - " + datetime.datetime.now().strftime('%Y-%m-%d') + ": NMON IBM dual cron: fixed 60s*1440 (daily/weekly) + 900s*96 (monthly), dual cron status, admin info card"
j.setdefault('changelog', []).insert(0, log_entry)
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
    if [ $ok -eq 1 ]; then
        echo "[OK] itagent-web running (HTTP $HTTP)"
    else
        echo "[FAIL] itagent-web not responding - check: journalctl -u itagent-web -n 50"
        exit 1
    fi
else
    echo "[SKIP] itagent-web not active"
fi

echo
echo "========================================"
echo "  v3.17.15.0 install complete"
echo "========================================"
echo "Verify:"
echo "  1. Admin -> perf-mgmt tab -> NMON schedule: IBM dual cron displayed"
echo "  2. Apply schedule -> ansible deploys 2 crons per host"
echo "  3. Status check -> shows daily + monthly cron columns"
echo "  4. Info card at bottom of perf-mgmt tab"
echo
echo "Backups:"
ls -la "${INSPECTION_HOME}"/ansible/roles/collect_nmon/tasks/main.yml.bak.${TS} \
       "${INSPECTION_HOME}"/webapp/{static/js/admin.js,templates/admin.html,routes/api_nmon.py}.bak.${TS} \
       "${INSPECTION_HOME}"/scripts/verify_nmon.py.bak.${TS} 2>/dev/null || true
