# v3.12.1.0 COMBO

VMware tab 全套：prereq + w1 + collector 一條命令裝完。

## 13 上裝法

```bash
cd /tmp
curl -fLO https://github.com/alienid4/it-web-full/releases/download/v3.12.1.0-combo/patch_v3.12.1.0-combo.tar.gz
tar xzf patch_v3.12.1.0-combo.tar.gz
sudo bash v3.12.1.0-combo/install.sh
```

## 結構（tarball 內）

```
v3.12.1.0-combo/
├── install.sh               主 wrapper (跑 3 顆子 install.sh)
├── patch_info.txt
├── README.md (本檔)
├── 01_prereq/               = v3.12.0.0-vmware-prereq 全部內容
├── 02_w1/                   = v3.12.0.0-vmware-tab-w1 全部內容
└── 03_collector/            = v3.12.1.0-vmware-collector 全部內容
```

## 重新打包（給開發者）

```bash
cd patches
rm -rf v3.12.1.0-combo/01_prereq v3.12.1.0-combo/02_w1 v3.12.1.0-combo/03_collector
cp -r v3.12.0.0-vmware-prereq    v3.12.1.0-combo/01_prereq
cp -r v3.12.0.0-vmware-tab-w1    v3.12.1.0-combo/02_w1
cp -r v3.12.1.0-vmware-collector v3.12.1.0-combo/03_collector
tar czf ../patch_v3.12.1.0-combo.tar.gz v3.12.1.0-combo/
gh release create v3.12.1.0-combo ../patch_v3.12.1.0-combo.tar.gz --title "..."
# 打包後刪掉 01_/02_/03_ 不 commit (避免 git 重複)
rm -rf v3.12.1.0-combo/01_prereq v3.12.1.0-combo/02_w1 v3.12.1.0-combo/03_collector
```

## 為什麼 git 不收 01_/02_/03_

子 patch 已經是獨立目錄存在於 `patches/v3.12.0.0-vmware-prereq/` 等，combo 收子 patch 會造成 git 內容重複。
打包時臨時複製進來、打完包刪掉。
