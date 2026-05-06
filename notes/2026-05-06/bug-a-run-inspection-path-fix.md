# Bug A: run_inspection.sh 路徑寫死修復 SOP

> 紀錄日期: 2026-05-06
> 紀錄組: notes-writer subagent
> 此檔已範例化, 真實主機名 / IP 已替換

---

## 背景

- **時間**: 2026-05-06 下午
- **發現管道**: 家裡 secansible (192.168.1.x 段) 上 web UI 觀察 [公司主機 A] 的 nmon 資料,
  發現 dashboard 無任何資料更新
- **追查結果**: secansible 上的巡檢 cron 從 2026-04-23 起連續 13 天跑死,
  囤積了大量 .nmon 檔未匯入 MongoDB

---

## 根因分析

| 項目 | 說明 |
|---|---|
| 問題腳本 | `/seclog/AI/inspection/run_inspection.sh` |
| 問題行號 | 第 5 行 |
| 錯誤寫法 | `INSPECTION_HOME="/opt/inspection"` (硬編碼絕對路徑) |
| 實際安裝位置 | `/seclog/AI/inspection` |
| 失敗點 | cron 跑到 `cd "${ANSIBLE_DIR}"` 時目錄不存在 → `exit 1` |
| 連帶問題 | 第 32 / 43 / 75 行的 `--vault-password-file /opt/inspection/.vault_pass` 同樣寫死路徑 |

**失敗鏈**: cron 觸發 → `INSPECTION_HOME` 指向不存在的路徑 → `cd` 失敗 → 腳本 exit 1
→ ansible-playbook 未執行 → .nmon 檔持續累積未匯入

---

## 修法

### 第 5 行: 動態偵測腳本所在目錄

```bash
# 修改前
INSPECTION_HOME="/opt/inspection"

# 修改後
INSPECTION_HOME="${INSPECTION_HOME:-$(cd "$(dirname "$0")" && pwd)}"
```

說明:
- `$(dirname "$0")` 取得腳本自身所在目錄
- `${VAR:-default}` 語法讓外部環境變數可以 override (彈性部署)
- 腳本搬到任何路徑都能自動適應

### 第 32 / 43 / 75 行: vault 密碼檔路徑改用變數

```bash
# 修改前
--vault-password-file /opt/inspection/.vault_pass

# 修改後
--vault-password-file "${INSPECTION_HOME}/.vault_pass"
```

---

## 驗證結果

1. 手動跑一次 `run_inspection.sh`
2. ansible-playbook 正常跑通
3. nmon 匯入輸出:
   ```
   [nmon] scanned=2302 imported=2302 failed=0
   ```
4. 13 天囤積的 .nmon 檔全數成功補進 MongoDB
5. web UI dashboard 恢復顯示資料

---

## 同步改動

- 正式安裝路徑 `/seclog/AI/inspection/run_inspection.sh` 已手動修改 (共 4 處)
- git repo `AI/run_inspection.sh` 也同步修改 (共 5 處)
- **尚未 commit** — 等 v3.17.14.0 patch 一起進版控

---

## 教訓 / 預防規則

1. **任何 shell script 禁止寫死絕對路徑**
2. 標準模式: `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`
3. 即使當下「只會裝在這個路徑」也不行 — 早晚會被搬路徑
4. 需要 override 彈性時用 `${VAR:-default}` 語法
5. 新增巡檢 cron 後, 建議加監控: 若連續 N 天無匯入記錄則告警

---

## 受影響主機

- [公司主機 A] (生產環境, 內網 [公司網段])
- secansible (管理節點, 家裡 192.168.1.x 段可連)

> 實際主機名與 IP 請查閱 ~/.inspection.local 或 inventory 設定檔
