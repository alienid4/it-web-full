# 巡檢系統重建 — Copilot 開發提示詞

> 把這份文件貼給 Copilot 作為第一輪指令。
> 搭配同目錄下的 `FULL_SYSTEM_SPEC.md`（完整規格）和 `DB_SCHEMA.json`（資料庫結構）。

---

## 你的角色

你是一位全端工程師，負責從零重建一套「金融業 IT 每日自動巡檢系統」。
這套系統已有運行中的 MongoDB 資料庫（database: `inspection`），你的程式碼必須**直接連接並使用現有資料**，不需要建新的資料表。

---

## 專案目標

完整複製原系統的所有功能，包含：
- 17 個前端頁面
- 80+ 個 REST API 端點
- 12 個 Flask Blueprint
- 使用者認證與角色權限（superadmin / admin / oper）
- 所有圖表、表格、KPI 卡片、Modal 對話框
- 完整的管理後台（12 個 Tab）
- TWGCB 合規管理 4 頁
- 安全稽核與 Linux 初始化遠端工具

---

## 技術要求

### 後端
- **語言**：Python 3.9+
- **框架**：Flask 3.x
- **資料庫驅動**：PyMongo 4.x
- **資料庫**：MongoDB（連線至 `localhost:27017`，database: `inspection`）
- **認證**：Session-based（Flask Session + bcrypt 密碼雜湊）
- **WSGI**：Gunicorn（生產環境）

### 前端
- **模板引擎**：Jinja2（Flask 內建）
- **JavaScript**：原生 Vanilla JS（不使用框架）
- **圖表**：Chart.js v4
- **字型**：Noto Sans TC + JetBrains Mono（Google Fonts）
- **CSS**：自訂 `example.css` 設計系統（不用 Tailwind/Bootstrap）

### 不需要的
- 不需要建立 Ansible playbook（那是獨立元件）
- 不需要建立 Shell 腳本
- 不需要建立 MongoDB 或容器
- 不需要寫測試

---

## 開發順序建議

請按以下順序逐步開發，每完成一個階段確認可運行後再繼續：

### Phase 1：專案骨架 + 認證系統
1. 建立專案目錄結構（參考規格書「目錄結構」章節）
2. 建立 `config.py`（MongoDB 連線、SECRET_KEY、路徑設定）
3. 建立 `app.py`（Flask 主應用，註冊所有 Blueprint，安全標頭中介層）
4. 建立 `services/auth_service.py`（密碼雜湊、預設管理員建立）
5. 建立 `decorators.py`（@login_required, @admin_required, @superadmin_required）
6. 建立 `routes/api_admin.py` 的認證端點（login / logout / me / change-password）
7. 建立 `templates/base.html`（導覽列框架）
8. 建立 `templates/login.html`（登入頁）
9. 建立 `static/css/example.css`（完整設計系統）
10. 確認可以登入、Session 運作正常

### Phase 2：Dashboard + 核心資料 API
1. 建立 `services/mongo_service.py`（MongoDB CRUD 操作）
2. 建立 `routes/api_hosts.py`（主機清單 API）
3. 建立 `routes/api_inspections.py`（巡檢結果 API）
4. 建立 `routes/api_settings.py`（設定 API）
5. 建立 `templates/dashboard.html`（KPI 卡片 + 圖表 + 主機表格）
6. 建立 `static/js/dashboard.js`（圖表渲染、KPI 篩選、UID=0 警示）
7. 確認 Dashboard 可正常顯示 MongoDB 中的資料

### Phase 3：報告與查詢頁面
1. 建立 `templates/report.html`（今日報告卡片頁）
2. 建立 `templates/host_detail.html`（主機詳情深度報告）
3. 建立 `templates/history.html`（歷史趨勢查詢）
4. 建立 `templates/summary.html`（異常總結 + 修復建議）
5. 確認所有報告頁可正常顯示

### Phase 4：管理功能
1. 建立 `templates/hosts.html`（主機管理 + 群組設定）
2. 建立 `routes/api_rules.py`（過濾規則 CRUD）
3. 建立 `templates/filter_rules.html`（過濾規則管理）
4. 建立 `routes/api_audit.py`（帳號稽核 API）
5. 建立 `templates/audit.html`（帳號稽核頁）

### Phase 5：管理後台
1. 建立 `templates/admin.html`（12 個 Tab 管理後台）
2. 建立 `static/js/admin.js`（Tab 導航 + 所有管理功能）
3. 完成所有 `/api/admin/*` 端點：
   - 系統狀態、系統資訊
   - 備份管理（建立/還原/刪除）
   - 任務管理（seed/status）
   - 日誌查看（巡檢日誌/Flask 日誌）
   - 告警管理（列表/確認）
   - 主機 CRUD（新增/編輯/刪除/Ping/CSV 匯入匯出）
   - 排程管理
   - 月報（SLA 統計 + CSV/JSON 匯出）
   - 操作日誌（worklog）

### Phase 6：TWGCB 合規模組
1. 建立 `routes/api_twgcb.py`（合規 API）
2. 建立 `routes/api_harden.py`（強化 API）
3. 建立 `templates/twgcb.html`（合規矩陣）
4. 建立 `templates/twgcb_detail.html`（主機合規詳情）
5. 建立 `templates/twgcb_harden.html`（一鍵修復 + 備份回滾）
6. 建立 `templates/twgcb_report.html`（合規報告）
7. 建立 `templates/twgcb_settings.html`（合規設定）

### Phase 7：進階工具
1. 建立 `routes/api_security_audit.py`（安全稽核 API + 非同步任務 + 即時進度）
2. 建立 `routes/api_linux_init.py`（Linux 初始化 API + 回滾）
3. 建立 `routes/api_superadmin.py`（Git 管理 + 文件管理）
4. 建立 `templates/superadmin.html`（超級管理員頁面）
5. 建立 `routes/api_ldap.py`（LDAP 查詢，Mock 模式）

### Phase 8：收尾
1. 密碼重設頁面
2. RWD 響應式調整（手機/平板）
3. 版本號顯示（從 `/api/settings/version` 讀取）
4. 所有安全標頭確認（X-Frame-Options, CSP 等）
5. Session 8 小時逾時
6. 登入失敗鎖定（5次→15分鐘）

---

## 重要開發規則

### 1. MongoDB 連線
```python
from pymongo import MongoClient
client = MongoClient("localhost", 27017)
db = client["inspection"]

# 可直接使用的 Collections：
# db.hosts, db.inspections, db.filter_rules, db.settings,
# db.users, db.admin_worklog, db.alert_acks,
# db.twgcb_results, db.twgcb_backups,
# db.hr_users, db.account_notes
```

### 2. 設定雙寫入
更新 settings 時，必須同時寫入 MongoDB 和 `data/settings.json` 檔案：
```python
# 寫入 MongoDB
db.settings.update_one({"key": key}, {"$set": {"value": value}}, upsert=True)
# 同時寫入 JSON 檔
with open(settings_path, 'w') as f:
    json.dump(all_settings, f, indent=2, ensure_ascii=False)
```

### 3. 狀態判定邏輯
```python
def calc_overall_status(inspection):
    statuses = [
        inspection.get("disk", {}).get("status", "ok"),
        inspection.get("cpu", {}).get("status", "ok"),
        inspection.get("service", {}).get("status", "ok"),
        inspection.get("account", {}).get("status", "ok"),
        inspection.get("error_log", {}).get("status", "ok"),
        inspection.get("system", {}).get("status", "ok"),
    ]
    if "error" in statuses:
        return "error"
    if "warn" in statuses:
        return "warn"
    return "ok"
```

### 4. CSS 色彩規則
- OK = `#4AB234`（綠）
- WARN = `#E87C07`（橘）
- ERROR = `#E00B00`（紅）
- 磁碟 < 85% = 綠，85-95% = 橘，> 95% = 紅
- CPU/記憶體 < 80% = 綠，80-95% = 橘，> 95% = 紅

### 5. UID=0 警示
如果 `inspection.account.uid0_alert === true`，必須顯示紅色閃爍動畫：
```css
@keyframes uid0-flash {
  0%, 100% { background: #FFEBEE; }
  50% { background: #E00B00; color: white; }
}
.uid0-alert { animation: uid0-flash 1s infinite; }
```

### 6. API 回傳格式
成功：
```json
{"success": true, "data": {...}}
```
失敗：
```json
{"success": false, "error": "錯誤訊息"}
```
未登入：
```json
// HTTP 401
{"success": false, "error": "未登入"}
```

### 7. 安全標頭（在 @app.after_request 中設定）
```python
@app.after_request
def add_security_headers(response):
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    response.headers['Permissions-Policy'] = 'geolocation=(), microphone=(), camera=()'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Content-Security-Policy'] = (
        "default-src 'self'; "
        "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.jsdelivr.net; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
        "font-src 'self' https://fonts.gstatic.com; "
        "img-src 'self' data:; "
    )
    del response.headers['Server']
    return response
```

### 8. 使用者活動追蹤
```python
@app.before_request
def track_user_activity():
    if "user_id" in session:
        db.users.update_one(
            {"username": session["user_id"]},
            {"$set": {
                "last_seen": datetime.utcnow().isoformat(),
                "last_ip": request.remote_addr
            }}
        )
```

### 9. 線上使用者判定
```python
# 30 分鐘內有活動 = 線上
threshold = datetime.utcnow() - timedelta(minutes=30)
online = db.users.find({"last_seen": {"$gte": threshold.isoformat()}})
```

---

## 目錄結構（請照此建立）

```
webapp/
├── app.py                          # Flask 主應用（12 Blueprint 註冊 + 安全標頭 + Session 設定）
├── config.py                       # 組態（MongoDB/LDAP/路徑/SECRET_KEY）
├── decorators.py                   # @login_required, @admin_required, @superadmin_required
├── requirements.txt                # flask, pymongo, gunicorn, python-ldap
│
├── routes/
│   ├── __init__.py
│   ├── api_hosts.py                # /api/hosts（主機 CRUD + 篩選 + 群組）
│   ├── api_inspections.py          # /api/inspections（latest/history/trend/summary/abnormal）
│   ├── api_rules.py                # /api/rules（過濾規則 CRUD + toggle）
│   ├── api_settings.py             # /api/settings（設定讀寫 + 版本）
│   ├── api_ldap.py                 # /api/ldap（LDAP 查詢 Mock）
│   ├── api_admin.py                # /api/admin（認證 + 系統狀態 + 備份 + 主機管理 + 排程 + 報表 + 日誌 + 告警）
│   ├── api_audit.py                # /api/audit（帳號稽核 + CSV 匯出）
│   ├── api_twgcb.py                # /api/twgcb（合規掃描 + 匯入 + 結果 + 摘要）
│   ├── api_harden.py               # /api/harden（備份 + 修復 + 回滾）
│   ├── api_superadmin.py           # /api/superadmin（Git 管理 + 文件 + 使用者管理）
│   ├── api_security_audit.py       # /api/security-audit（安全稽核 + 非同步進度 + 報告下載）
│   └── api_linux_init.py           # /api/linux-init（Linux 初始化 + 進度 + 回滾）
│
├── services/
│   ├── __init__.py
│   ├── mongo_service.py            # MongoDB CRUD 封裝（hosts/inspections/rules/settings）
│   ├── auth_service.py             # 密碼雜湊 + 預設管理員建立 + 登入鎖定
│   ├── ldap_service.py             # LDAP 查詢（Mock 模式）
│   ├── report_service.py           # 趨勢彙總 + 異常摘要產生
│   └── email_service.py            # SMTP 通知發送
│
├── models/
│   ├── __init__.py
│   ├── host.py                     # HOST_SCHEMA + validate_host()
│   ├── inspection.py               # INSPECTION_SCHEMA + calc_overall_status()
│   └── filter_rule.py              # FILTER_RULE_SCHEMA + validate_rule()
│
├── templates/
│   ├── base.html                   # 導覽列 + Chart.js + example.css + 版本號
│   ├── login.html                  # 登入表單
│   ├── dashboard.html              # KPI + 圖表 + 主機表格
│   ├── report.html                 # 今日報告卡片（OS 分頁）
│   ├── host_detail.html            # 主機深度報告（10 個資訊區塊）
│   ├── history.html                # 歷史趨勢（主機選擇 + 天數 + 折線圖 + 表格）
│   ├── hosts.html                  # 主機管理（篩選 + 表格 + 群組 Modal）
│   ├── summary.html                # 異常總結（KPI + 問題列表 + 建議 + 匯出）
│   ├── filter_rules.html           # 過濾規則（規則列表 + 新增/編輯 Modal）
│   ├── audit.html                  # 帳號稽核
│   ├── twgcb.html                  # TWGCB 合規矩陣（OS 分頁 + 統計）
│   ├── twgcb_detail.html           # 單一主機合規詳情
│   ├── twgcb_harden.html           # 強化操作（勾選 + 備份 + 修復 + 回滾）
│   ├── twgcb_report.html           # 合規報告（含簽核欄）
│   ├── twgcb_settings.html         # 合規設定
│   ├── admin.html                  # 管理後台（12 Tab）
│   ├── superadmin.html             # 超級管理員（Git + 文件 + 使用者）
│   └── reset_password.html         # 密碼重設
│
├── static/
│   ├── css/
│   │   └── example.css              # 完整設計系統（色彩/字型/元件/RWD）
│   ├── js/
│   │   ├── dashboard.js            # Dashboard 圖表 + KPI 篩選
│   │   └── admin.js                # Admin 12 Tab 邏輯
│   └── img/
│       └── example_logo.svg         # Example Logo
│
└── data/
    ├── settings.json               # 系統設定（與 MongoDB settings 同步）
    └── version.json                # 版本資訊
```

---

## 完整規格書

所有功能細節請參閱同目錄下的 **`FULL_SYSTEM_SPEC.md`**，該文件包含：

- 每個 API 端點的方法/路徑/參數/回傳值
- 每個 MongoDB Collection 的欄位定義
- 每個頁面的 UI 元素與互動行為
- CSS 設計系統的所有變數與元件 class
- 安全機制清單
- 設定檔範本

**請逐章閱讀規格書，確保每一項功能都有實作。**

---

## 驗收標準

開發完成後，系統必須滿足以下條件：

1. 連接 MongoDB `inspection` 資料庫後，Dashboard 可正常顯示 KPI 和圖表
2. 所有 17 個頁面可正常渲染
3. 登入/登出/改密碼功能正常
4. 角色權限控制正確（oper 無法存取 admin 功能）
5. 管理後台 12 個 Tab 全部可操作
6. TWGCB 合規頁面可顯示合規率和檢查項目
7. CSV 匯入/匯出功能正常
8. 備份/還原功能正常
9. 所有安全標頭正確設定
10. RWD 支援手機/平板/桌面

---

## 啟動方式

開發完成後，執行以下指令啟動：

```bash
# 安裝依賴
pip install -r requirements.txt

# 開發模式
python app.py

# 生產模式
gunicorn --workers=4 --bind=0.0.0.0:5000 app:app
```

瀏覽器開啟 `http://localhost:5000` → 登入頁。
預設管理員帳號由 `ensure_default_admin()` 自動建立。
