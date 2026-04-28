#!/bin/bash
# v3.17.7.0 CMDB 整合 combo (P1-P6 全部一次包)
# 適用對象: 公司 13 / 任何 v3.11.x ~ v3.16.x 的環境
# 行為: snapshot 替換檔案 + DB migration + 智能 idempotent
set -e

PATCH_VER="3.17.7.0"
HERE="$(cd "$(dirname "$0")" && pwd)"

# auto-detect INSPECTION_HOME (公司 13 通常 /opt/inspection, 家裡 221 是 /seclog/AI/inspection)
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "[FAIL] 找不到 INSPECTION_HOME"; exit 1; }
echo "[i] INSPECTION_HOME=$INSPECTION_HOME"

# 偵測 mongo 執行方式 (公司 13/11 沒 podman, 走系統 mongosh; 家裡 221 走 podman)
MONGOSH=""
MONGOEXPORT=""
MONGOIMPORT=""
if command -v mongosh >/dev/null 2>&1; then
    MONGOSH="mongosh inspection --quiet"
    MONGOEXPORT="mongoexport --db inspection"
    MONGOIMPORT="mongoimport --db inspection"
    echo "[i] MONGO 走系統 mongosh"
elif command -v mongo >/dev/null 2>&1; then
    MONGOSH="mongo inspection --quiet"
    MONGOEXPORT="mongoexport --db inspection"
    MONGOIMPORT="mongoimport --db inspection"
    echo "[i] MONGO 走系統 mongo (legacy)"
elif command -v podman >/dev/null 2>&1 && podman ps 2>/dev/null | grep -q mongodb; then
    MONGOSH="podman exec -i mongodb mongosh inspection --quiet"
    MONGOEXPORT="podman exec mongodb mongoexport --db inspection"
    MONGOIMPORT="podman exec -i mongodb mongoimport --db inspection"
    echo "[i] MONGO 走 podman container"
elif command -v docker >/dev/null 2>&1 && docker ps 2>/dev/null | grep -q mongodb; then
    MONGOSH="docker exec -i mongodb mongosh inspection --quiet"
    MONGOEXPORT="docker exec mongodb mongoexport --db inspection"
    MONGOIMPORT="docker exec -i mongodb mongoimport --db inspection"
    echo "[i] MONGO 走 docker container"
fi
[ -z "$MONGOSH" ] && { echo "[FAIL] 找不到 mongosh/mongo/podman/docker — 至少要有一種"; exit 1; }

# 偵測 service name
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
echo "[i] 13 目前版本: $CURRENT_VER → 將升級到: $PATCH_VER"
echo ""

TS=$(date +%Y%m%d_%H%M%S)
BACKUP_ROOT="/var/backups/inspection/v${PATCH_VER}_${TS}"
mkdir -p "$BACKUP_ROOT"

# ============ Step 1: 備份 ============
echo "[1/6] 備份既有檔案 + DB"
declare -a FILES=(
    "webapp/app.py"
    "webapp/routes/api_admin.py"
    "webapp/templates/base.html"
    "webapp/templates/admin.html"
    "webapp/static/js/admin.js"
)
for f in "${FILES[@]}"; do
    src="$INSPECTION_HOME/$f"
    if [ -f "$src" ]; then
        mkdir -p "$BACKUP_ROOT/$(dirname $f)"
        cp "$src" "$BACKUP_ROOT/$f"
    fi
done
# 備份 hosts collection (跨環境相容: podman 要從 container 拷, 系統直接寫到本機)
if [[ "$MONGOEXPORT" == podman* ]] || [[ "$MONGOEXPORT" == docker* ]]; then
    $MONGOEXPORT --collection hosts --out /tmp/hosts.json 2>&1 | tail -1
    DRT="${MONGOEXPORT%% *}"  # podman or docker
    $DRT cp mongodb:/tmp/hosts.json "$BACKUP_ROOT/hosts.json" 2>/dev/null || true
else
    $MONGOEXPORT --collection hosts --out "$BACKUP_ROOT/hosts.json" 2>&1 | tail -1
fi
echo "      備份在 $BACKUP_ROOT"

# ============ Step 2: 部署新檔案 ============
echo ""
echo "[2/6] 部署 28 個檔案 (22 主 + 6 拓撲: api_dependencies / 3 templates / dependencies.js / example.css / feature_flags)"
# templates (11 個 = 8 hosts + 3 dependencies)
for f in admin.html base.html host_edit.html host_history.html host_duplicates.html subnets.html recon.html orphans.html dependencies.html dependencies_fullscreen.html dependencies_ghosts.html; do
    cp "$HERE/files/webapp/templates/$f" "$INSPECTION_HOME/webapp/templates/$f"
done
# services (7 個 = 6 新 + feature_flags 更新)
for f in dependency_service.py change_log.py host_dedup.py subnet_service.py recon_service.py orphan_service.py feature_flags.py; do
    cp "$HERE/files/webapp/services/$f" "$INSPECTION_HOME/webapp/services/$f"
done
# routes (2 個)
cp "$HERE/files/webapp/routes/api_admin.py"        "$INSPECTION_HOME/webapp/routes/api_admin.py"
cp "$HERE/files/webapp/routes/api_dependencies.py" "$INSPECTION_HOME/webapp/routes/api_dependencies.py"
# app.py
cp "$HERE/files/webapp/app.py" "$INSPECTION_HOME/webapp/app.py"
# static (js + css)
cp "$HERE/files/webapp/static/js/admin.js"        "$INSPECTION_HOME/webapp/static/js/admin.js"
cp "$HERE/files/webapp/static/js/dependencies.js" "$INSPECTION_HOME/webapp/static/js/dependencies.js"
cp "$HERE/files/webapp/static/css/example.css"    "$INSPECTION_HOME/webapp/static/css/example.css"
# v3.17.7.2+: 拓撲採集 (ansible playbook/role + scripts)
mkdir -p "$INSPECTION_HOME/ansible/playbooks" "$INSPECTION_HOME/ansible/roles/collect_connections/tasks"
cp "$HERE/files/ansible/playbooks/collect_connections.yml" "$INSPECTION_HOME/ansible/playbooks/"
cp "$HERE/files/ansible/roles/collect_connections/tasks/main.yml"  "$INSPECTION_HOME/ansible/roles/collect_connections/tasks/"
cp "$HERE/files/ansible/roles/collect_connections/tasks/linux.yml" "$INSPECTION_HOME/ansible/roles/collect_connections/tasks/"
cp "$HERE/files/scripts/dependency_seed_collect.py" "$INSPECTION_HOME/scripts/"
cp "$HERE/files/scripts/run_dep_collect.sh"         "$INSPECTION_HOME/scripts/"
chmod +x "$INSPECTION_HOME/scripts/dependency_seed_collect.py" "$INSPECTION_HOME/scripts/run_dep_collect.sh"
chown -R sysinfra:itagent "$INSPECTION_HOME/webapp" 2>/dev/null || true
echo "      OK"

# ============ Step 3: DB migrations (idempotent) ============
echo ""
echo "[3/6] DB migrations (全 idempotent, 重跑安全)"
$MONGOSH <<'JSEOF'
let r = 0;

// Migration A: hosts 加 5 新欄位 + ips array + aliases array (P1)
db.hosts.find({}).forEach(h => {
  const set = {};
  ["device_model", "rack_no", "hardware_seq", "sys_admin"].forEach(k => {
    if (h[k] === undefined) set[k] = "";
  });
  if (h.quantity === undefined) set.quantity = 1;
  if (!Array.isArray(h.ips)) set.ips = h.ip ? [h.ip] : [];
  if (!Array.isArray(h.aliases)) set.aliases = [];
  if (Object.keys(set).length > 0) {
    db.hosts.updateOne({_id: h._id}, {$set: set});
    r++;
  }
});
print("[A] hosts 加 ips/aliases/5新欄位: " + r + " 台補上");

// Migration B: dependency_relations source/target 從 system_id 轉 hostname (相容性)
const MAP = {"INSPECTION-WEB":"secansible","INSPECTION-DB":"secansible","LINUX-RHEL":"secclient1","LINUX-DEBIAN":"sec9c2","WIN-SVR":"WIN-7L4JNM4P2KN"};
let u = 0, ds = 0, dd = 0;
const all = db.dependency_relations.find({}).toArray();
all.forEach(rel => {
  const nf = MAP[rel.from_system] || rel.from_system;
  const nt = MAP[rel.to_system]   || rel.to_system;
  if (nf === nt) { db.dependency_relations.deleteOne({_id: rel._id}); ds++; return; }
  if (nf !== rel.from_system || nt !== rel.to_system) {
    const dup = db.dependency_relations.findOne({from_system:nf, to_system:nt, port:rel.port, _id:{$ne:rel._id}});
    if (dup) { db.dependency_relations.deleteOne({_id: rel._id}); dd++; }
    else { db.dependency_relations.updateOne({_id:rel._id}, {$set:{from_system:nf, to_system:nt}}); u++; }
  }
});
print("[B] dependency_relations 轉 hostname: 更新=" + u + " 自我loop=" + ds + " 重複刪=" + dd);

// Migration C: 建 collection indexes (idempotent)
db.change_log.createIndex({hostname: 1, when: -1});
db.change_log.createIndex({when: -1});
db.subnets.createIndex({cidr: 1}, {unique: true});
db.subnets.createIndex({env: 1});
db.subnets.createIndex({location: 1});
print("[C] indexes (change_log, subnets) 建立");
JSEOF

# ============ Step 4: bump version + 重啟 ============
echo ""
echo "[4/6] bump version + 重啟"
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): CMDB 整合 P1-P6 combo (從 v$CURRENT_VER 升級) — 主機表加 ips array+aliases+5資產欄位; 重複偵測; 變更歷史; IPAM 網段管理; Excel 對帳; 孤兒主機/稽核曝光; 拓撲圖從 hosts 派生; 主機管理拉到 top nav. 22 個檔案 snapshot 替換 + 3 個 DB migration (idempotent)."] + d["changelog"]
with open(fp,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2)
print(f"      version: $CURRENT_VER -> $PATCH_VER")
PYEOF

systemctl restart "$SERVICE" && sleep 3
[ -n "$TUNNEL_SVC" ] && systemctl restart "$TUNNEL_SVC" && sleep 2
echo "      $SERVICE=$(systemctl is-active $SERVICE)"
[ -n "$TUNNEL_SVC" ] && echo "      $TUNNEL_SVC=$(systemctl is-active $TUNNEL_SVC)"

# ============ Step 5: smoke test (HTTP) ============
echo ""
echo "[5/6] smoke test"
set +e
ALL_OK=true
for u in /login /admin/host-edit/$(hostname) /admin/host-duplicates /admin/subnets /admin/recon /admin/orphans; do
    H=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:5000$u")
    case "$H" in 200|302) echo "      $u = $H ✓" ;; *) echo "      $u = $H ✗"; ALL_OK=false ;; esac
done

# ============ Step 6: contract check ============
echo ""
echo "[6/6] contract check (Python service 函式)"
sudo -u sysinfra python3 <<PYEOF
import sys
sys.path.insert(0, "$INSPECTION_HOME/webapp")
errors = []
try:
    from services.host_dedup import find_similar_hosts
    pairs = find_similar_hosts()
    print(f"      find_similar_hosts: {len(pairs)} 組 ✓")
except Exception as e: errors.append(f"host_dedup: {e}")
try:
    from services.change_log import list_history
    print(f"      change_log.list_history: OK ✓")
except Exception as e: errors.append(f"change_log: {e}")
try:
    from services.subnet_service import list_subnets
    subs = list_subnets()
    print(f"      list_subnets: {len(subs)} 段 ✓")
except Exception as e: errors.append(f"subnet: {e}")
try:
    from services.recon_service import compare
    print(f"      recon_service.compare: OK ✓")
except Exception as e: errors.append(f"recon: {e}")
try:
    from services.orphan_service import audit_summary
    a = audit_summary()
    print(f"      audit_summary: stale={a['stale_hosts_count']}, gap_ips={a['subnet_gaps']['total_gap_ips']} ✓")
except Exception as e: errors.append(f"orphan: {e}")
try:
    from services.dependency_service import _topology_from_hosts
    t = _topology_from_hosts()
    print(f"      topology: {len(t['nodes'])} nodes, {len(t['edges'])} edges ✓")
except Exception as e: errors.append(f"topology: {e}")
if errors:
    print("\n      contract FAIL:")
    for e in errors: print(f"        {e}")
    sys.exit(1)
PYEOF
[ "$?" = "0" ] || ALL_OK=false

echo ""
if $ALL_OK; then
    echo "✅ ✅ ✅  v${PATCH_VER} combo 部署完成"
    echo ""
    echo "新功能 URL:"
    echo "  /admin#hosts                         主機管理 (top nav)"
    echo "  /admin/host-edit/<hostname>          全頁編輯主機 (30 欄)"
    echo "  /admin/host-history/<hostname>       主機變更歷史"
    echo "  /admin/host-duplicates               🔍 重複偵測"
    echo "  /admin/subnets                       🌐 IPAM"
    echo "  /admin/recon                         📊 對帳"
    echo "  /admin/orphans                       👻 孤兒主機"
    echo "  /dependencies                        🗺️ 系統聯通圖 (節點從 hosts 派生)"
else
    echo "⚠️  smoke 有紅, 請檢查上面輸出再決定是否回滾"
fi

echo ""
echo "回滾 (若需要):"
echo "  cp -r $BACKUP_ROOT/webapp/* $INSPECTION_HOME/webapp/"
echo "  $MONGOIMPORT --collection hosts --drop < $BACKUP_ROOT/hosts.json"
echo "  systemctl restart $SERVICE ${TUNNEL_SVC:+$TUNNEL_SVC}"
