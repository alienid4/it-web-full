# ~/.claude/ 環境升級 v1.0 → v2.2.0

> 紀錄日期: 2026-05-05
> 紀錄組: notes-writer subagent
> 參考來源: Claude Code 系統化教程 2026/04 PDF
> 警告: 此檔已範例化，實 IP 放 ~/.xxx.local

---

## 背景

閱讀《Claude Code 系統化教程 2026/04》PDF 後，依 PDF 建議對本機 `~/.claude/` 環境做全面升級。

舊版: v1.0 (3 組件: CLAUDE.md + version-check.sh + stop-sanity.sh)
新版: v2.2.0 (13 組件: 3 hooks + 4 skills + 6 subagents + templates)

---

## 完成項目

### 1. 新增 Hooks

#### safety-guard.sh (PreToolUse)

套用在 Bash + Edit|Write 兩個 matcher。

硬擋規則 (exit code 2，直接中止):
- `rm -rf` 打到系統路徑 (例: /etc, /usr, /bin，但 /tmp、/var/tmp 放行)
- Bash 工具寫入 settings.json
- `git commit --no-verify`
- `git push --force`

警告規則 (exit code 0，印警告繼續):
- Edit/Write `.env` 檔
- Edit/Write `.ssh/` 目錄下的檔案

測試結果: 16/16 通過

#### settings.json 更新

加入 safety-guard.sh 到兩個 matcher:
```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/safety-guard.sh" }] },
      { "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/safety-guard.sh" }] }
    ]
  }
}
```

---

### 2. 新增 Skills (自動觸發)

#### plan-mode
- 觸發關鍵字: 「設計」「規劃」「我想做」「plan」等
- 四階段 SOP: Explore → Plan → Implement → Verify
- Explore 階段必讀相關檔案，不能憑空設計

#### worktree-helper
- 觸發: 口頭描述需要同時處理多個任務的情境
- 三種情境自動執行對應 git worktree 指令:
  1. Hot-fix 插隊: 開新 worktree 不干擾主線
  2. 多功能並行: 各 feature 獨立 worktree
  3. A-B 比較: 兩個 worktree 跑同一測試對比

#### model-advisor
- 每訊息結尾自評目前任務複雜度
- 主動建議使用者打 `/model sonnet` 或 `/model opus`
- 限制: Claude Code 不支援自動切換 model，只能建議，使用者手動下指令

---

### 3. 新增 Subagents (Agent Team 完整版)

| Agent | 模型 | 職責 |
|---|---|---|
| code-reviewer | Sonnet | fresh-context 看 git diff，7 大紀律錯誤 |
| inspection-planner | Opus | 接需求產 spec/plan 到 ~/.claude/plans/ |
| deploy-validator | Sonnet | smoke test 7步，retry 5x2s |
| twgcb-auditor | Sonnet | TWGCB/FCB 金融業合規稽核 |
| patch-bundler | Sonnet | release tarball 打包，5 鐵律 |
| notes-writer | Sonnet | 對話結論 → notes/，自動 sanitize IP/帳密 |

---

### 4. 修改既有 Skills

以下 3 個 skill 加入 `disable-model-invocation: true`，避免被自動呼叫產生副作用:
- `deploy/SKILL.md`
- `credentials/SKILL.md`
- `secclient1-remote/SKILL.md`

---

### 5. 更新 Plugin

名稱: inspection-feedback-loop v2.2.0

包含:
- 3 hooks (version-check.sh / stop-sanity.sh / safety-guard.sh)
- 4 skills (plan-mode / worktree-helper / model-advisor / sanity-check)
- 6 agents (上表)
- templates/ 目錄

install.sh 5步一鍵安裝，支援 Windows git-bash:
1. 複製 hooks → ~/.claude/hooks/
2. 複製 skills → ~/.claude/skills/
3. 複製 agents → ~/.claude/agents/
4. 複製 templates → ~/.claude/templates/
5. 更新 settings.json (merge，不覆蓋既有設定)

Windows 路徑: 改用 forward slash，settings.json 用 `CLAUDE_HOME_PLACEHOLDER` 在安裝時替換。

---

### 6. 更新 CLAUDE_FRAMEWORK.md

版本: v1.0 → v2.2

新增內容:
- 全組件表格 (hooks / skills / agents 三大類)
- 「模型選擇策略」章節:
  - Opus: 架構設計、跨系統規劃、新功能需求分析
  - Sonnet: 日常 coding、patch、deploy、notes 整理
  - Haiku: 快速查詢、格式轉換、單純問答

---

## 技術重點 / 踩坑紀錄

### Agent Team 並行呼叫
必須在**同一訊息**發出多個 Agent 呼叫才能真正並行。
分開兩則訊息發出 = 循序執行，無法加速。

### safety-guard.sh regex 修正
初版誤擋 `/tmp` 和 `/var/tmp`，導致正常暫存操作被攔截。
修正: 明確列出危險路徑 (不用萬用 `/`)，/tmp 系列明確放行。

### model-advisor 限制
Claude Code API 不支援 agent 自動切換 model。
model-advisor 只能輸出文字建議，使用者需自行在 UI 打 `/model sonnet`。

### Plugin 跨機安裝 Windows 路徑
Windows `~/.claude/` 實際路徑含空格 (例: `C:/Users/User/...`)。
settings.json hook command 必須用 forward slash + 雙引號包路徑。
install.sh 用 `CLAUDE_HOME_PLACEHOLDER` 在安裝時 sed 替換。

---

## 環境版本對照

| 組件 | v1.0 | v2.2.0 |
|---|---|---|
| Hooks | 2 (version-check / stop-sanity) | 3 (+safety-guard) |
| Skills | 1 (sanity-check) | 4 (+plan-mode / worktree-helper / model-advisor) |
| Subagents | 0 | 6 |
| Plugin 版本 | 無 | inspection-feedback-loop v2.2.0 |
| 框架文件 | CLAUDE_FRAMEWORK.md v1.0 | v2.2 |

---

## 下一步

- [ ] 公司 13 (192.168.1.13) git pull 後確認 notes-writer subagent 可正常 commit
- [ ] 測試 plan-mode 關鍵字觸發是否如預期
- [ ] safety-guard.sh 在公司機上做一次 dry-run 驗證 16 個 case
- [ ] 考慮 inspection-planner (Opus) 觸發時機，避免 token 浪費
