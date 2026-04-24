# 2026-04-24 15:15 — ESXi GBIC DOM 手動測試 (光模組衰減值)

**目的**：確認 ESXi 主機的 `esxcli` 能拿到 SFP/GBIC 的 Digital Optical Monitoring (DOM) 值，為 v3.12.0.0 VMware+GBIC tab 做準備。
**執行**：挑 **1 台 ESXi** 測即可，不用全部 100 台。
**預計時間**：5 分鐘。

---

## Stage 1 — 先開 ESXi SSH Service

ESXi 預設 SSH 是關的，要先在 vSphere Client 開啟：

```
vSphere Client → 選一台 ESXi host → 設定 (Configure)
 → 服務 (Services) → SSH → 啟動 (Start) 或 編輯啟動原則
```

或用 esxcli 遠端開（如果你已經有其他入口）：
```bash
# 在 vCenter 主機上
# (這段我們 v3.12.0.0 tab 做好後可以自動處理，現在手動)
```

**備註**：測完記得把 SSH 關回去（資安原則）。

---

## Stage 2 — SSH 到 ESXi + 查 transceiver

```bash
# 從你的工作機
ssh root@<esxi-ip>

# 進入後 (ESXi shell)
esxcli network nic list
```

應該列出 vmnic0 / vmnic1 / vmnic2 ... 一堆 NIC，每個有 MAC、driver、link state、speed。

**挑一張 speed 是 10000 Mbps（10Gb）的 vmnic**（通常是光纖 / GBIC），例如 `vmnic0`。

---

## Stage 3 — 查該 NIC 的 transceiver DOM

```bash
# 列所有 NIC 的 transceiver
esxcli network nic transceiver list

# 看某張 NIC 的完整 DOM
esxcli network nic transceiver get --nic=vmnic0
```

### 預期輸出（成功 — 支援 DOM 的 NIC）

```
vmnic0
   Vendor Name      : Cisco Systems
   Part Number      : SFP-10G-SR
   Serial Number    : FNS12345678
   Revision         : V01
   Wavelength       : 850 nm
   Transceiver Type : 10G Base-SR
   Fibre Type       : Multi-mode 50 um
   Temperature      : 42.5 C
   Voltage          : 3.3 V
   Tx Power         : -2.5 dBm          ← 發送功率
   Rx Power         : -4.8 dBm          ← 接收功率 ★老闆要看的
   Bias Current     : 6.2 mA
```

### 預期輸出（失敗 — 舊 NIC 驅動不支援 DOM）

```
Error: Unable to query transceiver information
```
或
```
vmnic0
   Vendor Name : (空白或 Unknown)
   Tx Power    : N/A
   Rx Power    : N/A
```

---

## 回報給 Claude 的 5 項

1. **SSH 可不可以開** (能進 ESXi shell)
2. **`esxcli network nic list`** 的輸出（第一行 header + 前 3 台 NIC，可脫敏 MAC）
3. **`esxcli network nic transceiver list`** 完整輸出（這會列出所有 NIC 的 SFP 基本資訊）
4. **`esxcli network nic transceiver get --nic=vmnicX`** 其中 1 張 10G NIC 的完整輸出（**最關鍵**，看 Rx Power / Tx Power 有沒有值）
5. **測試的 ESXi host 機型** (vendor/model，例如 Cisco UCS / HPE ProLiant / Dell PowerEdge) — 決定 NIC 驅動能不能讀 DOM

---

## 為什麼要測這個

- vCenter API **完全不給** SFP DOM 資訊
- 只能 SSH 到 ESXi 跑 esxcli
- **不同 NIC 廠牌支援度不同**：Intel、Mellanox、Broadcom 主流新卡都支援；較舊的 QLogic / 某些 Emulex 可能不支援
- 確認你們家的卡支援後，才能設計自動化

---

## 老闆為什麼關心 Rx Power

| Rx Power (10G SR) | 狀態 | 說明 |
|---|---|---|
| `-3` ~ `-9` dBm | 🟢 正常 | 健康 |
| `-9` ~ `-12` dBm | 🟠 衰減加劇 | 光纖髒污、接頭老化 |
| `-12` ~ `-14` dBm | 🔴 即將故障 | 準備更換 |
| `< -14` dBm | ⚫ 失效 | Link down |

**預測性維護**：Rx Power 連續 30 天逐步下滑 = 光纖劣化前兆 → 能提早排程更換，避免 production 突然斷線。

---

## 測完的下一步

1. 確認 DOM 支援 → 我設計 Ansible playbook 蒐集所有 ESXi
2. 存 MongoDB (時序：每 8H 一筆 DOM 快照)
3. 做 GBIC 子頁：每 host NIC 清單 + Rx 功率即時值 + 30 天趨勢
4. 月報加一頁：GBIC 衰減清單（TOP 10 下滑最快、接近閾值的 NIC）

---

## 資安備註

- 本 notes **不含任何實際 IP / FQDN / 帳號 / 密碼**
- SSH 到 ESXi 建議用 key-based auth（下一步 v3.12.0.0 正式實作時會改成 key）
- 測試完**關閉 ESXi SSH service**
- `esxcli network nic transceiver get` 是**read-only** 指令，不改任何設定
