# 2026-04-23 15:05 — seed 套完 account_audit 還是空 — 3 步定位

13 上依序跑這三段，把每段輸出貼回來。

## Step 1 — 確認 seed_data.py 是新版

```bash
grep "account_audit: " /opt/inspection/webapp/seed_data.py | head -3
```

**預期** 看到：
```
    print(f"account_audit: {db.account_audit.count_documents({})} 筆 (累計)")
```

如果 grep 不到 → **你覆蓋失敗 / 覆蓋到錯路徑**，重覆 notes 14:59 的 cp 步驟。

---

## Step 2 — seed 完整輸出（看是哪個環節 0 筆）

```bash
cd /opt/inspection/webapp && sudo -u sysinfra python3 seed_data.py
```

**看這幾行**：
```
hosts: N 筆匯入/更新
inspections: N 筆匯入/更新     ← N > 0 代表有讀到 inspection JSON
account_audit: M 筆 (累計)     ← M = 0 代表 inspection JSON 裡沒 account_audit 資料
```

---

## Step 3 — 直接看 inspection JSON 有沒有 account_audit

```bash
sudo ls -t /opt/inspection/data/reports/inspection_*_SECSVR198-013T.json 2>/dev/null | head -1 | \
  xargs sudo cat 2>/dev/null | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception as e:
    print("❌ JSON parse fail:", e); sys.exit()
results = d.get("results", {})
print("results keys:", list(results.keys()))
acc = results.get("account_audit", None)
if acc is None:
    print("❌ results.account_audit 不存在 (role 沒跑 / 寫進其他 key)")
elif not isinstance(acc, list):
    print("❌ account_audit 不是 list, 型別:", type(acc).__name__)
elif len(acc) == 0:
    print("❌ account_audit 是空 list (role 跑但採集 0 筆)")
else:
    print("✅ account_audit 筆數:", len(acc))
    print("   第 1 筆:", json.dumps(acc[0], ensure_ascii=False)[:200])
'
```

---

## 判讀表

| Step 1 | Step 2 | Step 3 | 根因 | 下一步 |
|---|---|---|---|---|
| grep 不到 | N/A | N/A | 覆蓋失敗 | 重跑 cp 指令 |
| OK | `account_audit: 0 筆` | `❌ account_audit 是空 list` | role 跑了但採集不到 (shell 或 from_json parse fail) | debug role, 貼 site.yml PLAY RECAP 那台 ok= 多少 |
| OK | `account_audit: 0 筆` | `❌ account_audit 不存在` | site.yml 沒把 account_audit key 寫入 results | 看 site.yml host_result 定義 |
| OK | `account_audit: 0 筆` | `❌ JSON parse fail` | inspection JSON 有損 | 看 reports/ 最新檔大小 `ls -la` |
| OK | `account_audit: N 筆 (>0)` | `✅ 筆數 X` | 匯入成功, 剛剛沒 f5 page | 重整 /audit |

---

## 回傳

貼三段輸出給我，我看完立刻定位。
