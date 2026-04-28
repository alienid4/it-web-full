#!/bin/bash
# v3.15.5.0 hosts 29 欄資產表對齊 - install.sh
# 1. 備份 hosts collection
# 2. 跑 migration: 加 5 欄 + 補 secansible/WIN 缺資料
# 3. bump version.json

set -e

PATCH_VER="3.15.5.0"
HERE="$(cd "$(dirname "$0")" && pwd)"

# auto-detect INSPECTION_HOME
INSPECTION_HOME=""
for p in /seclog/AI/inspection /opt/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "[FAIL] 找不到 INSPECTION_HOME"; exit 1; }
echo "[i] INSPECTION_HOME=$INSPECTION_HOME"

# Step 1/3: 備份 hosts collection (mongoexport)
TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/backups/inspection/hosts"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/hosts_pre_v${PATCH_VER}_${TS}.json"
echo ""
echo "[1/3] 備份 hosts collection 到 $BACKUP_FILE"
podman exec mongodb mongoexport --db inspection --collection hosts --out "/tmp/hosts_backup.json" 2>&1 | tail -3
podman cp mongodb:/tmp/hosts_backup.json "$BACKUP_FILE"
echo "      $(wc -l < "$BACKUP_FILE") 筆主機已備份"

# Step 2/3: 跑 migration
echo ""
echo "[2/3] 跑 migration (加 5 欄 + 補 secansible/WIN 缺資料)"
python3 "$HERE/migration_add_29_fields.py"

# Step 3/3: bump version.json
echo ""
echo "[3/3] bump version.json"
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp, encoding="utf-8") as f:
    d = json.load(f)
old = d.get("version")
new_entry = "$PATCH_VER - $(date +%Y-%m-%d): hosts collection 對齊 29 欄資產表 - 加 5 個缺欄位 (device_model/rack_no/quantity/hardware_seq/sys_admin) + 補 secansible/WIN-7L4JNM4P2KN best-guess 資產資料 (你可在 UI 修正)"
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = [new_entry] + d.get("changelog", [])
with open(fp, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print(f"      version.json: {old} -> $PATCH_VER")
PYEOF

echo ""
echo "[OK] v${PATCH_VER} install 完成"
echo "[i] 備份: $BACKUP_FILE"
echo "[i] 不需要重啟服務 (純 DB 改動)"
echo ""
echo "驗證: 開瀏覽器 → admin → 主機清單,看 secansible/WIN 多了資產欄位"
