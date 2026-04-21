# 金融業 IT 每日自動巡檢系統
# 安裝與操作教學手冊 v2.0.0.0

---

## 目錄

1. [系統需求](#1-系統需求)
2. [安裝步驟](#2-安裝步驟)
3. [首次設定](#3-首次設定)
4. [日常操作](#4-日常操作)
5. [系統管理](#5-系統管理)
6. [帳號盤點](#6-帳號盤點)
7. [新增主機](#7-新增主機)
8. [備份與還原](#8-備份與還原)
9. [故障排除](#9-故障排除)
10. [附錄](#10-附錄)

---

## 1. 系統需求

| 項目 | 需求 |
|------|------|
| 作業系統 | Rocky Linux 9.x |
| CPU | 2 核以上 |
| 記憶體 | 4GB 以上 |
| 磁碟 | 20GB 以上 |
| 網路 | 可連到受管主機 |
| 帳號 | root |

### 監控支援的設備類型
| 設備 | 連線方式 |
|------|---------|
| Linux (Rocky/RHEL/Debian) | SSH |
| AIX | SSH (raw module) |
| Windows Server 2019+ | SSH (OpenSSH) |
| Windows Server 2016 | WinRM |
| 網路設備 (Cisco/Juniper等) | SNMP |
| IBM AS/400 | SNMP |

---

## 2. 安裝步驟

### 2.1 準備部署包

將 `inspection_deploy_v2.0.0.0.tar.gz` 複製到新主機：
```bash
# 從 USB
cp /mnt/usb/inspection_deploy_v2.0.0.0.tar.gz /tmp/

# 或從另一台主機
scp inspection_deploy_v2.0.0.0.tar.gz root@<新主機IP>:/tmp/
```

### 2.2 解壓

```bash
cd /tmp
tar xzf inspection_deploy_v2.0.0.0.tar.gz
cd deploy_v2
```

### 2.3 執行安裝

```bash
bash install.sh
```

### 2.4 安裝引導畫面

安裝腳本會依序詢問以下設定：

```
安裝目錄 [/opt/inspection]:      ← 直接 Enter 用預設值
備份目錄 [/var/backups/inspection]:              ← 直接 Enter 用預設值
工作日誌目錄 [/root/AI/AI_worklog]:     ← 直接 Enter 用預設值
Flask Port [5000]:                      ← 直接 Enter 用預設值
MongoDB Port [27017]:                   ← 直接 Enter 用預設值
Admin 預設密碼 [admin]:                 ← 建議改成強密碼
巡檢排程 [06:30,13:30,17:30]:          ← 每天三次巡檢
```

確認設定後輸入 `y` 開始安裝。

### 2.5 安裝完成

安裝成功後會顯示：
```
============================================
  安裝完成！ v2.0.0.0
============================================
  Web:        http://10.x.x.x:5000
  Admin:      http://10.x.x.x:5000/admin
  帳號:       admin / <你設的密碼>
============================================
```

---

## 3. 首次設定

### 3.1 登入系統管理

1. 開啟瀏覽器，輸入 `http://<主機IP>:5000/admin`
2. 帳號密碼：admin / admin（或你安裝時設的密碼）
3. 首次登入會要求修改密碼

### 3.2 新增受管主機

1. 進入 Admin → **主機管理** tab
2. 點擊 **新增主機** 按鈕
3. 填寫：
   - 主機名稱（例：`PROD-SVR01`）
   - IP 位址
   - OS 類型
   - OS Group（rocky/rhel/debian/windows/snmp/as400）
   - 環境（正式/測試）
   - 保管者
4. 點擊**儲存**

### 3.3 設定 SSH 連線

在巡檢主機（安裝本系統的主機）上：

```bash
# 建立巡檢用帳號的 SSH Key
ssh-keygen -t ed25519 -C "ansible_svc" -f /opt/inspection/.ssh/ansible_svc_key -N ""

# 將公鑰複製到受管主機
ssh-copy-id -i /opt/inspection/.ssh/ansible_svc_key.pub ansible_svc@<受管主機IP>
```

在受管主機上建立 ansible_svc 帳號：
```bash
# Linux
useradd ansible_svc
mkdir -p /home/ansible_svc/.ssh
# 貼入公鑰到 /home/ansible_svc/.ssh/authorized_keys

# Windows（PowerShell 管理員）
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
net user ansible_svc P@ssw0rd123! /add
net localgroup Administrators ansible_svc /add
```

### 3.4 更新 Ansible Inventory

```bash
# 編輯主機清單
vi /opt/inspection/ansible/inventory/hosts.yml
```

範例：
```yaml
all:
  children:
    linux:
      children:
        rocky:
          hosts:
            PROD-SVR01:
              ansible_host: 10.0.0.1
        rhel:
          hosts:
            PROD-SVR02:
              ansible_host: 10.0.0.2
    windows:
      hosts:
        WIN-SVR01:
          ansible_host: 10.0.0.50
          ansible_connection: ssh
          ansible_shell_type: cmd
          ansible_user: ansible_svc
          ansible_password: "P@ssw0rd123!"
```

### 3.5 執行第一次巡檢

```bash
/opt/inspection/run_inspection.sh
```

執行完畢後重新整理網頁，即可看到巡檢結果。

---

## 4. 日常操作

### 4.1 查看 Dashboard

網址：`http://<IP>:5000`

- **KPI 卡片**：點擊正常/警告/異常可篩選主機
- **全部主機狀態**：預設只顯示異常（右上角開關可切換）
- **OS 數量統計**：各 OS 類型的主機數量

### 4.2 查看今日報告

網址：`http://<IP>:5000/report`

每台主機的卡片顯示：
- CPU / MEM / Swap / IO / Load / Users
- Disk 使用率（正常顯示 OK，異常才展開）
- 服務 / 帳號 / 錯誤日誌 / FailLogin
- Uptime

**點擊任意卡片** → 進入該主機的詳細報告

### 4.3 查看異常總結

網址：`http://<IP>:5000/summary`

- 依嚴重度排序
- 每台異常主機顯示：原因分析 + 建議處理動作 + 負責人
- 可匯出文字報告

### 4.4 查看歷史趨勢

網址：`http://<IP>:5000/history`

選擇主機和天數 → 顯示 CPU/磁碟歷史折線圖 + 表格

---

## 5. 系統管理

網址：`http://<IP>:5000/admin`（需登入）

### 5.1 系統狀態 tab
- 查看 Flask / MongoDB / 磁碟 / 容器狀態
- 快速操作：立即巡檢、匯入 MongoDB

### 5.2 設定管理 tab
- 修改閾值（Disk 85%/95%、CPU 80%/95%、MEM 80%/95%）
- 管理服務檢查清單（新增/移除）
- 修改 Email 通知收件人

### 5.3 備份管理 tab
- 查看所有備份
- 一鍵建立備份
- 一鍵還原
- 刪除舊備份

### 5.4 工作排程 tab
- 查看最近執行狀態
- 查看執行日誌（最後 30 行）

### 5.5 日誌檢視 tab
- 搜尋巡檢日誌（依日期/關鍵字）
- 查看 Flask 日誌

### 5.6 主機管理 tab
- 新增/編輯/刪除主機
- Ping 測試連線
- CSV 匯入/匯出
- 重建 Ansible Inventory

### 5.7 告警管理 tab
- 查看所有 warn/error 告警紀錄
- 確認（acknowledge）告警

### 5.8 排程設定 tab
- 查看/新增/停用/刪除巡檢排程
- 每個排程可單獨啟用或停用

### 5.9 合規報告 tab
- 選擇月份產生月報
- 每台主機的正常/警告/異常次數 + SLA%
- 匯出 CSV

### 5.10 帳號盤點 tab
- 所有主機帳號清單（排除內建帳號）
- 風險標示：密碼過老 / 密碼到期 / 未登入
- 篩選：依主機 / 依部門 / 依風險
- 點擊**編輯**修改帳號備註和部門

### 5.11 帳號管理 tab
- 盤點閾值設定（預設 180 天）
- HR 人員 CSV 匯入/下載範本

### 5.12 操作紀錄 tab
- 所有管理操作的審計紀錄（誰/什麼時候/做了什麼）

---

## 6. 帳號盤點

### 6.1 流程
1. 巡檢自動採集所有主機帳號資訊
2. 進入 Admin → 帳號盤點 tab
3. 篩選有風險的帳號
4. 點擊**編輯**為帳號加備註（例：`004808_ALIEN_測試專用`）
5. 匯出 CSV 給主管審核

### 6.2 風險判定
| 風險 | 條件 | 等級 |
|------|------|------|
| 密碼過老 | 超過 180 天未變更密碼 | 警告 |
| 密碼到期 | 密碼已過期 | 嚴重 |
| 未登入 | 超過 180 天未登入 | 警告 |

### 6.3 匯入 HR 人員
1. 進入 Admin → 帳號管理 tab
2. 下載 CSV 範本
3. 填入人員資料（工號/姓名/AD帳號/部門）
4. 上傳 CSV
5. 帳號盤點會自動比對 AD 帳號帶出部門

---

## 7. 新增主機

### 7.1 Linux 主機
```bash
# 在受管主機上
useradd ansible_svc
mkdir -p /home/ansible_svc/.ssh
# 貼入巡檢主機的公鑰

# 在巡檢主機上
ssh-copy-id -i /opt/inspection/.ssh/ansible_svc_key.pub ansible_svc@<IP>
```

### 7.2 Windows 主機
```powershell
# 安裝 OpenSSH（Windows 2019+）
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force

# 建立帳號
net user ansible_svc P@ssw0rd123! /add
net localgroup Administrators ansible_svc /add

# 開防火牆
New-NetFirewallRule -DisplayName "SSH" -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow
```

### 7.3 SNMP 設備
在 inventory 中設定：
```yaml
network_devices:
  hosts:
    SWITCH-01:
      ansible_host: 10.0.0.1
      ansible_connection: local
      snmp_device: true
      snmp_community: "your_community"
```

---

## 8. 備份與還原

### 8.1 自動備份
- 每次程式碼更新前會自動備份
- 備份保留最近 3 份

### 8.2 手動備份
```bash
tar czf /var/backups/inspection/INSPECTION_HOME_$(date +%Y%m%d_%H%M%S).tar.gz -C /opt inspection/
```

或在 Admin → 備份管理 tab → 點擊**立即備份**

### 8.3 還原
```bash
cd /opt && tar xzf /var/backups/inspection/INSPECTION_HOME_XXXXXXXX_XXXXXX.tar.gz
```

或在 Admin → 備份管理 tab → 點擊**還原**

### 8.4 MongoDB 備份
```bash
podman exec mongodb mongodump --out /tmp/mongodump
```

---

## 9. 故障排除

### 9.1 Flask 沒有啟動
```bash
# 查看日誌
cat /tmp/flask.log

# 手動啟動
cd /opt/inspection/webapp
python3 app.py
```

### 9.2 MongoDB 沒有啟動
```bash
# 檢查容器
podman ps -a

# 啟動
podman start mongodb

# 查看日誌
podman logs mongodb
```

### 9.3 巡檢失敗
```bash
# 手動跑巡檢看錯誤
cd /opt/inspection/ansible
ansible-playbook playbooks/site.yml -i inventory/hosts.yml -v

# 測試單台
ansible -i inventory/hosts.yml <hostname> -m ping -u ansible_svc
```

### 9.4 SSH 連不上受管主機
```bash
# 測試
ssh -i /opt/inspection/.ssh/ansible_svc_key ansible_svc@<IP>

# 常見原因
# 1. SSH key 沒複製到受管主機
# 2. ansible_svc 帳號沒建
# 3. 防火牆擋 port 22
```

### 9.5 網頁打不開
```bash
# 檢查 Flask
ss -tlnp | grep 5000

# 檢查防火牆
firewall-cmd --list-all | grep 5000
```

---

## 10. 附錄

### 10.1 目錄結構
```
/opt/inspection/
├── ansible/          # Ansible 巡檢引擎
├── webapp/           # Flask Web 應用
├── data/             # 設定檔與報告
├── container/        # MongoDB 資料
├── scripts/          # 工具腳本
├── logs/             # 執行日誌
└── run_inspection.sh # 巡檢執行腳本
```

### 10.2 預設閾值
| 項目 | 警告 | 嚴重 |
|------|------|------|
| 磁碟 | 85% | 95% |
| CPU | 80% | 95% |
| 記憶體 | 80% | 95% |
| Swap | 50% | 80% |
| IO Busy | 70% | 90% |
| Load（倍數）| 2x | 4x |
| 帳號密碼 | 180 天 | 到期 |
| 帳號登入 | 180 天 | - |
| FailLogin | 5 次 | - |

### 10.3 API 端點清單
| 端點 | 說明 |
|------|------|
| GET /api/hosts/summary | 主機狀態摘要 |
| GET /api/inspections/latest | 最新巡檢結果 |
| GET /api/inspections/abnormal | 異常主機 |
| GET /api/inspections/trend | 7 日趨勢 |
| GET /api/inspections/summary | 異常總結報告 |
| POST /api/admin/login | 登入 |
| GET /api/admin/system/status | 系統狀態 |
| GET /api/admin/audit/accounts | 帳號盤點 |

完整 API 請參考 PROJECT_HANDOFF.md

### 10.4 版本紀錄
- v2.0.0.0 — 正式版初始安裝
- 詳細版本紀錄請查看 `/data/version.json`
