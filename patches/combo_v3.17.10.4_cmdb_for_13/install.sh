#!/bin/bash
# v3.17.10.4 hot-fix: 採集 default --limit 寫死 secansible:secclient1:sec9c2 → 改 all
#   13 環境 inventory 沒這 3 個 hostname → ansible "no hosts to target" → 採集失敗
#   改成 default 採 inventory 全部 host (playbook 內已 skip 非 Linux)
# 適用對象: 任何 v3.14.0.0+ 環境 (家裡/公司通用)
# 改動範圍: 2 個檔
set -e

PATCH_VER="3.17.10.4"
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
mkdir -p "$BACKUP_ROOT/webapp/routes" "$BACKUP_ROOT/scripts"

# ============ Step 1: 備份 ============
echo "[1/4] 備份"
for f in "webapp/routes/api_dependencies.py" "scripts/run_dep_collect.sh"; do
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
cp "$HERE/files/webapp/routes/api_dependencies.py" "$INSPECTION_HOME/webapp/routes/api_dependencies.py"
cp "$HERE/files/scripts/run_dep_collect.sh"        "$INSPECTION_HOME/scripts/run_dep_collect.sh"
chmod +x "$INSPECTION_HOME/scripts/run_dep_collect.sh"
chown sysinfra:itagent "$INSPECTION_HOME/webapp/routes/api_dependencies.py" "$INSPECTION_HOME/scripts/run_dep_collect.sh" 2>/dev/null || true
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
note = "$PATCH_VER - $(date +%Y-%m-%d): 採集 default --limit 從寫死 secansible:secclient1:sec9c2 改成 all (跨環境通用. 13 inventory 沒這 3 個 hostname → 之前 ansible 'no hosts to target' 採集失敗). 改 api_dependencies.py:243 + run_dep_collect.sh:35 兩處."
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

# 4a. 語法字串確認 (不再有寫死的 hostname)
if grep -q "limit all" "$INSPECTION_HOME/webapp/routes/api_dependencies.py" && \
   ! grep -q "secansible:secclient1:sec9c2" "$INSPECTION_HOME/webapp/routes/api_dependencies.py"; then
    echo "      api_dependencies.py: default --limit all (寫死 hostname 已清掉) ✓"
else
    echo "      api_dependencies.py: 修法字串檢查失敗 ✗"; ALL_OK=false
fi

if grep -q 'DEP_COLLECT_LIMIT:-all' "$INSPECTION_HOME/scripts/run_dep_collect.sh"; then
    echo "      run_dep_collect.sh: DEP_COLLECT_LIMIT default all ✓"
else
    echo "      run_dep_collect.sh: 修法字串檢查失敗 ✗"; ALL_OK=false
fi

# 4b. inventory 連通性: 看 ansible 列得出 hosts
INV="$INSPECTION_HOME/ansible/inventory/hosts.yml"
if [ -f "$INV" ]; then
    HOST_COUNT=$(sudo -u sysinfra ansible -i "$INV" all --list-hosts 2>/dev/null | grep -c "^    " || echo "0")
    if [ "$HOST_COUNT" -gt 0 ]; then
        echo "      ansible -i $INV all --list-hosts: $HOST_COUNT 台 ✓"
    else
        echo "      ansible inventory 列不出 hosts (檢查 $INV) ⚠"
    fi
fi

# 4c. service 活著
H=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:5000/dependencies")
case "$H" in 200|302) echo "      /dependencies = $H ✓" ;; *) echo "      /dependencies = $H ✗"; ALL_OK=false ;; esac

echo ""
if $ALL_OK; then
    echo "✅  v${PATCH_VER} hot-fix 部署完成"
    echo ""
    echo "下一步:"
    echo "  1. 硬重整 (Ctrl+Shift+R) /dependencies"
    echo "  2. 點「📡 採集」(這次 default --limit 改 all, 應該會抓到真實 host)"
    echo "  3. 1-3 分後點「📊 狀態」看結果"
    echo "  4. 仍 fail 的話, error 應該變更具體 (unreachable / Permission denied 等), 對照 notes"
else
    echo "⚠️  smoke 有紅"
    echo "回滾: cp -r $BACKUP_ROOT/* $INSPECTION_HOME/ && systemctl restart $SERVICE"
fi
