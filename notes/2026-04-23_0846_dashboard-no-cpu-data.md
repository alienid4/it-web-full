# 2026-04-23 08:46 — 跑完 run_inspection 但 Dashboard CPU/MEM 還是 -% 診斷

## 背景

使用者已跑 `run_inspection.sh`，但 Dashboard 上 CPU/MEM/Disk/Swap 還是顯示 -%（沒資料）。

⚠ 先更正：正確路徑是 `/opt/inspection/run_inspection.sh`（**不是** `/opt/inspection/scripts/run_inspection.sh`）。如果你剛才跑的路徑錯了，這邊會沒執行到。

## 流程複習

```
/opt/inspection/run_inspection.sh
  ↓
1. ansible-playbook site.yml                   → 產 /opt/inspection/data/reports/inspection_*.json
2. python3 webapp/seed_data.py                 → 讀 reports/ 匯入 MongoDB inspections collection
3. packages_service.import_packages_from_reports → 套件
4. cio_service.snapshot_twgcb_daily           → CIO 合規快照
  ↓
Dashboard /api/inspections/latest → 讀 inspections collection → 顯示
```

**任一環節失敗** → Dashboard 沒數字。

## 要查的 3 件事（13 上執行）

### 1. log 尾巴（確認哪一步失敗）

```bash
sudo ls -t /opt/inspection/logs/*run.log | head -1 | xargs sudo tail -80
```

重點看：
- 有沒有 `ansible-playbook ... failed` / `UNREACHABLE`？
- 有沒有 `seed_data.py ... Error` / `ModuleNotFoundError`？
- 結尾的 `exit=0` 還是 `exit=非 0`？

### 2. reports 目錄（確認 ansible 有沒有產檔）

```bash
sudo ls -lt /opt/inspection/data/reports/inspection_*.json 2>/dev/null | head -5
```

重點看：
- 有沒有 `inspection_SECSVR198-013T_*.json` 這樣的檔案
- 檔案時間是不是剛剛（跑完之後）

如果一個都沒有 → site.yml 整個沒跑成功。
如果有但時間很舊（昨天以前）→ 剛才跑的 site.yml 失敗了。

### 3. 直接看 MongoDB 有沒有資料

打 API（需先登入網站，讓瀏覽器帶 session cookie）：

```
http://10.92.198.13:5000/api/inspections/latest
```

回傳：
- `{"success":true,"data":[],"count":0}` → DB 空（seed_data.py 沒匯入）
- `{"success":true,"data":[{...}],"count":2}` → DB 有資料（**問題在前端 Dashboard 渲染**，不是後端）

---

## 判讀表

| log 結尾 | reports | API latest | 下一步 |
|---|---|---|---|
| `exit=0`，OK | 有新檔 | count=2 | **後端 OK，Dashboard 前端顯示 bug** — 查 dashboard.js 怎麼畫 CPU |
| `exit=0` | 有新檔 | count=0 | seed_data.py 沒把 reports 寫進 DB — 查 seed_data.py log |
| 有 `UNREACHABLE` / `failed` | 無新檔 | count=0 | ansible 連不到 host — 查 ssh / sudo 權限 |
| `command not found` / path 錯 | 無新檔 | count=0 | 你剛才跑的路徑可能是 `/opt/inspection/scripts/run_inspection.sh`（不存在）— 重跑 `sudo -u sysinfra /opt/inspection/run_inspection.sh` |

---

## 回傳格式

貼三段：

1. **log 尾巴**（指令 1 的輸出最後 30 行）
2. **reports 列表**（指令 2 的輸出）
3. **API latest**（網址 3 的 JSON）

Claude 看到這三樣就能定位是哪一環卡住。
