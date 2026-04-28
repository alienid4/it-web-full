#!/bin/bash
set -e
PATCH_VER="3.17.9.0"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "FAIL"; exit 1; }
TS=$(date +%Y%m%d_%H%M%S)

cp "$INSPECTION_HOME/webapp/routes/api_hosts.py"   "$INSPECTION_HOME/webapp/routes/api_hosts.py.bak.${TS}"
cp "$INSPECTION_HOME/webapp/static/js/admin.js"    "$INSPECTION_HOME/webapp/static/js/admin.js.bak.${TS}"
cp "$INSPECTION_HOME/webapp/templates/host_edit.html" "$INSPECTION_HOME/webapp/templates/host_edit.html.bak.${TS}"

cp "$HERE/files/webapp/services/actuals_service.py"   "$INSPECTION_HOME/webapp/services/actuals_service.py"
cp "$HERE/files/webapp/routes/api_hosts.py"           "$INSPECTION_HOME/webapp/routes/api_hosts.py"
cp "$HERE/files/webapp/static/js/admin.js"            "$INSPECTION_HOME/webapp/static/js/admin.js"
cp "$HERE/files/webapp/templates/host_edit.html"      "$INSPECTION_HOME/webapp/templates/host_edit.html"
chown -R sysinfra:itagent "$INSPECTION_HOME/webapp" 2>/dev/null || true

python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): 真實偵測值 vs 資產表填寫 對照 — (1) services/actuals_service.py: 從最新 inspections 撈 os/ip/hostname 偵測值, 與 hosts 比對, 不一致時 _mismatches 標記 (2) /api/hosts list/detail 自動 annotate _actuals/_mismatches (3) 主機列表 OS/IP 欄位顯示 ⚠️ badge (hover 看實際值) (4) 主機編輯頁 sticky header 下方顯示衝突 banner + 一鍵採用按鈕 (5) POST /api/hosts/<hn>/adopt-actual 把實際值寫進 hosts (6) 不自動覆蓋 — 人填值是責任歸屬"] + d["changelog"]
with open(fp,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2)
PYEOF

SERVICE=""
for svc in itagent-web itagent inspection-web; do
    systemctl list-unit-files | grep -q "^$svc" && SERVICE="$svc" && break
done
systemctl restart "$SERVICE" && sleep 2
TUNNEL=""
for svc in itagent-tunnel cloudflared; do
    systemctl list-unit-files | grep -q "^$svc" && TUNNEL="$svc" && break
done
[ -n "$TUNNEL" ] && systemctl restart "$TUNNEL" && sleep 2

set +e
echo ""
echo "=== smoke ==="
HTTP=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:5000/login)
echo "  /login = $HTTP"
sudo -u sysinfra python3 <<PYEOF
import sys; sys.path.insert(0, "$INSPECTION_HOME/webapp")
from services.actuals_service import get_actuals_map, annotate_host
m = get_actuals_map()
print(f"  actuals_map: {len(m)} 台主機有偵測值")
PYEOF
echo "[OK] v$PATCH_VER 完成"
