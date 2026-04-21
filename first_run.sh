#!/bin/bash
###############################################
#  IT Inspection System - 首次啟動引導
#  版本: v3.5.0.0-testenv
#
#  用途：install.sh 完成後執行，負責
#    1. 檢查服務狀態
#    2. 協助匯入主機清單
#    3. 分發 SSH 公鑰
#    4. 執行試跑一次巡檢
###############################################
set -e

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"
CYAN="\033[0;36m"; BOLD="\033[1m"; NC="\033[0m"

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}\n"; }

# 讀取安裝環境
ENV_FILE="/etc/default/itagent"
[ -f "$ENV_FILE" ] || fail "找不到 $ENV_FILE，請先執行 install.sh"
source "$ENV_FILE"

[ -d "$ITAGENT_HOME" ] || fail "ITAGENT_HOME ($ITAGENT_HOME) 不存在"

clear
echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║     IT Inspection System - 首次啟動引導          ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================
# Step 1: 檢查服務
# ============================================
step "檢查服務狀態"

for svc in itagent-db itagent-web; do
    if systemctl is-active "$svc" &>/dev/null; then
        ok "$svc: active"
    else
        warn "$svc: 未啟動，嘗試啟動..."
        systemctl start "$svc" && ok "$svc 已啟動" || fail "$svc 啟動失敗，請查看 journalctl -u $svc"
    fi
done

# ============================================
# Step 2: 匯入主機清單
# ============================================
step "主機清單"

HOSTS_FILE="$ITAGENT_HOME/data/hosts_config.json"
TEMPLATE="$ITAGENT_HOME/data/hosts_config.template.json"

if [ -f "$HOSTS_FILE" ]; then
    COUNT=$(python3 -c "import json; print(len(json.load(open('$HOSTS_FILE')).get('hosts', [])))" 2>/dev/null || echo "?")
    ok "已有主機清單（$COUNT 台）"
    read -rp "  是否重新匯入？(y/N) " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        cp "$TEMPLATE" "$HOSTS_FILE"
        echo "  請編輯: $HOSTS_FILE"
        ${EDITOR:-vi} "$HOSTS_FILE"
    fi
else
    if [ -f "$TEMPLATE" ]; then
        cp "$TEMPLATE" "$HOSTS_FILE"
        echo "  已從範本複製到 $HOSTS_FILE"
        echo "  ${BOLD}請編輯主機清單後繼續${NC}"
        read -rp "  按 Enter 開啟編輯器..."
        ${EDITOR:-vi} "$HOSTS_FILE"
    else
        warn "找不到範本 $TEMPLATE，跳過主機匯入"
    fi
fi

# ============================================
# Step 3: 分發 SSH 公鑰
# ============================================
step "SSH 公鑰分發提示"

PUB_KEY="$ITAGENT_HOME/.ssh/ansible_svc_key.pub"
if [ -f "$PUB_KEY" ]; then
    echo -e "  ansible_svc 公鑰位置：${CYAN}$PUB_KEY${NC}"
    echo ""
    echo -e "  ${BOLD}請在 *每一台* 受控主機上建立 ansible_svc 帳號並放入此公鑰：${NC}"
    echo ""
    echo "    # 受控主機上執行："
    echo "    useradd -m -s /bin/bash ansible_svc"
    echo "    mkdir -p /home/ansible_svc/.ssh && chmod 700 /home/ansible_svc/.ssh"
    echo "    # 把下面這行貼進 /home/ansible_svc/.ssh/authorized_keys:"
    echo ""
    echo -e "    ${CYAN}$(cat "$PUB_KEY")${NC}"
    echo ""
    echo "    chmod 600 /home/ansible_svc/.ssh/authorized_keys"
    echo "    chown -R ansible_svc:ansible_svc /home/ansible_svc/.ssh"
    echo ""
    echo -e "  或本機可 ssh-copy-id：${CYAN}ssh-copy-id -i $PUB_KEY ansible_svc@<IP>${NC}"
else
    warn "找不到公鑰 $PUB_KEY，請先執行 install.sh"
fi

read -rp "  完成 SSH 公鑰分發後按 Enter 繼續（未完成也可按 Enter 跳過）..."

# ============================================
# Step 4: 試跑一次巡檢
# ============================================
step "試跑巡檢"

RUN_SCRIPT="$ITAGENT_HOME/run_inspection.sh"
if [ -f "$RUN_SCRIPT" ]; then
    read -rp "  是否現在試跑巡檢？(Y/n) " ans
    if [[ ! "$ans" =~ ^[Nn]$ ]]; then
        echo ""
        "$RUN_SCRIPT" || warn "巡檢失敗，請檢查 $ITAGENT_HOME/logs/"
    fi
else
    warn "找不到 $RUN_SCRIPT，跳過試跑"
fi

# ============================================
# 完成
# ============================================
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
FLASK_PORT=$(grep -oP 'port \K\d+' /etc/systemd/system/itagent-web.service 2>/dev/null || echo 5000)

echo ""
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ 首次啟動引導完成${NC}"
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo ""
echo -e "  管理網址: ${CYAN}http://${IP}:${FLASK_PORT}/admin${NC}"
echo -e "  服務狀態: ${BOLD}itagent status${NC}"
echo -e "  查看日誌: ${BOLD}itagent log${NC}"
echo ""
echo -e "  ${YELLOW}提醒：請立即修改 oper 帳號的預設密碼${NC}"
echo ""
