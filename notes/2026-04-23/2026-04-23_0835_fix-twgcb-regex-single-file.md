# 2026-04-23 08:35 — TWGCB 矩陣 regex fix 套用指引（單檔替換）

## 根因

api_twgcb.py 的 Linux OS filter regex：

```python
"(?i)(rocky|rhel|red hat|centos|debian|ubuntu|suse|oracle linux|linux)"
```

但 playbook 實際寫入 `twgcb_results.os` 欄位是 **`"RedHat 9.6"`**（從 summary API 截圖確認）：
- `rhel` ≠ `RedHat`
- `red hat`（有空格） ≠ `RedHat`（無空格）
- `linux` 字面也不在 `RedHat 9.6` 裡

→ Linux tab 發 `os_type=linux` 時兩台都被 filter 掉 → `count=0` → 矩陣空白。

## 修法

regex 加 `redhat`（無空格）：

```python
"(?i)(rocky|rhel|redhat|red hat|centos|debian|ubuntu|suse|oracle linux|linux)"
```

只改 `AI/webapp/routes/api_twgcb.py` 兩處（`/api/twgcb/results` 與 `/api/twgcb/export` 的 Linux filter）。

## 套用步驟（198.13）

### 1. 下載單檔

在公司 Win10 桌機瀏覽器打開：

```
https://github.com/alienid4/it-web-full/raw/main/AI/webapp/routes/api_twgcb.py
```

按右鍵「另存新檔」存到桌面（檔名 `api_twgcb.py`）。

### 2. 備份現有檔 + 覆蓋

從桌機把 `api_twgcb.py` scp 或 USB 搬到 198.13（例如 `/tmp/`），然後：

```bash
# 備份原檔
sudo cp /opt/inspection/webapp/routes/api_twgcb.py \
        /opt/inspection/webapp/routes/api_twgcb.py.bak.$(date +%Y%m%d_%H%M)

# 覆蓋
sudo cp /tmp/api_twgcb.py /opt/inspection/webapp/routes/api_twgcb.py

# 權限對齊
sudo chown sysinfra:itagent /opt/inspection/webapp/routes/api_twgcb.py
sudo chmod 640 /opt/inspection/webapp/routes/api_twgcb.py

# 重啟服務
sudo systemctl restart itagent-web

# 驗證服務起來
sudo systemctl status itagent-web --no-pager | head -20
```

### 3. 驗證

打開 `http://10.92.198.13:5000/api/twgcb/results?os_type=linux&limit=30`

**預期**：`"count":2,"total":2`（原本是 0）

再打開 TWGCB 合規頁，Linux tab 下方應該看到完整矩陣（分類摺疊 × 兩台主機燈號）。

## 快速 rollback（如果重啟失敗）

```bash
sudo cp /opt/inspection/webapp/routes/api_twgcb.py.bak.<時間戳> \
        /opt/inspection/webapp/routes/api_twgcb.py
sudo systemctl restart itagent-web
```

## 回傳格式

貼兩件事：

1. `sudo systemctl status itagent-web` 輸出前 20 行（確認服務 active）
2. 打開 TWGCB Linux tab 的截圖，看矩陣是不是出來了

如果還是空白，再貼 `/api/twgcb/results?os_type=linux&limit=30` 的 JSON 開頭。
