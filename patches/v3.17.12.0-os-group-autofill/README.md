# v3.17.12.0 — os_group autofill

## 解決的問題

公司 13 (v3.17.11.1) 的「系統管理 → 監控平台管理 → NMON 效能採樣排程」頁面，
4 台主機全部顯示「不支援 (?)」，無法勾選。

## 根因

1. `api_nmon.py` L92 的 NMON 支援白名單看 `hosts.os_group` 欄位 (`rhel`/`rocky`/`centos`/`debian`/`ubuntu`/`aix`/`linux`)
2. `hosts.os_group` 卻是空的，因為:
   - **v3.17.10.1** 加了 `os_parse.py` + `import_csv` hook 自動推 OS family
   - **v3.17.11.0** csv_business_system patch **回退** 了 `import_csv`，把 v3.17.10.1 的 hook 整個搞丟
   - 之後 import 進來的主機 `os_group` 全部空白
3. 即使 hook 在，原版只填 `os` (family) 跟 `os_version`，**從沒填 `os_group`**

## 改動 (兩條路線)

### A 路線 (主) — ansible 連目標主機真實抓 OS
| 檔案 | 變更 |
|---|---|
| `scripts/probe_os.py` | **新檔**: 跑 `ansible all -m setup -a 'gather_subset=min'` 抓 `ansible_distribution` / `ansible_distribution_version`，查 DIST_MAP 對應 → (family, os_group) 寫回 hosts。連不上的主機標 `reachable=false`，不覆寫既有 os_group |
| `webapp/routes/api_admin.py` | 新增 `POST /api/admin/hosts/probe-os` endpoint，subprocess 呼叫 probe_os.py，timeout 200s |
| `webapp/templates/admin.html` | NMON 排程頁加「🔄 重新偵測 OS」按鈕 (套用按鈕旁) |
| `webapp/static/js/admin.js` | 新增 `probeAllHostsOS()` function，呼叫 API 後自動 refresh NMON 主機列表 + 彈窗摘要 |

### B 路線 (備援) — CSV 字串解析
| 檔案 | 變更 |
|---|---|
| `webapp/services/os_parse.py` | 加 `_FAMILY_TO_GROUP` mapping、`family_to_group(family)`、`infer_os_group(os_str)` |
| `webapp/routes/api_admin.py` | 加 `_autofill_os_fields(doc)`，被 `add_host` / `edit_host` / `import_csv` 三處 hook 共用，自動從 OS 字串補 os/os_version/os_group |
| `scripts/csv_to_inventory.py` | OS_MAP 加 `RedHat` (沒空格) / `Red Hat` / `AlmaLinux` / `Oracle Linux` 兜底；`detect_os_group` 改 long-first 比對 |
| `scripts/fix_os_group.py` | **新檔**: 一次性掃 hosts collection，補既有空 os_group 主機，先 dump backup |

A 蓋過 B：B 先補字串能解的 → A 再用真實 OS 蓋過去。連不上的主機 (sudo NOPASSWD 沒設 / 防火牆) 至少還有 B 路線的字串解析結果。

## 部署

```bash
tar -xzf patch_combo_v3.17.12.0.tar.gz
cd v3.17.12.0-os-group-autofill
sudo bash install.sh
```

`install.sh` 會：
- 自動偵測 `INSPECTION_HOME` (公司 `/opt/inspection` / 家裡 `/seclog/AI/inspection`)
- 備份既有 3 個檔案 (`.bak.${TS}`)
- 部署 4 個檔案 (含新 `fix_os_group.py`)
- bump `version.json` 到 `3.17.12.0`
- restart systemd service (`itagent-web` / `itagent` / `inspection-web` 自動偵測)
- 跑 `fix_os_group.py` 修既有資料
- Smoke test (HTTP / Python import + 8 個 OS 案例 / mongosh NMON 可勾主機數 / systemd 狀態 / log)

## Smoke 預期輸出

```
[OK]   HTTP /login = 200
[OK]   Python smoke 全綠
  NMON 可勾選 = 4 / 4 (空/unknown 還剩 0)
[OK]   systemctl is-active itagent-web
```

## 回滾

```bash
TS=20260504_xxxxxx   # 看 install.sh 印出的時間戳
cp /opt/inspection/webapp/services/os_parse.py.bak.${TS} /opt/inspection/webapp/services/os_parse.py
cp /opt/inspection/webapp/routes/api_admin.py.bak.${TS}  /opt/inspection/webapp/routes/api_admin.py
cp /opt/inspection/scripts/csv_to_inventory.py.bak.${TS} /opt/inspection/scripts/csv_to_inventory.py
rm /opt/inspection/scripts/fix_os_group.py
systemctl restart itagent-web
# 既有資料修正不會自動回滾, 如需還原: 從 /opt/inspection/data/backups/hosts_pre_os_group_fix_*.json restore
```
