#!/bin/bash
###############################################
#  ITAgent 巡檢系統 - 服務管理工具
#  用法: itagent {start|stop|restart|status|log|menu}
#  最後同步：2026-04-18 (v3.4.6.0)
#  或直接執行進入互動選單
###############################################

# 讀取環境變數（搬家只需改 /etc/default/itagent）
ENV_FILE="/etc/default/itagent"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "錯誤: 找不到 $ENV_FILE，請先建立環境設定檔"
    echo "範例: echo ITAGENT_HOME=/opt/inspection > $ENV_FILE"
    exit 1
fi

SCRIPT_NAME="itagent"
DB_SVC="itagent-db"
WEB_SVC="itagent-web"
TUNNEL_SVC="itagent-tunnel"
LOG_FILE="${ITAGENT_HOME}/logs/flask.log"
VERSION_FILE="${ITAGENT_HOME}/data/version.json"

# 顏色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

print_status() {
    local svc=$1
    local status
    status=$(systemctl is-active "$svc" 2>/dev/null)
    case "$status" in
        active)   echo -e "  ${GREEN}● $svc${NC}\t${GREEN}running${NC}" ;;
        inactive) echo -e "  ${RED}○ $svc${NC}\t${RED}stopped${NC}" ;;
        failed)   echo -e "  ${RED}✗ $svc${NC}\t${RED}failed${NC}" ;;
        *)        echo -e "  ${YELLOW}? $svc${NC}\t${YELLOW}$status${NC}" ;;
    esac
}

get_version() {
    if [ -f "$VERSION_FILE" ]; then
        grep -o '"version": "[^"]*"' "$VERSION_FILE" 2>/dev/null | head -1 | cut -d'"' -f4 || echo "unknown"
    else
        echo "unknown"
    fi
}

do_start() {
    echo -e "${CYAN}▶ 啟動 ITAgent 服務...${NC}"
    systemctl start $DB_SVC
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ MongoDB 啟動失敗${NC}"
        systemctl status $DB_SVC --no-pager -l
        return 1
    fi
    echo -e "  ${GREEN}✓${NC} MongoDB 已啟動"

    systemctl start $WEB_SVC
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Flask 啟動失敗${NC}"
        systemctl status $WEB_SVC --no-pager -l
        return 1
    fi
    echo -e "  ${GREEN}✓${NC} Flask 已啟動"

    systemctl start $TUNNEL_SVC 2>/dev/null
    echo -e "  ${GREEN}✓${NC} Tunnel 已啟動"

    local retry=0
    while [ $retry -lt 10 ]; do
        if curl -s -o /dev/null http://127.0.0.1:5000/ 2>/dev/null; then
            echo -e "${GREEN}✓ ITAgent 服務啟動完成${NC}"
            return 0
        fi
        sleep 1
        retry=$((retry+1))
    done
    echo -e "${YELLOW}⚠ 服務已啟動但 HTTP 尚未回應，請稍後確認${NC}"
}

do_stop() {
    echo -e "${CYAN}■ 停止 ITAgent 服務...${NC}"
    systemctl stop $TUNNEL_SVC 2>/dev/null
    echo -e "  ${GREEN}✓${NC} Tunnel 已停止"
    systemctl stop $WEB_SVC
    echo -e "  ${GREEN}✓${NC} Flask 已停止"
    systemctl stop $DB_SVC
    echo -e "  ${GREEN}✓${NC} MongoDB 已停止"
    echo -e "${GREEN}✓ ITAgent 服務已全部停止${NC}"
}

do_restart() {
    echo -e "${CYAN}↻ 重啟 ITAgent 服務...${NC}"
    do_stop
    sleep 2
    do_start
}

do_status() {
    local ver
    ver=$(get_version)
    echo ""
    echo -e "${BOLD}═══ ITAgent 巡檢系統 v${ver} ═══${NC}"
    echo -e "  HOME: ${ITAGENT_HOME}"
    echo ""
    print_status $DB_SVC
    print_status $WEB_SVC
    print_status $TUNNEL_SVC
    echo ""

    local http_code
    http_code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5000/ 2>/dev/null)
    if [ "$http_code" = "200" ]; then
        echo -e "  ${GREEN}● HTTP${NC}\t\t${GREEN}200 OK${NC}"
    else
        echo -e "  ${RED}○ HTTP${NC}\t\t${RED}$http_code${NC}"
    fi

    if podman exec mongodb mongosh --eval "db.runCommand({ping:1})" --quiet 2>/dev/null | grep -q "ok"; then
        echo -e "  ${GREEN}● MongoDB${NC}\t${GREEN}connected${NC}"
    else
        echo -e "  ${RED}○ MongoDB${NC}\t${RED}disconnected${NC}"
    fi
    echo ""

    # Tunnel URL
    local tunnel_url
    tunnel_url=$(journalctl -u $TUNNEL_SVC --no-pager 2>/dev/null | grep -o 'https://[^ ]*trycloudflare.com' | tail -1)
    if [ -n "$tunnel_url" ]; then
        echo -e "  ${GREEN}● Tunnel${NC}\t${CYAN}${tunnel_url}${NC}"
    else
        echo -e "  ${YELLOW}○ Tunnel${NC}\t${YELLOW}未取得網址${NC}"
    fi
    echo ""

    local db_enabled web_enabled tunnel_enabled
    db_enabled=$(systemctl is-enabled $DB_SVC 2>/dev/null)
    web_enabled=$(systemctl is-enabled $WEB_SVC 2>/dev/null)
    tunnel_enabled=$(systemctl is-enabled $TUNNEL_SVC 2>/dev/null)
    echo -e "  開機自啟: DB=${db_enabled}, Web=${web_enabled}, Tunnel=${tunnel_enabled}"
    echo ""
}

do_log() {
    echo -e "${CYAN}📋 最近 30 行日誌:${NC}"
    echo "─────────────────────────────────────────"
    journalctl -u $WEB_SVC --no-pager -n 30 2>/dev/null || tail -30 "$LOG_FILE" 2>/dev/null || echo "(無日誌)"
    echo "─────────────────────────────────────────"
}

do_tunnel_url() {
    local tunnel_url
    tunnel_url=$(journalctl -u $TUNNEL_SVC --no-pager 2>/dev/null | grep -o 'https://[^ ]*trycloudflare.com' | tail -1)
    if [ -n "$tunnel_url" ]; then
        echo ""
        echo -e "  ${BOLD}外部存取網址：${NC}"
        echo -e "  ${CYAN}${tunnel_url}${NC}"
        echo ""
        echo -e "  ${YELLOW}⚠ Quick Tunnel 網址會在重啟後變更${NC}"
    else
        echo -e "  ${RED}Tunnel 未啟動或尚未取得網址${NC}"
        echo -e "  執行: systemctl restart itagent-tunnel"
    fi
}

show_menu() {
    local ver
    ver=$(get_version)
    while true; do
        echo ""
        echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
        echo -e "${BOLD}║   ITAgent 巡檢系統 v${ver}          ║${NC}"
        echo -e "${BOLD}║   服務管理工具                       ║${NC}"
        echo -e "${BOLD}╠══════════════════════════════════════╣${NC}"
        echo -e "${BOLD}║${NC}  1) ${GREEN}啟動服務${NC}                        ${BOLD}║${NC}"
        echo -e "${BOLD}║${NC}  2) ${RED}停止服務${NC}                        ${BOLD}║${NC}"
        echo -e "${BOLD}║${NC}  3) ${YELLOW}重啟服務${NC}                        ${BOLD}║${NC}"
        echo -e "${BOLD}║${NC}  4) ${CYAN}確認狀態${NC}                        ${BOLD}║${NC}"
        echo -e "${BOLD}║${NC}  5) 查看日誌                        ${BOLD}║${NC}"
        echo -e "${BOLD}║${NC}  6) ${CYAN}Tunnel 網址${NC}                     ${BOLD}║${NC}"
        echo -e "${BOLD}║${NC}  0) 離開                            ${BOLD}║${NC}"
        echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
        echo ""
        read -rp "請選擇 [0-6]: " choice
        case "$choice" in
            1) do_start ;;
            2) do_stop ;;
            3) do_restart ;;
            4) do_status ;;
            5) do_log ;;
            6) do_tunnel_url ;;
            0) echo -e "${GREEN}Bye!${NC}"; exit 0 ;;
            *) echo -e "${RED}無效選項${NC}" ;;
        esac
    done
}

case "${1:-menu}" in
    start)   do_start ;;
    stop)    do_stop ;;
    restart) do_restart ;;
    status)  do_status ;;
    log)     do_log ;;
    tunnel)  do_tunnel_url ;;
    menu)    show_menu ;;
    *)
        echo "用法: $SCRIPT_NAME {start|stop|restart|status|log|tunnel|menu}"
        exit 1
        ;;
esac
