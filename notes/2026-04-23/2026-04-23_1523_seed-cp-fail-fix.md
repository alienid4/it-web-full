# 2026-04-23 15:23 — seed_data.py 覆蓋失敗 — 1 條指令定位 + 修

## 已知

Step 1 `grep "account_audit: "` 結果空 → **目的地還是舊版 seed_data.py**，cp 沒真正覆蓋到。

## 診斷（貼輸出）

```bash
echo "--- A. /tmp/seed_data.py 來源檔 ---" && ls -la /tmp/seed_data.py 2>&1
echo "--- B. /tmp 來源是否含新版標記 ---" && grep -c "account_audit: " /tmp/seed_data.py 2>&1
echo "--- C. /opt/inspection 目的地是否含新版標記 ---" && grep -c "account_audit: " /opt/inspection/webapp/seed_data.py
```

---

## 情境 A — `/tmp/seed_data.py` 不存在 or B 顯示 0

你根本沒下載到新版（或下載到 GitHub 網頁 HTML 而非 raw）。

### 修法：強制用 curl 下載 raw URL

```bash
curl -L -o /tmp/seed_data.py \
  https://github.com/alienid4/it-web-full/raw/main/AI/webapp/seed_data.py

# 驗證: 應該 >= 1 (新版標記)
grep -c "account_audit: " /tmp/seed_data.py
```

如果 `curl` 在 13 被擋（例如公司 proxy），改走 v3.11.17.0 tarball：

```bash
curl -L -o /tmp/patch_v3.11.17.0.tar.gz \
  https://github.com/alienid4/it-web-full/releases/download/v3.11.17.0/patch_v3.11.17.0.tar.gz
cd /tmp && tar xzf patch_v3.11.17.0.tar.gz
cp /tmp/v3.11.17.0/files/webapp/seed_data.py /tmp/seed_data.py
grep -c "account_audit: " /tmp/seed_data.py
```

---

## 情境 B — A/B 都 OK，C 還是 0

源頭沒問題，但 cp 沒跑到或被擋。重跑 cp：

```bash
sudo cp /tmp/seed_data.py /opt/inspection/webapp/seed_data.py
sudo chown sysinfra:itagent /opt/inspection/webapp/seed_data.py

# 驗證
grep -c "account_audit: " /opt/inspection/webapp/seed_data.py   # 應該 >= 1
stat /opt/inspection/webapp/seed_data.py | grep Modify          # 看檔案時間 = 今天
```

---

## 完成後重跑 seed

目的地確認是新版後：

```bash
cd /opt/inspection/webapp && sudo -u sysinfra python3 seed_data.py
```

**預期輸出**（關鍵是第 3 行）：
```
hosts: 2 筆匯入/更新
inspections: N 筆匯入/更新
account_audit: M 筆 (累計)    ← ✅ 有這行 + M > 0
settings: 匯入完成
```

---

## 最後驗證

```bash
mongosh inspection --quiet --eval '
  const r = db.account_audit.findOne({user:"root"});
  print(r ? "✅ root uid="+r.uid+" gid="+r.gid : "❌ 找不到 root");
  print("總筆數:", db.account_audit.countDocuments({}));
'
```

應該看到 `✅ root uid=0 gid=0`。然後刷 `/audit`，表格滿滿。

---

## 回傳

1. 上方診斷三條的輸出（A/B/C）
2. 最終 seed_data.py 輸出
3. mongosh 最終驗證結果
