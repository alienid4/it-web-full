# 兩地開發換機 Checklist

> **核心原則**: code 只在 git 上同步,本機 working copy 各自管。
> **路徑可不同**: PC 在 `F:\ClaudeHome\CL_webit`、NB 在 `C:\ClaudeHome\CL_webit`。BAT 自動偵測。

---

## 三台機器角色

| 機器 | Tailscale IP | 路徑 | 用途 |
|---|---|---|---|
| **PC (alien-6f-2024)** | 100.90.1.127 | `F:\ClaudeHome\CL_webit` | 晚上開發 |
| **NB (alien-fuji)** | 100.66.104.82 | `C:\ClaudeHome\CL_webit` | 白天開發 |
| **secansible** | 100.102.166.2 | `/opt/inspection` | 巡檢系統部署/runtime |

GitHub repo: `alienid4/it-web-full` (private)

---

## 雙擊就好的捷徑

兩個 BAT 都在 `CL_webit/scripts/` 內,**透過 git 自動同步兩台**:

| BAT | 何時用 |
|---|---|
| `scripts/pull-then-open.bat` | **開工**: 開機 / 換到這台 |
| `scripts/commit-and-push.bat` | **收工**: 關機 / 換去另一台前 |

兩個 BAT 內建**自動偵測**邏輯:會找 `F:\ClaudeHome\CL_webit` 跟 `C:\ClaudeHome\CL_webit`,哪台用什麼路徑都通用。

---

## (一次性) 建桌面捷徑

每台機器各自建一次,就能從桌面雙擊執行。

### PC 端 (PowerShell)
```powershell
$ws = New-Object -ComObject WScript.Shell
$d = [Environment]::GetFolderPath('Desktop')
$s1 = $ws.CreateShortcut("$d\開工.lnk")
$s1.TargetPath = "F:\ClaudeHome\CL_webit\scripts\pull-then-open.bat"
$s1.WorkingDirectory = "F:\ClaudeHome\CL_webit"
$s1.Save()
$s2 = $ws.CreateShortcut("$d\收工.lnk")
$s2.TargetPath = "F:\ClaudeHome\CL_webit\scripts\commit-and-push.bat"
$s2.WorkingDirectory = "F:\ClaudeHome\CL_webit"
$s2.Save()
```

### NB 端 (PowerShell)
```powershell
$ws = New-Object -ComObject WScript.Shell
$d = [Environment]::GetFolderPath('Desktop')
$s1 = $ws.CreateShortcut("$d\開工.lnk")
$s1.TargetPath = "C:\ClaudeHome\CL_webit\scripts\pull-then-open.bat"
$s1.WorkingDirectory = "C:\ClaudeHome\CL_webit"
$s1.Save()
$s2 = $ws.CreateShortcut("$d\收工.lnk")
$s2.TargetPath = "C:\ClaudeHome\CL_webit\scripts\commit-and-push.bat"
$s2.WorkingDirectory = "C:\ClaudeHome\CL_webit"
$s2.Save()
```

---

## 開工 SOP

1. **桌面雙擊「開工」** (或執行 `scripts/pull-then-open.bat`)
   - 自動 cd 進 CL_webit
   - 跑 `git pull` 拉另一台的最新
   - 開 VS Code
2. 看 BAT 顯示「最近 5 個 commit」是否有預期的進度
3. 開工

**如果 pull 失敗**: BAT 會提示處理方法 (通常是本機有忘 commit 的東西,要 stash)。

---

## 收工 SOP

1. **桌面雙擊「收工」** (或執行 `scripts/commit-and-push.bat`)
2. 輸入 commit 訊息
   - code 改動: `feat(v3.x.y.z): 改了什麼`
   - 文件/筆記: `docs: ... [skip-version]`
3. BAT 自動 `add -A` + `commit` + `push`
4. 看到「收工完成」就可以關機

**如果 commit 被擋** (version-check hook):
- 文件/筆記類 → 訊息結尾加 `[skip-version]`
- code 改動 → 先 bump `version.json` 再雙擊一次 BAT

**如果 push 被擋** (另一台先 push 了):
- 跑 `git pull --rebase` (在 Git Bash 裡)
- 再雙擊 BAT

---

## 換機緊急情況

### 情境 A: 忘了在另一台 push,現在這台又開發了

```bash
cd /c/ClaudeHome/CL_webit       # PC 用 /f/ClaudeHome/CL_webit
git stash                        # 把這台的改動暫存起來
# 回另一台 push (或 SSH 進去 push)
git pull                         # 拉另一台的進度
git stash pop                    # 把這台的改動疊回
# 解 conflict (如果有)
```

### 情境 B: 兩台同時改同一個檔案

`git pull` 會回 conflict,VS Code 會標紅綠藍三色。逐檔解完:
```bash
git add <解完的檔>
git commit                       # commit message 預設就是 merge 訊息,可直接存
git push
```

### 情境 C: 想看另一台 commit 但沒拉下來

```bash
git fetch                        # 不動 working copy,只拉 metadata
git log origin/main --oneline    # 看另一台推了什麼
git diff HEAD origin/main        # 看具體改了什麼
```

---

## 跟 secansible (巡檢部署主機) 互動

從 NB / PC **任何終端** (不需 VPN,走 Tailscale):

```bash
ssh secansible                   # 進 shell
ssh secansible "uptime"          # 一次性指令
scp file secansible:/tmp/        # 傳檔
```

部署巡檢系統到 secansible 時,SOP 另外寫 (在巡檢系統 deploy 文件裡)。

---

## 不要做的事

- ❌ **把 `~/.ssh/` 同步到 OneDrive** (私鑰外洩)
- ❌ **把 `ClaudeHome\CL_webit` 放到 OneDrive 下** (`.git/` 會打架,LF/CRLF 會炸)
- ❌ **兩台同時不 push 就跨機開發** (一定會 conflict)
- ❌ **直接在 secansible 上 `vim` 改 code** (改了沒 push 回 git,下次部署會被覆蓋)

---

## 檢查清單 (每次換機 30 秒)

**開工前**:
- [ ] 雙擊「開工」桌面捷徑
- [ ] 看到「最近 5 個 commit」是另一台的進度
- [ ] VS Code 開起來

**收工前**:
- [ ] 雙擊「收工」桌面捷徑
- [ ] 輸入有意義的 commit 訊息
- [ ] 看到「收工完成」
- [ ] (可選) 在另一台跑 `git fetch` 確認 push 上去了

---

> 此筆記建立於 2026-05-06, NB 端 Tailscale + GitHub SSH 設定當天。
> 路徑或 hook 規則改了,記得更新此檔。
