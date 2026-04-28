#!/bin/bash
# 拓撲圖 debug 腳本 (v3.17.10.1+)
# 用法: bash debug_topology.sh
# 目的: 自動診斷「拓撲圖畫不出來」的常見原因

# 顏色
G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; B='\033[0;34m'; N='\033[0m'

ok()   { echo -e "${G}[OK]${N}   $*"; }
warn() { echo -e "${Y}[WARN]${N} $*"; }
fail() { echo -e "${R}[FAIL]${N} $*"; FAIL_CNT=$((FAIL_CNT+1)); }
hdr()  { echo -e "\n${B}=== $* ===${N}"; }
FAIL_CNT=0

# 偵測 INSPECTION_HOME
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { fail "找不到 INSPECTION_HOME (試 /opt/inspection 跟 /seclog/AI/inspection)"; exit 1; }
ok "INSPECTION_HOME = $INSPECTION_HOME"

# 偵測 mongo 執行方式
MONGOSH=""
if command -v mongosh >/dev/null 2>&1; then
    MONGOSH="mongosh inspection --quiet"
elif command -v mongo >/dev/null 2>&1; then
    MONGOSH="mongo inspection --quiet"
elif command -v podman >/dev/null 2>&1 && podman ps 2>/dev/null | grep -q mongodb; then
    MONGOSH="podman exec -i mongodb mongosh inspection --quiet"
elif command -v docker >/dev/null 2>&1 && docker ps 2>/dev/null | grep -q mongodb; then
    MONGOSH="docker exec -i mongodb mongosh inspection --quiet"
fi
[ -z "$MONGOSH" ] && { fail "找不到 mongo 執行方式"; exit 1; }
ok "MONGOSH = $MONGOSH"

# 1. 服務狀態
hdr "1. Web 服務狀態"
SERVICE=""
for svc in itagent-web itagent inspection-web; do
    systemctl list-unit-files 2>/dev/null | grep -q "^$svc" && SERVICE="$svc" && break
done
if [ -n "$SERVICE" ]; then
    STATE=$(systemctl is-active "$SERVICE")
    if [ "$STATE" = "active" ]; then
        ok "$SERVICE = active"
    else
        fail "$SERVICE = $STATE (應 active)"
    fi
else
    fail "找不到 web service (試 itagent-web/itagent/inspection-web)"
fi

# 2. 版本
hdr "2. 版本"
VER=$(python3 -c "import json; print(json.load(open('$INSPECTION_HOME/data/version.json'))['version'])" 2>/dev/null || echo "?")
echo "  目前版本: $VER"
case "$VER" in
    3.17.10.*|3.17.11.*|3.17.12.*|3.18.*|3.19.*|3.20.*) ok "版本 >= v3.17.10 (拓撲已修)" ;;
    3.17.0.0|3.17.7.0|3.17.7.1|3.17.7.2) warn "版本 $VER 拓撲可能有 edge id 空 bug, 建議升 v3.17.10.1+" ;;
    *) warn "版本 $VER 較舊, 建議升到 v3.17.10.1+" ;;
esac

# 3. Collection 計數
hdr "3. MongoDB Collection 資料"
COUNTS=$($MONGOSH --eval "
print('hosts:' + db.hosts.countDocuments());
print('dep_sys:' + db.dependency_systems.countDocuments());
print('dep_rel:' + db.dependency_relations.countDocuments());
print('feat:' + db.feature_flags.countDocuments({key:'dependencies', enabled:true}));
" 2>&1 | grep -E '^(hosts|dep_sys|dep_rel|feat):')
echo "$COUNTS"

HOSTS_N=$(echo "$COUNTS" | grep '^hosts:' | cut -d: -f2)
DEP_SYS_N=$(echo "$COUNTS" | grep '^dep_sys:' | cut -d: -f2)
DEP_REL_N=$(echo "$COUNTS" | grep '^dep_rel:' | cut -d: -f2)
FEAT_ON=$(echo "$COUNTS" | grep '^feat:' | cut -d: -f2)

if [ "$HOSTS_N" = "0" ]; then
    fail "hosts collection 是空的 — 還沒匯主機資料, 拓撲沒節點來源"
elif [ "$HOSTS_N" -gt 0 ]; then
    ok "hosts: $HOSTS_N 台"
fi

if [ "$FEAT_ON" = "1" ] || [ "$FEAT_ON" = "0" ]; then
    if [ "$FEAT_ON" = "1" ]; then ok "feature_flags.dependencies = enabled";
    else warn "feature_flags.dependencies = OFF (去 superadmin → 模組管理 開啟)"; fi
else
    warn "feature_flags 查不到 dependencies key (預設應為 enabled)"
fi

if [ "$DEP_REL_N" = "0" ]; then
    warn "dependency_relations 是空的 — 拓撲只有節點沒邊 (跑「立即採集」)"
else
    ok "dependency_relations: $DEP_REL_N 條邊"
fi

# 4. 檔案存在
hdr "4. 拓撲關鍵檔案"
for f in webapp/services/dependency_service.py webapp/routes/api_dependencies.py webapp/templates/dependencies.html webapp/static/js/dependencies.js webapp/static/css/example.css; do
    if [ -f "$INSPECTION_HOME/$f" ]; then
        ok "$f"
    else
        fail "缺 $f"
    fi
done

# 5. SSH warning 污染 (歷史踩過)
hdr "5. JS / template 開頭污染檢查"
for f in webapp/static/js/admin.js webapp/static/js/dependencies.js webapp/templates/admin.html; do
    if [ -f "$INSPECTION_HOME/$f" ]; then
        FIRST=$(head -1 "$INSPECTION_HOME/$f")
        if echo "$FIRST" | grep -q "^\*\*"; then
            fail "$f 開頭被 SSH warning 污染! 第 1 行: $FIRST"
        else
            ok "$f 開頭乾淨"
        fi
    fi
done

# 6. _topology_from_hosts 內部測試
hdr "6. Python service 直跑"
sudo -u sysinfra python3 <<PYEOF 2>&1 | sed 's/^/  /'
import sys
sys.path.insert(0, "$INSPECTION_HOME/webapp")
try:
    from services.dependency_service import _topology_from_hosts
    r = _topology_from_hosts()
    nodes = r.get("nodes", [])
    edges = r.get("edges", [])
    print(f"_topology_from_hosts: {len(nodes)} nodes, {len(edges)} edges")
    if not nodes:
        print("  -> nodes 空, 拓撲畫不出 (檢查 hosts collection)")
    if edges:
        ids = [e.get("id") for e in edges]
        empty = sum(1 for i in ids if not i)
        from collections import Counter
        dups = [k for k,v in Counter(ids).items() if v > 1]
        print(f"  edge id: empty={empty}, duplicates={len(dups)}")
        if empty or dups:
            print("  -> vis-network 會拒絕重複/空 id, 升 v3.17.10.1+")
        # check from/to keys
        if edges and ("from" not in edges[0] or "to" not in edges[0]):
            print("  -> edge 缺 from/to keys (用 from_system/to_system 是 v3.16.0.0 bug)")
except Exception as e:
    print(f"FAIL: {e}")
PYEOF

# 7. 最近 log error
hdr "7. 最近 log error (排除 stale)"
LOG_DIR="$INSPECTION_HOME/logs"
if [ -d "$LOG_DIR" ]; then
    LATEST=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
    if [ -n "$LATEST" ]; then
        ERRS=$(tail -100 "$LATEST" 2>/dev/null | grep -iE 'error|traceback|exception' | tail -3)
        if [ -z "$ERRS" ]; then
            ok "最近 log 乾淨"
        else
            warn "log 有 error:"
            echo "$ERRS" | sed 's/^/    /'
        fi
    fi
fi

# 8. HTTP 直 ping
hdr "8. HTTP 健康"
HTTP_LOGIN=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:5000/login 2>/dev/null)
HTTP_DEP=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:5000/dependencies 2>/dev/null)
HTTP_API=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:5000/api/dependencies/topology 2>/dev/null)
echo "  /login = $HTTP_LOGIN (應 200)"
echo "  /dependencies = $HTTP_DEP (應 200/302)"
echo "  /api/dependencies/topology = $HTTP_API (應 401 未登入 / 200 已登入)"

# 結論
hdr "結論"
if [ "$FAIL_CNT" -eq 0 ]; then
    echo -e "${G}全部關鍵檢查通過${N}, 還是畫不出 → 看 DevTools Console 截圖"
else
    echo -e "${R}$FAIL_CNT 個 fail${N}, 從紅色 [FAIL] 那行下手"
fi
echo ""
echo "若版本舊或拓撲 bug, 升 v3.17.10.1+:"
echo "  cd /tmp && rm -rf patch_combo_v3.17.* combo_v3.17.*"
echo "  wget https://github.com/alienid4/it-web-full/releases/download/v3.17.10.1/patch_combo_v3.17.10.1.tar.gz"
echo "  tar xzf patch_combo_v3.17.10.1.tar.gz"
echo "  cd combo_v3.17.10.1_cmdb_for_13 && bash install.sh"
