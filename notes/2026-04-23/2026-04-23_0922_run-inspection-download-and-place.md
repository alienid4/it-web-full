# 2026-04-23 09:22 — 補齊 run_inspection.sh 到 13

## 狀況

13 上 `sudo /opt/inspection/run_inspection.sh` 回 `command not found` — 檔案不在 `/opt/inspection/` 根目錄。

## 作法

直接從 GitHub 下載 repo 裡的 `run_inspection.sh` 放上去。

### Step 1 — 下載（Win10 瀏覽器右鍵另存）

```
https://github.com/alienid4/it-web-full/raw/main/AI/run_inspection.sh
```

### Step 2 — 搬到 13 + 放位置 + 給權限

scp / USB 搬到 13 的 `/tmp/`，然後：

```bash
# 備份現有（若存在）
[ -f /opt/inspection/run_inspection.sh ] && \
  sudo cp /opt/inspection/run_inspection.sh \
          /opt/inspection/run_inspection.sh.bak.$(date +%Y%m%d_%H%M)

# 放到 /opt/inspection/ 根目錄（腳本內部寫死這個路徑）
sudo cp /tmp/run_inspection.sh /opt/inspection/run_inspection.sh

# 權限 + 擁有者
sudo chown sysinfra:itagent /opt/inspection/run_inspection.sh
sudo chmod 750 /opt/inspection/run_inspection.sh
```

### Step 3 — 確認能跑

```bash
# 直接跑（會等 1-2 分鐘跑完完整 inspection + seed + packages + cio snapshot）
sudo -u sysinfra /opt/inspection/run_inspection.sh
```

### Step 4 — 跑完驗新檔有 `inspection_` 前綴

```bash
sudo ls -lt /opt/inspection/data/reports/inspection_*.json | head -5
```

**預期**：看到今天時間戳的 2 個 `inspection_20260423_*_SECSVR198-*.json`。

### Step 5 — 看 Dashboard 有 CPU/MEM

打開 `http://10.92.198.13:5000/` Dashboard，CPU / MEM / Disk / Swap 應有數字。

---

## 合併 0910 那份的步驟

如果你還沒做 0910 notes 的 site.yml + seed_data.py 覆蓋，**三個檔一起搬**：

```
AI/run_inspection.sh
AI/ansible/playbooks/site.yml
AI/webapp/seed_data.py
```

三個下載 URL（Win10 一次全存到桌面）：

```
https://github.com/alienid4/it-web-full/raw/main/AI/run_inspection.sh
https://github.com/alienid4/it-web-full/raw/main/AI/ansible/playbooks/site.yml
https://github.com/alienid4/it-web-full/raw/main/AI/webapp/seed_data.py
```

三個位置：

| 下載檔 | 目標位置 | 權限 |
|---|---|---|
| `run_inspection.sh` | `/opt/inspection/run_inspection.sh` | `sysinfra:itagent 750` |
| `site.yml` | `/opt/inspection/ansible/playbooks/site.yml` | `sysinfra:itagent 640` |
| `seed_data.py` | `/opt/inspection/webapp/seed_data.py` | `sysinfra:itagent 640` |

一鍵覆蓋腳本：

```bash
# 三個檔都先搬到 /tmp/
cd /tmp
TS=$(date +%Y%m%d_%H%M)

# run_inspection.sh
[ -f /opt/inspection/run_inspection.sh ] && sudo cp /opt/inspection/run_inspection.sh /opt/inspection/run_inspection.sh.bak.${TS}
sudo cp /tmp/run_inspection.sh /opt/inspection/run_inspection.sh
sudo chown sysinfra:itagent /opt/inspection/run_inspection.sh
sudo chmod 750 /opt/inspection/run_inspection.sh

# site.yml
sudo cp /opt/inspection/ansible/playbooks/site.yml /opt/inspection/ansible/playbooks/site.yml.bak.${TS}
sudo cp /tmp/site.yml /opt/inspection/ansible/playbooks/site.yml
sudo chown sysinfra:itagent /opt/inspection/ansible/playbooks/site.yml
sudo chmod 640 /opt/inspection/ansible/playbooks/site.yml

# seed_data.py
sudo cp /opt/inspection/webapp/seed_data.py /opt/inspection/webapp/seed_data.py.bak.${TS}
sudo cp /tmp/seed_data.py /opt/inspection/webapp/seed_data.py
sudo chown sysinfra:itagent /opt/inspection/webapp/seed_data.py
sudo chmod 640 /opt/inspection/webapp/seed_data.py

# 清 twgcb 垃圾資料
mongosh inspection --quiet --eval '
  const r = db.inspections.deleteMany({run_id: /^twgcb_/});
  print("deleted:", r.deletedCount);
'

# 跑一次 inspection
sudo -u sysinfra /opt/inspection/run_inspection.sh

# 驗新檔
sudo ls -lt /opt/inspection/data/reports/inspection_*.json | head -5
```

跑完就能看 Dashboard。

## 回傳格式

貼：
1. `ls -lt reports/inspection_*.json` 輸出
2. Dashboard 截圖（CPU/MEM/Disk/Swap 有沒有數字）
