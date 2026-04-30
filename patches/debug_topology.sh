#!/bin/bash
# 拓撲圖 debug 腳本 v2 (對應 v3.17.10.4+)
# 用法: sudo bash debug_topology.sh           # quiet (預設,只印異常)
#       sudo VERBOSE=1 bash debug_topology.sh # 全印
#
# 設計: ssh 到 INSPECTION host 跑一次, 從 [FAIL]/[WARN] 紅黃字一眼定位
# - 採集鏈 (mongo dep_collect_runs / hosts↔system 反查)
# - 後端 API
# - 前端模板
# - 路由層 (5xx / login redirect / 模板 jinja error)

# 顏色
G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; B='\033[0;34m'; N='\033[0m'

FAIL_CNT=0
PENDING_HDR=""

# Quiet by default, VERBOSE=1 開後門
_flush_hdr() {
    if [ -n "$PENDING_HDR" ]; then
        echo -e "\n${B}=== $PENDING_HDR ===${N}"
        PENDING_HDR=""
    fi
}
hdr() {
    if [ "$VERBOSE" = "1" ]; then
        echo -e "\n${B}=== $* ===${N}"
        PENDING_HDR=""
    else
        PENDING_HDR="$*"
    fi
}
ok()   { [ "$VERBOSE" = "1" ] && echo -e "${G}[OK]${N}   $*"; }
info() { [ "$VERBOSE" = "1" ] && echo "  $*"; }
warn() { _flush_hdr; echo -e "${Y}[WARN]${N} $*"; }
fail() { _flush_hdr; echo -e "${R}[FAIL]${N} $*"; FAIL_CNT=$((FAIL_CNT+1)); }

echo -e "${B}===== 拓撲 debug v2 (quiet mode, VERBOSE=1 印全部) =====${N}"

# 偵測 INSPECTION_HOME
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
if [ -z "$INSPECTION_HOME" ]; then
    echo -e "${R}[FAIL]${N} 找不到 INSPECTION_HOME (試 /opt/inspection 跟 /seclog/AI/inspection)"
    exit 1
fi
ok "INSPECTION_HOME = $INSPECTION_HOME"

# 偵測 mongo 執行方式 (mongosh > mongo > podman > docker, memory: feedback_company_no_podman)
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
if [ -z "$MONGOSH" ]; then
    echo -e "${R}[FAIL]${N} 找不到 mongo 執行方式"
    exit 1
fi
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
    fail "找不到 web service (試過 itagent-web/itagent/inspection-web)"
fi

# 2. 版本
hdr "2. 版本"
VER=$(python3 -c "import json; print(json.load(open('$INSPECTION_HOME/data/version.json'))['version'])" 2>/dev/null || echo "?")
case "$VER" in
    3.17.10.4|3.17.10.5*|3.17.11.*|3.17.12.*|3.18.*|3.19.*|3.20.*) ok "版本 $VER (>= v3.17.10.4 拓撲已修)" ;;
    3.17.10.0|3.17.10.1|3.17.10.2|3.17.10.3) warn "版本 $VER 需升 v3.17.10.4 (修採集 default --limit 寫死 hostname)" ;;
    3.17.0.0|3.17.7.*|3.17.8.*|3.17.9.*) warn "版本 $VER 拓撲可能有 edge id 或採集 limit bug, 建議升 v3.17.10.4+" ;;
    *) warn "版本 $VER 較舊或讀不到, 建議升到 v3.17.10.4+" ;;
esac

# 3. Collection 計數
hdr "3. MongoDB Collection 資料"
COUNTS=$($MONGOSH --eval "
print('hosts:' + db.hosts.countDocuments());
print('dep_sys:' + db.dependency_systems.countDocuments());
print('dep_rel:' + db.dependency_relations.countDocuments());
print('dep_runs:' + db.dependency_collect_runs.countDocuments());
print('feat:' + db.feature_flags.countDocuments({key:'dependencies', enabled:true}));
" 2>&1 | grep -E '^(hosts|dep_sys|dep_rel|dep_runs|feat):')

HOSTS_N=$(echo "$COUNTS" | grep '^hosts:' | cut -d: -f2)
DEP_SYS_N=$(echo "$COUNTS" | grep '^dep_sys:' | cut -d: -f2)
DEP_REL_N=$(echo "$COUNTS" | grep '^dep_rel:' | cut -d: -f2)
DEP_RUNS_N=$(echo "$COUNTS" | grep '^dep_runs:' | cut -d: -f2)
FEAT_ON=$(echo "$COUNTS" | grep '^feat:' | cut -d: -f2)

[ "$VERBOSE" = "1" ] && echo "$COUNTS"

if [ "$HOSTS_N" = "0" ] || [ -z "$HOSTS_N" ]; then
    fail "hosts collection 是空的 — 還沒匯主機資料, 拓撲沒節點來源"
else
    ok "hosts: $HOSTS_N 台"
fi

if [ "$DEP_SYS_N" = "0" ] || [ -z "$DEP_SYS_N" ]; then
    fail "dependency_systems 是空的 — 沒任何 system 節點 (拓撲畫不出)"
else
    ok "dependency_systems: $DEP_SYS_N 個系統"
fi

if [ "$FEAT_ON" = "1" ]; then
    ok "feature_flags.dependencies = enabled"
elif [ "$FEAT_ON" = "0" ]; then
    fail "feature_flags.dependencies = OFF (去 superadmin → 模組管理 開啟)"
else
    warn "feature_flags 查不到 dependencies key (預設應為 enabled, 可能是舊版)"
fi

if [ "$DEP_REL_N" = "0" ] || [ -z "$DEP_REL_N" ]; then
    warn "dependency_relations 是空的 — 拓撲只有節點沒邊 (看 9.dep_collect_runs 與 10.host_refs 反查)"
else
    ok "dependency_relations: $DEP_REL_N 條邊"
fi

# 4. 檔案存在
hdr "4. 拓撲關鍵檔案"
for f in webapp/services/dependency_service.py webapp/routes/api_dependencies.py \
         webapp/templates/dependencies.html webapp/templates/dependencies_fullscreen.html \
         webapp/static/js/dependencies.js; do
    if [ -f "$INSPECTION_HOME/$f" ]; then
        ok "$f"
    else
        fail "缺 $f"
    fi
done

# 5. SSH warning 污染 (memory: feedback_ssh_stderr_pollution)
hdr "5. JS / template 開頭污染檢查"
for f in webapp/static/js/admin.js webapp/static/js/dependencies.js webapp/templates/dependencies.html webapp/templates/base.html; do
    if [ -f "$INSPECTION_HOME/$f" ]; then
        FIRST=$(head -1 "$INSPECTION_HOME/$f")
        if echo "$FIRST" | grep -q "^\*\*"; then
            fail "$f 開頭被 SSH warning 污染! 第 1 行: $FIRST"
        else
            ok "$f 開頭乾淨"
        fi
    fi
done

# 6. Python service 直跑 (對應 v3.17.10.x 新 API)
hdr "6. Python topology() 直跑測 3 個 view"
PY_OUT=$(sudo -u sysinfra python3 <<PYEOF 2>&1
import sys
sys.path.insert(0, "$INSPECTION_HOME/webapp")
try:
    from services.dependency_service import topology
except Exception as e:
    print(f"IMPORT_FAIL: {e}")
    sys.exit(0)

from collections import Counter
for view in ("system", "host", "ip"):
    try:
        r = topology(view=view)
        nodes, edges = r.get("nodes", []), r.get("edges", [])
        # edge id 完整性
        ids = [e.get("id") for e in edges]
        empty = sum(1 for i in ids if not i)
        dups = sum(1 for k, v in Counter(ids).items() if v > 1)
        # from/to keys 檢查 (v3.16.0.0 bug: 用了 from_system/to_system)
        bad_keys = sum(1 for e in edges if "from" not in e or "to" not in e)
        # node id 完整性
        node_ids = [n.get("id") or n.get("system_id") for n in nodes]
        node_empty = sum(1 for i in node_ids if not i)
        line = f"VIEW={view}: nodes={len(nodes)} edges={len(edges)}"
        if empty: line += f" edge_id_empty={empty}"
        if dups: line += f" edge_id_dup={dups}"
        if bad_keys: line += f" edge_no_fromto={bad_keys}"
        if node_empty: line += f" node_id_empty={node_empty}"
        print(line)
    except Exception as e:
        print(f"VIEW={view}: EXCEPTION {type(e).__name__}: {e}")
PYEOF
)
if echo "$PY_OUT" | grep -q "IMPORT_FAIL"; then
    fail "topology() import 失敗:"
    echo "$PY_OUT" | sed 's/^/    /'
elif echo "$PY_OUT" | grep -qE "EXCEPTION|edge_id_empty|edge_id_dup|edge_no_fromto|node_id_empty"; then
    fail "topology() 有結構問題:"
    echo "$PY_OUT" | sed 's/^/    /'
else
    [ "$VERBOSE" = "1" ] && echo "$PY_OUT" | sed 's/^/    /'
    # 額外檢查: 三個 view 都 0 邊
    if echo "$PY_OUT" | grep -q "edges=0$" && [ "$DEP_REL_N" != "0" ]; then
        warn "topology() 撈出 0 邊但 dep_rel 有 $DEP_REL_N 條 → BFS/limit/center 把邊濾掉了"
    fi
    ok "topology() 三 view 結構正常"
fi

# 7. 最近 webapp log error
hdr "7. webapp log 最近 error"
LOG_DIR="$INSPECTION_HOME/logs"
if [ -d "$LOG_DIR" ]; then
    LATEST=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | grep -v dep_collect | head -1)
    if [ -n "$LATEST" ]; then
        ERRS=$(tail -200 "$LATEST" 2>/dev/null | grep -iE 'error|traceback|exception' | tail -5)
        if [ -z "$ERRS" ]; then
            ok "$LATEST 末 200 行乾淨"
        else
            warn "$LATEST 有 error:"
            echo "$ERRS" | sed 's/^/    /'
        fi
    fi
fi

# 8. HTTP 健康 (基本 ping)
hdr "8. HTTP 基本 ping"
HTTP_LOGIN=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:5000/login 2>/dev/null)
HTTP_API=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:5000/api/dependencies/topology 2>/dev/null)
if [ "$HTTP_LOGIN" != "200" ]; then
    fail "/login = $HTTP_LOGIN (應 200)"
else
    ok "/login = 200"
fi
if [ "$HTTP_API" != "401" ] && [ "$HTTP_API" != "200" ] && [ "$HTTP_API" != "302" ]; then
    fail "/api/dependencies/topology = $HTTP_API (應 401 未登入 / 200 已登入 / 302 redirect)"
else
    ok "/api/dependencies/topology = $HTTP_API"
fi

# ---- 9-14: v2 新增 ----

# 9. dependency_collect_runs 最新一筆 (v3.17.10.3+ 加的 collection)
hdr "9. dependency_collect_runs 最新一筆"
RUN_OUT=$($MONGOSH --eval '
const d = db.dependency_collect_runs.find({}).sort({started_at:-1}).limit(1).toArray()[0];
if (!d) {
    print("NO_RUN");
} else {
    print("STATUS:" + (d.status || "-"));
    print("STARTED:" + (d.started_at || "-"));
    print("FINISHED:" + (d.finished_at || "-"));
    print("EDGES_ADDED:" + (d.edges_added || 0));
    print("EDGES_UPDATED:" + (d.edges_updated || 0));
    print("TRIGGERED_BY:" + (d.triggered_by || "-"));
    print("LIMIT:" + (d.limit || "-"));
    print("ERROR:" + (d.error || "-"));
}
' 2>/dev/null)

if echo "$RUN_OUT" | grep -q "^NO_RUN$"; then
    warn "dep_collect_runs 沒任何紀錄 (還沒按過 toolbar『📡 採集』, 或 cron 還沒跑)"
else
    R_STATUS=$(echo "$RUN_OUT" | grep "^STATUS:" | cut -d: -f2-)
    R_ERROR=$(echo "$RUN_OUT" | grep "^ERROR:" | cut -d: -f2-)
    R_EDGES=$(echo "$RUN_OUT" | grep "^EDGES_ADDED:" | cut -d: -f2-)
    R_UPD=$(echo "$RUN_OUT" | grep "^EDGES_UPDATED:" | cut -d: -f2-)
    if [ "$R_STATUS" = "failed" ]; then
        fail "最近一次採集 failed — error: $R_ERROR"
        echo "    對照 SOP Step 6: notes/2026-04-29/2026-04-29_1500_install-v3.17.10.2-and-3-then-cron-13.md"
    elif [ "$R_STATUS" = "running" ]; then
        warn "採集 running 中 (1-3 分後再跑這支 debug)"
    elif [ "$R_STATUS" = "success" ]; then
        if [ "$R_EDGES" = "0" ] && [ "$R_UPD" = "0" ]; then
            warn "採集 success 但 edges_added=0 + edges_updated=0 (連線採到了但反查不到 system → 看 10.)"
        else
            ok "採集 success: +$R_EDGES 邊 / 更新 $R_UPD"
        fi
    fi
    [ "$VERBOSE" = "1" ] && echo "$RUN_OUT" | sed 's/^/    /'
fi

# 10. hosts ↔ dependency_systems.host_refs 反查健康度
hdr "10. host_refs 反查 (採集寫邊的關鍵)"
ORPHAN_OUT=$($MONGOSH --eval '
const hostnames = db.hosts.distinct("hostname");
const refDocs = db.dependency_systems.aggregate([
    {$unwind:"$host_refs"},
    {$group:{_id:"$host_refs"}}
]).toArray();
const refSet = new Set(refDocs.map(x => x._id));
const orphans = hostnames.filter(h => !refSet.has(h));
print("HOSTS:" + hostnames.length);
print("IN_REFS:" + refSet.size);
print("ORPHANS:" + orphans.length);
if (orphans.length > 0) {
    print("SAMPLE:" + JSON.stringify(orphans.slice(0, 5)));
}
' 2>/dev/null)

O_HOSTS=$(echo "$ORPHAN_OUT" | grep "^HOSTS:" | cut -d: -f2)
O_REFS=$(echo "$ORPHAN_OUT" | grep "^IN_REFS:" | cut -d: -f2)
O_ORPHAN=$(echo "$ORPHAN_OUT" | grep "^ORPHANS:" | cut -d: -f2)
O_SAMPLE=$(echo "$ORPHAN_OUT" | grep "^SAMPLE:" | cut -d: -f2-)

if [ -n "$O_HOSTS" ] && [ "$O_HOSTS" != "0" ]; then
    if [ "$O_ORPHAN" = "$O_HOSTS" ]; then
        fail "$O_ORPHAN/$O_HOSTS 主機都不在任何 system.host_refs → 採集寫不出邊"
        echo "    去 /admin → 拓撲管理 tab → 設 system 與 host_refs"
        [ -n "$O_SAMPLE" ] && echo "    orphan sample: $O_SAMPLE"
    elif [ "$O_ORPHAN" -gt 0 ] 2>/dev/null; then
        warn "$O_ORPHAN/$O_HOSTS 主機未綁 system (這幾台採集到也無邊可寫)"
        [ -n "$O_SAMPLE" ] && echo "    orphan sample: $O_SAMPLE"
    else
        ok "$O_HOSTS 台主機全都已綁進 system.host_refs"
    fi
fi

# 11. HTTP 三條路由比對 (對症「畫面空白」)
hdr "11. HTTP 路由 (對症畫面空白)"
for path in /dependencies /dependencies/fullscreen /dependencies/ghosts; do
    HEAD_LINE=$(curl -sS -i --max-time 5 "http://localhost:5000$path" 2>/dev/null | head -1 | tr -d '\r')
    HTTP_CODE=$(echo "$HEAD_LINE" | awk '{print $2}')
    BODY=$(curl -sS --max-time 5 "http://localhost:5000$path" 2>/dev/null | head -c 500 | tr -d '\n\r' | sed 's/  */ /g')

    if [ -z "$HTTP_CODE" ]; then
        fail "$path → 連不到 (curl 失敗)"
    elif [ "$HTTP_CODE" = "200" ]; then
        # 200 但內容可能是 5xx HTML 或模板斷掉
        if echo "$BODY" | grep -qiE 'internal server error|traceback|jinja'; then
            fail "$path → 200 但 body 含 error 字樣 (Jinja 渲染斷):"
            echo "    body[0:200]: $(echo "$BODY" | head -c 200)"
        elif ! echo "$BODY" | grep -q 'dep-toolbar\|dep-fullscreen\|dep-ghosts\|<title>\|系統聯通'; then
            fail "$path → 200 但 body 沒拓撲頁特徵字串 (模板可能被換掉):"
            echo "    body[0:200]: $(echo "$BODY" | head -c 200)"
        else
            ok "$path → 200 (body 含拓撲頁特徵)"
        fi
    elif [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        LOC=$(curl -sS -i --max-time 5 "http://localhost:5000$path" 2>/dev/null | grep -i '^Location:' | tr -d '\r')
        warn "$path → $HTTP_CODE redirect ($LOC)"
        echo "    八成是 session 過期 → 重新 login 後再點「📊 狀態」"
    else
        fail "$path → HTTP $HTTP_CODE"
        if [ "$VERBOSE" = "1" ] || [ "$HTTP_CODE" -ge 500 ] 2>/dev/null; then
            echo "    body[0:300]: $(echo "$BODY" | head -c 300)"
        fi
    fi
done

# 12. systemd journalctl 最近 traceback
hdr "12. systemctl 最近 30 分 traceback"
if [ -n "$SERVICE" ]; then
    JOURNAL=$(sudo journalctl -u "$SERVICE" --since "30 min ago" --no-pager 2>/dev/null \
        | grep -A 15 -iE 'traceback|exception|werkzeug.*error|jinja2.exceptions' | tail -50)
    if [ -n "$JOURNAL" ]; then
        fail "$SERVICE 最近 30 分有 traceback (上下文 50 行):"
        echo "$JOURNAL" | sed 's/^/    /'
    else
        ok "$SERVICE 最近 30 分無 traceback"
    fi
fi

# 13. cron 採集排程 (對應 SOP Step 5b/c)
hdr "13. cron 採集排程"
CRON_LINE=$(sudo crontab -u sysinfra -l 2>/dev/null | grep MARK_DEP_COLLECT)
if [ -z "$CRON_LINE" ]; then
    warn "cron 未設過 MARK_DEP_COLLECT (admin → 拓撲管理 tab → 採集排程)"
else
    ok "cron: $CRON_LINE"
fi

# 14. 最新 ansible 採集 log 末段
hdr "14. ansible 採集 log 末 30 行"
LAT_DEP_LOG=$(sudo ls -t "$INSPECTION_HOME/logs/dep_collect_"*.log 2>/dev/null | head -1)
if [ -z "$LAT_DEP_LOG" ]; then
    warn "找不到 dep_collect_*.log (還沒手動觸發過採集)"
else
    # 只在 9. fail 時印, 不然太多
    if [ "$R_STATUS" = "failed" ] || [ "$VERBOSE" = "1" ]; then
        fail "ansible log: $LAT_DEP_LOG (末 30 行):"
        sudo tail -30 "$LAT_DEP_LOG" 2>/dev/null | sed 's/^/    /'
    else
        ok "ansible log 存在: $LAT_DEP_LOG (採集未 fail, 不印詳細)"
    fi
fi

# ---- 結論 + 對症 hint ----
echo ""
echo -e "${B}===== 結論 =====${N}"
if [ "$FAIL_CNT" -eq 0 ]; then
    echo -e "${G}✅ 全部關鍵檢查通過${N}"
    if [ "$DEP_REL_N" = "0" ] || [ -z "$DEP_REL_N" ]; then
        echo "  但 dep_rel = 0 → 點 toolbar『📡 採集』, 等 1-3 分按『📊 狀態』"
    elif [ "$O_ORPHAN" = "$O_HOSTS" ] && [ -n "$O_HOSTS" ] && [ "$O_HOSTS" != "0" ]; then
        echo "  但所有主機都未綁 system → /admin 拓撲管理 tab 補 host_refs"
    else
        echo "  畫面還是空白 → 看 DevTools Console + Network tab 的 /api/dependencies/topology 回傳"
    fi
else
    echo -e "${R}✗ $FAIL_CNT 個 fail${N} — 從上面紅色 [FAIL] 那行下手"
fi
echo ""
