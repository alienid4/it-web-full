#!/bin/bash
# v3.15.7.0 全頁主機編輯
set -e
PATCH_VER="3.15.7.0"
HERE="$(cd "$(dirname "$0")" && pwd)"

INSPECTION_HOME=""
for p in /seclog/AI/inspection /opt/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "[FAIL] 找不到 INSPECTION_HOME"; exit 1; }
echo "[i] INSPECTION_HOME=$INSPECTION_HOME"

TS=$(date +%Y%m%d_%H%M%S)

echo ""
echo "[1/4] 備份"
cp "$INSPECTION_HOME/webapp/app.py"             "$INSPECTION_HOME/webapp/app.py.bak.${TS}"
cp "$INSPECTION_HOME/webapp/static/js/admin.js" "$INSPECTION_HOME/webapp/static/js/admin.js.bak.${TS}"
echo "      app.py.bak.${TS}"
echo "      admin.js.bak.${TS}"

echo ""
echo "[2/4] 部署"
cp "$HERE/files/webapp/app.py"                          "$INSPECTION_HOME/webapp/app.py"
cp "$HERE/files/webapp/static/js/admin.js"              "$INSPECTION_HOME/webapp/static/js/admin.js"
cp "$HERE/files/webapp/templates/host_edit.html"        "$INSPECTION_HOME/webapp/templates/host_edit.html"
chown -R sysinfra:itagent "$INSPECTION_HOME/webapp" 2>/dev/null || true
echo "      OK"

echo ""
echo "[3/4] bump version.json"
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp, encoding="utf-8") as f: d = json.load(f)
old = d["version"]
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): 主機編輯改全頁新分頁 - 新 /admin/host-edit/<hostname> 頁面 (5 區段卡片 grid layout, sticky 標題列含儲存按鈕, 不需捲動 modal); admin 主機表格『編輯』按鈕改 <a target=_blank>; 同 API (/api/admin/hosts PUT) 不動"] + d["changelog"]
with open(fp, "w", encoding="utf-8") as f: json.dump(d, f, ensure_ascii=False, indent=2)
print(f"      version.json: {old} -> $PATCH_VER")
PYEOF

echo ""
echo "[4/4] 重啟"
systemctl restart itagent-web && sleep 2 && systemctl restart itagent-tunnel
echo "      web=$(systemctl is-active itagent-web) tunnel=$(systemctl is-active itagent-tunnel)"
HTTP=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 http://localhost:5000/login)
echo "      curl /login = $HTTP"

echo ""
echo "[OK] v${PATCH_VER} install 完成"
echo "[i] 試開: http://221:5000/admin/host-edit/secansible"
echo ""
echo "回滾:"
echo "  cp $INSPECTION_HOME/webapp/app.py.bak.${TS} $INSPECTION_HOME/webapp/app.py"
echo "  cp $INSPECTION_HOME/webapp/static/js/admin.js.bak.${TS} $INSPECTION_HOME/webapp/static/js/admin.js"
echo "  rm $INSPECTION_HOME/webapp/templates/host_edit.html"
echo "  systemctl restart itagent-web itagent-tunnel"
