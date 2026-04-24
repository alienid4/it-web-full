#!/bin/bash
###############################################
#  v3.12.0.0-vmware-tab-w1 installer
#  VMware 管理 tab W1 MVP (mock data 版)
#
#  動作:
#    1. 新增 api_vmware blueprint + vmware.html + vmware.css + vmware_mock.py
#    2. 在 base.html nav 插 VMware 入口 (TWGCB 後面)
#    3. 在 app.py 註冊 vmware_bp
#    4. 更新 data/version.json (prepend changelog, 版號 → 3.12.0.0)
#    5. 重啟 itagent-web
#    6. HTTP 驗證 /vmware 可達
#
#  Usage: sudo ./install.sh
###############################################
set -u
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}OK${NC}   $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; exit 1; }
info() { echo -e "  ${CYAN}-->${NC}  $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/files"
TS=$(date +%Y%m%d_%H%M%S)

# ========== [0] 前置 ==========
echo ""
echo -e "${CYAN}+===============================================+${NC}"
echo -e "${CYAN}|  v3.12.0.0-vmware-tab-w1 (MVP + mock data)   |${NC}"
echo -e "${CYAN}+===============================================+${NC}"
[ "$(id -u)" -eq 0 ] || fail "需 root / sudo"

# 偵測 inspection home (221 家裡 /seclog/AI/inspection; 13 /opt/inspection)
if [ -n "${INSPECTION_HOME:-}" ]; then
    HOME_DIR="$INSPECTION_HOME"
elif [ -f "/opt/inspection/data/version.json" ]; then
    HOME_DIR="/opt/inspection"
elif [ -f "/seclog/AI/inspection/data/version.json" ]; then
    HOME_DIR="/seclog/AI/inspection"
else
    fail "找不到 inspection home (/opt/inspection 或 /seclog/AI/inspection)"
fi
info "inspection home: $HOME_DIR"

BACKUP_DIR="/var/backups/inspection/pre_v3.12.0.0-vmware-tab-w1_${TS}"

# 檢查 patch 檔案齊全
for f in \
    "$SRC_DIR/webapp/routes/api_vmware.py" \
    "$SRC_DIR/webapp/templates/vmware.html" \
    "$SRC_DIR/webapp/services/vmware_mock.py" \
    "$SRC_DIR/webapp/static/css/vmware.css" \
    "$SCRIPT_DIR/CHANGELOG_ENTRY.txt"; do
    [ -f "$f" ] || fail "缺 patch 檔: $f"
done
ok "patch 檔齊全"

# 檢查目標檔案存在
for f in \
    "$HOME_DIR/webapp/app.py" \
    "$HOME_DIR/webapp/templates/base.html" \
    "$HOME_DIR/data/version.json"; do
    [ -f "$f" ] || fail "目標缺檔: $f (inspection home 對嗎?)"
done

CUR_VER=$(python3 -c "import json; print(json.load(open('$HOME_DIR/data/version.json'))['version'])" 2>/dev/null || echo "unknown")
info "當前版本: $CUR_VER"

# 檢查 pyvmomi prereq 是否已裝 (W1 目前 mock 不需要, 但提醒)
if ! python3 -c "import pyVmomi" 2>/dev/null; then
    warn "pyvmomi 尚未安裝. 目前 W1 走 mock 不需要, 但接真 VC 增量前要先套 v3.12.0.0-vmware-prereq"
fi

# ========== [1] 備份 ==========
echo -e "${BOLD}[1/7] 備份${NC}"
mkdir -p "$BACKUP_DIR"
cp -p "$HOME_DIR/webapp/app.py" "$BACKUP_DIR/" && ok "app.py → bak"
cp -p "$HOME_DIR/webapp/templates/base.html" "$BACKUP_DIR/" && ok "base.html → bak"
cp -p "$HOME_DIR/data/version.json" "$BACKUP_DIR/" && ok "version.json → bak"
info "備份: $BACKUP_DIR"

# ========== [2] 複製新檔 ==========
echo -e "${BOLD}[2/7] 複製新檔${NC}"
OWNER=$(stat -c "%U:%G" "$HOME_DIR/webapp/app.py")
info "檔案 owner: $OWNER"

mkdir -p "$HOME_DIR/webapp/services"
mkdir -p "$HOME_DIR/webapp/static/css"

cp "$SRC_DIR/webapp/routes/api_vmware.py" "$HOME_DIR/webapp/routes/" && chown "$OWNER" "$HOME_DIR/webapp/routes/api_vmware.py" && ok "api_vmware.py (新)"
cp "$SRC_DIR/webapp/templates/vmware.html" "$HOME_DIR/webapp/templates/" && chown "$OWNER" "$HOME_DIR/webapp/templates/vmware.html" && ok "vmware.html (新)"
cp "$SRC_DIR/webapp/services/vmware_mock.py" "$HOME_DIR/webapp/services/" && chown "$OWNER" "$HOME_DIR/webapp/services/vmware_mock.py" && ok "vmware_mock.py (新)"
cp "$SRC_DIR/webapp/static/css/vmware.css" "$HOME_DIR/webapp/static/css/" && chown "$OWNER" "$HOME_DIR/webapp/static/css/vmware.css" && ok "vmware.css (新)"

# ========== [3] Python 語法驗證 ==========
echo -e "${BOLD}[3/7] Python 語法驗證${NC}"
python3 -c "import ast; ast.parse(open('$HOME_DIR/webapp/routes/api_vmware.py').read())" 2>&1 || fail "api_vmware.py 語法錯"
python3 -c "import ast; ast.parse(open('$HOME_DIR/webapp/services/vmware_mock.py').read())" 2>&1 || fail "vmware_mock.py 語法錯"
ok "py 語法通過"

# ========== [4] 插入 base.html nav ==========
echo -e "${BOLD}[4/7] 插入 base.html nav${NC}"
python3 <<PYEOF || fail "base.html 注入 nav 失敗"
import re
p = "$HOME_DIR/webapp/templates/base.html"
s = open(p).read()

# idempotent: 已有就跳過
if 'id="nav-vmware"' in s:
    print("  already has vmware nav, skip")
else:
    # 找 TWGCB 那行, 在後面插入 VMware
    marker = '<li><a href="/twgcb" id="nav-twgcb">'
    if marker not in s:
        # fallback: 找 admin nav 前面
        marker_alt = '<li><a href="/admin"'
        if marker_alt not in s:
            raise SystemExit("找不到 nav 錨點 (TWGCB 或 admin)")
        # 在 admin 前插
        new_li = '<li><a href="/vmware" id="nav-vmware">🖥️ VMware 管理</a></li>\n      '
        s = s.replace(marker_alt, new_li + marker_alt, 1)
    else:
        # 在 TWGCB 那整行 li 結束後插
        idx = s.index(marker)
        li_end = s.index('</li>', idx) + len('</li>')
        insert = '\n      <li><a href="/vmware" id="nav-vmware">🖥️ VMware 管理</a></li>'
        s = s[:li_end] + insert + s[li_end:]
    open(p, 'w').write(s)
    print("  nav 插入完成")
PYEOF
ok "base.html nav OK"

# ========== [5] 註冊 blueprint 到 app.py ==========
echo -e "${BOLD}[5/7] 註冊 vmware_bp 到 app.py${NC}"
python3 <<PYEOF || fail "app.py 註冊 blueprint 失敗"
p = "$HOME_DIR/webapp/app.py"
s = open(p).read()

# idempotent: 已有就跳過
if 'api_vmware' in s:
    print("  already registered, skip")
else:
    # 找最後一個 import bp as XXX_bp 的位置
    import re
    m = list(re.finditer(r'from routes\.\w+ import bp as \w+_bp\n', s))
    if not m:
        raise SystemExit("找不到 blueprint import 錨點")
    last_import = m[-1]
    inject = "from routes.api_vmware import bp as vmware_bp\n"
    s = s[:last_import.end()] + inject + s[last_import.end():]

    # 找最後一個 register_blueprint
    m2 = list(re.finditer(r'app\.register_blueprint\(\w+_bp\)\n', s))
    if not m2:
        raise SystemExit("找不到 register_blueprint 錨點")
    last_reg = m2[-1]
    inject2 = "app.register_blueprint(vmware_bp)\n"
    s = s[:last_reg.end()] + inject2 + s[last_reg.end():]

    open(p, 'w').write(s)
    print("  blueprint 註冊完成")
PYEOF

# 驗證 app.py 語法仍然 OK
python3 -c "import ast; ast.parse(open('$HOME_DIR/webapp/app.py').read())" 2>&1 || fail "app.py 修改後語法錯! 從 $BACKUP_DIR 還原"
ok "blueprint 註冊 OK"

# ========== [6] 更新 version.json (prepend changelog) ==========
echo -e "${BOLD}[6/7] 更新 version.json${NC}"
python3 <<PYEOF || fail "version.json 更新失敗"
import json, datetime
p = "$HOME_DIR/data/version.json"
d = json.load(open(p))
new_entry = open("$SCRIPT_DIR/CHANGELOG_ENTRY.txt").read().strip()

# idempotent: 已經包含此版本的 entry 就不重加
if any(e.startswith("3.12.0.0 ") for e in d.get("changelog", [])):
    print("  changelog already has 3.12.0.0, skip prepend")
else:
    d.setdefault("changelog", []).insert(0, new_entry)

d["version"] = "3.12.0.0"
d["updated_at"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
print("  version.json → 3.12.0.0")
PYEOF
chown "$OWNER" "$HOME_DIR/data/version.json"
ok "version.json OK"

# ========== [7] 重啟 + 驗證 ==========
echo -e "${BOLD}[7/7] 重啟 + 驗證${NC}"
RESTARTED=0
for svc in itagent-web inspection inspection-web; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" && ok "systemctl restart $svc" && RESTARTED=1 && break
    fi
done
[ "$RESTARTED" -eq 1 ] || warn "沒偵測到 Flask service, 請手動重啟"
sleep 3

# HTTP 驗證
NEW_VERSION=$(python3 -c "import json; print(json.load(open('$HOME_DIR/data/version.json'))['version'])" 2>/dev/null || echo "?")
[ "$NEW_VERSION" = "3.12.0.0" ] && ok "版本 $NEW_VERSION ✅" || warn "版本異常: $NEW_VERSION"

HTTP_VM=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5000/vmware" 2>/dev/null || echo "000")
case "$HTTP_VM" in
    200|302|401) ok "/vmware $HTTP_VM (頁面路由載入成功)" ;;
    *) warn "/vmware $HTTP_VM (非預期, 可能要手動重啟 flask)" ;;
esac

# Python import 測試 (blueprint 真的載入)
sudo -u "$(echo $OWNER | cut -d: -f1)" bash -c "cd $HOME_DIR/webapp && python3 -c \"from routes.api_vmware import bp; from services.vmware_mock import get_overview_data; d=get_overview_data(); print('endpoints:', len([r for r in bp.deferred_functions]), '| mock keys:', list(d.keys())[:5])\"" 2>&1 | grep -q "endpoints:" && ok "blueprint + mock 載入通過" || warn "import 測試有異常, 檢查 $BACKUP_DIR"

echo ""
echo -e "${GREEN}${BOLD}╔═════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  v3.12.0.0 W1 VMware tab MVP 完成!          ║${NC}"
echo -e "${GREEN}${BOLD}╚═════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}瀏覽器測試 (Ctrl+Shift+R 強制重載)${NC}:"
echo "  1. 打開巡檢系統 (221 家裡走本機 / 13 公司走你平常網址)"
echo "  2. 登入 → nav 應該看到 🖥️ VMware 管理 (在 TWGCB 後)"
echo "  3. 點進去 → 應該看到：橘色 mock banner + 綠色圓環「整體狀態正常」"
echo "  4. 下方綠色漸層卡「2026-03 月報已產生」+ 4 個按鈕 (W2 才實作下載)"
echo "  5. 再下方 Cluster chip + 本月風險 sidebar + 底部 VC 資料源條"
echo ""
echo -e "${BOLD}下一增量${NC}:"
echo "  - W1 接真 VC: 寫 collector/vcenter_collector.py 讀 vault 加密的 VC 帳密, 8H 排程"
echo "  - W2 月報 PPT: python-pptx 產出 6 頁主管版 PPT"
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo "  cd $BACKUP_DIR"
echo "  sudo cp -p app.py base.html version.json $HOME_DIR/webapp/  (注意路徑: base.html → templates/, version.json → data/)"
echo "  sudo rm $HOME_DIR/webapp/routes/api_vmware.py"
echo "  sudo rm $HOME_DIR/webapp/templates/vmware.html"
echo "  sudo rm $HOME_DIR/webapp/services/vmware_mock.py"
echo "  sudo rm $HOME_DIR/webapp/static/css/vmware.css"
echo "  sudo systemctl restart itagent-web"
