# VMware Collector 設定指南

## 檔案清單

```
data/vmware/
├── vcenters.yaml.sample      範本 (無實 IP, 可 commit)
├── vcenters.yaml             實際 VC 清單 (本機 only, chmod 600)
└── vc_credentials.vault      ansible-vault 加密 (帳號+密碼)
```

## 初次設定 (3 步)

### 1. 建 `vcenters.yaml`

```bash
cd $INSPECTION_HOME/data/vmware
cp vcenters.yaml.sample vcenters.yaml
vi vcenters.yaml              # 填入實際 5 個 VC 的 IP + label
chmod 600 vcenters.yaml
chown sysinfra:sysinfra vcenters.yaml
```

### 2. 建加密 credentials

```bash
cd $INSPECTION_HOME/data/vmware

# 走 .vault_pass (既有; 若無則走互動模式)
ansible-vault create vc_credentials.vault \
  --vault-password-file $INSPECTION_HOME/.vault_pass
```

編輯器打開後填入 (YAML 格式):

```yaml
user: "administrator@vsphere.local"
password: "YourRealPasswordHere"
```

存檔後會變 `$ANSIBLE_VAULT;1.1;AES256` 開頭的加密檔。

```bash
chmod 600 vc_credentials.vault
chown sysinfra:sysinfra vc_credentials.vault
```

### 3. 測試 collector

**先 dry-run 單台** (不寫 MongoDB, 只確認可以連線抓資料):

```bash
cd $INSPECTION_HOME
sudo -u sysinfra python3 collector/vcenter_collector.py --only 板橋 --dry-run -v
```

看到每個 VC 的 `cluster_count` / `host_count` 有值 → OK。

**正式跑 (寫 MongoDB)**:

```bash
sudo -u sysinfra python3 collector/vcenter_collector.py
```

## 驗證 MongoDB

```bash
mongosh inspection --eval "
db.vmware_snapshots.find({}, {
  timestamp:1, 'vcenter.label':1, status:1,
  cluster_count: {\$size: '\$clusters'},
  host_count: {\$size: '\$hosts'}
}).sort({timestamp:-1}).limit(5).pretty()
"
```

## Cron (每 8 小時)

v3.12.1.0 patch install.sh 會自動裝:

```
/etc/cron.d/inspection-vmware-collect:
0 */8 * * * sysinfra /usr/bin/python3 $INSPECTION_HOME/collector/vcenter_collector.py >> $INSPECTION_HOME/logs/vcenter_collector.log 2>&1
```

## 資安

- `vcenters.yaml` 含實 IP → chmod 600, 不 commit
- `vc_credentials.vault` → ansible-vault 加密 + chmod 600
- `.vault_pass` → 600, 絕不 commit
- Collector 嚴格 read-only (見程式碼註解)
- 即使用 administrator 帳號, 只讀 summary/quickStats/config

## Rollback

```bash
sudo rm /etc/cron.d/inspection-vmware-collect
sudo rm -rf $INSPECTION_HOME/collector
```
