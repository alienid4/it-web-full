#!/bin/bash
# v3.17.2.0 變更歷史 (P6 of CMDB)
set -e
PATCH_VER="3.17.2.0"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSPECTION_HOME=""
for p in /seclog/AI/inspection /opt/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "FAIL"; exit 1; }
TS=$(date +%Y%m%d_%H%M%S)

echo "[1/4] 備份"
cp "$INSPECTION_HOME/webapp/app.py"            "$INSPECTION_HOME/webapp/app.py.bak.${TS}"
cp "$INSPECTION_HOME/webapp/routes/api_admin.py" "$INSPECTION_HOME/webapp/routes/api_admin.py.bak.${TS}"

echo ""
echo "[2/4] 部署"
cp "$HERE/files/webapp/app.py"                          "$INSPECTION_HOME/webapp/app.py"
cp "$HERE/files/webapp/routes/api_admin.py"             "$INSPECTION_HOME/webapp/routes/api_admin.py"
cp "$HERE/files/webapp/templates/host_history.html"     "$INSPECTION_HOME/webapp/templates/host_history.html"
cp "$HERE/files/webapp/services/change_log.py"          "$INSPECTION_HOME/webapp/services/change_log.py"
chown -R sysinfra:itagent "$INSPECTION_HOME/webapp" 2>/dev/null || true

echo ""
echo "[3/4] DB index + bump + 重啟"
sudo -u sysinfra python3 -c "
import sys; sys.path.insert(0, '$INSPECTION_HOME/webapp')
from services.change_log import ensure_indexes
ensure_indexes()
print('      change_log indexes 建立')
"
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): 變更歷史 (P6 CMDB) — (1) services/change_log.py: ensure_indexes/record/list_history/diff_dicts (2) hosts CRUD 4 處 (add/edit/delete/merge) hook 自動寫 change_log (before+after diff) (3) 新頁 /admin/host-history/<hostname> timeline 顯示 (action 顏色標籤 + diff table 紅刪綠加) (4) API: GET /api/admin/hosts/<hn>/history"] + d["changelog"]
with open(fp,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2)
PYEOF
systemctl restart itagent-web && sleep 2 && systemctl restart itagent-tunnel
echo "      web=$(systemctl is-active itagent-web) tunnel=$(systemctl is-active itagent-tunnel)"

echo ""
echo "[4/4] smoke + contract"
set +e
ALL_OK=true
for u in /login /admin/host-history/secansible; do
    H=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:5000$u")
    echo "  $u = $H"
    case "$H" in 200|302) ;; *) ALL_OK=false ;; esac
done
sudo -u sysinfra python3 <<PYEOF
import sys; sys.path.insert(0, "$INSPECTION_HOME/webapp")
from services.change_log import list_history, record, diff_dicts
# 寫測試紀錄看 record 不報錯
record(hostname="__smoke__", action="create", who="smoke_test", detail="P6 contract test")
hist = list_history(hostname="__smoke__")
assert len(hist) >= 1, "record 沒寫進去"
# diff
d = diff_dicts({"a":1,"b":2}, {"a":1,"b":3,"c":4})
assert any(c["field"]=="b" for c in d), "diff 沒抓到 b 變動"
print(f"  contract: change_log 寫/讀/diff OK ({len(hist)} smoke entries)")
# 清掉測試資料
from services.mongo_service import get_collection
get_collection("change_log").delete_many({"hostname":"__smoke__"})
PYEOF
[ "$?" = "0" ] || ALL_OK=false
if $ALL_OK; then echo ""; echo "✅ v${PATCH_VER} smoke 全綠"; else echo ""; echo "⚠️ smoke 有紅"; fi
