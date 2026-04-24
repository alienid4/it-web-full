# 2026-04-24 13:35 — vCenter 連通性 & API 測試 (v3.12.0.0 VMware tab 準備)

**目的**：確認巡檢系統主機可對公司 5 個 vCenter 做 API 呼叫 + 讀 ESXi CPU Busy。
**執行位置**：巡檢系統主機 (公司)
**帳號**：VC read-only 帳號；本檔**不寫密碼**。

> **資安備註**：本檔**不寫入任何實際 IP / FQDN / 帳號 / 密碼**。
> 實際位址由執行者從內部資料自行填入，建議寫到 `~/.vc_ips.local`（已加入 `.gitignore`，不 commit）。

---

## 前置：建立本地 IP 清單 (不落地到 repo)

```bash
# 在執行機上建立本地清單檔，格式：每行一個「IP<TAB>位置標籤」
# 檔案放使用者 home，不會被 commit
cat > ~/.vc_ips.local <<'EOF'
# 填入實際 IP，格式：IP<space>位置
VC_IP_1 板橋
VC_IP_2 內湖-1
VC_IP_3 內湖-2
VC_IP_4 VCF
VC_IP_5 敦南
EOF
chmod 600 ~/.vc_ips.local
# 編輯實際 IP：vi ~/.vc_ips.local
```

---

## Stage 1 — 網路連通性 (TCP 443)

```bash
while read -r ip label; do
  [[ "$ip" =~ ^# || -z "$ip" ]] && continue
  echo -n "[$label] $ip:443 → "
  timeout 3 bash -c "</dev/tcp/$ip/443" 2>/dev/null && echo "✅ OK" || echo "❌ FAIL"
done < ~/.vc_ips.local
```

**預期**：5 個全 ✅。若有 ❌ → 找網路組開防火牆，其他 Stage 不用跑。

---

## Stage 2 — Python / pyvmomi 環境

```bash
# 2a. Python3
python3 --version && which python3

# 2b. pyvmomi 是否已裝
python3 -c "import pyVmomi; print('pyvmomi ok:', getattr(pyVmomi,'__version__','unknown'))"
```

**若 `ModuleNotFoundError`**：
```bash
# 有外網
pip3 install --user pyvmomi

# 走 proxy
pip3 install --user --proxy=http://<proxy>:<port> pyvmomi

# 離線 wheel (家裡 download → scp 上去)
#   家裡: pip3 download pyvmomi -d /tmp/pyvmomi_wheels
#   機上: pip3 install --user --no-index --find-links=./pyvmomi_wheels pyvmomi
```

---

## Stage 3 — VC 登入 + 讀 ESXi CPU Busy

### 3a. 寫測試腳本 (讀 `~/.vc_ips.local`，不內嵌 IP)

```bash
cat > /tmp/vc_cpu_test.py <<'PYEOF'
#!/usr/bin/env python3
"""v3.12.0.0 前置測試 — 驗證可取得 ESXi CPU Busy (IP 從 ~/.vc_ips.local 讀)"""
import ssl, sys, os, getpass
from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim

def load_vcs():
    path = os.path.expanduser('~/.vc_ips.local')
    vcs = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split(None, 1)
            ip = parts[0]
            label = parts[1] if len(parts) > 1 else ip
            vcs.append((ip, label))
    return vcs

def test_vc(host, label, user, pwd):
    print(f"\n=== [{label}] {host} ===")
    ctx = ssl._create_unverified_context()
    try:
        try:
            si = SmartConnect(host=host, user=user, pwd=pwd, sslContext=ctx,
                              disableSslCertValidation=True)
        except TypeError:
            si = SmartConnect(host=host, user=user, pwd=pwd, sslContext=ctx)
    except Exception as e:
        print(f"  ❌ 連線/登入失敗: {e}")
        return

    try:
        content = si.RetrieveContent()
        cv = content.viewManager.CreateContainerView(
            content.rootFolder, [vim.HostSystem], True)
        hosts = cv.view
        print(f"  ✅ 登入成功，取得 {len(hosts)} 台 ESXi")
        print(f"  {'Host':<42}{'Used MHz':>10}{'Total MHz':>12}{'Busy%':>8}")
        print("  " + "-" * 72)
        for h in hosts[:10]:
            used = h.summary.quickStats.overallCpuUsage or 0
            total = 0
            if h.hardware and h.hardware.cpuInfo:
                total = (h.hardware.cpuInfo.hz // 1_000_000) * h.hardware.cpuInfo.numCpuCores
            busy = (used / total * 100) if total else 0
            print(f"  {h.name[:40]:<42}{used:>10}{total:>12}{busy:>7.1f}%")
        if len(hosts) > 10:
            print(f"  ...(另有 {len(hosts)-10} 台未列出)")
        cv.Destroy()
    finally:
        Disconnect(si)

if __name__ == '__main__':
    vcs = load_vcs()
    if not vcs:
        print("~/.vc_ips.local 是空的或只有註解行"); sys.exit(1)
    user = input("vCenter 帳號: ").strip()
    pwd = getpass.getpass("vCenter 密碼 (不顯示): ")
    if not user or not pwd:
        print("帳密不可空"); sys.exit(1)
    for ip, label in vcs:
        try:
            test_vc(ip, label, user, pwd)
        except Exception as e:
            print(f"\n=== [{label}] {ip} ===\n  ❌ 意外錯誤: {e}")
PYEOF
```

### 3b. 執行

```bash
python3 /tmp/vc_cpu_test.py
```

### 3c. 測完立刻清理

```bash
rm /tmp/vc_cpu_test.py
history -c && history -w
```

---

## 回報給 Claude 的 4 項

1. **Stage 1 連通性**：5/5 通，或哪幾個 ❌
2. **Stage 2 pyvmomi**：已裝成功？走哪條路？錯誤訊息貼上
3. **Stage 3 登入**：5 個 VC 都登入成功？
4. **Sample 輸出**：1 個 VC 的前 3 台 ESXi 輸出（hostname + IP 都脫敏）

---

## 資安備註

- 本檔**不含**任何實際 IP / FQDN / 帳號 / 密碼
- 實際 IP 放 `~/.vc_ips.local` (600 權限，不 commit)
- 腳本**不寫密碼到檔案**，runtime 互動輸入
- 測完刪腳本 + 清 bash history
- **只讀 (read-only)**，無任何修改/建立/刪除操作
- VC 帳號建議：`Read-only` role（不需 Administrator）
