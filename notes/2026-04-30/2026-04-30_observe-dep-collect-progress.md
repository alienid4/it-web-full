# 觀察拓撲採集進度與結果 — 5 個觀察點

採集中 / 採集後可以從這 5 個地方確認資料有沒有產生。從淺到深排。

---

## 1. UI「📊 狀態」按鈕 (最快)

`/dependencies` toolbar → `📊 狀態` → alert 顯示 status / edges_added / edges_updated / error。

採集中 status=running, 1-3 分後再點看是不是 success。**免 ssh, 99% 場合用這個就夠**。

---

## 2. mongo `dependency_collect_runs` 看 run 歷史

```bash
# 最新一筆
sudo mongosh inspection --quiet --eval '
const d = db.dependency_collect_runs.find({}).sort({started_at:-1}).limit(1).toArray()[0];
if (!d) print("(無 run 紀錄)");
else printjson({
  run_id: d.run_id, status: d.status,
  started: d.started_at, finished: d.finished_at,
  edges_added: d.edges_added, edges_updated: d.edges_updated,
  host_count: d.host_count, triggered_by: d.triggered_by,
  limit: d.limit, error: d.error || "-"
});
'

# 看歷史 5 筆 (查趨勢)
sudo mongosh inspection --quiet --eval '
db.dependency_collect_runs.find({}, {_id:0, run_id:1, status:1, started_at:1, edges_added:1, edges_updated:1, error:1})
  .sort({started_at:-1}).limit(5).forEach(printjson)
'
```

**status 三態**:
- `running` — ansible 還在跑 (1-3 分)
- `success` — 採集成功, 看 edges_added
- `failed` — 看 error 欄訊息

---

## 3. mongo `dependency_relations` 看真實邊

```bash
# 總數
sudo mongosh inspection --quiet --eval 'print("dep_rel total:", db.dependency_relations.countDocuments({}))'

# 依來源分群 (ss-tunp = 採集自動 / manual = 手動)
sudo mongosh inspection --quiet --eval '
db.dependency_relations.aggregate([
  {$group: {_id: "$source", n: {$sum: 1}}}
]).forEach(printjson)
'

# 看前 10 條邊 (確認 from/to 是 system_id, port 真實)
sudo mongosh inspection --quiet --eval '
db.dependency_relations.find({}, {_id:0, from_system:1, to_system:1, protocol:1, port:1, source:1, "evidence.last_remote_ip":1, "evidence.sample_hosts":1}).limit(10).forEach(printjson)
'

# 邊跟哪個業務系統有關 (撈某 system 的所有邊)
sudo mongosh inspection --quiet --eval '
db.dependency_relations.find({$or:[{from_system:"巡檢系統"},{to_system:"巡檢系統"}]}, {_id:0}).forEach(printjson)
'
```

採集成功 + 邊 > 0 = 拓撲圖會有線。

---

## 4. ansible 採集 log (跑中 tail -f, 失敗看 traceback)

```bash
# 列最近 5 個 log
sudo ls -lt /opt/inspection/logs/dep_collect_*.log 2>/dev/null | head -5

# tail -f 看採集進度 (跑中)
sudo tail -f $(sudo ls -t /opt/inspection/logs/dep_collect_*.log | head -1)

# 末 50 行 (採集完看結尾, COLLECT_OK = 兩階段都成功)
sudo tail -50 $(sudo ls -t /opt/inspection/logs/dep_collect_*.log | head -1)
```

**關鍵字**:
- `COLLECT_OK` — ansible + seed 兩階段都成功 (找這個就對了)
- `unreachable` / `Permission denied` — ssh 連不到, 看 sysinfra NOPASSWD / SSH key
- `TASK [...] FAILED` — 看上下文哪個 task 死了
- `ss: command not found` — 該 host 缺 iproute2 套件

---

## 5. raw JSON — ansible ss 採回來的原始連線

`/opt/inspection/data/connections_<epoch>_<hostname>.json` 每台採集一次寫一份。

```bash
# 列最近 10 份 (採集完每台一份)
sudo ls -lt /opt/inspection/data/connections_*.json 2>/dev/null | head -10

# 看某台採回什麼 (raw ss 解析後)
sudo head -100 $(sudo ls -t /opt/inspection/data/connections_*.json | head -1)

# 統計某台採到幾條連線
sudo python3 -c "
import json
with open('$(sudo ls -t /opt/inspection/data/connections_*.json | head -1)') as f:
    d = json.load(f)
print('hostname:', d.get('hostname'))
print('connections:', len(d.get('connections', [])))
for c in d.get('connections', [])[:5]:
    print(' ', c)
"
```

raw JSON 通常存 7 天, 之後採集腳本會清掉。是「為什麼某條邊沒寫進去」的最後線索。

---

## 觀察順序建議

採集中 → **第 4 步 tail -f log** 看進度
採集完 → **第 1 步 UI 狀態** 確認結果
edges_added > 0 → **第 3 步 mongo dep_rel** 看真實邊
edges_added = 0 → **第 5 步 raw JSON** 看採集到什麼但沒寫
status = failed → **第 4 步 log 末尾 + 第 2 步 error 欄**
