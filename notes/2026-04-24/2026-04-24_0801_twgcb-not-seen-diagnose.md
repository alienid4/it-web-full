# 2026-04-24 08:01 — TWGCB 第 3 台沒抓到 — 3 條診斷

接續昨天 [2026-04-23_1701](../2026-04-23/2026-04-23_1701_twgcb-not-seen-debug.md) 的 TWGCB 問題。
**目的**：找出第 3 台主機的 TWGCB 資料為何在 UI 沒出現。

直接貼結果給我，我判讀要不要發 v3.11.23.0 hot-fix。

---

## 在 13 上依序跑（可一次全貼）

```bash
echo "========== [1] twgcb JSON 檔 =========="
ls -la /opt/inspection/data/reports/twgcb_*.json

echo ""
echo "========== [2] onboard TWGCB 掃描 log 尾巴 =========="
ls -t /tmp/onboard_twgcb_*.log 2>/dev/null | head -1 | xargs -I{} bash -c 'echo "file: {}"; tail -30 {}'

echo ""
echo "========== [3] Python 直接 _import_results (繞過 HTTP login) =========="
cd /opt/inspection/webapp && sudo -u sysinfra python3 -c '
import sys
sys.path.insert(0, ".")
from routes.api_twgcb import _import_results
print("imported:", _import_results())
'

echo ""
echo "========== [4] 現在 UI /twgcb 抓到幾台 =========="
mongosh inspection --quiet --eval '
  const hosts = db.twgcb_results.distinct("hostname");
  print("主機清單:", JSON.stringify(hosts));
  print("筆數:", db.twgcb_results.countDocuments({}));
'
```

---

## 判讀表（我看到結果會對照這張表）

| [1] JSON 檔數 | [2] onboard log | [3] imported: N | [4] UI 主機 | 結論 / 下一步 |
|---|---|---|---|---|
| 3 個 (含新主機) | (不看) | `imported: 3` | 3 台 | ✅ 一切正常；**重整 browser /twgcb** 看新主機是否顯示 |
| 3 個 | (不看) | `imported: 3` | 2 台 | ⚠️ 匯入成功但 UI cache / feature_flag 問題 → 刷新 + 檢查 feature_flags |
| 3 個 | (不看) | `imported: 2` | 2 台 | ⚠️ _import_results 有 bug（regex 不 match 新主機 hostname）→ 發 v3.11.23.0 修 import |
| 只 2 個 | log 有 `FAILED` | `imported: 2` | 2 台 | ❌ onboard Step 4.5 ansible playbook 失敗 → 看 log 找 role / 權限原因 |
| 只 2 個 | log 有 `UNREACHABLE` | `imported: 2` | 2 台 | ❌ 新主機 SSH 不通 → 回 onboard Step 3 驗 ssh key |
| 0 個 | 無 log 檔 | `imported: 0` | ? | ❌ onboard 的 Step 4.5 根本沒執行 → 查 onboard_new_host.sh 是否走到 Step 4.5 |

---

## 回貼給我哪三段？

1. `[1]` 的 `ls -la` 輸出 — 看檔案數 / 時間
2. `[2]` 的 `tail -30` onboard twgcb log — 若有
3. `[3]` 的 `imported: N` — N 是多少
4. `[4]` 的 hosts 清單 — 主機清單 + 筆數

我一看判讀表就知道：hot-fix 就夠、還是要修 onboard / SSH key。

---

## 參考：v3.11.22.0 已在家裡 221 驗證 (sec client1 端到端跑通)

v3.11.22.0 深度檢查功能還沒套到 13。等 TWGCB 這邊修好，再決定先套 22 還是一起打 combo。
