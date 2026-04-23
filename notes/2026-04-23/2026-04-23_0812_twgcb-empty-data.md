# 2026-04-23 08:12 — TWGCB 矩陣細項空白診斷

## 背景

**症狀**：TWGCB 合規檢查頁面（`http://10.92.198.13:5000/twgcb`）上半部合規率、各主機比例顯示正常（83.7%），但下半部矩陣表（分類×主機燈號）**整片空白**，點分類行沒東西可展開。

**已確認**：
- Network tab 看到 `/api/twgcb/results?os_type=linux&fail_only=1` 回 `Content-Length: 69` → 等於空陣列 `{"success":true,"data":[],"total":0,...}`
- stats API 有資料（所以上半部合規率顯示正常）→ 代表 `twgcb_results` collection 非空
- 矛盾點：為何 stats 有資料但 results 過濾後空？

**最懷疑**：API 的 OS filter regex 沒 match 到 `twgcb_results.os` 欄位的實際字串。

---

## 要執行的測試

在公司 Win10 的瀏覽器，分別打開這兩個網址，把回傳的 **JSON 內容**貼回聊天（或截圖貼也可以）。

### 測試 A — 最寬（不帶 OS filter、不帶 fail_only）

```
http://10.92.198.13:5000/api/twgcb/results?limit=30
```

**重點看：**
- `total` 是多少？
- `data[0].os` 欄位是什麼字串？（例如 `"Linux"` / `"RHEL 9.6"` / `""` / `null`）
- `data[0].hostname` 是什麼？

### 測試 B — 只帶 OS filter

```
http://10.92.198.13:5000/api/twgcb/results?os_type=linux&limit=30
```

**重點看：** `total` 是多少？（跟 A 比）

---

## 判讀表

| 測試 A | 測試 B | 結論 | 下一步 |
|---|---|---|---|
| total=0 | total=0 | `twgcb_results` 被清空（但 stats API 有值矛盾） | 查 stats API 實際讀什麼 collection |
| total=2 | total=0 | ✅ **OS regex 沒 match `data[0].os`** | Claude 出 patch v3.11.7.0 修 regex / 修 playbook 寫入的 os 欄位 |
| total=2 | total=2 | OS filter OK，只 fail_only=1 壞 | 查 `checks.status` 欄位值、查 API line 114 `query["checks.status"]="FAIL"` |

---

## 回傳格式

你只需要做一件事：

**貼「測試 A 的 JSON」過來**。如果 JSON 太長可以只貼：
- 開頭的 `total`、`count` 那幾個欄位
- `data[0]` 的前幾行（特別是 `hostname`、`os`、`scan_time`）

Claude 一看到 `os` 欄位字串就知道怎麼改。

---

## 背景知識（供參考）

API 的 OS 過濾邏輯（`AI/webapp/routes/api_twgcb.py:103-111`）：

```python
if os_type == "linux":
    query["os"] = {"$regex": "(?i)(rocky|rhel|red hat|centos|debian|ubuntu|suse|oracle linux|linux)"}
```

如果 `os` 是空字串 `""` 或 `null`，regex 不會 match → 回空陣列。這是最常見的空矩陣原因。
