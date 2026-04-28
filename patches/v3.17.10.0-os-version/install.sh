#!/bin/bash
set -e
PATCH_VER="3.17.10.0"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "FAIL"; exit 1; }
TS=$(date +%Y%m%d_%H%M%S)

# Backup
cp "$INSPECTION_HOME/webapp/templates/host_edit.html" "$INSPECTION_HOME/webapp/templates/host_edit.html.bak.${TS}"
cp "$INSPECTION_HOME/webapp/static/js/admin.js" "$INSPECTION_HOME/webapp/static/js/admin.js.bak.${TS}"

# Deploy
cp "$HERE/files/webapp/services/os_parse.py"          "$INSPECTION_HOME/webapp/services/os_parse.py"
cp "$HERE/files/webapp/templates/host_edit.html"      "$INSPECTION_HOME/webapp/templates/host_edit.html"
cp "$HERE/files/webapp/static/js/admin.js"            "$INSPECTION_HOME/webapp/static/js/admin.js"
chown -R sysinfra:itagent "$INSPECTION_HOME/webapp" 2>/dev/null || true

# Migration: 解析現有 hosts.os 拆出 os_version, 並嘗試從 inspections.os fallback
echo ""
echo "[migration] 解析現有 hosts.os ..."
sudo -u sysinfra python3 <<PYEOF
import sys
sys.path.insert(0, "$INSPECTION_HOME/webapp")
from services.mongo_service import get_collection
from services.os_parse import parse_os

hosts_col = get_collection("hosts")
ins_col = get_collection("inspections")

# 抓最新 inspection 偵測 OS
ins_pipeline = [
    {"\$sort": {"run_date": -1, "run_time": -1}},
    {"\$group": {"_id": "\$hostname", "doc": {"\$first": "\$\$ROOT"}}},
    {"\$replaceRoot": {"newRoot": "\$doc"}},
    {"\$project": {"_id": 0, "hostname": 1, "os": 1}},
]
ins_map = {d["hostname"]: d.get("os","") for d in ins_col.aggregate(ins_pipeline) if d.get("hostname")}

updated = 0
unparsed = []
for h in hosts_col.find({}):
    cur_os = h.get("os","") or ""
    cur_ver = h.get("os_version","") or ""
    family, ver = parse_os(cur_os)
    # 若還是空 version 而且有 inspection 偵測 → 試解 inspections.os
    if not ver and h.get("hostname") in ins_map:
        f2, v2 = parse_os(ins_map[h["hostname"]])
        if v2:
            ver = v2
            if not family or family == cur_os:
                family = f2
    set_doc = {}
    if family and family != cur_os:
        set_doc["os"] = family
    if ver and ver != cur_ver:
        set_doc["os_version"] = ver
    elif "os_version" not in h:
        set_doc["os_version"] = cur_ver or ""
    if set_doc:
        hosts_col.update_one({"_id": h["_id"]}, {"\$set": set_doc})
        updated += 1
    if not ver and cur_os:
        unparsed.append(cur_os)

print(f"  {updated} 台主機 os/os_version 更新")
if unparsed:
    print(f"  解不出版本: {len(unparsed)} 台 (請手動填), 樣本: {unparsed[:5]}")
PYEOF

# bump version
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): hosts 加 os_version 欄位 + 解析雜亂 os 字串 — (1) services/os_parse.py: 認 Rocky/RHEL/CentOS/Debian/Ubuntu/Windows Server/AIX/SLES/Oracle/Alpine/AS400/Fortios/Cisco IOS, regex 抽 family + version (2) migration 自動解析既有 hosts.os, 拆成 os(family) + os_version (3) 解不出版本的從最新 inspections.os fallback (4) 編輯頁加 OS 版本 input (5) 主機列表 OS 欄顯示 family + version 組合"] + d["changelog"]
with open(fp,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2)
PYEOF

SERVICE=""
for svc in itagent-web itagent inspection-web; do
    systemctl list-unit-files | grep -q "^$svc" && SERVICE="$svc" && break
done
systemctl restart "$SERVICE" && sleep 2

set +e
HTTP=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:5000/login)
echo ""
echo "[smoke] /login=$HTTP"
sudo -u sysinfra python3 <<PYEOF
import sys; sys.path.insert(0, "$INSPECTION_HOME/webapp")
from services.os_parse import parse_os
tests = [("Rocky Linux 9.7", ("Rocky Linux", "9.7")), ("Debian 13", ("Debian", "13")), ("Windows Server 2019", ("Windows Server", "2019")), ("RHEL 9.4", ("RHEL", "9.4"))]
for s, exp in tests:
    got = parse_os(s)
    ok = "✓" if got == exp else "✗"
    print(f"  {ok} parse_os({s!r}) = {got}")
PYEOF
echo "[OK] v$PATCH_VER 完成"
