# 2026-04-23 14:50 — Phase 2 套用前驗證 + 執行腳本（13 上）

## 流程

```
Step 1 驗證 P1 完整 → Step 2 (若需要) 重跑 inspection → Step 3 套 P2 → Step 4 驗證 P2
```

---

## Step 1 — 驗證 account_audit 有沒有 P1 的新欄位

```bash
mongosh inspection --quiet --eval '
  const r = db.account_audit.findOne({user:"root"});
  if (!r) { print("❌ 找不到 root (P1 role 沒生效 or 沒跑 inspection)"); }
  else {
    print("hostname:", r.hostname);
    print("user:", r.user);
    print("uid:", r.uid);
    print("gid:", r.gid);
    print("primary_group:", r.primary_group);
    if (r.gid === undefined || r.gid === null) print("❌ 缺 gid 欄位, P1 role 沒生效");
    else print("✅ gid 欄位有值");
  }
'
```

### 判讀

| 結果 | 意思 | 下一步 |
|---|---|---|
| 印出 `uid:0, gid:0, primary_group:"root"` + `✅ gid 欄位有值` | P1 完整, 可直接套 P2 | 跳到 Step 3 |
| `❌ 找不到 root` | run_inspection 沒跑 / role 舊版 | 先跑 Step 2 |
| 有 hostname/uid 但缺 gid | role 是舊版或沒跑新版 inspection | 先跑 Step 2 |

---

## Step 2 — (若需要) 重跑 inspection 抓 P1 新資料

```bash
sudo -u sysinfra /opt/inspection/run_inspection.sh
```

約 2~5 分鐘。結束後再跑一次 Step 1 驗證。

---

## Step 3 — 套 P2 (2 檔單檔 cp, 繞過 patch_apply.sh 備份 bug)

```bash
cd /tmp
curl -LO https://github.com/alienid4/it-web-full/releases/download/v3.11.16.0/patch_v3.11.16.0.tar.gz
tar xzf patch_v3.11.16.0.tar.gz

TS=$(date +%Y%m%d_%H%M)

# audit.html
sudo cp /opt/inspection/webapp/templates/audit.html \
        /opt/inspection/webapp/templates/audit.html.bak.${TS}
sudo cp /tmp/v3.11.16.0/files/webapp/templates/audit.html \
        /opt/inspection/webapp/templates/audit.html
sudo chown sysinfra:itagent /opt/inspection/webapp/templates/audit.html

# api_audit.py
sudo cp /opt/inspection/webapp/routes/api_audit.py \
        /opt/inspection/webapp/routes/api_audit.py.bak.${TS}
sudo cp /tmp/v3.11.16.0/files/webapp/routes/api_audit.py \
        /opt/inspection/webapp/routes/api_audit.py
sudo chown sysinfra:itagent /opt/inspection/webapp/routes/api_audit.py

# 重啟 Flask (api 改了)
sudo systemctl restart itagent-web
sudo systemctl status itagent-web --no-pager | head -10
```

---

## Step 4 — 驗證 P2

打開 `http://10.92.198.13:5000/audit` 應該看到：

1. 表格最右多 **操作** 欄
2. `root` 列顯示「系統」灰文字（不能手動標記, 已系統高權限）
3. 其他帳號（`sysinfra` / `alien` / `ap_xxx` 等）顯示橘色 **⭐ 標記** 按鈕
4. 點 **⭐ 標記** 跳 modal：
   - 備註必填（空著點「標記」會 alert 擋）
   - 填完備註 → 確定 → 該帳號：
     - 變紅底
     - 帳號名旁多 `⭐ 人工高權限` badge
     - 操作欄變 **取消⭐**
5. Hover `⭐ 人工高權限` badge → tooltip 看 reason + 標記人
6. 上方統計「其中 N 個高權限」會把人工的算進去
7. 勾「只顯示高權限」→ 包含系統（UID=0/GID=0）+ 人工兩類

---

## 回傳

1. Step 1 的 mongosh 輸出
2. (若跑了 Step 2) inspection 結束訊息
3. Step 3 `systemctl status itagent-web` 輸出
4. Step 4 /audit 截圖 (含試標記一個 AP 帳號後的效果)
