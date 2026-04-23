# 2026-04-23 09:05 — Dashboard CPU 無資料 最終修法（取代 0846 / 0855 兩份）

## 更新：site.yml 其實跑成功了

從你 PuTTY 截圖確認：

```
PLAY RECAP
SECSVR198-011T : ok=77 changed=1 ...
SECSVR198-013T : ok=81 changed=2 ...
===== 巡檢完成 exit=0 =====
"Report: /opt/inspection/data/reports/202604..."
```

- ✅ site.yml 跑完 `exit=0`
- ✅ inspection JSON 已產，檔名格式 `20260423_084220_SECSVR198-013T.json`（**時間戳前綴，不是 inspection_ 前綴** — 我昨天 notes 寫的 `ls inspection_*.json` 查法錯了，所以你才會以為沒產檔）

## 唯一根因

**`seed_data.py` glob 太寬**：

```python
# 原本：data/reports/*_*.json （任何含 _ 的都吃）
# 所以 twgcb_SECSVR198-013T.json 也被當 inspection 匯入
```

reports/ 底下同時有：
- `20260423_084220_SECSVR198-013T.json` ← 真 inspection
- `twgcb_SECSVR198-013T.json` ← TWGCB 掃描結果

兩種都被匯進 `inspections` collection → 13 筆裡混著真資料和垃圾 → Dashboard 抓最新 per host 時剛好抓到 twgcb 那筆（`results:{}`）→ CPU 顯示 -%。

**修法**：glob 改成只接受 `YYYYMMDD_HHMMSS_` 開頭檔名（真 inspection 才符合）。已 commit 到 main。

---

## 修復步驟（13 上執行）

### Step 1 — 下載修好的 seed_data.py

在公司 Win10 瀏覽器右鍵另存：

```
https://github.com/alienid4/it-web-full/raw/main/AI/webapp/seed_data.py
```

scp / USB 搬到 13 的 `/tmp/`。

### Step 2 — 覆蓋 + 清 twgcb 垃圾 + 重跑 seed

```bash
# 備份 + 覆蓋
sudo cp /opt/inspection/webapp/seed_data.py \
        /opt/inspection/webapp/seed_data.py.bak.$(date +%Y%m%d_%H%M)
sudo cp /tmp/seed_data.py /opt/inspection/webapp/seed_data.py
sudo chown sysinfra:itagent /opt/inspection/webapp/seed_data.py

# 清掉被誤匯的 twgcb 垃圾
mongosh inspection --quiet --eval '
  const r = db.inspections.deleteMany({run_id: /^twgcb_/});
  print("deleted:", r.deletedCount);
'

# 重跑 seed_data（會從 reports/ 讀真 inspection JSON 重匯）
cd /opt/inspection/webapp && sudo -u sysinfra python3 seed_data.py
```

**預期輸出**：
```
hosts: 2 筆匯入/更新
inspections: N 筆匯入/更新     ← N 應該是真實 inspection 檔數（可能 2 筆以上）
settings: 匯入完成
```

### Step 3 — 驗證

```
http://10.92.198.13:5000/api/inspections/latest
```

**預期**：
- `data[0].run_id` 是 `"20260423_084220"` 這種時間戳（**不再是 `twgcb_...`**）
- `data[0].results.cpu` / `results.disk` / `results.service` 有實際內容
- `data[0].run_date` 是正常日期 `"2026-04-23"`（不再是 `"twgc-b_-SE"`）

然後打開 Dashboard（`http://10.92.198.13:5000/`），**CPU / MEM / Disk / Swap 數字應該都跑出來**。

---

## 快速 rollback（如果出錯）

```bash
sudo cp /opt/inspection/webapp/seed_data.py.bak.<時間戳> \
        /opt/inspection/webapp/seed_data.py
sudo -u sysinfra python3 /opt/inspection/webapp/seed_data.py
```

---

## 回傳格式

3 段：

1. **mongosh deleted 幾筆**（Step 2 的 `print("deleted:", r.deletedCount)` 輸出）
2. **seed_data.py 最終輸出**（Step 2 最後一行，inspections: N 筆）
3. **Dashboard 截圖**（Step 3 驗證，CPU/MEM 有沒有數字出來）

如果 Dashboard 仍然 -%，貼 Step 3 的 API JSON 前 30 行，我再看是 Dashboard 前端 render bug 還是資料還有問題。
