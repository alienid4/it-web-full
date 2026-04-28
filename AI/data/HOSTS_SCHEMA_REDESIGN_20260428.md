# 主機清單 Schema 重新設計（吃進資產表 29 欄）

**狀態**: Draft v2, 2026-04-28
**目的**: 把使用者的 29 欄資產表 **直接塞進 `hosts` collection**，作為巡檢系統 ground truth。
**前提決策**: 不另開 `assets` collection — 一張表搞定（用戶決定）。

---

## 0. 設計原則

```
hosts collection
├── 資產表 29 欄 (你提供)              ← 新增
├── 巡檢專屬欄位 (ssh_*, nmon_*, ...)  ← 保留
└── 系統自動欄位 (created_at, ...)    ← 保留
```

非伺服器資產（iPad / 筆電 / 防火牆）的巡檢專屬欄位會是空，這沒問題：
- 巡檢只會 target `connection != ""` 且 `os in (Linux/Windows)` 的記錄
- iPad / 筆電不會被當 Ansible target，不會誤跑

---

## 1. 完整欄位清單

### 1.1 資產表 29 欄（新增）

**(2026-04-28 update: 改採 221 實際命名,5 個缺欄位用 ⭐ 標記)**

| # | 中文 | DB 欄位 | 型別 | 必填 | Enum / 範例 |
|---|---|---|---|---|---|
| 1 | 盤點單位-處別 | `division` | string | ✅ | "資訊管理處" |
| 2 | 盤點單位-部門 | `department` | string | ✅ | "資訊架構部" |
| 3 | 資產序號 | `asset_seq` | string unique | ✅ | "HW-00001001" |
| 4 | 資產狀態 | `status` | enum | ✅ | 使用中 / 停用 / 報廢 / 待退役 |
| 5 | 群組名稱 | `group_name` | enum | ✅ | H1~H9 (見資產表 9 類) |
| 6 | APID | `apid` | string | ⬜ | "巡檢測試環境" |
| 7 | 資產名稱 | `asset_name` | string | ✅ | "L-001" |
| 8 | 整體基礎架構 | `device_type` | enum | ✅ | "地端資產 (VM)" |
| 9 | 設備型號 ⭐**新增** | `device_model` | string | ⬜ | "VMware VM" / "Dell R740" |
| 10 | 資產用途 | `asset_usage` | string | ⬜ | "AP Server" |
| 11 | 資產實體位置 | `location` | string | ⬜ | "LAB機房" |
| 12 | 機櫃編號 ⭐**新增** | `rack_no` | string | ⬜ | "R12" |
| 13 | 數量 ⭐**新增** | `quantity` | int | ✅ default=1 | 1 |
| 14 | 擁有者 | `owner` | string | ✅ | "資訊架構部" |
| 15 | 環境別 | `environment` | enum | ✅ | OA / 正式 / UAT / 備援 / 測試 / DEV |
| 16 | 主機名稱 | `hostname` | string | ⬜* | "secansible" |
| 17 | 作業系統 | `os` | string | ⬜ | "Rocky Linux" / "Debian" |
| 18 | BIG IP/VIP | `bigip` | string | ⬜ | "無" / "VIP-10.1.1.100" |
| 19 | 硬體編號 ⭐**新增** | `hardware_seq` | string | ⬜ | "VM-98765" |
| 20 | IP | `ip` | string | ⬜ | "192.168.1.221" |
| 21 | 保管者 | `custodian` | string | ✅ | "林凱文" |
| 22 | 系統管理者 ⭐**新增** | `sys_admin` | string | ⬜ | "李大華" |
| 23 | 使用者 | `user` | string | ⬜ | "lab-admin" |
| 24 | 附加說明 | `note` | string text | ⬜ | "Rocky Linux 測試主機" |
| 25 | 所屬公司 | `company` | string | ✅ | "敦南總公司" |
| 26 | 機密性 | `confidentiality` | int 1-3 (1=高/2=中/3=低) | ✅ | 1 |
| 27 | 完整性 | `integrity` | int 1-3 | ✅ | 1 |
| 28 | 可用性 | `availability` | int 1-3 | ✅ | 1 |
| 29 | 申請單編號 | `request_no` | string | ✅ | "E000000000001" |

**221 額外有的欄位 (不在資產表 29 內,但保留)**:
- `infra` ("LAB測試環境")
- `user_unit` ("資訊架構部")
- `imported_at`, `updated_at`, `has_python`, `group` (legacy)
### 1.2 巡檢專屬欄位（保留，不動）

| DB 欄位 | 型別 | 用途 | 哪些資產會用 |
|---|---|---|---|
| `connection` | string | "ssh" / "local" / "winrm" | 伺服器類 |
| `ssh_user`, `ssh_port`, `ssh_key` | string/int | SSH 連線 | Linux/Win 伺服器 |
| `ssh_key_records` | dict | 多帳號 SSH key 部署紀錄 | 同上 |
| `nmon_enabled` | bool | 是否採 nmon | Linux 伺服器 |
| `nmon_interval_min` | int | 採樣頻率 | 同上 |
| `nmon_deployed_at`, `nmon_removed_at` | datetime | 部署紀錄 | 同上 |
| `tier` | enum 金/銀/銅 | 巡檢分級（不同於 CIA） | 業務系統相關 |
| `ap_owner` | string | AP 負責人 | 系統類 |
| `system_name` | string | 業務系統別 | 系統類 |
| `os_group` | string | rocky/debian/win/aix | 系統巡檢用 |

### 1.3 已存在但可能跟資產表衝突 ⚠️

| hosts 現有 | 資產表對應 | 處理 |
|---|---|---|
| `status` (使用中) | `status` | **保留 status，status 鏡像** 或 **改用 status，舊欄位 deprecated** |
| `department` | `department` | 同上抉擇 |
| `division` | `division` | 同上 |
| `note` | `note` (24) | 同欄位，OK |
| `os_group` (rocky/debian) | `group_name` (H6/H8/H9) | **語意不同，兩者並存** |

→ 衝突 4 處需決策（見第 5 節）。

---

## 2. Demo 資料 (3 筆 — 真主機)

### 2.1 secansible (192.168.1.221) — 巡檢主機

```json
{
  // 資產表 29 欄
  "asset_seq": "HW-00000221",
  "division": "資訊管理處",
  "department": "系統運維組",
  "status": "使用中",
  "group_name": "H9-伺服器",
  "apid": "AP-INSPECT",
  "asset_name": "巡檢系統主機",
  "device_type": "地端",
  "device_model": "VMware VM",
  "asset_usage": "AP 主機 / DB 主機",
  "location": "家裡實驗室",
  "rack_no": "N/A",
  "quantity": 1,
  "owner": "資訊管理處",
  "environment": "DEV",
  "hostname": "secansible",
  "os": "Debian 13",
  "bigip": "N/A",
  "hardware_seq": "VM-IDxxx",
  "ip": "192.168.1.221",
  "custodian": "Alienlee",
  "sys_admin": "Alienlee",
  "user": "資訊管理處",
  "note": "跑 Flask + Gunicorn + MongoDB + Cloudflared Tunnel",
  "company": "example-corp",
  "confidentiality": 2, "integrity": 1, "availability": 1,
  "request_no": "REQ-20260101001",
  // 巡檢系統: 完整性高 (1) + 可用性高 (1), 機密性中 (2)

  // 巡檢專屬
  "os_group": "debian",
  "connection": "local",
  "ssh_user": "sysinfra",
  "ssh_port": 22,
  "tier": "金",
  "ap_owner": "Alienlee",
  "system_name": "巡檢系統",
  "nmon_enabled": false
}
```

### 2.2 secclient1 (192.168.1.222) — Rocky 測試機

```json
{
  "asset_seq": "HW-00000222",
  "division": "資訊管理處",
  "department": "系統運維組",
  "status": "使用中",
  "group_name": "H9-伺服器",
  "asset_name": "受監控測試主機",
  "device_type": "地端",
  "asset_usage": "TWGCB / 巡檢驗證測試",
  "location": "家裡實驗室",
  "rack_no": "N/A",
  "quantity": 1,
  "owner": "資訊管理處",
  "environment": "DEV",
  "hostname": "secclient1",
  "os": "Rocky Linux 9.7",
  "ip": "192.168.1.222",
  "custodian": "Alienlee",
  "company": "example-corp",
  "confidentiality": 3, "integrity": 3, "availability": 3,
  "request_no": "REQ-20260101002",
  // 測試機: CIA 全低 (3)
  "os_group": "rocky",
  "connection": "ssh",
  "ssh_user": "sysinfra",
  "tier": "銅",
  "nmon_enabled": true
}
```

### 2.3 192.168.1.223 — 第三台（hostname **待你確認**）

```json
{
  "asset_seq": "HW-00000223",
  "asset_name": "受監控測試主機 (Debian)",
  "device_type": "地端",
  "group_name": "H9-伺服器",
  "status": "使用中",
  "environment": "DEV",
  "hostname": "sec9c2",
  "os": "Debian 13",
  "ip": "192.168.1.223",
  "custodian": "Alienlee",
  "company": "example-corp",
  "confidentiality": 3, "integrity": 3, "availability": 3,
  "request_no": "REQ-20260101003",
  // 測試機: CIA 全低 (3)
  "os_group": "debian",
  "connection": "ssh",
  "ssh_user": "sysinfra",
  "tier": "銅"
}
```

---

## 3. 衝擊分析

### 3.1 後端

| 檔案 | 改動 |
|---|---|
| `scripts/bootstrap.py` `seed_hosts` | 加 18 個新欄位的預設值 |
| `webapp/services/host_service.py`（新建） | CRUD + validate + ensure_indexes |
| `webapp/routes/api_admin.py` CSV 匯入 | 11 欄解析 → 29 欄解析 + enum 驗證 |
| `webapp/routes/api_admin.py` CSV 範本下載 | 重出 29 欄範本 |
| `scripts/generate_inventory.py` | 過濾 `connection != ""` 才入 inventory（防 iPad 被當 ansible target） |
| `scripts/onboard_new_host.sh` | Step 0 加新欄位最小值 |
| `scripts/migrate_hosts_add_29fields.py`（新建） | 一次性遷移既有 hosts 文件 |

### 3.2 前端

| 檔案 | 改動 |
|---|---|
| `webapp/templates/admin.html` 主機 tab | 表格欄位重排、Modal 重做 |
| `webapp/static/js/admin.js` 主機編輯 | 18 個新 input + enum 下拉 |
| 主機 tab 標題 | 「主機清單」→「資產主機清單」（A 方案）|
| 搜尋條 | 加 CIA / 環境別 / group_name 過濾 |

---

## 4. UI 改動（最小變動原則）

**保留使用者習慣**，UI 不大改：

| UI 元件 | 改動 |
|---|---|
| 主機清單表格 | **保留現狀，最多加 2-3 欄**（資產序號 / 環境別 / CIA）|
| 編輯 Modal | **必須擴充 18 個 input**（不擴充新欄位填不進去）|
| 搜尋條 | **加 3 個 filter**：環境別 / 群組名稱 / CIA |
| Tab 標題 | 不改名（仍叫「主機清單」） |
| CSV 匯入 / 範本 | **不做**（資產表由公司原系統維護，巡檢系統不參與）|
| 五區分頁 modal | **不做**（過度設計） |

→ 比原計畫**節省約 60% 工時**。

---

## 5. 待你決策（11 題）

| # | 問題 | 選項 | 我建議 |
|---|---|---|---|
| 1 | ~~CIA 三性怎麼存？~~ | ✅ **已決：int 1-3，且 1=高 / 2=中 / 3=低（反直覺，跟 P1/P2/P3 邏輯一樣）** | locked |
| 2 | 資產序號正則？ | 嚴格 `^HW-\d{8}$` / 自由格式 | **嚴格** |
| 3 | ~~資產狀態 enum~~ | ✅ **已決：使用中 / 停用 / 報廢 / 待退役** | locked |
| 4 | ~~群組名稱 enum~~ | ✅ **已決：H1~H9 共 9 類** | locked |
| 5 | ~~環境別 enum~~ | ✅ **已決：OA / 正式 / UAT / 備援 / 測試 / DEV** | locked |
| 6 | ~~整體基礎架構 enum~~ | ✅ **已決：「地端」一種（未來可加 雲端 / 混合）** | locked |
| 7 | `status` vs `status`？ | 並存 / 廢舊用新 | **(b) 用 status，遷移時把 status 值複製過去** |
| 8 | `department` vs `department`？ | 並存 / 廢舊用新 | **(b)** |
| 9 | `division` 同上 | 並存 / 廢舊用新 | **(b)** |
| 10 | `os_group` (rocky) vs `group_name` (H9)？ | 並存 (語意不同) | **並存** |
| 11 | ~~UI 改名「主機清單」→「資產主機清單」？~~ | ✅ **已決：不改名（保留使用者習慣）** | locked |

---

## 6. 下一步路線（精簡版）

| Step | 內容 | 預估版號 |
|---|---|---|
| 1 | **lock schema**（你決策第 5 節後 finalize）| - |
| 1.5 | 加 `get_hosts_col()` helper（49 處 → 1 處集中）| v3.14.2.0 |
| 2 | bootstrap.py + ensure_indexes 加 18 欄 + migration script | v3.15.0.0 |
| 3 | 編輯 Modal 加 18 欄 input（表格不動）| v3.15.1.0 |
| 4 | 搜尋條加 3 filter（環境別/群組名稱/CIA）| v3.15.2.0 |
| 5 | (選做) 表格加 2-3 欄關鍵資訊 | v3.15.3.0 |
| 6 | onboard_new_host.sh 加新欄位最小值 | v3.16.0.0 |
| 7 | dependency_systems 拓撲整合（asset_seq 顯示）| v3.17.0.0 |

**已砍掉**：CSV 匯入改造、五區 modal、UI 改名（節省 ~60% 工時）。

---

## 附錄：資產類型 → 適用欄位對照

| 資產類型 | 巡檢專屬欄位填寫? | 範例 |
|---|---|---|
| 伺服器 (Linux/Win) | ✅ 全填 (connection/ssh/nmon/tier) | 221/222/223 |
| VM | ✅ 同上 | F 列 (Azure-TW VM) |
| 網路設備 (FortiGate) | ⚠️ 部分 (connection 可能無) | E 列 |
| 防火牆設備 | ⚠️ 部分 | D 列 |
| 平板 (iPad) | ❌ 全空 | C 列 |
| 筆電 | ❌ 全空 | G 列 |

→ 主機清單 UI 應該支援「**只看伺服器類**」過濾（device_type in [伺服器, VM]）
