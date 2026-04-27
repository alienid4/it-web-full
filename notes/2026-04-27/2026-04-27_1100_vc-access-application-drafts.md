# 2026-04-27 11:00 — VMware 巡檢申請草稿（防火牆 + AD 帳號）

目的：跑 dry-run 時 13 連 VC 卡 TCP connect (防火牆擋)，需走兩個申請：
1. 防火牆白名單：13 → 5 個 vCenter TCP/443
2. AD 服務帳號：vCenter 唯讀，給巡檢 collector 用

**敏感資訊請填回實際值再送出**（本檔已範例化）。

---

## 草稿 1：防火牆通訊申請

```
【防火牆通訊申請】

申請類別：新增白名單
申請事由：巡檢系統 vCenter 資源監控 (主管月報)

【來源】
主機: <巡檢主機 hostname>  (例: SECSVR-XXX-XXX)
IP:   <巡檢主機 內部 IP>
所屬: 資安巡檢系統 (IT 巡檢)
業務系統: 巡檢系統 - VMware 管理模組

【目的】
主機: vCenter Server (5 台)
- 板橋 VC      <填入 IP>
- 內湖-1 VC    <填入 IP>
- 內湖-2 VC    <填入 IP>
- VCF VC       <填入 IP>
- 敦南 VC      <填入 IP>

【協定 / Port】
TCP/443 (HTTPS, vSphere SOAP API)
方向: 單向 (來源 → 目的)

【用途說明】
1. 巡檢系統使用 pyvmomi 9.0 SDK 經 vSphere SOAP API 連線
2. 嚴格 read-only：僅呼叫 RetrieveContent / CreateContainerView 讀取
   Cluster / ESXi 主機 / CPU / Memory / 版本資訊
3. 程式碼層級限制：絕不呼叫 Create / Modify / Destroy / PowerOn / PowerOff
4. 抓取頻率: 每 8 小時 1 次 (00:00 / 08:00 / 16:00)
5. 資料用途: 寫入巡檢系統 MongoDB, 供主管月報與每日開門檢查使用

【資安說明】
- 連線帳號使用 AD 服務帳號 (申請中, 詳見另一申請單)
- 密碼以 ansible-vault AES256 加密儲存於巡檢主機
- 連線過程不寫入任何 vCenter 資料
- 巡檢結果僅儲存在巡檢系統內部 MongoDB

【後續維運】
連線異常時, 巡檢系統會在 logs/vcenter_collector.log 留 ERROR log,
並在 /vmware 頁面顯示對應 VC 為「pending」狀態 (橘燈)。
不會自動重試, 等下次 8H cron 觸發。

【預計上線日期】
<填入>

申請人: <你的名字>
單位: <你的單位>
連絡電話: <電話>
```

---

## 草稿 2：AD 服務帳號申請（給 vCenter 用）

```
【AD 服務帳號申請】

申請類別：新建 AD 服務帳號
申請事由：巡檢系統 vCenter 唯讀監控

【建議帳號名稱】
svc-inspection-vmware  (或 svc_inspection_vmware, 依公司命名規範)

【帳號類型】
服務帳號 (Service Account)
- 永不過期 (建議; 或設 1 年到期+提醒換密碼)
- 不允許互動式登入 (僅供 API 使用)
- 密碼複雜度: 16 字元以上, 含大小寫+數字+符號

【權限需求】
位置: vCenter Server (5 台均需加入)
角色: Read-Only (vCenter 內建角色)
Scope: 根目錄 (Root Folder) - 含所有 Datacenter / Cluster / Host / VM
傳播: 是 (Propagate to children)

【明確需要的 vCenter 權限項目】
- System.Anonymous (內建)
- System.View (內建)
- System.Read (內建)
以上即 Read-Only 角色預設包含, 不需額外加權限

【明確「不需要」的權限】
- 任何 Configuration / Modify 類權限
- VirtualMachine.Interact.* (PowerOn / PowerOff)
- VirtualMachine.Provisioning.*
- Host.Config.*
- 任何 Write 類權限

【使用主機】
<巡檢主機 hostname>  (例: SECSVR-XXX-XXX)
IP: <巡檢主機 內部 IP>
所屬: 巡檢系統

【密碼存放】
ansible-vault AES256 加密
路徑: /opt/inspection/data/vmware/vc_credentials.vault
主密鑰: /opt/inspection/.vault_pass (檔案權限 600, owner sysinfra)

【使用頻率】
每 8 小時自動登入 1 次 (cron 排程)
每次連線 5 個 vCenter, 抓完即登出 (Disconnect)

【替代方案】
若不便建專屬服務帳號, 可暫用唯讀角色之既有帳號
但長期建議獨立帳號以便日後稽核 (Who accessed what when)。

【預計上線日期】
<填入>

申請人: <你的名字>
單位: <你的單位>
```

---

## 送出前 checklist

- [ ] 5 個 VC 真實 IP 填回
- [ ] 巡檢主機 hostname + IP 填回
- [ ] 申請人 / 單位 / 電話填回
- [ ] 預計上線日期填回
- [ ] AD 帳號命名對齊公司規範
- [ ] 確認公司是否要附「資安掃描報告」或「網段風險評估表」

## 上線後驗證

防火牆 + AD 帳號都到位後：

1. 改 vCenters.yaml 5 個真實 IP
2. ansible-vault edit vc_credentials.vault 換成新 AD 帳號 (`svc-inspection-vmware@vsphere.local` 或實際 UPN)
3. 跑 dry-run 驗一台：
   ```bash
   sudo -u sysinfra python3 /opt/inspection/collector/vcenter_collector.py \
     --only 板橋 --dry-run -v
   ```
4. 過了再跑全 5 VC 真寫入

對應 SOP：`notes/2026-04-27_1015` (vault) + `notes/2026-04-27_1030` (first real collect)

---

## 為什麼會卡

2026-04-27 10:17 在 13 上跑 dry-run 連 `<某 VC IP>` → traceback 卡在 `http/client.py line 1447, in connect: super().connect()`，意思是 TCP 三次握手都沒完成，**純網路層卡住**（不是程式 bug、不是帳密錯）。預期防火牆開通後問題自動解。
