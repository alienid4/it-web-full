#!/bin/bash
set -e
PATCH_VER="3.15.7.1"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSPECTION_HOME=""
for p in /seclog/AI/inspection /opt/inspection; do
  [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "FAIL"; exit 1; }
TS=$(date +%Y%m%d_%H%M%S)
cp "$INSPECTION_HOME/webapp/templates/host_edit.html" "$INSPECTION_HOME/webapp/templates/host_edit.html.bak.${TS}"
cp "$HERE/files/webapp/templates/host_edit.html" "$INSPECTION_HOME/webapp/templates/host_edit.html"
chown sysinfra:itagent "$INSPECTION_HOME/webapp/templates/host_edit.html" 2>/dev/null || true
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp, encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): 主機編輯頁精簡 — 拿掉 7 個多餘欄位 (SNMP Community/使用單位/AP負責人/級別tier/系統別/架構說明/群組legacy), 留 29 資產表 + os_group = 30 欄。DB 資料保留, 只是 UI 不顯示 (未來想再加可從備份還原)"] + d["changelog"]
with open(fp, "w", encoding="utf-8") as f: json.dump(d, f, ensure_ascii=False, indent=2)
PYEOF
systemctl restart itagent-web && sleep 2 && systemctl restart itagent-tunnel
echo "OK v$PATCH_VER 完成 — web=$(systemctl is-active itagent-web)"
