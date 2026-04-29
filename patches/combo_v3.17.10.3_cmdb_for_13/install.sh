#!/bin/bash
# v3.17.10.3 hot-fix: 拓撲頁加「📊 狀態」按鈕 (前端查採集進度) + tooltip 改清楚
# 適用對象: 任何 v3.14.0.0+ (有 dependencies 模組) 的環境
# 改動範圍: 3 個檔 (dependencies.js + dependencies.html + dependencies_fullscreen.html)
set -e

PATCH_VER="3.17.10.3"
HERE="$(cd "$(dirname "$0")" && pwd)"

# auto-detect INSPECTION_HOME
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "[FAIL] 找不到 INSPECTION_HOME"; exit 1; }
echo "[i] INSPECTION_HOME=$INSPECTION_HOME"

# detect service
SERVICE=""
for svc in itagent-web itagent inspection-web; do
    systemctl list-unit-files | grep -q "^$svc" && SERVICE="$svc" && break
done
[ -z "$SERVICE" ] && { echo "[FAIL] 找不到 web service"; exit 1; }
echo "[i] SERVICE=$SERVICE"

TUNNEL_SVC=""
for svc in itagent-tunnel cloudflared; do
    systemctl list-unit-files | grep -q "^$svc" && TUNNEL_SVC="$svc" && break
done

CURRENT_VER=$(python3 -c "import json; print(json.load(open('$INSPECTION_HOME/data/version.json'))['version'])" 2>/dev/null || echo "?")
echo "[i] 目前版本: $CURRENT_VER → 將升級到: $PATCH_VER"
echo ""

TS=$(date +%Y%m%d_%H%M%S)
BACKUP_ROOT="/var/backups/inspection/v${PATCH_VER}_${TS}"
mkdir -p "$BACKUP_ROOT/webapp/static/js" "$BACKUP_ROOT/webapp/templates"

# ============ Step 1: 備份 ============
echo "[1/4] 備份 3 個既有檔"
for f in "webapp/static/js/dependencies.js" "webapp/templates/dependencies.html" "webapp/templates/dependencies_fullscreen.html"; do
    src="$INSPECTION_HOME/$f"
    if [ -f "$src" ]; then
        cp "$src" "$BACKUP_ROOT/$f"
        echo "      $f"
    else
        echo "[FAIL] 找不到目標檔: $src"; exit 1
    fi
done
echo "      → $BACKUP_ROOT"

# ============ Step 2: 部署 ============
echo ""
echo "[2/4] 部署 3 個檔"
cp "$HERE/files/webapp/static/js/dependencies.js"            "$INSPECTION_HOME/webapp/static/js/dependencies.js"
cp "$HERE/files/webapp/templates/dependencies.html"          "$INSPECTION_HOME/webapp/templates/dependencies.html"
cp "$HERE/files/webapp/templates/dependencies_fullscreen.html" "$INSPECTION_HOME/webapp/templates/dependencies_fullscreen.html"
chown sysinfra:itagent "$INSPECTION_HOME/webapp/static/js/dependencies.js" "$INSPECTION_HOME/webapp/templates/dependencies.html" "$INSPECTION_HOME/webapp/templates/dependencies_fullscreen.html" 2>/dev/null || true
echo "      OK"

# ============ Step 3: bump version + 重啟 ============
echo ""
echo "[3/4] bump version + 重啟"
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp, encoding="utf-8") as f:
    d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
note = "$PATCH_VER - $(date +%Y-%m-%d): 拓撲頁加「📊 狀態」按鈕 (前端 alert 顯示最新採集 run record, 不用 ssh) + 主 /dependencies 也加「📡 採集」按鈕 (原本只 fullscreen 才有) + 採集 button tooltip 改清楚 (補「需 admin/superadmin」+「1-3 分鐘」說明) + depTriggerCollect 從 fullscreen.html inline 搬到 dependencies.js 共用 + 401/403 錯誤訊息友善化."
d["changelog"] = [note] + d.get("changelog", [])
with open(fp, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print(f"      version: $CURRENT_VER -> $PATCH_VER")
PYEOF

systemctl restart "$SERVICE" && sleep 3
[ -n "$TUNNEL_SVC" ] && systemctl restart "$TUNNEL_SVC" && sleep 2
echo "      $SERVICE=$(systemctl is-active $SERVICE)"
[ -n "$TUNNEL_SVC" ] && echo "      $TUNNEL_SVC=$(systemctl is-active $TUNNEL_SVC)"

# ============ Step 4: smoke test ============
echo ""
echo "[4/4] smoke test"
ALL_OK=true

# 4a. JS 檔可下載
JS_HTTP=$(curl -sS -o /tmp/dep.js -w "%{http_code}" --max-time 5 "http://localhost:5000/static/js/dependencies.js")
JS_BYTES=$(wc -c < /tmp/dep.js)
if [ "$JS_HTTP" = "200" ] && [ "$JS_BYTES" -gt 1000 ]; then
    echo "      /static/js/dependencies.js = 200 ($JS_BYTES bytes) ✓"
else
    echo "      /static/js/dependencies.js = $JS_HTTP ($JS_BYTES bytes) ✗"; ALL_OK=false
fi

# 4b. dependencies + fullscreen 路由
for u in /dependencies /dependencies/fullscreen; do
    H=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:5000$u")
    case "$H" in 200|302) echo "      $u = $H ✓" ;; *) echo "      $u = $H ✗"; ALL_OK=false ;; esac
done

# 4c. 修法關鍵字串存在
if grep -q "depShowCollectStatus" /tmp/dep.js && grep -q "depTriggerCollect" /tmp/dep.js; then
    echo "      depShowCollectStatus + depTriggerCollect 字串存在 ✓"
else
    echo "      新函式不在 dependencies.js ✗"; ALL_OK=false
fi

# 4d. Status API 存活 (登入後才回 200, 沒登入回 401, 都算 API 路由 OK)
S_HTTP=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:5000/api/dependencies/collect/status/latest")
case "$S_HTTP" in 200|401|404) echo "      /api/dependencies/collect/status/latest = $S_HTTP ✓" ;; *) echo "      status API = $S_HTTP ✗"; ALL_OK=false ;; esac

echo ""
if $ALL_OK; then
    echo "✅  v${PATCH_VER} hot-fix 部署完成"
    echo ""
    echo "下一步驗:"
    echo "  1. 瀏覽器硬重整 (Ctrl+Shift+R) /dependencies 或 /dependencies/fullscreen"
    echo "  2. toolbar 應看到新按鈕「📡 採集」 +「📊 狀態」"
    echo "  3. 點「📊 狀態」立刻 alert 顯示最新採集 run record (status/started_at/edges_added)"
    echo "  4. 點「📡 採集」觸發 ansible 背景跑 (1-3 分), 完成後自動 alert + reload"
else
    echo "⚠️  smoke 有紅, 請檢查"
    echo "回滾: cp -r $BACKUP_ROOT/webapp/* $INSPECTION_HOME/webapp/ && systemctl restart $SERVICE"
fi
