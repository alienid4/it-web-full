# 2026-04-23 17:01 — TWGCB 沒抓到 — 3 條診斷 + hot-fix

先貼結果不急著改 code。

## 3 條診斷（13 上依序跑）

```bash
# 1. reports/ 有沒有第 3 台的 twgcb JSON
echo "--- [1] twgcb JSON 檔 ---"
ls -la /opt/inspection/data/reports/twgcb_*.json

# 2. onboard 的 TWGCB 掃描 log 尾巴 (若 Step 4.5 有跑過才有)
echo ""
echo "--- [2] onboard TWGCB log ---"
ls -t /tmp/onboard_twgcb_*.log 2>/dev/null | head -1 | xargs -I{} bash -c 'echo "file: {}"; tail -30 {}'

# 3. Hot-fix: 直接呼叫 Python _import_results (繞過 HTTP login 擋)
echo ""
echo "--- [3] Python 直接 import ---"
cd /opt/inspection/webapp && sudo -u sysinfra python3 -c '
import sys
sys.path.insert(0, ".")
from routes.api_twgcb import _import_results
print("imported:", _import_results())
'
```

## 判讀

| [1] 結果 | [2] 結果 | [3] 結果 | 結論 |
|---|---|---|---|
| 有 3 個 twgcb_*.json | (不看) | `imported: 3` | ✅ hot-fix 解，刷 /twgcb 看第 3 台 |
| 只 2 個（缺新主機）| log 有 `FAILED` | `imported: 2` | Step 4.5 ansible-playbook 失敗, 看 log 找原因 |
| 只 2 個 | log 有 UNREACHABLE | `imported: 2` | 新主機 SSH 又有問題, 回 Step 3 驗 |
| 0 個 | 無 log 檔 | `imported: 0` | onboard 的 Step 4.5 根本沒執行到 |

## 貼這三段給我

1. `ls -la twgcb_*.json` 輸出 — 看檔案數 / 時間
2. `tail -30` onboard twgcb log — 若有
3. `imported: N` — N 是多少

我一看就能判斷：
- 只要 hot-fix 即可
- 還是 Step 4.5 根本跑失敗，要修 role / 權限 / ssh key
- 還是根本沒跑到（腳本某步提前 exit）

---

## 之後要不要出 v3.11.22.0

等你確認 hot-fix [3] 能讓 /twgcb 看到第 3 台後，我再做 v3.11.22.0：
- 修 onboard 的 TWGCB 匯入改用 Python 直呼（永久解 login 擋）
- UI 新增主機自動觸發全掃（你前面問過的）
