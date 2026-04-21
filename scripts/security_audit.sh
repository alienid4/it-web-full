#!/bin/bash
# ============================================================
# LINUX 系統安全稽核腳本（完整版）
# 支援系統與版本：
#   Red Hat 系：RHEL 7/8/9、CentOS 7/8、Rocky 8/9、AlmaLinux 8/9
#   Debian  系：Debian 10/11/12、Ubuntu 20.04/22.04/24.04
# 對應稽核表格：類別一 ~ 類別六
# 超過 100 行的檔案另存至 /tmp/Audit_*.$DATE 並打包壓縮
# ============================================================

HOSTNAME=$(hostname)
IP_ADDR=$(hostname -I | awk '{print $1}')
DATE_FULL=$(date "+%Y-%m-%d %H:%M:%S")
DATE=$(date +%Y%m%d)
REPORT="/tmp/Audit_Report_${HOSTNAME}_${DATE}.txt"

# ── 可配置參數（環境變數覆蓋）──
AUDIT_CAT1="${AUDIT_CAT1:-1}"         # 類別一：版本確認 (1=啟用 0=停用)
AUDIT_CAT2="${AUDIT_CAT2:-1}"         # 類別二：密碼原則
AUDIT_CAT3="${AUDIT_CAT3:-1}"         # 類別三：帳號權限
AUDIT_CAT4="${AUDIT_CAT4:-1}"         # 類別四：敏感檔案權限
AUDIT_CAT5="${AUDIT_CAT5:-1}"         # 類別五：網路安全
AUDIT_CAT6="${AUDIT_CAT6:-1}"         # 類別六：日誌稽核
AUDIT_LARGE_LINES="${AUDIT_LARGE_LINES:-100}"    # 大檔案截斷行數
AUDIT_LAST_N="${AUDIT_LAST_N:-20}"               # 登入紀錄顯示筆數
AUDIT_ARCHIVE="${AUDIT_ARCHIVE:-1}"              # 是否產生壓縮封存 (1/0)
AUDIT_SVC_HEAD="${AUDIT_SVC_HEAD:-30}"           # 服務列表顯示筆數
AUDIT_SERVICES_HEAD="${AUDIT_SERVICES_HEAD:-50}" # /etc/services 顯示行數

# ============================================================
# 一、偵測系統類型與主版本號
# ============================================================
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_TYPE="${ID,,}"
    OS_NAME="${PRETTY_NAME}"
    OS_VER_FULL="${VERSION_ID:-unknown}"
    OS_VER="${OS_VER_FULL%%.*}"
else
    OS_TYPE="unknown"
    OS_NAME="Linux (unknown)"
    OS_VER_FULL="unknown"
    OS_VER="0"
fi

case "$OS_TYPE" in
    debian|ubuntu|linuxmint|pop)
        OS_FAMILY="deb" ;;
    centos|rhel|rocky|almalinux|ol|fedora|amzn)
        OS_FAMILY="rhel" ;;
    *)
        OS_FAMILY="rhel" ;;
esac

# ============================================================
# 二、依版本決定各工具 / 路徑差異
# ============================================================

if [[ "$OS_FAMILY" == "deb" ]]; then
    PKG_UPDATE_CMD="apt-get update -qq 2>/dev/null; apt list --upgradable 2>/dev/null | grep -i security || echo 'No security updates needed.'"
elif command -v dnf &>/dev/null; then
    PKG_UPDATE_CMD="dnf --security check-update 2>/dev/null; echo '(結束碼 100=有更新 0=無更新)'"
else
    PKG_UPDATE_CMD="yum --security check-update 2>/dev/null; echo '(結束碼 100=有更新 0=無更新)'"
fi

if [[ "$OS_FAMILY" == "deb" ]]; then
    PAM_AUTH_PATH="/etc/pam.d/common-auth"
    PAM_PASS_PATH="/etc/pam.d/common-password"
else
    PAM_AUTH_PATH="/etc/pam.d/system-auth"
    PAM_PASS_PATH="/etc/pam.d/system-auth"
fi

if [[ "$OS_FAMILY" == "rhel" && "$OS_VER" == "7" ]]; then
    PAM_LOCK_MOD="pam_tally2"
    PAM_LOCK_CONF=""
    PAM_LOCK_CMD="pam_tally2 --user=root 2>/dev/null || echo 'pam_tally2 不可用'"
else
    PAM_LOCK_MOD="pam_faillock"
    PAM_LOCK_CONF="/etc/security/faillock.conf"
    PAM_LOCK_CMD="faillock --user root 2>/dev/null || echo 'faillock 不可用'"
fi

if [[ "$OS_FAMILY" == "deb" && "$OS_VER" -le 10 ]]; then
    PAM_LOCK_MOD2="pam_tally2"
else
    PAM_LOCK_MOD2="pam_faillock"
fi

if [[ "$OS_FAMILY" == "rhel" && "$OS_VER" -ge 8 ]]; then
    HAS_AUTHSELECT=true
else
    HAS_AUTHSELECT=false
fi

PWQUALITY_CONF="/etc/security/pwquality.conf"

SELINUX_CONF=""
for f in /etc/sysconfig/selinux /etc/selinux/config; do
    [ -f "$f" ] && SELINUX_CONF="$f" && break
done

if [[ "$OS_FAMILY" == "deb" ]]; then
    SECURE_LOG="/var/log/auth.log"
    SECURE_LABEL="auth_log"
else
    SECURE_LOG="/var/log/secure"
    SECURE_LABEL="secure_log"
fi

AUDIT_RULES="/etc/audit/audit.rules"
AUDIT_RULES_D="/etc/audit/rules.d"

# ============================================================
# 三、共用函數
# ============================================================

copy_if_large() {
    local src="$1"
    local label="$2"
    local dest="/tmp/Audit_${label}.${DATE}"

    if [ ! -f "$src" ]; then
        echo "  ⚠ 檔案不存在：$src" >> "$REPORT"
        return
    fi

    local lines
    lines=$(wc -l < "$src")

    if [ "$lines" -gt "$AUDIT_LARGE_LINES" ]; then
        cp "$src" "$dest"
        echo "  ℹ 檔案行數 $lines 行（>100），已另存至：$dest" >> "$REPORT"
        echo "  （報表僅顯示前 20 行）" >> "$REPORT"
        echo "" >> "$REPORT"
        head -20 "$src" >> "$REPORT"
        echo "  ... (略，完整內容請參閱 $dest)" >> "$REPORT"
    else
        cat "$src" >> "$REPORT"
    fi
}

render_item() {
    local id="$1"
    local title="$2"
    shift 2
    local cmds=("$@")

    echo "------------------------------------------------------------" >> "$REPORT"
    echo "【$id】$title" >> "$REPORT"
    echo "" >> "$REPORT"

    for cmd in "${cmds[@]}"; do
        echo "指令: $cmd" >> "$REPORT"
        echo "[root@$HOSTNAME ~]# date" >> "$REPORT"
        date >> "$REPORT"
        echo "[root@$HOSTNAME ~]# $cmd" >> "$REPORT"
        eval "$cmd" >> "$REPORT" 2>/dev/null
        echo "[root@$HOSTNAME ~]# " >> "$REPORT"
        echo "" >> "$REPORT"
    done
}

render_file() {
    local id="$1"
    local title="$2"
    local src="$3"
    local label="$4"

    echo "------------------------------------------------------------" >> "$REPORT"
    echo "【$id】$title" >> "$REPORT"
    echo "" >> "$REPORT"
    echo "指令: cat $src" >> "$REPORT"
    echo "[root@$HOSTNAME ~]# date" >> "$REPORT"
    date >> "$REPORT"
    echo "[root@$HOSTNAME ~]# cat $src" >> "$REPORT"
    copy_if_large "$src" "$label"
    echo "[root@$HOSTNAME ~]# " >> "$REPORT"
    echo "" >> "$REPORT"
}

# ============================================================
# 四、報表抬頭
# ============================================================
{
echo "============================================================"
echo "  LINUX 系統安全稽核操作紀錄 (Screen Capture)"
echo "  主機名稱 (Hostname)   : $HOSTNAME"
echo "  網路位址 (IP Address) : $IP_ADDR"
echo "  作業系統 (OS Version) : $OS_NAME"
echo "  版本識別 (ID/VER)     : $OS_TYPE $OS_VER_FULL  [Family: $OS_FAMILY]"
echo "  PAM 認證模組          : $PAM_LOCK_MOD"
if $HAS_AUTHSELECT; then
echo "  PAM 管理方式          : authselect (RHEL $OS_VER)"
fi
echo "  執行時間 (Report Date): $DATE_FULL"
echo "============================================================"
echo ""
} > "$REPORT"

# ============================================================
# 【類別一】使用版本確認 EOS 及修補
# ============================================================
if [ "$AUDIT_CAT1" = "1" ]; then
echo "【類別一】使用版本確認 EOS 及修補" >> "$REPORT"

render_item "1.1" "作業系統版本" \
    "ls -l /etc/*-release" \
    "cat /etc/os-release"

render_item "1.2" "安全性更新" "$PKG_UPDATE_CMD"
fi

# ============================================================
# 【類別二】帳號密碼原則參數設定
# ============================================================
if [ "$AUDIT_CAT2" = "1" ]; then
echo "" >> "$REPORT"
echo "【類別二】帳號密碼原則參數設定" >> "$REPORT"
{
echo "  PAM_AUTH : $PAM_AUTH_PATH"
echo "  PAM_PASS : $PAM_PASS_PATH"
echo "  LOCK_MOD : $PAM_LOCK_MOD"
[ -n "$PAM_LOCK_CONF" ] && echo "  LOCK_CONF: $PAM_LOCK_CONF"
$HAS_AUTHSELECT && echo "  ⚠ 此系統使用 authselect 管理 PAM，system-auth 為自動產生，請同時參考 authselect current"
} >> "$REPORT"
echo "" >> "$REPORT"

render_item "2.1" "密碼原則－密碼歷史代數 (remember)" \
    "grep -i 'remember' $PAM_PASS_PATH 2>/dev/null || echo '未設定 remember'"

if $HAS_AUTHSELECT; then
    render_item "2.1" "authselect 目前設定（RHEL $OS_VER）" \
        "authselect current 2>/dev/null || echo 'authselect 不可用'"
fi

render_item "2.2" "密碼原則－密碼的最短經歷時間 (PASS_MIN_DAYS)" \
    "grep '^PASS_MIN_DAYS' /etc/login.defs || echo '未找到 PASS_MIN_DAYS'"

render_item "2.3" "密碼原則－密碼的最長經歷時間 (PASS_MAX_DAYS)" \
    "grep '^PASS_MAX_DAYS' /etc/login.defs || echo '未找到 PASS_MAX_DAYS'"

render_item "2.4" "密碼原則－密碼到期警告時間 (PASS_WARN_AGE)" \
    "grep '^PASS_WARN_AGE' /etc/login.defs || echo '未找到 PASS_WARN_AGE'"

render_item "2.5" "密碼原則－密碼的最小長度 (minlen)" \
    "grep '^PASS_MIN_LEN' /etc/login.defs 2>/dev/null || echo '（login.defs 無 PASS_MIN_LEN）'" \
    "grep 'minlen' $PAM_PASS_PATH 2>/dev/null || echo '（PAM 無 minlen）'" \
    "grep '^minlen' $PWQUALITY_CONF 2>/dev/null || echo '（pwquality.conf 無 minlen）'"

render_item "2.6" "密碼原則－複雜度－大寫字母個數 (ucredit)" \
    "grep -i 'ucredit' $PAM_PASS_PATH $PWQUALITY_CONF 2>/dev/null || echo '未設定 ucredit'"

render_item "2.7" "密碼原則－複雜度－小寫字母個數 (lcredit)" \
    "grep -i 'lcredit' $PAM_PASS_PATH $PWQUALITY_CONF 2>/dev/null || echo '未設定 lcredit'"

render_item "2.8" "密碼原則－複雜度－數字個數 (dcredit)" \
    "grep -i 'dcredit' $PAM_PASS_PATH $PWQUALITY_CONF 2>/dev/null || echo '未設定 dcredit'"

render_item "2.9" "密碼原則－複雜度－其他字元個數 (ocredit / minclass)" \
    "grep -iE 'ocredit|minclass' $PAM_PASS_PATH $PWQUALITY_CONF 2>/dev/null || echo '未設定 ocredit/minclass'"

render_item "2.10" "密碼原則－帳號鎖定次數 (deny)" \
    "grep -E 'pam_tally2|pam_faillock' $PAM_AUTH_PATH 2>/dev/null || echo '未在 PAM 設定鎖定模組'"

if [[ "$OS_FAMILY" == "rhel" && "$OS_VER" == "7" ]]; then
    render_item "2.10" "RHEL 7 pam_tally2 目前計數" \
        "pam_tally2 --user=root 2>/dev/null || echo 'pam_tally2 不可用'"
    render_item "2.10" "RHEL 7 password-auth 鎖定設定" \
        "grep -E 'pam_tally2|deny' /etc/pam.d/password-auth 2>/dev/null || echo '無 password-auth 設定'"
else
    render_item "2.10" "faillock.conf 鎖定設定" \
        "cat $PAM_LOCK_CONF 2>/dev/null | grep -v '^#' | grep -v '^\$' || echo '無 faillock.conf 或無有效設定'"
    render_item "2.10" "faillock 目前鎖定狀態" \
        "faillock --user root 2>/dev/null || echo 'faillock 不可用'"
fi

render_item "2.11" "密碼原則－帳號鎖定的解鎖時間 (unlock_time)" \
    "grep -E 'unlock_time' $PAM_AUTH_PATH 2>/dev/null || echo '未在 PAM 設定 unlock_time'"

if [[ -n "$PAM_LOCK_CONF" ]]; then
    render_item "2.11" "faillock.conf unlock_time" \
        "grep '^unlock_time' $PAM_LOCK_CONF 2>/dev/null || echo '（faillock.conf 無 unlock_time）'"
fi

if [[ "$OS_FAMILY" == "rhel" && "$OS_VER" == "7" ]]; then
    render_item "2.11" "RHEL 7 pam_tally2 解鎖時間" \
        "grep -E 'unlock_time' /etc/pam.d/system-auth /etc/pam.d/password-auth 2>/dev/null || echo '未設定 unlock_time'"
fi

fi

# ============================================================
# 【類別三】系統帳號清單及帳號權限檢視
# ============================================================
if [ "$AUDIT_CAT3" = "1" ]; then
echo "" >> "$REPORT"
echo "【類別三】系統帳號清單及帳號權限檢視" >> "$REPORT"

render_item "3.1" "帳號新增預設設定 (/etc/default/useradd)" \
    "grep -v '^#' /etc/default/useradd 2>/dev/null | grep -v '^\$' || echo '無有效設定'"

render_file "3.2" "本機帳號清單 (/etc/passwd)" \
    "/etc/passwd" "passwd"
render_item "3.2" "本機帳號清單（一般使用者 UID>=1000）" \
    "awk -F: '\$3 >= 1000 && \$3 < 65534 {print \$1, \$3, \$6, \$7}' /etc/passwd"

render_item "3.3" "本機帳號密碼檔 (ls -l)" \
    "ls -l /etc/shadow"
render_file "3.3" "本機帳號密碼檔 (/etc/shadow)" \
    "/etc/shadow" "shadow"

render_item "3.6" "本機群組清單 (ls -l)" \
    "ls -l /etc/group"
render_file "3.6" "本機群組清單 (/etc/group)" \
    "/etc/group" "group"

render_item "3.7" "本機群組密碼檔 (ls -l)" \
    "ls -l /etc/gshadow"
render_file "3.7" "本機群組密碼檔 (/etc/gshadow)" \
    "/etc/gshadow" "gshadow"

render_item "3.7" "最高權限帳號身分轉換指令權限 (ls -l)" \
    "ls -l /etc/sudoers" \
    "ls -l /etc/sudoers.d/ 2>/dev/null || echo '無 sudoers.d 目錄'"
render_file "3.7" "sudoers 內容 (/etc/sudoers)" \
    "/etc/sudoers" "sudoers"

fi

# ============================================================
# 【類別四】敏感檔案及目錄權限
# ============================================================
if [ "$AUDIT_CAT4" = "1" ]; then
echo "" >> "$REPORT"
echo "【類別四】敏感檔案及目錄權限" >> "$REPORT"

render_item "4.1" "密碼相關檔案的檔案權限" \
    "ls -l /etc/passwd /etc/shadow /etc/group /etc/gshadow /etc/default/useradd 2>/dev/null"

render_item "4.2" "指定檔案的檔案權限" \
    "ls -l /etc/shadow" \
    "ls -l /etc/audit/auditd.conf 2>/dev/null || echo '無 /etc/audit/auditd.conf'" \
    "ls -l /var/log/audit/ 2>/dev/null || echo '無 /var/log/audit/ 目錄'"

render_item "4.3" "指定目錄及該目錄下所有檔案的權限" \
    "ls -la /var/log/audit/ 2>/dev/null || echo '無 /var/log/audit/ 目錄'"

fi

# ============================================================
# 【類別五】網路安全服務
# ============================================================
if [ "$AUDIT_CAT5" = "1" ]; then
echo "" >> "$REPORT"
echo "【類別五】網路安全服務" >> "$REPORT"

render_item "5.1" "遠端連線管控（hosts.allow / hosts.deny）" \
    "cat /etc/hosts.allow 2>/dev/null || echo '無 hosts.allow'" \
    "cat /etc/hosts.deny 2>/dev/null || echo '無 hosts.deny'"

render_item "5.2" "遠端登錄安全設定 (ls -l)" \
    "ls -l /etc/ssh/sshd_config"
render_file "5.2" "遠端登錄安全設定 (/etc/ssh/sshd_config)" \
    "/etc/ssh/sshd_config" "sshd_config"
render_item "5.2" "sshd_config 有效設定（去除註解）" \
    "grep -v '^#' /etc/ssh/sshd_config | grep -v '^\$'"

if [[ ( "$OS_FAMILY" == "rhel" && "$OS_VER" -ge 9 ) || ( "$OS_FAMILY" == "deb" && "$OS_VER" -ge 12 ) ]]; then
    render_item "5.2" "sshd_config.d 目錄（新版額外設定）" \
        "ls -l /etc/ssh/sshd_config.d/ 2>/dev/null || echo '無 sshd_config.d 目錄'" \
        "grep -r '' /etc/ssh/sshd_config.d/ 2>/dev/null | grep -v '^#' || echo '目錄為空或無有效設定'"
fi

render_item "5.3" "管理服務安全設定 (ls -l /etc/services)" \
    "ls -l /etc/services"
render_file "5.3" "管理服務安全設定 (/etc/services)" \
    "/etc/services" "services"

render_item "5.4" "禁止 root 從遠端登入" \
    "grep -i 'PermitRootLogin' /etc/ssh/sshd_config 2>/dev/null || echo '未設定 PermitRootLogin'" \
    "cat /etc/httpd/conf/httpd.conf 2>/dev/null | grep -iE '^User|^Group' | head -5 || echo '無 httpd.conf'"

if [[ "$OS_FAMILY" == "rhel" ]]; then
    render_item "5.5" "啟動 SELinux 設定 ($SELINUX_CONF)" \
        "cat $SELINUX_CONF 2>/dev/null || echo '無 SELinux 設定檔'" \
        "grep '^SELINUX=' $SELINUX_CONF 2>/dev/null || echo '未找到 SELINUX= 設定'"
    render_item "5.6" "查看 SELinux 狀態 (sestatus)" \
        "sestatus 2>/dev/null || echo 'sestatus 不可用'"
else
    render_item "5.5" "AppArmor 狀態（Debian/Ubuntu 以 AppArmor 取代 SELinux）" \
        "apparmor_status 2>/dev/null || aa-status 2>/dev/null || echo 'AppArmor 不可用或未安裝'"
    render_item "5.6" "SELinux 狀態（Debian/Ubuntu 通常不啟用，僅確認）" \
        "sestatus 2>/dev/null || echo 'SELinux 未安裝（此系統使用 AppArmor）'"
fi

render_item "5.7" "使用中的服務（監聽服務）" \
    "ss -plnt 2>/dev/null || netstat -plnt 2>/dev/null" \
    "systemctl list-units --type=service --state=running 2>/dev/null | head -$AUDIT_SVC_HEAD"

render_item "5.8" "使用已定義檔案驗證服務（/etc/services 前 50 行）" \
    "head -$AUDIT_SERVICES_HEAD /etc/services"

render_item "5.9" "顯示本機開啟的 TCP Port" \
    "ss -ant 2>/dev/null | grep LISTEN || netstat -ant 2>/dev/null | grep LISTEN" \
    "nmap localhost 2>/dev/null || echo 'nmap 未安裝'"

fi

# ============================================================
# 【類別六】日誌與稽核紀錄
# ============================================================
if [ "$AUDIT_CAT6" = "1" ]; then
echo "" >> "$REPORT"
echo "【類別六】日誌與稽核紀錄" >> "$REPORT"

render_item "6.1" "事件稽核紀錄設定 (ls -l)" \
    "ls -l $AUDIT_RULES 2>/dev/null || echo '無 audit.rules'" \
    "ls -l $AUDIT_RULES_D/ 2>/dev/null || echo '無 rules.d 目錄'"
render_file "6.1" "稽核規則 ($AUDIT_RULES)" \
    "$AUDIT_RULES" "audit_rules"

if [[ "$OS_FAMILY" == "rhel" && "$OS_VER" -ge 8 ]]; then
    render_item "6.1" "rules.d 目錄下的規則檔（RHEL $OS_VER）" \
        "ls -l $AUDIT_RULES_D/ 2>/dev/null" \
        "cat $AUDIT_RULES_D/*.rules 2>/dev/null | grep -v '^#' | grep -v '^\$' || echo '無有效規則'"
fi

render_item "6.1" "目前載入的稽核規則 (auditctl -l)" \
    "auditctl -l 2>/dev/null || echo 'auditctl 不可用'"

render_item "6.2" "查核稽核紀錄 (ls -l)" \
    "ls -l $SECURE_LOG 2>/dev/null; ls -l /var/log/audit/audit.log 2>/dev/null"

render_file "6.2" "稽核日誌 (/var/log/audit/audit.log)" \
    "/var/log/audit/audit.log" "audit_log"

render_file "6.2" "認證日誌 ($SECURE_LOG)" \
    "$SECURE_LOG" "$SECURE_LABEL"

RSYSLOG_CONF="/etc/rsyslog.conf"
[ -f "/etc/syslog.conf" ] && RSYSLOG_CONF="/etc/syslog.conf"
render_item "6.2" "syslog 設定 (ls -l)" \
    "ls -l $RSYSLOG_CONF 2>/dev/null || echo '無 rsyslog.conf'"
render_file "6.2" "syslog 設定內容 ($RSYSLOG_CONF)" \
    "$RSYSLOG_CONF" "rsyslog_conf"

render_item "6.3" "重要日誌紀錄權限" \
    "ls -l \
        /var/log/auth.log \
        /var/log/secure \
        /var/log/syslog \
        /var/log/lastlog \
        /var/log/faillog \
        /var/log/messages \
        /var/log/boot.log \
        /var/log/cron \
        /var/log/adm/sulog \
        /var/log/audit/audit.log \
        2>/dev/null | grep -v 'cannot access'"

render_item "6.3" "非預期登入紀錄 (last / lastb)" \
    "last -n $AUDIT_LAST_N" \
    "lastb -n $AUDIT_LAST_N 2>/dev/null || echo 'lastb 需要 root 或不可用'"

fi

# ============================================================
# 五、壓縮封存
# ============================================================
if [ "$AUDIT_ARCHIVE" = "1" ]; then
ARCHIVE="/tmp/Audit_${HOSTNAME}_${DATE}.tar.gz"

AUDIT_FILES=()
while IFS= read -r f; do
    AUDIT_FILES+=("$f")
done < <(ls /tmp/Audit_*.${DATE} 2>/dev/null)
AUDIT_FILES+=("$REPORT")

tar -czf "$ARCHIVE" "${AUDIT_FILES[@]}" 2>/dev/null

{
echo ""
echo "============================================================"
echo "  稽核報表產製完成"
echo "  系統：$OS_NAME  [$OS_TYPE $OS_VER_FULL / Family: $OS_FAMILY]"
echo "  報表路徑：$REPORT"
echo "  產製時間：$(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "  【另存大型檔案清單（行數 > 100）】"
ls /tmp/Audit_*.${DATE} 2>/dev/null | grep -v "$REPORT" | grep -v ".tar.gz" | while read f; do
    echo "  - $f  ($(wc -l < "$f") 行)"
done
echo ""
echo "  【壓縮封存】"
echo "  封存路徑：$ARCHIVE"
echo "  封存大小：$(du -sh "$ARCHIVE" 2>/dev/null | cut -f1)"
echo "============================================================"
} >> "$REPORT"

else
# 不壓縮封存
{
echo ""
echo "============================================================"
echo "  稽核報表產製完成（未壓縮）"
echo "  系統：$OS_NAME  [$OS_TYPE $OS_VER_FULL / Family: $OS_FAMILY]"
echo "  報表路徑：$REPORT"
echo "  產製時間：$(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
} >> "$REPORT"
fi

# 輸出報告路徑供 Ansible fetch
echo "$REPORT"
