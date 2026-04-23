# 2026-04-23 09:55 — v3.11.10.0 修 CPU 固定顯示 100% bug

## 根因

`AI/ansible/roles/check_cpu/tasks/linux.yml` 原本用：

```bash
vmstat 1 3 | tail -1 | awk '{print 100 - $15}'
```

某些環境下（RHEL 9 + 特定套件），`vmstat` 輸出欄位對不上 $15 位置，或 `tail -1` 抓到 header 行導致 `$15` 變字串 `id` / `st` → awk 數值運算當 0 → `100 - 0 = 100` → **固定顯示 100%**。

你實測 13 本機 `vmstat 1 3`：
```
r b swpd free buff cache si so bi bo in cs us sy id wa st
1 0    0 13108632 4320 2329576 0 0 1 11 83 123 1 0 99 0 0
```
$15=99（id），本該是 `100-99=1`，但實際跑出來 100。

## 治本

改用 **mpstat** 優先、**top** fallback，都不依賴欄位位置：

```bash
if command -v mpstat >/dev/null 2>&1; then
  LANG=C mpstat 1 1 | awk 'END{v=100-$NF; print int(v+0.5)}'   # mpstat 最後欄是 %idle
else
  LANG=C top -bn1 | awk -F'[ ,%]+' '/Cpu\(s\)/ {for(i=1;i<=NF;i++) if($i=="id") {print int(100-$(i-1)+0.5); exit}}'
fi
```

- `mpstat`：來自 `sysstat` 套件（13/11 應已裝，run_inspection 能跑起來代表有），最後一欄一定是 `%idle`，用 `$NF` 穩拿
- `top -bn1` fallback：`LANG=C` 強制英文 locale 防中文 "使用率" 破 awk；用 `id` 關鍵字找欄位而非位置

## 套用（13 上）

### Step 1 — 下載單檔

```
https://github.com/alienid4/it-web-full/raw/main/AI/ansible/roles/check_cpu/tasks/linux.yml
```

scp / USB 到 13 的 `/tmp/linux.yml`。

### Step 2 — 覆蓋 + 驗證命令本地能跑

```bash
# 備份 + 覆蓋
sudo cp /opt/inspection/ansible/roles/check_cpu/tasks/linux.yml \
        /opt/inspection/ansible/roles/check_cpu/tasks/linux.yml.bak.$(date +%Y%m%d_%H%M)
sudo cp /tmp/linux.yml /opt/inspection/ansible/roles/check_cpu/tasks/linux.yml
sudo chown sysinfra:itagent /opt/inspection/ansible/roles/check_cpu/tasks/linux.yml

# 先驗證命令本地能跑出合理數字
command -v mpstat >/dev/null && echo "mpstat 存在" || echo "無 mpstat, 會用 top fallback"
LANG=C mpstat 1 1 2>/dev/null | awk 'END{print "mpstat 使用率:", int(100-$NF+0.5)"%"}'
LANG=C top -bn1 | awk -F'[ ,%]+' '/Cpu\(s\)/ {for(i=1;i<=NF;i++) if($i=="id") {print "top 使用率:", int(100-$(i-1)+0.5)"%"; exit}}'
```

**預期**：兩個數字都在合理範圍（0~20%，除非機器真的很忙）。

### Step 3 — 重跑 inspection 產新 JSON

```bash
sudo -u sysinfra /opt/inspection/run_inspection.sh
```

### Step 4 — 驗證

```bash
# 看新 JSON 的 cpu_percent
sudo ls -t /opt/inspection/data/reports/inspection_*.json | head -2 | \
  xargs -I{} sh -c 'echo "--- {} ---"; sudo cat {} | python3 -c "import sys,json; d=json.load(sys.stdin); print(\"cpu_percent:\", d[\"results\"][\"cpu\"].get(\"cpu_percent\"))"'
```

**預期**：看到合理數字（e.g. `cpu_percent: "0"` 或 `"1"` 或 `"5"`）。

### Step 5 — F5 Dashboard

CPU 應該從 100% 變成實際使用率（可能 0~5%）。

---

## 回傳

1. **Step 2** 兩條命令的 mpstat / top 輸出數字
2. **Step 4** 的 `cpu_percent` 值
3. Dashboard 截圖（CPU 欄位新數字）

---

## 如果 mpstat 輸出失敗

如果 Step 2 `mpstat` 沒有數字（`sysstat` 沒裝），就看 top fallback 有沒有中。若也失敗，貼 `which mpstat` 和 `LANG=C top -bn1 | head -5` 原始輸出，我再調 awk。
