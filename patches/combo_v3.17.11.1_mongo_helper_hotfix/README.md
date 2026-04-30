# v3.17.11.1 — hot-fix v3.17.11.0 ImportError get_hosts_col

## 13 上裝 v3.17.11.0 的症狀

```
Active: activating (auto-restart) (Result: exit-code)
ImportError: cannot import name 'get_hosts_col' from 'services.mongo_service'
```

systemd auto-restart 一直撞同一個錯, restart_counter 攀升。

## 雙根因

1. **本機 `mongo_service.py:22` 寫成無限遞迴 bug**
   - 原: `def get_hosts_col(): return get_hosts_col()` ← 自己呼叫自己
   - 修: `def get_hosts_col(): return get_collection("hosts")`

2. **13 上 mongo_service.py 沒有 get_hosts_col helper**
   - v3.14.2.0 重構引入這 helper, 但 13 從來沒裝過完整 baseline
   - v3.17.10.x 系列 hot-fix 都只動拓撲檔, 沒帶 mongo_service.py
   - v3.17.11.0 patch 用了新版 api_admin.py + dependency_service.py 都 import `get_hosts_col` → ImportError

## 改動

| 檔案 | 動作 |
|---|---|
| `webapp/services/mongo_service.py` | **修無限遞迴 + 補進 13** (使用者環境第一次拿到此 helper) |
| `webapp/services/dependency_service.py` | 同 v3.17.11.0 (含 sync_systems_from_hosts helper) |
| `webapp/routes/api_admin.py` | 同 v3.17.11.0 (含業務系統欄解析) |

## install.sh 改進

- **retry curl 5 次每次 sleep 2** 取代固定 sleep 3 (memory feedback_install_sleep_too_short)
- **import 鏈真跑一次** sudo -u sysinfra python3 import, 比 AST 強一級
- **smoke 全綠才回 ✅** 包含 HTTP / AST / helper / import 4 項

## 部署

```bash
gh release download v3.17.11.1 -p '*.tar.gz' -O /tmp/p11_1.tar.gz
cd /tmp && tar -xzf p11_1.tar.gz
cd combo_v3.17.11.1_mongo_helper_hotfix && sudo bash install.sh
```

## 適用環境

- 已經裝壞 v3.17.11.0 的環境 (像 13) → 直接覆蓋, 救起來
- 還沒裝 v3.17.11.0 的環境 → 直接裝這顆, 跳過 v3.17.11.0
- 家裡 221 (本機 baseline 同步) → 也建議裝, 修 mongo_service.py:22 無限遞迴 (雖然之前沒被觸發)

## 緊急回滾

如果這顆也壞:
```bash
sudo cp -r /var/backups/inspection/v3.17.11.1_<TS>/webapp/* /opt/inspection/webapp/
sudo systemctl restart itagent-web
```
