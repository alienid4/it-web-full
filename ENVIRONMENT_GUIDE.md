# 環境準備指南 — 巡檢系統 Linux 部署前置作業

> 本文件說明在 Linux 主機上部署巡檢系統前，需要安裝哪些套件、建立哪些目錄、
> 開什麼帳號、設什麼權限。
>
> **⚠️ 最新做法（v3.11.2+）**：直接用 [`setup_testenv.sh`](./setup_testenv.sh)
> 一鍵完成所有步驟（含離線 RPM/pip 安裝 + 服務建立 + DB 初始化）。
>
> **最快部署方式**：讀 [`README.md`](./README.md)，3 行指令搞定。

---

## 推薦：setup_testenv.sh（11 步離線一鍵）

```bash
cd /AI                      # 或你解壓 repo 的目錄
sudo ./setup_testenv.sh
```

自動完成：環境檢查 → 引導設定 → 下載/解壓 deps → MongoDB RPM →
python3-ldap → 離線 pip → 部署程式碼 → 寫 config/env/vault → 產 SSH key →
MongoDB 初始化 → systemd → 防火牆 → HTTP 驗證。

詳見 [`README.md`](./README.md)、[`DEVELOPER.md`](./DEVELOPER.md)。

---

## 下方為手動步驟（`setup_environment.sh` 時代，保留作為除錯/參考）

```bash
# 上傳腳本到目標主機後
chmod +x setup_environment.sh
sudo ./setup_environment.sh
```

腳本會自動完成以下所有步驟。以下逐項說明每一步的內容與原因。

---

## 1. 作業系統要求

| 項目 | 需求 |
|------|------|
| **主要支援** | Rocky Linux 9.x（推薦 9.7）|
| **也支援** | RHEL 8-9 / AlmaLinux 8-9 / CentOS 8 / Debian 11-12 / Ubuntu 22.04-24.04 |
| **CPU** | 最少 2 核心 |
| **記憶體** | 最少 4 GB |
| **磁碟** | 最少 20 GB |
| **網路** | 需能 SSH 連線到受監控主機 |
| **權限** | 需要 root |

---

## 2. 需安裝的系統套件

### RHEL 系列（Rocky / RHEL / AlmaLinux / CentOS）

```bash
dnf install -y \
  podman           \  # 容器引擎（跑 MongoDB）
  python3          \  # Python 直譯器
  python3-pip      \  # Python 套件管理器
  python3-devel    \  # Python 開發標頭檔（編譯 python-ldap 需要）
  openldap-devel   \  # LDAP 函式庫（編譯 python-ldap 需要）
  gcc              \  # C 編譯器（編譯 python-ldap 需要）
  make             \  # 建置工具
  sysstat          \  # 系統效能工具（iostat, sar）
  net-snmp-utils   \  # SNMP 工具（snmpget, snmpwalk 監控網路設備）
  sshpass          \  # 非互動式 SSH 密碼登入（Ansible 需要）
  openssh-clients  \  # SSH 客戶端
  ansible-core     \  # Ansible 自動化引擎
  git              \  # 版本控制
  tar gzip         \  # 壓縮解壓
  cronie           \  # Cron 排程服務
  firewalld        \  # 防火牆
  jq               \  # JSON 處理工具
  curl wget        \  # HTTP 下載工具
  epel-release        # EPEL 套件庫（額外套件）
```

### Debian 系列（Debian / Ubuntu）

```bash
apt-get install -y \
  podman              \
  python3             \
  python3-pip         \
  python3-venv        \
  python3-dev         \
  libldap2-dev        \  # 對應 RHEL 的 openldap-devel
  libsasl2-dev        \  # SASL 認證函式庫
  gcc make            \
  sysstat             \
  snmp                \
  snmp-mibs-downloader\
  sshpass             \
  openssh-client      \
  ansible             \
  git tar gzip        \
  cron                \
  ufw                 \  # 對應 RHEL 的 firewalld
  jq curl wget
```

### 各套件用途說明

| 套件 | 用途 | 為什麼需要 |
|------|------|------------|
| **podman** | 容器引擎 | MongoDB 以容器方式運行，不需安裝 MongoDB RPM |
| **python3 + pip** | 程式語言 | Flask Web 應用的執行環境 |
| **python3-devel** | 開發標頭 | 編譯 `python-ldap` 套件時需要 Python.h |
| **openldap-devel** | LDAP 函式庫 | 編譯 `python-ldap` 需要 ldap.h |
| **gcc + make** | 編譯器 | 編譯 `python-ldap` 和 `bcrypt` 的 C 擴展 |
| **sysstat** | 系統監控 | 巡檢角色 `check_cpu` 使用 `iostat`/`sar` |
| **net-snmp-utils** | SNMP 工具 | 監控網路設備（交換器/路由器/防火牆）|
| **sshpass** | SSH 密碼工具 | Ansible 首次連線用密碼認證時需要 |
| **ansible-core** | 自動化引擎 | 執行巡檢 playbook 連線受監控主機 |
| **git** | 版本控制 | superadmin 的 Git 推送功能 |
| **cronie/cron** | 排程服務 | 每日自動巡檢排程 |
| **firewalld/ufw** | 防火牆 | 開放 Flask Web 埠 |
| **jq** | JSON 處理 | 腳本中解析 JSON 回應 |

---

## 3. 需安裝的 Python 套件

```bash
pip3 install flask==3.0.3 pymongo==4.7.3 python-ldap==3.4.4 gunicorn==22.0.0 bcrypt
```

| 套件 | 版本 | 用途 |
|------|------|------|
| **flask** | 3.0.3 | Web 框架（路由、模板、Session）|
| **pymongo** | 4.7.3 | MongoDB Python 驅動程式 |
| **python-ldap** | 3.4.4 | 連接 Active Directory / LDAP |
| **gunicorn** | 22.0.0 | 生產環境 WSGI 伺服器（多 Worker） |
| **bcrypt** | latest | 密碼雜湊加密 |

### 選裝套件

```bash
pip3 install pywinrm pysnmp
```

| 套件 | 用途 |
|------|------|
| **pywinrm** | Windows 遠端管理（WinRM 協定）|
| **pysnmp** | Python SNMP 函式庫（替代 net-snmp-utils 的 Python 版）|

---

## 4. 需建立的目錄

```
/var/log/inspection/                                    # 根目錄
├── AI/
│   └── inspection/                         # 主安裝目錄
│       ├── webapp/                         # Flask Web 應用程式
│       │   ├── routes/                     # API Blueprint 模組
│       │   ├── services/                   # 業務邏輯服務
│       │   ├── models/                     # 資料模型
│       │   ├── templates/                  # Jinja2 HTML 模板
│       │   └── static/                     # 靜態資源
│       │       ├── css/                    #   CSS 樣式
│       │       ├── js/                     #   JavaScript
│       │       └── img/                    #   圖片
│       │
│       ├── data/                           # 資料儲存
│       │   ├── reports/                    # 每日巡檢 JSON 報告
│       │   ├── snapshots/                  # 帳號變更快照（diff 用）
│       │   ├── security_audit_reports/     # 安全稽核報告
│       │   ├── linux_init_reports/         # Linux 初始化報告
│       │   └── audit_progress/            # 非同步任務進度檔
│       │
│       ├── ansible/                        # Ansible 自動化
│       │   ├── inventory/                  # 主機清單
│       │   │   ├── group_vars/            # 群組變數
│       │   │   └── host_vars/             # 主機變數
│       │   ├── playbooks/                  # Playbook
│       │   └── roles/                      # 檢查角色
│       │
│       ├── scripts/                        # Shell/Python 腳本
│       ├── logs/                           # 執行日誌
│       ├── container/
│       │   └── mongodb_data/               # MongoDB 資料卷掛載點
│       └── .ssh/                           # Ansible SSH 金鑰
│
├── backup/                                 # 備份目錄
│   ├── twgcb/                             # TWGCB 強化前備份
│   └── db_dumps/                          # MongoDB 備份
│
└── (root home)
    └── /root/AI/AI_worklog/               # 管理操作日誌
```

---

## 5. 需建立的帳號與權限

### 5.1 系統帳號

| 帳號 | 類型 | 用途 | 建立指令 |
|------|------|------|----------|
| `ansible_svc` | 系統服務帳號 | SSH 連線受監控主機執行巡檢 | `useradd -r -m -s /bin/bash ansible_svc` |

**ansible_svc 需要的設定**：
- 加入 `systemd-journal` 群組（可讀 journalctl 日誌）
- 產生 SSH 金鑰對（ed25519）
- 將公鑰部署到所有受監控主機

```bash
# 建立帳號
useradd -r -m -s /bin/bash -c "Ansible Service Account" ansible_svc

# 加入群組
usermod -aG systemd-journal ansible_svc

# 產生金鑰
ssh-keygen -t ed25519 -f /opt/inspection/.ssh/ansible_svc_key -N ""
```

### 5.2 Web 應用帳號（MongoDB 內）

| 帳號 | 角色 | 密碼 | 說明 |
|------|------|------|------|
| `admin` | admin | 安裝時設定 | 預設管理員，首次登入須改密碼 |

> 更多使用者由 superadmin 在 Web 介面建立。

### 5.3 角色權限矩陣

| 功能 | superadmin | admin | oper |
|------|:----------:|:-----:|:----:|
| 瀏覽 Dashboard | O | O | O |
| 瀏覽報告/歷史 | O | O | O |
| 管理主機 | O | O | X |
| 管理規則 | O | O | X |
| 備份/還原 | O | O | X |
| 管理排程 | O | O | X |
| 觸發巡檢 | O | O | X |
| Git 操作 | O | X | X |
| 管理使用者 | O | X | X |
| 重啟服務 | O | X | X |

---

## 6. 檔案權限設定

| 檔案/目錄 | 權限 | 說明 |
|-----------|------|------|
| `/opt/inspection/.vault_pass` | 600 | Ansible Vault 密碼，僅 root 可讀 |
| `/opt/inspection/.ssh/ansible_svc_key` | 600 | SSH 私鑰，僅 root 可讀 |
| `/opt/inspection/.ssh/` | 700 | SSH 目錄 |
| `/opt/inspection/webapp/config.py` | 600 | 含 SECRET_KEY，僅 root 可讀 |
| `/opt/inspection/webapp/.env` | 600 | 含 SMTP/LDAP 密碼 |
| `/opt/inspection/data/settings.json` | 600 | 系統設定（含 Email 憑證路徑）|
| `/opt/inspection/run_inspection.sh` | 755 | 執行腳本 |
| `/opt/inspection/scripts/*.sh` | 755 | 所有 Shell 腳本 |
| `/opt/inspection/container/mongodb_data/` | 777 | MongoDB 容器寫入用 |
| `/opt/inspection/logs/` | 755 | 日誌目錄 |

---

## 7. MongoDB 容器設定

```bash
# 拉取映像（有網路時）
podman pull docker.io/library/mongo:6

# 或載入離線映像
podman load -i mongodb6.tar

# 啟動容器
podman run -d \
  --name mongodb \
  -p 127.0.0.1:27017:27017 \               # 僅監聽本機，不對外
  -v /opt/inspection/container/mongodb_data:/data/db:Z \  # SELinux :Z
  --restart=always \
  docker.io/library/mongo:6
```

**重點**：
- 只綁定 `127.0.0.1`，不對外開放
- 使用 `:Z` SELinux 標籤
- `--restart=always` 確保重開機自動啟動

### 初始化的 Collections（11 個）

| Collection | 用途 | 索引 |
|-----------|------|------|
| `hosts` | 主機清單 | hostname (unique) |
| `inspections` | 巡檢結果 | (hostname, run_date, run_time) |
| `filter_rules` | 過濾規則 | rule_id |
| `settings` | 系統設定 | key |
| `users` | 使用者帳號 | username (unique) |
| `admin_worklog` | 操作日誌 | timestamp (desc) |
| `alert_acks` | 告警確認 | key |
| `twgcb_results` | 合規結果 | (hostname, scan_time) |
| `twgcb_backups` | 強化備份 | - |
| `hr_users` | HR 員工資料 | ad_account (unique) |
| `account_notes` | 帳號備註 | - |

---

## 8. Systemd 服務

### 8.1 MongoDB 服務 (`itagent-db.service`)

```ini
[Unit]
Description=ITAgent MongoDB (Podman Container)
After=network-online.target

[Service]
Type=forking
ExecStartPre=/usr/bin/podman start mongodb
ExecStart=/bin/bash -c 'until podman exec mongodb mongosh --eval "db.runCommand({ping:1})" --quiet; do sleep 1; done'
ExecStop=/usr/bin/podman stop -t 10 mongodb
RemainAfterExit=yes
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 8.2 Flask Web 服務 (`itagent-web.service`)

```ini
[Unit]
Description=ITAgent Flask Web Application
After=itagent-db.service
Requires=itagent-db.service

[Service]
Type=simple
WorkingDirectory=/opt/inspection/webapp
ExecStart=/usr/bin/gunicorn --workers=4 --bind=0.0.0.0:5000 --timeout=120 app:app
Restart=on-failure
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
```

### 服務管理指令

```bash
# 啟動
systemctl start itagent-db itagent-web

# 停止
systemctl stop itagent-web itagent-db

# 重啟 Web（不影響 DB）
systemctl restart itagent-web

# 查看狀態
systemctl status itagent-db itagent-web

# 查看日誌
journalctl -u itagent-web -f

# 開機自動啟動
systemctl enable itagent-db itagent-web
```

---

## 9. 防火牆設定

### RHEL 系列（firewalld）
```bash
firewall-cmd --add-port=5000/tcp --permanent
firewall-cmd --reload
```

### Debian 系列（ufw）
```bash
ufw allow 5000/tcp
```

### 不需要開放的埠
- MongoDB 27017：僅監聽 127.0.0.1，不需開放

---

## 10. Cron 排程

```bash
# 每日三次巡檢（預設時間）
30 06 * * * /opt/inspection/run_inspection.sh >> /opt/inspection/logs/cron.log 2>&1
30 13 * * * /opt/inspection/run_inspection.sh >> /opt/inspection/logs/cron.log 2>&1
30 17 * * * /opt/inspection/run_inspection.sh >> /opt/inspection/logs/cron.log 2>&1
```

可在管理後台的「排程」Tab 動態調整時間。

---

## 11. SELinux 注意事項

如果 SELinux 為 Enforcing 模式：

```bash
# 允許 Podman 容器管理 cgroup
setsebool -P container_manage_cgroup on

# MongoDB 資料卷使用 :Z 標籤自動 relabel
# （已在 podman run 指令中設定）
```

---

## 12. 部署後驗證清單

| # | 驗證項目 | 驗證指令 | 預期結果 |
|---|---------|---------|---------|
| 1 | Python 版本 | `python3 --version` | >= 3.9 |
| 2 | Flask 安裝 | `python3 -c "import flask; print(flask.__version__)"` | 3.0.3 |
| 3 | MongoDB 運行 | `podman exec mongodb mongosh --eval "db.runCommand({ping:1})" --quiet` | { ok: 1 } |
| 4 | MongoDB 資料庫 | `podman exec mongodb mongosh inspection --eval "db.getCollectionNames()"` | 11 個 Collection |
| 5 | Systemd 服務 | `systemctl is-enabled itagent-db itagent-web` | enabled |
| 6 | 防火牆 | `firewall-cmd --list-ports` | 5000/tcp |
| 7 | Cron 排程 | `crontab -l \| grep inspection` | 3 筆排程 |
| 8 | SSH 金鑰 | `ls -la /opt/inspection/.ssh/` | ansible_svc_key (600) |
| 9 | config.py | `ls -la /opt/inspection/webapp/config.py` | 600 權限 |
| 10 | 目錄結構 | `ls /opt/inspection/` | webapp/ ansible/ data/ logs/ scripts/ |

---

## 13. 常見問題

### Q: python-ldap 安裝失敗
```
error: command 'gcc' failed
```
**原因**：缺少開發標頭檔
**解法**：
```bash
# RHEL
dnf install -y python3-devel openldap-devel gcc

# Debian
apt-get install -y python3-dev libldap2-dev libsasl2-dev gcc
```

### Q: Podman 啟動 MongoDB 失敗
```
Error: error creating container storage
```
**原因**：SELinux 阻擋或磁碟空間不足
**解法**：
```bash
# 檢查磁碟空間
df -h /var/log/inspection

# SELinux 暫時設為 Permissive 測試
setenforce 0
podman run ...
setenforce 1
```

### Q: Flask 啟動後無法連線
**解法**：
```bash
# 檢查防火牆
firewall-cmd --list-ports

# 檢查服務狀態
systemctl status itagent-web
journalctl -u itagent-web --no-pager -n 50
```

### Q: Ansible 連線受監控主機失敗
**解法**：
```bash
# 測試 SSH 連線
ssh -i /opt/inspection/.ssh/ansible_svc_key ansible_svc@<target_ip>

# 測試 Ansible ping
ansible -i inventory/hosts.yml all -m ping
```

---

## 14. 腳本參數調整

`setup_environment.sh` 頂部的可調參數：

```bash
INSTALL_DIR="/opt/inspection"        # 修改安裝路徑
BACKUP_DIR="/var/backups/inspection"                # 修改備份路徑
FLASK_PORT=5000                            # 修改 Web 埠
MONGO_PORT=27017                           # 修改 MongoDB 埠
ADMIN_USER="admin"                         # 修改預設管理員帳號
ADMIN_PASS="ChangeMe@2026"                # 修改預設密碼
CRON_TIMES=("06 30" "13 30" "17 30")       # 修改巡檢時間
```

修改後重新執行腳本即可套用。
