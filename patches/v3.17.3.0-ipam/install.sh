#!/bin/bash
# v3.17.3.0 IPAM 簡化版 (P3 of CMDB)
set -e
PATCH_VER="3.17.3.0"
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
cp "$HERE/files/webapp/templates/subnets.html"       "$INSPECTION_HOME/webapp/templates/subnets.html"
cp "$HERE/files/webapp/services/subnet_service.py"   "$INSPECTION_HOME/webapp/services/subnet_service.py"
chown -R sysinfra:itagent "$INSPECTION_HOME/webapp" 2>/dev/null || true

echo ""
echo "[3/4] DB index + seed (192.168.1.0/24 demo) + bump + 重啟"
sudo -u sysinfra python3 -c "
import sys; sys.path.insert(0, '$INSPECTION_HOME/webapp')
from services.subnet_service import ensure_indexes, list_subnets, create_subnet
ensure_indexes()
existing = list_subnets()
if not any(s['cidr'] == '192.168.1.0/24' for s in existing):
    create_subnet({'cidr': '192.168.1.0/24', 'vlan': 1, 'env': '測試', 'location': 'LAB機房', 'purpose': '測試主網段', 'gateway': '192.168.1.1'}, who='install')
    print('      seed 192.168.1.0/24 OK')
else:
    print('      192.168.1.0/24 已存在')
"
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): IPAM 簡化版 (P3 CMDB) — (1) services/subnet_service.py: subnets CRUD + compute_usage(用 ipaddress 比對 hosts.ips/ip 算使用率) + next_available_ip (2) /admin/subnets 頁: 表格列 8 欄 (CIDR/VLAN/環境/地點/用途/使用率 bar/Gateway/操作), 點 IP 表 開右側 drawer 看已用 IP 與下一可用 IP, Add/Edit/Delete modal (3) navbar 加 🌐 IPAM 入口 (4) seed 192.168.1.0/24 demo (4 台主機 IP 自動算進使用率) (5) API: GET/POST /subnets, GET/PUT/DELETE /subnets/<cidr>"] + d["changelog"]
with open(fp,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2)
PYEOF
systemctl restart itagent-web && sleep 2 && systemctl restart itagent-tunnel
echo "      web=$(systemctl is-active itagent-web) tunnel=$(systemctl is-active itagent-tunnel)"

echo ""
echo "[4/4] smoke + contract"
set +e
ALL_OK=true
for u in /login /admin/subnets; do
    H=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:5000$u")
    echo "  $u = $H"
    case "$H" in 200|302) ;; *) ALL_OK=false ;; esac
done
sudo -u sysinfra python3 <<PYEOF
import sys; sys.path.insert(0, "$INSPECTION_HOME/webapp")
from services.subnet_service import list_subnets, compute_usage, next_available_ip
subs = list_subnets()
print(f"  contract: list_subnets() {len(subs)} 段")
assert len(subs) >= 1, "應至少有 192.168.1.0/24"
demo = next((s for s in subs if s["cidr"] == "192.168.1.0/24"), None)
assert demo, "demo subnet not found"
assert demo["used"] >= 4, f"demo subnet used={demo['used']}, 應 >= 4 (4 台主機)"
nxt = next_available_ip("192.168.1.0/24")
assert nxt, "next_ip 算不出"
print(f"  contract: 192.168.1.0/24 used={demo['used']}/{demo['total']} ({demo['percent']}%), next_ip={nxt} ✓")
PYEOF
[ "$?" = "0" ] || ALL_OK=false
if $ALL_OK; then echo ""; echo "✅ v${PATCH_VER} smoke 全綠"; else echo ""; echo "⚠️ smoke 有紅"; fi
