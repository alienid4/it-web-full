# 2026-04-23 16:42 — 路線 C：全套更新（一次貼完）

## 目標

1. 裝 v3.11.20.0 onboard 腳本（方案 X）
2. 更新 `version.json` 讓 UI 右下角顯示 v3.11.20.0
3. 驗證

---

## 全套指令（13 上一次貼完）

```bash
TS=$(date +%Y%m%d_%H%M)

# === 1. onboard_new_host.sh (v3.11.20.0) ===
curl -fL -o /tmp/onboard_new_host.sh \
  https://github.com/alienid4/it-web-full/raw/main/AI/scripts/onboard_new_host.sh

# 驗證下載成功 (應該看到方案 X 字樣)
grep -c "方案 X" /tmp/onboard_new_host.sh

# 覆蓋 + 權限
[ -f /opt/inspection/scripts/onboard_new_host.sh ] && \
  sudo cp /opt/inspection/scripts/onboard_new_host.sh \
          /opt/inspection/scripts/onboard_new_host.sh.bak.${TS}
sudo cp /tmp/onboard_new_host.sh /opt/inspection/scripts/onboard_new_host.sh
sudo chown sysinfra:itagent /opt/inspection/scripts/onboard_new_host.sh
sudo chmod 750 /opt/inspection/scripts/onboard_new_host.sh

# === 2. version.json ===
curl -fL -o /tmp/version.json \
  https://github.com/alienid4/it-web-full/raw/main/AI/data/version.json

# 驗證下載成功 (應該是 3.11.20.0)
grep version /tmp/version.json | head -1

# 覆蓋 + 權限
sudo cp /opt/inspection/data/version.json \
        /opt/inspection/data/version.json.bak.${TS}
sudo cp /tmp/version.json /opt/inspection/data/version.json
sudo chown sysinfra:itagent /opt/inspection/data/version.json

# === 3. 重啟 Flask (version.json 在啟動時讀到 _APP_VER 全域, 重啟才生效) ===
sudo systemctl restart itagent-web
sleep 3
sudo systemctl status itagent-web --no-pager | head -10
```

---

## 驗證

### V1. onboard 腳本新版

```bash
sudo /opt/inspection/scripts/onboard_new_host.sh
```

應該看到：
- Usage 列 `<hostname> [ip] [os_group] [ssh_user]`
- 「方案 X (v3.11.20.0+)」字樣
- 6 步流程清單

### V2. UI 版本號

打開任何頁面（例如 http://10.92.198.13:5000/）→ 右下角應顯示：

```
v3.11.20.0 | 2026-04-23 16:20
```

不再是 v3.11.6.0。

### V3. /audit 仍運作

打開 `/audit`，應該有完整帳號清單 + root 紅底 + 高權限可標記（v3.11.15/16/17 的成果沒被覆蓋）。

---

## 之後加第 3 台

```bash
sudo /opt/inspection/scripts/onboard_new_host.sh <新hostname> <新IP>
```

範例：

```bash
sudo /opt/inspection/scripts/onboard_new_host.sh SECSVR198-012T 10.92.198.12
```

3~7 分鐘後這 6 個頁面都有第 3 台：Dashboard / 今日報告 / 帳號盤點 / TWGCB / 軟體盤點 / 效能月報。

---

## 回傳

1. V1 Usage 的前 10 行（看到方案 X 字樣）
2. V2 任何頁面截圖（看版本號變 3.11.20.0）
3. 之後加第 3 台時的 onboard 完整輸出
