# RUNBOOK — IT 監控系統常見問題排查

> **給接手 ops / AI 的 first responder 指南**。
> 最後更新: v3.10.1.1 (2026-04-20)

---

## 0. 健檢儀式 (懷疑系統壞掉時先跑)

```bash
ssh ansible-host '
echo "=== services ==="; systemctl is-active itagent-web itagent-db itagent-tunnel sshd firewalld
echo "=== ports ==="; ss -tln | grep -E ":22|:5000|:27017|:9090"
echo "=== local HTTP ==="; curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:5000/login
echo "=== external HTTP ==="; curl -sSL -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 https://it.94alien.com/login
echo "=== uptime ==="; uptime
echo "=== errors (5 min) ==="; journalctl -u itagent-web --since "-5 minutes" -p err --no-pager | tail -10
'
```

**預期**：所有 service active、HTTP 200、外部 <2s。

---

## 1. SSH 連不上 ansible-host — 先查 MTU 不是 sshd

**症狀**：
- ssh timeout (`connect to host <ANSIBLE_HOST> port 22: Connection timed out`)
- port 22 test fail (`TcpTestSucceeded=False`)
- 但 ping 通 (`PingSucceeded=True`)

**診斷**：
```bash
ping -M do -s 1472 1.1.1.1   # 若回 "message too long, mtu=1492" → MTU 問題
```

**修復 (一次性)**：
```bash
ip link set ens160 mtu 1492
nmcli connection modify ens160 802-3-ethernet.mtu 1492
sysctl -w net.ipv4.tcp_mtu_probing=1
echo "net.ipv4.tcp_mtu_probing=1" > /etc/sysctl.d/99-tcp-mtu-probe.conf
```

**原因**：台灣 ISP 多走 PPPoE (overhead 8 bytes)，VM 網卡預設 1500 → 大封包被中間設備默默丟。

---

## 2. 網站 HTTP 502 Bad gateway — 先查 tunnel

**症狀**：瀏覽器看 Cloudflare 502 錯誤頁，顯示「it.94alien.com Host Error」。

**診斷**：
```bash
systemctl is-active itagent-tunnel
journalctl -u itagent-tunnel --since "-10 minutes" | grep -iE "Registered|ERR" | tail -10
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:5000/login   # 本機若 200 = tunnel 問題
```

**修復 (常態)**：
```bash
systemctl restart itagent-tunnel
```

**自動化**：`scripts/tunnel_healthcheck.sh` 已裝在 cron (*/2 min)，連 2 次失敗自動 restart。
查 `/opt/inspection/logs/tunnel_healthcheck.log`。

**若頻繁自動重啟**：看是否 MTU 問題 (見 §1)，tunnel 設定 `--protocol http2` (已預設) 比 QUIC 穩。

---

## 3. 網站 500 / 無法開啟

**診斷**：
```bash
systemctl is-active itagent-web
journalctl -u itagent-web --since "-10 minutes" | tail -30
```

**常見原因與修復**：

| 症狀 | 原因 | 修復 |
|---|---|---|
| `ModuleNotFoundError` | pip package 被降級 | `pip install -r webapp/requirements.txt` |
| `pymongo.errors.ServerSelectionTimeoutError` | MongoDB 當機 | `systemctl restart itagent-db` |
| Template error `jinja2.UndefinedError: APP_VER` | context processor 沒 load | app.py 要 `import os` |
| `OperationFailure: Cannot do inclusion on field...` | MongoDB projection 混用 | 只保留 exclusion (`"key":0`) |
| Flask 剛重啟 cookie 全失效 | SECRET_KEY 被改 | 檢查 config.py 的 `SECRET_KEY` 沒變 (應為固定值) |

---

## 4. 某頁面空白只顯示「載入中」

**原因 95%**：瀏覽器快取舊 JS，沒 loadXxxTab 函式。

**修復**：`Ctrl+F5` 強制刷新。若此問題常發生，檢查 `/admin` 頁的 `<script src="/static/js/admin.js?v={{ APP_VER }}">` 是否有帶 `?v=` 參數。

---

## 5. TWGCB 修復按鈕按了沒反應 / 看起來沒更新

**症狀**：點「修」按鈕 spinner 轉完 → 項目還是紅色。

**診斷**：
```bash
# 1. 看是否真的被 block 在 fix_locks 鎖裡
python3 -c "
from pymongo import MongoClient
db = MongoClient().inspection
for d in db.fix_locks.find():
    print(d)
"

# 2. 看背景 rescan 有沒有跑
journalctl -u itagent-web --since "-5 minutes" | grep -iE "rescan|fix" | tail -10
```

**修復**：
- 等 20~30 秒 (背景 rescan 需時間)
- 若鎖卡住超過 5 分鐘：`db.fix_locks.delete_many({})` 手動清
- 若 `ansible_distribution undefined` → 加 `default('Linux')` filter

---

## 6. nmon 月報沒資料

**症狀**：`/perf` 頁「尚無資料」或某日空白。

**診斷**：
```bash
# 1. 主機是否開啟 nmon_enabled
python3 -c "
from pymongo import MongoClient
db = MongoClient().inspection
for h in db.hosts.find({'nmon_enabled': True}, {'hostname':1, 'nmon_interval_min':1}):
    print(h)
"

# 2. Ansible 有沒有抓到檔
ls -la /opt/inspection/data/nmon/<hostname>/

# 3. 主機上 cron 有沒有裝對
ansible <host> -b -m shell -a "crontab -l -u root | grep nmon"

# 4. MongoDB 有沒有該日資料
python3 -c "
from pymongo import MongoClient
db = MongoClient().inspection
d = db.nmon_daily.find_one({'hostname':'<host>', 'date':'2026-04-20'})
print(d)
"
```

**修復**：
- 若 checkbox 有勾但無資料 → 去 系統管理 → 監控平台管理 → 效能月報管理 tab 重按「套用」重新部署 cron
- 若檔案有但 MongoDB 沒 → `python3 -c "from services import nmon_service; print(nmon_service.import_nmon_files())"`
- 若圖不刷新 → 按頁面上「🔄 重畫」按鈕強制 bypass 快取

---

## 7. 功能模組 on/off 不生效

**症狀**：在 superadmin → 模組管理關掉某模組，navbar 入口還在。

**修復**：
1. `Ctrl+F5` 刷新 (因為 `window.FEATURES` 是 render 時注入，需重載)
2. 若還是不行，檢查 `feature_flags` collection 是否真的更新：
```bash
python3 -c "from services import feature_flags; print(feature_flags.all_flags())"
```

---

## 8. 登入失敗被鎖

**症狀**：`帳號已鎖定，請 15 分鐘後再試`

**解鎖**：
```bash
python3 -c "
from services.mongo_service import get_collection
get_collection('login_attempts').delete_many({})
print('cleared')
"
```

---

## 9. MongoDB 容器問題

**症狀**：itagent-db 顯示 failed / MongoDB 連不上。

**診斷**：
```bash
podman ps -a | grep mongodb
podman logs mongodb --tail 50
```

**常見修復**：
```bash
# a. 容器停了 → 啟動
podman start mongodb

# b. 容器壞了 → 重建（資料留在 volume）
podman rm -f mongodb
podman run -d --name mongodb --systemd always -p 127.0.0.1:27017:27017 \
  -v /var/log/inspection/mongodb:/data/db docker.io/library/mongo:6
systemctl restart itagent-db
```

---

## 10. 資料安全 / 備份還原

### 每日自動備份
- cron: `0 2 * * * tar czf /var/backups/inspection/INSPECTION_HOME_$(date +%Y%m%d).tar.gz ...`
- cron: `5 2 * * * podman exec mongodb mongodump --db inspection --out /tmp/mongo_daily_backup`

### 手動全備
```bash
# MongoDB
podman exec mongodb mongodump --db inspection --archive --gzip > /var/backups/inspection/mongo_$(date +%Y%m%d).archive.gz

# 整個 inspection 目錄
tar czf /var/backups/inspection/full_$(date +%Y%m%d).tar.gz -C /opt inspection/
```

### 還原 MongoDB
```bash
podman exec -i mongodb mongorestore --db inspection --archive --gzip < /var/backups/inspection/mongo_<DATE>.archive.gz
```

---

## 11. 緊急全站停 / 復原

**全站停**:
```bash
systemctl stop itagent-web itagent-tunnel
```

**復原**:
```bash
systemctl start itagent-db itagent-web itagent-tunnel
# 等 10 秒
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:5000/login
```

---

## 12. 未來待開發 (CIO/資訊主管視角)

當前系統偏「工程師排錯」視角。下批可考慮加這些給主管看：

### 一頁總覽
- **/cio-dashboard** 主管儀表板: 綜合健康指數 + SLA + 合規率趨勢 + Top 5 風險
- **合規率 30/90/365 天趨勢線**: 新 collection `twgcb_daily_stats` (每日 snapshot)

### 決策支援
- **合規項老化分析**: FAIL >30 天未修的清單，按部門/AP 負責人聚合
- **高風險主機 Top 5**: 合規低 + 修復慢 + 次數多 綜合分數
- **告警疲勞指標**: 本月告警量 + 誤報率

### 稽核舉證
- **月度 PDF 報告自動產製**: 每月 1 號 cron → 產 TWGCB + 效能 + 事件摘要 → email
- **例外審批流程**: TWGCB 例外到期管理 + 即將到期提醒
- **事件時間軸**: admin_worklog 視覺化

### 團隊管理
- **MTTR / on-call 次數統計**: 按人員 / 主機類型

工時估計: 主管儀表板 4~6 小時 / 趨勢線 2 小時 / 老化分析 1.5 小時 / 月報 PDF 3 小時。

---

## 附: 斷電/重啟後驗證清單

```bash
systemctl is-active itagent-db itagent-web itagent-tunnel sshd cloudflared
curl -s http://127.0.0.1:5000/api/settings/version | head -c 200
curl -sSL -o /dev/null -w "%{http_code}\n" https://it.94alien.com/login
crontab -l | grep -E "inspection|tunnel|backup"
ls -la /opt/inspection/data/reports/ | tail -5
```

全部通過 = 系統健康。
