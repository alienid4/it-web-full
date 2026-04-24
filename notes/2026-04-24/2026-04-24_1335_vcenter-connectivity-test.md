# 2026-04-24 13:35 — vCenter 連通性 & API 測試 (v3.12.0.0 VMware tab 準備)

**目的**：確認公司 13 可以對 5 個 vCenter 做 API 呼叫 + 讀 ESXi CPU Busy，為 v3.12.0.0「VMware 管理」tab 做準備。
**執行位置**：公司 13 (`10.92.198.13`)，任何路徑皆可（不動 `/opt/inspection`）
**帳號**：你的 VC read-only 帳號；本檔**不寫密碼**，執行時互動輸入。

---

## Stage 1 — 5 個 VC 的網路連通性 (TCP 443)

```bash
for ip in 10.93.169.191 10.93.3.191 10.93.198.121 10.93.199.191 10.93.19.191; do
  echo -n "VC $ip:443 → "
  timeout 3 bash -c "</dev/tcp/$ip/443" 2>/dev/null && echo "✅ OK" || echo "❌ FAIL"
done
```

**預期**：5 個全部 ✅ OK。
**若有 ❌**：先回報，其他 Stage 不用跑 → 要找網路組開防火牆。

---

## Stage 2 — Python / pyvmomi 環境

### 2a. Python3 確認

```bash
python3 --version
which python3
```

### 2b. pyvmomi 是否已裝

```bash
python3 -c "import pyVmomi; print('pyvmomi ok:', getattr(pyVmomi,'__version__','unknown'))"
```

- **印 `ok:` → 跳 Stage 3**
- **印 `ModuleNotFoundError` → 走 2c**

### 2c. 裝 pyvmomi (3 條路擇一)

```bash
# (i) 有外網
pip3 install --user pyvmomi

# (ii) 走內部 proxy (如果公司有)
pip3 install --user --proxy=http://<proxy-ip>:<port> pyvmomi

# (iii) 離線 wheel (家裡下載 → scp 上去)
#     家裡: pip3 download pyvmomi -d /tmp/pyvmomi_wheels
#     13上: pip3 install --user --no-index --find-links=./pyvmomi_wheels pyvmomi
```

裝完再跑一次 2b 確認。

---

## Stage 3 — 真正的功能測試：讀 ESXi CPU Busy

### 3a. 寫測試腳本

```bash
cat > /tmp/vc_cpu_test.py <<'PYEOF'
#!/usr/bin/env python3
"""v3.12.0.0 前置測試 — 驗證可取得 ESXi CPU Busy"""
import ssl, sys, getpass
from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim

VCENTERS = [
    ('10.93.169.191', '板橋'),
    ('10.93.3.191',   '內湖-1'),
    ('10.93.198.121', '內湖-2'),
    ('10.93.199.191', 'VCF'),
    ('10.93.19.191',  '敦南'),
]

def test_vc(host, location, user, pwd):
    print(f"\n=== [{location}] {host} ===")
    ctx = ssl._create_unverified_context()
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
            used = (h.summary.quickStats.overallCpuUsage or 0)
            total = 0
            if h.hardware and h.hardware.cpuInfo:
                total = (h.hardware.cpuInfo.hz // 1_000_000) * h.hardware.cpuInfo.numCpuCores
            busy = (used / total * 100) if total else 0
            print(f"  {h.name[:40]:<42}{used:>10}{total:>12}{busy:>7.1f}%")
        if len(hosts) > 10:
            print(f"  ...(另有 {len(hosts)-10} 台未列出)")
    finally:
        Disconnect(si)

if __name__ == '__main__':
    user = input("vCenter 帳號 (例 svc_xxx@vsphere.local 或 DOMAIN\\user): ").strip()
    pwd = getpass.getpass("vCenter 密碼 (不顯示): ")
    if not user or not pwd:
        print("帳密不可空"); sys.exit(1)
    for host, loc in VCENTERS:
        try:
            test_vc(host, loc, user, pwd)
        except Exception as e:
            print(f"\n=== [{loc}] {host} ===\n  ❌ 意外錯誤: {e}")
PYEOF
```

### 3b. 執行

```bash
python3 /tmp/vc_cpu_test.py
```

會先問帳號 + 密碼（密碼輸入不顯示字元）。

### 3c. 預期輸出樣貌

```
=== [板橋] 10.93.169.191 ===
  ✅ 登入成功，取得 38 台 ESXi
  Host                                      Used MHz   Total MHz   Busy%
  ------------------------------------------------------------------------
  esxi-bq-a-01.xxx.com                         18500      102400   18.1%
  esxi-bq-a-02.xxx.com                         42100      102400   41.1%
  ...
=== [內湖-1] 10.93.3.191 ===
  ...(5 個 VC 都類似)
```

---

## 回報給 Claude 的 4 項

1. **Stage 1 連通性**：5/5 通，或哪幾個 ❌
2. **Stage 2 pyvmomi**：已裝成功？走了哪條路 (i/ii/iii)？有錯誤訊息貼上
3. **Stage 3 登入**：5 個 VC 都登入成功？或某個帳號沒權限？
4. **Sample 輸出**：挑 1 個 VC 的前 3 台 ESXi 輸出貼回來（hostname 可脫敏）

有這 4 項資料，就可以開始設計 VMware 管理 tab 的真實資料結構。

---

## 資安備註

- 腳本**不寫密碼到檔案**，runtime 互動輸入，只在 process 記憶體
- 測完刪掉：`rm /tmp/vc_cpu_test.py`
- 本測試**只讀 (read-only)**，無任何修改/建立/刪除操作
- VC 帳號建議權限：`Read-only` role（不需 Administrator）
- 完成後可回收：腳本不留、帳號改回平常用途
