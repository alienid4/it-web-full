# 2026-04-24 14:20 — VMware + LDAP 離線包 v3.12.0.0 (pyvmomi + python-ldap)

**目的**：為巡檢系統 (公司 13) 裝齊 VMware tab 前置套件 + 既有 LDAP 套件，離線一包搞定。
**檔案**：`deploy_pkg/vmware_ldap_offline_v3.12.0.0.tar.gz`（**2.0 MB**）
**gitignore**：是（依既有慣例，`*.tar.gz` 不進 git）

## 📦 內容

| 套件 | 版本 | 大小 | 安裝方式 |
|---|---|---|---|
| `pyvmomi` | 9.0.0.0 | 2.0 MB | Python wheel → `pip --user` |
| `python3-ldap` | 3.4.3 | 215 KB | Rocky 9 RPM → `dnf localinstall` |
| `python3-pyasn1` | 0.4.8 | 132 KB | Rocky 9 RPM (依賴) |
| `python3-pyasn1-modules` | 0.4.8 | 211 KB | Rocky 9 RPM (依賴) |

## 🚚 傳輸到 13

包位於本機 OneDrive（已自動同步）：
```
C:\Users\User\OneDrive\2025 Data\AI LAB\claude code\deploy_pkg\vmware_ldap_offline_v3.12.0.0.tar.gz
```

傳到 13（3 條路擇一）：

```bash
# 路徑 A: 從 221 轉發 (如果家裡 221 有 mount OneDrive)
scp vmware_ldap_offline_v3.12.0.0.tar.gz user@10.92.198.13:/tmp/

# 路徑 B: 直接從 Windows scp (WSL / PuTTY / scp.exe)
scp "deploy_pkg/vmware_ldap_offline_v3.12.0.0.tar.gz" user@10.92.198.13:/tmp/

# 路徑 C: USB 隨身碟
```

## 🛠️ 13 上安裝

```bash
cd /tmp
tar xzf vmware_ldap_offline_v3.12.0.0.tar.gz
cd vmware_ldap_offline_v3.12.0.0
chmod +x install.sh verify.sh

# 看 README 確認流程
cat README.md

# 跑安裝 (互動式；RPM 階段需要 sudo)
./install.sh
```

安裝流程：

1. **Part 1 — python3-ldap (RPM)**：若已裝跳過；沒裝走 `sudo dnf localinstall rpms/*.rpm`
2. **Part 2 — pyvmomi (wheel)**：若已裝問要不要覆蓋；沒裝走 `pip install --user --no-index --find-links=./wheels pyvmomi`

## ✅ 驗證

```bash
./verify.sh
```

應該看到：
```
✅ pyvmomi 可用
   版本 : 9.0.0.0
✅ python-ldap 可用
   版本 : 3.4.3
✅ 全部套件可用
```

## 🏃 裝完做什麼

回到 VC 連通性測試：

```bash
cd /opt/inspection
git pull
# 跑 Stage 0 (本 notes 上方那個 vcenter-connectivity-test.md 裡)
```

## 🧹 安裝後清理

```bash
rm -rf /tmp/vmware_ldap_offline_v3.12.0.0 /tmp/vmware_ldap_offline_v3.12.0.0.tar.gz
```

## ⚠️ 踩雷預防

1. **RPM 階段需要 sudo** → 你的 `sysinfra` 帳號若有 NOPASSWD，不會卡密碼；否則會提示
2. **python3 預設版本要是 3.9** → RHEL 9 預設 OK，若系統改過要確認 `python3 --version`
3. **若 pyasn1 已裝** → `dnf localinstall` 會自動跳過，不會重覆
4. **pip --user 裝到誰的 home** → 看你執行帳號；建議用 `sysinfra` 裝（因為巡檢系統以 sysinfra 跑）

## 🔒 資安備註

- 本包**不含任何實際 IP / FQDN / 帳號 / 密碼**
- RPM 來源：Rocky Linux 官方 `dl.rockylinux.org`
- Wheel 來源：PyPI 官方 `pyvmomi` package
