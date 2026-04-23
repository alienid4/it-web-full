# 2026-04-23 10:38 — v3.11.11.0 修關閉模組報 "feature summary not found"

## 根因

`services/feature_flags.py` 的 `set_flag`:

```python
# 原本
r = col.update_one({"key": key}, {"$set": {"enabled": ...}}, upsert=False)
return r.matched_count > 0
```

`upsert=False` → DB 裡沒 `summary` 這筆時 `matched_count=0` → API 回 404 "feature summary not found"。

**歷史線索**：
- v3.10.0.0 首版 DEFAULT_FLAGS 只有 5 個（audit / packages / perf / twgcb / security_audit）
- 後續版本加入 `summary` 但 13 的 feature_flags collection 是舊版建的，沒這筆
- `list_flags()` 讀取時會補 default=True 回給 UI（所以 UI 看得到 summary 啟用中），**但沒寫回 DB**
- toggle 時 `set_flag` 找不到 DB 筆 → 404

`twgcb` / `perf` / `audit` 等可以正常切換（舊 DB 有這幾筆），只有 `summary`（後加的）會報錯。

## 治本

改 `set_flag`：對 `DEFAULT_FLAGS` 裡有定義的 key 用 `upsert=True` + `$setOnInsert` 自動補 name/description；非預設 key 維持原行為防亂建。

---

## 套用（13 上）

### Step 1 — 下載單檔

```
https://github.com/alienid4/it-web-full/raw/main/AI/webapp/services/feature_flags.py
```

### Step 2 — 覆蓋 + 重啟 Flask

```bash
sudo cp /opt/inspection/webapp/services/feature_flags.py \
        /opt/inspection/webapp/services/feature_flags.py.bak.$(date +%Y%m%d_%H%M)
sudo cp /tmp/feature_flags.py /opt/inspection/webapp/services/feature_flags.py
sudo chown sysinfra:itagent /opt/inspection/webapp/services/feature_flags.py
sudo systemctl restart itagent-web
```

### Step 3 — 驗證

打開 `/superadmin` → 模組管理 tab → 關閉 `summary`：

**預期**：不再跳 alert "feature summary not found"，checkbox 正常切換。

驗證 DB 有補齊：

```bash
mongosh inspection --quiet --eval '
  db.feature_flags.find({}, {_id:0, key:1, enabled:1}).toArray()
'
```

**預期**：看到 6 筆含 `{key:"summary", enabled:false}`。

### Step 4 — 順便確認其他模組

切換 `audit` / `packages` / `perf` 等（切 OFF 再 ON），應該都正常。

---

## 回傳

1. Step 3 的切換動作有沒有 alert
2. Step 3 的 mongosh find 輸出

---

## 附：目前版本總覽（今天累計）

| 版本 | 改什麼 |
|---|---|
| v3.11.7.0 | TWGCB 矩陣空白（OS regex 加 redhat） |
| v3.11.8.0 | seed_data.py 誤吃 twgcb JSON（regex 過濾） |
| v3.11.9.0 | inspection JSON 加 `inspection_` 前綴（治本） |
| v3.11.10.0 | CPU 固定 100%（vmstat → mpstat/top） |
| v3.11.11.0 | **feature_flags 關 summary 報 not found（upsert）** |
