#!/bin/bash
set -e
PATCH_VER="3.17.7.4"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "FAIL"; exit 1; }
TS=$(date +%Y%m%d_%H%M%S)

cp "$INSPECTION_HOME/webapp/services/dependency_service.py" "$INSPECTION_HOME/webapp/services/dependency_service.py.bak.${TS}"
cp "$INSPECTION_HOME/webapp/static/js/admin.js" "$INSPECTION_HOME/webapp/static/js/admin.js.bak.${TS}"
cp "$HERE/files/webapp/services/dependency_service.py" "$INSPECTION_HOME/webapp/services/dependency_service.py"
cp "$HERE/files/webapp/static/js/admin.js" "$INSPECTION_HOME/webapp/static/js/admin.js"
chown sysinfra:itagent "$INSPECTION_HOME/webapp/services/dependency_service.py" "$INSPECTION_HOME/webapp/static/js/admin.js" 2>/dev/null || true

python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): hot-fix 2 件 — (1) 拓撲節點 display_name 改用 asset_name 優先 (之前用 apid 不對) (2) 立即採集加 confirm 對話 + 預估時間 (1-3 分鐘) + 友善進度文字, 避免使用者以為系統當機"] + d["changelog"]
with open(fp,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2)
PYEOF

SERVICE=""
for svc in itagent-web itagent inspection-web; do
    systemctl list-unit-files | grep -q "^$svc" && SERVICE="$svc" && break
done
systemctl restart "$SERVICE" 2>/dev/null && sleep 2
TUNNEL=""
for svc in itagent-tunnel cloudflared; do
    systemctl list-unit-files | grep -q "^$svc" && TUNNEL="$svc" && break
done
[ -n "$TUNNEL" ] && systemctl restart "$TUNNEL" 2>/dev/null && sleep 2

# smoke
HTTP=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:5000/login)
echo "smoke /login=$HTTP"
echo "[OK] v$PATCH_VER 完成"
