#!/bin/bash
# v3.17.4.0 Excel 對帳 (P4 of CMDB)
set -e
PATCH_VER="3.17.4.0"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSPECTION_HOME=""
for p in /seclog/AI/inspection /opt/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "FAIL"; exit 1; }
TS=$(date +%Y%m%d_%H%M%S)

echo "[1/4] 備份"
for f in webapp/app.py webapp/routes/api_admin.py webapp/templates/base.html; do
    cp "$INSPECTION_HOME/$f" "$INSPECTION_HOME/$f.bak.${TS}"
done

echo ""
echo "[2/4] 部署"
cp "$HERE/files/webapp/app.py"                       "$INSPECTION_HOME/webapp/app.py"
cp "$HERE/files/webapp/routes/api_admin.py"          "$INSPECTION_HOME/webapp/routes/api_admin.py"
cp "$HERE/files/webapp/templates/base.html"          "$INSPECTION_HOME/webapp/templates/base.html"
cp "$HERE/files/webapp/templates/recon.html"         "$INSPECTION_HOME/webapp/templates/recon.html"
cp "$HERE/files/webapp/services/recon_service.py"    "$INSPECTION_HOME/webapp/services/recon_service.py"
chown -R sysinfra:itagent "$INSPECTION_HOME/webapp" 2>/dev/null || true

echo ""
echo "[3/4] bump + 重啟"
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): Excel/CSV 對帳 (P4 CMDB) — (1) services/recon_service.py: parse_xlsx (openpyxl) + parse_csv (auto utf-8/big5/gbk) + compare() 三欄分類 (excel_only/matched/db_only), 比對 by hostname/alias/ip (2) /admin/recon 頁: 拖曳上傳 + 5 KPI + 3 欄看板 (3) navbar 加 📊 對帳 入口 (4) API: POST /api/admin/recon/upload"] + d["changelog"]
with open(fp,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2)
PYEOF
systemctl restart itagent-web && sleep 2 && systemctl restart itagent-tunnel
echo "      web=$(systemctl is-active itagent-web) tunnel=$(systemctl is-active itagent-tunnel)"

echo ""
echo "[4/4] smoke + contract"
set +e
ALL_OK=true
for u in /login /admin/recon; do
    H=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:5000$u")
    echo "  $u = $H"
    case "$H" in 200|302) ;; *) ALL_OK=false ;; esac
done

# Contract: 模擬 CSV 比對
sudo -u sysinfra python3 <<PYEOF
import sys; sys.path.insert(0, "$INSPECTION_HOME/webapp")
from services.recon_service import parse_csv, compare
csv_bytes = "hostname,ip\nsecansible,192.168.1.221\nfake-host,10.99.99.99\n".encode("utf-8")
rows = parse_csv(csv_bytes)
assert len(rows) == 2, f"parse_csv 應 2 筆 但 {len(rows)}"
result = compare(rows)
s = result["stats"]
assert s["matched_count"] >= 1, "secansible 應對得起來"
assert s["excel_only_count"] >= 1, "fake-host 應在 excel_only"
print(f"  contract: parse 2 行 → matched={s['matched_count']}, excel_only={s['excel_only_count']}, db_only={s['db_only_count']} ✓")
PYEOF
[ "$?" = "0" ] || ALL_OK=false
if $ALL_OK; then echo ""; echo "✅ v${PATCH_VER} smoke 全綠"; else echo ""; echo "⚠️ smoke 有紅"; fi
