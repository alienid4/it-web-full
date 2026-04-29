# v3.17.10.4 hot-fix — 採集 default --limit 寫死 hostname → 改 all

## 問題

13 上手動點「📡 採集」(或 cron 跑) 一律失敗:
```
[WARNING]: Could not match supplied host pattern, ignoring: secansible
[WARNING]: Could not match supplied host pattern, ignoring: secclient1
[WARNING]: Could not match supplied host pattern, ignoring: sec9c2
ERROR! Specified inventory, host pattern and/or --limit leaves us with no hosts to target.
```

## 根因

兩處寫死了**家裡 221 環境的 hostname** (secansible / secclient1 / sec9c2):

- `webapp/routes/api_dependencies.py:243` UI 觸發採集的 fallback
  ```python
  limit_arg = f"--limit {shlex.quote(limit)}" if limit else "--limit 'secansible:secclient1:sec9c2'"
  ```
- `scripts/run_dep_collect.sh:35` cron wrapper 的 fallback
  ```bash
  LIMIT_HOSTS="${DEP_COLLECT_LIMIT:-secansible:secclient1:sec9c2}"
  ```

公司 13 inventory 是 SECSVR198-013T / SECSVR198-015T 等, 沒這 3 個 hostname → ansible 對不到 → 0 個目標 host → 採集失敗。

跟 memory「不准 hardcode INSPECTION_HOME」同類問題, 不該寫死跨環境會變的東西。

## 修法

兩處 default 都改成 `all` (採 inventory 全部 host):
- playbook 內已有 `when: ansible_system | lower == "linux"`, 非 Linux host (Windows/AIX) 自動跳過, 安全
- UI/cron 仍能傳具體 limit 覆蓋 (selective collect 場景不變)

## 改動檔案 (2 個)

- `webapp/routes/api_dependencies.py`
- `scripts/run_dep_collect.sh`

## 安裝

```bash
sudo bash install.sh
```

install.sh 流程: backup → cp → bump version → restart →
3 項 smoke (修法字串 / ansible inventory 列得出 hosts / /dependencies 200)。

## 驗證

裝完點「📡 採集」→ 1-3 分後點「📊 狀態」:
- ✓ status=success + edges_added > 0 → 真採到了, 重整 /dependencies 看線
- ✗ status=failed + 新 error 訊息 (unreachable / Permission denied) → 看 notes/2026-04-29 對照表往下排查 (sysinfra SSH key / sudoers / hosts.yml IP)

## 回滾

```bash
cp -r /var/backups/inspection/v3.17.10.4_TS/* /opt/inspection/
systemctl restart itagent-web
```
