#!/bin/bash
# v3.17.19.0 - 主機上線頁面重設計 (一頁完成)
#
# Changes:
#   - 移除 4 個 tab 結構, 改用 3 段 accordion (單台/貼清單/CSV/掃描)
#   - 加入候選池 (所有來源灌進同一個池)
#   - STEP 2: 一鍵上線勾選的 N 台 (含進度區+結果表)
#   - STEP 3: 自動跑首次巡檢 + 即時 polling 看到今日卡片連結
#   - 後端 batch-onboard 新增 run_inspection 參數
#   - 新增 /hosts/onboard-status?job_id=xxx 輪詢 endpoint
#
# Baseline: v3.17.18.2
# Usage:    sudo bash install.sh
set -e

PATCH_VER="3.17.19.0"
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
backup "$INSPECTION_HOME/webapp/templates/admin.html"
backup "$INSPECTION_HOME/webapp/static/js/admin.js"
backup "$INSPECTION_HOME/webapp/routes/api_admin.py"

cp -v "$HERE/files/admin.html" "$INSPECTION_HOME/webapp/templates/admin.html"
cp -v "$HERE/files/admin.js"   "$INSPECTION_HOME/webapp/static/js/admin.js"
cp -v "$HERE/files/api_admin.py" "$INSPECTION_HOME/webapp/routes/api_admin.py"

# Verify Python syntax
python3 -c "import py_compile; py_compile.compile('$INSPECTION_HOME/webapp/routes/api_admin.py', doraise=True)" \
    && echo "[OK] api_admin.py syntax check pass" \
    || { echo "[FAIL] api_admin.py syntax error"; exit 1; }

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
    ': 主機上線頁面重設計 (一頁完成: 候選池 + 一鍵全自動到首次巡檢)')
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
echo "  v3.17.19.0 install complete"
echo "========================================"
echo "新流程:"
echo "  主機管理 -> 批次上線主機"
echo "  STEP 1: 三段 accordion (單台/貼清單/CSV/掃描) -> 加入候選池"
echo "  候選清單: 全選/全不選/清空, 每台可單獨勾選或移除"
echo "  STEP 2: ☑ 同時跑首次巡檢 + [✦ 一鍵上線勾選的 N 台 ✦]"
echo "  STEP 3: 進度區 + 結果表 (DB/Inventory/Probe/Inspection 即時更新)"
