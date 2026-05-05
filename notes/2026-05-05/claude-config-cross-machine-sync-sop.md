# ~/.claude/ 跨機同步 SOP

> 紀錄日期: 2026-05-05
> 紀錄組: notes-writer subagent
> 已實測: PC + NB 雙向同步通過
> 敏感值: 已範例化；實值放本機環境，不上 repo

---

## 背景

`~/.claude/` 設定從單機升級成跨 PC + NB 雙機自動同步。

---

## 架構決策

考慮過 3 種方案，選 **git private repo**:

| 方案 | Symlink | OneDrive 直接同步 | **Git private repo (採用)** |
|---|---|---|---|
| Session 衝突風險 | 高 | 高 | 無 |
| 認證安全 | 上雲，風險 | 上雲，風險 | 留本機 |
| 改錯能回滾 | 無 | OneDrive 30天 | git history |
| 跨平台 | Windows-only | Windows-only | 任何 OS |

**理由**: `~/.claude/` 混了 (1) 設定 (2) Session 資料 (3) 認證。前兩種方案把全部綁一起同步，
造成衝突 + 認證上雲洩漏風險。

---

## 一、源機 (有完整設定那台) 設定

```bash
# 在 git-bash 執行
cd ~/.claude
git init
```

### .gitignore 排除清單

```
# 認證 (絕對不能上雲)
.credentials.json

# Session / runtime 資料
projects/
sessions/
todos/
history.jsonl
plans/

# 執行時暫存
logs/
cache/
telemetry/
shell-snapshots/
auto-sync.log
*.log

# 從 GitHub 拉的，不需同步
plugins/marketplaces/
```

### .gitattributes

```
*.sh text eol=lf
```

(鐵律: Linux 主機拉 .sh 必須 LF，Windows OneDrive 會寫成 CRLF)

### settings.json 路徑修正

把寫死的絕對路徑換成 `$HOME` 變數，跨機才能用。

### 建 GitHub private repo

```bash
# 絕對不要 public — agent 指示檔含 RFC1918 內網 IP
gh repo create claude-config --private
git remote add origin https://github.com/<USERNAME>/claude-config.git
git push -u origin main
```

---

## 二、源機 auto-sync 設定 (每 15 分鐘自動 commit + push)

腳本路徑: `~/.claude/scripts/auto-sync.ps1`

### 關鍵邏輯順序

```
commit 本地變動 → pull --rebase → push
```

**不能反過來**: 先 pull --rebase 會被「未 commit 變動」拒絕 (踩過的雷 #2)。

### 註冊 Windows Task Scheduler (PowerShell)

```powershell
schtasks /Create /SC MINUTE /MO 15 /TN "ClaudeConfigSync" `
  /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$env:USERPROFILE\.claude\scripts\auto-sync.ps1`"" `
  /F /RL LIMITED
```

---

## 三、新機器 (NB / 公司 / 其他) 加入

1. **先關掉所有 CC 視窗** (避免檔案鎖)

2. 備份 credentials (如果有舊 ~/.claude/):

```bash
# git-bash
mkdir -p ~/claude-backup-$(date +%Y%m%d)
cp ~/.claude/.credentials.json ~/claude-backup-$(date +%Y%m%d)/
```

3. Clone — **必須在 git-bash，不能用 PowerShell** (踩過的雷 #1):

```bash
# git-bash
rm ~/.claude        # 如果是 symlink 先移除 (不會刪 OneDrive 實檔)
git clone https://github.com/<USERNAME>/claude-config.git ~/.claude
```

4. 還原 credentials:

```bash
cp ~/claude-backup-*/.credentials.json ~/.claude/.credentials.json
```

5. 註冊 scheduled task (PowerShell):

```powershell
schtasks /Create /SC MINUTE /MO 15 /TN "ClaudeConfigSync" `
  /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$env:USERPROFILE\.claude\scripts\auto-sync.ps1`"" `
  /F /RL LIMITED
```

---

## 四、驗證方法 (從快到慢)

| 方法 | 指令 |
|---|---|
| 看 log | `tail -f ~/.claude/auto-sync.log` |
| 看 task 狀態 | `schtasks /Query /TN "ClaudeConfigSync" /FO LIST` |
| GUI | Win+R → `taskschd.msc` |
| 看 GitHub commit | 應有 `auto-sync from <hostname>` commits |
| 主動測試 | 隨便改檔 → 觸發 task → 看另一台是否收到 |

---

## 五、踩過的雷

### 雷 1: PowerShell 不展開 `~`

- **症狀**: `git clone https://... ~/.claude` 在 PowerShell 看似成功，實際 clone 到
  `C:\Windows\System32\~\.claude\` 詭異路徑
- **原因**: PowerShell 5.1 不像 bash 自動展開 `~` 給 git
- **解法**: clone 必須在 git-bash；PowerShell 只用來跑 schtasks

### 雷 2: pull --rebase 拒絕未 commit 變動

- **症狀**: log 出現 `FAIL pull (rebase conflict)` 但實際只是 working tree 有未 commit 的檔
- **原因**: 原版腳本邏輯是 pull → commit → push，順序反了
- **解法**: 改成 commit → pull → push (本版採用)

### 雷 3: OneDrive symlink 干擾

- **症狀**: NB 原本 `~/.claude` 是 symlink → OneDrive 資料夾，clone 時 OneDrive 那邊已有檔案
  造成詭異狀態
- **解法**: 先 `rm ~/.claude` 移除 symlink，不會刪 OneDrive 實檔，再 fresh clone

### 雷 4: log 檔被 commit

- **症狀**: 每次 sync 跑一次就產生一個 commit (auto-sync.log 自己變動了)
- **解法**: 加 `*.log` + `auto-sync.log` 到 .gitignore

### 雷 5: agent 指示檔含 RFC1918 IP

- **症狀**: notes-writer / nmon-verify 等 agent 指示檔含內網 IP (給 agent sanitize 規則用)
- **解法**: repo 必須 **private**，內部 IP 雖不可路由，但敏感資訊不宜公開

---

## 六、日常維護指令

```bash
# 拉新設定 (開始工作前)
cd ~/.claude && git pull

# 手動推 (改完設定立刻推)
cd ~/.claude && git add . && git commit -m "chore: <說明>" && git push

# 看哪些檔被 ignore
cd ~/.claude && git status --ignored

# 強制觸發 sync (不等 15 分鐘)
schtasks /Run /TN "ClaudeConfigSync"

# 移除 scheduled task
schtasks /Delete /TN "ClaudeConfigSync" /F
```

---

## 七、衝突處理 (邊緣 case)

兩台機同時改同一檔同一行，rebase 會卡住，log 出現 `FAIL pull (rebase conflict)`。

```bash
cd ~/.claude
git status          # 看哪些檔 conflict
# 手動編輯解 conflict (移除 <<<<<<< ======= >>>>>>> 標記)
git add <衝突檔>
git rebase --continue
git push
```

---

## 附：範例值對照

| 實值類型 | 範例化寫法 |
|---|---|
| 公司內網 IP (Class A 私網) | `192.168.1.13` / `192.168.1.221` |
| GitHub token | `${GH_TOKEN}` |
| 帳號 | `<USERNAME>` |
| 密碼 / secret | `${SECRET}` |
