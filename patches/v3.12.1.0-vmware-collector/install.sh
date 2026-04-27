#!/bin/bash
###############################################
#  v3.12.1.0-vmware-collector installer
#  接真 vCenter (pyvmomi) → MongoDB snapshot + 8H cron
#
#  動作:
#    1. 部署 collector/vcenter_collector.py
#    2. 部署 services/vmware_service.py (取代 mock fallback 路徑)
#    3. 改寫 routes/api_vmware.py → 走 vmware_service (有 MongoDB 用真資料, 沒有 fallback inline mock)
#    4. 建 data/vmware/ + vcenters.yaml.sample + README.md
#    5. 安裝 cron /etc/cron.d/inspection-vmware-collect (8H 一次)
#    6. 確認 pyvmomi prereq 已裝 (沒裝就 fail, 提示先套 v3.12.0.0-vmware-prereq)
#    7. 更新 data/version.json → 3.12.1.0 + prepend changelog
#    8. 重啟 itagent-web + HTTP 驗證
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
echo -e "${CYAN}+========================================================+${NC}"
echo -e "${CYAN}|  v3.12.1.0-vmware-collector (接真 VC + 8H cron)        |${NC}"
echo -e "${CYAN}+========================================================+${NC}"
[ "$(id -u)" -eq 0 ] || fail "需 root / sudo"

# 偵測 inspection home (13 /opt; 221 /seclog/AI)
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

BACKUP_DIR="/var/backups/inspection/pre_v3.12.1.0-vmware-collector_${TS}"

# 檢查 patch 檔案齊全
for f in \
    "$SRC_DIR/collector/vcenter_collector.py" \
    "$SRC_DIR/webapp/services/vmware_service.py" \
    "$SRC_DIR/webapp/routes/api_vmware.py" \
    "$SRC_DIR/data/vmware/vcenters.yaml.sample" \
    "$SRC_DIR/data/vmware/README.md" \
    "$SCRIPT_DIR/CHANGELOG_ENTRY.txt"; do
    [ -f "$f" ] || fail "缺 patch 檔: $f"
done
ok "patch 檔齊全"

# 檢查 v3.12.0.0-vmware-tab-w1 已套 (vmware_mock 是 fallback 必須在)
[ -f "$HOME_DIR/webapp/services/vmware_mock.py" ] || fail "vmware_mock.py 不在, 請先套 v3.12.0.0-vmware-tab-w1"
[ -f "$HOME_DIR/webapp/routes/api_vmware.py" ] || fail "api_vmware.py 不在, 請先套 v3.12.0.0-vmware-tab-w1"
ok "v3.12.0.0-vmware-tab-w1 prereq 已就緒"

# 檢查 pyvmomi (v3.12.0.0-vmware-prereq 提供)
if ! python3 -c "import pyVmomi; import yaml; from pymongo import MongoClient" 2>/dev/null; then
    fail "pyvmomi / pyyaml / pymongo 缺一, 請先套 v3.12.0.0-vmware-prereq"
fi
ok "pyvmomi + pyyaml + pymongo 已就緒"

# ansible-vault 必須在 (collector 用它解 vc_credentials.vault)
command -v ansible-vault >/dev/null 2>&1 || fail "ansible-vault 不在 PATH, 請先 dnf install ansible-core"
ok "ansible-vault 就緒"

CUR_VER=$(python3 -c "import json; print(json.load(open('$HOME_DIR/data/version.json'))['version'])" 2>/dev/null || echo "unknown")
info "當前版本: $CUR_VER"

# ========== [1] 備份 ==========
echo -e "${BOLD}[1/8] 備份${NC}"
mkdir -p "$BACKUP_DIR"
cp -p "$HOME_DIR/webapp/routes/api_vmware.py" "$BACKUP_DIR/" && ok "api_vmware.py → bak"
cp -p "$HOME_DIR/data/version.json" "$BACKUP_DIR/" && ok "version.json → bak"
# vmware_service.py 可能不存在 (首次裝)
if [ -f "$HOME_DIR/webapp/services/vmware_service.py" ]; then
    cp -p "$HOME_DIR/webapp/services/vmware_service.py" "$BACKUP_DIR/" && ok "vmware_service.py → bak"
fi
info "備份: $BACKUP_DIR"

# ========== [2] 複製 collector ==========
echo -e "${BOLD}[2/8] 部署 collector${NC}"
OWNER=$(stat -c "%U:%G" "$HOME_DIR/webapp/app.py")
info "檔案 owner: $OWNER"

mkdir -p "$HOME_DIR/collector"
mkdir -p "$HOME_DIR/logs"
cp "$SRC_DIR/collector/vcenter_collector.py" "$HOME_DIR/collector/" && \
    chown "$OWNER" "$HOME_DIR/collector/vcenter_collector.py" && \
    chmod 750 "$HOME_DIR/collector/vcenter_collector.py" && \
    ok "vcenter_collector.py"
chown "$OWNER" "$HOME_DIR/collector"
chown "$OWNER" "$HOME_DIR/logs"

# ========== [3] 複製 service + 改寫 api ==========
echo -e "${BOLD}[3/8] 部署 vmware_service + 改寫 api_vmware${NC}"
cp "$SRC_DIR/webapp/services/vmware_service.py" "$HOME_DIR/webapp/services/" && \
    chown "$OWNER" "$HOME_DIR/webapp/services/vmware_service.py" && \
    ok "vmware_service.py (新, fallback 到 vmware_mock)"
cp "$SRC_DIR/webapp/routes/api_vmware.py" "$HOME_DIR/webapp/routes/" && \
    chown "$OWNER" "$HOME_DIR/webapp/routes/api_vmware.py" && \
    ok "api_vmware.py (改 route 指向 vmware_service)"

# 語法驗證
python3 -c "import ast; ast.parse(open('$HOME_DIR/webapp/services/vmware_service.py').read())" 2>&1 || fail "vmware_service.py 語法錯"
python3 -c "import ast; ast.parse(open('$HOME_DIR/webapp/routes/api_vmware.py').read())" 2>&1 || fail "api_vmware.py 語法錯"
python3 -c "import ast; ast.parse(open('$HOME_DIR/collector/vcenter_collector.py').read())" 2>&1 || fail "vcenter_collector.py 語法錯"
ok "py 語法通過"

# ========== [4] 建 data/vmware ==========
echo -e "${BOLD}[4/8] 建 data/vmware/ (vcenters.yaml.sample + README)${NC}"
mkdir -p "$HOME_DIR/data/vmware"
cp "$SRC_DIR/data/vmware/vcenters.yaml.sample" "$HOME_DIR/data/vmware/" && ok "vcenters.yaml.sample"
cp "$SRC_DIR/data/vmware/README.md" "$HOME_DIR/data/vmware/" && ok "README.md"
chown -R "$OWNER" "$HOME_DIR/data/vmware"
chmod 750 "$HOME_DIR/data/vmware"
chmod 640 "$HOME_DIR/data/vmware/vcenters.yaml.sample"
chmod 640 "$HOME_DIR/data/vmware/README.md"
info "等使用者手動建 vcenters.yaml + vc_credentials.vault (ansible-vault), 見 data/vmware/README.md"

# ========== [5] 安裝 cron ==========
echo -e "${BOLD}[5/8] 安裝 cron (每 8H)${NC}"
CRON_USER="$(echo "$OWNER" | cut -d: -f1)"
CRON_FILE="/etc/cron.d/inspection-vmware-collect"
cat > "$CRON_FILE" <<CRONEOF
# v3.12.1.0 VMware vCenter collector — 每 8 小時抓一次 snapshot 寫 MongoDB
# 由 install.sh 產生, rollback: rm $CRON_FILE
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
INSPECTION_HOME=$HOME_DIR
0 */8 * * * $CRON_USER /usr/bin/python3 $HOME_DIR/collector/vcenter_collector.py >> $HOME_DIR/logs/vcenter_collector.log 2>&1
CRONEOF
chmod 644 "$CRON_FILE"
chown root:root "$CRON_FILE"
ok "cron 已裝: $CRON_FILE (跑 user: $CRON_USER)"
info "下次觸發: 00:00 / 08:00 / 16:00"

# ========== [6] 更新 version.json ==========
echo -e "${BOLD}[6/8] 更新 version.json → 3.12.1.0${NC}"
python3 <<PYEOF || fail "version.json 更新失敗"
import json, datetime
p = "$HOME_DIR/data/version.json"
d = json.load(open(p))
new_entry = open("$SCRIPT_DIR/CHANGELOG_ENTRY.txt").read().strip()

if any(e.startswith("3.12.1.0 ") for e in d.get("changelog", [])):
    print("  changelog already has 3.12.1.0, skip prepend")
else:
    d.setdefault("changelog", []).insert(0, new_entry)

d["version"] = "3.12.1.0"
d["updated_at"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
print("  version.json → 3.12.1.0")
PYEOF
chown "$OWNER" "$HOME_DIR/data/version.json"
ok "version.json OK"

# ========== [7] 重啟 + 驗證 ==========
echo -e "${BOLD}[7/8] 重啟 itagent-web + HTTP 驗證${NC}"
RESTARTED=0
for svc in itagent-web inspection inspection-web; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" && ok "systemctl restart $svc" && RESTARTED=1 && break
    fi
done
[ "$RESTARTED" -eq 1 ] || warn "沒偵測到 Flask service, 請手動重啟"
sleep 3

NEW_VERSION=$(python3 -c "import json; print(json.load(open('$HOME_DIR/data/version.json'))['version'])" 2>/dev/null || echo "?")
[ "$NEW_VERSION" = "3.12.1.0" ] && ok "版本 $NEW_VERSION ✅" || warn "版本異常: $NEW_VERSION"

HTTP_VM=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5000/vmware" 2>/dev/null || echo "000")
case "$HTTP_VM" in
    200|302|401) ok "/vmware $HTTP_VM (頁面路由載入成功)" ;;
    *) warn "/vmware $HTTP_VM (非預期, 可能要手動重啟 flask)" ;;
esac

# Python import 測試
sudo -u "$CRON_USER" bash -c "cd $HOME_DIR/webapp && python3 -c \"from routes.api_vmware import bp; from services.vmware_service import get_overview_data; d=get_overview_data(); print('endpoints:', len([r for r in bp.deferred_functions]), '| keys:', list(d.keys())[:5], '| source:', d.get('_source','live'))\"" 2>&1 | grep -q "endpoints:" && ok "blueprint + service 載入通過 (目前 fallback 到 inline mock, 等填 vcenters.yaml + 跑 collector 才有真資料)" || warn "import 測試有異常, 檢查 $BACKUP_DIR"

# ========== [8] collector dry-run 提示 ==========
echo -e "${BOLD}[8/8] collector 設定指引${NC}"
info "下一步 (人工):"
echo "    1. cd $HOME_DIR/data/vmware"
echo "    2. cp vcenters.yaml.sample vcenters.yaml && vi vcenters.yaml  # 填 5 個 VC IP + label"
echo "    3. chmod 600 vcenters.yaml && chown $CRON_USER:$(echo $OWNER | cut -d: -f2) vcenters.yaml"
echo "    4. ansible-vault create vc_credentials.vault --vault-password-file $HOME_DIR/.vault_pass"
echo "       (內容: user: \"administrator@vsphere.local\" / password: \"...\")"
echo "    5. chmod 600 vc_credentials.vault && chown 同上"
echo "    6. dry-run: sudo -u $CRON_USER python3 $HOME_DIR/collector/vcenter_collector.py --only 板橋 --dry-run -v"
echo "    7. 真跑: sudo -u $CRON_USER python3 $HOME_DIR/collector/vcenter_collector.py"
echo "    8. mongosh inspection --eval 'db.vmware_snapshots.find({},{timestamp:1,\"vcenter.label\":1,status:1}).sort({timestamp:-1}).limit(5)'"

echo ""
echo -e "${GREEN}${BOLD}╔═════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  v3.12.1.0 VMware collector 部署完成 (cron 已排)         ║${NC}"
echo -e "${GREEN}${BOLD}╚═════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}221 家裡 (沒實 VC) 用 mock-write 模式${NC}:"
echo "  sudo -u $CRON_USER python3 $HOME_DIR/collector/vcenter_collector.py --mock-write"
echo "  # 寫 5 VC mock snapshot 到 MongoDB, /vmware 頁會切到真 MongoDB 資料 (帶 mock 標記)"
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo "  sudo rm $CRON_FILE"
echo "  sudo rm -rf $HOME_DIR/collector"
echo "  sudo rm -rf $HOME_DIR/data/vmware"
echo "  sudo rm $HOME_DIR/webapp/services/vmware_service.py"
echo "  sudo cp -p $BACKUP_DIR/api_vmware.py $HOME_DIR/webapp/routes/"
echo "  sudo cp -p $BACKUP_DIR/version.json $HOME_DIR/data/"
echo "  sudo systemctl restart itagent-web"
