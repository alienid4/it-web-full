# 從零重建 IT 監控系統 SKILL

> **給 AI 的自給自足重建指南**。餵給 Claude/其他 AI + 一台空 Linux（建議 Rocky 9 / RHEL 9）+ 網路，能重建功能等價的系統。
>
> 最後更新: **v3.10.1.1 (2026-04-20)**

---

## 一、給 AI 的起手句（複製貼上）

```
你是資深 Linux/Python 工程師，接手「Example Corp IT 巡檢系統」的**從零重建**任務。
目標：重建一套能對 Linux / Windows / AIX / AS400 做每日巡檢 + TWGCB 合規檢查
+ 一鍵修復 + 備份還原 + 合規報告的 Web 系統。

請先讀這份 SKILL 整份，然後按「十、建置順序」一步步做。每步驟做完回報，我會檢查
後再給下一步。不要一次做完；不要跳步。所有 commit 訊息用繁體中文。每次變更都要
更新 version.json 和 SPEC_CHANGELOG_20260410.md。
```

---

## 二、系統概觀（一段話版本）

一台 `ansible-host` 控制機（Rocky 9）負責：
1. 跑 **Flask + Gunicorn** 提供 Web UI（port 5000，Cloudflare Tunnel 對外）
2. 跑 **Podman 容器化的 MongoDB 6**（port 27017，只 bind 127.0.0.1）
3. 用 **Ansible** 管理所有受監控主機（Linux 走 ssh + ansible_svc 帳號 + become；Windows 走 ssh + PowerShell EncodedCommand）
4. 每日 cron 或使用者點擊觸發：巡檢 / TWGCB 合規掃描 / 修復 / 還原

Web UI 提供 Dashboard、今日報告、歷史查詢、帳號盤點、TWGCB 合規、系統管理（Admin）、開發後台（Superadmin）。

---

## 三、技術堆疊

| 層 | 技術 | 為什麼這選 |
|----|------|-----------|
| OS | Rocky Linux 9（控制機） | 跟目標客群（金融業）常用一致 |
| 容器 | Podman（systemd 管理） | RHEL 系預設，輕量 |
| DB | MongoDB 6 | 結構彈性，inspection 結果每台主機欄位不同 |
| Web | Flask 3 + Gunicorn 22 | Gunicorn 4 worker 支撐 500~2000 台規模 |
| Ansible | ansible-core（community.general） | 受監控主機零 agent |
| Python | 3.9+ | RHEL 9 預設 |
| 前端 | 原生 JS（無 framework） | 避免打包流程；適合傳統金融環境 |
| 對外 | Cloudflare Tunnel | 不用開公網 IP，用者打 it.example.com |

---

## 四、目錄結構（關鍵）

```
/opt/inspection/              # 專案根
├── ansible/
│   ├── inventory/hosts.yml         # generate_inventory.py 從 data/hosts_config.json 產生
│   ├── playbooks/
│   │   ├── run_inspection.yml      # 每日巡檢（disk/cpu/service/account 等）
│   │   ├── twgcb_scan.yml          # TWGCB 合規掃描
│   │   └── run_harden.yml          # 單台強化用
│   ├── roles/
│   │   ├── check_twgcb/tasks/main.yml      # ← 60+ 項 Linux TWGCB 檢查（核心）
│   │   ├── check_twgcb_win/tasks/main.yml  # Windows 版
│   │   ├── check_disk/、check_cpu/ ...     # 每日巡檢各項目
│   └── .vault_pass                 # Ansible Vault 密碼檔（權限 600）
├── data/
│   ├── hosts_config.json           # 主機清單（含保管者/系統別/AP 負責人）
│   ├── reports/                    # 巡檢/TWGCB 掃描結果 JSON
│   ├── security_audit_reports/     # 系統安全稽核報告 txt
│   ├── SPEC_CHANGELOG_20260410.md  # 所有變更需求（每次改都要追加）
│   ├── version.json                # 版本 + changelog
│   └── (此 SKILL 與其他 9 份文件)
├── webapp/
│   ├── app.py                      # Flask 入口（Gunicorn 用 app:app）
│   ├── routes/
│   │   ├── api_twgcb.py            # /api/twgcb/* （scan/results/stats/exceptions...）
│   │   ├── api_admin.py            # /api/admin/* （fix/fix-all/restore/ping-all...）
│   │   ├── api_superadmin.py       # /api/superadmin/* （git push/download-package/docs...）
│   │   ├── api_audit.py            # 帳號盤點
│   │   ├── api_security_audit.py   # 系統安全稽核
│   │   ├── api_linux_init.py       # Linux 初始化工具
│   │   └── api_harden.py           # TWGCB 強化管理
│   ├── services/
│   │   ├── mongo_service.py        # get_collection / get_db / TTL indexes
│   │   └── auth_service.py         # bcrypt 密碼 + login_attempts 鎖定
│   ├── templates/                  # 17 個 .html（base/dashboard/twgcb/admin/...）
│   └── static/                     # example.css + js/*
├── systemd/
│   ├── itagent-db.service          # MongoDB container
│   └── itagent-web.service         # Gunicorn（舊版跑 python3 app.py）
├── scripts/
│   ├── patch_gen.sh / patch_apply.sh    # Patch 系統
│   ├── security_audit.sh / sysexpert.sh # 稽核 / 初始化
│   └── rollback_to_flask_dev.sh         # Gunicorn 出問題的緊急 rollback
└── itagent.sh                      # 控制台：start/stop/restart/status/log
```

---

## 五、MongoDB Schema

| Collection | 用途 | 關鍵欄位 |
|-----------|------|---------|
| `users` | 登入帳號 | username, password_hash (bcrypt), role (superadmin/admin/oper) |
| `hosts` | 主機中繼資料 | hostname, ip, os, os_group, custodian, ap_owner, system_name, tier |
| `inspections` | 每日巡檢結果 | hostname, timestamp, results.{disk,cpu,service,account,...} |
| `twgcb_results` | TWGCB 最新掃描 | hostname, scan_time, checks[{id,name,status,actual,remediation,level,category}] |
| `twgcb_config` | 檢查項設定 | check_id, enabled, threshold, remediation, exception_hosts |
| `twgcb_exceptions` | 例外紀錄（正式） | check_id + hostname + reason + approved_by + approved_date |
| `twgcb_fix_status` | 修復進度 | hostname, status, results[], started_at, finished_at |
| `account_audit` | 帳號盤點 | hostname, user, last_change, last_login, risk_flags |
| `cache` | **共享 cache（Gunicorn multi-worker）** | _id（key）, data, updated_at |
| `fix_locks` | **per-host 修復鎖** | _id（hostname）, locked_at, expires_at, locked_by |
| `login_attempts` | 登入失敗計數 | username, attempts, locked_until |
| `admin_worklog` | 操作稽核 | user, action, detail, ip, timestamp |
| `host_packages` (v3.8+) | 主機套件快照 | hostname, os, kernel, pkg_manager, packages[{name,version,arch,install_date}] |
| `host_packages_changes` (v3.8+) | 套件變更日誌 | hostname, changed_at, added[], removed[], upgraded[] |
| `nmon_daily` (v3.9+) | 每日效能 | hostname+date (unique), cpu/mem/disk/net_kbps {peak,avg,peak_time}, timeseries: [{time,cpu,mem,disk,net_kbps}] |
| `feature_flags` (v3.10+) | 功能模組開關 | key, name, enabled, description |
| `settings` | 全域設定 | key, value, updated_at (含 nmon_interval_min) |

**TTL / 索引**：`twgcb_results.{hostname, os+hostname, checks.status}`、`hosts.{ap_owner, tier}`、`twgcb_exceptions.{hostname+check_id}`

---

## 六、核心功能清單

1. **每日巡檢**：cron 或 UI 觸發 `site.yml` → 寫 `inspections`
2. **今日報告 / 歷史查詢**：從 `inspections` 顯示；卡片點擊 → 主機詳情
3. **異常總結**：聚合 FAIL 項目，可匯出 CSV
4. **TWGCB 合規**：57 項 Linux + 8 項 Windows check，4-tier 矩陣（檢查項 × 主機）
5. **TWGCB 修復 / 全修 / 還原 / 全還原**：4 個關鍵路徑，**都必須走背景 rescan**（見坑八）
6. **TWGCB 例外管理**：點紅/綠燈 → modal → 填原因/核准人/日期；可編輯、可取消
7. **主機管理**：CSV/JSON 匯入匯出，含 system_name/tier/ap_owner/custodian
8. **帳號盤點**：180 天未改密 / 未登入 + HR 匯入比對
9. **系統安全稽核**：萬用 Linux 安全稽核 shell，IP 複選、進度條、報告
10. **Patch 系統**：上傳 patch_vX.X.X.X.tar.gz → 預覽 → 套用 → 一鍵回滾
11. **MongoDB Dump/Restore**：UI 觸發 `mongodump --archive --gzip`
12. **超管 Git 推送**：UI 直接 `git add/commit/push` 到 GitHub
13. **軟體盤點 (v3.8.0.0+)**：Ansible collect_packages role → rpm/dpkg/Windows uninstall registry → 合併至 `host_packages`；搜尋「哪些主機裝了 openssh?」跨 OS 版本分布
14. **效能月報 (v3.9.0.0+)**：nmon 採樣（per-host 可調 1/5/15/30/60/1440 分鐘）→ 解析 .nmon (CPU_ALL/MEM/DISKBUSY/NET) → `nmon_daily` (peak/avg + timeseries) → matplotlib 產 PNG (Noto Sans CJK) → 日/週/月三視角 + 事件亮點 + vs 昨日/上週/上月比較 + 列印友善
15. **Tunnel 健康檢查 (v3.8.0.3+)**：`scripts/tunnel_healthcheck.sh` cron 每 2 分鐘 curl 外部 URL，連 2 次失敗才 restart cloudflared（避免 tunnel QUIC long-connection stall 造成 502）
16. **功能模組 on/off (v3.10.0.0+)**：6 個模組可切換（audit/packages/perf/twgcb/summary/security_audit），關閉即 navbar 藏入口 + 頁面跳 `/feature-disabled` + API 回 402 + admin tab 同步藏

---

## 七、關鍵 API 設計

```
GET    /api/twgcb/results?os_type=linux&fail_only=1&limit=30&offset=0  # server-side filter/pagination
GET    /api/twgcb/stats                                               # overall + by_host + by_category + top_fails
GET    /api/twgcb/filter-options                                      # distinct systems/ap_owners/tiers
POST   /api/twgcb/scan    { target: "hostname" or "all" }
POST   /api/twgcb/remediate { hostname, check_id, remediation }
POST   /api/twgcb/exceptions  { check_id, hostname, reason, approved_by, approved_date }  # upsert
DELETE /api/twgcb/exceptions  { check_id, hostname }

POST   /api/admin/twgcb/fix       { check_id, hostname }   # 單項，背景 rescan
POST   /api/admin/twgcb/fix-all   { hostname }            # 全修，跳過例外，背景 rescan
POST   /api/admin/twgcb/restore   { hostname, backup_files: [...] }  # 單項還原
POST   /api/admin/twgcb/restore-all  { hostname }                    # 全還原，背景 rescan
GET    /api/admin/hosts/ping-all?force=1  # 60s MongoDB cache；回傳 cached+age_sec
```

所有耗時 API 必須：
- 前端：spinner + AbortController + `_dashToast`（或 `_showRescanToast`）+ finally 還原按鈕
- 後端：`@admin_required` + log_action() + 回傳 JSON {success, message, ...}
- 修復/還原：**務必背景 rescan + 回 `rescan_pending: true`**，前端延遲 20s loadTab

---

## 八、非顯而易見的坑（**AI 必讀，避免重踩**）

### 1. Ansible 連線細節
- Linux: `ansible -u ansible_svc --become -m shell` — 每台被控機要有 `ansible_svc` 使用者 + sudo 無密碼
- Windows: `-m raw`（不是 shell）+ EncodedCommand 編碼 PowerShell
- ansible-host 本機 inventory 要設 `ansible_connection: local`

### 2. remediation 指令的通用 bug
- **Debian auditd `log_group = adm` 會 revert**：只 chown/chmod 沒用，必須先 `sed log_group=root` + `systemctl restart auditd` 再 chown
- **sed `1i TEXT` 透過 `ansible -m shell` 傳遞會 quoting 失敗**（報「預期在 a c i 之後出現 \」）→ 改用 `sed '1s|^|TEXT\n|'`
- **check 腳本不要依賴指令的訊息文字**：中文 locale 下 `rpm -q pkg | grep 'not installed'` 會誤判；改用 exit code

### 3. fix-all / restore-all 歷史作弊
- 舊版 fix-all 直接把 `twgcb_results.status` 改 PASS + 寫 `fixed_at`（不重掃）
- 舊版 restore-all 靠 `fixed_at` 反向標 FAIL
- **兩者都要廢掉**，改用 `threading.Thread` 跑背景 `twgcb_scan.yml --limit <host>` + import JSON
- 回傳 `rescan_pending: true` 給前端，前端 20s 後 loadTab

### 4. success 判斷絕不能只看 rc=0
- 很多 remediation 以 `echo OK` 結尾，前面失敗 rc 仍 0
- 必須加字串檢查：`"| FAILED"`, `"UNREACHABLE"`, `"Failed to mask"`, `"Failed to enable"`, `"Authentication failed"`, `"Permission denied"` 任一 match → 判失敗

### 5. Gunicorn multi-worker 前置功課
- Process-local 記憶體（dict/set/rate limit）**不跨 worker 共享** → 搬 MongoDB
- `_ping_cache` 和 `_fixingHosts`（per-host 鎖）必須用 MongoDB，用 `_id` 唯一約束做原子 lock（`DuplicateKeyError` 表示已鎖）
- 背景 thread 在 worker recycle 時會被 kill → 目前接受（未設 max_requests）

### 6. Ansible fact 可能缺
- `ansible_distribution` 在某些 Debian + ansible 組合下**即使 gather_facts=true 也會 undefined**
- `set_fact` 引用時**一定要加 `| default('Linux')`**，不然 playbook fatal=1，背景 rescan 默默失敗，UI 看起來假綠

### 7. API filter 的 regex 要涵蓋 fallback 值
- 例：`/api/twgcb/results?os_type=linux` 的 filter regex 必須包含 `linux` 字面，不能只列 distro 名稱
- 否則 `os="Linux"` fallback 的主機會被漏掉，Linux tab count 跟 matrix 不一致

### 8. 前端同主機鎖
- `window._fixingHosts[hostname] = unlock_ts`，按第二次按鈕時先 `_tryLockFix`
- 成功後 `_extendLockFix(hostname, 20)` 讓鎖持續到背景 rescan 結束

### 9. 模板編輯陷阱
- `tmp_*_served.html` 是 Flask 渲染後輸出，不是 Jinja 模板
- 改 template 要 `scp` 下載原始 `templates/xxx.html`，改完傳回
- 不要覆蓋用 `tmp_*_served.html`，會失去 `{% extends %}`

### 10. 部署後 Jinja cache
- 改 template 要 `systemctl restart itagent-web`，不然 Jinja cache 不會 reload

### 11. 靜態資源快取（v3.9.3.0+）
- Flask context processor 注入 `_APP_VER = _load_app_version()`（讀 data/version.json）
- 所有 `<link>` `<script>` 要帶 `?v={{ APP_VER }}`，改版自動 bust 瀏覽器 cache
- `app.py` 必須 `import os`（`_load_app_version()` 用到）

### 12. MongoDB projection 規則
- 同一 projection 不能 inclusion (`key:1`) 加 exclusion (`key:0`) 混用 — 會噴 `Cannot do inclusion on field X in exclusion projection`
- 例：`col.find({}, {"_id":0, "timeseries":0, "cpu":1})` 會爆；只保留 `{"_id":0, "timeseries":0}` 即可

### 13. SSH 斷線 / cloudflared 502 / curl stall — 不是 server 問題，查 MTU (v3.9.x 踩坑)
- 症狀：SSH 連幾秒就 `kex_exchange_identification: Connection closed`、網站間歇 502、大檔下載到 ~200KB 卡住 17 秒
- 診斷：`ping -M do -s 1472 1.1.1.1` → `message too long, mtu=1492` 就是中毒
- 原因：台灣 ISP PPPoE overhead 8 bytes，實 MTU=1492 但 VM 網卡預設 1500 → 大封包默默被中間設備丟、PMTUD 常被擋
- 修復：`ip link set ens160 mtu 1492` + `nmcli connection modify ens160 802-3-ethernet.mtu 1492` (永久)
- 預防：`sysctl net.ipv4.tcp_mtu_probing=1` 寫入 `/etc/sysctl.d/99-tcp-mtu-probe.conf`，kernel 自動偵測 PMTU blackhole
- **不要先怪 sshd** — sshd 從頭到尾活著，是 TCP 封包在中間丟

### 14. nmon 5-min cron 的 timeseries 合併
- 每 5 分鐘跑 `nmon -f -s 60 -c 5` 產一個 5-min 小檔
- 1 天 288 個小檔，`import_nmon_files()` 同日多檔要**合併 timeseries**（去重 by time，重算 peak/avg）
- 第一次 import 用新 parser → **要先清 nmon_daily + bust chart cache**，不然舊 doc 沒 timeseries

### 15. matplotlib 中文字型
- Rocky 9 裝 `google-noto-sans-cjk-ttc-fonts`；matplotlib 會看到 `Noto Sans CJK JP` (JP 字型含全部 CJK unicode，能顯示繁中)
- `rcParams["font.family"] = _CJK_FONT` + `rcParams["axes.unicode_minus"] = False`
- 無 X display 用 `matplotlib.use("Agg")`

### 16. cloudflared QUIC 老 connection 會卡死
- 跑 24h+ 後 4 條 QUIC 可能集體 timeout 進指數 backoff，tunnel process 沒死但無法 serve
- 解法：改走 `--protocol http2`（TCP 比 UDP 寬容丟包）+ cron healthcheck 2 次失敗 restart
- healthcheck 區分 `http=000` (我方 timeout，restart) vs `http=502/530` (Cloudflare edge sync 延遲，通常自癒)

### 17. Feature Flag 的 3 層攔截
- DB (feature_flags collection) → Server (`@app.before_request` 配 `_FEATURE_PATH_MAP`) → Client (`window.FEATURES` + `applyFeatureFilter()` 藏 nav/admin tab)
- login gate 要比 feature gate **更早** register（Flask 按註冊順序執行），不然未登入會看到 module 頁面
- `/feature-disabled?m=xxx` 這個頁面**本身不能被任何 flag 擋**，否則死循環

---

## 九、預設設定值

- Flask session: 8 小時
- 登入失敗鎖定: 5 次 / 15 分鐘
- MongoDB cache TTL: 60 秒（ping-all）
- 修復鎖 TTL: 60 秒（單項）/ 300 秒（全修）
- Gunicorn: `-w 4 --timeout 300 --graceful-timeout 30`
- AbortController timeout: 30s（儲存/ping）/ 90s（單項修復）/ 120s（掃描/還原）/ 180s（下載部署包）/ 300s（全修）
- TWGCB 各項 check_id 閾值 → 見 `twgcb_config` collection

---

## 十、建置順序（AI 按這做，一步一步）

> **原則：每步做完回報 → 等確認 → 下一步**。出問題立刻停下討論，不要自行跳步。

1. **準備**：Rocky 9 VM（≥ 2GB RAM / 20GB 硬碟）+ 網路 + root + Git
2. **安裝依賴**：`dnf install -y podman ansible-core python3-pip git vim net-snmp-utils`
3. **建立目錄**：`mkdir -p /opt/inspection/{ansible,data,webapp,scripts,systemd}`
4. **Ansible Vault**：`ansible-vault create .vault_pass`
5. **MongoDB**：`podman run -d --name mongodb --systemd always -p 127.0.0.1:27017:27017 -v /var/log/inspection/mongodb:/data/db docker.io/library/mongo:6`
6. **Python deps**：`pip install flask pymongo bcrypt pyyaml gunicorn python-ldap cryptography`
7. **寫 Flask app**：`app.py`（SECRET_KEY 用 `secrets.token_hex(32)`、SESSION_COOKIE_HTTPONLY=True、SESSION_COOKIE_SAMESITE=Lax、FLASK_DEBUG=False、覆蓋 Server header）
8. **寫 routes**：按「七、關鍵 API 設計」逐個加，先 twgcb 再 admin 再 superadmin
9. **寫 services**：mongo_service.py（get_db/get_collection + TTL indexes） / auth_service.py（bcrypt + login_attempts）
10. **寫 templates**：base.html（含 `_dashToast` helper in dashboard.js）→ 其他頁 extends
11. **寫 Ansible roles**：`check_twgcb/tasks/main.yml`（60+ 項，**每項帶 id/category/name/level/expected/actual/status/detail/remediation**）
12. **systemd unit**：itagent-db.service + itagent-web.service（用 Gunicorn）
13. **部署 SSH key** 到受監控主機 + 建 ansible_svc 帳號 + sudoers NOPASSWD
14. **seed 資料**：`users`（bcrypt hash 的 superadmin/admin）、`hosts`（CSV 匯入 UI 也可）
15. **Cloudflare Tunnel**：`cloudflared tunnel create inspection` → token → systemd
16. **Smoke test**：ping-all / login / TWGCB 矩陣 / fix / fix-all / restore / restore-all 全走一次
17. **Git init + push 到 GitHub private repo**

---

## 十一、完成條件

- `/` Dashboard 可看到 4 台測試主機（2 Rocky + 1 Debian + 1 Windows）
- `/twgcb` 矩陣看到檢查項 × 主機，紅/綠/橘燈正確顯示
- 故意弄壞某項 → 按「修」→ 20s 後自動變綠（驗證修復鏈完整）
- 修好後按「還原」→ 20s 後再變紅（驗證還原鏈完整）
- `ps -ef | grep gunicorn` 看到 1 master + 4 worker
- `systemctl is-active itagent-db itagent-web` 都 active
- 跨 worker cache：連打 10 次 `/api/admin/hosts/ping-all` 都 `cached: True`

---

## 十二、給 AI 的最後提醒

1. **每次改動必更版**：`data/version.json` + 追加 `data/SPEC_CHANGELOG_20260410.md`
2. **變更檔案先備份**：`cp file file.bak_$(date +%Y%m%d_%H%M)`
3. **commit 訊息繁體中文** + 含 `Co-Authored-By`
4. **不要跳過測試**：每階段跑 smoke test
5. **看到類似 bug 別急著打地鼠**：#31→#36→#44→#45→#46 就是「治標不治本」的反面教材，要找出呼叫鏈的對偶端一起修
6. **前端所有耗時按鈕必須有 spinner + toast + timeout + finally**（async-feedback 標準）
7. **前端資料流**：按鈕點擊 → AbortController → fetch → 檢查 `res.success` → 顯示 toast → finally 還原按鈕
8. **後端資料流**：`@admin_required` → parse → 業務邏輯 → `log_action()` → return `jsonify({success, ...})`
