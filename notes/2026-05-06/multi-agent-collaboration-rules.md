# Multi-Agent 協作規則 (巡檢系統)

> 紀錄日期: 2026-05-06
> 紀錄組: notes-writer subagent
> 此為架構決策紀錄 (ADR), 無敏感資訊

---

## 背景

2026-05-06 對話中確立兩條跨機協作 / agent 使用規則,
以解決以下痛點:
- 每次 patch 任務都要使用者手動要求分工, 繁瑣
- agent spawn 預設繼承主 context 的 Opus 模型, 成本 5x 於 Sonnet

---

## 規則一: 巡檢系統 patch 任務自動 multi-agent 分工

### 原則

不需要每次詢問使用者是否要用 agent, **滿足觸發條件就自動分工**。

### 觸發條件 (任一符合即觸發)

| 條件 | 說明 |
|---|---|
| 新 patch 版本 | 例: v3.17.x.x 新版本需要規劃 |
| 跨模組變更 | 同時涉及 webapp + ansible + UI 任意兩個以上 |
| 法規相關 | 涉及 TWGCB / CIS / 法遵掃描 |
| 涉及部署 | 需要 scp / ansible-playbook 到遠端主機 |

### 標準 Pipeline

```
inspection-planner
      +
twgcb-auditor       <- 與 planner 並行
      |
      v
主 context 寫 patch
      |
      v
code-reviewer
      +
deploy-validator    <- 與 reviewer 並行
      |
      v
patch-bundler
      |
      v
notes-writer
```

**說明**:
- `inspection-planner`: 分析變更範圍、版號規劃、changelog 草稿
- `twgcb-auditor`: 對照 TWGCB / CIS 基準確認法規衝擊
- 主 context: 實際撰寫 patch 程式碼 (深度推理留 Opus)
- `code-reviewer`: 靜態分析、安全掃描、diff 審查
- `deploy-validator`: 確認部署前置條件、rollback 計畫
- `patch-bundler`: 打包 .tar.gz、產生 checksum
- `notes-writer`: 整理對話結論成 notes/YYYY-MM-DD/*.md

---

## 規則二: spawn agent 主動帶 model: "sonnet"

### 原則

spawn subagent 時**一律明確指定** `model: "claude-sonnet-4-5"` (或當前最新 Sonnet),
不繼承主 context 的 Opus 模型。

### 理由

| 模型 | 適用場景 | 成本比 |
|---|---|---|
| Opus (主 context) | 深度推理、即時對話、架構決策 | 5x |
| Sonnet (subagent) | 執行型任務: 掃描、打包、寫 notes、部署驗證 | 1x |

Sonnet 完全足夠應付執行型 subagent 的工作, 沒有理由用 Opus。

### 實作方式

```python
# spawn subagent 時明確帶 model 參數
result = agent.run(
    agent_id="notes-writer",
    model="claude-sonnet-4-5",   # 明確指定, 不繼承主 context
    prompt=summary,
)
```

---

## 同步建立的 Memory 條目

| 檔案名稱 | 內容摘要 |
|---|---|
| `feedback_proactive_agent_spawn.md` | 巡檢 patch 任務觸發條件 + pipeline 結構 |
| `feedback_agent_use_sonnet.md` | subagent 一律指定 Sonnet, 不繼承 Opus |

---

## 預期效益

- 使用者不再需要每次手動提示「用 multi-agent」
- patch 任務從規劃到 notes 全流程自動化
- 成本降低: 執行型任務改用 Sonnet 節省 ~80% token 成本
- 主 context Opus 專注高價值推理工作
