#!/bin/bash
# v3.17.7.3 hot-fix: import_csv 29 中文 + 主機管理頁隱藏其他 group + DELETE auto reload
set -e
PATCH_VER="3.17.7.3"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "FAIL"; exit 1; }
TS=$(date +%Y%m%d_%H%M%S)

cp "$INSPECTION_HOME/webapp/routes/api_admin.py"   "$INSPECTION_HOME/webapp/routes/api_admin.py.bak.${TS}"
cp "$INSPECTION_HOME/webapp/static/js/admin.js"    "$INSPECTION_HOME/webapp/static/js/admin.js.bak.${TS}"
cp "$HERE/files/webapp/routes/api_admin.py"        "$INSPECTION_HOME/webapp/routes/api_admin.py"
cp "$HERE/files/webapp/static/js/admin.js"         "$INSPECTION_HOME/webapp/static/js/admin.js"
chown sysinfra:itagent "$INSPECTION_HOME/webapp/routes/api_admin.py" "$INSPECTION_HOME/webapp/static/js/admin.js" 2>/dev/null || true

python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): hot-fix 3 件 — (1) import_csv 加 29 欄中文標頭 mapping (匯出再匯回完整對得上) (2) URL hash=hosts/jobs/scheduler/alerts 時 admin 頁隱藏其他 nav group (主機管理變獨立頁) (3) DELETE host 後 auto loadHosts() (不用手動重整)"] + d["changelog"]
with open(fp,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2)
PYEOF

# 偵測 service
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

echo ""
echo "=== smoke ==="
HTTP=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:5000/login)
echo "  /login = $HTTP"
sudo -u sysinfra python3 -c "
import sys, ast
sys.path.insert(0, '$INSPECTION_HOME/webapp')
ast.parse(open('$INSPECTION_HOME/webapp/routes/api_admin.py').read())
print('  api_admin.py AST OK')
print('  ✓ HEADER_MAP keys:', open('$INSPECTION_HOME/webapp/routes/api_admin.py').read().count('盤點單位-處別'), '個 (應 >= 1)')
"
echo ""
echo "[OK] v$PATCH_VER 完成"
echo "回滾:"
echo "  cp $INSPECTION_HOME/webapp/routes/api_admin.py.bak.${TS} $INSPECTION_HOME/webapp/routes/api_admin.py"
echo "  cp $INSPECTION_HOME/webapp/static/js/admin.js.bak.${TS}  $INSPECTION_HOME/webapp/static/js/admin.js"
echo "  systemctl restart $SERVICE ${TUNNEL:+$TUNNEL}"
