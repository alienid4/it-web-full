# 2026-04-23 13:38 — v3.11.13.0 patch Step 1/5 備份失敗繞過 + debug

## 狀況

`sudo ./v3.11.13.0/patch_apply.sh` 卡在 `Step 1/5 Backup`，印 `FAIL 備份失敗` 後 exit。

原因未明，因為 patch_apply.sh line 70 寫：
```bash
tar czf ... 2>/dev/null || fail "備份失敗"
```

`2>/dev/null` 把 tar 的 stderr 全吞了，所以看不到真實錯誤訊息。

## 繞過方案（最快，3 分鐘搞定）

本次只改 1 個檔 `audit.html`，直接單檔覆蓋就好，**不必走 patch_apply.sh**：

### Step 1 — 解壓 tarball（若還沒解）

```bash
cd /tmp
tar xzf patch_v3.11.13.0.tar.gz
ls v3.11.13.0/files/webapp/templates/audit.html   # 確認檔案在
```

### Step 2 — 單檔覆蓋 + 重啟

```bash
TS=$(date +%Y%m%d_%H%M)

# 備份原檔 (單檔 cp 不會 tar 整個 inspection/, 不會遇到剛才的 bug)
sudo cp /opt/inspection/webapp/templates/audit.html \
        /opt/inspection/webapp/templates/audit.html.bak.${TS}

# 覆蓋
sudo cp /tmp/v3.11.13.0/files/webapp/templates/audit.html \
        /opt/inspection/webapp/templates/audit.html

# 權限對齊
sudo chown sysinfra:itagent /opt/inspection/webapp/templates/audit.html

# 重啟
sudo systemctl restart itagent-web
```

### Step 3 — 驗證

打開 `http://10.92.198.13:5000/audit`，主機下拉右邊應該多了「主機搜尋」input。

---

## Debug（選做，順便找出 patch_apply.sh 備份失敗根因）

想知道為什麼 tar 失敗，跑這條（不丟 stderr）：

```bash
sudo tar czf /tmp/debug_backup_test.tar.gz \
  --exclude=inspection/container \
  --exclude=inspection/logs \
  -C /opt inspection
```

**可能的錯誤訊息**：

| 訊息 | 根因 | 解法 |
|---|---|---|
| `No space left on device` | /tmp 滿了 | `df -h /tmp` 確認；清 /tmp 舊 tarball |
| `Permission denied` 某檔 | sysinfra:itagent 權限路徑有 root-only 子檔 | 找該檔 `chmod a+r` 或 exclude |
| `file changed as we read it` | 有程式正在寫該檔（Flask log?） | 跑之前 stop itagent-web |
| `Cannot open: ...` | 某檔是 socket / pipe | tar 加 `--warning=no-file-ignored` |

把訊息貼回，我改下版 patch_apply.sh 把 `2>/dev/null` 拿掉顯示真實錯誤。

---

## 回傳

1. Step 3 驗證截圖（主機搜尋欄位出現）
2. (選做) debug 指令的錯誤訊息
