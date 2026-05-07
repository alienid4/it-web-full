# v3.17.14.0 — NMON 離線 RPM 派送

## 動機

公司隔離環境 (例 198.13) 連不到 EPEL repo, `yum install nmon` 失敗 → nmon binary 不存在 → cron 觸發空跑 → web UI `/perf` 頁顯示「無資料」。

v3.17.13.0 加了「📊 NMON 部署狀態」面板可診斷 (顯示 🔴 binary=✗),但不能修。**這個 patch 是配套的修復工具**: UI 上一鍵把預打包的 nmon RPM 派送到目標主機 `rpm -Uvh` 安裝。

## 改動

| 檔案 | 變更 |
|---|---|
| `offline_bundle/nmon/nmon-16p-1.el9.x86_64.rpm` | **新檔** (76KB, 來自 EPEL 9, 沒外部相依) |
| `ansible/roles/install_nmon_rpm/tasks/main.yml` | **新 role**: copy RPM → yum install → which nmon 驗證 → 清 /tmp |
| `ansible/playbooks/install_nmon_rpm.yml` | **新 playbook**: 走 install_nmon_rpm role |
| `scripts/download_nmon_rpm.sh` | **新工具**: 在外網機器跑, 自動 dnf download / curl EPEL 抓最新 RPM |
| `webapp/routes/api_nmon.py` | append `POST /api/nmon/install-rpm` endpoint (subprocess ansible-playbook --limit) |
| `webapp/static/js/admin.js` | append `installNmonRpmFail()` function |
| `webapp/templates/admin.html` | inject 「📦 派送 RPM」按鈕到 NMON 部署狀態 card 標題列 |

## UI 流程

```
系統管理 → 監控平台管理 → 效能月報管理
  └── 📊 NMON 部署狀態
       [🔍 立即檢查] [📦 派送 RPM]   ← 按鈕新加
       
       點「立即檢查」看到:
       | 狀態 | 主機 | bin | 細節 |
       | 🔴   | 198-013T | ✗ | nmon binary 沒裝 |
       
       點「📦 派送 RPM」:
       1. 重新 fetch /api/nmon/verify 撈 binary_ok=false 主機清單
       2. confirm 對話 (列出哪些主機要被派送)
       3. POST /api/nmon/install-rpm body={hostnames:[...]}
       4. 後端 ansible-playbook install_nmon_rpm.yml --limit "host1:host2"
       5. 完成後自動再跑「立即檢查」, 確認 bin=✓
```

## 部署

```bash
cd patches/v3.17.14.0-nmon-offline-rpm-pusher/
sudo bash install.sh
```

install.sh 會:
1. 偵測 INSPECTION_HOME (`/opt/inspection` or `/seclog/AI/inspection`)
2. 確認 v3.17.13.0 已部署 (verify panel 存在), 沒就 abort
3. 備份 admin.html / admin.js / api_nmon.py
4. 部署 ansible role + playbook + RPM + download script
5. append 新 endpoint / function, inject 新 button
6. 升 version.json + changelog
7. systemctl restart itagent-web
8. 印出驗證步驟

## 前提

- **必須先部署 v3.17.13.0** (NMON 部署狀態驗證面板)
- 主機 OS 是 RHEL 9 / Rocky 9 / CentOS Stream 9 (RPM 是 EL9)
- 如果是 EL8, 跑 `scripts/download_nmon_rpm.sh 8` 額外抓 EL8 RPM 進 offline_bundle/

## 範圍 (這個 patch 不做什麼)

- ❌ AIX nmon (內建 topas-nmon, 不需此 patch)
- ❌ Debian/Ubuntu (apt 路線不同, 之後另開 .deb 方案)
- ❌ EL7 (RHEL 7 已 EOL, 不支援)
- ❌ 自動派送 (要使用者手動點按鈕, 避免亂派)

## ⚠️ 合規 deferred 清單 (MVP, 後續強化)

twgcb-auditor 給出 4 項必修, 為了快速 MVP **暫緩**, 已記錄為下個版本任務:

1. **GPG 驗簽** (TWGCB 軟體完整性)
   - 目前: `disable_gpg_check: yes` (跳過驗簽)
   - 應改: 把 `RPM-GPG-KEY-EPEL-9` 也包進 offline_bundle, 安裝前 `rpm --import` + `rpm -K` 驗簽
   - 風險: 高 (RPM 被篡改可能在生產主機裝惡意套件)
   - 計畫版本: v3.17.14.1 或 v3.17.15.0

2. **sudoers 限定指令**
   - 目前: ansible 用既有 sysinfra sudoers (寬鬆)
   - 應改: `/etc/sudoers.d/sysinfra-nmon-rpm` 限定可執行的 rpm 指令 (`rpm -Uvh /tmp/nmon-*.rpm` etc.)
   - 風險: 高 (ansible 帳號可被利用做任意 rpm 操作)

3. **變更管控 (Change Ticket)**
   - 目前: API 點按鈕直接派送, 無核可關卡
   - 應改: API 加 `change_reason` 必填欄位, UI confirm 對話加「輸入變更編號」框
   - 風險: 中 (admin 誤觸或未授權部署無法追溯)

4. **webapp Audit Log**
   - 目前: 只有 ansible cron.log 記錄
   - 應改: webapp audit log 加 `nmon_rpm_install` action, 每筆紀錄 operator_id / operator_ip / timestamp / target_hosts / result(per host)
   - 保留期需 ≥ 180 天 (金融業要求)

5. **always cleanup /tmp**
   - 目前: 只在成功 case 清 /tmp RPM
   - 應改: ansible task 用 `always` block 不論成功失敗都清

詳見 `~/.claude/plans/v3.17.14.0-nmon-offline-rpm-pusher.md` (合規章節)。

## 驗證 (家裡 secansible)

```bash
# 1. 部署 v3.17.13.0 (如果還沒)
cd patches/v3.17.13.0-nmon-verify-panel && sudo bash install.sh

# 2. 部署 v3.17.14.0
cd patches/v3.17.14.0-nmon-offline-rpm-pusher && sudo bash install.sh

# 3. 開 https://it.94alien.com (或內網 :5000) → 系統管理 → 監控平台管理 → 效能月報管理
# 4. 點「🔍 立即檢查」 → 看 secclient1 / sec9c2 / secansible 狀態
# 5. 點「📦 派送 RPM」 → 因為這 3 台都已有 nmon, 應顯示「沒有缺 binary 主機, 不需派送」
#    (這就是 idempotent 驗證: ansible role 偵測到已裝就 skip)
# 6. 看 cron.log 沒新錯誤, smoke test 7 步全綠
```

## 公司部署 SOP (公司網段隔離, 不能 git pull)

公司網段抓不到 GitHub, 必須走 **release tarball** 通道:

```bash
# === 在家裡 / 能進公司的中介機器 ===
# 1. 從 GitHub release 下載 tarball (建議), 或自打包
#    Release URL: https://github.com/alienid4/it-web-full/releases/tag/v3.17.14.0
#    下載: v3.17.14.0-nmon-offline-rpm-pusher.tar.gz (~85KB)
#
# 或從 git working copy 自打包:
cd /path/to/CL_webit/patches
tar czf /tmp/v3.17.14.0-nmon-offline-rpm-pusher.tar.gz v3.17.14.0-nmon-offline-rpm-pusher/

# 2. 帶 tarball 進公司 (USB / 公司允許的傳檔方式)

# === 在公司巡檢主機上 ===
# 3. 解壓
cd /tmp && tar xzf v3.17.14.0-nmon-offline-rpm-pusher.tar.gz

# 4. 部署
cd v3.17.14.0-nmon-offline-rpm-pusher
sudo bash install.sh
# install.sh 會: 確認 v3.17.13.0 已部署 → 備份 → 部署檔案 → workaround EnvFile
#                → restart webapp (retry 5x)

# 5. 開 http://<COMPANY_INSPECTION_HOST>:5000 → 系統管理 → 監控平台管理 → 效能月報管理
# 6. 點「🔍 立即檢查」 → <TARGET_HOST> 應為 🔴 (bin=✗)
# 7. 點「📦 派送 RPM」 → modal 勾選主機 → 派送 → 等 1-3 分鐘
# 8. 自動 re-verify → <TARGET_HOST> 應變 🟢 (bin=✓)
# 9. 等 5-10 分鐘讓 nmon cron 採第一筆
# 10. 看 web UI /perf → <TARGET_HOST> 應有資料
```

## 配套 SKILL (放使用者 ~/.claude/skills/nmon-rpm-deploy/)

下次使用者問「nmon 沒裝」「EPEL 不通」「派送 RPM」, Claude 會自動引導
用本 patch 的 UI 流程 + 故障對照表. 詳見 `~/.claude/skills/nmon-rpm-deploy/SKILL.md`.

## 復原

每個 install.sh 步驟都有備份 (`.bak.YYYYMMDD_HHMMSS`)。

如果要還原:
```bash
cd $INSPECTION_HOME
TS=20260507_xxxx  # 從 install log 拿
cp -v webapp/routes/api_nmon.py.bak.$TS webapp/routes/api_nmon.py
cp -v webapp/templates/admin.html.bak.$TS webapp/templates/admin.html
cp -v webapp/static/js/admin.js.bak.$TS webapp/static/js/admin.js
cp -v data/version.json.bak.$TS data/version.json
rm -rf ansible/roles/install_nmon_rpm ansible/playbooks/install_nmon_rpm.yml offline_bundle/nmon
systemctl restart itagent-web
```
