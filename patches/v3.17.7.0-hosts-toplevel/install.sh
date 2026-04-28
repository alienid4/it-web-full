#!/bin/bash
set -e
PATCH_VER="3.17.7.0"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSPECTION_HOME=""
for p in /seclog/AI/inspection /opt/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
TS=$(date +%Y%m%d_%H%M%S)
cp "$INSPECTION_HOME/webapp/templates/base.html" "$INSPECTION_HOME/webapp/templates/base.html.bak.${TS}"
cp "$HERE/files/webapp/templates/base.html" "$INSPECTION_HOME/webapp/templates/base.html"
chown sysinfra:itagent "$INSPECTION_HOME/webapp/templates/base.html" 2>/dev/null || true
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): 主機管理拉到 top nav 變成獨立大項目 (從系統管理底下抽出, 用 /admin#hosts 直接到 主機清單 tab); navMap hash 偵測讓 /admin#hosts /jobs /scheduler /alerts 都 highlight 主機管理"] + d["changelog"]
with open(fp,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2)
PYEOF
systemctl restart itagent-web && sleep 2 && systemctl restart itagent-tunnel
HTTP=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:5000/login)
echo "smoke /login=$HTTP web=$(systemctl is-active itagent-web)"
[ "$HTTP" = "200" ] && echo "✅ v$PATCH_VER OK"
