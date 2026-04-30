#!/bin/bash
# v3.17.11.0: hosts CSV import 加「業務系統」欄, 自動同步 dependency_systems
#   修「dep_sys=0 → 拓撲畫不出」根因 — 使用者在 CSV 多填一欄, 拓撲節點自己長出來
# 適用對象: 任何 v3.14.0.0+ 環境 (家裡/公司通用)
# 改動範圍: 2 個檔 (services/dependency_service.py + routes/api_admin.py)
set -e

PATCH_VER="3.17.11.0"
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
for f in "webapp/services/dependency_service.py" "webapp/routes/api_admin.py"; do
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
echo "[2/4] 部署 2 個檔"
cp "$HERE/files/webapp/services/dependency_service.py" "$INSPECTION_HOME/webapp/services/dependency_service.py"
cp "$HERE/files/webapp/routes/api_admin.py"            "$INSPECTION_HOME/webapp/routes/api_admin.py"
chown sysinfra:itagent "$INSPECTION_HOME/webapp/services/dependency_service.py" "$INSPECTION_HOME/webapp/routes/api_admin.py" 2>/dev/null || true
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
note = "$PATCH_VER - $(date +%Y-%m-%d): hosts CSV import 加『業務系統』欄, 自動同步 dependency_systems. 對映: 業務系統=資產表的資產名稱 (自動避險/SPEEDY 等中文當 system_id PK), APID/群組/基礎架構→metadata. 新增 sync_systems_from_hosts() helper (build/update/move 邏輯), 改 import_csv/export_csv/template_csv/template_xlsx 加欄. 修『dep_sys=0 拓撲畫不出』根因."
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

# 4a. AST 語法 (memory: 部署後 4 項全綠)
sudo -u sysinfra python3 -c "import ast; ast.parse(open('$INSPECTION_HOME/webapp/services/dependency_service.py', encoding='utf-8').read()); ast.parse(open('$INSPECTION_HOME/webapp/routes/api_admin.py', encoding='utf-8').read())" 2>/dev/null \
    && echo "      AST 語法 OK ✓" \
    || { echo "      AST 語法檢查失敗 ✗"; ALL_OK=false; }

# 4b. helper 真有寫進去
if grep -q "def sync_systems_from_hosts" "$INSPECTION_HOME/webapp/services/dependency_service.py"; then
    echo "      sync_systems_from_hosts helper 存在 ✓"
else
    echo "      sync_systems_from_hosts helper 缺 ✗"; ALL_OK=false
fi

# 4c. import_csv 有解析業務系統欄
if grep -q '業務系統' "$INSPECTION_HOME/webapp/routes/api_admin.py"; then
    echo "      api_admin.py 有業務系統欄解析 ✓"
else
    echo "      api_admin.py 缺業務系統欄解析 ✗"; ALL_OK=false
fi

# 4d. service 活著
H=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:5000/admin")
case "$H" in 200|302) echo "      /admin = $H ✓" ;; *) echo "      /admin = $H ✗"; ALL_OK=false ;; esac

# 4e. log 沒新 ERROR
sleep 2
LATEST_LOG=$(sudo ls -t "$INSPECTION_HOME/logs/"*.log 2>/dev/null | grep -v dep_collect | grep -v vcenter_collector | head -1)
if [ -n "$LATEST_LOG" ]; then
    NEW_ERR=$(sudo tail -50 "$LATEST_LOG" 2>/dev/null | grep -iE 'error|traceback|exception' | grep -v "ERROR \[內湖VC" | head -3)
    if [ -z "$NEW_ERR" ]; then
        echo "      log 末 50 行無新 error ✓"
    else
        echo "      log 有 error: ✗"; echo "$NEW_ERR" | sed 's/^/        /'; ALL_OK=false
    fi
fi

echo ""
if $ALL_OK; then
    echo "✅  v${PATCH_VER} 部署完成"
    echo ""
    echo "下一步:"
    echo "  1. 下載新範本: /admin → 主機管理 → 下載 CSV/XLSX 範本 (應有「業務系統」欄)"
    echo "  2. 把 4 台 (011T/013T/014T/015T) 在「業務系統」欄填上歸屬名稱"
    echo "     (例如全填「巡檢系統」, 或按業務分: 011T/013T 填「業務 A」, 014T/015T 填「業務 B」)"
    echo "  3. 重 import CSV → admin 介面會顯示「同步業務系統 +N/~M/移動 K」"
    echo "  4. 進 /dependencies 看拓撲應該有節點 (顯示業務系統名)"
    echo "  5. 點「📡 採集」重採一次, 看 edges_added > 0"
    echo "  6. 跑 debug_topology.sh 確認 10. host_refs 反查 全綠"
else
    echo "⚠️  smoke 有紅"
    echo "回滾: cp -r $BACKUP_ROOT/* $INSPECTION_HOME/ && systemctl restart $SERVICE"
fi
