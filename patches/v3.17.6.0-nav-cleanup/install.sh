#!/bin/bash
set -e
PATCH_VER="3.17.6.0"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSPECTION_HOME=""
for p in /seclog/AI/inspection /opt/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
TS=$(date +%Y%m%d_%H%M%S)
cp "$INSPECTION_HOME/webapp/templates/base.html"  "$INSPECTION_HOME/webapp/templates/base.html.bak.${TS}"
cp "$INSPECTION_HOME/webapp/templates/admin.html" "$INSPECTION_HOME/webapp/templates/admin.html.bak.${TS}"
cp "$HERE/files/webapp/templates/base.html"  "$INSPECTION_HOME/webapp/templates/base.html"
cp "$HERE/files/webapp/templates/admin.html" "$INSPECTION_HOME/webapp/templates/admin.html"
chown sysinfra:itagent "$INSPECTION_HOME/webapp/templates/base.html" "$INSPECTION_HOME/webapp/templates/admin.html" 2>/dev/null || true
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): nav cleanup — 把 IPAM/對帳/孤兒 3 個入口從 top navbar 移到 admin → 主機管理 toolbar (跟現有 🔍重複偵測 並排); 因為這 3 個都是主機管理範疇, 不該佔頂部 nav"] + d["changelog"]
with open(fp,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2)
PYEOF
systemctl restart itagent-web && sleep 2 && systemctl restart itagent-tunnel
HTTP=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:5000/login)
echo "smoke /login=$HTTP web=$(systemctl is-active itagent-web)"
[ "$HTTP" = "200" ] && echo "✅ v$PATCH_VER OK" || echo "⚠️"
