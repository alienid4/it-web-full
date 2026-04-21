#!/bin/bash
# 打包原始碼 + bootstrap, 排除機密與歷史資料
# 產出: /opt/inspection/data/uploads/inspection_source_vX.X.X.X.tar.gz
set -e

INSPECTION_HOME=/opt/inspection
cd "${INSPECTION_HOME}"

VERSION=$(python3 -c "import json; print(json.load(open('data/version.json'))['version'])")
STAMP=$(date +%Y%m%d_%H%M%S)
OUT_DIR="${INSPECTION_HOME}/data/uploads"
mkdir -p "${OUT_DIR}"

TMPDIR=$(mktemp -d)
STAGE="${TMPDIR}/inspection_source_v${VERSION}"
mkdir -p "${STAGE}"

echo "[1/6] 複製 webapp/ (排除 .bak / __pycache__)"
mkdir -p "${STAGE}/webapp"
tar cf - --exclude='__pycache__' --exclude='*.bak*' --exclude='*.pyc' -C webapp . | tar xf - -C "${STAGE}/webapp/"

echo "[2/6] 複製 ansible/ (排除 .vault_pass)"
mkdir -p "${STAGE}/ansible"
tar cf - --exclude='.vault_pass' --exclude='*.bak*' -C ansible . | tar xf - -C "${STAGE}/ansible/"

echo "[3/6] 複製 scripts/ (all)"
mkdir -p "${STAGE}/scripts"
tar cf - -C scripts . | tar xf - -C "${STAGE}/scripts/"

echo "[4/6] 複製 systemd/ (all)"
mkdir -p "${STAGE}/systemd"
[ -d systemd ] && tar cf - -C systemd . 2>/dev/null | tar xf - -C "${STAGE}/systemd/" 2>/dev/null || true
# 另外從 /etc/systemd/system/ 抓 itagent-*.service
mkdir -p "${STAGE}/systemd/"
cp /etc/systemd/system/itagent-*.service "${STAGE}/systemd/" 2>/dev/null || true

echo "[5/6] 複製 bootstrap + requirements + 文件"
cp scripts/bootstrap.py "${STAGE}/" 2>/dev/null || true
cp webapp/requirements.txt "${STAGE}/"
cp data/OFFLINE_DEPS.md "${STAGE}/" 2>/dev/null || true
cp data/REBUILD_FROM_ZERO_SKILL.md "${STAGE}/" 2>/dev/null || true
cp data/RUNBOOK.md "${STAGE}/" 2>/dev/null || true
cp data/version.json "${STAGE}/"

# README 安裝指南
cat > "${STAGE}/README_INSTALL.md" << EOF
# IT 監控系統 — 離線安裝包 v${VERSION}

產製時間: $(date '+%Y-%m-%d %H:%M')

## 包含

- webapp/          — Flask 應用 (routes/services/templates/static)
- ansible/         — Ansible roles/playbooks/inventory (**不含 .vault_pass**, 需重建)
- scripts/         — 管理腳本 (tunnel_healthcheck, cio_monthly_report 等)
- systemd/         — 3 個 service unit (itagent-web/db/tunnel)
- bootstrap.py     — MongoDB 初始化 (建帳號/索引/feature_flags 預設)
- requirements.txt — Python 套件清單 (35 個)
- OFFLINE_DEPS.md  — 套件下載連結
- REBUILD_FROM_ZERO_SKILL.md — 完整重建指南
- RUNBOOK.md       — 常見問題排查
- version.json     — 版本號

## 不含 (需重建)

- ansible/.vault_pass     — Ansible Vault 密碼
- webapp/config.py 的 SECRET_KEY — Flask session 簽章 (bootstrap 會幫產)
- /root/.cloudflared/*     — Tunnel 憑證 (內網不需要)
- /root/.ssh/id_*          — 控制機 SSH 私鑰

## 安裝順序 (Rocky Linux 9.x)

### 1. 裝 RPM (從 Rocky 公司內部 mirror 或白名單 repo)
\`\`\`bash
sudo dnf install -y epel-release
sudo dnf install -y podman ansible-core python3-pip openssh-server \\
    openssh-clients net-snmp-utils google-noto-sans-cjk-ttc-fonts nmon
\`\`\`

### 2. 裝 MongoDB 6 (YUM repo)
\`\`\`bash
cat > /etc/yum.repos.d/mongodb-org-6.0.repo << REPO
[mongodb-org-6.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/6.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-6.0.asc
REPO

sudo dnf install -y mongodb-org
sudo systemctl enable --now mongod
\`\`\`

### 3. 安裝 Python wheels
\`\`\`bash
# 方式 A: 在有網機用 pip download 一次抓
pip3 install -r requirements.txt

# 方式 B: 離線: 你把 wheels/ 打包過來
sudo pip3 install --no-index --find-links=wheels/ -r requirements.txt
\`\`\`

### 4. 部署程式
\`\`\`bash
sudo mkdir -p /opt/inspection
sudo tar xzf inspection_source_v${VERSION}.tar.gz -C /opt/inspection --strip-components=1
cd /opt/inspection
\`\`\`

### 5. 初始化 DB
\`\`\`bash
python3 scripts/bootstrap.py --auto  # 全預設, 密碼 changeme123
# 或互動:
# python3 scripts/bootstrap.py
\`\`\`

### 6. 產 Ansible Vault 密碼
\`\`\`bash
openssl rand -base64 32 > /opt/inspection/ansible/.vault_pass
chmod 600 /opt/inspection/ansible/.vault_pass
\`\`\`

### 7. 裝 systemd services
\`\`\`bash
sudo cp /opt/inspection/systemd/itagent-*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now itagent-web
# itagent-db 如果用 native MongoDB (步驟 2) 就不用, 已是 mongod
# itagent-tunnel 若不對外可略
\`\`\`

### 8. 驗證
\`\`\`bash
curl -s http://127.0.0.1:5000/login | head -20   # 應看到 HTML
systemctl is-active itagent-web mongod          # 應 active
\`\`\`

登入: http://<此機 IP>:5000
帳號: superadmin
密碼: changeme123 (首次會要求改)

### 9. 匯入真實主機
UI → 系統管理 → 主機管理 → 匯入 CSV (或 JSON)

### 10. SSH 部署到各受監控機
\`\`\`bash
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519
ssh-copy-id -i /root/.ssh/id_ed25519 root@<target-host>
# 目標機建 ansible_svc 帳號 + sudoers NOPASSWD
\`\`\`

### 常見問題
見 RUNBOOK.md

EOF

echo "[6/6] 打包 tar.gz"
cd "${TMPDIR}"
tar czf "${OUT_DIR}/inspection_source_v${VERSION}_${STAMP}.tar.gz" "inspection_source_v${VERSION}"
SIZE=$(du -h "${OUT_DIR}/inspection_source_v${VERSION}_${STAMP}.tar.gz" | cut -f1)
SHA256=$(sha256sum "${OUT_DIR}/inspection_source_v${VERSION}_${STAMP}.tar.gz" | cut -d' ' -f1)

# 清理暫存
rm -rf "${TMPDIR}"

chmod 644 "${OUT_DIR}/inspection_source_v${VERSION}_${STAMP}.tar.gz"

echo
echo "=== 完成 ==="
echo "檔案: ${OUT_DIR}/inspection_source_v${VERSION}_${STAMP}.tar.gz"
echo "大小: ${SIZE}"
echo "SHA256: ${SHA256}"
echo
echo "下載方式 A (從 UI):"
echo "  登入 https://it.94alien.com → 開發後台 → 檔案管理"
echo "下載方式 B (scp):"
echo "  scp ansible-host:${OUT_DIR}/inspection_source_v${VERSION}_${STAMP}.tar.gz ."
