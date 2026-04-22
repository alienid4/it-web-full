# Changelog

本檔由 `AI/data/version.json` 轉出。版本由新到舊。

目前版本：**3.11.4.1**

---

## v3.11.4.1 — 2026-04-22
修 `run_inspection.sh` 3 個 bug（使用者實跑發現）
- (1) 新增 `ansible/ansible.cfg` 設 `roles_path=./roles`（原本缺 cfg 導致 `collect_packages.yml` 找不到 role → playbook 失敗）
- (2) CIO snapshot 區段 `date +%Y-%m-%d %H:%M:%S` 修引號（原本被當成 2 個 arg，`%H:%M:%S` 變 extra operand）
- (3) CIO snapshot python heredoc 修字串引號（`sys.path.insert(0, .)` → `(0, '.')`；`print([cio]...)` 整段沒 quotes 導致 SyntaxError line 3）

## v3.11.4.0 — 2026-04-22
預設自動加本機當第一台主機 + 修 `hosts_config.json` 沒同步 bug
- (1) `bootstrap.py seed_hosts` 改寫：`socket.gethostname()` + `127.0.0.1` + `ansible_connection=local` + 自動偵測 OS（從 `/etc/os-release` 讀 PRETTY_NAME/ID），刪掉原本 2 個範例（`ansible-host` + `testhost01` placeholder）；新增 `_sync_hosts_config_json()` 和 `_regen_inventory()` helper，seed_hosts 即使 skip 也會強制 sync + regen 解決已裝環境
- (2) `generate_inventory.py` 支援 host 的 `connection` 欄位 → `ansible_connection=local` var；移除 `SECANSIBLE` 硬編碼 block（含 `<ANSIBLE_HOST>` placeholder leak），改從 `hosts_config.json` 動態產 management 群組
- (3) `patches/v3.11.4.0/post_install.sh` 自動修復：偵測 hosts 為空 seed self → 強制重建 `hosts_config.json` → `chown data/` 給 sysinfra → 重建 inventory，解決使用者 DB 加主機卻不產 json 的卡點

## v3.11.3.0 — 2026-04-22
產品化 patch 流程 v1 + 修 example.css 404
- (1) `AI/scripts/patch_apply.sh` 大改 — 支援 `whls/` 離線 pip install（`--break-system-packages`，避免 `--user` 裝到 `/root/.local` 讓 systemd 看不到）+ 可選 `post_install.sh` hook + 環境變數驅動 `ITAGENT_HOME`/`ITAGENT_SERVICE` + `REQUIRES_RESTART` 旗標 + 備份排除 `container/` `logs/` + HTTP 驗證
- (2) 補 `webapp/static/css/example.css`（從 `cathay.css` 複製）— 修 sanitize 時漏改導致 `base.html` / `login.html` / `reset_password.html` 三個模板 404 撞 MIME check
- (3) `patches/v3.11.3.0/` 完整 patch 包（`patch_info.txt` + `patch_apply.sh` + `files/`）— 可 `tar czf` 後 scp 到目標機命令列套用，**Flask 不需活著（解雞生蛋）**
- (4) 新增 `AI/scripts/user_admin.sh`（9 選單：列帳號 / 詳情 / 解鎖 / 改密 / 新增 / 改角色 / 刪 / 登入紀錄 / **一鍵診斷登入問題** — 7 層檢查 MongoDB / Flask / port / 帳號 / 欄位 / 鎖定 / API）

## v3.11.2.0 — 2026-04-20
離線部署包 (給公司郵件帶) - (1) scripts/bootstrap.py 獨立 DB 初始化 (users 3 角色/feature_flags 6/settings 3/hosts 2 sample/indexes 15+, 用 werkzeug.security 不需 bcrypt) (2) scripts/build_source_bundle.sh 打包 webapp+ansible+scripts+systemd+bootstrap+requirements+4 份 md + 自動產 README_INSTALL.md 10 步安裝指南, 產出 352KB tar.gz 放 data/uploads/ (可從 UI 檔案管理 下載) (3) WHEEL_URLS.md: 27 個 Python 套件的 PyPI files.pythonhosted.org 直連 URL (pypi json api 抓的), 掛 DOCS_MAP 第 14 份 (4) requirements.txt 擴充 6 個核心 (flask/pymongo/gunicorn/matplotlib/reportlab/python-ldap)

## v3.11.1.0 — 2026-04-20
CIO #2-4 完成 + 離線依賴清單. (1) CIO #2 TWGCB 合規率趨勢: twgcb_daily_stats collection (唯一鍵 date), snapshot_twgcb_daily() 已整合 run_inspection.sh 每日巡檢, /api/cio/trend|trend-chart (PNG, matplotlib), /executive 頁加 30/90/365 天切換. (2) CIO #3 老化分析: by department / by ap_owner / by level + 超門檻 Top 20 (FAIL 已開幾天), /api/cio/aging?threshold=30. (3) CIO #4 月度 PDF: reportlab + Noto CJK 字型, services/cio_pdf.py, /api/cio/pdf 一鍵下載, scripts/cio_monthly_report.sh + cron 0 9 1 * * (每月 1 號). (4) 離線安裝包: 新 OFFLINE_DEPS.md (35 Python wheel PyPI 連結, 10 個 Rocky 9 RPM, MongoDB 映像 podman save/load, cloudflared RPM, 中繼機一鍵打包腳本 bundle_offline_deps.sh 預估 1.5~2GB), 掛 DOCS_MAP 第 13 份

## v3.11.0.0 — 2026-04-20
CIO #1 資訊主管儀表板 /executive - (1) services/cio_service.py 彙整主機健康/TWGCB 合規率/Top 5 高風險/TWGCB A 級 FAIL 計數/效能峰值/事件摘要/綜合健康指數 (host 0.3 + 合規 0.4 + 資安 0.3) (2) 4 支 API /api/cio/overview /recommendations /top-risks /health-score (login_required) (3) /executive 頁: conic-gradient 健康指數環 + 4 大 KPI 卡 (主機在線/合規率/資安/效能峰) + 建議行動 (error/warn/info/ok 分色) + Top 5 高風險表格 + 本週事件 + 合規趨勢 placeholder (CIO #2 尚未) (4) navbar 加 👔 主管儀表板 入口 (限 admin+superadmin) (5) 列印友善 CSS. 實測 health_score=93.9 優良

## v3.10.2.0 — 2026-04-20
開發者文件 3 件更新 - (1) REBUILD_FROM_ZERO_SKILL.md 擴充 (加 軟體盤點/效能月報/tunnel healthcheck/feature flags 4 模組章節, MongoDB schema 補 5 新 collection, 坑 11-17 含 MTU/cache bust/MongoDB projection/nmon timeseries 合併/matplotlib 中文字型/cloudflared QUIC/feature flag 3 層攔截, 從 266 行擴到 314 行) (2) project_memory.md 全改寫至 v3.10.1.1 總覽 (3) 新增 RUNBOOK.md (286 行, 12 類常見問題: 健檢儀式/SSH-MTU/502/500/空白頁/TWGCB 修復/nmon/feature flag/登入鎖/MongoDB 容器/備份還原/全站停復原/CIO 待開發清單) 掛 DOCS_MAP 第 12 份

## v3.10.1.1 — 2026-04-20
修 superadmin 模組管理 tab 空白 bug - 原 patch 的 anchor 找不到導致 tab-content-features div 沒插入 (只有按鈕沒內容)。改以 tab-content-notes 結束標記當 anchor, 並補上 tabs list 加 features。現在 superadmin → 模組管理 tab 會顯示 6 個模組開關 + 說明 + 啟用/關閉 badge

## v3.10.1.0 — 2026-04-20
Feature Flag UI 完整隱藏 - (1) base.html 注入 window.FEATURES = {...} 給前端 JS (2) admin.js 加 applyFeatureFilter(): 根據 window.FEATURES 隱藏 [data-feature] 關閉的 tab 按鈕 + tab-panel, 整組 admin-nav-group 子項全藏時連組別也藏, 當前 active tab 被藏時自動切到第一個可見 tab (3) 適用所有 feature tabs: audit/security_audit/twgcb/twgcb reports/perf 的 tab 按鈕與 panel 同步消失

## v3.10.0.0 — 2026-04-20
功能模組 on/off 系統 + admin reorg (方法 2) - (1) admin-nav CSS 從 flex:1 改 gap:32px justify-content:center (消除標題 5 分等寬的大片空白) (2) 新 feature_flags collection, 6 個可關模組預設全開: audit/packages/perf/twgcb/summary/security_audit (3) Flask before_request _check_feature_flag + _FEATURE_PATH_MAP: 頁面 302→/feature-disabled?m=xxx, API 回 402, /static/*與/feature-disabled 白名單 (4) Jinja context processor 注入 FEATURES, base.html nav 用 {% if FEATURES.xxx %} 包起來 (5) /feature-disabled 頁 (友善說明) (6) admin.html: nmon 排程卡從 巡檢排程 tab 剪出, 新建獨立 tab-perf-mgmt (監控平台管理 → 🎚️ 效能月報管理), 所有 feature 相關 tab 加 data-feature=xxx; admin.js _tabLoaders 加 perf-mgmt: loadNmonSchedule (7) superadmin 新 tab 🎛️ 模組管理 + /api/superadmin/features/list /features/toggle (8) test_client 驗證 302→disabled page / 402 API / nav 條件渲染全通. 後續仍須 admin.js 依 data-feature 隱藏模組 tab 按鈕 (未做 — 目前 tab 按鈕還在但 click 進去 tab-panel 本身有 data-feature, CSS 藏 tab-panel 即可遮蔽)

## v3.9.4.0 — 2026-04-20
nmon 排程支援 per-host 頻率 - (1) API /schedule 接受 host_configs=[{hostname,interval_min}] (相容舊 {interval_min,hostnames}) (2) 部署時依 interval 分組, 一組一次 ansible-playbook (減少重複執行) (3) UI 每台主機卡片新增 頻率下拉 (1/5/15/30/60/1440 分), 可各自不同 (4) 新 applyBatchInterval() 按鈕: 把頂部「批次頻率」一鍵套到所有勾選中主機 (5) 確認 Modal 按頻率分組顯示 (例: [5min] 3 台 / [15min] 2 台) (6) 全域 settings.nmon_interval_min 儲存「最常用那個」當新主機預設

## v3.9.3.0 — 2026-04-20
靜態資源 auto cache-busting - (1) app.py context processor 啟動時讀 data/version.json 存到 _APP_VER (2) Jinja {{ APP_VER }} 注入所有 template 全域 (3) regex 一次更新 4 個 template (admin/base/login/reset_password) 共 7 個 /static/css|js/ 引用自動加 ?v={{ APP_VER }} (4) 以後 bump version.json 瀏覽器會自動重拉 JS/CSS，不用手動改 HTML。需重啟 webapp 才會重新 load _APP_VER (因只在啟動讀一次)

## v3.9.2.0 — 2026-04-20
nmon 排程整合到系統管理頁 - (1) 監控平台管理 → 巡檢排程 下方加「nmon 效能採樣排程」卡片 (2) 稽核專區風格多主機 checkbox: hostname/IP/OS + tier badge + 搜尋 + 全選 + 隱藏/顯示不支援 (Windows 自動灰掉不可勾) (3) 頻率下拉 6 檔: 1/5/15/30/60/1440 分 (4) Ansible role collect_nmon 支援 nmon_interval_min 變數, cron 公式自動算 minute/hour (5) 新 playbook remove_nmon.yml (僅清 cron, 保留歷史 .nmon 檔案) (6) API /api/nmon/schedule GET+POST + /preview: 擋 Windows + 分類 to_enable/to_disable/skipped_windows (7) 套用 Modal 二次確認 (列出啟用/停用/忽略名單) (8) async-feedback: 按鈕 disabled+spinner+toast+finally, 30 秒後自動 reload 狀態 (9) 主機卡片顯示最後部署時間+頻率 (10) hosts collection 加 nmon_interval_min / nmon_deployed_at / nmon_removed_at 三欄位. 備份: admin.html/admin.js .bak.20260420_nmon_sched

## v3.9.1.1 — 2026-04-20
日報/週報加事件亮點+比較區塊 (跟月報對齊). 日報: 本日事件(掃 timeseries 找 CPU>80/Mem>85/Disk>70 片段) + 昨日比較 (avg vs avg). 週報: 本週事件(7 天內超門檻天數) + 上週比較 (7 天 peak 均 vs 上週). 修 MongoDB projection 不能同時 inclusion+exclusion 的 bug.

## v3.9.1.0 — 2026-04-20
效能報表全面升級 - (1) 圖表從 Chart.js 動態改 matplotlib server-side PNG (列印/email 友善, 裝 google-noto-sans-cjk-ttc-fonts 解中文), 檔案快取 data/cache/charts/, mtime vs latest_import_at 失效 (2) 新增日/週/月三種視角: 日=intra-day timeseries (HH:MM x 軸, 看峰段), 週=7 天 peak/avg, 月=全月 peak/avg (既有) (3) nmon_service _parse_nmon 保留 timeseries, import_nmon_files 同日多小檔自動合併+去重+重算 peak/avg (配合 5 分鐘 cron 會產 288 個小檔/天) (4) 5 支新 API: /chart 加 mode+year/month/start/date, 新 /day, /week (5) perf.html 加 日/週/月 toggle + 對應 date picker + 重畫按鈕 (bypass cache) (6) sec9c2 cron 從 0 0 * * *（24h 大檔) 改為 */5 * * * * -s 60 -c 5 (5-min 小檔便於日內查看). TWGCB fix: sec9c2 dpkg host default route parsing 在 check_network 還沒修. L2b/c/d 後續.

## v3.9.0.0 — 2026-04-20
效能月報模組 (nmon) — 給部門主管看. (1) Ansible role collect_nmon Linux(apt/dnf/yum 自動) + AIX raw playbook, 下 cron 00:00 跑 nmon -f -s 60 -c 1440 (24h/60s 採樣), fetch 近 2 天 .nmon (2) services/nmon_service.py 解析 CPU_ALL/MEM/DISKBUSY/NET 四類 + ZZZZ 時戳, 每日 peak/avg/peak_time/peak_disk 壓縮存 nmon_daily (unique idx hostname+date) (3) 月聚合: 本月峰值/均值 + 峰值日 + 上月 avg 比較 (4) 6 支 API /api/nmon/* (hosts/monthly/toggle/import/collect/export CSV, 都加 @login_required / @admin_required) (5) /perf 月報頁: header(hostname/IP+系統+級別金銀銅漸層 badge) + 4 KPI 卡 + 4 張 Chart.js 每日趨勢(峰值/均值雙線) + 事件亮點(CPU>80/Mem>85/Disk>70 門檻) + 上月比較 + 列印 CSS(隱藏 nav) + CSV 匯出 (6) navbar 加「效能月報」入口 (7) 日巡檢 run_inspection.sh 整合: nmon_enabled 主機清單自動抓 + collect + import. 實測 sec9c2 手動 30s 採樣, parser 正確解析 10 snapshot, aggregate/monthly/peak_days/上月比較均通.

## v3.8.0.3 — 2026-04-20
Cloudflare Tunnel 健康檢查 + 自動重啟. 事故: tunnel 跑 24h+ 後 QUIC 連線 timeout 進指數 backoff 無法 self-heal (502). 對策: (1) systemd 已有 Restart=on-failure+RestartSec=10 (process 死) (2) 新增 scripts/tunnel_healthcheck.sh: 每 2 分鐘 cron curl https://it.94alien.com/login, 連續 2 次失敗才 restart itagent-tunnel (防瞬斷誤判), 重啟後 180s 寬限期, log 輪轉 >1000 行截半. 實測模擬 2 次失敗觸發 restart, tunnel 8 秒內全 4 條連線重註冊 (tpe01x2+khh01x2).

## v3.8.0.2 — 2026-04-20
全站強制登入 - (1) decorators.py 從緊急 bypass 版還原為正式認證 (2) app.py 加 @before_request 全站攔截, 未登入頁面 302→/login?next=<path>, API 回 401 (3) 白名單: /login, /api/admin/login, /api/settings/version, /favicon.ico, /static/*. 備份 .bak.20260420_enforcelogin. 實測 8 個頁面全部 302 到 login, 4 支 API 401, 白名單通.

## v3.8.0.1 — 2026-04-20
【緊急變更】移除「Example Corp」字眼(base.html title 改 IT 監控系統 + navbar brand 去掉 logo 與文字 + admin/twgcb_report/twgcb_settings rptCompany 預設值清空) + 暫時停用登入(decorators.py login_required/admin_required 自動注入 guest/admin session). 備份檔 .bak.20260420_emergency. 還原指令: cp <file>.bak.20260420_emergency <file> && systemctl restart itagent-web

## v3.8.0.0 — 2026-04-20
新增軟體盤點模組 (Package Inventory / SBOM) - (1) Ansible role collect_packages (Linux rpm/dpkg 雙模式 + Windows registry uninstall, Windows role 已就緒待主機 online 測試) (2) MongoDB: host_packages 快照 + host_packages_changes 變更日誌, 6 個索引 (3) 7 支 API: list/host/search/changes/export/collect/import 全部加 @login_required 或 @admin_required (4) /packages 頁 3 tab: 主機清單 (下載 CSV/JSON) / 套件搜尋 (跨 OS 版本分布) / 變更歷史 (diff +added -removed ~upgraded) (5) navbar 加「軟體盤點」入口 (6) 整合 run_inspection.sh: 日巡檢跑完自動收套件+diff 入 MongoDB. 實測 3 台 Linux (ansible-host 489/client-host-1 375/sec9c2 345)

## v3.7.2.0 — 2026-04-19
上線前 P1 資安修補完成 - (1) flask 2.2.5→3.1.3 升級 (requirements.txt 修正對齊實際 pin) (2) python-ldap 3.4.5 同步 (3) /api/hosts /api/inspections/latest /api/settings 及同 blueprint 共 12 支 GET/PUT 補 @login_required (保留 /api/settings/version 給 navbar 公開) (4) Cockpit 9090 移出 firewall public zone (需 SSH tunnel 連線). security_scan.sh full: FAIL 5→2 (剩系統套件 66 CVE 列 P2 + CSRF 規劃 v3.8.0.0). pip-audit on requirements.txt: clean.

## v3.7.1.0 — 2026-04-19
上線前資安 5 層掃描完成(security_scan full/Bandit SAST/pip-audit/Wapiti DAST/TWGCB 自掃) - 產出 SECURITY_RELEASE_20260419.md 掛上開發者文件第 11 份；TWGCB ansible-host 49/49 100% 合規，P1 5 項待修

## v3.7.0.0 — 2026-04-19
SSH Key 管理加強 (#46) + 新建遠端工具分頁 (#47) + Admin nav 改名拆運維工具分組 + tab auto-loader (#48). Batch Deploy/Remove 走 Ansible 自動建帳號密碼 P@ssw0rd, ssh_key_records 每帳號獨立時間戳. 遠端工具支援批次上傳/下載打包zip/執行指令, 空間>85% 告警, 營業時間 09:00-15:00 異動指令需 OA 單號. 踩坑: 三引號內 
 陷阱改 chr(10); regex 替換用 START/END marker 防 orphan.

## v3.6.1.1 — 2026-04-19
superadmin tab 順序調整 - 開發者文件 / 檔案管理 / 備忘錄 / GitHub / 提交紀錄 (預設停開發者文件)

## v3.6.1.0 — 2026-04-19
superadmin 5 功能分 5 tab (GitHub 推送/提交紀錄/開發者文件/檔案管理/備忘錄) (#48)

## v3.6.0.0 — 2026-04-19
開發者文件區補第 10 份「從零重建 SKILL」(#47) - 266 行完整自給自足重建指南，含架構/API/DB schema/坑紀錄/17 步建置順序

## v3.5.4.2 — 2026-04-19
/api/twgcb/results 的 linux regex 補 "linux" 字面 match (ansible_distribution fallback 後 os=Linux 的主機被過濾掉)

## v3.5.4.1 — 2026-04-19
修 ansible_distribution undefined 讓背景 rescan playbook 不再 fatal (#46) - 一直以來背景 rescan 默默失敗導致 UI 假綠色

## v3.5.4.0 — 2026-04-19
修 remediation 對 Debian 有效 (#44) + restore/restore-all 加背景 rescan (#45)

## v3.5.3.1 — 2026-04-19
橘色例外環改粗 4px + 加光暈 (2px 太細看不到)

## v3.5.3.0 — 2026-04-19
PASS 項有例外時加橘色環標示 (父項目橘燈可對應到子項目)

## v3.5.2.0 — 2026-04-19
例外編輯 + 全修跳過例外 - exDetailModal 加 edit 模式可改 reason/approved_by/approved_date；twgcb_fix_all 過濾掉已標例外的 check_id，回傳 skipped_exceptions 計數

## v3.5.1.0 — 2026-04-19
實測回報修復 - (1) 安全稽核完成加「查看/下載報告」按鈕 (2) twgcb_config 清理 34 筆 undefined (補 11+刪 23) (3) harden 頁 doException 改走統一 API 與主頁一致

## v3.5.0.0 — 2026-04-19
Phase 2 #5 Flask dev server 換成 Gunicorn (1 master + 4 worker, 300s timeout) 支撐 500-2000 台規模；依賴 #39 共享狀態改造；新增 rollback_to_flask_dev.sh 緊急回切腳本

## v3.4.19.0 — 2026-04-19
Gunicorn 準備 - ping-all 快取 + TWGCB 修復鎖從 process-local 搬到 MongoDB 共享 (cache / fix_locks 兩個 collection)；新增 4 個 _mongo_* helper；multi-worker 安全

## v3.4.18.0 — 2026-04-19
TWGCB Phase 2 #7B+#7C - TWGCB 強化/設定/詳情三頁按鈕 + superadmin gitPush/downloadPackage + admin.js adminAction helper(28+ 按鈕共用) 全部套 async-feedback 標準

## v3.4.17.0 — 2026-04-19
TWGCB 修復按鈕同主機鎖 - 避免連點兩顆修引發 remediation race；quickFix/execFix/fixOneHost 三入口套 _tryLockFix，鎖延到背景 rescan 結束(20s)，失敗立即釋放；toast 顯示剩餘秒數

## v3.4.16.0 — 2026-04-19
TWGCB 修復鏈收口 - /api/admin/twgcb/fix 與 fix-all 加 failure_markers 字串檢查(避免 echo OK 吞錯誤)；移除 fix-all 直接改 DB 為 PASS 的作弊；改為背景 rescan+import，前端 20 秒後自動刷新真實狀態

## v3.4.15.0 — 2026-04-19
TWGCB Phase 2 #7A UI 標準化(批A) - Dashboard/今日報告/主機詳情共 5 顆後端觸發按鈕套 async-feedback(spinner+AbortController+toast+finally)；dashboard.js 新增全站 _dashToast

## v3.4.14.0 — 2026-04-19
TWGCB Phase 2 #6 UI 標準化 - execFix/restoreFix 兩按鈕改為 async/await + spinner + AbortController(90s/60s) + toast + finally 還原狀態，與站內其他 9 顆按鈕對齊

## v3.4.13.0 — 2026-04-19
TWGCB Phase 2 #4 效能優化 - /api/admin/hosts/ping-all 加 60 秒記憶體快取(避免每次進 Dashboard 都並行開 500 個 ping subprocess)，支援 ?force=1 強制刷新

## v3.4.12.0 — 2026-04-19
TWGCB Phase 2 #3 UI 優化(500台規模) - 新增 /api/twgcb/filter-options endpoint 從 hosts collection distinct 載滿系統別/AP負責人/級別下拉，不再分頁累積只看當前頁

## v3.4.11.0 — 2026-04-19
TWGCB 修復三項 bug - (a) FCB-0006 sendmail check 中文 locale 誤判(改用 exit code); (b) /api/twgcb/remediate 缺 -b become 導致 sudo 不生效; (c) FCB-0017 mask ctrl-alt-del.target 未先移除 symlink 導致失敗

## v3.4.10.0 — 2026-04-19
TWGCB Phase 2 UI 優化(500台規模) - 各主機合規率卡片只顯示最差10台+矩陣頁總合規率改用跨所有主機的 overall.rate(避免分頁時只算當前頁誤導)

## v3.4.9.0 — 2026-04-19
TWGCB Phase 1 500 台規模改造 + UX 修復批次. (1) 9 顆按鈕套 async-feedback (重掃/全修/還原/scanAll/匯入/存例外/取消例外/quickFix/quickRestore) — disabled+spinner+toast+timeout+連點防護. (2) 後端 /api/twgcb/results 加 server-side filter + pagination (fail_only/ap_owner/tier/system/search/limit/offset, limit 硬上限 100). (3) MongoDB 索引 6 個 (twgcb_results/hosts/twgcb_exceptions). (4) 前端分頁 UI (首/上/下/末頁) + debounce filter + race guard 防 tab 切換資料錯位. (5) loadCounts 重構 (用 stats.by_host 計算 OS 數量, 消除多餘 /results 全量抓取, 4.3s→0.9s). (6) Flask threaded=True 消除單執行緒序列化. (7) rescanHost 重命名 twgcbRescan 避免與 dashboard.js 同名衝突. 500 台壓測完整載入 ~1s.

## v3.4.8.7 — 2026-04-19
Flask after_request 對 text/html 加 Cache-Control: no-cache, 避免瀏覽器 cache 中間壞版本 HTML 導致頁面空白 (TWGCB 事故複盤預防).

## v3.4.8.6 — 2026-04-19
TWGCB 矩陣每台主機 header 加獨立 🔄重掃 按鈕 (並列全修/還原). 使用情境: 單台修復完單點覆掃, 不用等全部主機 rescan.

## v3.4.8.5 — 2026-04-19
TWGCB 統計頁面 (四卡片: 總體合規率/各主機/各分類/失敗項 Top 5). API /api/twgcb/stats 計算 pass/fail/rate by host+by category+top_fails. 頁面頂部顯示實時統計.

## v3.4.8.4 — 2026-04-19
Batch 4 系統強化 7 項 (0066/FCB-0004/0005/0006/0015/0017/0022). 總檢查項 8→49 項, 三台合規率 ~92% (client-host-1 45/49, sec9c2 44/49, ansible-host 44/49). 剩餘為 OS 預設 edge cases.

## v3.4.8.3 — 2026-04-19
Batch 3 稽核/日誌 16 項 (0132/0133/0137-0144/0149/0171/0174/0175/0177-0179). auditd/rsyslog 安裝+啟用, 權限/擁有者修正, /etc/audit/rules.d/twgcb.rules drop-in, rsyslog /etc/rsyslog.d/99-twgcb.conf drop-in. 全部 check tasks 加 become:true 統一 root 讀取. client-host-1 42/42, sec9c2/ansible-host 剩 edge cases.

## v3.4.8.2 — 2026-04-19
Batch 2 密碼策略 14 項 (retry/minlen/dcredit/ucredit/lcredit/ocredit/difok/maxclassrepeat/maxrepeat/dictcheck/deny/PASS_MIN_DAYS/unlock_time/remember). pwquality 用 drop-in /etc/security/pwquality.conf.d/99-twgcb.conf. 所有項目中文命名. become 權限修正. 3 台 26/26 全 PASS.

## v3.4.8.1 — 2026-04-19
SSH remediation 改 drop-in + reload 模式. 不碰主 sshd_config, 改寫 /etc/ssh/sshd_config.d/99-twgcb.conf, 支援 Debian(ssh)/RHEL(sshd). 3 台 x 3 輪壓測 SSH 全程不斷.

## v3.4.8.0 — 2026-04-19
TWGCB Batch 1 SSH 加固 (+4 項 0275/0278/0280a/0280b, 每台 Linux 主機從 8 項擴充到 12 項). remediation 用 sed -E 刪舊行+append 新值, 冪等且無雙引號衝突.

## v3.4.7.9 — 2026-04-19
0156 remediation 加自動安裝 auditd (Debian/RHEL), 支援 sec9c2 (Debian 13 預設沒裝 auditd 導致目錄不存在錯誤)

## v3.4.7.8 — 2026-04-19
修 TWGCB-01-008-0156 永遠修不好 bug (remediation 原用 auditctl -w runtime add, rule 已存在就 rc=255. 改為 append 到 /etc/audit/rules.d/twgcb.rules + augenrules --load, 持久化且冪等)

## v3.4.7.7 — 2026-04-19
修 restore-all 後端沒還原 twgcb_results.checks 狀態 bug (用 fixed_at 標記 arrayFilters 改回 FAIL + unset fixed_at)

## v3.4.7.6 — 2026-04-19
TWGCB 還原/重新掃描 UX 跟全修一致 (restoreOneHost 顯示 restored/total 統計+檔案列表+服務重啟; 失敗改紅色面板+output 片段; catch 改紅色面板; rescanHost 加計時器+成功綠色/失敗紅色面板)

## v3.4.7.5 — 2026-04-18
TWGCB 修復完成後自動把成功項標為 PASS (fix-all 後端 update twgcb_results.checks[].status, 使用者不用再手動 rescan)

## v3.4.7.4 — 2026-04-18
TWGCB 修復完成後 spinner 和計時器沒停 (fixOneHost/restoreOneHost 成功分支遺漏 clearInterval + spinner hide)

## v3.4.7.3 — 2026-04-18
TWGCB 修復 UX 改善 (未登入 alert 明確提示/scanProgress scrollIntoView/catch 錯誤紅色面板 12s)

## v3.4.7.2 — 2026-04-18
修復 TWGCB 頁面全失效 (twgcb.html line 551 errMsg 字串字面換行導致整支 script SyntaxError, 改為 
 escape)

## v3.4.7.1 — 2026-04-18
帳號盤點加姓名/帳號/備註/工號搜尋框 (即時過濾)

## v3.4.7.0 — 2026-04-18
帳號盤點修復 (api_audit 改讀 account_audit collection) + 開始盤點按鈕 + 盤點狀態列 + tooltip

## v3.4.6.0 — 2026-04-18
今日報告搜尋修復 (ip/custodian 欄位補齊) + 重新掃描按鈕自訂 tooltip

## v3.4.5.0 — 2026-04-17
QA full test pass + 4 bug fixes + SSH Key mgmt + navbar version + Excel template

## v3.4.4.0 — 2026-04-17
Web SSH Key management (generate/send/test via Admin UI)

## v3.4.3.0 — 2026-04-17
navbar version display + install fix (werkzeug+pyyaml+resolvelib)

## v3.4.2.0 — 2026-04-16
TWGCB修復失敗時顯示完整錯誤(主機+項目+輸出) + Windows TWGCB閾值對齊公司標準

## v3.4.1.0 — 2026-04-16
audit_linux_v6 — WARN化(2.4/5.4/5.5/5.6) + sudoers grep bug修正 + 閾值對齊公司TWGCB/FCB基準

## v3.4.0.0 — 2026-04-14
稽核專區(系統安全稽核+IP複選+非同步進度條+錯誤LOG)+Linux初始化工具(sysexpert.sh整合auto/check模式)+在線使用者追蹤+admin-tools Skill

## v3.3.2.0 — 2026-04-14
TWGCB修復(Windows playbook Jinja2引號錯誤全部修正+掃描4台成功)

## v3.3.1.0 — 2026-04-14
全站登入機制(oper帳號)+導覽列身分顯示+登入跳轉修正

## v3.3.0.0 — 2026-04-14
開發後台新增檔案管理(上傳/下載/刪除)+備忘錄(儲存/檢視/刪除)+94alien.com固定域名+Cloudflare Named Tunnel

## v3.2.1.0 — 2026-04-13
superadmin權限修正+TWGCB修復進度改善(計時器/F5安全/逐項重啟/失敗原因/重新掃描按鈕)+開發者文件區+歷史假資料

## v3.9.4.0 — 2026-04-13
下載部署包功能+Windows服務控制修復(shell→raw)+登入失敗解鎖重設按鈕+主機rescan按鈕+密碼重設

## v3.9.3.0 — 2026-04-13
登入失敗監控加解除鎖定+重設計數按鈕(API+前端)+Windows IP改回110+Ansible密碼更新

## v3.9.2.0 — 2026-04-13
Rescan功能(全部重掃按鈕+單台點擊重掃)+Dashboard和今日報告同步支援

## v3.9.1.0 — 2026-04-13
主機離線即時偵測(批次ping API+今日報告離線遮罩+Dashboard離線badge+綠點在線標記)

## v3.9.0.0 — 2026-04-13
TWGCB改為公司實際文件標準(Linux25項+Windows18項=43項)+官方TWGCB/FCB編號+RHEL/Debian指令適配+全站審查修復

## v3.8.0.0 — 2026-04-12
全站功能審查修復(hosts/rules合併+登入導向+TWGCB undefined+navMap+漢堡收合+bak清理)

## v3.7.1.0 — 2026-04-12
TWGCB 8項OS差異修正(RHEL/Debian:SELinux↔AppArmor,firewalld↔ufw,pwquality↔pam,grub2↔grub)+修復前自動備份+一鍵還原

## v3.7.0.0 — 2026-04-12
TWGCB擴充至120項(Linux60+Windows60) — 7+8分類完整合規檢查

## v3.6.1.0 — 2026-04-12
60項系統強化(HSTS+MongoDB索引6個+自動備份cron+bare except修正+error handler+vault權限+gitignore)

## v3.6.0.0 — 2026-04-12
UI圖示規範(導覽列+管理tab emoji)+全站搜尋+分類重整+Tunnel Web管理+Skill文件更新

## v3.5.1.0 — 2026-04-12
使用者管理(新增/編輯/刪除/角色切換)+API CRUD+oper訪客模式可瀏覽系統管理

## v3.5.0.0 — 2026-04-12
三級權限系統(oper唯讀/admin操作/superadmin全部)+未登入導覽列限制+變更按鈕權限檢查+Toast提示

## v3.4.2.0 — 2026-04-12
系統管理改名系統狀態+各主機服務控制面板(狀態/存活時間/啟停重啟)+確認Modal

## v3.4.1.0 — 2026-04-12
服務表格加入即時存活時間(透過Ansible遠端查詢systemctl)+API service-status

## v3.4.0.0 — 2026-04-12
RWD手機版(漢堡選單+768px/480px斷點+表格橫捲+卡片縮排)+Tunnel服務化+itagent整合tunnel

## v3.3.2.0 — 2026-04-12
服務控制vault修復+系統管理加itagent服務狀態+Cloudflare Tunnel外部存取

## v3.3.1.0 — 2026-04-12
服務控制按鈕(啟動/重啟/停止)+確認Modal+操作日誌+Linux systemctl+Windows PowerShell

## v3.3.0.0 — 2026-04-12
今日報告加入OS分類Tab(Linux/Win/AIX/AS400)+搜尋框+只顯示異常toggle

## v3.2.2.0 — 2026-04-12
修復Admin 403權限(superadmin角色)+主機管理補齊ansible-host+WIN保管者資料

## v3.2.1.0 — 2026-04-12
systemd服務管理(itagent-db+itagent-web)+itagent.sh管理腳本+開機自啟+環境變數集中管理+服務管理手冊

## v3.2.0.0 — 2026-04-12
CSS統一設計規範+帳號管理(修改密碼/忘記密碼/Email綁定)+commit備註

## v3.1.2.0 — 2026-04-11
Admin導覽改為下拉分類選單(系統維運/主機管理/合規安全/日誌紀錄)+主機管理改名伺服器清單

## v3.1.1.0 — 2026-04-11
開發後台加GitHub Pull+Flask重啟按鈕+導覽列開發後台連結+superadmin密碼修正

## v3.1.0.0 — 2026-04-11
超級管理員頁面(/superadmin)+GitHub一鍵推送+Git狀態顯示+引導式安裝腳本+README

## v3.0.1.0 — 2026-04-11
主機管理加系統別/級別(金銀銅)/AP負責人欄位(Modal+表格+API)

## v3.0.0.0 — 2026-04-11
TWGCB大改版-OS Tab分頁(Linux/Win/AIX/AS400)+只顯示異常toggle+Excel匯出匯入+級別篩選+分類摺疊

## v2.9.2.0 — 2026-04-11
TWGCB分類摺疊+Windows TWGCB 8項檢查(密碼/鎖定/稽核/防火牆/RDP)+全部展開收合按鈕

## v2.9.1.0 — 2026-04-11
TWGCB改為矩陣式表格(檢查項x主機)+系統別/AP負責人表頭+搜尋篩選+例外管理

## v2.9.0.0 — 2026-04-11
TWGCB改版為單機Excel式檢視+例外管理(紅綠橘三色燈號)

## v2.8.0.0 — 2026-04-11
單台主機強化管理(三步驟:備份→逐項強化→驗證+雙份備份local+ansible-host+一鍵還原)

## v2.7.0.0 — 2026-04-11
Example Corp真實Logo去背+系統改名Example Corp監控系統+TWGCB官方編號(TWGCB-01-008-xxxx)+管理介面TWGCB設定tab

## v2.6.0.0 — 2026-04-11
TWGCB報表(Example Corp抬頭+燈號矩陣+簽核欄+列印PDF)+設定管理(啟停/閾值/例外主機)

## v2.5.1.0 — 2026-04-11
TWGCB詳細改獨立頁面+8分類Excel表格+一鍵修復功能

## v2.5.0.0 — 2026-04-11
TWGCB合規報告(8項測試+Ansible role+API+UI三種檢視)

## v2.4.0.0 — 2026-04-11
資安修復(Vault加密+NoSQL防護+Debug關閉+SECRET_KEY隨機+API認證+登入鎖定+安全Headers+套件升級+檔案權限)

## v2.3.0.0 — 2026-04-11
SVG圖示庫(Dashboard KPI+OS統計+報告卡片+詳細報告區塊)

## v2.2.2.0 — 2026-04-11
修復異常總結API(Windows CPU小數值int轉換錯誤)+修復匯出CSV

## v2.2.1.0 — 2026-04-11
UI升級為examplesec.com.tw官網風格(暖灰白背景+青綠主色+左側色條KPI+大間距)

## v2.2.0.0 — 2026-04-11
UI美化(毛玻璃導覽+陰影層次+漸層按鈕+動畫+斑馬紋表格+進度條光澤)

## v2.1.1.0 — 2026-04-11
帳號盤點拉到獨立頁面/audit+修復CSV匯出+導覽列加入帳號盤點

## v2.1.0.0 — 2026-04-11
MongoDB Dump/Restore/Import/Download + Patch Web上傳/預覽/套用/回滾

## v2.0.0.0 — 2026-04-11
正式版打包(離線引導式安裝+MongoDB image+乾淨初始化)

## v1.9.1.0 — 2026-04-11
帳號盤點測試資料建立完成(Linux+Windows), HR對應正確, 19個帳號

## v1.9.0.0 — 2026-04-10
帳號盤點功能(密碼/登入稽核+風險標示+備註編輯+HR匯入+部門對應+CSV匯出)

## v1.8.0.0 — 2026-04-10
Windows SSH巡檢完成!全部role改用EncodedCommand, WIN-7L4JNM4P2KN測試通過

## v1.7.4.0 — 2026-04-10
Windows role全部改為SSH+PowerShell(不需WinRM)

## v1.7.3.0 — 2026-04-10
Dashboard加入OS數量統計(數字+百分比+進度條)

## v1.7.2.0 — 2026-04-10
Dashboard拿掉趨勢圖和甜甜圈圖+KPI加百分比數字

## v1.7.1.0 — 2026-04-10
Windows 2019 (<WIN_HOST>) 加入巡檢系統 via SSH

## v1.7.0.0 — 2026-04-10
SNMP監控(網路設備)+AS400監控+pysnmp/net-snmp-utils+主機管理加設備類型

## v1.6.0.0 — 2026-04-10
Windows監控支援(WinRM+8個role+Update/IIS/Defender/防火牆+前端Windows區塊)

## v1.5.1.0 — 2026-04-10
主機管理加入CSV匯入/JSON匯入/CSV匯出/範本下載+Skill補版號規範

## v1.5.0.0 — 2026-04-10
Admin系統完成(登入/系統狀態/設定/備份/排程/日誌/主機管理/告警/報告/操作紀錄)

## v1.4.3.0 — 2026-04-10
全部主機表格加入異常篩選開關(預設開啟)

## v1.4.2.0 — 2026-04-10
KPI卡片可點擊篩選查看對應狀態主機清單

## v1.4.1.0 — 2026-04-10
版本旁顯示更新日期時間

## v1.4.0.0 — 2026-04-10
FailLogin加入RawData明細+帳號鎖定狀態+解鎖指令

## v1.3.2.0 — 2026-04-10
今日報告卡片加入全部檢查項(Swap/IO/Load/Users/Uptime/FailLogin)+DISK改善+修復dashboard.js

## v1.3.1.0 — 2026-04-10
導覽列右上角新增版本號顯示

## v1.3.0.0 — 2026-04-10
新增6項系統檢查(Swap/IO/Load/Uptime/Users/FailLogin)+DISK顯示改善

## v1.2.0.0 — 2026-04-10
新增異常總結報告+磁碟多分區監控+修復5項缺失

## v1.1.0.0 — 2026-04-10
新增主機詳細報告+全部主機可點擊+圖表縮小

## v1.0.0.0 — 2026-04-09
初版建立 (Phase 1-4 完成)

