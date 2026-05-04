#!/bin/bash
# v3.17.13.0 — NMON 部署狀態驗證面板
# 新功能: admin perf-mgmt tab 加「📊 NMON 部署狀態」card, 一鍵看所有勾選主機
#         的 cron / nmon binary / 最近 .nmon 檔 / nmon process / DB 今日筆數
set -e

PATCH_VER="3.17.13.0"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)

# ---------- 1. 偵測 INSPECTION_HOME ----------
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
if [ -z "$INSPECTION_HOME" ]; then
    echo "[FAIL] 找不到 inspection 目錄"
    exit 1
fi
echo "[INFO] INSPECTION_HOME=$INSPECTION_HOME"

# ---------- 2. 備份 ----------
backup() {
    [ -f "$1" ] && cp "$1" "${1}.bak.${TS}" && echo "[BACKUP] $1 → ${1}.bak.${TS}"
}
backup "$INSPECTION_HOME/webapp/routes/api_nmon.py"
backup "$INSPECTION_HOME/webapp/templates/admin.html"
backup "$INSPECTION_HOME/webapp/static/js/admin.js"

# ---------- 3. 部署新檔 ----------
install_file() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    chown sysinfra:itagent "$dst" 2>/dev/null || true
    chmod 644 "$dst"
    echo "[INSTALL] $dst"
}
install_file "$HERE/files/webapp/routes/api_nmon.py"   "$INSPECTION_HOME/webapp/routes/api_nmon.py"
install_file "$HERE/files/webapp/templates/admin.html" "$INSPECTION_HOME/webapp/templates/admin.html"
install_file "$HERE/files/webapp/static/js/admin.js"   "$INSPECTION_HOME/webapp/static/js/admin.js"
install_file "$HERE/files/scripts/verify_nmon.py"      "$INSPECTION_HOME/scripts/verify_nmon.py"
chmod +x "$INSPECTION_HOME/scripts/verify_nmon.py" 2>/dev/null || true

# ---------- 4. bump version.json ----------
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp, encoding="utf-8") as f:
    d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
note = "$PATCH_VER - $(date +%Y-%m-%d): NMON 部署狀態驗證面板 — admin 系統管理 → 監控平台管理 → 效能月報管理 → 拉到下方「📊 NMON 部署狀態」card → 「🔍 立即檢查」按鈕一鍵看所有勾選主機的 cron/nmon binary/最近 .nmon 檔/nmon process 4 項狀態 + nmon_daily DB 今日筆數. 新增 scripts/verify_nmon.py (ansible -m shell 一次跑 4 項檢查 + DB 統計) + GET /api/nmon/verify endpoint (sync 200s timeout). 表格顯示 🟢 OK / 🟡 PARTIAL / 🔴 FAIL / ⚫ UNREACHABLE 四種狀態 + 細節欄. 配套 ~/.claude/skills/nmon-verify/SKILL.md 讓 Claude 下次能主動引導使用者用此面板."
d["changelog"] = [note] + d.get("changelog", [])
with open(fp, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print(f"[VERSION] bumped to $PATCH_VER")
PYEOF

# ---------- 5. restart service ----------
SERVICE=""
for svc in itagent-web itagent inspection-web; do
    systemctl list-unit-files | grep -q "^${svc}\." && SERVICE="$svc" && break
done
HTTP="000"
if [ -n "$SERVICE" ]; then
    systemctl restart "$SERVICE"
    echo "[RESTART] $SERVICE"
    for i in 1 2 3 4 5; do
        sleep 2
        HTTP=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:5000/login 2>/dev/null || echo "000")
        [ "$HTTP" = "200" ] && break
    done
    echo "[HTTP /login] $HTTP (try $i)"
fi

# ---------- 6. Smoke ----------
echo ""
echo "========== Smoke Test =========="

# (a) HTTP
[ "$HTTP" = "200" ] && echo "  [OK]   HTTP /login = 200" || echo "  [FAIL] HTTP /login = $HTTP"

# (b) Python import + 真調用 verify_nmon.py 裡關鍵 function
python3 <<PYEOF
import sys
sys.path.insert(0, "$INSPECTION_HOME/webapp")
sys.path.insert(0, "$INSPECTION_HOME/scripts")
try:
    from services.mongo_service import get_hosts_col, get_collection
    print("  [OK]   import mongo_service.get_hosts_col / get_collection")
except Exception as e:
    print(f"  [FAIL] import mongo_service: {e}"); sys.exit(1)

# verify_nmon 純 import
import importlib.util
spec = importlib.util.spec_from_file_location("verify_nmon", "$INSPECTION_HOME/scripts/verify_nmon.py")
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
    assert callable(mod.parse_check_output) and callable(mod.run_ansible_check)
    print("  [OK]   verify_nmon.py import + parse_check_output/run_ansible_check OK")
except Exception as e:
    print(f"  [FAIL] verify_nmon.py: {e}"); sys.exit(1)
PYEOF
PY_RC=$?

# (c) verify_nmon.py 真跑一次 (即使 nmon_enabled=0 也應該回 JSON 不爆)
echo ""
echo "  [INFO] 試跑 verify_nmon.py --json:"
INSPECTION_HOME="$INSPECTION_HOME" python3 "$INSPECTION_HOME/scripts/verify_nmon.py" --json 2>&1 | head -20

# (d) systemd 狀態
[ -n "$SERVICE" ] && {
    if systemctl is-active --quiet "$SERVICE"; then
        echo "  [OK]   systemctl is-active $SERVICE"
    else
        echo "  [FAIL] systemctl is-active $SERVICE"
    fi
}

# (e) log 末 5 行
echo ""
echo "========== Service log 末 5 行 =========="
journalctl -u "$SERVICE" -n 5 --no-pager 2>/dev/null || tail -5 "$INSPECTION_HOME/logs/web.log" 2>/dev/null || echo "(無 log)"

echo ""
echo "[DONE] v$PATCH_VER 部署完成"
echo "       下一步:"
echo "         1) F5 重整 Web → 系統管理 → 監控平台管理 → 效能月報管理"
echo "         2) 拉到下方「📊 NMON 部署狀態」card → 按「🔍 立即檢查」"
echo "         3) 30~60 秒看到表格: 🟢 OK / 🟡 部分 / 🔴 失敗 / ⚫ 連不上"
