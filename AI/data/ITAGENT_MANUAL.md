# ITAgent 服務管理手冊

> 最後更新：2026-04-14 | 版本：v3.4.0.0

---

## 一、架構說明

ITAgent 巡檢系統由兩個 systemd 服務組成：

| 服務名稱 | 說明 | 依賴 |
|----------|------|------|
| `itagent-db.service` | MongoDB（Podman 容器） | network.target |
| `itagent-web.service` | Flask Web 應用 | itagent-db.service |

啟動順序：`itagent-db` → `itagent-web`（自動依賴）

### 檔案清單

| 檔案 | 位置 | 用途 |
|------|------|------|
| 環境變數 | `/etc/default/itagent` | 定義 `ITAGENT_HOME`，搬家只改這裡 |
| DB 服務 | `/etc/systemd/system/itagent-db.service` | MongoDB 容器管理 |
| Web 服務 | `/etc/systemd/system/itagent-web.service` | Flask 應用管理 |
| 管理腳本 | `${ITAGENT_HOME}/itagent.sh` | 互動式管理工具 |
| 全域指令 | `/usr/local/bin/itagent` | symlink → itagent.sh |

---

## 二、日常操作

### 互動選單模式

```bash
itagent
```

會顯示：
```
╔══════════════════════════════════════╗
║   ITAgent 巡檢系統 v3.2.0.0          ║
║   服務管理工具                       ║
╠══════════════════════════════════════╣
║  1) 啟動服務                        ║
║  2) 停止服務                        ║
║  3) 重啟服務                        ║
║  4) 確認狀態                        ║
║  5) 查看日誌                        ║
║  0) 離開                            ║
╚══════════════════════════════════════╝
```

### CLI 模式

```bash
itagent start      # 啟動所有服務（DB → Web）
itagent stop       # 停止所有服務（Web → DB）
itagent restart    # 重啟所有服務
itagent status     # 顯示服務狀態、HTTP、MongoDB 連線
itagent log        # 查看最近 30 行日誌
```

### systemctl 操作

```bash
# 單獨控制
systemctl start itagent-db       # 只啟動 MongoDB
systemctl start itagent-web      # 只啟動 Flask（會自動拉起 DB）
systemctl restart itagent-web    # 只重啟 Flask
systemctl status itagent-web     # 查看 Flask 狀態

# 查看日誌
journalctl -u itagent-web -f     # 即時追蹤 Flask 日誌
journalctl -u itagent-db -f      # 即時追蹤 DB 日誌
```

---

## 三、環境變數設定

檔案位置：`/etc/default/itagent`

```bash
# ITAgent 巡檢系統 - 環境變數設定
# 搬家時只需修改 ITAGENT_HOME 即可
ITAGENT_HOME=/opt/inspection
```

### 為什麼放在 /etc/default/？

- 這是 Linux systemd 讀取 `EnvironmentFile` 的標準位置
- systemd service 檔無法使用未定義的變數來找設定檔
- 所以 `/etc/default/itagent` 是唯一需要寫死路徑的地方
- 其他所有檔案（service、script）都透過 `ITAGENT_HOME` 變數取得路徑

---

## 四、搬家（變更安裝路徑）

當巡檢系統需要搬移到不同目錄時，只需三步：

### 步驟

```bash
# 1. 先停止服務
itagent stop

# 2. 搬移目錄
mv /opt/inspection /new/path/inspection

# 3. 修改環境變數（只改這一個檔案）
vi /etc/default/itagent
# 將 ITAGENT_HOME=/opt/inspection
# 改為 ITAGENT_HOME=/new/path/inspection

# 4. 更新全域指令的 symlink
ln -sf /new/path/inspection/itagent.sh /usr/local/bin/itagent

# 5. 重新載入並啟動
systemctl daemon-reload
itagent start

# 6. 驗證
itagent status
```

### 注意事項

- MongoDB 資料卷在 `${ITAGENT_HOME}/container/mongodb_data/`，搬移目錄時資料會一起搬
- 如果 MongoDB 容器的 volume mount 是用絕對路徑建立的，需要重建容器：
  ```bash
  podman stop mongodb && podman rm mongodb
  podman run -d --name mongodb \
    -p 127.0.0.1:27017:27017 \
    -v ${ITAGENT_HOME}/container/mongodb_data:/data/db \
    mongo:6
  ```
- Flask 的 `config.py` 中 `INSPECTION_HOME` 也需要同步修改（或改為讀取環境變數）

---

## 五、開機自動啟動

已透過 `systemctl enable` 設定：

```bash
# 查看是否已啟用
systemctl is-enabled itagent-db    # 應顯示 enabled
systemctl is-enabled itagent-web   # 應顯示 enabled

# 如需重新啟用
systemctl enable itagent-db itagent-web

# 如需停用開機自啟
systemctl disable itagent-db itagent-web
```

開機啟動順序由 systemd 依賴管理：
1. `network.target` 就緒
2. `itagent-db.service` 啟動 MongoDB 容器
3. `itagent-web.service` 啟動 Flask（等 DB 就緒後）

---

## 六、故障排除

### Flask 啟動失敗

```bash
# 查看詳細錯誤
journalctl -u itagent-web --no-pager -n 50

# 手動測試啟動
cd ${ITAGENT_HOME}/webapp && python3 app.py
```

### MongoDB 無法連線

```bash
# 檢查容器狀態
podman ps -a --filter name=mongodb

# 手動啟動容器
podman start mongodb

# 測試連線
podman exec mongodb mongosh --eval "db.runCommand({ping:1})"
```

### 服務一直重啟（restart loop）

```bash
# 查看失敗原因
systemctl status itagent-web --no-pager -l
journalctl -u itagent-web --since "5 min ago"

# 常見原因：
# - Python 套件缺失 → pip3 install -r requirements.txt
# - MongoDB 未啟動 → systemctl start itagent-db
# - Port 5000 被占用 → lsof -i :5000
```

### 環境變數未生效

```bash
# 確認檔案存在且格式正確
cat /etc/default/itagent

# 確認 systemd 有讀取
systemctl show itagent-web | grep Environment
```

---

## 七、服務設定檔內容

### /etc/systemd/system/itagent-db.service

```ini
[Unit]
Description=ITAgent MongoDB (Podman)
After=network.target
Wants=network.target

[Service]
Type=forking
EnvironmentFile=/etc/default/itagent
ExecStartPre=/usr/bin/podman start mongodb
ExecStart=/bin/bash -c 'until podman exec mongodb mongosh --eval "db.runCommand({ping:1})" --quiet 2>/dev/null; do sleep 1; done'
ExecStop=/usr/bin/podman stop -t 10 mongodb
ExecReload=/usr/bin/podman restart mongodb
RemainAfterExit=yes
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### /etc/systemd/system/itagent-web.service

```ini
[Unit]
Description=ITAgent Flask Web Application
After=itagent-db.service
Requires=itagent-db.service

[Service]
Type=simple
User=root
EnvironmentFile=/etc/default/itagent
ExecStart=/bin/bash -c "cd ${ITAGENT_HOME}/webapp && /usr/bin/python3 app.py"
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
```

---

## 八、版本紀錄

| 日期 | 版本 | 變更 |
|------|------|------|
| 2026-04-12 | v3.2.0.0 | 建立 systemd 服務管理 + itagent 管理腳本 + 開機自啟 |


---

## 九、Cloudflare Tunnel（外部存取）

### 服務

| 項目 | 說明 |
|------|------|
| 服務名稱 | `itagent-tunnel` |
| 類型 | Cloudflare Named Tunnel（固定域名） |
| 設定檔 | `/etc/systemd/system/itagent-tunnel.service` |
| 固定域名 | https://it.94alien.com |
| 開機自啟 | 已啟用 |

### 操作

```bash
# CLI
itagent tunnel              # 查看目前外部網址
itagent status              # 顯示全部狀態（含 tunnel 網址）

# systemctl
systemctl start itagent-tunnel
systemctl stop itagent-tunnel
systemctl restart itagent-tunnel    # 會產生新網址
```

### Web 管理
系統管理 → 系統狀態 → 「外部存取 (Cloudflare Tunnel)」卡片：
- 顯示運行狀態 + 可點擊網址
- 複製網址按鈕
- 重啟 Tunnel
- 關閉 Tunnel

### 注意事項
- 已改用 Named Tunnel，固定域名 ，重啟不會變更
- Tunnel 依賴 Flask（itagent-web），Flask 停止時外部無法存取

---

## 十、版本紀錄

| 日期 | 版本 | 變更 |
|------|------|------|
| 2026-04-12 | v3.2.1.0 | 建立 systemd 服務管理 + itagent 管理腳本 + 開機自啟 |
| 2026-04-12 | v3.6.0.0 | 加入 itagent-tunnel 服務 + Tunnel Web 管理 + 三級權限 + RWD |
| 2026-04-14 | v3.4.0.0 | Tunnel改Named Tunnel固定域名it.94alien.com + 稽核專區 + Linux初始化工具 + 在線使用者追蹤 |
