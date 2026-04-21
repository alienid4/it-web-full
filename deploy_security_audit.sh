#!/bin/bash
# ============================================================
#  稽核專區功能部署腳本
#  用途: 將稽核專區相關檔案部署到 ansible-host 伺服器
#  日期: 2026-04-14
# ============================================================

set -e
INSPECTION_HOME="/seclog/AI/inspection"
BACKUP_DIR="/seclog/backup/pre_security_audit_$(date +%Y%m%d_%H%M%S)"

echo "========================================"
echo "  稽核專區 — 部署腳本"
echo "========================================"

# --- Step 1: 備份現有檔案 ---
echo ""
echo "[1/4] 備份現有檔案到 $BACKUP_DIR ..."
mkdir -p "$BACKUP_DIR"
cp -p "$INSPECTION_HOME/webapp/templates/admin.html"     "$BACKUP_DIR/admin.html.bak"     2>/dev/null && echo "  ✓ admin.html" || echo "  - admin.html (不存在，跳過)"
cp -p "$INSPECTION_HOME/webapp/app.py"                    "$BACKUP_DIR/app.py.bak"          2>/dev/null && echo "  ✓ app.py" || echo "  - app.py (不存在，跳過)"
cp -p "$INSPECTION_HOME/webapp/static/js/admin.js"        "$BACKUP_DIR/admin.js.bak"        2>/dev/null && echo "  ✓ admin.js" || echo "  - admin.js (不存在，跳過)"
echo "  備份完成: $BACKUP_DIR"

# --- Step 2: 建立必要目錄 ---
echo ""
echo "[2/4] 建立目錄 ..."
mkdir -p "$INSPECTION_HOME/data/security_audit_reports"
mkdir -p "$INSPECTION_HOME/scripts"
echo "  ✓ data/security_audit_reports/"
echo "  ✓ scripts/"

# --- Step 3: 複製檔案 (需要先把開發檔放到 /tmp/deploy_audit/) ---
echo ""
echo "[3/4] 複製檔案 ..."
STAGE="/tmp/deploy_audit"

if [ ! -d "$STAGE" ]; then
    echo "  ✗ 錯誤: 請先將開發檔案上傳到 $STAGE/"
    echo ""
    echo "  在本機執行："
    echo "    scp tmp_admin.html tmp_app.py tmp_api_security_audit.py ansible-host:/tmp/deploy_audit/"
    echo "    scp audit_build/admin.js ansible-host:/tmp/deploy_audit/"
    echo "    scp scripts/security_audit.sh ansible-host:/tmp/deploy_audit/"
    echo "    scp tmp_security_audit_playbook.yml ansible-host:/tmp/deploy_audit/"
    exit 1
fi

cp -p "$STAGE/tmp_admin.html"                "$INSPECTION_HOME/webapp/templates/admin.html"
echo "  ✓ templates/admin.html"

cp -p "$STAGE/tmp_app.py"                    "$INSPECTION_HOME/webapp/app.py"
echo "  ✓ app.py"

cp -p "$STAGE/tmp_api_security_audit.py"     "$INSPECTION_HOME/webapp/routes/api_security_audit.py"
echo "  ✓ routes/api_security_audit.py (新增)"

cp -p "$STAGE/admin.js"                      "$INSPECTION_HOME/webapp/static/js/admin.js"
echo "  ✓ static/js/admin.js"

cp -p "$STAGE/security_audit.sh"             "$INSPECTION_HOME/scripts/security_audit.sh"
chmod +x "$INSPECTION_HOME/scripts/security_audit.sh"
echo "  ✓ scripts/security_audit.sh (新增, +x)"

cp -p "$STAGE/tmp_security_audit_playbook.yml" "$INSPECTION_HOME/ansible/playbooks/security_audit.yml"
echo "  ✓ ansible/playbooks/security_audit.yml (新增)"

# --- Step 4: 重啟 Flask ---
echo ""
echo "[4/4] 重啟 Flask 服務 ..."
cd "$INSPECTION_HOME"
if command -v podman &>/dev/null && podman ps --format '{{.Names}}' | grep -q inspection; then
    podman restart inspection
    echo "  ✓ podman container 已重啟"
elif systemctl is-active --quiet inspection; then
    systemctl restart inspection
    echo "  ✓ systemd service 已重啟"
else
    echo "  ⚠ 請手動重啟 Flask 服務"
fi

echo ""
echo "========================================"
echo "  部署完成！"
echo "  請到 https://it.94alien.com/admin"
echo "  點選「📋 稽核專區」→「🔒 系統安全稽核」"
echo "========================================"
echo "  備份位置: $BACKUP_DIR"
echo "========================================"
