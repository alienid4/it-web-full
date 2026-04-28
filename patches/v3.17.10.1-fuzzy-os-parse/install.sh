#!/bin/bash
set -e
PATCH_VER="3.17.10.1"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "FAIL"; exit 1; }
TS=$(date +%Y%m%d_%H%M%S)

cp "$INSPECTION_HOME/webapp/services/os_parse.py" "$INSPECTION_HOME/webapp/services/os_parse.py.bak.${TS}"
cp "$INSPECTION_HOME/webapp/routes/api_admin.py"  "$INSPECTION_HOME/webapp/routes/api_admin.py.bak.${TS}"

cp "$HERE/files/webapp/services/os_parse.py"  "$INSPECTION_HOME/webapp/services/os_parse.py"
cp "$HERE/files/webapp/routes/api_admin.py"   "$INSPECTION_HOME/webapp/routes/api_admin.py"
chown sysinfra:itagent "$INSPECTION_HOME/webapp/services/os_parse.py" "$INSPECTION_HOME/webapp/routes/api_admin.py" 2>/dev/null || true

python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): hot-fix os_parse 容忍 typo + 接 import/edit hook — (1) os_parse.py 加 typo aliases (RHLE/RED HTA/Centosss/Debain/Ubunto/Win 等 16 種常見打錯) + Levenshtein fuzzy match (cutoff 0.65) (2) Win + 4 位年份自動歸類 Windows Server (3) import_csv / add_host / edit_host 全部 hook parse_os, 收到亂寫 OS 字串自動解析家族+版本"] + d["changelog"]
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
tests = [
    ("RHLE 9.6", ("RHEL", "9.6")),
    ("Red Hta 9.4", ("RHEL", "9.4")),
    ("Debain 13", ("Debian", "13")),
    ("Win 2019", ("Windows Server", "2019")),
]
for s, exp in tests:
    got = parse_os(s)
    print(f"  parse_os({s!r}) = {got} {'OK' if got==exp else 'FAIL'}")
PYEOF
echo "[OK] v$PATCH_VER 完成"
