# v3.17.10.3 hot-fix — 拓撲頁加「📊 狀態」按鈕 + tooltip 改清楚

## 問題

v3.17.10.2 上去後 user 點了「📡 採集」按鈕但**不知道有沒在跑**, 也不知道採集完了沒。
要 ssh 到 host 跑 `mongosh ... db.dependency_collect_runs.find(...)` 才看得到。

另外 fullscreen 頁的「📡 採集」tooltip 寫「(需 admin)」讓人誤以為是「現在被擋」(實際只是說明該 action 的權限要求)。

## 修法

### 1. 加「📊 狀態」按鈕 (主功能)
toolbar 點一下 alert 顯示最新採集 record:
```
最新採集 run_id: dep_20260429_141500
status:        running / success / failed
started_at:    ...
finished_at:   ...
edges_added:   N
edges_updated: N
error:         ...
```
不用 ssh, 不用 mongosh。

### 2. 主 /dependencies 也加「📡 採集」按鈕
原本只 fullscreen 才有, 現在主頁也能直接觸發。

### 3. tooltip 改清楚
- 原: "觸發 ansible 採集 (需 admin)"
- 新: "觸發背景採集 (ansible 跑 ss -tunp 至各 host, 1-3 分鐘. 需 admin/superadmin)"

### 4. depTriggerCollect 共用
原本定義在 fullscreen.html inline `<script>`, 搬到 dependencies.js 兩頁共用 (DRY)。

### 5. 401/403 錯誤訊息友善化
- 401 (session 過期) → "未登入或 session 過期, 請重新登入後再試"
- 403 (role 不夠) → "權限不足 — 需 admin/superadmin 才能觸發採集"

## 改動檔案 (3 個)

- `webapp/static/js/dependencies.js`
- `webapp/templates/dependencies.html`
- `webapp/templates/dependencies_fullscreen.html`

## 安裝

```bash
sudo bash install.sh
```

install.sh 流程: detect INSPECTION_HOME → backup → cp → bump version → restart →
4 項 smoke (HTTP / 路由 / 函式字串 / status API)。

## 驗證 (DevTools)

硬重整 (Ctrl+Shift+R) 後:
- toolbar 應多兩按鈕 (主頁) / 一按鈕 (fullscreen, 因為原本就有採集)
- 點「📊 狀態」立刻 alert
- 點「📡 採集」變「⏳ 採集中...」, 5 秒輪詢一次, 完成後 alert 結果並自動 reload
- 401 / 403 錯誤訊息有具體說明 (不再光「採集失敗:」)

## 回滾

```bash
cp -r /var/backups/inspection/v3.17.10.3_TS/webapp/* /opt/inspection/webapp/
systemctl restart itagent-web
```
