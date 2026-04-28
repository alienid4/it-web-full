# v3.17.7.0 CMDB 整合 combo (給公司 13)

**從 v3.11.x ~ v3.16.x 任何版本一次升到 v3.17.7.0**

## 內容

| Phase | 功能 | 動的東西 |
|---|---|---|
| P1 | hosts 加 ips array + aliases array | DB schema |
| P2 | 重複/相似主機偵測 (Levenshtein) | 新頁 + 新 service |
| P6 | 變更歷史 (auto-record + timeline UI) | 新 collection + hooks |
| P3 | IPAM 網段管理 | 新 collection + 新頁 + 使用率 bar |
| P4 | Excel/CSV 對帳 (3 欄看板) | 新頁 + openpyxl |
| P5 | 孤兒主機 + 稽核曝光 (6 道防線狀態) | 新頁 |
| 拓撲 | 節點直接從 hosts 派生 (不再雙表維護) | 重寫 _topology_from_hosts |
| Nav | 主機管理拉到 top nav (大項目) | base.html |

## 部署

```bash
# 在 13 上 (root)
cd /tmp
tar xzf patch_combo_v3.17.7.0.tar.gz
cd combo_v3.17.7.0_cmdb_for_13
bash install.sh
```

install.sh 會自動：
- 偵測 INSPECTION_HOME (`/opt/inspection` 或 `/seclog/AI/inspection`)
- 偵測 podman / docker
- 偵測 web service 名稱
- 備份所有改動檔案 + hosts collection 到 `/var/backups/inspection/v3.17.7.0_<TS>/`
- 部署 22 個檔案
- 跑 3 個 idempotent DB migration
- 6 步 smoke test + 6 個 service 函式 contract check

## 風險

- ⚠️ **未在 13 真實環境測試過**, 若 13 已部署過部分 v3.12.x / v3.13.x patch, 會被覆蓋
- ⚠️ admin.html / app.py / api_admin.py 是整檔替換 — 13 上若有獨有改動會被洗掉
- ⚠️ 建議先在閒置時段做, 萬一爆掉用 backup 回滾

## 回滾

```bash
BACKUP=/var/backups/inspection/v3.17.7.0_<TS>
cp -r $BACKUP/webapp/* /opt/inspection/webapp/
podman exec -i mongodb mongoimport --db inspection --collection hosts --drop < $BACKUP/hosts.json
systemctl restart itagent-web itagent-tunnel
```
