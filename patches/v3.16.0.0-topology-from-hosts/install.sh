#!/bin/bash
# v3.16.0.0 拓撲圖從 hosts 派生 (移除 dependency_systems 內部 system 維護需求)
set -e
PATCH_VER="3.16.0.0"
HERE="$(cd "$(dirname "$0")" && pwd)"

INSPECTION_HOME=""
for p in /seclog/AI/inspection /opt/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "FAIL"; exit 1; }
echo "[i] INSPECTION_HOME=$INSPECTION_HOME"

TS=$(date +%Y%m%d_%H%M%S)

# Step 1/5: 備份
echo ""
echo "[1/5] 備份"
cp "$INSPECTION_HOME/webapp/services/dependency_service.py" \
   "$INSPECTION_HOME/webapp/services/dependency_service.py.bak.${TS}"
podman exec mongodb mongoexport --db inspection --collection dependency_relations --out /tmp/relations_backup.json 2>&1 | tail -1
podman cp mongodb:/tmp/relations_backup.json "/var/backups/inspection/relations_pre_v${PATCH_VER}_${TS}.json"
echo "      service .bak / relations.json 備份完"

# Step 2/5: 邊資料 migration (system_id -> hostname)
echo ""
echo "[2/5] 邊 source/target 轉換 INSPECTION-WEB->secansible 等"
podman exec -i mongodb mongosh inspection --quiet <<'JSEOF'
const MAP = {
  "INSPECTION-WEB": "secansible",
  "INSPECTION-DB": "secansible",
  "LINUX-RHEL": "secclient1",
  "LINUX-DEBIAN": "sec9c2",
  "WIN-SVR": "WIN-7L4JNM4P2KN"
};
let updated = 0, deleted_self = 0, deleted_dup = 0;
db.dependency_relations.find({}).forEach(r => {
  const newFrom = MAP[r.from_system] || r.from_system;
  const newTo = MAP[r.to_system] || r.to_system;
  if (newFrom === newTo) {
    db.dependency_relations.deleteOne({_id: r._id});
    deleted_self++;
    return;
  }
  if (newFrom !== r.from_system || newTo !== r.to_system) {
    const dup = db.dependency_relations.findOne({
      from_system: newFrom, to_system: newTo, port: r.port, _id: {$ne: r._id}
    });
    if (dup) {
      db.dependency_relations.deleteOne({_id: r._id});
      deleted_dup++;
    } else {
      db.dependency_relations.updateOne({_id: r._id}, {$set: {from_system: newFrom, to_system: newTo}});
      updated++;
    }
  }
});
print("[migration] updated=" + updated + " self_loop_deleted=" + deleted_self + " dup_deleted=" + deleted_dup);
JSEOF

# Step 3/5: 部署新 dependency_service.py
echo ""
echo "[3/5] 部署 dependency_service.py"
cp "$HERE/files/webapp/services/dependency_service.py" \
   "$INSPECTION_HOME/webapp/services/dependency_service.py"
chown sysinfra:itagent "$INSPECTION_HOME/webapp/services/dependency_service.py" 2>/dev/null || true

# Step 4/5: bump version + restart
echo ""
echo "[4/5] bump version + 重啟"
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp, encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): 拓撲圖從 hosts collection 派生 — 主機清單變唯一資料來源。每台 host = 一個拓撲節點 (system_id=hostname). 內部 system (INSPECTION-WEB/LINUX-RHEL 等) 不再從 dependency_systems 取, 直接從 hosts.system_name+apid 動態算. 外部節點 (AD/DNS/EXT/UNKNOWN) 仍留 dependency_systems. 邊資料 migration: INSPECTION-WEB->secansible, LINUX-RHEL->secclient1, LINUX-DEBIAN->sec9c2, WIN-SVR->WIN-7L4JNM4P2KN. 自我 loop 邊刪除. 重複邊去重."] + d["changelog"]
with open(fp, "w", encoding="utf-8") as f: json.dump(d, f, ensure_ascii=False, indent=2)
PYEOF
systemctl restart itagent-web && sleep 2 && systemctl restart itagent-tunnel
echo "      web=$(systemctl is-active itagent-web) tunnel=$(systemctl is-active itagent-tunnel)"

# Step 5/5: SMOKE TEST (per feedback_must_smoke_after_deploy 規則)
echo ""
echo "[5/5] smoke test"
ALL_OK=true
HTTP_LOGIN=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 http://localhost:5000/login)
HTTP_DEP=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 http://localhost:5000/dependencies)
echo "      curl /login = $HTTP_LOGIN (預期 200)"
echo "      curl /dependencies = $HTTP_DEP (預期 302 = 未登入導向)"
[ "$HTTP_LOGIN" = "200" ] || ALL_OK=false
case "$HTTP_DEP" in 200|302) ;; *) ALL_OK=false ;; esac

# topology API 直接 query (不用 auth, 但要 admin_required 可能 401)
HTTP_API=$(curl -sS -o /tmp/topo.json -w '%{http_code}' --max-time 10 http://localhost:5000/api/dependencies/topology)
echo "      curl /api/dependencies/topology = $HTTP_API"

# log 看 ERROR
ERR_COUNT=$(tail -50 "$INSPECTION_HOME/logs/app.log" 2>/dev/null | grep -ciE "error|traceback|exception" || echo 0)
echo "      log 近 50 行 ERROR/Traceback: $ERR_COUNT"
[ "$ERR_COUNT" = "0" ] || ALL_OK=false

# Python import 測試
podman exec mongodb mongosh inspection --quiet --eval "
const c = db.dependency_relations.countDocuments();
const internal_targets = db.dependency_relations.find({to_system: {\$in: ['secansible','secclient1','sec9c2','WIN-7L4JNM4P2KN']}}).count();
print('[mongo] relations total: ' + c);
print('[mongo] internal hostname-target edges: ' + internal_targets + ' (應 > 0)');
" 2>&1 | tail -3

if $ALL_OK; then
  echo ""
  echo "✅ v${PATCH_VER} smoke test 全綠"
else
  echo ""
  echo "⚠️ smoke test 部分紅, 請查上面輸出"
fi
echo ""
echo "回滾:"
echo "  cp $INSPECTION_HOME/webapp/services/dependency_service.py.bak.${TS} $INSPECTION_HOME/webapp/services/dependency_service.py"
echo "  podman exec -i mongodb mongoimport --db inspection --collection dependency_relations --drop < /var/backups/inspection/relations_pre_v${PATCH_VER}_${TS}.json"
echo "  systemctl restart itagent-web itagent-tunnel"
