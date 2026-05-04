# v3.17.13.0 — NMON 部署狀態驗證面板

## 動機

部署 NMON 後沒有「驗證」入口 — 使用者勾選主機按「套用」之後，無法一眼看出：
- ansible 真的跑成功了嗎？
- 主機上 cron 設好了嗎？
- nmon binary 裝起來了嗎？
- 已經開始採樣了嗎？
- 資料有進 nmon_daily collection 嗎？

之前只能 SSH 進主機跑 `crontab -l` / `which nmon` / `ls /var/log/nmon/` / `mongosh` 4 步驟手動驗證。
而 Claude 自己無法 SSH 公司 13/11，要協助使用者更難。

## 改動

| 檔案 | 變更 |
|---|---|
| `scripts/verify_nmon.py` | **新檔**: 對所有 `nmon_enabled=true` 主機跑 ansible -m shell, 一次抓 cron+binary+log+proc 4 項輸出 + 跨表查 `nmon_daily` 今日筆數. 支援 `--json` 給 web API 用 / 不加給 CLI 用 |
| `webapp/routes/api_nmon.py` | 加 `GET /api/nmon/verify` endpoint, subprocess 呼叫 verify_nmon.py --json (timeout 200s) |
| `webapp/templates/admin.html` | 在 NMON 排程 card 下方加「📊 NMON 部署狀態」card + 「🔍 立即檢查」按鈕 |
| `webapp/static/js/admin.js` | 新增 `verifyNmonDeployment()` function, 渲染表格 + 摘要列 (🟢/🟡/🔴/⚫) |
| `~/.claude/skills/nmon-verify/SKILL.md` | **新 skill**: Claude 下次接到「驗證 NMON」之類問題會自動引導使用者用此面板 + 4 層驗證 SOP + 故障對照表 |

## UI

```
系統管理 → 監控平台管理 → 效能月報管理
└── nmon 採樣排程 (既有)
└── 📊 NMON 部署狀態 ← 新加
     [🔍 立即檢查] 按鈕
     摘要: 總計 4 台 | 🟢 3 OK | 🟡 0 部分 | 🔴 1 失敗 | ⚫ 0 連不上
     表格:
        | 狀態 | 主機 | OS | cron | bin | log | proc | 今日 DB | 細節 |
        | 🟢   | 011T | rhel | ✓ | ✓ | ✓ | ✓ | 12 | (空) |
        | 🔴   | 015T | rhel | ✗ | ✗ | ✗ | ✗ | 0  | nmon binary 沒裝 (公司隔離環境抓不到 EPEL?) |
```

## 部署

```bash
gh release download v3.17.13.0 -R alienid4/it-web-full --pattern 'patch_combo_v3.17.13.0.tar.gz' -D /tmp
cd /tmp && tar -xzf patch_combo_v3.17.13.0.tar.gz
cd v3.17.13.0-nmon-verify-panel && sudo bash install.sh
```

## Smoke 預期

```
[OK]   HTTP /login = 200
[OK]   import mongo_service.get_hosts_col / get_collection
[OK]   verify_nmon.py import + parse_check_output/run_ansible_check OK
[INFO] 試跑 verify_nmon.py --json:
{"hosts": [...], "summary": {"total": 4, "ok": 3, "fail": 1, ...}}
[OK]   systemctl is-active itagent-web
```

## 回滾

```bash
TS=20260504_xxxxxx
cp /opt/inspection/webapp/routes/api_nmon.py.bak.${TS}    /opt/inspection/webapp/routes/api_nmon.py
cp /opt/inspection/webapp/templates/admin.html.bak.${TS}  /opt/inspection/webapp/templates/admin.html
cp /opt/inspection/webapp/static/js/admin.js.bak.${TS}    /opt/inspection/webapp/static/js/admin.js
rm /opt/inspection/scripts/verify_nmon.py
systemctl restart itagent-web
```

## 不影響的事

- 不改 nmon 排程邏輯 (api_nmon.py 的 `/schedule` POST 完全不動)
- 不改 collect_nmon ansible role (cron 設定方式照舊)
- 不改 nmon_daily collection schema
- 純讀取性質, 不會改 hosts 任何欄位
