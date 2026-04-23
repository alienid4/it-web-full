# 2026-04-23 09:40 — 立刻清 twgcb 垃圾（Dashboard N/A 最後一哩）

## 為什麼 Dashboard 還是 N/A

從你貼的 JSON 看到 `cpu_percent: "100"`, `mem_percent: "49"` — **inspection JSON 裡已經有 CPU/MEM 資料**。

但 Dashboard 顯示 N/A，代表它讀到的是 **DB 裡的舊 twgcb 垃圾記錄**（`results:{}` 空），不是新 inspection。

## 一行指令（13 上跑）

```bash
mongosh inspection --quiet --eval 'const r = db.inspections.deleteMany({run_id: /^twgcb_/}); print("deleted:", r.deletedCount);'
```

**預期輸出**：`deleted: 2`（或更多）

跑完**立刻重整 Dashboard F5**，CPU / MEM 應該跳出數字。

## 驗證

打開：

```
http://10.92.198.13:5000/api/inspections/latest
```

檢查 `data[0].run_id`：
- ✅ 看起來像 `20260423_093030` 或 `inspection_20260423_093030`（時間戳格式）→ 正常
- ❌ 還是 `twgcb_SECSVR198-013T.json` → 清除沒生效，再跑一次 mongosh

## 回傳

1. `deleted: N` 的輸出
2. Dashboard 截圖（CPU/MEM 有沒有數字）

---

## 下一個要處理：CPU 顯示 100% 不對

你實測本機 vmstat `id=99/100`（idle 99~100%）→ 使用率應該 0~1%，但 JSON 寫 `cpu_percent: "100"` — 明顯錯。

根因推測：`vmstat 1 3 | tail -1 | awk '{print 100 - $15}'` 在某些環境 tail -1 抓到 header 行，$15 變字串 "st"，awk 數值運算當 0 → `100 - 0 = 100`。

治本方案（下個 patch v3.11.10.0 候選）：改用 `top -bn1 | grep "Cpu(s)" | awk -F'id,' '{split($1, a, ","); print 100 - a[length(a)]}'` 或 `mpstat 1 1` 穩定解析。

先解決 Dashboard N/A，CPU=100% 下一步再處理。
