#!/bin/bash
# v3.17.0.0 hosts 加 ips array + aliases array (Phase 1: CMDB 整合 進巡檢系統)
set -e
PATCH_VER="3.17.0.0"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSPECTION_HOME=""
for p in /seclog/AI/inspection /opt/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "FAIL"; exit 1; }
echo "[i] INSPECTION_HOME=$INSPECTION_HOME"
TS=$(date +%Y%m%d_%H%M%S)

echo ""
echo "[1/5] 備份"
cp "$INSPECTION_HOME/webapp/templates/host_edit.html" \
   "$INSPECTION_HOME/webapp/templates/host_edit.html.bak.${TS}"
cp "$INSPECTION_HOME/webapp/services/dependency_service.py" \
   "$INSPECTION_HOME/webapp/services/dependency_service.py.bak.${TS}"
podman exec mongodb mongoexport --db inspection --collection hosts --out /tmp/hosts.json 2>&1 | tail -1
mkdir -p /var/backups/inspection
podman cp mongodb:/tmp/hosts.json "/var/backups/inspection/hosts_pre_v${PATCH_VER}_${TS}.json"

echo ""
echo "[2/5] DB migration: 既有 host ip → ips=[ip]; aliases=[]"
podman exec -i mongodb mongosh inspection --quiet <<'JSEOF'
let upd = 0;
db.hosts.find({}).forEach(h => {
  const set = {};
  if (!Array.isArray(h.ips)) {
    set.ips = h.ip ? [h.ip] : [];
  }
  if (!Array.isArray(h.aliases)) {
    set.aliases = [];
  }
  if (Object.keys(set).length > 0) {
    db.hosts.updateOne({_id: h._id}, {$set: set});
    upd++;
  }
});
print("[migration] 加 ips/aliases 到 " + upd + " 台 host");
JSEOF

echo ""
echo "[3/5] 部署檔案"
cp "$HERE/files/webapp/templates/host_edit.html" \
   "$INSPECTION_HOME/webapp/templates/host_edit.html"
cp "$HERE/files/webapp/services/dependency_service.py" \
   "$INSPECTION_HOME/webapp/services/dependency_service.py"
chown -R sysinfra:itagent "$INSPECTION_HOME/webapp" 2>/dev/null || true

echo ""
echo "[4/5] bump version + 重啟"
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): hosts 加 ips array (多 IP) + aliases array (歷史名稱) — CMDB 整合 Phase 1. (1) DB migration 既有 ip→ips=[ip], aliases=[] (2) 主機編輯頁加『主 IP / 其他 IP / 主機別名』3 個欄位, 每行一個 (3) heSave/heLoad 處理 array <-> textarea 轉換 (4) 拓撲圖節點 IP 優先讀 ips[0], fallback h.ip"] + d["changelog"]
with open(fp,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2)
PYEOF
systemctl restart itagent-web && sleep 2 && systemctl restart itagent-tunnel
echo "      web=$(systemctl is-active itagent-web) tunnel=$(systemctl is-active itagent-tunnel)"

echo ""
echo "[5/5] smoke test (HTTP + contract)"
ALL_OK=true
for u in /login /static/js/dependencies.js; do
    H=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:5000$u")
    echo "  $u = $H (預期 200)"
    [ "$H" = "200" ] || ALL_OK=false
done
ERR=$(tail -50 "$INSPECTION_HOME/logs/app.log" 2>/dev/null | grep -ciE "error|traceback|exception")
echo "  log err: $ERR (預期 0)"
[ "$ERR" = "0" ] || ALL_OK=false

# Contract: hosts 必有 ips array, aliases array
sudo -u sysinfra python3 <<PYEOF
import sys
sys.path.insert(0, "$INSPECTION_HOME/webapp")
from services.mongo_service import get_hosts_col
hosts = list(get_hosts_col().find({}))
fail = []
for h in hosts:
    if not isinstance(h.get("ips"), list):
        fail.append(f"{h.get('hostname')}: ips not list")
    if not isinstance(h.get("aliases"), list):
        fail.append(f"{h.get('hostname')}: aliases not list")
if fail:
    print("  contract FAIL:", fail)
    sys.exit(1)
print(f"  contract: {len(hosts)} hosts 都有 ips + aliases array ✓")

# Topology contract
from services.dependency_service import _topology_from_hosts
r = _topology_from_hosts()
nodes = r["nodes"]; edges = r["edges"]
assert len(nodes) > 0, "空 nodes"
assert all("system_id" in n for n in nodes), "node 缺 system_id"
assert all("from" in e and "to" in e for e in edges), "edge 缺 from/to"
ids = [e["id"] for e in edges]
assert all(ids), "edge id 不能空"
assert len(set(ids)) == len(ids), "edge id 重複"
print(f"  topology contract: {len(nodes)} nodes, {len(edges)} edges ✓")
PYEOF
[ "$?" = "0" ] || ALL_OK=false

if $ALL_OK; then
    echo ""
    echo "✅ v${PATCH_VER} smoke 全綠"
else
    echo ""
    echo "⚠️ smoke 有紅, 請查上面"
fi
echo ""
echo "回滾:"
echo "  cp $INSPECTION_HOME/webapp/templates/host_edit.html.bak.${TS} $INSPECTION_HOME/webapp/templates/host_edit.html"
echo "  cp $INSPECTION_HOME/webapp/services/dependency_service.py.bak.${TS} $INSPECTION_HOME/webapp/services/dependency_service.py"
echo "  podman exec -i mongodb mongoimport --db inspection --collection hosts --drop < /var/backups/inspection/hosts_pre_v${PATCH_VER}_${TS}.json"
echo "  systemctl restart itagent-web itagent-tunnel"
