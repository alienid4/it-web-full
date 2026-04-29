#!/bin/bash
# v3.17.10.2 hot-fix: 拓撲 0 edges 時 nodes 重疊看不到 (hierarchical+sortMethod=directed bug)
# 適用對象: 任何 v3.14.0.0+ (有 dependencies 模組) 的環境
# 改動範圍: 只動 webapp/static/js/dependencies.js 一個檔
set -e

PATCH_VER="3.17.10.2"
HERE="$(cd "$(dirname "$0")" && pwd)"

# auto-detect INSPECTION_HOME
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "[FAIL] 找不到 INSPECTION_HOME (試過 /opt/inspection /seclog/AI/inspection)"; exit 1; }
echo "[i] INSPECTION_HOME=$INSPECTION_HOME"

# detect service name
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
mkdir -p "$BACKUP_ROOT/webapp/static/js"

# ============ Step 1: 備份 ============
echo "[1/4] 備份 dependencies.js"
TARGET="$INSPECTION_HOME/webapp/static/js/dependencies.js"
if [ -f "$TARGET" ]; then
    cp "$TARGET" "$BACKUP_ROOT/webapp/static/js/dependencies.js"
    echo "      $TARGET → $BACKUP_ROOT/webapp/static/js/dependencies.js"
else
    echo "[FAIL] 找不到目標檔: $TARGET"; exit 1
fi

# ============ Step 2: 部署 ============
echo ""
echo "[2/4] 部署新版 dependencies.js"
cp "$HERE/files/webapp/static/js/dependencies.js" "$TARGET"
chown sysinfra:itagent "$TARGET" 2>/dev/null || true
NEW_BYTES=$(wc -c < "$TARGET")
echo "      $TARGET ($NEW_BYTES bytes)"

# ============ Step 3: bump version + 重啟 ============
echo ""
echo "[3/4] bump version + 重啟 service"
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp, encoding="utf-8") as f:
    d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
note = "$PATCH_VER - $(date +%Y-%m-%d): hot-fix 拓撲 0 edges 重疊 bug — hierarchical+sortMethod=directed 在沒邊時把 nodes 全擠 level 0 重疊看不到. 改成 0 edges 自動切 free layout + repulsion physics 散開, 並加「⚠️ 還沒採集任何邊資料 [前往採集 →]」UI hint."
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

# 4a. JS 檔可下載 + size 合理
JS_HTTP=$(curl -sS -o /tmp/dep.js -w "%{http_code}" --max-time 5 "http://localhost:5000/static/js/dependencies.js")
JS_BYTES=$(wc -c < /tmp/dep.js)
if [ "$JS_HTTP" = "200" ] && [ "$JS_BYTES" -gt 1000 ]; then
    echo "      /static/js/dependencies.js = 200 ($JS_BYTES bytes) ✓"
else
    echo "      /static/js/dependencies.js = $JS_HTTP ($JS_BYTES bytes) ✗"; ALL_OK=false
fi

# 4b. dependencies 頁路由可達
DEP_HTTP=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:5000/dependencies")
case "$DEP_HTTP" in 200|302) echo "      /dependencies = $DEP_HTTP ✓" ;; *) echo "      /dependencies = $DEP_HTTP ✗"; ALL_OK=false ;; esac

# 4c. JS 開頭乾淨 (memory: 之前 SSH 拉檔污染 stderr 有過案例)
JS_HEAD=$(head -c 50 /tmp/dep.js | tr -d '\n')
if echo "$JS_HEAD" | grep -q "^/\*\*"; then
    echo "      JS 開頭乾淨 ($JS_HEAD...) ✓"
else
    echo "      JS 開頭異常: $JS_HEAD ✗"; ALL_OK=false
fi

# 4d. 修法字串確實存在 (避免 cp 失敗或舊檔)
if grep -q "hasEdges" /tmp/dep.js && grep -q "stabilizationIterationsDone" /tmp/dep.js; then
    echo "      hasEdges + stabilizationIterationsDone 字串存在 ✓"
else
    echo "      修法關鍵字串不在新版 dependencies.js ✗"; ALL_OK=false
fi

# 4e. log 無新 ERROR
sleep 2
LOG="$INSPECTION_HOME/logs/app.log"
if [ -f "$LOG" ]; then
    NEW_ERR=$(tail -n 50 "$LOG" | grep -c "ERROR" || true)
    [ "$NEW_ERR" -eq 0 ] && echo "      log 末 50 行無 ERROR ✓" || echo "      log 末 50 行 $NEW_ERR 條 ERROR (請看 $LOG)"
fi

echo ""
if $ALL_OK; then
    echo "✅  v${PATCH_VER} hot-fix 部署完成"
    echo ""
    echo "下一步驗證:"
    echo "  1. 瀏覽器硬重整 (Ctrl+Shift+R) http://<本機 IP>:5000/dependencies"
    echo "  2. DevTools Console 應看到 [dep] vis.Network init + [dep] stabilization done"
    echo "  3. 畫面應看到 4 個淡綠 dot 散開 (不再疊成空白)"
    echo "  4. 上方應顯示「⚠️ 還沒採集任何邊資料 [前往採集 →]」"
    echo "  5. 點「前往採集 →」跳到 /admin#dependencies 可手動觸發採集"
else
    echo "⚠️  smoke 有紅, 請檢查上面輸出"
    echo "回滾: cp $BACKUP_ROOT/webapp/static/js/dependencies.js $TARGET && systemctl restart $SERVICE"
fi
