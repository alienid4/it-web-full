# 2026-04-23 10:45 — v3.11.12.0 歷史查詢加入可關閉模組

## 動機

截圖顯示模組管理只有 6 個可關模組（audit/packages/perf/twgcb/summary/security_audit），缺「歷史查詢」。使用者要求加入。

## 改動

3 個檔案：

### 1. `services/feature_flags.py` — 新增 DEFAULT_FLAGS key

```python
{"key": "history", "name": "歷史查詢", "description": "/history 頁 (巡檢歷史趨勢查詢)"},
```

### 2. `app.py` — _FEATURE_PATH_MAP 加攔截

```python
("history", ["/history"]),
```

before_request 發現 `/history` 且 flag=false → 302 到 `/feature-disabled`。

### 3. `templates/base.html` — nav 條件渲染

```html
{% if FEATURES.history %}<li><a href="/history" id="nav-history">歷史查詢</a></li>{% endif %}
```

---

## 套用（13 上）

### Step 1 — 下載三個檔

```
https://github.com/alienid4/it-web-full/raw/main/AI/webapp/services/feature_flags.py
https://github.com/alienid4/it-web-full/raw/main/AI/webapp/app.py
https://github.com/alienid4/it-web-full/raw/main/AI/webapp/templates/base.html
```

### Step 2 — 覆蓋 + 重啟

```bash
TS=$(date +%Y%m%d_%H%M)

# feature_flags.py
sudo cp /opt/inspection/webapp/services/feature_flags.py \
        /opt/inspection/webapp/services/feature_flags.py.bak.${TS}
sudo cp /tmp/feature_flags.py /opt/inspection/webapp/services/feature_flags.py
sudo chown sysinfra:itagent /opt/inspection/webapp/services/feature_flags.py

# app.py
sudo cp /opt/inspection/webapp/app.py /opt/inspection/webapp/app.py.bak.${TS}
sudo cp /tmp/app.py /opt/inspection/webapp/app.py
sudo chown sysinfra:itagent /opt/inspection/webapp/app.py

# base.html
sudo cp /opt/inspection/webapp/templates/base.html \
        /opt/inspection/webapp/templates/base.html.bak.${TS}
sudo cp /tmp/base.html /opt/inspection/webapp/templates/base.html
sudo chown sysinfra:itagent /opt/inspection/webapp/templates/base.html

# 重啟
sudo systemctl restart itagent-web
```

### Step 3 — 驗證

1. 打開 `/superadmin` → 模組管理 tab → 應該看到 **7 個模組**（多了「歷史查詢」在最下面）
2. 關閉「歷史查詢」checkbox → 不跳 alert
3. 刷新任何頁面，導覽列的「歷史查詢」連結**消失**
4. 直接打 `http://10.92.198.13:5000/history` → 302 到 `/feature-disabled?m=history`
5. 回到 `/superadmin` 開啟「歷史查詢」→ 連結回來，頁面能用

---

## 回傳

1. `/superadmin` 模組管理 tab 截圖（確認 7 個模組都在）
2. 關閉「歷史查詢」後導覽列截圖（確認連結消失）

---

## 附：今天累計

| 版本 | 改什麼 |
|---|---|
| v3.11.7.0 | TWGCB 矩陣空白 |
| v3.11.8.0 | seed 誤吃 twgcb |
| v3.11.9.0 | inspection 前綴治本 |
| v3.11.10.0 | CPU 固定 100% |
| v3.11.11.0 | feature_flags summary 404 |
| v3.11.12.0 | **歷史查詢加入 feature flag** |
