#!/usr/bin/env bash
# ============================================================
#  系統專家維護工具 v2.0  |  SysExpert Maintenance Framework
#  支援: RHEL / Rocky / CentOS / Debian / Ubuntu
#  作者: 自動生成 | 日期: $(date +%Y%m%d)
# ============================================================

set -euo pipefail

# ─────────────────────────────────────────────
#  ANSI 色彩定義
# ─────────────────────────────────────────────
RED='\033[0;31m';    GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m';   CYAN='\033[0;36m';  WHITE='\033[1;37m'
MAGENTA='\033[0;35m'; BOLD='\033[1m';    DIM='\033[2m';  RESET='\033[0m'
BG_BLUE='\033[44m';  BG_GREEN='\033[42m'; BG_RED='\033[41m'

# ─────────────────────────────────────────────
#  全域變數
# ─────────────────────────────────────────────
SCRIPT_VERSION="2.0"
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="Init_Report_${HOSTNAME_SHORT}_${TIMESTAMP}.log"
BACKUP_DIR="/var/backup/sysexpert_${TIMESTAMP}"
# A 類可配置參數（支援環境變數覆蓋）
PASS_MAX_DAYS="${SYSEXPERT_PASS_MAX_DAYS:-90}"
PASS_MIN_DAYS="${SYSEXPERT_PASS_MIN_DAYS:-1}"
PASS_MIN_LEN="${SYSEXPERT_PASS_MIN_LEN:-8}"
FAILLOCK_DENY="${SYSEXPERT_FAILLOCK_DENY:-5}"
FAILLOCK_UNLOCK="${SYSEXPERT_FAILLOCK_UNLOCK:-900}"
TIMEZONE="${SYSEXPERT_TIMEZONE:-Asia/Taipei}"
NTP_SERVER="${SYSEXPERT_NTP_SERVER:-10.93.168.1}"
DNS1="${SYSEXPERT_DNS1:-10.93.168.1}"
DNS2="${SYSEXPERT_DNS2:-10.93.3.1}"
SNMP_COMMUNITY="${SYSEXPERT_SNMP_COMMUNITY:-exampleup}"
SYSINFRA_USER="${SYSEXPERT_SYSINFRA_USER:-sysinfra}"
SYSINFRA_UID="${SYSEXPERT_SYSINFRA_UID:-645}"
SYSINFRA_PASS="${SYSEXPERT_SYSINFRA_PASS:-1qaz@WSX}"
CHRONY_SERVER="${SYSEXPERT_CHRONY_SERVER:-10.93.168.1}"

# ─────────────────────────────────────────────
#  環境偵測
# ─────────────────────────────────────────────
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_LIKE="${ID_LIKE:-}"
        OS_NAME="${NAME:-Unknown}"
        OS_VERSION="${VERSION_ID:-}"
    else
        OS_ID="unknown"; OS_LIKE=""; OS_NAME="Unknown"; OS_VERSION=""
    fi

    if echo "$OS_ID $OS_LIKE" | grep -qiE 'rhel|centos|rocky|fedora|almalinux'; then
        OS_FAMILY="rhel"
        PKG_MGR="dnf"
        PKG_INSTALL="dnf install -y"
        PKG_CLEAN="dnf clean all"
        PKG_MAKECACHE="dnf makecache"
        DISPLAY_OS="RHEL"
    elif echo "$OS_ID $OS_LIKE" | grep -qiE 'debian|ubuntu|mint'; then
        OS_FAMILY="debian"
        PKG_MGR="apt"
        PKG_INSTALL="apt-get install -y"
        PKG_CLEAN="apt-get clean"
        PKG_MAKECACHE="apt-get update"
        DISPLAY_OS="Debian/Ubuntu"
    else
        OS_FAMILY="unknown"
        PKG_MGR="unknown"
        PKG_INSTALL="echo [不支援的 OS]"
        PKG_CLEAN="true"
        PKG_MAKECACHE="true"
        DISPLAY_OS="Unknown"
    fi
}

# ─────────────────────────────────────────────
#  日誌與輸出工具
# ─────────────────────────────────────────────
log_init() {
    mkdir -p "$(dirname "$REPORT_FILE")" 2>/dev/null || true
    {
        echo "================================================================"
        echo "  系統專家維護工具 v${SCRIPT_VERSION}  |  報告日誌"
        echo "  主機: ${HOSTNAME_SHORT}  |  IP: ${HOST_IP}"
        echo "  OS: ${DISPLAY_OS}  |  套件管理: ${PKG_MGR}"
        echo "  開始時間: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "================================================================"
    } | tee "$REPORT_FILE"
}

log()  { local ts; ts=$(date '+%H:%M:%S')
         echo -e "${DIM}[$ts]${RESET} $*"
         echo "[$ts] $*" >> "$REPORT_FILE" 2>/dev/null || true; }
ok()   { echo -e "${GREEN}[✔ 完成]${RESET} $*"; echo "[OK]    $*" >> "$REPORT_FILE" 2>/dev/null || true; }
skip() { echo -e "${YELLOW}[─ 跳過]${RESET} $*"; echo "[SKIP]  $*" >> "$REPORT_FILE" 2>/dev/null || true; }
warn() { echo -e "${YELLOW}[⚠ 警告]${RESET} $*"; echo "[WARN]  $*" >> "$REPORT_FILE" 2>/dev/null || true; }
err()  { echo -e "${RED}[✘ 錯誤]${RESET} $*"; echo "[ERR]   $*" >> "$REPORT_FILE" 2>/dev/null || true; }
info() { echo -e "${CYAN}[ℹ 資訊]${RESET} $*"; echo "[INFO]  $*" >> "$REPORT_FILE" 2>/dev/null || true; }
section() {
    echo ""
    echo -e "${BOLD}${BG_BLUE}${WHITE}  ★ $* ${RESET}"
    echo "" >> "$REPORT_FILE" 2>/dev/null || true
    echo "--- $* ---" >> "$REPORT_FILE" 2>/dev/null || true
}

# ─────────────────────────────────────────────
#  備份工具
# ─────────────────────────────────────────────
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        mkdir -p "$BACKUP_DIR"
        local bak="${BACKUP_DIR}/$(basename "$file").bak_${TIMESTAMP}"
        cp -p "$file" "$bak"
        info "備份: $file → $bak"
        echo "$bak" >> "${BACKUP_DIR}/manifest.txt"
    fi
}

# ─────────────────────────────────────────────
#  Live Log 即時視窗 (背景安裝用)
# ─────────────────────────────────────────────
live_install() {
    local desc="$1"; shift
    local logfile="/tmp/sysexpert_install_$$.log"
    local pid

    echo -e "${CYAN}[安裝中]${RESET} $desc ..."
    "$@" > "$logfile" 2>&1 &
    pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        local last
        last=$(tail -n 1 "$logfile" 2>/dev/null | cut -c1-80 || true)
        printf "\r  ${DIM}%-80s${RESET}" "$last"
        sleep 0.5
    done
    printf "\r%-82s\r" " "

    wait "$pid"
    local rc=$?
    cat "$logfile" >> "$REPORT_FILE" 2>/dev/null || true
    rm -f "$logfile"
    return $rc
}

# ─────────────────────────────────────────────
#  互動式問答工具
# ─────────────────────────────────────────────
ask() {
    local prompt="$1"; local default="${2:-}"
    local answer
    if [ -n "$default" ]; then
        echo -ne "${CYAN}  ➤ $prompt ${DIM}[預設: $default]${RESET}: "
    else
        echo -ne "${CYAN}  ➤ $prompt${RESET}: "
    fi
    read -r answer
    echo "${answer:-$default}"
}

ask_yn() {
    local prompt="$1"; local default="${2:-y}"
    local answer
    echo -ne "${CYAN}  ➤ $prompt ${DIM}[Y/n]${RESET}: "
    read -r answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy] ]]
}

# ─────────────────────────────────────────────
#  主選單顯示
# ─────────────────────────────────────────────
show_header() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║            系統專家維護工具  v${SCRIPT_VERSION}                        ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo -e "  ${WHITE}Host:${RESET} ${HOSTNAME_SHORT}  ${WHITE}IP:${RESET} ${HOST_IP}  ${WHITE}OS:${RESET} ${DISPLAY_OS}  ${WHITE}Pkg:${RESET} ${PKG_MGR}"
    echo -e "  ${DIM}Report: ${REPORT_FILE}${RESET}"
    echo ""
}

show_menu() {
    show_header
    echo -e "  ${BOLD}${GREEN}A1.${RESET} 全自動初始化 (1-18)  ${BOLD}${GREEN}A2.${RESET} 檢查現況  ${BOLD}${GREEN}A3.${RESET} 單選還原備份"
    echo ""
    echo -e "  ${BOLD}${YELLOW}─────────────────── A 類：稽核必要項目 ───────────────────${RESET}"
    local items=(
        "設定密碼最長有效期 (90天)"
        "設定密碼最短更改間隔 (1天)"
        "設定密碼最小長度 (8位)"
        "配置 Authselect Faillock"
        "禁用 SELinux"
        "禁用 IPv6 (GRUB)"
        "停止並禁用 Postfix 服務"
        "同步時區至 Asia/Taipei"
        "建立 sysinfra 管理員帳號"
        "設定帳號預設密碼 (1qaz\@WSX)"
        "設定帳號密碼永不過期"
        "配置 Sudoers 免密碼"
        "修改 SNMP Community (exampleup)"
        "啟動 SNMP 服務"
        "更新 DNS 解析器 (10.93.x)"
        "配置 Chrony NTP 同步"
        "安裝系統維護必要工具"
        "清理與更新 Repo 快取"
    )
    for i in "${!items[@]}"; do
        printf "  ${BOLD}%2d.${RESET} %s\n" "$((i+1))" "${items[$i]}"
    done
    echo ""
    echo -e "  ${BOLD}${MAGENTA}─────────────────── B 類：進階互動優化 ───────────────────${RESET}"
    local bitems=(
        "SSH 逾時設定 (TMOUT)"
        "File Descriptor 限制 (ulimit)"
        "全域別名套用 (ll/vi/grep)"
        "Kernel TCP 優化"
        "自訂登入訊息 (MOTD)"
        "History 歷史強化"
        "服務精簡 (停用冗余服務)"
        "Tmp 自動清理 (cron)"
        "Auditd 監控規則"
        "Syslog authpriv 強化"
    )
    for i in "${!bitems[@]}"; do
        printf "  ${BOLD}B%d.${RESET} %s\n" "$((i+1))" "${bitems[$i]}"
    done
    echo ""
    echo -e "  ${DIM}請輸入選擇 [A1-A3/1-18/B1-B10/Q]:${RESET} "
}

# ============================================================
#  A 類 - 稽核必要項目實作
# ============================================================

# ── A1: 密碼最長有效期 ──────────────────────────────────────
do_a1() {
    section "A1: 設定密碼最長有效期 (90天)"
    local cfg="/etc/login.defs"
    local current
    current=$(grep -E '^\s*PASS_MAX_DAYS' "$cfg" 2>/dev/null | awk '{print $2}' || echo "")
    if [ "$current" = "$PASS_MAX_DAYS" ]; then
        skip "PASS_MAX_DAYS 已為 ${PASS_MAX_DAYS}，無需修改"
    else
        backup_file "$cfg"
        if grep -qE '^\s*PASS_MAX_DAYS' "$cfg"; then
            sed -i "s/^\s*PASS_MAX_DAYS.*/PASS_MAX_DAYS   ${PASS_MAX_DAYS}/" "$cfg"
        else
            echo "PASS_MAX_DAYS   ${PASS_MAX_DAYS}" >> "$cfg"
        fi
        ok "PASS_MAX_DAYS 設定為 ${PASS_MAX_DAYS}"
    fi
}

# ── A2: 密碼最短更改間隔 ────────────────────────────────────
do_a2() {
    section "A2: 設定密碼最短更改間隔 (1天)"
    local cfg="/etc/login.defs"
    local current
    current=$(grep -E '^\s*PASS_MIN_DAYS' "$cfg" 2>/dev/null | awk '{print $2}' || echo "")
    if [ "$current" = "$PASS_MIN_DAYS" ]; then
        skip "PASS_MIN_DAYS 已為 ${PASS_MIN_DAYS}，無需修改"
    else
        backup_file "$cfg"
        if grep -qE '^\s*PASS_MIN_DAYS' "$cfg"; then
            sed -i "s/^\s*PASS_MIN_DAYS.*/PASS_MIN_DAYS   ${PASS_MIN_DAYS}/" "$cfg"
        else
            echo "PASS_MIN_DAYS   ${PASS_MIN_DAYS}" >> "$cfg"
        fi
        ok "PASS_MIN_DAYS 設定為 ${PASS_MIN_DAYS}"
    fi
}

# ── A3: 密碼最小長度 ────────────────────────────────────────
do_a3() {
    section "A3: 設定密碼最小長度 (8位)"
    local cfg="/etc/login.defs"
    local current
    current=$(grep -E '^\s*PASS_MIN_LEN' "$cfg" 2>/dev/null | awk '{print $2}' || echo "")
    if [ "$current" = "$PASS_MIN_LEN" ]; then
        skip "PASS_MIN_LEN 已為 ${PASS_MIN_LEN}，無需修改"
    else
        backup_file "$cfg"
        if grep -qE '^\s*PASS_MIN_LEN' "$cfg"; then
            sed -i "s/^\s*PASS_MIN_LEN.*/PASS_MIN_LEN    ${PASS_MIN_LEN}/" "$cfg"
        else
            echo "PASS_MIN_LEN    ${PASS_MIN_LEN}" >> "$cfg"
        fi
        ok "PASS_MIN_LEN 設定為 ${PASS_MIN_LEN}"
    fi
}

# ── A4: Authselect Faillock ─────────────────────────────────
do_a4() {
    section "A4: 配置 Authselect Faillock"
    if [ "$OS_FAMILY" != "rhel" ]; then
        skip "Authselect 僅支援 RHEL 體系，目前 OS 為 ${DISPLAY_OS}，跳過"
        return 0
    fi
    if ! command -v authselect &>/dev/null; then
        warn "authselect 指令不存在，嘗試安裝..."
        $PKG_INSTALL authselect 2>/dev/null || true
    fi
    if authselect current 2>/dev/null | grep -q 'with-faillock'; then
        skip "Faillock 已配置"
    else
        authselect select sssd with-faillock --force 2>/dev/null || \
        authselect select minimal with-faillock --force 2>/dev/null || \
        warn "authselect 配置失敗，請手動檢查"
        ok "Authselect with-faillock 配置完成"
    fi
    # 設定 faillock 參數
    local flcfg="/etc/security/faillock.conf"
    if [ -f "$flcfg" ]; then
        backup_file "$flcfg"
        grep -q '^deny' "$flcfg" || echo "deny = ${FAILLOCK_DENY}" >> "$flcfg"
        grep -q '^unlock_time' "$flcfg" || echo "unlock_time = ${FAILLOCK_UNLOCK}" >> "$flcfg"
        ok "faillock.conf: deny=${FAILLOCK_DENY}, unlock_time=${FAILLOCK_UNLOCK}"
    fi
}

# ── A5: 禁用 SELinux ────────────────────────────────────────
do_a5() {
    section "A5: 禁用 SELinux"
    if [ "$OS_FAMILY" != "rhel" ]; then
        skip "SELinux 不適用於 ${DISPLAY_OS}，跳過"
        return 0
    fi
    local cfg="/etc/selinux/config"
    if [ ! -f "$cfg" ]; then
        skip "SELinux 設定檔不存在，可能未安裝"
        return 0
    fi
    local current
    current=$(grep -E '^SELINUX=' "$cfg" | cut -d= -f2 | tr -d '[:space:]')
    if [ "$current" = "disabled" ]; then
        skip "SELinux 已設為 disabled"
    else
        backup_file "$cfg"
        sed -i 's/^SELINUX=.*/SELINUX=disabled/' "$cfg"
        ok "SELinux 設定為 disabled（重開機後生效）"
    fi
    # 即時關閉（若可能）
    if command -v setenforce &>/dev/null; then
        setenforce 0 2>/dev/null && info "即時 setenforce 0 執行完成" || true
    fi
}

# ── A6: 禁用 IPv6 (GRUB) ───────────────────────────────────
do_a6() {
    section "A6: 禁用 IPv6 (GRUB)"
    local grub_cfg="/etc/default/grub"
    if [ ! -f "$grub_cfg" ]; then
        warn "找不到 $grub_cfg，跳過 GRUB 配置"
        return 0
    fi
    if grep -q 'ipv6.disable=1' "$grub_cfg"; then
        skip "IPv6 disable 參數已存在於 GRUB"
    else
        backup_file "$grub_cfg"
        sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 ipv6.disable=1"/' "$grub_cfg"
        # 重建 grub 設定
        if command -v grub2-mkconfig &>/dev/null; then
            grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null && ok "grub2-mkconfig 執行完成" || warn "grub2-mkconfig 失敗"
        elif command -v update-grub &>/dev/null; then
            update-grub 2>/dev/null && ok "update-grub 執行完成" || warn "update-grub 失敗"
        fi
        ok "IPv6 已加入 GRUB 核心參數（重開機後生效）"
    fi
    # sysctl 即時停用
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 &>/dev/null || true
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 &>/dev/null || true
    info "sysctl 即時禁用 IPv6"
}

# ── A7: 停止並禁用 Postfix ──────────────────────────────────
do_a7() {
    section "A7: 停止並禁用 Postfix 服務"
    if ! systemctl list-unit-files postfix.service &>/dev/null | grep -q postfix; then
        skip "Postfix 服務不存在"
        return 0
    fi
    local active; active=$(systemctl is-active postfix 2>/dev/null || echo "inactive")
    local enabled; enabled=$(systemctl is-enabled postfix 2>/dev/null || echo "disabled")
    if [ "$active" = "inactive" ] && [ "$enabled" = "disabled" ]; then
        skip "Postfix 已停止且已禁用"
    else
        systemctl stop postfix 2>/dev/null || true
        systemctl disable postfix 2>/dev/null || true
        ok "Postfix 已停止並禁用"
    fi
}

# ── A8: 時區設定 ────────────────────────────────────────────
do_a8() {
    section "A8: 同步時區至 Asia/Taipei"
    local current_tz
    current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || \
                 cat /etc/timezone 2>/dev/null || echo "unknown")
    if [ "$current_tz" = "$TIMEZONE" ]; then
        skip "時區已為 ${TIMEZONE}"
    else
        timedatectl set-timezone "$TIMEZONE"
        ok "時區設定為 ${TIMEZONE}（原: $current_tz）"
    fi
}

# ── A9: 建立 sysinfra 帳號 ──────────────────────────────────
do_a9() {
    section "A9: 建立 sysinfra 管理員帳號 (UID ${SYSINFRA_UID})"
    if id "$SYSINFRA_USER" &>/dev/null; then
        skip "使用者 ${SYSINFRA_USER} 已存在"
    else
        useradd -m -u "$SYSINFRA_UID" -s /bin/bash -c "SysInfra Admin" "$SYSINFRA_USER"
        ok "使用者 ${SYSINFRA_USER} 建立完成 (UID=${SYSINFRA_UID})"
    fi
}

# ── A10: 設定預設密碼 ────────────────────────────────────────
do_a10() {
    section "A10: 設定帳號預設密碼"
    if ! id "$SYSINFRA_USER" &>/dev/null; then
        warn "使用者 ${SYSINFRA_USER} 不存在，請先執行 A9"
        return 1
    fi
    echo "${SYSINFRA_USER}:${SYSINFRA_PASS}" | chpasswd
    ok "密碼設定完成（使用者: ${SYSINFRA_USER}）"
}

# ── A11: 密碼永不過期 ────────────────────────────────────────
do_a11() {
    section "A11: 設定帳號密碼永不過期"
    if ! id "$SYSINFRA_USER" &>/dev/null; then
        warn "使用者 ${SYSINFRA_USER} 不存在，請先執行 A9"
        return 1
    fi
    local max_days
    max_days=$(chage -l "$SYSINFRA_USER" 2>/dev/null | grep 'Maximum' | awk -F': ' '{print $2}' || echo "")
    if [ "$max_days" = "never" ] || [ "$max_days" = "-1" ]; then
        skip "${SYSINFRA_USER} 密碼已設定永不過期"
    else
        chage -M -1 "$SYSINFRA_USER"
        ok "${SYSINFRA_USER} 密碼永不過期設定完成"
    fi
}

# ── A12: Sudoers 免密碼 ──────────────────────────────────────
do_a12() {
    section "A12: 配置 Sudoers 免密碼"
    local sudoers_file="/etc/sudoers.d/${SYSINFRA_USER}"
    local rule="${SYSINFRA_USER} ALL=(ALL) NOPASSWD:ALL"
    if [ -f "$sudoers_file" ] && grep -qF "NOPASSWD:ALL" "$sudoers_file"; then
        skip "Sudoers 規則已存在"
    else
        echo "$rule" > "$sudoers_file"
        chmod 440 "$sudoers_file"
        # 驗證語法
        visudo -c -f "$sudoers_file" &>/dev/null && ok "Sudoers 規則寫入: $sudoers_file" || {
            err "Sudoers 語法錯誤，已回復"
            rm -f "$sudoers_file"
        }
    fi
}

# ── A13: SNMP Community ──────────────────────────────────────
do_a13() {
    section "A13: 修改 SNMP Community (${SNMP_COMMUNITY})"
    local snmp_cfg="/etc/snmp/snmpd.conf"
    # 若不存在先安裝
    if [ ! -f "$snmp_cfg" ]; then
        info "snmpd.conf 不存在，嘗試安裝 net-snmp..."
        if [ "$OS_FAMILY" = "rhel" ]; then
            $PKG_INSTALL net-snmp net-snmp-utils 2>/dev/null || warn "net-snmp 安裝失敗"
        else
            $PKG_INSTALL snmpd snmp 2>/dev/null || warn "snmpd 安裝失敗"
        fi
    fi
    if [ ! -f "$snmp_cfg" ]; then
        warn "SNMP 設定檔仍不存在，跳過"
        return 0
    fi
    backup_file "$snmp_cfg"
    # 移除舊的 community 設定，插入新的
    sed -i '/^com2sec\|^rocommunity\|^rwcommunity/d' "$snmp_cfg"
    cat >> "$snmp_cfg" <<EOF

# SysExpert: SNMP Community (${TIMESTAMP})
com2sec notConfigUser  default       ${SNMP_COMMUNITY}
group   notConfigGroup v1            notConfigUser
group   notConfigGroup v2c           notConfigUser
view    systemview     included      .1.3.6.1.2.1.1
view    systemview     included      .1.3.6.1.2.1.25.1.1
access  notConfigGroup ""            any  noauth  exact  systemview  none  none
rocommunity ${SNMP_COMMUNITY}
EOF
    ok "SNMP Community 設定為 ${SNMP_COMMUNITY}"
}

# ── A14: 啟動 SNMP 服務 ──────────────────────────────────────
do_a14() {
    section "A14: 啟動 SNMP 服務"
    local svc="snmpd"
    if ! systemctl list-unit-files "${svc}.service" &>/dev/null | grep -q "$svc"; then
        warn "snmpd 服務不存在，跳過"
        return 0
    fi
    systemctl enable "$svc" 2>/dev/null || true
    systemctl restart "$svc" 2>/dev/null && ok "snmpd 服務已啟動並設為開機自動啟動" || warn "snmpd 啟動失敗"
    systemctl is-active "$svc" && info "snmpd 狀態: $(systemctl is-active $svc)" || true
}

# ── A15: DNS 設定 ────────────────────────────────────────────
do_a15() {
    section "A15: 更新 DNS 解析器"
    local rcfg="/etc/resolv.conf"
    if grep -q "nameserver ${DNS1}" "$rcfg" 2>/dev/null && grep -q "nameserver ${DNS2}" "$rcfg" 2>/dev/null; then
        skip "DNS 已設定為 ${DNS1} 與 ${DNS2}"
        return 0
    fi
    backup_file "$rcfg"
    # 移除舊 nameserver 行
    grep -v '^nameserver' "$rcfg" 2>/dev/null > /tmp/resolv_tmp || true
    {
        cat /tmp/resolv_tmp 2>/dev/null || true
        echo "nameserver ${DNS1}"
        echo "nameserver ${DNS2}"
    } > "$rcfg"
    rm -f /tmp/resolv_tmp
    # 防止 NetworkManager 覆寫
    chattr +i "$rcfg" 2>/dev/null || warn "無法設定 resolv.conf 不可變更屬性（chattr +i）"
    ok "DNS 設定: ${DNS1}, ${DNS2}"
}

# ── A16: Chrony NTP 同步 ────────────────────────────────────
do_a16() {
    section "A16: 配置 Chrony NTP 同步"
    # 安裝 chrony
    if ! command -v chronyc &>/dev/null; then
        info "chrony 未安裝，正在安裝..."
        live_install "安裝 chrony" $PKG_INSTALL chrony || warn "chrony 安裝失敗"
    fi
    local chrony_cfg="/etc/chrony.conf"
    [ -f "$chrony_cfg" ] || chrony_cfg="/etc/chrony/chrony.conf"
    if [ ! -f "$chrony_cfg" ]; then
        warn "找不到 chrony 設定檔，跳過"
        return 0
    fi
    if grep -q "server ${CHRONY_SERVER}" "$chrony_cfg"; then
        skip "Chrony 已包含 ${CHRONY_SERVER} 伺服器設定"
    else
        backup_file "$chrony_cfg"
        sed -i '/^server\|^pool/d' "$chrony_cfg"
        sed -i "1i server ${CHRONY_SERVER} iburst" "$chrony_cfg"
        ok "Chrony 伺服器設定為 ${CHRONY_SERVER}"
    fi
    systemctl enable chronyd 2>/dev/null || true
    systemctl restart chronyd 2>/dev/null && ok "chronyd 已重啟" || warn "chronyd 重啟失敗"
    sleep 2
    chronyc tracking 2>/dev/null | head -5 | while IFS= read -r line; do info "Chrony: $line"; done || true
}

# ── A17: 安裝系統工具 ────────────────────────────────────────
do_a17() {
    section "A17: 安裝系統維護必要工具"
    local pkgs_rhel=("net-tools" "chrony" "unzip" "sysstat" "bind-utils" "net-snmp" "net-snmp-utils" "lsof" "tcpdump" "vim")
    local pkgs_deb=("net-tools" "chrony" "unzip" "sysstat" "dnsutils" "snmpd" "snmp" "lsof" "tcpdump" "vim")

    local to_install=()
    if [ "$OS_FAMILY" = "rhel" ]; then
        for p in "${pkgs_rhel[@]}"; do
            rpm -q "$p" &>/dev/null || to_install+=("$p")
        done
    else
        for p in "${pkgs_deb[@]}"; do
            dpkg -l "$p" 2>/dev/null | grep -q '^ii' || to_install+=("$p")
        done
    fi

    if [ "${#to_install[@]}" -eq 0 ]; then
        skip "所有必要工具已安裝"
    else
        info "待安裝: ${to_install[*]}"
        live_install "安裝套件組" $PKG_INSTALL "${to_install[@]}" && ok "套件安裝完成" || warn "部分套件安裝失敗"
    fi
}

# ── A18: Repo 快取清理 ───────────────────────────────────────
do_a18() {
    section "A18: 清理與更新 Repo 快取"
    info "清理快取..."
    $PKG_CLEAN &>/dev/null && info "快取清理完成"
    info "重建快取..."
    live_install "重建 Repo 快取" $PKG_MAKECACHE && ok "Repo 快取重建完成" || warn "Repo 快取重建失敗"
}

# ============================================================
#  A2: 檢查現況 (Status Check)
# ============================================================
do_status_check() {
    show_header
    section "A2: 系統現況檢查"
    
    # 密碼原則
    echo -e "\n${BOLD}[ 密碼原則 /etc/login.defs ]${RESET}"
    grep -E 'PASS_MAX_DAYS|PASS_MIN_DAYS|PASS_MIN_LEN' /etc/login.defs 2>/dev/null | \
        sed 's/^/  /' || echo "  (無法讀取)"

    # SELinux
    echo -e "\n${BOLD}[ SELinux 狀態 ]${RESET}"
    if command -v getenforce &>/dev/null; then
        echo "  $(getenforce)"
    else
        echo "  N/A (非 RHEL 或未安裝)"
    fi

    # 時區
    echo -e "\n${BOLD}[ 時區 ]${RESET}"
    timedatectl show --property=Timezone --value 2>/dev/null || date +%Z

    # 使用者
    echo -e "\n${BOLD}[ sysinfra 帳號 ]${RESET}"
    if id "$SYSINFRA_USER" &>/dev/null; then
        id "$SYSINFRA_USER"
        chage -l "$SYSINFRA_USER" 2>/dev/null | grep -E 'Maximum|Password expires' | sed 's/^/  /'
    else
        echo "  (不存在)"
    fi

    # DNS
    echo -e "\n${BOLD}[ DNS /etc/resolv.conf ]${RESET}"
    grep 'nameserver' /etc/resolv.conf 2>/dev/null | sed 's/^/  /' || echo "  (無法讀取)"

    # SNMP
    echo -e "\n${BOLD}[ SNMP 服務 ]${RESET}"
    systemctl is-active snmpd 2>/dev/null | sed 's/^/  狀態: /' || echo "  未安裝"

    # Chrony
    echo -e "\n${BOLD}[ Chrony 狀態 ]${RESET}"
    chronyc tracking 2>/dev/null | head -3 | sed 's/^/  /' || echo "  未安裝或未運行"

    # 服務清單
    echo -e "\n${BOLD}[ 關鍵服務狀態 ]${RESET}"
    for svc in postfix snmpd chronyd sshd; do
        local st; st=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
        local color="$GREEN"
        [ "$st" = "inactive" ] || [ "$st" = "not-found" ] && color="$RED"
        printf "  %-15s %b%s%b\n" "${svc}:" "$color" "$st" "$RESET"
    done

    echo ""
    read -rp "  按 Enter 返回主選單..." _dummy
}

# ============================================================
#  A3: 單選還原備份
# ============================================================
do_rollback() {
    show_header
    section "A3: 單選還原備份"
    
    # 搜尋所有備份目錄
    local backup_dirs=()
    while IFS= read -r -d '' d; do
        backup_dirs+=("$d")
    done < <(find /var/backup -maxdepth 1 -type d -name 'sysexpert_*' -print0 2>/dev/null | sort -z)

    if [ "${#backup_dirs[@]}" -eq 0 ]; then
        warn "找不到任何備份目錄 (/var/backup/sysexpert_*)"
        read -rp "  按 Enter 返回..." _dummy
        return 0
    fi

    echo -e "  ${CYAN}可用備份目錄：${RESET}"
    for i in "${!backup_dirs[@]}"; do
        local cnt; cnt=$(ls "${backup_dirs[$i]}"/*.bak_* 2>/dev/null | wc -l || echo 0)
        printf "  %2d. %s  (%s 個備份檔)\n" "$((i+1))" "${backup_dirs[$i]}" "$cnt"
    done

    echo ""
    local sel
    sel=$(ask "請選擇備份目錄編號 (1-${#backup_dirs[@]})" "1")
    local idx=$((sel-1))
    if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#backup_dirs[@]}" ]; then
        warn "無效選擇"
        return 0
    fi

    local chosen_dir="${backup_dirs[$idx]}"
    local bak_files=()
    while IFS= read -r -d '' f; do
        bak_files+=("$f")
    done < <(find "$chosen_dir" -maxdepth 1 -name '*.bak_*' -print0 2>/dev/null | sort -z)

    if [ "${#bak_files[@]}" -eq 0 ]; then
        warn "該目錄下無備份檔"
        return 0
    fi

    echo -e "\n  ${CYAN}備份檔列表：${RESET}"
    for i in "${!bak_files[@]}"; do
        local orig; orig=$(basename "${bak_files[$i]}" | sed 's/\.bak_.*//')
        printf "  %2d. %-35s ← %s\n" "$((i+1))" "$orig" "$(basename "${bak_files[$i]}")"
    done

    echo ""
    local fsel
    fsel=$(ask "請選擇要還原的備份編號 (1-${#bak_files[@]})" "")
    local fidx=$((fsel-1))
    if [ "$fidx" -lt 0 ] || [ "$fidx" -ge "${#bak_files[@]}" ]; then
        warn "無效選擇"
        return 0
    fi

    local bak="${bak_files[$fidx]}"
    # 推算原始路徑（從 manifest）
    local orig_name; orig_name=$(basename "$bak" | sed 's/\.bak_.*//')
    
    # 嘗試從 manifest 比對
    local orig_path=""
    if [ -f "${chosen_dir}/manifest.txt" ]; then
        orig_path=$(grep "/$orig_name\." "${chosen_dir}/manifest.txt" 2>/dev/null | \
                    sed "s|${chosen_dir}/||;s|\.bak_.*||" | tail -1 || true)
    fi
    
    if [ -z "$orig_path" ]; then
        orig_path=$(ask "請輸入還原目標路徑（原始檔案完整路徑）" "")
    fi

    if [ -z "$orig_path" ]; then
        warn "未指定目標路徑，取消還原"
        return 0
    fi

    echo ""
    echo -e "  ${YELLOW}即將還原：${RESET}"
    echo -e "    備份來源: $bak"
    echo -e "    還原至:   $orig_path"
    echo ""
    if ask_yn "確認還原？"; then
        cp -p "$bak" "$orig_path" && ok "還原完成: $orig_path" || err "還原失敗"
    else
        info "取消還原"
    fi
    read -rp "  按 Enter 返回..." _dummy
}

# ============================================================
#  B 類 - 進階互動優化
# ============================================================

# ── B1: SSH 逾時 ─────────────────────────────────────────────
do_b1() {
    section "B1: SSH 逾時設定 (TMOUT)"
    local tmout="${SYSEXPERT_TMOUT:-$(ask "請輸入 TMOUT 秒數" "600")}"
    local profile="/etc/profile"
    backup_file "$profile"
    # 移除舊設定
    sed -i '/^TMOUT=/d;/^export TMOUT/d' "$profile"
    echo "" >> "$profile"
    echo "# SysExpert: SSH Timeout" >> "$profile"
    echo "TMOUT=${tmout}" >> "$profile"
    echo "export TMOUT" >> "$profile"
    ok "TMOUT=${tmout} 已寫入 /etc/profile"
}

# ── B2: File Descriptor ──────────────────────────────────────
do_b2() {
    section "B2: File Descriptor 限制"
    local limit="${SYSEXPERT_ULIMIT:-$(ask "請輸入 ulimit 數值" "65535")}"
    local lcfg="/etc/security/limits.conf"
    backup_file "$lcfg"
    # 移除舊設定
    grep -v '# SysExpert FD' "$lcfg" | grep -v 'nofile' > /tmp/limits_tmp || true
    mv /tmp/limits_tmp "$lcfg"
    cat >> "$lcfg" <<EOF
# SysExpert FD
*               soft    nofile          ${limit}
*               hard    nofile          ${limit}
root            soft    nofile          ${limit}
root            hard    nofile          ${limit}
EOF
    ok "File Descriptor 限制設定為 ${limit}"
}

# ── B3: 全域別名 ─────────────────────────────────────────────
do_b3() {
    section "B3: 全域別名套用"
    if [ -n "${SYSEXPERT_NOASK:-}" ] || ask_yn "是否套用常用 alias (ll, vi→vim, grep 顏色)？"; then
        local alias_file="/etc/profile.d/sysexpert_alias.sh"
        cat > "$alias_file" <<'EOF'
# SysExpert: Global Aliases
alias ll='ls -alh --color=auto'
alias la='ls -A'
alias vi='vim'
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -sh'
alias ps='ps aux'
alias netstat='netstat -tulnp'
EOF
        chmod 644 "$alias_file"
        ok "別名已寫入 $alias_file"
    else
        skip "使用者取消 alias 套用"
    fi
}

# ── B4: Kernel TCP 優化 ──────────────────────────────────────
do_b4() {
    section "B4: Kernel TCP 優化"
    local fin_timeout="${SYSEXPERT_TCP_FIN:-$(ask "TCP FIN 等待逾時秒數" "30")}"
    local sysctl_file="/etc/sysctl.d/99-sysexpert.conf"
    cat > "$sysctl_file" <<EOF
# SysExpert: Kernel Optimization (${TIMESTAMP})
net.ipv4.tcp_fin_timeout = ${fin_timeout}
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
vm.swappiness = 10
fs.file-max = 1000000
EOF
    sysctl -p "$sysctl_file" &>/dev/null && ok "sysctl 優化套用完成 (tcp_fin_timeout=${fin_timeout})" || warn "sysctl -p 失敗"
}

# ── B5: MOTD ─────────────────────────────────────────────────
do_b5() {
    section "B5: 自訂登入訊息 (MOTD)"
    local motd_msg="${SYSEXPERT_MOTD:-$(ask "請輸入歡迎標語" "Welcome to ${HOSTNAME_SHORT} | Authorized Access Only")}"
    backup_file "/etc/motd"
    cat > /etc/motd <<EOF
================================================================
  ${motd_msg}
================================================================
  Hostname : ${HOSTNAME_SHORT}
  IP       : ${HOST_IP}
  OS       : ${DISPLAY_OS}
  Time     : $(date '+%Y-%m-%d %H:%M:%S')
================================================================
EOF
    ok "MOTD 已更新"
}

# ── B6: History 強化 ─────────────────────────────────────────
do_b6() {
    section "B6: History 歷史強化"
    local histsize="${SYSEXPERT_HISTSIZE:-$(ask "History 保留筆數" "10000")}"
    local hist_file="/etc/profile.d/sysexpert_history.sh"
    cat > "$hist_file" <<EOF
# SysExpert: History Enhancement
export HISTSIZE=${histsize}
export HISTFILESIZE=${histsize}
export HISTTIMEFORMAT="%F %T  "
export HISTCONTROL=ignoredups:erasedups
shopt -s histappend 2>/dev/null || true
PROMPT_COMMAND="history -a;\${PROMPT_COMMAND:-}"
EOF
    chmod 644 "$hist_file"
    ok "History 強化設定完成 (保留 ${histsize} 筆，含時間戳記)"
}

# ── B7: 服務精簡 ─────────────────────────────────────────────
do_b7() {
    section "B7: 停用冗余服務"
    local default_svcs="avahi-daemon cups bluetooth"
    local svcs_input="${SYSEXPERT_DISABLE_SVCS:-$(ask "要停用的服務（空格分隔）" "$default_svcs")}"
    IFS=' ' read -ra svcs <<< "$svcs_input"
    for svc in "${svcs[@]}"; do
        if systemctl list-unit-files "${svc}.service" &>/dev/null | grep -q "$svc"; then
            systemctl stop "$svc" 2>/dev/null || true
            systemctl disable "$svc" 2>/dev/null || true
            ok "服務 ${svc} 已停止並禁用"
        else
            skip "服務 ${svc} 不存在"
        fi
    done
}

# ── B8: Tmp 自動清理 ─────────────────────────────────────────
do_b8() {
    section "B8: Tmp 自動清理"
    local days="${SYSEXPERT_TMP_DAYS:-$(ask "清理天數（超過幾天未使用的 /tmp 檔案）" "7")}"
    local cron_entry="0 3 * * * root find /tmp -type f -atime +${days} -delete"
    backup_file "/etc/crontab"
    # 移除舊設定
    grep -v 'SysExpert.*tmp\|find /tmp' /etc/crontab > /tmp/cron_tmp 2>/dev/null || true
    mv /tmp/cron_tmp /etc/crontab
    echo "# SysExpert: Auto-clean tmp older than ${days} days" >> /etc/crontab
    echo "$cron_entry" >> /etc/crontab
    ok "Tmp 自動清理設定完成：每日 03:00 清理超過 ${days} 天的 /tmp 檔案"
}

# ── B9: Auditd 監控 ──────────────────────────────────────────
do_b9() {
    section "B9: Auditd 監控規則"
    local watch_path="${SYSEXPERT_AUDIT_PATH:-$(ask "監控路徑" "/etc/shadow")}"
    if ! command -v auditctl &>/dev/null; then
        info "auditd 未安裝，嘗試安裝..."
        live_install "安裝 audit" $PKG_INSTALL audit auditd 2>/dev/null || warn "安裝失敗"
    fi
    local rules_file="/etc/audit/rules.d/sysexpert.rules"
    mkdir -p /etc/audit/rules.d/
    echo "# SysExpert Audit Rules" > "$rules_file"
    echo "-w ${watch_path} -p warx -k sysexpert_watch" >> "$rules_file"
    echo "-w /etc/passwd -p warx -k sysexpert_watch" >> "$rules_file"
    echo "-w /etc/sudoers -p warx -k sysexpert_watch" >> "$rules_file"
    systemctl enable auditd 2>/dev/null || true
    systemctl restart auditd 2>/dev/null && ok "Auditd 規則套用完成，監控: ${watch_path}" || warn "auditd 啟動失敗"
}

# ── B10: Syslog 強化 ─────────────────────────────────────────
do_b10() {
    section "B10: Syslog authpriv 強化"
    local log_path="${SYSEXPERT_AUTHPRIV_LOG:-$(ask "authpriv 記錄路徑" "/var/log/secure")}"
    local rsyslog_cfg="/etc/rsyslog.d/sysexpert.conf"
    cat > "$rsyslog_cfg" <<EOF
# SysExpert: Syslog Enhancement (${TIMESTAMP})
authpriv.*          ${log_path}
auth.*              ${log_path}
EOF
    systemctl restart rsyslog 2>/dev/null && ok "Syslog 規則套用完成，authpriv → ${log_path}" || warn "rsyslog 重啟失敗"
}

# ============================================================
#  全自動 A1-A18 執行
# ============================================================
do_full_auto() {
    show_header
    echo -e "  ${BOLD}${RED}⚠ 即將執行全自動初始化 (A1-A18)！${RESET}"
    echo -e "  ${YELLOW}所有變更將被記錄，修改前自動備份至 ${BACKUP_DIR}${RESET}"
    echo ""
    if ! ask_yn "確認開始全自動執行？"; then
        info "使用者取消"
        return 0
    fi
    mkdir -p "$BACKUP_DIR"
    do_a1; do_a2; do_a3
    do_a4; do_a5; do_a6; do_a7; do_a8
    do_a9; do_a10; do_a11; do_a12
    do_a13; do_a14; do_a15; do_a16
    do_a17; do_a18
    echo ""
    echo -e "${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║   ✔ 全自動初始化完成！                   ║"
    echo "  ╚══════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${WHITE}報告檔案：${RESET}${REPORT_FILE}"
    echo -e "  ${WHITE}備份目錄：${RESET}${BACKUP_DIR}"
    echo ""
    read -rp "  按 Enter 返回主選單..." _dummy 2>/dev/null || true
}

# ============================================================
#  主程式入口
# ============================================================
main() {
    # 必須 root 執行
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}[錯誤]${RESET} 此腳本需要 root 權限執行！"
        echo "  請使用: sudo $0"
        exit 1
    fi

    detect_os

    # ── 非互動模式（供 Ansible / Web 呼叫）──
    case "${1:-}" in
        --auto)
            REPORT_FILE="/tmp/Init_Report_${HOSTNAME_SHORT}_${TIMESTAMP}.log"
            log_init
            mkdir -p "$BACKUP_DIR"
            do_a1; do_a2; do_a3; do_a4; do_a5; do_a6; do_a7; do_a8
            do_a9; do_a10; do_a11; do_a12; do_a13; do_a14; do_a15; do_a16
            do_a17; do_a18
            echo "[DONE] 全自動初始化完成" >> "$REPORT_FILE"
            echo "$REPORT_FILE"
            exit 0
            ;;
        --check)
            REPORT_FILE="/tmp/Init_Report_${HOSTNAME_SHORT}_${TIMESTAMP}.log"
            log_init
            do_status_check 2>&1 | tee -a "$REPORT_FILE"
            echo "[DONE] 現況檢查完成" >> "$REPORT_FILE"
            echo "$REPORT_FILE"
            exit 0
            ;;
        --items)
            export SYSEXPERT_NOASK=1
            REPORT_FILE="/tmp/Init_Report_${HOSTNAME_SHORT}_${TIMESTAMP}.log"
            log_init
            mkdir -p "$BACKUP_DIR"
            IFS=',' read -ra _ITEMS <<< "${2:-}"
            for _item in "${_ITEMS[@]}"; do
                _item=$(echo "$_item" | tr '[:upper:]' '[:lower:]' | xargs)
                case "$_item" in
                    a1)  do_a1  ;; a2)  do_a2  ;; a3)  do_a3  ;; a4)  do_a4  ;;
                    a5)  do_a5  ;; a6)  do_a6  ;; a7)  do_a7  ;; a8)  do_a8  ;;
                    a9)  do_a9  ;; a10) do_a10 ;; a11) do_a11 ;; a12) do_a12 ;;
                    a13) do_a13 ;; a14) do_a14 ;; a15) do_a15 ;; a16) do_a16 ;;
                    a17) do_a17 ;; a18) do_a18 ;;
                    b1)  do_b1  ;; b2)  do_b2  ;; b3)  do_b3  ;; b4)  do_b4  ;;
                    b5)  do_b5  ;; b6)  do_b6  ;; b7)  do_b7  ;; b8)  do_b8  ;;
                    b9)  do_b9  ;; b10) do_b10 ;;
                    *) warn "未知項目: $_item" ;;
                esac
            done
            echo "[DONE] 選取項目執行完成: ${2:-}" >> "$REPORT_FILE"
            echo "$REPORT_FILE"
            exit 0
            ;;
        --rollback)
            # 列出備份: --rollback list
            # 還原檔案: --rollback restore <bak_path> <orig_path>
            case "${2:-}" in
                list)
                    echo "["
                    local first=true
                    for d in $(find /var/backup -maxdepth 1 -type d -name 'sysexpert_*' 2>/dev/null | sort -r); do
                        [ "$first" = true ] && first=false || echo ","
                        echo "  {\"dir\": \"$d\", \"files\": ["
                        local ffirst=true
                        if [ -f "$d/manifest.txt" ]; then
                            while IFS= read -r bak; do
                                [ -f "$bak" ] || continue
                                local orig_name; orig_name=$(basename "$bak" | sed 's/\.bak_.*//')
                                local orig_path; orig_path=$(grep "/${orig_name}" "$d/manifest.txt" 2>/dev/null | sed "s|${d}/||;s|\.bak_.*||" | head -1)
                                [ "$ffirst" = true ] && ffirst=false || echo ","
                                echo "    {\"bak\": \"$bak\", \"name\": \"$orig_name\", \"orig\": \"${orig_path:-unknown}\"}"
                            done < <(find "$d" -maxdepth 1 -name '*.bak_*' 2>/dev/null | sort)
                        fi
                        echo "  ]}"
                    done
                    echo "]"
                    exit 0
                    ;;
                restore)
                    local bak_path="${3:-}"
                    local orig_path="${4:-}"
                    if [ -z "$bak_path" ] || [ -z "$orig_path" ]; then
                        echo '{"success":false,"error":"需要 bak_path 和 orig_path"}'
                        exit 1
                    fi
                    if [ ! -f "$bak_path" ]; then
                        echo '{"success":false,"error":"備份檔不存在"}'
                        exit 1
                    fi
                    cp -p "$bak_path" "$orig_path" && echo '{"success":true,"message":"還原完成"}' || echo '{"success":false,"error":"還原失敗"}'
                    exit 0
                    ;;
            esac
            ;;
    esac

    # ── 互動模式（原始 TUI 選單）──
    log_init

    while true; do
        show_menu
        read -rp "" choice

        case "$choice" in
            A1|a1) do_full_auto ;;
            A2|a2) do_status_check ;;
            A3|a3) do_rollback ;;
            1)  do_a1;  read -rp "  按 Enter 繼續..." _ ;;
            2)  do_a2;  read -rp "  按 Enter 繼續..." _ ;;
            3)  do_a3;  read -rp "  按 Enter 繼續..." _ ;;
            4)  do_a4;  read -rp "  按 Enter 繼續..." _ ;;
            5)  do_a5;  read -rp "  按 Enter 繼續..." _ ;;
            6)  do_a6;  read -rp "  按 Enter 繼續..." _ ;;
            7)  do_a7;  read -rp "  按 Enter 繼續..." _ ;;
            8)  do_a8;  read -rp "  按 Enter 繼續..." _ ;;
            9)  do_a9;  read -rp "  按 Enter 繼續..." _ ;;
            10) do_a10; read -rp "  按 Enter 繼續..." _ ;;
            11) do_a11; read -rp "  按 Enter 繼續..." _ ;;
            12) do_a12; read -rp "  按 Enter 繼續..." _ ;;
            13) do_a13; read -rp "  按 Enter 繼續..." _ ;;
            14) do_a14; read -rp "  按 Enter 繼續..." _ ;;
            15) do_a15; read -rp "  按 Enter 繼續..." _ ;;
            16) do_a16; read -rp "  按 Enter 繼續..." _ ;;
            17) do_a17; read -rp "  按 Enter 繼續..." _ ;;
            18) do_a18; read -rp "  按 Enter 繼續..." _ ;;
            B1|b1) do_b1; read -rp "  按 Enter 繼續..." _ ;;
            B2|b2) do_b2; read -rp "  按 Enter 繼續..." _ ;;
            B3|b3) do_b3; read -rp "  按 Enter 繼續..." _ ;;
            B4|b4) do_b4; read -rp "  按 Enter 繼續..." _ ;;
            B5|b5) do_b5; read -rp "  按 Enter 繼續..." _ ;;
            B6|b6) do_b6; read -rp "  按 Enter 繼續..." _ ;;
            B7|b7) do_b7; read -rp "  按 Enter 繼續..." _ ;;
            B8|b8) do_b8; read -rp "  按 Enter 繼續..." _ ;;
            B9|b9) do_b9; read -rp "  按 Enter 繼續..." _ ;;
            B10|b10) do_b10; read -rp "  按 Enter 繼續..." _ ;;
            Q|q|quit|exit)
                echo -e "\n  ${GREEN}感謝使用系統專家維護工具。報告已儲存至: ${REPORT_FILE}${RESET}\n"
                exit 0
                ;;
            *)
                warn "無效選擇: '$choice'，請重新輸入"
                sleep 1
                ;;
        esac
    done
}

main "$@"
