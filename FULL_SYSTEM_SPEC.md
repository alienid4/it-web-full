# 金融業 IT 每日自動巡檢系統 — 完整開發規格手冊

> **目的**：本文件是「一模一樣重建」整套巡檢系統的**唯一參考**。
> AI 開發者請逐章閱讀，每一項功能均須實作，不可遺漏。
> 新系統可直接匯入現有 MongoDB 資料庫（database: `inspection`）。

---

## 目錄

1. [系統總覽](#1-系統總覽)
2. [技術架構與依賴](#2-技術架構與依賴)
3. [資料庫結構 (MongoDB)](#3-資料庫結構-mongodb)
4. [認證與授權系統](#4-認證與授權系統)
5. [前端頁面清單與功能](#5-前端頁面清單與功能)
6. [API 端點完整清單](#6-api-端點完整清單)
7. [Ansible 自動化與角色](#7-ansible-自動化與角色)
8. [Shell 腳本與自動化工具](#8-shell-腳本與自動化工具)
9. [設計系統 (CSS/UI)](#9-設計系統-cssui)
10. [部署與運維](#10-部署與運維)
11. [安全機制](#11-安全機制)
12. [版本管理機制](#12-版本管理機制)
13. [各頁面功能詳細說明（使用者手冊級）](#13-各頁面功能詳細說明使用者手冊級)

---

## 1. 系統總覽

### 1.1 系統名稱
**金融業 IT 每日自動巡檢系統**（Financial IT Daily Automated Inspection System）

### 1.2 目的
為金融機構（Example Corp）提供每日自動化伺服器健康檢查、合規掃描、安全稽核、與異常通報。
支援 Linux / Windows / AIX / AS/400 / 網路設備（SNMP），透過 Web 介面集中管理。

### 1.3 目前版本
`v3.4.2.0`（2026-04-16）

### 1.4 部署伺服器
- **主機名稱**：ansible-host
- **IP**：<ANSIBLE_HOST>
- **OS**：Rocky Linux 9.7
- **用途**：Ansible 控制節點 + Flask Web 應用 + MongoDB

### 1.5 系統架構圖（文字版）

```
┌─────────────┐     SSH/WinRM/SNMP      ┌──────────────────┐
│  Cron Job   │ ──→ Ansible Playbooks ──→│  受監控主機群     │
│ (3次/日)    │                          │  Linux/Win/AIX   │
└──────┬──────┘                          │  AS400/SNMP      │
       │                                 └──────────────────┘
       ▼
┌──────────────┐    JSON Reports
│ run_inspection│ ──→ /data/reports/
│     .sh      │
└──────┬───────┘
       │  seed_data.py
       ▼
┌──────────────┐     API Queries     ┌──────────────────┐
│   MongoDB    │ ◄─────────────────→ │  Flask Web App   │
│ (Podman)     │                     │  Port 5000       │
│ DB:inspection│                     │  12 Blueprints   │
└──────────────┘                     └───────┬──────────┘
                                             │
                                     ┌───────▼──────────┐
                                     │  Browser (使用者) │
                                     │  Dashboard/Admin │
                                     └──────────────────┘
```

### 1.6 資料流程
1. **排程觸發**：Cron 每日 06:30 / 13:30 / 17:30 執行 `run_inspection.sh`
2. **Ansible 執行**：`ansible-playbook site.yml` 對所有主機執行 12 個檢查角色
3. **產出報告**：每台主機產出 JSON 檔案至 `/data/reports/`
4. **匯入資料庫**：`seed_data.py` 將 JSON 匯入 MongoDB
5. **Web 呈現**：Flask API 查詢 MongoDB，前端渲染 Dashboard
6. **異常通報**：若有異常，透過 Email (SMTP) 發送告警

---

## 2. 技術架構與依賴

### 2.1 後端
| 元件 | 版本 | 用途 |
|------|------|------|
| Python | 3.9.25 | 主要程式語言 |
| Flask | 3.0.3 | Web 框架 |
| PyMongo | 4.7.3 | MongoDB 驅動 |
| python-ldap | 3.4.4 | AD/LDAP 整合（目前 Mock 模式）|
| Gunicorn | 22.0.0 | 生產 WSGI 伺服器 |

### 2.2 資料庫
| 元件 | 版本 | 備註 |
|------|------|------|
| MongoDB | 6.0.27 | 透過 Podman 容器運行，僅監聽 127.0.0.1:27017 |

### 2.3 自動化
| 元件 | 版本 | 用途 |
|------|------|------|
| Ansible | core 2.14.18 | 遠端主機巡檢/強化/合規掃描 |
| Ansible Vault | - | 加密敏感憑證（密碼） |

### 2.4 前端
| 元件 | 備註 |
|------|------|
| Jinja2 Templates | Flask 內建模板引擎 |
| Vanilla JavaScript | 無框架，原生 JS + Fetch API |
| Chart.js v4 | 圖表（折線圖、甜甜圈圖）|
| Noto Sans TC | Google Fonts 繁體中文字型 |
| JetBrains Mono | 等寬字型（數據顯示）|
| example.css | 自訂設計系統（Example CI）|

### 2.5 容器化
| 元件 | 用途 |
|------|------|
| Podman | 容器運行時（取代 Docker）|
| MongoDB 容器 | `podman run -d --name mongodb -p 127.0.0.1:27017:27017` |

---

## 3. 資料庫結構 (MongoDB)

**Database 名稱**：`inspection`

### 3.1 `hosts` Collection — 主機清單

儲存所有受監控主機的基本資訊與資產資料。

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `hostname` | string | Y | 主機名稱（唯一鍵），例如 SECSVR019 |
| `ip` | string | Y | IP 位址 |
| `os` | string | Y | 完整 OS 名稱，如 "Rocky Linux 9.7" |
| `os_group` | string | Y | 分類：rhel / debian / rocky / aix / windows / snmp / as400 |
| `status` | string | Y | "使用中" 或 "停用" |
| `environment` | string | N | "正式" 或 "測試" |
| `group` | string | N | 自訂群組名稱 |
| `has_python` | bool | N | 是否安裝 Python |
| `asset_seq` | string | N | 資產編號 |
| `asset_name` | string | N | 資產名稱 |
| `division` | string | N | 處級單位 |
| `department` | string | N | 部級單位 |
| `owner` | string | N | 負責單位 |
| `custodian` | string | N | 保管人姓名 |
| `custodian_ad` | string | N | 保管人 AD 帳號 |
| `system_type` | string | N | 系統別（gold/silver/bronze）|
| `ap_owner` | string | N | 應用程式負責人 |
| `imported_at` | string | N | 匯入時間 (ISO 8601) |
| `updated_at` | string | N | 更新時間 (ISO 8601) |

**開發指引**：
- `hostname` 為唯一鍵，建立 unique index
- 支援 CSV 批次匯入/匯出
- `os_group` 用於前端 OS 分類篩選

---

### 3.2 `inspections` Collection — 巡檢結果

每次巡檢執行的完整結果，每台主機一筆。

| 欄位 | 型別 | 說明 |
|------|------|------|
| `hostname` | string | 對應 hosts.hostname |
| `run_id` | string | 執行 ID，格式 YYYYMMDD_HHMMSS |
| `run_date` | string | 日期 YYYY-MM-DD |
| `run_time` | string | 時間 HH:MM:SS |
| `overall_status` | string | 綜合狀態：ok / warn / error |
| `ip` | string | 主機 IP |
| `os` | string | 作業系統 |

**巢狀欄位 `disk`**：
```json
{
  "status": "ok|warn|error",
  "warn_threshold": 85,
  "crit_threshold": 95,
  "partitions": [
    {
      "mount": "/",
      "size": "50G",
      "used": "30G",
      "free": "20G",
      "percent": 60,
      "status": "ok"
    }
  ]
}
```

**巢狀欄位 `cpu`**：
```json
{
  "status": "ok|warn|error",
  "cpu_percent": 25.3,
  "mem_percent": 45.2,
  "warn_threshold": 80,
  "crit_threshold": 95
}
```

**巢狀欄位 `service`**：
```json
{
  "status": "ok|warn|error",
  "services": [
    {"name": "sshd", "status": "running"},
    {"name": "crond", "status": "running"}
  ]
}
```

**巢狀欄位 `account`**：
```json
{
  "status": "ok|warn|error",
  "diff": "No changes",
  "uid0_alert": false,
  "accounts_added": [],
  "accounts_removed": []
}
```

**巢狀欄位 `error_log`**：
```json
{
  "status": "ok|warn|error",
  "count": 3,
  "max_entries": 50,
  "entries": [
    {"time": "2026-04-18 06:30:00", "level": "ERROR", "message": "..."}
  ]
}
```

**巢狀欄位 `system`**（v2.0+ 新增）：
```json
{
  "status": "ok|warn|error",
  "swap_percent": 5.2,
  "io_busy": 12.5,
  "load_average": {"1min": 0.5, "5min": 0.3, "15min": 0.2},
  "uptime_seconds": 864000,
  "online_users": 3,
  "failed_login": {
    "count": 15,
    "top_offenders": [
      {
        "user": "root",
        "count": 10,
        "status": "locked",
        "unlock_cmds": ["faillock --user root --reset"]
      }
    ]
  }
}
```

| `created_at` | string | 建立時間 (ISO 8601) |

**開發指引**：
- 建立複合索引 `(hostname, run_date, run_time)` 加速查詢
- `overall_status` 取各子項中最嚴重的狀態（error > warn > ok）
- 前端需根據 `uid0_alert` 顯示紅色閃爍警示

---

### 3.3 `filter_rules` Collection — 過濾規則

用於標記「已知問題」以減少誤報。

| 欄位 | 型別 | 說明 |
|------|------|------|
| `rule_id` | string | ObjectId 字串 |
| `name` | string | 規則名稱 |
| `type` | string | keyword / regex / level |
| `pattern` | string | 匹配模式 |
| `apply_to` | string | "all" 或特定 hostname |
| `enabled` | bool | 是否啟用 |
| `is_known_issue` | bool | 是否標記為已知問題 |
| `known_issue_reason` | string | 已知問題原因說明 |
| `hit_count` | int | 命中次數統計 |
| `created_at` | string | 建立時間 |
| `updated_at` | string | 更新時間 |

---

### 3.4 `settings` Collection — 系統設定

Key-Value 結構儲存所有系統組態。

**重要 Key 值**：

| Key | 預設值 | 說明 |
|-----|--------|------|
| `thresholds` | `{"disk_warn":85,"disk_crit":95,"cpu_warn":80,"cpu_crit":95,"mem_warn":80,"mem_crit":95}` | 門檻值 |
| `disk_exclude_mounts` | `["/dev","/run","/sys","/proc","/tmp"]` | 排除掛載點 |
| `disk_exclude_prefixes` | `["/run/","/dev/","/sys/","/proc/","/var/lib/containers/"]` | 排除前綴 |
| `cpu_sample_minutes` | `10` | CPU 取樣分鐘數 |
| `error_log_max_entries` | `50` | 錯誤日誌最大筆數 |
| `error_log_hours` | `24` | 錯誤日誌回溯小時 |
| `service_check_list` | `["sshd","crond"]` | 監控服務清單 |
| `notify_email` | `{"enabled":true,"smtp_host":"smtp.gmail.com",...}` | Email 通知設定 |

---

### 3.5 `users` Collection — 使用者帳號

| 欄位 | 型別 | 說明 |
|------|------|------|
| `username` | string | 登入帳號（唯一）|
| `password_hash` | string | bcrypt 雜湊密碼 |
| `display_name` | string | 顯示名稱 |
| `role` | string | superadmin / admin / oper |
| `must_change_password` | bool | 首次登入是否須改密碼 |
| `last_seen` | string | 最後活動時間 |
| `last_ip` | string | 最後登入 IP |
| `email` | string | Email（密碼重設用）|

---

### 3.6 `admin_worklog` Collection — 管理操作日誌

| 欄位 | 型別 | 說明 |
|------|------|------|
| `username` | string | 操作者帳號 |
| `action` | string | 操作類型（login/backup/restore/...）|
| `details` | string | 操作細節 |
| `timestamp` | string | 操作時間 |
| `ip_address` | string | 來源 IP |

---

### 3.7 `alert_acks` Collection — 告警確認

| 欄位 | 型別 | 說明 |
|------|------|------|
| `key` | string | 格式：hostname_date_time |
| `user` | string | 確認者帳號 |
| `timestamp` | string | 確認時間 |

---

### 3.8 `twgcb_results` Collection — TWGCB 合規結果

| 欄位 | 型別 | 說明 |
|------|------|------|
| `hostname` | string | 主機名稱 |
| `os` | string | 作業系統 |
| `scan_time` | string | 掃描時間 |
| `checks` | array | 各檢查項目 [{check_id, category, level, title, expected, actual, result: pass/fail/na}] |
| `imported_at` | string | 匯入時間 |

---

### 3.9 `twgcb_backups` Collection — 強化備份記錄

| 欄位 | 型別 | 說明 |
|------|------|------|
| `hostname` | string | 主機名稱 |
| `timestamp` | string | 備份時間戳 |
| `type` | string | full / incremental |
| `local_path` | string | 目標主機備份路徑 |
| `mgmt_path` | string | 管理站備份路徑 |
| `local_ok` | bool | 本機備份是否成功 |
| `mgmt_ok` | bool | 管理站備份是否成功 |
| `created_at` | string | 建立時間 |

---

### 3.10 `hr_users` Collection — HR 員工資料

| 欄位 | 型別 | 說明 |
|------|------|------|
| `ad_account` | string | AD 帳號 |
| `name` | string | 姓名 |
| `emp_id` | string | 員工編號 |
| `department` | string | 部門 |
| `title` | string | 職稱 |
| `email` | string | Email |
| `phone` | string | 電話 |

---

### 3.11 `account_notes` Collection — 帳號稽核備註

| 欄位 | 型別 | 說明 |
|------|------|------|
| `hostname` | string | 主機名稱 |
| `user` | string | 被備註的帳號 |
| `note` | string | 備註內容 |
| `department` | string | 所屬部門 |

---

## 4. 認證與授權系統

### 4.1 角色定義

| 角色 | 權限 | 說明 |
|------|------|------|
| `superadmin` | 全部 | 可管理使用者、Git 操作、重啟服務、所有管理功能 |
| `admin` | 管理級 | 可操作主機管理、備份還原、排程設定、告警管理 |
| `oper` | 唯讀 | 僅可瀏覽 Dashboard / Report / History / Summary |

### 4.2 認證機制

- **Session-based**：使用 Flask Session，HttpOnly Cookie
- **Session 存活時間**：8 小時
- **密碼儲存**：bcrypt 雜湊
- **預設管理員**：系統啟動時自動建立（`ensure_default_admin()`）
- **首次登入強制改密碼**：`must_change_password: true`

### 4.3 登入失敗鎖定

- 連續 5 次登入失敗 → 帳號鎖定 15 分鐘
- 使用 timestamp 追蹤（非資料庫計數器）

### 4.4 裝飾器

```python
@login_required      # 檢查 session["user_id"] 是否存在
@admin_required      # 檢查 role 是否為 admin 或 superadmin
@superadmin_required # 檢查 role 是否為 superadmin（僅 superadmin 頁面使用）
```

### 4.5 活躍使用者追蹤

- 每次 API 請求透過 `@app.before_request` 更新 `last_seen` 和 `last_ip`
- 線上使用者定義：30 分鐘內有活動
- API：`GET /api/admin/online-users`

**開發指引**：
- 未登入請求回傳 `401 {"success": false, "error": "未登入"}`
- 權限不足回傳 `403 {"success": false, "error": "權限不足"}`
- Session Cookie 設定：`HttpOnly=True, SameSite=Lax, Secure=True(生產環境)`

---

## 5. 前端頁面清單與功能

### 5.1 頁面總覽

| # | 路由 | 頁面 | 模板 | 需登入 | 最低角色 |
|---|------|------|------|--------|----------|
| 1 | `/login` | 登入頁 | login.html | N | - |
| 2 | `/` | Dashboard | dashboard.html | Y | oper |
| 3 | `/report` | 今日報告 | report.html | Y | oper |
| 4 | `/report/<hostname>` | 主機詳情 | host_detail.html | Y | oper |
| 5 | `/history` | 歷史查詢 | history.html | Y | oper |
| 6 | `/hosts` | 主機管理 | hosts.html | Y | oper |
| 7 | `/summary` | 異常總結 | summary.html | Y | oper |
| 8 | `/rules` | 過濾規則 | filter_rules.html | Y | admin |
| 9 | `/audit` | 帳號稽核 | audit.html | Y | oper |
| 10 | `/twgcb` | TWGCB 合規 | twgcb.html | Y | oper |
| 11 | `/twgcb/<hostname>` | TWGCB 主機詳情 | twgcb_detail.html | Y | oper |
| 12 | `/twgcb/harden/<hostname>` | 強化操作 | twgcb_harden.html | Y | admin |
| 13 | `/twgcb-report` | TWGCB 報告 | twgcb_report.html | Y | oper |
| 14 | `/twgcb-settings` | TWGCB 設定 | twgcb_settings.html | Y | admin |
| 15 | `/admin` | 管理後台 | admin.html | Y | admin |
| 16 | `/superadmin` | 超級管理員 | superadmin.html | Y | superadmin |
| 17 | `/reset-password` | 密碼重設 | reset_password.html | N | - |

### 5.2 導覽列（Navbar）

- 固定在頂部（sticky）
- 高度 56px
- 左側：Example Logo + 綠色圓點 + 系統名稱
- 右側：6 個主要連結（Dashboard / 今日報告 / 歷史查詢 / 主機管理 / 異常總結 / 過濾規則）
- 當前頁面底線標示（active underline）
- 右上角：版本號（從 `/api/settings/version` 取得）
- RWD：手機版顯示漢堡選單

### 5.3 模板繼承

```
base.html
  ├── dashboard.html
  ├── report.html
  ├── host_detail.html
  ├── history.html
  ├── hosts.html
  ├── summary.html
  ├── filter_rules.html
  ├── audit.html
  ├── twgcb.html
  ├── twgcb_detail.html
  ├── twgcb_harden.html
  ├── twgcb_report.html
  ├── twgcb_settings.html
  ├── admin.html
  ├── superadmin.html
  ├── login.html
  └── reset_password.html
```

---

## 6. API 端點完整清單

### 6.1 主機管理 API (`/api/hosts`)

| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/hosts` | page, per_page, os_group, status | 分頁主機列表 | 列出所有主機，支援 OS 類型與狀態篩選 |
| GET | `/api/hosts/summary` | - | {ok, warn, error, total} | 取得主機狀態統計摘要 |
| GET | `/api/hosts/<hostname>` | - | 主機文件 | 取得單一主機詳細資訊 |
| PUT | `/api/hosts/<hostname>/group` | {group: string} | success | 更新主機群組 |

### 6.2 巡檢結果 API (`/api/inspections`)

| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/inspections/latest` | - | 所有主機最新巡檢 | 取得每台主機最新一筆巡檢結果 |
| GET | `/api/inspections/<hostname>/latest` | - | 單一巡檢文件 | 取得特定主機最新巡檢 |
| GET | `/api/inspections/<hostname>/history` | days (預設 7) | 歷史巡檢陣列 | 取得指定天數的歷史巡檢資料 |
| GET | `/api/inspections/abnormal` | - | 異常巡檢清單 | 取得所有 warn/error 狀態的主機 |
| GET | `/api/inspections/trend` | days (預設 7) | 趨勢資料 | 取得按日彙總的狀態趨勢（ok/warn/error 數量）|
| GET | `/api/inspections/summary` | - | 異常摘要報告 | 綜合異常摘要，含問題描述與修復建議 |

### 6.3 過濾規則 API (`/api/rules`)

| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/rules` | - | 規則陣列 | 列出所有過濾規則 |
| POST | `/api/rules` | {name, type, pattern, apply_to, enabled, is_known_issue, known_issue_reason} | {rule_id} | 建立新規則 |
| PUT | `/api/rules/<rule_id>` | 同上 | success | 更新規則 |
| DELETE | `/api/rules/<rule_id>` | - | success | 刪除規則 |
| PUT | `/api/rules/<rule_id>/toggle` | - | {enabled: bool} | 切換規則啟用/停用 |

### 6.4 系統設定 API (`/api/settings`)

| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/settings` | - | {key: value} dict | 列出所有設定 |
| PUT | `/api/settings/<key>` | {value} | success | 更新設定值（同時寫入 MongoDB + settings.json 檔案）|
| GET | `/api/settings/version` | - | {version: string} | 取得系統版本號 |

### 6.5 LDAP API (`/api/ldap`)

| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/ldap/user/<ad_account>` | - | 使用者資訊 | 查詢 LDAP 使用者（目前為 Mock 模式）|

### 6.6 管理員 API (`/api/admin`) — 需 @login_required 或 @admin_required

#### 認證相關
| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| POST | `/api/admin/login` | {username, password} | {username, role, display_name, must_change_password} | 使用者登入，建立 Session |
| POST | `/api/admin/logout` | - | success | 登出並清除 Session |
| GET | `/api/admin/me` | - | {username, role, display_name} | 取得目前登入使用者資訊 |
| POST | `/api/admin/change-password` | {new_password} | success | 變更密碼 |

#### 系統狀態
| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/admin/system/status` | - | {flask, mongodb, disk, containers} | 系統健康檢查（Flask/MongoDB/磁碟/容器）|
| GET | `/api/admin/system/info` | - | {os, hostname, ip, versions, uptime} | 系統資訊（作業系統/主機名/IP/版本/運行時間）|
| POST | `/api/admin/system/run-inspection` | {hostname} | {pid, message} | 手動觸發單一主機巡檢 |
| GET | `/api/admin/online-users` | - | 線上使用者列表 | 取得 30 分鐘內活躍使用者 |

#### 設定管理
| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/admin/settings` | - | 所有設定 dict | 列出管理員設定 |
| PUT | `/api/admin/settings/<key>` | {value} | success | 更新設定（雙寫入：MongoDB + 檔案）|

#### 備份管理
| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/admin/backups` | - | 備份檔案陣列 | 列出所有備份 |
| POST | `/api/admin/backups` | - | {message, name} | 建立新備份 |
| POST | `/api/admin/backups/<name>/restore` | - | success | 從備份還原 |
| DELETE | `/api/admin/backups/<name>` | - | success | 刪除備份 |

#### 任務管理
| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| POST | `/api/admin/jobs/seed` | - | {output} | 重新匯入 MongoDB 資料 |
| GET | `/api/admin/jobs/status` | - | {last_run, log_tail} | 任務狀態與最新日誌 |

#### 日誌查看
| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/admin/logs/inspection` | date, keyword, tail | 日誌行陣列 | 查看巡檢日誌（支援日期/關鍵字篩選）|
| GET | `/api/admin/logs/flask` | tail | 日誌行陣列 | 查看 Flask 應用日誌 |

#### 告警管理
| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/admin/alerts` | - | 告警陣列 | 列出 warn/error 告警 |
| PUT | `/api/admin/alerts/<hostname>/<run_date>/<run_time>/ack` | - | success | 確認（acknowledge）告警 |

#### 主機 CRUD
| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| POST | `/api/admin/hosts` | {hostname, ip, os, ...} | success | 新增主機 |
| PUT | `/api/admin/hosts/<hostname>` | {fields} | success | 編輯主機 |
| DELETE | `/api/admin/hosts/<hostname>` | - | success | 刪除主機 |
| POST | `/api/admin/hosts/<hostname>/ping` | - | {reachable, output} | Ansible ping 測試連線 |
| POST | `/api/admin/hosts/regenerate-inventory` | - | {output} | 重新產生 Ansible inventory |

#### 匯入/匯出
| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| POST | `/api/admin/hosts/import-csv` | CSV 檔案或原始文字 | {message, count, errors} | 從 CSV 批次匯入主機 |
| POST | `/api/admin/hosts/import-json` | - | {message, count} | 從 hosts_config.json 匯入 |
| GET | `/api/admin/hosts/export-csv` | - | CSV 檔案下載 | 匯出所有主機為 CSV |
| GET | `/api/admin/hosts/template-csv` | - | CSV 範本下載 | 下載 CSV 匯入範本 |

#### 排程管理
| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/admin/scheduler` | - | cron 項目陣列 | 取得目前排程設定 |
| PUT | `/api/admin/scheduler` | {times: [{minute, hour, enabled}]} | success | 更新排程時間 |

#### 報表
| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/admin/reports/monthly` | month (YYYY-MM) | {month, hosts with SLA stats} | 月報（含 SLA 統計）|
| GET | `/api/admin/reports/export` | month, format (csv/json) | CSV 或 JSON 檔案 | 匯出月報 |

#### 操作日誌
| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/admin/worklog` | page | {data, total, page} | 管理操作稽核日誌（分頁）|

#### 帳號稽核
| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/admin/audit/accounts` | - | 稽核資料 | 帳號清冊與風險評估 |

### 6.7 帳號稽核公開 API (`/api/audit`)

| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/audit/accounts` | - | {data, count, thresholds} | 帳號稽核資料（含密碼老化/登入時間風險）|
| GET | `/api/audit/export` | - | CSV 檔案 | 匯出帳號稽核為 CSV |

### 6.8 TWGCB 合規 API (`/api/twgcb`)

| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| POST | `/api/twgcb/scan` | {target: all/hostname} | {message, count} | 觸發 TWGCB 合規掃描 |
| POST | `/api/twgcb/import` | - | {message, count} | 匯入 TWGCB JSON 結果 |
| GET | `/api/twgcb/results` | - | {data, count} | 取得所有 TWGCB 掃描結果 |
| GET | `/api/twgcb/results/<hostname>` | - | {data} | 取得單一主機 TWGCB 結果 |
| GET | `/api/twgcb/summary` | - | {total_hosts, compliant_hosts, compliance_rate, by_level, by_category, hosts} | 合規摘要（含 L1/L2/L3 分級、分類統計）|
| GET | `/api/twgcb/check/<check_id>` | - | {check info, pass/fail hosts} | 單一檢查項目分析 |

### 6.9 強化操作 API (`/api/harden`)

| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| POST | `/api/harden/backup/full` | {hostname} | {backup_id, local_path, mgmt_path} | 完整組態備份（本機+管理站雙備份）|
| POST | `/api/harden/backup/item` | {hostname, files} | 備份詳情 | 單一檔案備份 |
| GET | `/api/harden/backups/<hostname>` | - | 備份列表 | 列出主機所有備份快照 |
| POST | `/api/harden/restore` | {hostname, backup_id} | {message} | 從備份還原組態 |
| GET | `/api/harden/status/<hostname>` | - | 強化狀態 | 目前強化進度 |
| GET | `/api/harden/check-files/<check_id>` | - | 檔案狀態 | 檢查特定組態檔案狀態 |

### 6.10 超級管理員 API (`/api/superadmin`) — 需 @superadmin_required

| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/superadmin/check-auth` | - | {username, role, is_superadmin} | 驗證超級管理員身分 |
| GET | `/api/superadmin/git/status` | - | {branch, remote, changed_files, recent_commits} | Git 儲存庫狀態 |
| POST | `/api/superadmin/git/push` | {message} | {message, output} | Git commit & push |
| GET | `/api/superadmin/git/notes` | - | 備註陣列 | 取得 Git commit 備註 |
| PUT | `/api/superadmin/git/notes/<commit_hash>` | {note_text} | success | 新增 Git 備註 |
| GET | `/api/superadmin/git/diff` | - | diff 輸出 | 顯示未提交的變更 |
| GET | `/api/superadmin/docs/list` | - | 文件陣列 | 列出系統文件 |
| GET | `/api/superadmin/docs/view/<doc_id>` | - | 文件內容 | 查看文件 |
| GET | `/api/superadmin/docs/download/<doc_id>` | - | 檔案下載 | 下載文件 |

### 6.11 安全稽核 API (`/api/security-audit`)

| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/security-audit/hosts` | - | 主機列表 | 取得安全稽核目標主機 |
| POST | `/api/security-audit/run` | {hosts, params} | {job_id, message} | 觸發安全稽核（非同步）|
| GET | `/api/security-audit/progress/<job_id>` | - | {status, progress, current_host} | 即時進度追蹤 |
| GET | `/api/security-audit/reports` | - | 報告檔案列表 | 列出稽核報告 |
| GET | `/api/security-audit/reports/<filename>/download` | - | 檔案下載 | 下載報告 |
| GET | `/api/security-audit/reports/<filename>/preview` | - | HTML/文字預覽 | 預覽報告 |
| GET | `/api/security-audit/config` | - | 目前設定 | 取得稽核設定 |
| PUT | `/api/security-audit/config` | {config_data} | success | 更新稽核設定 |

### 6.12 Linux 初始化 API (`/api/linux-init`)

| 方法 | 路徑 | 參數 | 回傳 | 功能說明 |
|------|------|------|------|----------|
| GET | `/api/linux-init/hosts` | - | 主機列表 | 取得初始化目標主機 |
| POST | `/api/linux-init/run` | {hosts, services, params} | {job_id, message} | 觸發 Linux 初始化（非同步）|
| GET | `/api/linux-init/progress/<job_id>` | - | {status, progress, current_host} | 即時進度 |
| GET | `/api/linux-init/config` | - | 目前設定 | 取得初始化設定 |
| PUT | `/api/linux-init/config` | {config_data} | success | 更新初始化設定 |
| POST | `/api/linux-init/rollback/list` | {hostname} | 快照列表 | 列出回滾點 |
| POST | `/api/linux-init/rollback/restore` | {hostname, snapshot_id} | {message} | 還原快照 |
| GET | `/api/linux-init/reports` | - | 報告列表 | 列出初始化報告 |
| GET | `/api/linux-init/reports/<filename>/download` | - | 檔案下載 | 下載報告 |
| GET | `/api/linux-init/reports/<filename>/preview` | - | HTML/文字 | 預覽報告 |

---

## 7. Ansible 自動化與角色

### 7.1 核心巡檢角色（site.yml 執行順序）

#### 角色 1：`check_disk` — 磁碟使用率
- **檢查項目**：所有掛載點的使用百分比
- **門檻**：warn=85%, crit=95%（可在 settings 調整）
- **排除**：/dev, /run, /sys, /proc, /tmp 等虛擬檔案系統
- **支援 OS**：Linux（df）、AIX（df -g）
- **輸出**：各分割區的 mount/size/used/free/percent/status

#### 角色 2：`check_cpu` — CPU 與記憶體
- **檢查項目**：CPU 使用率、記憶體使用率
- **門檻**：cpu_warn=80%, cpu_crit=95%, mem_warn=80%, mem_crit=95%
- **取樣**：預設 10 分鐘平均（可調）
- **支援 OS**：Linux（top/proc）、AIX（vmstat）、Windows（WMI PowerShell）

#### 角色 3：`check_service` — 服務狀態
- **檢查項目**：關鍵服務是否運行
- **預設監控**：sshd, crond
- **可自訂**：透過 settings 的 service_check_list
- **輸出**：每個服務的 name + status (running/stopped/failed)

#### 角色 4：`check_account` — 帳號變更偵測
- **檢查項目**：使用者帳號增減、UID=0 特權帳號
- **機制**：與前次快照比對（diff-based）
- **UID=0 警示**：若發現非 root 的 UID=0 帳號，觸發紅色閃爍警報
- **輸出**：新增帳號列表、移除帳號列表、uid0_alert 布林值

#### 角色 5：`check_error_log` — 錯誤日誌
- **檢查項目**：過去 24 小時系統日誌中的錯誤/警告
- **關鍵字**：kernel panic, OOM, permission denied, segfault 等
- **日誌來源**：
  - RHEL: /var/log/messages, /var/log/secure
  - Debian: /var/log/syslog, /var/log/auth.log
- **限制**：最多回傳 50 筆（可調）

#### 角色 6：`check_db_connection` — 資料庫連線
- **檢查項目**：TCP 埠測試資料庫連線
- **支援**：MySQL, PostgreSQL, Oracle, MongoDB
- **可設定**：per-host 連線字串

#### 角色 7：`check_account_audit` — 帳號安全稽核
- **檢查項目**：密碼老化、鎖定帳號、sudo 權限
- **輸出**：密碼上次更改日、帳號是否鎖定、sudoers 設定

#### 角色 8：`check_system` — 系統指標
- **檢查項目**：
  - Swap 使用率
  - IO Busy 百分比
  - Load Average（1/5/15 分鐘）
  - 開機時間（Uptime）
  - 線上使用者數
  - 失敗登入統計（含鎖定帳號偵測與解鎖指令）
- **支援 OS**：Linux（uptime, faillog, lastb）、AIX（lsattr）

#### 角色 9：`check_windows` — Windows 檢查
- **透過**：SSH + 編碼 PowerShell 命令
- **檢查項目**：
  - CPU/記憶體（WMI）
  - Windows Update（最近 30 天 HotFix）
  - Windows Defender（即時防護、病毒碼日期、威脅偵測）
  - 防火牆設定檔（Domain/Private/Public）
  - IIS 網站狀態
  - 事件日誌錯誤/警告

#### 角色 10：`check_snmp` — 網路設備 SNMP
- **執行位置**：委派至 localhost（ansible-host）
- **協定**：SNMPv1/v2c/v3
- **支援設備**：Cisco, Juniper, Aruba, Fortinet, 通用 SNMP
- **指標**：系統描述、運行時間、介面狀態/錯誤、CPU/記憶體
- **門檻**：介面 Down 數量、錯誤計數

#### 角色 11：`check_as400` — IBM AS/400
- **透過**：SNMP
- **指標**：工作佇列、程式庫狀態、磁碟使用

#### 角色 12：`check_twgcb` — TWGCB 合規檢查
- **項目數**：43+ 項（Linux 版）
- **分級**：L1（基本）/ L2（中級）/ L3（進階）
- **分類**：8 大類（密碼政策、帳號管理、SSH、SELinux、防火牆、稽核、檔案權限、網路）
- **輸出**：每項 check_id, category, level, title, expected, actual, result(pass/fail/na)

### 7.2 結果彙總邏輯

```
overall_status = max(disk.status, cpu.status, service.status, 
                     account.status, error_log.status, system.status)
# error > warn > ok
```

### 7.3 其他 Playbook

| Playbook | 用途 |
|----------|------|
| `create_ansible_svc.yml` | 在所有主機建立 ansible_svc 服務帳號 |
| `security_audit.yml` | 觸發安全稽核腳本（6 大類 100+ 項）|
| `linux_init.yml` | 系統初始化/強化（A/B 級參數）|
| `twgcb_scan.yml` | TWGCB 合規掃描 |

---

## 8. Shell 腳本與自動化工具

### 8.1 `run_inspection.sh` — 每日巡檢啟動器
- **Cron 排程**：`30 6,13,17 * * *`（每日 06:30 / 13:30 / 17:30）
- **功能**：
  1. PID 鎖定（防止併行執行）
  2. 呼叫 `ansible-playbook site.yml`
  3. 執行 `seed_data.py` 匯入 MongoDB
  4. 自動清理：日誌 >30 天、HTML 報告 >90 天、JSON 報告 >90 天
- **日誌**：`${INSPECTION_HOME}/logs/{TIMESTAMP}_run.log`

### 8.2 `security_audit.sh` — Linux 安全稽核腳本
- **支援系統**：RHEL 7/8/9, CentOS 7/8, Rocky 8/9, AlmaLinux 8/9, Debian 10-12, Ubuntu 20.04-24.04
- **6 大稽核類別**：
  1. AUDIT_CAT1：OS 版本與 EOS/補丁合規
  2. AUDIT_CAT2：密碼政策（remember, PASS_MIN_DAYS, PASS_MAX_DAYS, 複雜度）
  3. AUDIT_CAT3：帳號/群組管理、sudoers 權限
  4. AUDIT_CAT4：檔案/目錄權限（shadow, audit, logs）
  5. AUDIT_CAT5：網路安全（SSH, SELinux, 防火牆, 開放埠）
  6. AUDIT_CAT6：稽核日誌、syslog 設定
- **產出**：
  - 主報告：`/tmp/Audit_Report_{HOSTNAME}_{DATE}.txt`
  - 大檔案分割：>100 行自動拆分
  - 壓縮包：`/tmp/Audit_{HOSTNAME}_{DATE}.tar.gz`

### 8.3 `install.sh` — 離線安裝腳本
- **互動式安裝**：引導設定路徑、埠號、密碼、Cron 時間
- **步驟**：
  1. OS 驗證（Rocky Linux）
  2. Root 權限檢查
  3. 離線套件解壓（inspection_app.tar.gz, mongodb6.tar）
  4. Python 依賴安裝
  5. MongoDB 容器啟動（Podman）
  6. config.py 生成（含隨機 SECRET_KEY）
  7. MongoDB 初始化（使用者/Collection）
  8. Systemd 服務設定
  9. Cron 註冊（最多 3 個時段）
  10. Flask 應用啟動

### 8.4 `deploy_security_audit.sh` — 安全稽核增量部署
- 備份現有檔案至 `/seclog/backup/pre_security_audit_{DATE}/`
- 複製新檔案：admin.html, app.py, api_security_audit.py, admin.js, security_audit.sh, playbook
- 重啟 Flask 服務

### 8.5 `seed_data.py` — 資料匯入腳本
- 將 `/data/reports/` 下的 JSON 報告匯入 MongoDB `inspections` collection
- 同步 `hosts` collection 的主機清單

### 8.6 `generate_report.py` — HTML 報告產生器
- 從 MongoDB 查詢最新巡檢結果
- 產生 HTML 格式報告
- 可透過 SMTP 發送 Email

### 8.7 `generate_inventory.py` — Ansible Inventory 產生器
- 從 `hosts` collection 產生 `hosts.yml`
- 支援 Ansible Vault 加密密碼

---

## 9. 設計系統 (CSS/UI)

### 9.1 色彩系統（CSS 變數）

```css
:root {
  --g1: #4AB234;      /* 主要綠色 — OK 狀態、品牌色 */
  --g2: #26A862;      /* 深綠色 — Hover */
  --g-text: #124F05;  /* 暗綠色 — 品牌文字 */
  --g-light: #E8F5E9; /* 淺綠背景 */
  --yellow: #FFCA28;  /* 警告色 */
  --orange: #E87C07;  /* 告警色（85-95%）*/
  --red: #E00B00;     /* 嚴重/錯誤色（95%+, UID=0）*/
  --c1: #333333;      /* 主要文字 */
  --c2: #555555;      /* 次要文字 */
  --c3: #888888;      /* 輔助文字 */
  --c4: #BEBEBE;      /* 邊框色 */
  --bg: #F7F7F7;      /* 頁面背景 */
  --white: #FFFFFF;
}
```

### 9.2 字型

- **標題/內文**：Noto Sans TC（Google Fonts 繁體中文）
- **數據/指標**：JetBrains Mono（等寬字型）

### 9.3 元件清單

#### 導覽列 `.navbar`
- Sticky 頂部固定，高度 56px
- 品牌 Logo 含綠色圓點
- 水平選單，active 底線標示

#### 卡片 `.card`
- 白色背景、陰影、圓角
- `.card-title`：大寫灰色副標題

#### KPI 卡片 `.kpi-grid` + `.kpi-card`
- 自動適應欄位（min 200px）
- 頂部色條（依狀態著色）
- `.kpi-value`：36px 等寬大數字
- 色彩變體：`.kpi-value.ok`（綠）/ `.warn`（橘）/ `.error`（紅）

#### 狀態徽章 `.badge`
- 圓角藥丸標籤（12px 字體）
- `.badge-ok`（淺綠）/ `.badge-warn`（淺黃）/ `.badge-error`（淺紅）

#### 表格 `table`
- 全寬、hover 行高亮
- `th`：大寫灰色標頭
- `td`：等寬 13px 字型
- `.table-wrap`：水平捲動容器

#### 表單 `.form-group`
- 垂直堆疊（label + input）
- 輸入框：1px 灰邊框、8px 內距

#### 按鈕 `.btn`
- `.btn-primary`：綠底白字
- `.btn-danger`：紅底白字
- `.btn-sm`：小尺寸變體

#### 進度條 `.progress-bar`
- `.progress-fill.ok/warn/error`：色彩化填充動畫

#### UID=0 警示 `.uid0-alert`
- 紅色閃爍動畫（1 秒週期交替淡紅/紅）

#### Modal `.modal-overlay` + `.modal`
- 全螢幕半透明遮罩
- 白色對話框（max-width 500px）

#### 圖表 `.chart-grid`
- 雙欄排版（2fr + 1fr）
- 圖表高度 140-200px

#### 骨架屏 `.skeleton`
- 閃爍漸層動畫（1.5 秒）

#### 空狀態 `.no-data`
- 置中文字 + Emoji 圖示

### 9.4 RWD 響應式設計

| 斷點 | 變化 |
|------|------|
| ≤768px（平板）| 圖表改為單欄、KPI 改為 2 欄、Navbar 內距縮減 |
| ≤375px（手機）| 漢堡選單、堆疊佈局、表格水平捲動 |

---

## 10. 部署與運維

### 10.1 MongoDB 容器啟動

```bash
mkdir -p /seclog/AI/inspection/container/mongodb_data
podman run -d --name mongodb \
  -p 127.0.0.1:27017:27017 \
  -v /seclog/AI/inspection/container/mongodb_data:/data/db:Z \
  --restart=always \
  docker.io/library/mongo:6
```

### 10.2 Flask 服務（Systemd）

```ini
[Unit]
Description=itagent-web
After=network.target itagent-db.service

[Service]
Type=notify
ExecStart=gunicorn --workers=4 --bind=0.0.0.0:5000 app:app
WorkingDirectory=/seclog/AI/inspection/webapp
Environment=PYTHONUNBUFFERED=1
Restart=always

[Install]
WantedBy=multi-user.target
```

### 10.3 Cron 排程

```bash
30 6 * * *  /seclog/AI/inspection/run_inspection.sh >> logs/cron.log 2>&1
30 13 * * * /seclog/AI/inspection/run_inspection.sh >> logs/cron.log 2>&1
30 17 * * * /seclog/AI/inspection/run_inspection.sh >> logs/cron.log 2>&1
```

### 10.4 自動清理

| 目標 | 保留天數 | 清理指令 |
|------|----------|----------|
| 執行日誌 | 30 天 | `find logs -name "*.log" -mtime +30 -delete` |
| HTML 報告 | 90 天 | `find data/reports -name "*.html" -mtime +90 -delete` |
| JSON 報告 | 90 天 | `find data/reports -name "*.json" -mtime +90 -delete` |

### 10.5 備份策略

- **變更前自動備份**：`tar czf /seclog/backup/INSPECTION_HOME_$(date).tar.gz`
- **保留數量**：最近 3 份，舊的自動刪除
- **雙備份**（TWGCB 強化時）：目標主機 + ansible-host 管理站

### 10.6 目錄結構

```
/seclog/AI/inspection/
├── ansible/
│   ├── inventory/hosts.yml
│   ├── playbooks/
│   │   ├── site.yml
│   │   ├── create_ansible_svc.yml
│   │   ├── security_audit.yml
│   │   ├── linux_init.yml
│   │   └── twgcb_scan.yml
│   └── roles/
│       ├── check_disk/
│       ├── check_cpu/
│       ├── check_service/
│       ├── check_account/
│       ├── check_error_log/
│       ├── check_db_connection/
│       ├── check_account_audit/
│       ├── check_system/
│       ├── check_windows/
│       ├── check_snmp/
│       ├── check_as400/
│       └── check_twgcb/
├── webapp/
│   ├── app.py
│   ├── config.py
│   ├── seed_data.py
│   ├── routes/
│   │   ├── api_hosts.py
│   │   ├── api_inspections.py
│   │   ├── api_rules.py
│   │   ├── api_settings.py
│   │   ├── api_ldap.py
│   │   ├── api_admin.py
│   │   ├── api_audit.py
│   │   ├── api_twgcb.py
│   │   ├── api_harden.py
│   │   ├── api_superadmin.py
│   │   ├── api_security_audit.py
│   │   └── api_linux_init.py
│   ├── models/
│   ├── services/
│   ├── templates/
│   └── static/
├── scripts/
├── data/
│   ├── reports/
│   ├── settings.json
│   └── version.json
├── logs/
├── container/
│   └── mongodb_data/
└── run_inspection.sh
```

---

## 11. 安全機制

### 11.1 已實作的安全措施

| # | 類別 | 措施 | 說明 |
|---|------|------|------|
| 1 | 憑證 | Ansible Vault | inventory/hosts.yml 中的密碼加密 |
| 2 | 輸入驗證 | NoSQL 注入防護 | 字串型別 + 長度限制驗證 |
| 3 | 應用 | Flask Debug 關閉 | `FLASK_DEBUG = False` |
| 4 | 應用 | 隨機 SECRET_KEY | `secrets.token_hex(32)` 每次部署重新產生 |
| 5 | 認證 | API 認證 | 所有 API 端點加上 `@login_required` |
| 6 | 認證 | 登入鎖定 | 5 次失敗 → 15 分鐘鎖定 |
| 7 | HTTP | 安全標頭 | X-Frame-Options, CSP, X-Content-Type-Options 等 |
| 8 | Session | 安全 Cookie | HttpOnly, SameSite=Lax, Secure（生產環境）|
| 9 | 檔案 | 權限控制 | config.py, settings.json, .vault_pass 設為 600 |
| 10 | 憑證 | 環境變數 | SMTP 密碼存於 .env（chmod 600）|

### 11.2 HTTP 安全標頭

```python
response.headers['X-Frame-Options'] = 'DENY'
response.headers['X-Content-Type-Options'] = 'nosniff'
response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
response.headers['Permissions-Policy'] = 'geolocation=(), microphone=(), camera=()'
response.headers['X-XSS-Protection'] = '1; mode=block'
response.headers['Content-Security-Policy'] = "default-src 'self' 'unsafe-inline' 'unsafe-eval' ..."
# Server header 被移除
```

---

## 12. 版本管理機制

### 12.1 version.json 結構

```json
{
  "version": "3.4.2.0",
  "updated": "2026-04-16 16:06",
  "changelog": [
    {"version": "3.4.2.0", "date": "2026-04-16", "changes": ["TWGCB 錯誤詳情顯示", "Windows 強化"]},
    {"version": "3.4.1.0", "date": "2026-04-15", "changes": ["..."]},
    // ... 40+ 版本記錄
  ]
}
```

### 12.2 版本號規則

格式：`X.Y.Z.W`
- X：大版本（架構變更）
- Y：功能版本（新功能）
- Z：修補版本（Bug 修正）
- W：建置號

### 12.3 每次 Commit 前必須更新 version.json

---

## 13. 各頁面功能詳細說明（使用者手冊級）

### 13.1 登入頁 (`/login`)

**功能特色**：
系統的入口頁面，所有使用者必須先登入才能使用系統功能。

**頁面元素**：
- Example品牌 Logo
- 帳號輸入框
- 密碼輸入框
- 登入按鈕
- 忘記密碼連結（導向 `/reset-password`）

**行為邏輯**：
1. 使用者輸入帳號/密碼後點擊「登入」
2. 呼叫 `POST /api/admin/login`
3. 成功 → 建立 Session → 跳轉至 Dashboard
4. 失敗 → 顯示錯誤訊息（帳號或密碼錯誤）
5. 連續 5 次失敗 → 帳號鎖定 15 分鐘，顯示剩餘等待時間
6. 若 `must_change_password: true` → 登入後強制跳轉至改密碼頁

**開發指引**：
- 密碼欄位使用 `type="password"`
- 支援 Enter 鍵送出表單
- 錯誤訊息不可洩漏「帳號不存在」或「密碼錯誤」的具體資訊，統一顯示「帳號或密碼錯誤」

---

### 13.2 Dashboard (`/`)

**功能特色**：
系統首頁，一眼掌握所有主機的健康狀態。提供 KPI 數字摘要、7 天趨勢圖、狀態分布圖、以及完整主機列表。點擊 KPI 卡片可快速篩選特定狀態的主機。

**頁面區塊**：

#### A. KPI 卡片區（4 張可點擊卡片）
- **正常主機**（綠色頂線）：顯示 ok 狀態的主機數量
- **警告主機**（橘色頂線）：顯示 warn 狀態的主機數量
- **異常主機**（紅色頂線）：顯示 error 狀態的主機數量
- **主機總數**（灰色頂線）：顯示所有主機數量

點擊任一卡片 → 下方主機表格自動篩選顯示對應狀態的主機。

#### B. 圖表區（雙欄）
- **左側：近 7 日趨勢圖**（折線圖 — Chart.js Line）
  - 三條線：OK（綠）、WARN（橘）、ERROR（紅）
  - X 軸：日期，Y 軸：主機數量
  - 資料來源：`GET /api/inspections/trend`

- **右側：狀態分布圖**（甜甜圈圖 — Chart.js Doughnut）
  - 三個區塊：OK / WARN / ERROR
  - 中心顯示總數

#### C. UID=0 警示區
- 若任何主機偵測到非 root 的 UID=0 帳號，此區會以**紅色閃爍動畫**顯示
- 動畫為 1 秒週期，在淡紅和紅色之間交替

#### D. 篩選後主機結果區
- 點擊 KPI 卡片後顯示（初始隱藏）
- 列出被篩選的主機名稱與基本資訊

#### E. 全部主機狀態表格
- **8 欄**：主機名稱、IP、OS、狀態、磁碟%、CPU%、服務、帳號
- 狀態欄使用色彩徽章（badge-ok/warn/error）
- **「只顯示異常」核取方塊**：勾選後僅顯示 warn/error 的主機
- 磁碟%/CPU% 超過門檻值時顯示橘色或紅色

**AJAX 呼叫**：
- `GET /api/hosts/summary` → KPI 數字
- `GET /api/inspections/trend` → 趨勢資料
- `GET /api/inspections/latest` → 所有主機最新巡檢

**開發指引**：
- 頁面載入時三個 API 並行呼叫
- 圖表使用 Chart.js v4
- KPI 卡片的數字使用 36px 等寬字型
- 全域變數 `_allHostsData` 快取主機資料供篩選用

---

### 13.3 今日報告 (`/report`)

**功能特色**：
以卡片形式展示每台主機的今日巡檢結果，每張卡片濃縮顯示該主機的所有健康指標。可一眼看出哪些主機有問題。支援 OS 分頁（Linux / Windows / AIX / AS400）。

**卡片內容（每台主機一張）**：
- **標題列**：主機名稱 + 狀態徽章
- **基本資訊**：IP、OS、巡檢時間
- **UID=0 警示**（有則顯示紅色閃爍）
- **CPU%**：百分比數值，超門檻變色
- **MEM%**：記憶體使用率
- **Swap%**：交換空間使用率
- **IO Busy%**：磁碟 IO 忙碌度
- **Load Average**：1/5/15 分鐘負載（對比 CPU 核心數）
- **線上使用者數**
- **磁碟狀態**：列出各分割區使用率（含進度條視覺化）
- **服務狀態**：以徽章顯示各服務 running/stopped
- **帳號稽核**：帳號總數、新增/移除帳號
- **錯誤日誌**：Error/Warning 數量
- **失敗登入**：次數 + 鎖定帳號列表 + 解鎖指令
- **運行時間**：Uptime 天數/小時

**可點擊**：整張卡片可點擊，連結至 `/report/{hostname}` 詳情頁。

**AJAX 呼叫**：`GET /api/inspections/latest`

**開發指引**：
- 卡片使用 CSS Grid（auto-fill, min 320px）
- 問題分割區的進度條根據使用率著色（綠/橘/紅）
- 服務狀態使用徽章（badge-ok/badge-error）

---

### 13.4 主機詳情 (`/report/<hostname>`)

**功能特色**：
單一主機的深度報告頁面，展示該主機所有巡檢細節。是管理員排查問題的主要工具。

**頁面區塊**：

#### A. 標題卡片
- 主機名稱（大字）
- 狀態徽章
- IP、OS、巡檢時間等 metadata

#### B. UID=0 詳細警示
- 若觸發，顯示完整的 UID=0 帳號清單

#### C. 系統資訊列（4 張指標卡）
- 開機時間（Uptime）
- 線上使用者數
- Swap 使用率
- IO Busy %

#### D. CPU/記憶體卡片
- 雙欄顯示
- 大字百分比數值
- 依門檻著色

#### E. Load Average 卡片
- 1min / 5min / 15min 三欄
- 顯示與 CPU 核心數的比值

#### F. 磁碟使用卡片
- 問題分割區：進度條視覺化（橘/紅）
- 正常分割區：文字列表

#### G. 服務狀態卡片
- 表格：服務名稱 + 狀態徽章

#### H. 帳號稽核卡片
- 帳號總數
- 新增帳號列表（橘色）
- 移除帳號列表（紅色）
- 備註區

#### I. 錯誤日誌卡片
- Error/Warning 統計數
- 日誌表格：時間 / 等級 / 訊息
- 可展開查看詳情

#### J. 失敗登入卡片
- 總失敗次數
- 鎖定帳號區（含解鎖指令，如 `faillock --user root --reset`）
- Top Offenders 表格（帳號 / 次數 / 鎖定狀態）
- 原始資料可收合區

**AJAX 呼叫**：`GET /api/inspections/<hostname>/latest`

---

### 13.5 歷史查詢 (`/history`)

**功能特色**：
查看特定主機過去一段時間的巡檢趨勢，透過折線圖和表格分析健康狀態的變化。

**頁面元素**：
- **主機下拉選單**：從 `/api/hosts` 載入所有主機名稱
- **天數選擇**：7 天 / 14 天 / 30 天
- **趨勢折線圖**（Chart.js Line）：
  - CPU% 趨勢線（綠色）
  - 磁碟最高% 趨勢線（橘色）
- **歷史記錄表格**（6 欄）：
  - 日期、時間、狀態、CPU%、磁碟最高%、錯誤日誌數
- **無資料狀態**：顯示提示訊息

**AJAX 呼叫**：
- `GET /api/hosts` → 主機清單
- `GET /api/inspections/<hostname>/history?days=N` → 歷史資料

---

### 13.6 主機管理 (`/hosts`)

**功能特色**：
管理受監控的主機清單。支援篩選、群組指派。管理員可從 Admin 後台進行新增/編輯/刪除和 CSV 匯入匯出。

**頁面元素**：
- **篩選控制列**：
  - OS 類型下拉（rocky, debian, rhel, windows, aix, snmp, as400）
  - 狀態下拉（使用中 / 停用）
- **主機表格**（8 欄）：
  - 主機名稱、IP、OS、狀態、環境、群組、保管者、操作
- **群組編輯 Modal**：
  - 主機名稱（唯讀）
  - 群組名稱輸入框
  - 儲存 / 取消按鈕

**AJAX 呼叫**：
- `GET /api/hosts?per_page=200&os_group=...&status=...`
- `PUT /api/hosts/<hostname>/group`

---

### 13.7 異常總結 (`/summary`)

**功能特色**：
AI 生成的異常報告，將所有問題按嚴重度排序，並附帶修復建議。可匯出為 .txt 文字檔。

**頁面區塊**：

#### A. 摘要 KPI（4 張卡片）
- 監控主機總數
- 正常主機數
- 異常/警告主機數
- 報告產生時間

#### B. 全部正常狀態
- 如果所有主機都 OK，顯示綠色勾勾圖示和「全部正常」訊息

#### C. 異常項目區（按主機分組）
- 每台異常主機一張卡片：
  - 主機名稱 + 狀態 + 趨勢圖示
  - 問題數量
  - **問題表格**：嚴重度、分類、詳細描述
  - **修復建議區**（綠色背景）：編號建議列表

#### D. 匯出按鈕
- 將報告內容匯出為 `.txt` 純文字檔案（Client-side Blob 下載）

**AJAX 呼叫**：`GET /api/inspections/summary`

---

### 13.8 過濾規則 (`/rules`)

**功能特色**：
管理員可建立「已知問題」過濾規則，讓反覆出現的已知告警不再干擾。支援關鍵字、正規表達式、等級三種匹配方式。

**頁面元素**：
- **「新增規則」按鈕**
- **規則列表**：
  - 規則卡片：名稱、類型、匹配模式、命中次數
  - 已知問題標記
  - 啟用/停用切換按鈕
  - 刪除按鈕

- **新增/編輯 Modal**：
  - 名稱輸入框
  - 類型選擇（keyword / regex / level）
  - 匹配模式輸入框
  - 適用範圍（全部主機 / 特定主機）
  - 「標記為已知問題」核取方塊
  - 已知問題原因文字區
  - 儲存 / 取消

**AJAX 呼叫**：
- `GET /api/rules` — 載入規則列表
- `POST /api/rules` — 建立
- `PUT /api/rules/<id>` — 更新
- `PUT /api/rules/<id>/toggle` — 切換啟用
- `DELETE /api/rules/<id>` — 刪除

---

### 13.9 帳號稽核 (`/audit`)

**功能特色**：
盤點所有受監控主機上的使用者帳號，與 HR 員工資料比對，識別離職人員殘留帳號、密碼過期帳號、長期未登入帳號等風險。

**頁面元素**：
- 帳號清冊表格
- 風險篩選（密碼老化 / 長期未登入 / 離職殘留）
- HR 比對狀態
- 匯出 CSV 功能

**AJAX 呼叫**：
- `GET /api/audit/accounts`
- `GET /api/audit/export`

---

### 13.10 TWGCB 合規 (`/twgcb`)

**功能特色**：
展示所有主機的 TWGCB（台灣政府組態基準）合規狀態。以 Excel 式矩陣呈現，可按 OS 分頁查看。支援合規率統計、分級分類分析。

**頁面元素**：
- **OS 分頁標籤**：Linux / Windows / AIX / AS400
- **合規率摘要**：總合規率%、合規主機數/總主機數
- **分級統計**（L1/L2/L3）
- **分類統計**（8 大類）
- **主機合規矩陣**：每台主機的 pass/fail/na 數量

可點擊主機名稱 → 跳轉至 `/twgcb/<hostname>` 詳情頁。

**AJAX 呼叫**：
- `GET /api/twgcb/results`
- `GET /api/twgcb/summary`

---

### 13.11 TWGCB 主機詳情 (`/twgcb/<hostname>`)

**功能特色**：
單一主機的完整 TWGCB 合規檢查結果。逐項列出每個檢查的預期值、實際值、結果。

**頁面元素**：
- 主機名稱 + OS + 掃描時間
- 合規率統計
- **檢查項目表格**：
  - Check ID
  - 分類（Category）
  - 等級（L1/L2/L3）
  - 標題
  - 預期值（Expected）
  - 實際值（Actual）
  - 結果（Pass ✓ / Fail ✗ / N/A）

**AJAX 呼叫**：`GET /api/twgcb/results/<hostname>`

---

### 13.12 TWGCB 強化操作 (`/twgcb/harden/<hostname>`)

**功能特色**：
針對合規檢查 Fail 的項目，提供一鍵修復功能。修復前自動備份組態，支援回滾。

**頁面元素**：
- 主機名稱 + 目前合規率
- Fail 項目列表（可勾選）
- **備份按鈕**：建立修復前快照
- **修復按鈕**：套用選取的修復項目
- **回滾區**：列出歷史備份快照，可選擇還原

**AJAX 呼叫**：
- `POST /api/harden/backup/full`
- `GET /api/harden/backups/<hostname>`
- `POST /api/harden/restore`
- `GET /api/harden/status/<hostname>`

---

### 13.13 TWGCB 報告 (`/twgcb-report`)

**功能特色**：
產生正式的 TWGCB 合規報告，含簽核欄位，可供稽核使用。

---

### 13.14 TWGCB 設定 (`/twgcb-settings`)

**功能特色**：
設定 TWGCB 合規政策的門檻值和例外處理規則。

---

### 13.15 管理後台 (`/admin`)

**功能特色**：
系統管理員的控制中心，以 12 個分頁組織所有管理功能。透過 JavaScript Tab 導航，不重新載入頁面。

#### Tab 1：Dashboard
- 系統狀態概覽（Flask/MongoDB/磁碟/容器 健康狀態）
- 系統資訊（OS/主機名/IP/版本/運行時間）
- 線上使用者列表
- 快速操作按鈕（手動觸發巡檢、重新匯入資料）

#### Tab 2：Settings（設定）
- **門檻值設定**：磁碟 warn/crit、CPU warn/crit、記憶體 warn/crit
- **服務監控清單**：可新增/移除監控的服務名稱
- **磁碟排除路徑**：排除不需監控的掛載點
- **Email 通知設定**：SMTP 主機/埠/帳號/收件者

#### Tab 3：Backups（備份）
- 備份列表：名稱、大小、建立時間
- **建立備份按鈕**
- 每筆備份的操作：還原 / 刪除

#### Tab 4：Jobs（任務）
- 最後執行時間
- 日誌尾端內容
- 重新匯入資料按鈕

#### Tab 5：Logs（日誌）
- 日期篩選
- 關鍵字搜尋
- 巡檢日誌檢視器
- Flask 應用日誌檢視器

#### Tab 6：Hosts（主機管理）
- 完整主機列表
- 新增主機按鈕
- 每筆主機：編輯 / 刪除 / Ping 測試
- **CSV 匯入**：上傳 CSV 檔案批次新增
- **CSV 匯出**：下載所有主機資料
- **CSV 範本下載**
- **JSON 匯入**：從 hosts_config.json 匯入
- **重新產生 Inventory**：重建 Ansible hosts.yml

#### Tab 7：Alerts（告警）
- 最近 100 筆告警列表
- 每筆告警可點擊「確認」（acknowledge）

#### Tab 8：Scheduler（排程）
- 目前排程時間表
- 可編輯每個時段的小時/分鐘
- 啟用/停用切換
- 儲存按鈕

#### Tab 9：Reports（報表）
- 月份選擇器
- 月報產生（含 SLA 統計）
- 匯出 CSV / JSON

#### Tab 10：Audit（帳號稽核）
- 帳號清冊
- 風險篩選
- HR 資料比對

#### Tab 11：Account Management（帳號管理）
- 稽核門檻設定
- HR 資料匯入（CSV）
- 帳號備註管理

#### Tab 12：Worklog（操作日誌）
- 管理操作稽核紀錄（分頁）
- 顯示：操作者、操作類型、細節、時間、IP

**開發指引**：
- 12 個 Tab 使用 JavaScript 切換，URL hash（`#tabname`）
- 每個 Tab 延遲載入（lazy load）— 切換時才呼叫對應 API
- 確認對話框保護破壞性操作（刪除/還原）

---

### 13.16 超級管理員 (`/superadmin`)

**功能特色**：
開發者專用後台，提供 Git 版控操作、服務重啟、使用者管理等進階功能。僅 `superadmin` 角色可訪問。

**頁面元素**：

#### Git 管理區
- **儲存庫狀態**：分支、遠端、已變更檔案、最近 commits
- **Git Push 按鈕**：輸入 commit message → 自動 commit + push
- **Git Notes**：查看/新增 commit 備註
- **Git Diff**：查看未提交變更

#### 文件管理區
- 系統文件列表
- 查看 / 下載功能

#### 使用者管理（僅 superadmin 可操作）
- 建立新使用者
- 修改角色
- 重設密碼

**AJAX 呼叫**：`/api/superadmin/*` 系列端點

---

### 13.17 密碼重設 (`/reset-password`)

**功能特色**：
使用者忘記密碼時的自助重設流程。

---

## 附錄 A：設定檔範本

### config.py

```python
import secrets

INSPECTION_HOME = "/seclog/AI/inspection"

MONGO_CONFIG = {
    "host": "localhost",
    "port": 27017,
    "db": "inspection"
}

LDAP_CONFIG = {
    "server": "ldap://your-ad-server",
    "base_dn": "DC=company,DC=com",
    "bind_dn": "CN=svc_ldap,OU=Service,DC=company,DC=com",
    "bind_password": "ENV:LDAP_PASSWORD",
    "mock_mode": True  # 設為 False 後連接真實 AD
}

FLASK_HOST = "0.0.0.0"
FLASK_PORT = 5000
FLASK_DEBUG = False
SECRET_KEY = secrets.token_hex(32)

BACKUP_DIR = "/seclog/backup"
```

### settings.json

```json
{
  "thresholds": {
    "disk_warn": 85,
    "disk_crit": 95,
    "cpu_warn": 80,
    "cpu_crit": 95,
    "mem_warn": 80,
    "mem_crit": 95
  },
  "disk_exclude_mounts": ["/dev", "/run", "/sys", "/proc", "/tmp"],
  "disk_exclude_prefixes": ["/run/", "/dev/", "/sys/", "/proc/", "/var/lib/containers/"],
  "cpu_sample_minutes": 10,
  "error_log_max_entries": 50,
  "error_log_hours": 24,
  "service_check_list": ["sshd", "crond"],
  "notify_email": {
    "enabled": true,
    "smtp_host": "smtp.gmail.com",
    "smtp_port": 587,
    "smtp_user": "your-email@gmail.com",
    "smtp_pass": "ENV:SMTP_PASSWORD",
    "recipients": ["admin@company.com"]
  }
}
```

---

## 附錄 B：Blueprint 註冊順序

```python
# app.py 中的 Blueprint 註冊
app.register_blueprint(api_hosts_bp)           # /api/hosts
app.register_blueprint(api_inspections_bp)     # /api/inspections
app.register_blueprint(api_rules_bp)           # /api/rules
app.register_blueprint(api_settings_bp)        # /api/settings
app.register_blueprint(api_ldap_bp)            # /api/ldap
app.register_blueprint(api_admin_bp)           # /api/admin
app.register_blueprint(api_audit_bp)           # /api/audit
app.register_blueprint(api_twgcb_bp)           # /api/twgcb
app.register_blueprint(api_harden_bp)          # /api/harden
app.register_blueprint(api_superadmin_bp)      # /api/superadmin
app.register_blueprint(api_security_audit_bp)  # /api/security-audit
app.register_blueprint(api_linux_init_bp)      # /api/linux-init
```

---

## 附錄 C：備份的組態檔案清單（TWGCB 強化用）

強化前自動備份的 17 個檔案 + 3 個目錄：

**檔案**：
1. `/etc/ssh/sshd_config`
2. `/etc/login.defs`
3. `/etc/security/pwquality.conf`
4. `/etc/pam.d/system-auth`（RHEL）
5. `/etc/pam.d/password-auth`（RHEL）
6. `/etc/pam.d/common-auth`（Debian）
7. `/etc/pam.d/common-password`（Debian）
8. `/etc/passwd`
9. `/etc/shadow`
10. `/etc/group`
11. `/etc/sysctl.conf`
12. `/etc/audit/auditd.conf`
13. `/etc/audit/audit.rules`
14. `/etc/sudoers`
15. `/etc/motd`
16. `/etc/issue`
17. `/etc/issue.net`

**目錄**：
1. `/etc/sysctl.d/`
2. `/etc/security/limits.d/`
3. `/etc/audit/rules.d/`

---

## 附錄 D：TWGCB 合規檢查分類

| 分類 | 代碼 | 檢查項目範例 |
|------|------|-------------|
| 密碼政策 | PWD | 最小長度、複雜度、歷史記錄、到期天數 |
| 帳號管理 | ACCT | 鎖定閾值、鎖定時間、root 限制 |
| SSH 安全 | SSH | Protocol 版本、PermitRootLogin、MaxAuthTries |
| SELinux | SEL | SELinux 模式（Enforcing）|
| 防火牆 | FW | firewalld 啟用、預設 zone |
| 稽核日誌 | AUD | auditd 啟用、保留設定 |
| 檔案權限 | FILE | /etc/shadow 權限、SUID/SGID |
| 網路安全 | NET | IP 轉發關閉、SYN Cookie 啟用 |

---

## 附錄 E：關鍵服務檔案路徑

| 服務 | 路徑 |
|------|------|
| Flask (systemd) | `/etc/systemd/system/itagent-web.service` |
| MongoDB (Podman) | `podman ps --filter name=mongodb` |
| Cron 排程 | `/var/spool/cron/root` |
| Ansible Vault | `/seclog/AI/inspection/.vault_pass` |
| Ansible Inventory | `/seclog/AI/inspection/ansible/inventory/hosts.yml` |
| 巡檢日誌 | `/seclog/AI/inspection/logs/` |
| 巡檢報告 | `/seclog/AI/inspection/data/reports/` |
| 系統設定 | `/seclog/AI/inspection/data/settings.json` |
| 版本資訊 | `/seclog/AI/inspection/data/version.json` |

---

> **文件結束**
> 本手冊涵蓋巡檢系統的全部功能，共計：
> - **17 個前端頁面**
> - **80+ 個 API 端點**
> - **12 個 Ansible 角色**
> - **11 個 MongoDB Collections**
> - **3 種使用者角色**
> - **6 個 Shell 腳本**
> - **完整 CSS 設計系統**
>
> AI 開發者應逐項實作上述所有功能，確保與原系統功能完全一致。
> 新系統連接 MongoDB `inspection` 資料庫即可直接使用現有資料。
