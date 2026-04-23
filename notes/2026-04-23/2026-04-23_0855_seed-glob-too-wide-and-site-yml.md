# 2026-04-23 08:55 — seed_data.py glob 誤吃 twgcb JSON + site.yml 沒產 inspection 檔

## 根因（兩層）

### 1. seed_data.py glob 太寬

```python
# 原本（錯）
pattern = "data/reports/*_*.json"   # 任何含 _ 的 JSON 都吃
```

reports/ 底下實際只有 `twgcb_*.json` 這種（site.yml 沒真的產 inspection 檔），seed_data.py 就**把 twgcb JSON 當 inspection 匯入**：

- `twgcb_SECSVR198-013T.json` 被當 inspection
- 檔名拆解：`ts="twgcb_SECSVR198-013T"` → `ts[:4]="twgc"`, `ts[4:6]="b_"`, `ts[6:8]="SE"`
- `run_date = "twgc-b_-SE"` ← 和你截圖 API 回傳完全對上
- `run_time = "SV:R1:98"` ← 對上
- twgcb JSON 沒 `results` 欄位（它用 `checks`）→ `results: {}` → Dashboard 讀 CPU/MEM 都是空

### 2. site.yml 沒真的跑完 → 沒產 inspection JSON

`/opt/inspection/data/reports/` 底下**沒有** `YYYYMMDD_HHMMSS_hostname.json` 這種檔（第 2 項查詢無資料確認）。

**你昨天看到的 PuTTY 終端 `ok=7 changed=1` PLAY RECAP 其實是 collect_packages 的**（在 site.yml 之後跑），不是 site.yml 本身。site.yml 真正的輸出往上翻才有。

可能的失敗點（待 log 確認）：
- 某個 role 失敗沒 register 變數 → 後面 post_tasks 套用 `| default({})` 都變空
- post_tasks 的「儲存主機巡檢 JSON」被 skip
- role 在 13 self 上有 `delegate_to` 問題

---

## 修復步驟（13 上執行）

### Step 1：下載修好的 seed_data.py

在公司 Win10 瀏覽器打開右鍵另存：

```
https://github.com/alienid4/it-web-full/raw/main/AI/webapp/seed_data.py
```

scp 到 13 的 `/tmp/`。

### Step 2：覆蓋 + 清掉壞資料 + 重匯

```bash
# 備份 + 覆蓋
sudo cp /opt/inspection/webapp/seed_data.py /opt/inspection/webapp/seed_data.py.bak.$(date +%Y%m%d_%H%M)
sudo cp /tmp/seed_data.py /opt/inspection/webapp/seed_data.py
sudo chown sysinfra:itagent /opt/inspection/webapp/seed_data.py

# 清掉被誤匯的 twgcb 垃圾資料（run_id 以 twgcb_ 開頭的那些）
mongosh inspection --quiet --eval '
  const r = db.inspections.deleteMany({run_id: /^twgcb_/});
  print("deleted:", r.deletedCount);
'

# 重跑 seed_data（不需重跑 ansible）
cd /opt/inspection/webapp && sudo -u sysinfra python3 seed_data.py
```

**預期輸出**：
```
hosts: 2 筆匯入/更新
inspections: 0 筆匯入/更新     ← 因為 reports/ 根本沒 inspection JSON
settings: 匯入完成
```

### Step 3：確認 API 回傳乾淨

```
http://10.92.198.13:5000/api/inspections/latest
```

**預期**：`{"success":true,"data":[],"count":0}`（乾淨的空，沒再亂丟 twgcb 資料）。

Dashboard 這時會正式變成「無資料」狀態（-%），但至少**不再亂顯示**。

---

## Step 4：追 site.yml 為何沒產檔（貼 log）

在 13 執行：

```bash
# 看最近一次 run log
sudo ls -t /opt/inspection/logs/*run.log | head -1 | xargs sudo cat | head -300
```

重點看 **site.yml 的 PLAY RECAP**（**不是** collect_packages 那個）：

```
PLAY RECAP *********
SECSVR198-013T : ok=?? changed=?? unreachable=?? failed=?? skipped=??
```

**貼那段 PLAY RECAP 加前面 20 行**（有 PLAY 名稱），我就能判斷：
- 如果 ok=10+ 但沒產 JSON → post_tasks 的 copy step 有問題
- 如果 failed > 0 → 某 role 掛了，貼失敗訊息
- 如果 skipped 很多 → role condition 沒符合（例如 windows role 在 linux 上 skip 正常，但 check_cpu 不該 skip）

---

## 回傳格式

三段：

1. **Step 2 的 mongosh 輸出**（deleted 幾筆）
2. **Step 2 的 seed_data.py 輸出**（inspections: X 筆）
3. **Step 4 的 site.yml PLAY RECAP + 有任何 FAILED/fatal 訊息**
