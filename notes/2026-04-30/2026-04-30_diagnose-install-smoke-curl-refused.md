# 診斷 v3.17.11.0 install.sh smoke 第 4 項 curl Connection refused

## 症狀

裝完 v3.17.11.0 後 smoke test 4/4：
- AST 語法 OK ✓
- sync_systems_from_hosts helper 存在 ✓
- api_admin.py 有業務系統欄解析 ✓
- 但 `curl: (7) Failed to connect to localhost port 5000: Connection refused`
- 畫面顯示 `itagent-web=activating` (還在啟動,沒進 active)

**根因推測**：install.sh `sleep 3` 太緊, gunicorn worker 還沒 spawn 完 curl 就打上去, 不是真的服務掛了。

下次 patch 該把 sleep 3 改 sleep 8, 並且改成 retry curl 5 次每次 sleep 2, 任一次成功就過。今天先用下面三段確認服務真的活著。

---

## Step 1. 等 5 秒再看狀態

```bash
sleep 5 && sudo systemctl status itagent-web --no-pager -l | head -15
```

預期 `Active: active (running) since ...`。

---

## Step 2. HTTP ping 確認真的能連

```bash
curl -sS -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 http://localhost:5000/login
```

預期 `HTTP 200`。

---

## Step 3. 兩種結果分流

### A. status active + HTTP 200 → 沒事, 接 Step 2 of v3.17.11.0 SOP

直接照 `notes/2026-04-30/2026-04-30_install-v3.17.11.0-on-13.md` 的 Step 2 (開 feature_flags) 繼續。install.sh 那個 curl 警告純時序假象, 不用管。

### B. status 還 activating / failed → 看 traceback

```bash
sudo journalctl -u itagent-web --since "2 min ago" --no-pager | grep -A 20 -iE 'traceback|exception|error' | tail -40
```

把輸出貼回對話, alienlee 對症修。

常見 traceback:
- `ImportError: cannot import name 'sync_systems_from_hosts'` — 部署沒覆蓋成功, 看 backup dir 跟 inspection home 是不是同份
- `SyntaxError` — 罕見 (我們本機 AST 都過了), 但若有則貼整段
- `AttributeError: ... 'datetime'` — 某 import 缺, 看 line 號

### C. 想直接 rollback

```bash
ls -t /var/backups/inspection/v3.17.11.0_* | head -1   # 找最新備份
sudo cp -r /var/backups/inspection/v3.17.11.0_<TS>/webapp/* /opt/inspection/webapp/
sudo systemctl restart itagent-web
```

回到 v3.17.10.3 狀態, 拓撲不會修但服務活著。
