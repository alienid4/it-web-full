#!/bin/bash
# v3.17.14.0 — NMON 離線 RPM 派送
# 解決公司隔離環境 EPEL 不通, nmon binary 裝不起來的問題
#
# 前提: 已部署 v3.17.13.0 (NMON 部署驗證面板)
# 部署: bash install.sh
set -e

PATCH_VER="3.17.14.0"
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

# ---------- 2. 確認 v3.17.13.0 已部署 (此 patch 假設 verify panel 存在) ----------
if ! grep -q "verifyNmonDeployment" "$INSPECTION_HOME/webapp/static/js/admin.js" 2>/dev/null; then
    echo "[FAIL] 偵測不到 v3.17.13.0 的 verifyNmonDeployment(), 請先部署 v3.17.13.0-nmon-verify-panel"
    exit 1
fi
echo "[INFO] v3.17.13.0 已部署, 繼續"

# ---------- 3. 備份 ----------
backup() {
    [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}" && echo "[BACKUP] $1 → ${1}.bak.${TS}"
}
backup "$INSPECTION_HOME/webapp/routes/api_nmon.py"
backup "$INSPECTION_HOME/webapp/templates/admin.html"
backup "$INSPECTION_HOME/webapp/static/js/admin.js"

# ---------- 4. 部署 ansible role + playbook ----------
echo "[INFO] 部署 ansible role install_nmon_rpm"
mkdir -p "$INSPECTION_HOME/ansible/roles/install_nmon_rpm/tasks"
cp -v "$HERE/files/ansible/roles/install_nmon_rpm/tasks/main.yml" \
       "$INSPECTION_HOME/ansible/roles/install_nmon_rpm/tasks/main.yml"
cp -v "$HERE/files/ansible/playbooks/install_nmon_rpm.yml" \
       "$INSPECTION_HOME/ansible/playbooks/install_nmon_rpm.yml"
chown -R sysinfra:itagent \
    "$INSPECTION_HOME/ansible/roles/install_nmon_rpm" \
    "$INSPECTION_HOME/ansible/playbooks/install_nmon_rpm.yml" 2>/dev/null || true

# ---------- 5. 部署 offline_bundle (RPM) ----------
echo "[INFO] 部署 offline_bundle/nmon (含 RPM)"
mkdir -p "$INSPECTION_HOME/offline_bundle/nmon"
cp -v "$HERE/files/offline_bundle/nmon/"*.rpm "$INSPECTION_HOME/offline_bundle/nmon/" 2>/dev/null
chown -R sysinfra:itagent "$INSPECTION_HOME/offline_bundle/nmon" 2>/dev/null || true
ls -la "$INSPECTION_HOME/offline_bundle/nmon/"

# ---------- 6. 部署 download_nmon_rpm.sh ----------
mkdir -p "$INSPECTION_HOME/scripts"
cp -v "$HERE/files/scripts/download_nmon_rpm.sh" \
       "$INSPECTION_HOME/scripts/download_nmon_rpm.sh"
chmod +x "$INSPECTION_HOME/scripts/download_nmon_rpm.sh"
chown sysinfra:itagent "$INSPECTION_HOME/scripts/download_nmon_rpm.sh" 2>/dev/null || true

# ---------- 7. webapp api_nmon.py append 新 endpoint ----------
echo "[INFO] 加 install-rpm endpoint 到 api_nmon.py"
if grep -q "v3.17.14.0+: NMON 離線 RPM 派送 endpoint" "$INSPECTION_HOME/webapp/routes/api_nmon.py"; then
    echo "[SKIP] api_nmon.py 已有 v3.17.14.0 endpoint"
else
    cat "$HERE/files/webapp/routes/api_nmon.py.append" >> "$INSPECTION_HOME/webapp/routes/api_nmon.py"
    echo "[OK] api_nmon.py 已 append"
fi

# ---------- 8. webapp admin.js append 新 function ----------
echo "[INFO] 加 installNmonRpmFail() 到 admin.js"
if grep -q "v3.17.14.0+: NMON 離線 RPM 派送" "$INSPECTION_HOME/webapp/static/js/admin.js"; then
    echo "[SKIP] admin.js 已有 v3.17.14.0 function"
else
    cat "$HERE/files/webapp/static/js/admin.js.append" >> "$INSPECTION_HOME/webapp/static/js/admin.js"
    echo "[OK] admin.js 已 append"
fi

# ---------- 9. webapp admin.html: inject 「📦 派送 RPM」按鈕到 NMON 部署狀態 card ----------
echo "[INFO] inject 派送 RPM 按鈕到 admin.html"
python3 - "$INSPECTION_HOME/webapp/templates/admin.html" <<'PY_EOF'
import sys, re
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    html = f.read()

if "installNmonRpmFail()" in html:
    print("[SKIP] admin.html 已有 RPM 派送按鈕")
    sys.exit(0)

# 找 verifyNmonDeployment() 那行 button, 在它後面加新 button
target_line = '<button class="btn btn-primary" style="font-size:13px;padding:4px 14px;" onclick="verifyNmonDeployment()">🔍 立即檢查</button>'
new_line = '<button class="btn" style="font-size:13px;padding:4px 14px;background:var(--g2);color:white;" onclick="installNmonRpmFail()" title="對 binary 缺漏的主機派送離線 RPM 安裝 (v3.17.14.0+)">📦 派送 RPM</button>'

if target_line not in html:
    print("[FAIL] anchor 找不到 (verifyNmonDeployment button), 是否已修改過 admin.html?")
    sys.exit(1)

html = html.replace(target_line, target_line + '\n      ' + new_line, 1)

with open(path, 'w', encoding='utf-8') as f:
    f.write(html)
print("[OK] admin.html 已 inject 「📦 派送 RPM」按鈕")
PY_EOF

# ---------- 10. 更新 version.json ----------
VERSION_JSON="$INSPECTION_HOME/data/version.json"
if [ -f "$VERSION_JSON" ]; then
    cp "$VERSION_JSON" "${VERSION_JSON}.bak.${TS}"
    python3 - "$VERSION_JSON" "$PATCH_VER" <<'PY_EOF'
import json, sys, datetime
path, ver = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    j = json.load(f)
j['version'] = ver
j['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
log_entry = ver + " - " + datetime.datetime.now().strftime('%Y-%m-%d') + ": NMON 離線 RPM 派送 (補 EPEL 不通環境的 binary 安裝)"
j.setdefault('changelog', []).insert(0, log_entry)
with open(path, 'w', encoding='utf-8') as f:
    json.dump(j, f, ensure_ascii=False, indent=2)
print("[OK] version.json 升到 " + ver)
PY_EOF
fi

# ---------- 10b. workaround v3.17.13.0 bug: api_nmon.py 讀 INSPECTION_HOME 但 EnvFile 只有 ITAGENT_HOME ----------
# 沒設 INSPECTION_HOME 時 webapp /api/nmon/verify 會跑到 /opt/inspection (default) 路徑不存在, 點 UI 會「失敗 UNKNOWN」.
# 在 /etc/default/itagent 自動加 INSPECTION_HOME (跟 ITAGENT_HOME 同值), 不破壞既有設定.
ENVFILE=/etc/default/itagent
if [ -f "$ENVFILE" ] && ! grep -q "^INSPECTION_HOME=" "$ENVFILE"; then
    backup "$ENVFILE"
    echo "INSPECTION_HOME=${INSPECTION_HOME}" >> "$ENVFILE"
    echo "[FIX] 已加 INSPECTION_HOME=${INSPECTION_HOME} 到 $ENVFILE (workaround v3.17.13.0 verify panel bug)"
else
    echo "[SKIP] $ENVFILE 已有 INSPECTION_HOME 或不存在"
fi

# ---------- 11. 重啟 webapp (retry 5 次, 對應鐵律 3: sleep 不夠) ----------
echo "[INFO] 重啟 itagent-web (讓新 endpoint / JS / HTML 生效)"
if systemctl is-active itagent-web >/dev/null 2>&1; then
    systemctl restart itagent-web
    ok=0
    for i in 1 2 3 4 5; do
        sleep 2
        if systemctl is-active itagent-web >/dev/null 2>&1; then
            # 進一步用 HTTP 確認 worker 真的接得到 request (gunicorn 起來但 worker import 死的情況)
            HTTP=$(curl -sI -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:5000/login 2>/dev/null || echo 000)
            if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then
                ok=1; break
            fi
        fi
        echo "[INFO] 等待 itagent-web 啟動... ($i/5, http=${HTTP:-?})"
    done
    if [ $ok -eq 1 ]; then
        echo "[OK] itagent-web 重啟成功 (HTTP $HTTP)"
    else
        echo "[FAIL] itagent-web 沒起來 (10s timeout), 查 journalctl -u itagent-web -n 50"
        exit 1
    fi
else
    echo "[SKIP] itagent-web 未跑 (可能此環境沒 webapp, 例如純 ansible control 主機)"
fi

# ---------- 12. 驗證 ----------
echo
echo "========================================"
echo "  v3.17.14.0 部署完成"
echo "========================================"
echo "驗證步驟:"
echo "  1. 開瀏覽器 → 系統管理 → 監控平台管理 → 效能月報管理"
echo "  2. 拉到「📊 NMON 部署狀態」card"
echo "  3. 應看到「🔍 立即檢查」旁多了「📦 派送 RPM」按鈕"
echo "  4. 點「🔍 立即檢查」 → 看哪些主機 bin=✗"
echo "  5. 點「📦 派送 RPM」 → confirm → 等 1-3 分鐘"
echo "  6. 再點「🔍 立即檢查」 → 確認 bin 變 ✓"
echo
echo "備份檔 (萬一要還原):"
ls -la "${INSPECTION_HOME}"/webapp/{routes/api_nmon.py,templates/admin.html,static/js/admin.js}.bak.${TS} 2>/dev/null
echo
echo "RPM 路徑:"
ls -la "$INSPECTION_HOME/offline_bundle/nmon/"
