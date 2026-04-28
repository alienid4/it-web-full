#!/bin/bash
# 巡檢系統 smoke test - deploy/patch 後驗證系統真的活著
# 用法:
#   bash smoke_test.sh                    → 在本機跑 (假設 webapp 在本機)
#   bash smoke_test.sh <host>             → SSH 到遠端跑 (預設 sysinfra)
#   bash smoke_test.sh <host> <ssh_user>  → 指定 SSH 帳號
#
# 7 步驟對應 v3.11.5.0 markupsafe 教訓:
#   1-4 HTTP 健康  5 process 正確帳號  6 log 無 ERROR  7 systemd 全綠
# 任一失敗 → exit 非 0, 印失敗原因。

set -uo pipefail

HOST="${1:-localhost}"
SSH_USER="${2:-sysinfra}"
PORT="${PORT:-5000}"
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# 顏色
if [ -t 1 ]; then
    G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; N='\033[0m'
else
    G=''; R=''; Y=''; N=''
fi

PASS=0; FAIL=0
RESULTS=()

ok()   { echo -e "  ${G}[OK]${N} $*"; PASS=$((PASS+1)); RESULTS+=("OK: $*"); }
fail() { echo -e "  ${R}[FAIL]${N} $*"; FAIL=$((FAIL+1)); RESULTS+=("FAIL: $*"); }
warn() { echo -e "  ${Y}[WARN]${N} $*"; RESULTS+=("WARN: $*"); }

# SSH wrapper - 本機就直接跑, 遠端就 ssh
run_remote() {
    if [ "$HOST" = "localhost" ] || [ "$HOST" = "127.0.0.1" ]; then
        bash -c "$1"
    else
        ssh $SSH_OPTS "$SSH_USER@$HOST" "$1"
    fi
}

# 偵測 INSPECTION_HOME (公司 /opt/inspection / 家裡 /seclog/AI/inspection)
detect_home() {
    run_remote 'for p in /opt/inspection /seclog/AI/inspection; do [ -f "$p/data/version.json" ] && echo "$p" && exit 0; done; exit 1'
}

URL_BASE="http://${HOST}:${PORT}"

echo "==================================="
echo "Smoke Test: $HOST (port $PORT)"
echo "==================================="

# Step 1: version API
echo ""
echo "[1/7] HTTP /api/settings/version"
HTTP=$(curl -sS -o /tmp/smoke_ver.json -w '%{http_code}' --max-time 10 "$URL_BASE/api/settings/version" 2>&1)
if [ "$HTTP" = "200" ]; then
    VER=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]*"' /tmp/smoke_ver.json | head -1)
    ok "200, version=$VER"
else
    fail "HTTP $HTTP (預期 200)"
fi
rm -f /tmp/smoke_ver.json

# Step 2: login page
echo ""
echo "[2/7] HTTP /login"
HTTP=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$URL_BASE/login")
[ "$HTTP" = "200" ] && ok "200" || fail "HTTP $HTTP (預期 200)"

# Step 3: admin (未登入應導向 login)
echo ""
echo "[3/7] HTTP /admin (未登入應 302)"
HTTP=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$URL_BASE/admin")
case "$HTTP" in
    302|401) ok "$HTTP (正確擋未登入)" ;;
    200)     warn "200 → 確認是不是 login 頁本身" ;;
    *)       fail "HTTP $HTTP (預期 302/401)" ;;
esac

# Step 4: static asset (example.css 修過, 怕又 404)
echo ""
echo "[4/7] HTTP /static/css/example.css"
HTTP=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$URL_BASE/static/css/example.css")
[ "$HTTP" = "200" ] && ok "200" || fail "HTTP $HTTP (預期 200, 之前 sanitize 漏改踩過坑)"

# Step 5: gunicorn 跑 sysinfra (v3.11.5.0 教訓)
echo ""
echo "[5/7] gunicorn 是否以 sysinfra 跑"
GUNI_USER=$(run_remote 'PID=$(pgrep -f "gunicorn.*itagent\|gunicorn.*webapp" | head -1); [ -n "$PID" ] && ps -o user= -p "$PID" | tr -d " "' 2>/dev/null)
case "$GUNI_USER" in
    sysinfra) ok "user=sysinfra (符合 v3.11.5.0 SOP)" ;;
    root)     fail "user=root (應切 sysinfra, 走 v3.11.5.0 流程)" ;;
    "")       fail "找不到 gunicorn process" ;;
    *)        warn "user=$GUNI_USER (非預期, 確認服務狀態)" ;;
esac

# Step 6: log 無 ERROR/Traceback
echo ""
echo "[6/7] 近期 log 無 ERROR/Traceback"
HOME_DIR=$(detect_home)
if [ -z "$HOME_DIR" ]; then
    warn "找不到 INSPECTION_HOME, 跳過 log 檢查"
else
    ERR=$(run_remote "sudo tail -200 $HOME_DIR/logs/app.log 2>/dev/null | grep -ciE 'error|traceback|critical|exception'" 2>/dev/null)
    ERR=${ERR:-0}
    if [ "$ERR" -eq 0 ]; then
        ok "log 乾淨 (近 200 行)"
    elif [ "$ERR" -lt 5 ]; then
        warn "$ERR 條疑似錯誤 (容忍範圍, 但要看一下)"
    else
        fail "$ERR 條 ERROR/Traceback (查 $HOME_DIR/logs/app.log)"
    fi
fi

# Step 7: systemd
echo ""
echo "[7/7] systemd 服務狀態"
SVCS="itagent-web itagent-tunnel"
ALL_OK=true
for svc in $SVCS; do
    STATE=$(run_remote "systemctl is-active $svc 2>/dev/null" || echo "unknown")
    STATE=$(echo "$STATE" | tr -d '\r\n ')
    if [ "$STATE" = "active" ]; then
        ok "$svc: active"
    elif [ "$STATE" = "unknown" ] || [ -z "$STATE" ]; then
        warn "$svc: 服務不存在 (本機可能無此 service)"
    else
        fail "$svc: $STATE"
        ALL_OK=false
    fi
done

# 總結
echo ""
echo "==================================="
if [ "$FAIL" -eq 0 ]; then
    echo -e "${G}Smoke Test 全綠 (PASS=$PASS, FAIL=0)${N}"
    echo "==================================="
    exit 0
else
    echo -e "${R}Smoke Test 失敗 (PASS=$PASS, FAIL=$FAIL)${N}"
    echo "==================================="
    echo ""
    echo "失敗清單:"
    for r in "${RESULTS[@]}"; do
        case "$r" in FAIL:*) echo "  $r" ;; esac
    done
    exit 1
fi
