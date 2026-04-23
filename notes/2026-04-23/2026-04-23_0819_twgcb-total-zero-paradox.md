# 2026-04-23 08:19 — TWGCB total=0 但上半部 83.7% 矛盾

## 上一輪結果

測試 A `/api/twgcb/results?limit=30` 回 **total=0**。

這跟上半部 UI 顯示合規率 83.7%（兩台都 83.7%）**矛盾**，因為 83.7% 一定要有資料才算得出來。

## 本輪要查什麼

釐清是：
- **情境 1**：`twgcb_results` collection 整個空 → 83.7% 來自 demo/殘留，掃描結果沒寫進 DB（**playbook 成功但 import 失敗**）
- **情境 2**：DB 有資料，只有 `/api/twgcb/results` endpoint 自身 bug（filter 邏輯把文件吃掉）

---

## 要執行的測試

打開這兩個網址，回報 JSON 開頭幾行：

### 測試 C — summary API

```
http://10.92.198.13:5000/api/twgcb/summary
```

**看：** `total_hosts`、`compliance_rate`

### 測試 D — stats API

```
http://10.92.198.13:5000/api/twgcb/stats
```

**看：** `overall.host_count`、`overall.rate`、`by_host` 的筆數

---

## 判讀表

| C.total_hosts | D.overall.host_count | 結論 | Claude 下一步 |
|---|---|---|---|
| 2 | 2 | ✅ DB 有 2 台 → `/api/twgcb/results` endpoint 有 bug | 查 results endpoint 哪段 query 把全部過濾掉 |
| 0 | 0 | DB 真的空，83.7% 來源要找 | 查 `reports/twgcb_*.json` 是否存在、import 是否失敗 |
| 0 | 有資料 | stats 讀別的 collection（cache？） | 查 stats API 實作、source of truth |
| 2 | 0 | 不合理 | 重新確認 |

---

## 情境 2 的備案：如果 summary 也回 0

再打這個 URL 看掃描結果檔有沒有存在：

```
http://10.92.198.13:5000/api/twgcb/import
```

⚠ 注意：這是 POST endpoint，直接 GET 會回 405。**改用以下方式測試**——打開 F12 → Console → 貼：

```js
fetch("/api/twgcb/import", {method:"POST"}).then(r=>r.json()).then(j=>console.log(j))
```

回傳會像：
- `{"success":true,"message":"匯入 2 台主機結果"}` → reports 檔有 2 份 JSON，import 機制 OK，重跑後資料就會進 DB
- `{"success":true,"message":"匯入 0 台主機結果"}` → reports/ 裡沒 JSON 檔（playbook 沒真的產出 / 產到別處 / 權限讀不到）

---

## 回傳格式

貼兩段：

1. **測試 C** 的 JSON（前 10 行即可）
2. **測試 D** 的 JSON 開頭（特別是 `overall` 區塊）

如果第 1 項 total_hosts=0，**再跑情境 2 的備案**貼第 3 段結果。
