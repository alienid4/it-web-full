#!/bin/bash
# v3.15.6.0 主機編輯 Modal 擴充 29 欄 + scrollable
# 1. 備份 admin.html / admin.js
# 2. 替換為新版 (modal scrollable + 5 區段 + 29 欄 input)
# 3. bump version.json
# 4. 重啟 itagent-web (template/JS 改動需要重啟)

set -e

PATCH_VER="3.15.6.0"
HERE="$(cd "$(dirname "$0")" && pwd)"

# auto-detect INSPECTION_HOME
INSPECTION_HOME=""
for p in /seclog/AI/inspection /opt/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "[FAIL] 找不到 INSPECTION_HOME"; exit 1; }
echo "[i] INSPECTION_HOME=$INSPECTION_HOME"

TS=$(date +%Y%m%d_%H%M%S)

# Step 1/4: 備份
echo ""
echo "[1/4] 備份"
cp "$INSPECTION_HOME/webapp/templates/admin.html" "$INSPECTION_HOME/webapp/templates/admin.html.bak.${TS}"
cp "$INSPECTION_HOME/webapp/static/js/admin.js" "$INSPECTION_HOME/webapp/static/js/admin.js.bak.${TS}"
echo "      admin.html.bak.${TS}"
echo "      admin.js.bak.${TS}"

# Step 2/4: 替換
echo ""
echo "[2/4] 替換 admin.html / admin.js"
cp "$HERE/files/webapp/templates/admin.html" "$INSPECTION_HOME/webapp/templates/admin.html"
cp "$HERE/files/webapp/static/js/admin.js" "$INSPECTION_HOME/webapp/static/js/admin.js"
chown sysinfra:itagent "$INSPECTION_HOME/webapp/templates/admin.html" "$INSPECTION_HOME/webapp/static/js/admin.js" 2>/dev/null || true
echo "      OK"

# Step 3/4: bump version.json
echo ""
echo "[3/4] bump version.json"
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp, encoding="utf-8") as f:
    d = json.load(f)
old = d.get("version")
new_entry = "$PATCH_VER - $(date +%Y-%m-%d): 主機編輯 Modal 擴充 29 欄資產表 - (1) Modal 加 max-height:88vh + overflow-y:auto 解滑鼠滾輪不能捲動 (2) 分 5 區段 (基本/資產表/人員/資安/巡檢專屬) (3) 加 18 個新 input 含 division/department/asset_seq/group_name/apid/asset_name/device_type/device_model/asset_usage/location/rack_no/quantity/bigip/hardware_seq/owner/sys_admin/user/user_unit/company/confidentiality/integrity/availability/request_no/infra (4) 環境別 enum 從 2 種擴成 6 種 (5) 資產狀態下拉 (6) saveHost / editHost 同步擴充 read/write 全 29 欄"
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = [new_entry] + d.get("changelog", [])
with open(fp, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print(f"      version.json: {old} -> $PATCH_VER")
PYEOF

# Step 4/4: 重啟 web (含 cloudflared 連帶)
echo ""
echo "[4/4] 重啟 itagent-web + itagent-tunnel"
systemctl restart itagent-web
sleep 2
systemctl restart itagent-tunnel
sleep 3
echo "      itagent-web=$(systemctl is-active itagent-web)"
echo "      itagent-tunnel=$(systemctl is-active itagent-tunnel)"

# HTTP 驗證
HTTP=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 http://localhost:5000/login)
echo "      curl /login HTTP: $HTTP"

echo ""
echo "[OK] v${PATCH_VER} install 完成"
echo "[i] 瀏覽器要 Ctrl+F5 強制清 cache 才會看到新 modal"
echo ""
echo "回滾指令:"
echo "  cp $INSPECTION_HOME/webapp/templates/admin.html.bak.${TS} $INSPECTION_HOME/webapp/templates/admin.html"
echo "  cp $INSPECTION_HOME/webapp/static/js/admin.js.bak.${TS} $INSPECTION_HOME/webapp/static/js/admin.js"
echo "  systemctl restart itagent-web itagent-tunnel"
