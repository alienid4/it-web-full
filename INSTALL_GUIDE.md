# IT Inspection System 安裝指南

**版本**：v3.5.0.0-testenv
**適用**：Rocky Linux 9 / RHEL 8-9 / CentOS 8-9
**部署模式**：雙軌（程式碼走 GitHub + 依賴走 USB）

---

## 架構說明

| 項目 | 來源 | 大小 |
|---|---|---|
| 程式碼 | GitHub (`git clone`) | ~500KB |
| RPM/pip 依賴 | USB（`inspection_deps_v3.5.0.0-testenv.tar.gz`） | ~220MB |

程式碼跟依賴分離，依賴只需搬一次，之後程式碼更新走 `git pull` 即可。

---

## 安裝前準備

### 測試機需具備
- Rocky Linux 9 / RHEL 9（建議 9.0+）
- root 權限
- 至少 4GB RAM、20GB 磁碟
- 網路通往 GitHub（clone 用）**或**預先把 repo tar.gz 也拷貝過來
- `/tmp/upload/` 可寫

### 先準備好兩個東西
1. **GitHub 存取** — 把 `alienid4/it-web-full` 設為 Private 後，建議用 Personal Access Token 或 SSH key
2. **依賴包** — `inspection_deps_v3.5.0.0-testenv.tar.gz`（透過 USB 或 SCP 搬到測試機）

---

## 安裝步驟（4 步）

### Step 1：把依賴包放到 /tmp/upload

```bash
mkdir -p /tmp/upload
# 從 USB 複製或透過 SCP
cp /media/usb/inspection_deps_v3.5.0.0-testenv.tar.gz /tmp/upload/
cd /tmp/upload
tar xzf inspection_deps_v3.5.0.0-testenv.tar.gz
ls /tmp/upload/packages/    # 應該看到 rpm/ pip/ versions.txt
```

### Step 2：從 GitHub clone 程式碼

```bash
cd /opt
git clone https://github.com/alienid4/it-web-full.git inspection
cd inspection
```

> 若公司測試區無外網：改為 SCP 整個 repo tar.gz 過來再解壓。

### Step 3：執行一鍵安裝

```bash
sudo ./install.sh
```

安裝腳本會詢問：

| 設定項 | 預設值 | 說明 |
|---|---|---|
| 安裝目錄 | `/opt/inspection` | 程式碼部署位置 |
| 備份目錄 | `/var/backups/inspection` | 升級時舊版備份位置 |
| Flask Port | 5000 | Web UI port |
| MongoDB Port | 27017 | 資料庫 port |
| 管理員密碼 | （手動輸入） | superadmin 帳號密碼 |
| 巡檢排程 | `06:30,13:30,17:30` | cron 排程時間 |

**搜尋依賴順序**：`./packages/` → `/tmp/upload/packages/` → `--deps-dir=<path>`

**完成時間**：約 2-5 分鐘（主要是 RPM 安裝）

### Step 4：首次啟動引導

```bash
sudo /opt/inspection/first_run.sh
```

會依序：
1. 檢查 `itagent-db` 和 `itagent-web` 服務
2. 協助你編輯 `hosts_config.json`（從 template 複製）
3. 印出 SSH 公鑰，指引你分發到受控主機
4. 試跑一次巡檢

---

## 常用管理指令

安裝完成後，`itagent` 指令全域可用：

```bash
itagent status       # 查看服務狀態
itagent start        # 啟動所有服務
itagent stop         # 停止
itagent restart      # 重啟
itagent log          # 查看 Flask 日誌
itagent menu         # 互動選單
```

---

## 常見問題

### Q1. install.sh 找不到套件
確認 `/tmp/upload/packages/` 下有 `rpm/` 和 `pip/` 兩個資料夾。或用 `--deps-dir=<path>` 明確指定。

### Q2. MongoDB 啟動失敗
```bash
journalctl -u itagent-db -n 50
```
最常見是 `/var/lib/mongo` 權限問題，執行：
```bash
chown -R mongod:mongod /var/lib/mongo
systemctl restart itagent-db
```

### Q3. Flask 起不來
```bash
journalctl -u itagent-web -n 50
```
通常是 pip 套件沒裝齊。重跑：
```bash
cd /tmp/upload/packages/pip
pip3 install --no-index --find-links=. flask pymongo bcrypt gunicorn pywinrm pysnmp openpyxl
```

### Q4. Ansible SSH 無法連線受控主機
- 公鑰有沒有放到 `/home/ansible_svc/.ssh/authorized_keys`？
- 受控主機 sshd 是否允許 key auth？
- 防火牆有沒有開 22？

### Q5. 想換安裝目錄
改 `/etc/default/itagent` 裡的 `ITAGENT_HOME=` 後重啟服務。

---

## 升級程式碼（不需要動依賴）

```bash
cd /opt/inspection
git pull
systemctl restart itagent-web
```

版本號在 `/opt/inspection/version.json`。

---

## 解除安裝

```bash
systemctl stop itagent-web itagent-db
systemctl disable itagent-web itagent-db
rm -f /etc/systemd/system/itagent-{db,web,tunnel}.service
rm -f /etc/default/itagent
rm -f /usr/local/bin/itagent
rm -rf /opt/inspection
# MongoDB 資料（確認要刪再動）
# rm -rf /var/lib/mongo
```

---

## 支援

* Issues: https://github.com/alienid4/it-web-full/issues
* 安裝日誌預設位置：`/opt/inspection/logs/`
