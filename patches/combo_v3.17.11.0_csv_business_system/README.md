# v3.17.11.0 — hosts CSV 加「業務系統」欄,自動同步 dependency_systems

## Why

debug_topology.sh v2 在 13 上跑出 3 個 [FAIL]，**根因 = `dependency_systems` 是空的**：

- 採集連線都採到了 (ansible 跑 `ss -tunp` OK)
- 但反查鏈 `IP → hostname → host_refs → system_id` 斷在最後一節 (沒任何 system 包住主機)
- 所以 dep_rel 永遠 0，拓撲畫不出

之前要使用者手動在 admin 拓撲管理 tab 一個個建 system + 綁主機，500 台規模做不來。

## What

把「業務系統歸屬」搬到資產表 single source of truth：

- `hosts.csv` 加 **業務系統** 欄（= 資產表的「資產名稱」，例：自動避險 / SPEEDY / Mantis 等中文業務系統名）
- import 結束後 webapp 自動同步 `dependency_systems`：建/更新/搬移 host_refs
- 業務系統改名 / 主機改歸屬 / 新主機，重 import CSV 一次 → dep_sys 自動跟著對齊

## 對映

| 資產表欄 | dependency_systems 對映 |
|---|---|
| **資產名稱** (自動避險, SPEEDY...) | **system_id = display_name** (中文當 PK) |
| **主機名稱** | host_refs[] |
| APID (N-008 等) | metadata.apid (輔助查詢) |
| 群組名稱 (H2-/H4-/H9-) | metadata.group |
| 整體基礎架構 (地端/雲端) | metadata.infra |
| 部門 | owner |

> APID 不能當業務系統 PK——資產表已驗證 N-008 同一個值對到「自動避險／SPEEDY／新權證帳務系統」三個不同業務系統，APID 是某種分類碼不是業務識別。

## 改動範圍

| 檔案 | 動作 | 細節 |
|---|---|---|
| webapp/services/dependency_service.py | **新增 helper** | `sync_systems_from_hosts(rows, source, actor)` — build/update/move 邏輯;主機改系統時舊 system 自動 `$pull` host_refs |
| webapp/routes/api_admin.py | **改 4 處** | import_csv 解析「業務系統」欄 + 呼叫 helper; export_csv / template_csv / template_xlsx 加欄 |

## 驗證

5 case mock test 本機通過：

1. 第一次 import 4 台主機建 2 個業務系統
2. 重 import 同樣資料 host_refs 不重複
3. 主機改系統時舊 system.host_refs 自動移除
4. hostname / system_id 空值跳過
5. 中文 PK (URL encoded) 撈得回來

## 部署 (公司 13 / 11 / 家裡 221 通用)

```bash
gh release download v3.17.11.0 -p '*.tar.gz' -O /tmp/p.tar.gz
cd /tmp && tar -xzf p.tar.gz
cd combo_v3.17.11.0_csv_business_system && sudo bash install.sh
```

## 部署後操作步驟

```
1. /admin → 主機管理 → 下載 CSV/XLSX 新範本 (應有「業務系統」欄)
2. 在「業務系統」欄填上每台主機的歸屬 (中文,如「巡檢系統」/「自動避險」)
3. 重 import CSV → 看 admin 提示「同步業務系統 +N/~M/移動 K」
4. /dependencies 應該看到拓撲節點 (顯示業務系統名)
5. 點「📡 採集」→ 等 1-3 分點「📊 狀態」→ edges_added 應 > 0
6. (可選) 跑 debug_topology.sh 看 10. host_refs 反查 全綠
```

## 不會破壞舊環境

CSV 沒帶「業務系統」欄 → 跳過同步 (sync_rows 是空 list)，舊 import 行為完全相容。
