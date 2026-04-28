#!/bin/bash
set -e
PATCH_VER="3.17.8.0"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "FAIL"; exit 1; }
TS=$(date +%Y%m%d_%H%M%S)
cp "$INSPECTION_HOME/webapp/templates/admin.html" "$INSPECTION_HOME/webapp/templates/admin.html.bak.${TS}"
cp "$INSPECTION_HOME/webapp/static/js/admin.js"  "$INSPECTION_HOME/webapp/static/js/admin.js.bak.${TS}"
cp "$HERE/files/webapp/templates/admin.html" "$INSPECTION_HOME/webapp/templates/admin.html"
cp "$HERE/files/webapp/static/js/admin.js"   "$INSPECTION_HOME/webapp/static/js/admin.js"
chown sysinfra:itagent "$INSPECTION_HOME/webapp/templates/admin.html" "$INSPECTION_HOME/webapp/static/js/admin.js" 2>/dev/null || true
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): 主機列表加搜尋/排序/快速篩選 + 換欄位 — (1) 加搜尋框 (hostname/IP/資產名稱/附加說明/系統別/別名/IP陣列) (2) 3 排快速 chip 篩選 (環境/OS/使用情境=asset_usage), 動態從現有資料生成 (3) 5 欄可點擊排序 (4) 表格欄位調整: 拿掉 保管者/部門/群組, 換 資產名稱/附加說明 (5) 顯示「N/總共」+ 清除全部 filter 按鈕"] + d["changelog"]
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

HTTP=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:5000/login)
echo "smoke /login=$HTTP"
echo "[OK] v$PATCH_VER 完成"
