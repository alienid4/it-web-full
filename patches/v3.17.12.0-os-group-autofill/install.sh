#!/bin/bash
# v3.17.12.0 — os_group autofill + 修既有空 os_group 主機
# 目標: NMON 排程頁不再全部「不支援 (?)」
set -e

PATCH_VER="3.17.12.0"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)

# ---------- 1. 偵測 INSPECTION_HOME ----------
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
if [ -z "$INSPECTION_HOME" ]; then
    echo "[FAIL] 找不到 inspection 目錄 (試過 /opt/inspection /seclog/AI/inspection)"
    exit 1
fi
echo "[INFO] INSPECTION_HOME=$INSPECTION_HOME"

# ---------- 2. 備份既有檔案 ----------
backup() {
    local f="$1"
    if [ -f "$f" ]; then
        cp "$f" "${f}.bak.${TS}"
        echo "[BACKUP] $f → ${f}.bak.${TS}"
    fi
}
backup "$INSPECTION_HOME/webapp/services/os_parse.py"
backup "$INSPECTION_HOME/webapp/routes/api_admin.py"
backup "$INSPECTION_HOME/webapp/templates/admin.html"
backup "$INSPECTION_HOME/webapp/static/js/admin.js"
backup "$INSPECTION_HOME/scripts/csv_to_inventory.py"

# ---------- 3. 部署新檔 ----------
install_file() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    chown sysinfra:itagent "$dst" 2>/dev/null || true
    chmod 644 "$dst"
    echo "[INSTALL] $dst"
}
install_file "$HERE/files/webapp/services/os_parse.py"   "$INSPECTION_HOME/webapp/services/os_parse.py"
install_file "$HERE/files/webapp/routes/api_admin.py"    "$INSPECTION_HOME/webapp/routes/api_admin.py"
install_file "$HERE/files/webapp/templates/admin.html"   "$INSPECTION_HOME/webapp/templates/admin.html"
install_file "$HERE/files/webapp/static/js/admin.js"     "$INSPECTION_HOME/webapp/static/js/admin.js"
install_file "$HERE/files/scripts/csv_to_inventory.py"   "$INSPECTION_HOME/scripts/csv_to_inventory.py"
install_file "$HERE/files/scripts/fix_os_group.py"       "$INSPECTION_HOME/scripts/fix_os_group.py"
install_file "$HERE/files/scripts/probe_os.py"           "$INSPECTION_HOME/scripts/probe_os.py"
chmod +x "$INSPECTION_HOME/scripts/fix_os_group.py" "$INSPECTION_HOME/scripts/probe_os.py" 2>/dev/null || true

# 確認 markupsafe 等套件權限 (memory 學乖, 怕 sysinfra import 失敗)
for d in /usr/local/lib/python3.*/site-packages /usr/local/lib64/python3.*/site-packages; do
    [ -d "$d" ] && chmod -R a+rX "$d" 2>/dev/null || true
done

# ---------- 4. bump version.json ----------
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp, encoding="utf-8") as f:
    d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
note = "$PATCH_VER - $(date +%Y-%m-%d): os_group 自動補齊 (兩條路) — (主路) probe_os.py 走 ansible setup module 連目標主機真實抓 ansible_distribution+version 寫回 hosts; admin UI 加「🔄 重新偵測 OS」按鈕 (POST /api/admin/hosts/probe-os); install.sh 部署完自動跑一次. (備援) os_parse 加 family_to_group/infer_os_group; api_admin add_host/edit_host/import_csv 三個 hook 點走 _autofill_os_fields 從 OS 字串推; csv_to_inventory OS_MAP 加 RedHat/AlmaLinux/Oracle Linux 兜底; fix_os_group.py 修既有空欄位. — 修復 v3.17.11.0 把 v3.17.10.1 hook 蓋掉造成 NMON 全主機「不支援」"
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
if [ -n "$SERVICE" ]; then
    systemctl restart "$SERVICE"
    echo "[RESTART] $SERVICE"
    # 等 worker 起來 (memory 學乖: sleep 3 太緊, 用 retry)
    for i in 1 2 3 4 5; do
        sleep 2
        HTTP=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:5000/login 2>/dev/null || echo "000")
        [ "$HTTP" = "200" ] && break
    done
    echo "[HTTP /login] $HTTP (try $i)"
else
    echo "[WARN] 找不到 systemd service, 跳過 restart"
fi

# ---------- 6a. 後援: 從 OS 字串解析補既有空欄位 (沒 ansible 連線也能跑) ----------
echo ""
echo "========== Step 6a: 字串解析後援 (fix_os_group.py) =========="
INSPECTION_HOME="$INSPECTION_HOME" sudo -u sysinfra python3 "$INSPECTION_HOME/scripts/fix_os_group.py" || \
    INSPECTION_HOME="$INSPECTION_HOME" python3 "$INSPECTION_HOME/scripts/fix_os_group.py"

# ---------- 6b. 主路: ansible 連目標主機抓真實 OS (蓋過字串解析結果) ----------
echo ""
echo "========== Step 6b: ansible probe 真實 OS (probe_os.py) =========="
if command -v ansible >/dev/null 2>&1; then
    INSPECTION_HOME="$INSPECTION_HOME" sudo -u sysinfra python3 "$INSPECTION_HOME/scripts/probe_os.py" 2>&1 | tee /tmp/probe_os_${TS}.log || \
        INSPECTION_HOME="$INSPECTION_HOME" python3 "$INSPECTION_HOME/scripts/probe_os.py" 2>&1 | tee /tmp/probe_os_${TS}.log
    echo "  (詳細輸出已存 /tmp/probe_os_${TS}.log)"
else
    echo "[WARN] 沒裝 ansible, 跳過 probe (主機 os_group 保留 fix_os_group.py 的字串解析結果)"
fi

# ---------- 7. Smoke tests ----------
echo ""
echo "========== Smoke Test =========="

# (a) HTTP
[ "$HTTP" = "200" ] && echo "  [OK]   HTTP /login = 200" || echo "  [FAIL] HTTP /login = $HTTP"

# (b) Python import + 真調用
python3 <<PYEOF
import sys
sys.path.insert(0, "$INSPECTION_HOME/webapp")
try:
    from services.os_parse import parse_os, family_to_group, infer_os_group
except ImportError as e:
    print(f"  [FAIL] import os_parse 失敗: {e}")
    sys.exit(1)

cases = [
    ("RedHat 9.4",                ("RHEL", "9.4"),         "rhel"),
    ("Red Hat Enterprise Linux 8.6", ("RHEL", "8.6"),      "rhel"),
    ("Rocky Linux 9.5",           ("Rocky Linux", "9.5"),  "rocky"),
    ("AlmaLinux 9",               ("Rocky Linux", "9"),    "rocky"),
    ("Oracle Linux 8",            ("Oracle Linux", "8"),   "rhel"),
    ("Debian 12",                 ("Debian", "12"),        "debian"),
    ("AIX 7.2",                   ("AIX", "7.2"),          "aix"),
    ("Win 2019",                  ("Windows Server", "2019"), "windows"),
]
fails = 0
for s, exp_parse, exp_grp in cases:
    got_parse = parse_os(s)
    got_grp = infer_os_group(s)
    ok_parse = got_parse == exp_parse
    ok_grp = got_grp == exp_grp
    flag = "OK" if (ok_parse and ok_grp) else "FAIL"
    if not (ok_parse and ok_grp):
        fails += 1
    print(f"  [{flag}] {s!r:42s} → parse={got_parse} group={got_grp!r}")
sys.exit(0 if fails == 0 else 2)
PYEOF
PY_RC=$?
[ "$PY_RC" = "0" ] && echo "  [OK]   Python smoke 全綠" || echo "  [FAIL] Python smoke 有 $PY_RC 個案例失敗"

# (c) MongoDB 統計 NMON 可勾主機數
MONGO_CMD=""
for c in mongosh mongo; do
    command -v "$c" >/dev/null 2>&1 && MONGO_CMD="$c" && break
done
if [ -n "$MONGO_CMD" ]; then
    echo "  [INFO] 用 $MONGO_CMD 查 hosts 統計"
    "$MONGO_CMD" inspection --quiet --eval '
        const supported = ["rocky","rhel","centos","debian","ubuntu","aix","linux"];
        const total = db.hosts.countDocuments({});
        const ok = db.hosts.countDocuments({os_group: {$in: supported}});
        const blank = db.hosts.countDocuments({$or: [{os_group: {$exists: false}}, {os_group: ""}, {os_group: null}, {os_group: "unknown"}]});
        print("  NMON 可勾選 = " + ok + " / " + total + " (空/unknown 還剩 " + blank + ")");
    ' 2>/dev/null || echo "  [WARN] mongosh 查詢失敗 (服務可能未啟動或權限不足)"
else
    echo "  [WARN] 沒有 mongosh/mongo, 跳過 DB 統計 (公司 13/11 環境注意)"
fi

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
journalctl -u "$SERVICE" -n 5 --no-pager 2>/dev/null || \
    tail -5 "$INSPECTION_HOME/logs/web.log" 2>/dev/null || \
    echo "  (找不到 log)"

echo ""
echo "[DONE] v$PATCH_VER 部署完成"
echo "       下一步:"
echo "         1) F5 重整 Web → 系統管理 → 監控平台管理 → 應該不再「不支援」"
echo "         2) 之後新加主機, 在該頁按「🔄 重新偵測 OS」即可 (走 ansible 真實抓)"
echo "         3) 連不上的主機 (sysinfra 沒設 sudo NOPASSWD), 看 /tmp/probe_os_${TS}.log 裡 [OFF] 標記"
