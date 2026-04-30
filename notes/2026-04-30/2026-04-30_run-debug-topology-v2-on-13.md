# 13 上跑 debug_topology.sh v2 — 對症「關聯線跑不出來/畫面空白」

**為什麼**: 昨天 (2026-04-29) 裝完 v3.17.10.4 + 設 cron，今天回報拓撲頁畫面空白連 dep-meta 都沒。
這比典型「0 邊」更上游，靠對話一條條問太慢。改用擴充版 debug 腳本一次掃齊，只印異常。

**派送**: GitHub release `debug-topology-v2` (asset: debug_topology.sh, 16KB)，13/11 直接 `gh release download` 抓，不走 patches/ 也不 scp。

**腳本變動**:
- v1 (commit c3da6a8) → v2 (release debug-topology-v2)
- v1 只能驗 8 點且 `_topology_from_hosts` 已不存在會 ImportError
- v2 修掉，改驗 v3.17.10.x 的 `topology()` 三個 view，並新加 6 段 (採集紀錄 / host_refs 反查 / HTTP 三路由 / journalctl traceback / cron / ansible log)
- 預設 quiet mode (OK 不印,異常才印)

---

## 步驟 1. 在 13 抓 release asset

```bash
ssh sysinfra@<13-ip>
gh release download debug-topology-v2 -p debug_topology.sh -O /tmp/debug_topology.sh
ls -la /tmp/debug_topology.sh   # 確認 ~16KB,LF 換行
```

Release URL: https://github.com/alienid4/it-web-full/releases/tag/debug-topology-v2

(IP 從 ~/.ssh/config 或 ~/.xxx.local 帶,依 memory feedback_no_real_ip_in_notes 不寫對話)

---

## 步驟 2. 跑 (quiet mode)

```bash
sudo bash /tmp/debug_topology.sh 2>&1 | tee /tmp/dep_debug_$(date +%H%M).log
```

**預期輸出兩種狀態**:

### A. 全綠 (無 [FAIL]/[WARN])

只印一行：
```
✅ 全部關鍵檢查通過
  但 dep_rel = 0 → 點 toolbar『📡 採集』, 等 1-3 分按『📊 狀態』
```
或其他 hint。

→ 把這行貼回對話，按 hint 操作。

### B. 有異常

範例：
```
=== 9. dependency_collect_runs 最新一筆 ===
[FAIL] 最近一次採集 failed — error: Permission denied (publickey)
    對照 SOP Step 6: notes/2026-04-29/...

=== 10. host_refs 反查 (採集寫邊的關鍵) ===
[WARN] 4/4 主機都不在任何 system.host_refs → 採集寫不出邊
    去 /admin → 拓撲管理 tab → 設 system 與 host_refs

=== 11. HTTP 路由 (對症畫面空白) ===
[FAIL] /dependencies → HTTP/1.1 500 Internal Server Error
```

→ 把整段紅黃字貼回對話，會直接對症修。

---

## 開後門 (debug 自己)

如果腳本本身可疑、想看全部檢查項目都跑哪些：

```bash
sudo VERBOSE=1 bash /tmp/debug_topology.sh 2>&1 | tee /tmp/dep_debug_v_$(date +%H%M).log
```

VERBOSE=1 會印所有 [OK] 行和 mongosh 原始輸出。

---

## 未來修腳本

source 仍在 `patches/debug_topology.sh`，改完後重 release：

```bash
# 本機改完
gh release create debug-topology-v3 patches/debug_topology.sh \
  --title "debug-topology-v3 — <describe change>" \
  --notes "..."
```

不 `--clobber` 舊 tag (memory feedback_release_tag_immutable)。

---

## 各段在驗什麼 (給 alienlee 自己心裡有底)

| # | 段名 | 驗的東西 | fail 代表 |
|---|---|---|---|
| 1 | Web 服務 | systemctl is-active | 服務沒起來 |
| 2 | 版本 | version.json | 沒升 v3.17.10.4 |
| 3 | Collection 計數 | hosts/dep_sys/dep_rel/dep_runs/feature_flags | 種子資料缺或 feature flag 關 |
| 4 | 關鍵檔案 | dep_service / api / 模板 / JS 是否在 | patch 沒裝完整 |
| 5 | 開頭污染 | js/template 第一行有沒有 SSH warning `**` | scp 拉檔時 stderr 灌進檔頭 (memory feedback_ssh_stderr_pollution) |
| 6 | Python topology() | 三 view 各跑一次,驗 edge id 完整性 | API schema 壞掉 |
| 7 | webapp log | 末 200 行 grep error/traceback | 服務有 runtime error |
| 8 | HTTP 基本 ping | /login + /api/dependencies/topology | 路由層死了 |
| **9** | **dep_collect_runs** | **最新一筆採集狀態** | **採集 fail 或從沒跑過** |
| **10** | **host_refs 反查** | **hosts ↔ system.host_refs orphan** | **採集寫不出邊 (邊 = 0 的根因)** |
| **11** | **HTTP 三路由** | **/dependencies + fullscreen + ghosts body** | **模板渲染斷或 500** |
| **12** | **journalctl** | **systemd 30 分內 traceback** | **服務在吐 exception** |
| **13** | **cron** | **MARK_DEP_COLLECT 排程是否設過** | **沒排過 = 採集只能手動** |
| **14** | **ansible log** | **dep_collect_*.log 末 30 行** | **ansible task 細節 (採集 fail 才印)** |

(粗體 9-14 是 v2 新加)

---

## 收工

跑完把輸出貼回對話。我會根據 [FAIL]/[WARN] 段對症給下一步。
