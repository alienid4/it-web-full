# IT Inspection System — 離線部署 repo

RHEL 9 巡檢系統（Flask + MongoDB + Ansible），支援離線/受限網路環境一鍵部署。

---

## 📦 Repo 結構

```
it-web-full/
├── AI/                            完整巡檢系統程式碼（v3.11.2.0）
│   ├── ansible/                   playbooks + roles（Linux/Windows/SNMP/AS400）
│   ├── webapp/                    Flask 應用
│   ├── scripts/                   管理腳本
│   └── data/                      範本與說明
├── setup_testenv.sh               ★ 一鍵安裝腳本（RHEL 9）
├── verify_stack.py                架構驗證工具
└── README.md
```

**離線依賴**（MongoDB RPM + 44 個 pip wheel，201MB）**另在 GitHub Release**：
→ https://github.com/alienid4/it-web-full/releases

---

## 🚀 安裝方式（兩種擇一）

### 方式 A：測試機能 git clone + HTTPS 對外

```bash
git clone https://github.com/alienid4/it-web-full.git /AI
cd /AI
sudo ./setup_testenv.sh
```

`setup_testenv.sh` 會 `curl` 從 Release 自動下載 201MB tarball。

---

### 方式 B：測試機無 git、無對外網路（IE + FTP 流程）

適用封閉環境。**Win10 端下載 + FTP 上傳**。

**① Win10 IE 下載 2 個檔**

| 檔名 | 網址 |
|---|---|
| `it-web-full-main.zip`（~2MB） | https://github.com/alienid4/it-web-full/archive/refs/heads/main.zip |
| `inspection_offline_deps_v3.11.2.0.tar.gz`（201MB） | https://github.com/alienid4/it-web-full/releases/download/v3.11.2.0/inspection_offline_deps_v3.11.2.0.tar.gz |

**② FTP 上傳兩檔** 到測試機 `/home/sysinfra/`

**③ 測試機解壓 + 安裝**

```bash
cd /home/sysinfra
sudo unzip it-web-full-main.zip -d /
sudo mv /it-web-full-main /AI
sudo mv inspection_offline_deps_v3.11.2.0.tar.gz /AI/
cd /AI
sudo ./setup_testenv.sh
```

`setup_testenv.sh` 找到同目錄 tarball 會直接解壓使用，**不會嘗試連網**。

---

## ⚙️ setup_testenv.sh 執行內容（11 步）

1. **環境檢查** — root、RHEL、AI/ 目錄、python3
2. **引導設定** — 問 install dir / MongoDB / Flask port / admin 密碼 / SMTP（有預設值）
3. **下載/解壓依賴** — 若 AI/rpms、AI/whls 不存在，自動尋找或 curl 下載 tarball
4. **裝 MongoDB RPM**（離線）— MongoDB 6.0.27 八件套
5. **裝 python3-ldap**（Satellite dnf）
6. **裝 Python wheel**（離線，從 AI/whls/）
7. **部署程式碼** → `/opt/inspection`
8. **寫 config/env/vault**（自動產生 SECRET_KEY 與 vault 密碼）
9. **產生 Ansible SSH key**
10. **初始化 MongoDB**（superadmin 帳號 + indexes）
11. **建 systemd + 防火牆 + 啟動 + HTTP 驗證**

完成後：
- Web 管理介面：`http://<IP>:5000/admin`
- 管理指令：`itagent status | start | stop | log`

---

## 🧪 驗證工具

光驗證架構（不跑完整 Flask）：
```bash
python3 verify_stack.py
```

起最小 Flask（/health 端點）：
```bash
python3 verify_stack.py --serve
```

---

## 🔒 Sanitize 規則

所有對外公開版本已清：
- SSH 私鑰、.env、.vault_pass（真實密碼）
- 客戶識別字樣（`國泰`、`Cathay`）
- 內網 IP（`192.168.1.x`）、內部主機名（`secansible`、`secclient1`）
- 內部路徑（`/seclog/AI/`）
- SECURITY_REPORT、PROJECT_HANDOFF、TWGCB_PLAN 等內部文件

Repo 為 Private；任何 commit 前先跑：
```bash
grep -rE "國泰|cathay|secansible|secclient|/seclog|192\.168\.1\.(19|100|110|221|222)" AI/ setup_testenv.sh
# 必須 0 命中
```

---

## 🏷️ 版本

- Repo 版本：v3.11.2.0-testenv
- 對應 Release：v3.11.2.0
- Python：3.9.21 (RHEL 9 內建)
- MongoDB：6.0.27

## 📂 延伸文件

- [`AI/data/INSTALL_GUIDE.md`](AI/data/INSTALL_GUIDE.md) — 安裝手冊
- [`AI/data/ITAGENT_MANUAL.md`](AI/data/ITAGENT_MANUAL.md) — 運維手冊
- [`AI/data/RUNBOOK.md`](AI/data/RUNBOOK.md) — 常用操作手冊
