# 2026-04-23 15:45 — 新增第 3 台主機 + 自動全掃 SOP

## 前提 (你已確認)

- ✅ 新主機 sysinfra 帳號已建
- ✅ 13 的 sysinfra SSH pub key 已放進新主機 `~/.ssh/authorized_keys`
- ✅ sudoers 設定完成 (新主機上 sysinfra 能免密碼 sudo)

---

## Step 1 — 在 13 的 UI 加主機

打開 `http://10.92.198.13:5000/admin#hosts` → 點「**新增主機**」填：

| 欄位 | 填什麼 | 範例 |
|---|---|---|
| hostname | 短 hostname (FQDN 也行) | `SECSVR198-012T` |
| ip | 管理 IP | `10.92.198.12` |
| os_group | linux / windows | `linux` |
| os | Distro 細節 (display 用) | `RedHat 9.6` |
| ssh_user | ansible 連線使用者 | `sysinfra` |
| ssh_port | 通常 22 | `22` |
| ssh_key | 私鑰路徑 (13 上的) | `/home/sysinfra/.ssh/id_ed25519` |
| department | 單位 | (依實際) |
| custodian / ap_owner | 保管人 | (依實際) |
| tier | 金 / 銀 / 銅 | (依實際) |
| system_name | 系統別 | (依實際) |

按「儲存」。

---

## Step 2 — 重建 inventory (13 上)

新主機資料進 DB 後，`ansible/inventory/hosts.yml` 也要重產：

```bash
cd /opt/inspection/scripts
sudo -u sysinfra python3 generate_inventory.py
cat /opt/inspection/ansible/inventory/hosts.yml | head -50   # 確認新主機在裡面
```

---

## Step 3 — 驗證 SSH / ansible 通

```bash
# 單獨 SSH 測試
sudo -u sysinfra ssh -o StrictHostKeyChecking=no sysinfra@<新主機IP> whoami
# 預期: sysinfra

# ansible ping
cd /opt/inspection/ansible
sudo -u sysinfra ansible <新主機hostname> -i inventory/hosts.yml -m ping
# 預期: <新主機> | SUCCESS => "ping":"pong"
```

如果 ping 失敗 → 檢查 Step 1 填的 ssh_user/ssh_port/ssh_key 是否對，回 UI 改再重跑 Step 2。

---

## Step 4 — 一口氣自動全掃（4 種功能）

**重點**：下一段 shell 會跑完「完整巡檢 + 套件盤點 + TWGCB + nmon 啟用 + seed」— 新主機從此完全納管。

```bash
NEWHOST="<新主機hostname>"   # e.g. SECSVR198-012T, 照實改
cd /opt/inspection

# 4.1 完整巡檢 (site.yml + collect_packages + seed_data + CIO snapshot)
#     也會觸發 account_audit role → account_audit collection
sudo -u sysinfra /opt/inspection/run_inspection.sh
# 約 2~5 分鐘

# 4.2 TWGCB 合規掃描 (single host)
cd /opt/inspection/ansible
sudo -u sysinfra ansible-playbook playbooks/twgcb_scan.yml \
  -i inventory/hosts.yml --limit "$NEWHOST" \
  --vault-password-file /opt/inspection/.vault_pass
# 掃完自動匯入 twgcb_results collection

# 4.3 啟用 nmon 效能採集 (若要收效能月報)
mongosh inspection --quiet --eval "
  db.hosts.updateOne(
    {hostname: '$NEWHOST'},
    {\$set: {nmon_enabled: true, nmon_interval_min: 5}}
  );
  print('nmon_enabled set for', '$NEWHOST');
"
# 下次 run_inspection.sh 會跑 collect_nmon 對它 (或手動再跑一次 4.1 也行)
```

---

## Step 5 — 驗證新主機在 4 個頁面都有

1. **Dashboard** `/` — 卡片應該出現 `<新主機hostname>` + CPU/MEM/Disk/Swap 數字
2. **今日報告** `/report` — 有新主機那列
3. **帳號盤點** `/audit` — 新主機的帳號出現（含 root + 高權限）
4. **TWGCB 合規** `/twgcb` — 新主機列在 Linux tab，有合規率
5. **軟體盤點** `/packages` — 套件清單含新主機
6. **效能月報** `/perf` — 新主機選單出現（要等 5 分鐘後有 nmon 資料才顯示圖）

---

## 簡化版一鍵腳本（候選 v3.11.18.0）

若之後每次加主機都手動跑這些太煩，可以做一個 `onboard_new_host.sh`：

```bash
sudo /opt/inspection/scripts/onboard_new_host.sh <hostname>
```

自動跑 Step 2~4。要我下版做嗎？

---

## 回傳 / 告訴我

1. 新主機的 **hostname / IP / OS** 是什麼？
2. 跑完 Step 4.1 的輸出（特別看 PLAY RECAP 新主機的 ok/fail 數）
3. Step 5 的 Dashboard 截圖（看到 3 台）
