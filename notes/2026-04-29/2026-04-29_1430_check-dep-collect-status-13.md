# 拓撲採集狀態查詢 (13/任意 INSPECTION host)

點了 fullscreen 頁的「⛶ 採集」按鈕後不知道有沒在跑、有沒成功？
在 host 上跑下面三段確認。

## 1. 看最新 collect run record (最快)

```bash
sudo mongosh inspection --quiet --eval '
  const d = db.dependency_collect_runs.find({}).sort({started_at:-1}).limit(1).toArray()[0];
  if (!d) { print("(沒有任何 collect run record)"); }
  else {
    print("run_id:     ", d.run_id);
    print("status:     ", d.status);
    print("started:    ", d.started_at);
    print("finished:   ", d.finished_at);
    print("edges_added:", d.edges_added);
    print("edges_upd:  ", d.edges_updated);
    print("error:      ", d.error || "-");
  }
'
```

`status` 三態：
- `running` — 還在跑 (ansible playbook 沒結束)
- `success` — 成功，邊已寫入 `dependency_relations`
- `failed` — fail，看 `error` 欄

## 2. 看 ansible 跑的 log (status=running 或 failed 看細節用)

```bash
sudo tail -50 $(sudo ls -t /opt/inspection/logs/dep_collect_*.log 2>/dev/null | head -1)
```

關鍵字：
- 結尾出現 `COLLECT_OK` → ansible + seed 兩階段都成功
- `unreachable` / `Permission denied` / `sudo: a password is required` → ansible 連不到 host (sysinfra NOPASSWD 沒設 / SSH key 沒分發)
- `TASK [...] FAILED` → 該 task 失敗看上下文

## 3. 看現在 dep_rel 有幾條 (採集後最終確認)

```bash
sudo mongosh inspection --quiet --eval 'print("dep_rel:", db.dependency_relations.countDocuments({}))'
```

> 0 → 重整 /dependencies 應該就有線了。

## 如果採集 fail 怎辦

回報以上輸出，alienlee 會打 v3.17.10.3 demo seed patch 直接灌 12 條 demo 邊 (測試環境用)。
