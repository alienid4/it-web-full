#!/bin/bash
# 緊急 rollback：把 itagent-web 切回 Flask dev server
# 使用時機：gunicorn 改造後發現嚴重問題，需立即回到 v3.4.19 時的狀態
set -e
BAK=$(ls -t /etc/systemd/system/itagent-web.service.bak_before_gunicorn_* 2>/dev/null | head -1)
if [ -z "$BAK" ]; then
    echo 'ERROR: 找不到 itagent-web.service 備份！' >&2
    exit 1
fi
echo "Rollback from: $BAK"
cp "$BAK" /etc/systemd/system/itagent-web.service
systemctl daemon-reload
systemctl restart itagent-web
sleep 3
systemctl status itagent-web --no-pager | head -15
echo '=== rollback done ==='
