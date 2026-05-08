#!/bin/bash
# v3.17.19.3 - 系統健康檢查按鈕 (UX)
#
# Changes:
#   - 系統管理 dashboard 右上加兩個按鈕:
#       🩺 系統健康檢查  (一鍵跑 /api/admin/health-check 檢查 6 個 endpoint)
#       🔄 重新載入       (重新載入此頁的卡片資料)
#   - v3.17.19.2 已加 endpoint 但只在錯誤時才有診斷連結, 本版讓使用者隨時主動跑
#
# Baseline: v3.17.19.2
# Usage:    sudo bash install.sh
set -e

PATCH_VER="3.17.19.3"
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
if ! echo "$CUR_VER" | grep -qE '^3\.17\.19\.'; then
    echo "[WARN] Expected baseline 3.17.19.x, found $CUR_VER - proceed? (y/N)"
    read -r ans; [ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 1
fi

backup() { [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}" && echo "[BACKUP] $1"; }
backup "$INSPECTION_HOME/webapp/templates/admin.html"
cp -v "$HERE/files/admin.html" "$INSPECTION_HOME/webapp/templates/admin.html"

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
    ': 系統管理 dashboard 常駐健康檢查按鈕')
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
    [ $ok -eq 1 ] && echo "[OK] itagent-web running (HTTP $HTTP)" || { echo "[FAIL]"; exit 1; }
fi

echo
echo "========================================"
echo "  v3.17.19.3 install complete"
echo "========================================"
echo "點選位置:"
echo "  系統管理 → Dashboard sub-tab (預設)"
echo "  → 右上角 [🩺 系統健康檢查] 按鈕"
