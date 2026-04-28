#!/bin/bash
# v3.17.5.0 孤兒主機 / 稽核曝光 (P5 of CMDB)
set -e
PATCH_VER="3.17.5.0"
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
cp "$HERE/files/webapp/templates/orphans.html"       "$INSPECTION_HOME/webapp/templates/orphans.html"
cp "$HERE/files/webapp/services/orphan_service.py"   "$INSPECTION_HOME/webapp/services/orphan_service.py"
chown -R sysinfra:itagent "$INSPECTION_HOME/webapp" 2>/dev/null || true

echo ""
echo "[3/4] bump + 重啟"
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): 孤兒主機/稽核曝光 (P5 CMDB) — (1) services/orphan_service.py: find_stale_hosts (依 inspections 最後 run_date 找 >30 天未巡檢) + find_subnet_gaps (IPAM CIDR 內未登記 IP) + audit_summary (2) /admin/orphans 頁: 6 道防線狀態 (公司沒給的 4 道標未開) + KPI + 久未巡檢表 + 網段 GAP 表 (3) navbar 加 👻 孤兒 入口 (4) API: GET /api/admin/orphans/audit"] + d["changelog"]
with open(fp,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2)
PYEOF
systemctl restart itagent-web && sleep 2 && systemctl restart itagent-tunnel
echo "      web=$(systemctl is-active itagent-web) tunnel=$(systemctl is-active itagent-tunnel)"

echo ""
echo "[4/4] smoke + contract"
set +e
ALL_OK=true
for u in /login /admin/orphans; do
    H=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:5000$u")
    echo "  $u = $H"
    case "$H" in 200|302) ;; *) ALL_OK=false ;; esac
done
sudo -u sysinfra python3 <<PYEOF
import sys; sys.path.insert(0, "$INSPECTION_HOME/webapp")
from services.orphan_service import audit_summary
a = audit_summary(days_threshold=30)
assert "stale_hosts" in a and "subnet_gaps" in a, "audit_summary 結構錯"
print(f"  contract: stale={a['stale_hosts_count']}台, subnets={a['subnet_gaps']['subnets_count']}段, gap_ips={a['subnet_gaps']['total_gap_ips']} ✓")
PYEOF
[ "$?" = "0" ] || ALL_OK=false
if $ALL_OK; then echo ""; echo "✅ v${PATCH_VER} smoke 全綠"; else echo ""; echo "⚠️ smoke 有紅"; fi
