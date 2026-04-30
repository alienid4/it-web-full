#!/bin/bash
# v3.17.11.1 hot-fix: 補 mongo_service.py 缺 get_hosts_col helper
#   13 上裝 v3.17.11.0 service 卡 activating, ImportError: cannot import name 'get_hosts_col'
#   根因: 13 mongo_service.py 從來沒升 v3.14.2.0 重構, 之前 hot-fix 都只動拓撲檔
#   順便修本機 mongo_service.py:22 無限遞迴 bug (return get_hosts_col() → return get_collection("hosts"))
# 適用對象: v3.17.11.0 部署失敗的環境 (13/11) + 想升 v3.17.11.0 但還沒升的環境
# 改動範圍: 3 個檔 (mongo_service + dependency_service + api_admin)
set -e

PATCH_VER="3.17.11.1"
HERE="$(cd "$(dirname "$0")" && pwd)"

# auto-detect INSPECTION_HOME
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "[FAIL] 找不到 INSPECTION_HOME"; exit 1; }
echo "[i] INSPECTION_HOME=$INSPECTION_HOME"

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
mkdir -p "$BACKUP_ROOT/webapp/routes" "$BACKUP_ROOT/webapp/services"

# ============ Step 1: 備份 ============
echo "[1/4] 備份"
for f in "webapp/services/mongo_service.py" "webapp/services/dependency_service.py" "webapp/routes/api_admin.py"; do
    src="$INSPECTION_HOME/$f"
    if [ -f "$src" ]; then
        cp "$src" "$BACKUP_ROOT/$f"
        echo "      $f"
    else
        echo "[FAIL] 找不到目標檔: $src"; exit 1
    fi
done

# ============ Step 2: 部署 ============
echo ""
echo "[2/4] 部署 3 個檔"
cp "$HERE/files/webapp/services/mongo_service.py"      "$INSPECTION_HOME/webapp/services/mongo_service.py"
cp "$HERE/files/webapp/services/dependency_service.py" "$INSPECTION_HOME/webapp/services/dependency_service.py"
cp "$HERE/files/webapp/routes/api_admin.py"            "$INSPECTION_HOME/webapp/routes/api_admin.py"
chown sysinfra:itagent "$INSPECTION_HOME/webapp/services/mongo_service.py" "$INSPECTION_HOME/webapp/services/dependency_service.py" "$INSPECTION_HOME/webapp/routes/api_admin.py" 2>/dev/null || true
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
note = "$PATCH_VER - $(date +%Y-%m-%d): hot-fix v3.17.11.0 ImportError get_hosts_col. 修 mongo_service.py:22 無限遞迴 + 補 helper 部署到 13. 3 檔: mongo_service + dependency_service + api_admin."
d["changelog"] = [note] + d.get("changelog", [])
with open(fp, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print(f"      version: $CURRENT_VER -> $PATCH_VER")
PYEOF

systemctl restart "$SERVICE"
[ -n "$TUNNEL_SVC" ] && systemctl restart "$TUNNEL_SVC"

# retry 5 次每次 sleep 2, 任一成功就過 (避開 sleep 3 太緊假象)
HTTP_OK=false
for i in 1 2 3 4 5; do
    sleep 2
    H=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:5000/login" 2>/dev/null)
    case "$H" in 200|302)
        echo "      $SERVICE 起來了 (try $i): HTTP $H"
        HTTP_OK=true
        break ;;
    esac
done
if ! $HTTP_OK; then
    echo "      [FAIL] $SERVICE 5 次重試 HTTP 都不通"
    echo "      systemctl status: $(systemctl is-active $SERVICE)"
    echo "      看 traceback: sudo journalctl -u $SERVICE --since '1 min ago' --no-pager | tail -30"
fi
[ -n "$TUNNEL_SVC" ] && echo "      $TUNNEL_SVC=$(systemctl is-active $TUNNEL_SVC)"

# ============ Step 4: smoke test ============
echo ""
echo "[4/4] smoke test"
ALL_OK=true
$HTTP_OK || ALL_OK=false

# 4a. AST
sudo -u sysinfra python3 -c "
import ast
for f in ['$INSPECTION_HOME/webapp/services/mongo_service.py',
         '$INSPECTION_HOME/webapp/services/dependency_service.py',
         '$INSPECTION_HOME/webapp/routes/api_admin.py']:
    ast.parse(open(f, encoding='utf-8').read())
" 2>/dev/null && echo "      AST 語法 OK ✓" || { echo "      AST 失敗 ✗"; ALL_OK=false; }

# 4b. get_hosts_col 不再無限遞迴
if grep -q 'return get_collection("hosts")' "$INSPECTION_HOME/webapp/services/mongo_service.py" \
   && ! grep -q 'def get_hosts_col.*return get_hosts_col' "$INSPECTION_HOME/webapp/services/mongo_service.py"; then
    echo "      mongo_service.py:get_hosts_col 修正 ✓"
else
    echo "      mongo_service.py:get_hosts_col 未修正 ✗"; ALL_OK=false
fi

# 4c. helper 還在
grep -q "def sync_systems_from_hosts" "$INSPECTION_HOME/webapp/services/dependency_service.py" \
    && echo "      sync_systems_from_hosts helper 存在 ✓" \
    || { echo "      helper 缺 ✗"; ALL_OK=false; }

# 4d. import 鏈活著 (Python 真 import 一次)
sudo -u sysinfra python3 -c "
import sys
sys.path.insert(0, '$INSPECTION_HOME/webapp')
from services.mongo_service import get_hosts_col, get_collection, get_all_settings, update_setting
from services.dependency_service import sync_systems_from_hosts
print('      import 鏈 OK ✓')
" 2>/dev/null || { echo "      import 鏈 fail ✗"; ALL_OK=false; }

echo ""
if $ALL_OK; then
    echo "✅  v${PATCH_VER} hot-fix 部署完成"
    echo ""
    echo "下一步 (接 v3.17.11.0 SOP Step 2):"
    echo "  1. /superadmin → 模組管理 → 開 dependencies"
    echo "  2. /admin → 主機管理 → 下載新範本 (應有「業務系統」欄)"
    echo "  3. 4 台都填「巡檢系統」→ 重 import"
    echo "  4. /dependencies 看拓撲節點長出來"
    echo "  5. 點「📡 採集」+「📊 狀態」看 edges_added > 0"
else
    echo "⚠️  smoke 還有紅"
    echo "回滾: sudo cp -r $BACKUP_ROOT/webapp/* $INSPECTION_HOME/webapp/ && sudo systemctl restart $SERVICE"
fi
