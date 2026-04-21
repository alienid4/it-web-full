#!/bin/bash
# Cloudflare Tunnel 健康檢查 + 自動重啟
# 每 2 分鐘由 cron 呼叫；連續 2 次失敗才重啟，避免瞬斷誤判
# cron: */2 * * * * /opt/inspection/scripts/tunnel_healthcheck.sh

SERVICE="itagent-tunnel"
URL="${HEALTHCHECK_URL:-https://it.94alien.com/login}"
TIMEOUT=10
STATE_FILE="/run/tunnel_healthcheck.fails"
LOG_FILE="/opt/inspection/logs/tunnel_healthcheck.log"
RESTART_STAMP="/run/tunnel_healthcheck.last_restart"
GRACE_SEC=180   # 重啟後 3 分鐘內不再檢查（給 tunnel 註冊時間）
FAIL_THRESHOLD=2

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# 寬限期：上次重啟後 GRACE_SEC 秒內不檢查
if [ -f "$RESTART_STAMP" ]; then
    now=$(date +%s)
    last=$(cat "$RESTART_STAMP" 2>/dev/null || echo 0)
    if [ $((now - last)) -lt $GRACE_SEC ]; then
        exit 0
    fi
fi

# 檢查 HTTP
http_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time $TIMEOUT -L "$URL" 2>/dev/null)

if [[ "$http_code" =~ ^[23] ]]; then
    # 成功：清 counter (僅當之前有失敗時才記 log)
    if [ -s "$STATE_FILE" ]; then
        fails=$(cat "$STATE_FILE")
        log "RECOVERED http=$http_code (was fail=$fails)"
        echo 0 > "$STATE_FILE"
    else
        echo 0 > "$STATE_FILE"
    fi
    exit 0
fi

# 失敗：遞增
fails=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
fails=$((fails + 1))
echo "$fails" > "$STATE_FILE"
log "FAIL $fails/$FAIL_THRESHOLD http=$http_code url=$URL"

if [ "$fails" -ge "$FAIL_THRESHOLD" ]; then
    log "RESTART $SERVICE (consecutive fails reached threshold)"
    /usr/bin/systemctl restart "$SERVICE"
    rc=$?
    date +%s > "$RESTART_STAMP"
    echo 0 > "$STATE_FILE"
    log "RESTART rc=$rc"
fi

# Log 輪轉：超過 1000 行裁掉
if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 1000 ]; then
    tail -500 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi
