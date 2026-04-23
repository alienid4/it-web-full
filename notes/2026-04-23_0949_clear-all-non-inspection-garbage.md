# 2026-04-23 09:49 — 清所有非 inspection 的垃圾記錄（含 packages_）

## 看到的真相

API `/api/inspections/latest` 回傳：

```json
"run_id": "packages_SECSVR198-011T.json"
"run_date": "pack-ag-"
"results": {}
```

**`packages_*.json` 也被舊 seed_data.py 誤匯**（`run_date="pack-ag-"` 從檔名硬切出來）。你前面只清了 `twgcb_` 那 2 筆，`packages_` 那 2 筆還在 DB，Dashboard 抓最新就抓到這筆 → `results:{}` → CPU N/A。

## 修復（3 步，13 上執行）

### Step 1 — 確認新 seed_data.py 已套用

```bash
grep "TS_RE" /opt/inspection/webapp/seed_data.py
```

**預期**：看到 `TS_RE = re.compile(r"^(?:inspection_)?\d{8}_\d{6}_")`

**如果 grep 不到任何東西** → 你還沒覆蓋新版，先按 [notes 0922](./2026-04-23_0922_run-inspection-download-and-place.md) 下載並覆蓋 `seed_data.py`。

### Step 2 — 清所有非 inspection 格式的垃圾

```bash
mongosh inspection --quiet --eval '
  const r = db.inspections.deleteMany({
    run_id: /^(twgcb_|packages_|network_|nmon_|security_audit_)/
  });
  print("deleted:", r.deletedCount);
'
```

**預期**：`deleted: 2`（或 4，因為 packages_ 兩筆 + 可能還有 network_ 等）。

### Step 3 — 重跑 seed_data.py（新版 glob 只讀真 inspection）

```bash
cd /opt/inspection/webapp && sudo -u sysinfra python3 seed_data.py
```

**預期輸出**：
```
hosts: 2 筆匯入/更新
inspections: N 筆匯入/更新    ← N 應該是實際 inspection_*.json 或舊 20260423_*.json 的檔數
settings: 匯入完成
```

### Step 4 — 驗 API

```
http://10.92.198.13:5000/api/inspections/latest
```

**預期**：
- `run_id` 是 `"20260423_093030"` 或 `"inspection_20260423_093030"`（時間戳開頭）
- `results.cpu.cpu_percent` 有值
- `run_date` 是 `"2026-04-23"`

### Step 5 — F5 Dashboard

應該看到 CPU / MEM 數字（雖然 CPU 可能顯示 100% — 那是另一個 vmstat bug，下個 patch 治本）。

---

## 回傳

1. Step 2 的 `deleted: N`
2. Step 3 的 `inspections: N 筆匯入/更新`
3. Step 4 的 API JSON 第一筆 `run_id` 長什麼樣
4. Dashboard 截圖

---

## 預防（下個 patch 候選）

`deleteMany` regex 名單未來可能漏掉新的非-inspection 前綴（例如以後加 `audit_` / `scan_` 等）。治本方向：改用**白名單**：`deleteMany({run_id: {$not: /^(inspection_|^\d{8}_\d{6}_)/}})`。v3.11.10.0 候選。
