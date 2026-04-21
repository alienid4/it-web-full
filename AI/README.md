# Example Corp IT 每日巡檢系統

金融業 IT 基礎設施每日自動巡檢 + TWGCB 合規管理系統。

## 快速安裝

```bash
# 解壓縮後執行引導式安裝
chmod +x install.sh
sudo ./install.sh
```

安裝腳本會引導你完成 10 個步驟：環境檢查 → 套件安裝 → MongoDB 部署 → 設定 → 啟動。

## 功能

- **每日巡檢**：Disk/CPU/Service/Account/ErrorLog/System（12項）
- **TWGCB 合規**：矩陣式燈號 + 例外管理 + Excel 匯出 + 分類摺疊
- **帳號盤點**：密碼/登入稽核 + HR 對應 + CSV 匯出
- **系統管理**：主機管理 + 備份 + Patch + 排程 + 日誌
- **多平台**：Linux / Windows / AIX / AS400

## 技術棧

Flask + MongoDB + Ansible + 原生 JS + Example Corp CI

## 文件

| 文件 | 說明 |
|------|------|
| data/PROJECT_HANDOFF.md | 完整功能總覽 |
| data/DEVLOG.md | 開發者日記 |
| data/SPEC_CHANGELOG_20260410.md | 需求變更紀錄 |
| data/INSTALL_GUIDE.md | 安裝指南 |
