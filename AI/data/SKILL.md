---
name: inspection
description: |
  金融業 IT 每日自動巡檢系統的開發接手技能。當使用者說「接手巡檢系統」、「繼續巡檢開發」、
  「inspection」、「巡檢」、「開門檢查」、或任何提到巡檢系統維護、修改、新增功能的請求時觸發。
  也包括使用者提到 ansible-host、Flask 巡檢網站、MongoDB 巡檢資料、Ansible 巡檢 playbook 等相關關鍵字時觸發。
  此 skill 確保 AI 能快速了解專案全貌、目前進度、並遵守備份與日誌規範。
---

# 金融業 IT 每日自動巡檢系統 - 開發接手流程

你正在接手一個金融業 IT 每日自動巡檢系統的開發工作。這個系統部署在遠端伺服器 ansible-host (<ANSIBLE_HOST>)，
透過 Ansible 自動採集主機健康狀態，用 Flask + MongoDB 提供 Web Dashboard。

## 溝通語言

全程使用**繁體中文**與使用者溝通。

## 第一步：建立 SSH 連線

確認本地 SSH config 中有 ansible-host 的設定：
```bash
cat ~/.ssh/config | grep -A4 ansible-host
```

如果沒有，請使用者設定：
```
Host ansible-host
    HostName <ANSIBLE_HOST>
    User root
    Port 22
    IdentityFile ~/.ssh/id_ed25519
```

測試連線：
```bash
ssh ansible-host "hostname && echo SSH_OK"
```

## 第二步：讀取專案文件，了解全貌

依序讀取以下三份文件：

```bash
# 1. 專案接手文件（目錄結構、技術棧、啟動方式、已知待辦）
ssh ansible-host 'cat /opt/inspection/data/PROJECT_HANDOFF.md'

# 2. 規格變更紀錄（使用者追加的需求，開發時必須遵守）
ssh ansible-host 'cat /opt/inspection/data/SPEC_CHANGELOG_20260410.md'

# 3. 工作日誌（了解目前做到哪裡、什麼已完成、什麼待辦）
ssh ansible-host 'cat /opt/inspection/data/worklog.log'
```

讀完後向使用者簡要報告：目前完成了什麼、有哪些待辦、系統狀態如何。

## 第三步：檢查系統狀態

```bash
# 檢查 MongoDB 容器是否運行
ssh ansible-host 'podman ps | grep mongodb'

# 檢查 Flask 是否運行
ssh ansible-host 'ss -tlnp | grep 5000'

# 如果 MongoDB 沒跑
ssh ansible-host 'podman start mongodb'

# 如果 Flask 沒跑
ssh ansible-host 'cd /opt/inspection/webapp && nohup python3 app.py > /tmp/flask.log 2>&1 &'
```

向使用者報告系統狀態（MongoDB 和 Flask 是否正常運行）。

## 開發規範（必須嚴格遵守）

### 規範 0：任務四步驟（討論→執行→驗證→回報）

每個任務必須依序完成以下四步，不能跳步：

1. **討論** — 收到需求後，用自己的話重述使用者要什麼、列出要做哪些事和影響哪些檔案，等使用者確認後才動手。絕對不能收到需求就直接開始寫程式。
2. **執行** — 確認後開始寫程式、部署到伺服器。
3. **驗證** — 自己用瀏覽器或 API 實際確認功能正常（不是叫使用者自己看）。如果有 UI 變更，截圖確認。
4. **回報** — 明確跟使用者說「完成了」，附上驗證結果。

### 規範 1：變更前必須備份

在修改 ansible-host 上的任何檔案之前，先執行備份：

```bash
ssh ansible-host 'tar czf /var/backups/inspection/INSPECTION_HOME_$(date +%Y%m%d_%H%M%S).tar.gz -C /opt inspection/ && echo "BACKUP OK"'
```

備份保留最近 3 份，清理舊的：
```bash
ssh ansible-host 'ls -t /var/backups/inspection/INSPECTION_HOME_*.tar.gz | tail -n +4 | xargs rm -f 2>/dev/null'
```

還原方式（如果改壞了）：
```bash
ssh ansible-host 'cd /opt && tar xzf /var/backups/inspection/INSPECTION_HOME_XXXXXXXX_XXXXXX.tar.gz'
```

### 規範 2：變更後寫工作日誌

每完成一個任務，寫入 worklog：
```bash
ssh ansible-host 'echo "[$(date +%Y-%m-%d\ %H:%M:%S)] DONE: <任務描述>" >> /opt/inspection/data/worklog.log'
```

日誌格式：
- `DONE: <描述>` — 已完成的任務
- `IN_PROGRESS: <描述>` — 進行中的任務
- `PENDING: <描述>` — 待辦任務

### 規範 3：Python 檔案寫完立即語法檢查

```bash
ssh ansible-host 'python3 -m py_compile <file>.py && echo "OK" || echo "SYNTAX ERROR"'
```

### 規範 4：API 寫完立即測試

```bash
ssh ansible-host 'curl -s http://localhost:5000/api/<endpoint> | python3 -m json.tool'
```

### 規範 5：每次變更必須更新版號

每次功能修改完成後，必須更新 version.json 的版號和時間：
```bash
ssh ansible-host "python3 -c \"
import json
from datetime import datetime
with open('/opt/inspection/data/version.json') as f:
    d = json.load(f)
d['version'] = 'X.X.X.X'  # 遞增版號
d['updated_at'] = datetime.now().strftime('%Y-%m-%d %H:%M')
d['changelog'].append('X.X.X.X - YYYY-MM-DD: 變更描述')
with open('/opt/inspection/data/version.json', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
\""
```

版號規則：主版本.功能版本.修正版本.建置版本
- 忘記更新版號 = 使用者無法確認是否有變更，絕對不能漏

### 規範 6：規格變更要記錄

如果使用者提出新需求，追加到 SPEC_CHANGELOG：
```bash
ssh ansible-host 'cat >> /opt/inspection/data/SPEC_CHANGELOG_20260410.md << "EOF"

## 變更 #N：<標題>
**需求描述：** <描述>
**影響範圍：** <檔案清單>
**驗收條件：** <如何驗證>
EOF'
```

## 關鍵路徑速查

| 項目 | 路徑 |
|------|------|
| 專案根目錄 | `/opt/inspection/` |
| Flask webapp | `/opt/inspection/webapp/` |
| Ansible playbooks | `/opt/inspection/ansible/` |
| 系統設定 | `/opt/inspection/data/settings.json` |
| 主機配置 | `/opt/inspection/data/hosts_config.json` |
| 規格變更 | `/opt/inspection/data/SPEC_CHANGELOG_20260410.md` |
| 接手文件 | `/opt/inspection/data/PROJECT_HANDOFF.md` |
| 工作日誌 | `/opt/inspection/data/worklog.log` |
| 備份目錄 | `/var/backups/inspection/` |
| Flask 日誌 | `/tmp/flask.log` |
| MongoDB 資料 | `/opt/inspection/container/mongodb_data/` |

## 技術棧

- **資料採集**：Ansible Core 2.14.18（Linux/Windows/AIX/SNMP/AS400）
- **後端**：Python 3.9 + Flask 3.0.3
- **資料庫**：MongoDB 6（Podman 容器，僅本地 127.0.0.1:27017）
- **前端**：HTML5 + 原生 JS + SVG 圖示庫 + Example Corp CI CSS
- **人員查詢**：LDAP（目前 Mock 模式）
- **Excel**：openpyxl（TWGCB 匯出/匯入）
- **安全**：Ansible Vault + @login_required + 登入鎖定 + 安全 Headers
- **部署**：Podman 離線部署（引導式安裝腳本）

## 目前版本：v3.4.6.0（2026-04-18）

## 系統功能清單

### 前台（不需登入）
| 頁面 | 路由 | 功能 |
|------|------|------|
| Dashboard | / | KPI 卡片（可點擊篩選）+ OS 統計 + 全部主機表格（異常開關）|
| 今日報告 | /report | 每台主機巡檢卡片（12 項檢查）|
| 主機詳細 | /report/<hostname> | 單台完整報告（Disk/CPU/Service/Account/ErrorLog/System）|
| 異常總結 | /summary | 嚴重度排序 + 建議處理 + 負責人 + 趨勢比較 + 匯出 |
| 歷史查詢 | /history | 歷史趨勢 |
| 帳號盤點 | /audit | 密碼/登入稽核 + HR 對應 + CSV 匯出 |
| TWGCB 合規 | /twgcb | 矩陣式表格（OS Tab + 分類摺疊 + 例外管理 + Excel 匯出匯入）|
| TWGCB 強化 | /twgcb/harden/<hostname> | 備份 → 逐項修復 → 驗證（三步驟）|
| TWGCB 報表 | /twgcb-report | Example Corp抬頭 + 燈號矩陣 + 簽核欄 + 列印 |
| TWGCB 設定 | /twgcb-settings | 檢查項啟停 / 閾值 / 例外主機 / 報表簽核人 |

### 後台（/admin — 四大分類）

#### 🏢 監控平台管理
| Tab | 功能 |
|-----|------|
| 📊 系統狀態 | Flask/MongoDB/itagent-db/itagent-web 狀態 + Cloudflare Tunnel 管理（網址/複製/重啟/關閉）|
| ⚙️ 設定管理 | 閾值(Disk/CPU/MEM warn/crit) + 磁碟排除 |
| 💾 備份管理 | 程式備份 + MongoDB Dump/Restore/Import/Download |
| 👤 使用者管理 | CRUD 使用者 + 角色切換(oper/admin/superadmin) |
| 📋 日誌檢視 | 系統日誌 |
| 📝 操作紀錄 | 操作 audit log |

#### 🖥️ 受監控主機
| Tab | 功能 |
|-----|------|
| 🖥️ 伺服器清單 | CRUD + CSV/JSON匯入匯出 + 系統別/級別/AP負責人 + 各主機服務控制（啟動/重啟/停止+存活時間）|
| ▶️ 巡檢排程 | 執行巡檢 + 匯入 MongoDB |
| 🕐 排程設定 | cron 排程管理 |
| 🔔 告警管理 | 告警紀錄 |

#### 🔐 合規安全
| Tab | 功能 |
|-----|------|
| 🛡️ TWGCB設定 | 檢查項啟停/閾值/例外 |
| 📄 合規報告 | 報表簽核設定 |

#### 🔑 帳號安全
| Tab | 功能 |
|-----|------|
| 📋 帳號盤點 | HR對應/密碼天數閾值 |
| 👥 帳號管理 | 帳號盤點設定 + HR CSV 匯入 |

### 三級權限系統
| 角色 | 權限 |
|------|------|
| oper（未登入）| 所有頁面唯讀瀏覽，變更按鈕彈「權限不足」Toast |
| admin | 全部操作 + 可建立 oper/admin 帳號 |
| superadmin | admin 全部 + 開發後台 + 可建立 superadmin 帳號 |

### 服務管理 (itagent)
| 服務 | 說明 |
|------|------|
| itagent-db | MongoDB (Podman) |
| itagent-web | Flask Web |
| itagent-tunnel | Cloudflare Quick Tunnel |
| 管理指令 | `itagent {start\|stop\|restart\|status\|log\|tunnel}` |
| 環境變數 | `/etc/default/itagent` → `ITAGENT_HOME` |

### Cloudflare Tunnel
- Quick Tunnel（臨時網址，重啟會變）
- Web 管理：系統管理 → 系統狀態 → Tunnel 卡片
- CLI：`itagent tunnel`

### Ansible Roles（14 個）
check_disk / check_cpu / check_service / check_account / check_account_audit /
check_error_log / check_db_connection / check_system / check_windows /
check_snmp / check_as400 / check_twgcb / check_twgcb_win

### API 端點（約 50+ 個）
api_hosts / api_inspections / api_rules / api_settings / api_ldap /
api_admin（含使用者CRUD/服務控制/Tunnel管理/備份） / api_audit / api_harden / api_twgcb / api_superadmin

### MongoDB Collections（13 個）
hosts / inspections / filter_rules / settings / users /
twgcb_results / twgcb_config / twgcb_exceptions / twgcb_report_config /
account_audit / account_notes / hr_users / admin_logs
