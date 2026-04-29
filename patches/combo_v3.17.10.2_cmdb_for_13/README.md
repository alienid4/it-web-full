# v3.17.10.2 hot-fix — 拓撲 0 edges 重疊 bug

## 問題

13 (公司測試區) 跑 v3.17.9.1, `dep_rel:0` 沒採集過邊。
打開 /dependencies 4 hosts 派生 4 nodes 應該畫得出來,
但畫面空白。

DevTools Console 顯示 `vis.Network init {nodes:4, edges:0, w:632, h:747}` 跟
`200ms check, canvas:685x909`, **沒任何 error**。

## 根因

`webapp/static/js/dependencies.js` renderTopology() layout 設定:

```js
layout: { hierarchical: { enabled: true, direction: "LR", sortMethod: "directed", ... } },
physics: false,
```

`hierarchical` + `sortMethod: "directed"` 在 **0 edges 時** 沒方向資訊,
4 個 nodes 全部分到 level 0 重疊在同座標。
`physics: false` 又沒斥力推開 → 4 個 size 22 的 dot 疊成一個小點 → 看起來像空白。

家裡 221 / 開發機 `dep_rel` 有 demo 邊不會中, 這條 bug 只在公司 13 浮現。

## 修法

dependencies.js 加 `hasEdges` 條件:
- 有邊 → 維持 hierarchical layout (原行為)
- 0 邊 → 切 free layout + repulsion physics 散開

同時 0 edges 時 dep-meta 顯示
「⚠️ 還沒採集任何邊資料 [前往採集 →]」 link 到 /admin#dependencies。

## 改動檔案 (1 個)

- `webapp/static/js/dependencies.js`

## 安裝

```bash
sudo bash install.sh
```

install.sh 會:
1. backup 原 dependencies.js → /var/backups/inspection/v3.17.10.2_TS/
2. cp 新版
3. bump version.json → 3.17.10.2
4. restart $SERVICE (+ tunnel)
5. smoke test 5 項 (HTTP 200 / size / JS 開頭 / 修法字串存在 / log)

## 驗證 (DevTools)

硬重整 (Ctrl+Shift+R) /dependencies 後 console 應看到:

```
[dep] vis.Network init {nodes: 4, edges: 0, w: ..., h: ...}
[dep] stabilization done, disable physics      ← 新增的
[dep] 200ms check, canvas: ...
```

畫面 4 個淡綠 dot 散開可見, 上方紅字提示去採集。

## 回滾

```bash
cp /var/backups/inspection/v3.17.10.2_TS/webapp/static/js/dependencies.js \
   /opt/inspection/webapp/static/js/dependencies.js
systemctl restart itagent-web
```
