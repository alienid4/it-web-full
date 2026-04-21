# Developer Guide — IT Inspection System

接手這個 repo 的工程師看這份就能上手。想部署的人請看 [`README.md`](./README.md)。

---

## 1. 30 秒總覽

- **技術棧**：Python 3.9 + Flask（Web）+ PyMongo + Ansible 2.14 + MongoDB 6
- **目的**：RHEL/Linux/Windows/AS400/SNMP 裝置每日自動巡檢，離線部署為主
- **版本管理**：`AI/data/version.json`（每次 commit 必更）；CHANGELOG 從中產出
- **目前版本**：v3.11.2.0
- **部署目標**：RHEL 9 / Rocky Linux 9
- **存放位置**：`alienid4/it-web-full` (private GitHub)
- **離線依賴**：`v3.11.2.0` Release 的 `inspection_offline_deps_v3.11.2.0.tar.gz`（201MB）

---

## 2. Repo 結構

```
it-web-full/
├── AI/                         ★ 巡檢系統程式碼（部署時整個搬到 /opt/inspection）
│   ├── ansible/
│   │   ├── inventory/          主機清單（實際運作時從 MongoDB 動態產）
│   │   ├── playbooks/          site.yml / linux_init / security_audit / twgcb_scan / ...
│   │   └── roles/              check_cpu / check_disk / check_network / check_windows ...
│   ├── webapp/                 Flask 應用（詳下節）
│   ├── scripts/                管理/工具腳本（bootstrap / patch_apply / cio_monthly_report ...）
│   ├── systemd/                itagent-web.service
│   ├── data/                   範本 (hr_template / hosts_config.template) + 文件
│   ├── offline_bundle/         離線安裝文件 (OFFLINE_DEPS / RUNBOOK / WHEEL_URLS)
│   ├── install.sh              老版離線安裝（已被 root 的 setup_testenv.sh 取代）
│   ├── itagent.sh              服務管理工具 (start/stop/status/log/menu)
│   └── run_inspection.sh       巡檢入口腳本
├── setup_testenv.sh            ★ 一鍵離線安裝（用這個）
├── verify_stack.py             架構驗證工具
├── README.md                   使用者部署手冊
├── DEVELOPER.md                （本檔）
├── CHANGELOG.md                版本歷程
├── ENVIRONMENT_GUIDE.md        路徑/權限清單
├── FULL_SYSTEM_SPEC.md         系統規格（歷史文件，v3.4.2 時代，擇部參考）
├── DB_SCHEMA.json              MongoDB schema
└── version.json                專案版本（不是 AI/data/version.json）
```

---

## 3. webapp 架構（`AI/webapp/`）

```
webapp/
├── app.py                  Flask 入口（blueprints 註冊、CSRF、session、template filters）
├── config.py               (由 setup_testenv.sh 產生，不入 git)
├── config.py.example       (範本，入 git)
├── decorators.py           @login_required / @admin_required
├── seed_data.py            初始資料
├── models/
│   ├── host.py             主機模型
│   ├── inspection.py       巡檢結果
│   └── filter_rule.py      誤報過濾規則
├── services/
│   ├── mongo_service.py    MongoDB client 單例
│   ├── auth_service.py     登入/密碼雜湊
│   ├── ldap_service.py     LDAP 整合
│   ├── email_service.py    告警郵件
│   ├── report_service.py   報告產生
│   ├── cio_service.py      CIO 儀表板資料彙整
│   ├── cio_chart.py        matplotlib 趨勢圖
│   ├── cio_pdf.py          reportlab 月報 PDF
│   ├── nmon_service.py     nmon 效能資料解析
│   ├── nmon_charts.py      nmon 圖表
│   ├── packages_service.py 軟體盤點
│   └── feature_flags.py    Feature flags
├── routes/ (16 個 blueprint)
│   ├── api_admin             Admin UI API
│   ├── api_superadmin        Super admin（feature toggle / backup / scheduler）
│   ├── api_hosts             主機 CRUD
│   ├── api_inspections       巡檢結果
│   ├── api_rules             filter rules
│   ├── api_settings          系統設定
│   ├── api_audit             帳號盤點
│   ├── api_security_audit    資安稽核
│   ├── api_twgcb             TWGCB 掃描與強化
│   ├── api_harden            主機強化
│   ├── api_linux_init        Linux 初始化
│   ├── api_ldap              LDAP 整合
│   ├── api_cio               CIO 儀表板
│   ├── api_nmon              效能監控
│   └── api_packages          軟體盤點
├── templates/ (20 個 Jinja2)
│   ├── base.html             全站 layout
│   ├── login / reset_password
│   ├── dashboard / summary   首頁 + 異常總結
│   ├── hosts / host_detail   主機清單與詳細
│   ├── report / history      報告與歷史
│   ├── audit / filter_rules  帳號盤點 / 過濾規則
│   ├── admin / superadmin    Admin UI
│   ├── twgcb_*               TWGCB 系列（掃描/詳細/強化/報告/設定）
│   ├── executive             CIO 儀表板（主管用）
│   ├── packages / perf       軟體盤點 / 效能
│   └── feature_disabled      feature flag 擋下的頁面
└── static/
    ├── css/ (admin.css, example.css)
    └── js/ (admin.js, dashboard.js, icons.js)
```

---

## 4. 本機開發流程

### 4.1 起本機環境（macOS/Linux，快速測試）

```bash
# Clone
git clone https://github.com/alienid4/it-web-full.git
cd it-web-full/AI

# venv
python3 -m venv .venv
source .venv/bin/activate

# 裝依賴（線上，沒離線限制時）
pip install flask pymongo bcrypt gunicorn jinja2 werkzeug \
    pywinrm requests xmltodict requests-ntlm pyspnego cryptography \
    dnspython matplotlib numpy reportlab openpyxl python-ldap

# 起 MongoDB（本機 podman 或 docker）
podman run -d --name mongodb -p 27017:27017 mongo:6

# 從 example 建 config
cp webapp/config.py.example webapp/config.py
# 編輯 config.py：SECRET_KEY / MongoDB / INSPECTION_HOME 指到本機路徑

# 跑 Flask
cd webapp && python app.py
# 開 http://localhost:5000/
```

### 4.2 Debug 模式

修改 `AI/webapp/config.py`：
```python
FLASK_DEBUG = True
```
或用 `.env`：
```
FLASK_DEBUG=True
```

### 4.3 跑 Ansible 本機測試

```bash
cd AI/ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check
```

---

## 5. 開發規範

### 5.1 版本號（**每次 commit 必更**）

- 格式：`X.Y.Z.W`
  - X：架構大改（極少）
  - Y：新 feature / 頁面
  - Z：小 feature / 重構
  - W：bug fix / UI 調整
- 規則：
  - `AI/data/version.json` 的 `version` 欄位 bump
  - `changelog` 陣列加一行：`"X.Y.Z.W - YYYY-MM-DD: 說明"`
  - 根目錄 `version.json` 的 `version` 也要同步

### 5.2 敏感字檢查（commit 前必跑）

```bash
grep -rE "國泰|cathay|secansible|secclient|192\.168\.1\.(19|100|110|221|222)|/seclog|alien4job" \
    AI/ setup_testenv.sh verify_stack.py *.md
# 必須 0 命中才能 commit
```

Sanitize 對照表在 [`memory/project_testenv_deployment.md`](https://github.com/alienid4/it-web-full/)（私人 memory）。

### 5.3 Commit 訊息格式

- `feat: XXX` — 新功能
- `fix: XXX` — bug 修正
- `refactor: XXX` — 重構
- `docs: XXX` — 文件
- `chore: XXX` — 雜項
- 底部加：
  ```
  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```

### 5.4 Python Style

- PEP 8
- 檔頭 docstring 一句話描述用途
- import 順序：stdlib → 3rd-party → local
- 避免 `from X import *`

---

## 6. 發佈新版流程

### 6.1 小版本（只改程式碼）

```bash
# 1. 改 version.json + CHANGELOG
vi AI/data/version.json version.json
# 2. commit + push
git add -A
git commit -m "feat: xxx"
git push
# 3. 測試機 git pull 即可
```

### 6.2 大版本（需要更新離線依賴）

若新增了 pip 套件或 RPM：

```bash
# 1. 打包新 deps tarball
cd <repo_root>
# 用 pip download 收集新 whl，加到 tarball
tar czf inspection_offline_deps_vX.Y.Z.W.tar.gz -C AI rpms whls

# 2. 刪 AI/rpms/、AI/whls/ 本地副本（不進 git）

# 3. 更新 setup_testenv.sh 的 DEPS_URL 版本號

# 4. commit + push

# 5. 上 GitHub 建 Release：
#    - Tag: vX.Y.Z.W
#    - Upload tarball as asset
```

---

## 7. 常用工具

### 7.1 `itagent` 指令（部署後可用）

```bash
itagent status      # 服務狀態
itagent start/stop/restart
itagent log         # Flask 日誌
itagent menu        # 互動選單
```

### 7.2 `verify_stack.py`

- 驗證 Python 套件 + MongoDB + Ansible 是否就緒
- 加 `--serve` 啟最小 Flask（含 `/health` 端點）

### 7.3 `setup_testenv.sh`

- 一鍵安裝（詳 [README.md](./README.md)）

---

## 8. MongoDB Schema（重要 collections）

| Collection | 主鍵 | 用途 |
|---|---|---|
| `users` | username | 系統帳號（superadmin/admin/oper） |
| `hosts` | hostname | 受控主機清單 |
| `inspections` | (hostname, run_date) | 每日巡檢結果 |
| `audit_accounts` | (hostname, username) | 帳號盤點結果 |
| `filter_rules` | id | 誤報過濾規則 |
| `settings` | key | 全站設定（閾值、排程等） |
| `feature_flags` | name | 模組開關 |
| `twgcb_scans` | scan_id | TWGCB 掃描結果 |
| `twgcb_daily_stats` | date | TWGCB 日趨勢 |
| `security_audit` | audit_id | 資安稽核結果 |
| `nmon_timeseries` | (hostname, timestamp) | 效能時序資料 |
| `packages` | (hostname, package) | 軟體盤點 |
| `patch_queue` | patch_id | 修補佇列 |
| `action_logs` | _id | 操作稽核 |

詳見 [DB_SCHEMA.json](./DB_SCHEMA.json)（注：該檔為 v3.4.2 時代產物，部分 collection 未列）。

---

## 9. Feature Flags

`feature_flags` collection 控制模組啟停。前端 `base.html` 注入 `window.FEATURES`，JS 隱藏關閉的 tab 與 panel。

目前 6 個 flag：
- `audit` — 帳號盤點
- `security_audit` — 資安稽核
- `twgcb` — TWGCB 掃描
- `twgcb_reports` — TWGCB 報告
- `perf` — 效能監控
- `packages` — 軟體盤點

改用 Superadmin UI → 模組管理。

---

## 10. 相關文件

| 文件 | 用途 |
|---|---|
| [README.md](./README.md) | 部署指南（雙流程） |
| [CHANGELOG.md](./CHANGELOG.md) | 版本歷程 |
| [ENVIRONMENT_GUIDE.md](./ENVIRONMENT_GUIDE.md) | 路徑/權限/環境變數 |
| [FULL_SYSTEM_SPEC.md](./FULL_SYSTEM_SPEC.md) | 系統規格（舊版 v3.4.2 時代，擇部參考） |
| [DB_SCHEMA.json](./DB_SCHEMA.json) | MongoDB schema |
| [AI/data/RUNBOOK.md](./AI/data/RUNBOOK.md) | 常見問題排錯 |
| [AI/data/ITAGENT_MANUAL.md](./AI/data/ITAGENT_MANUAL.md) | 運維手冊 |
| [AI/data/INSTALL_GUIDE.md](./AI/data/INSTALL_GUIDE.md) | 手動安裝（舊版，現用 setup_testenv.sh） |
| [AI/data/OFFLINE_DEPS.md](./AI/data/OFFLINE_DEPS.md) | 離線依賴清單 |
| [AI/data/WHEEL_URLS.md](./AI/data/WHEEL_URLS.md) | Python 套件 PyPI 直鏈 |
| [AI/offline_bundle/RUNBOOK.md](./AI/offline_bundle/RUNBOOK.md) | 離線安裝運維（補充版） |

---

## 11. Known Issues & TODOs

- [ ] `AI/.gitignore` 舊版有 `config.py` → 改用 `config.py.example` 模式（已修復，commit `e53316a`）
- [ ] `FULL_SYSTEM_SPEC.md` 停在 v3.4.2 時代，未涵蓋 Windows SSH / SNMP / AS400 / 帳號盤點 / patch / nmon / CIO / TWGCB 新功能（按需更新）
- [ ] `DB_SCHEMA.json` 只到 v3.4.2 的 collection，v3.11.2 新增的 10+ collection 未列
- [ ] pysnmp 的傳遞依賴（async-timeout / anyio / sniffio）尚未 100% 覆蓋
- [ ] 尚未做 CI/CD；手動 git push + 手動建 Release

歡迎有緣的下一位接手人補。
