# 035 v1 收尾：批量整理回执与 AI 合规标识

Status: proposed（2026-10-25，待实现）
Refs: #231（回执）、#232（合规导出）、[`phase-tracker.md`](../agents/phase-tracker.md) P4 结果回执 / P5 合规落地、031（批量入口）、034（文搜图）

## 1. 缺口事实（as-built）

| 缺口 | 现状 | 证据 |
|---|---|---|
| P4 回执 | 批量整理结束只有一次 Toast（`AgentFloatWindow.onBatchAction`），条数只存在于那个页面实例里 | `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets` L954–986：`showToast('批量完成：成功 N 条…')` |
| 小艺侧 | A2A 回复整段交给 `ReplyService.complete()`，模型不知道本次整理了几条，只能自由发挥 | `entry/src/main/ets/agentextability/AgentExtAbility.ets` L230–240 |
| P5 导出 | **全仓没有导出实现**，`导出` 只出现在注释（`EntryBackupAbility.ets` L14「后续可在此处把 RDB 数据导出」） | `grep -rn 导出 entry/src common/src agents/src` 无功能代码 |

P5 的验收标准写的是「导出的文件带 `AI生成 / MindTrace / mindtrace-note-agent`」，但导出这个承载物本身不存在，所以 P5 不是「补一行元数据」，而是「先有最小导出，再有元数据」。

## 2. P4 回执设计

### 2.1 状态存哪里

写一个 JSON 文件，不写 preferences：

- 路径：`<filesDir>/receipts/last-capture.json`，两个进程（`main` 与 `:agent`）看到的是同一个应用沙箱目录。
- 理由：`:agent` 进程里 `preferences.getPreferences` 出现过不返回（032 §3 的等待 4s 兜底就是为它加的），同步文件读没有这个风险；数据只有几十字节，也不需要事务。
- 写入点：`onBatchAction` 循环结束后**无论成功失败都写**（`done/failed/total`），写失败只打日志、不影响用户流程。
- 调试入口 `DebugCaptureRunner` 同样写一份，保证 e2e 能覆盖回执。

字段：

```json
{
  "done": 3,
  "failed": 0,
  "total": 3,
  "at": 1761363131000,
  "source": "batch"
}
```

### 2.2 小艺怎么用它

在 `AgentExtAbility.handleQuery` 里，**先判回执意图，命中就不调模型**：

| 步骤 | 行为 |
|---|---|
| `ReceiptIntent.matches(query)` 为真 | 读 `last-capture.json` → `formatReceipt()` → `sendAnswer()`，不走 `LlmConfig` / `ReplyService` |
| 文件不存在 | 回「还没有整理记录，先在 MindTrace 里用「+ → 批量」选图。」 |
| 文件存在但超过 24h | 回「最近一次整理是 N 小时前：X 条」——仍然给数字，不装作刚发生 |

关键词（本地判定，不花 token）：`整理了几条`、`整理多少`、`本次整理`、`刚才整理`、`几条笔记`、`整理结果`、`回执`。

文案模板：`本次整理 {done} 条：成功 {done} 条，失败 {failed} 条（{HH:mm}）。`

### 2.3 明确不做

- 不把条数塞进 LLM 的 system prompt 让它「自然地说」——数字必须来自落盘事实，不能让模型编。
- 不做多轮上下文回执（「那第 3 条呢」），v1 只回答本次批量结果。

## 3. P5 合规设计

### 3.1 应用内 AI 标识

- 笔记详情页（`NoteDetail`）标题下方加一枚「AI 生成」标签，数据源是 `KnowledgeUnit` 的来源字段（`provenance` 已有 chain 信息）。
- 卡片（`cardservice`）本轮**不改布局**：现有两行指标已占满，加标识需要重新排版，等用户对「掌握 0% / 连续复习 0 天」两行拍板时一起做。

### 3.2 最小导出

| 项 | 决定 |
|---|---|
| 触发 | 详情页「⋯ → 导出 Markdown」 |
| 落地方式 | `DocumentViewPicker.save()` 让用户选目录，拿到 URI 后 `fileIo` 写入（避免自造路径 + 权限） |
| 内容 | 标题、结构化要点、原始 OCR 摘录；**不含原图**（体积与隐私） |
| 文件名 | `mindtrace-{noteId}-{yyyyMMdd}.md` |

front-matter（固定四个字段，缺一不可）：

```markdown
---
ai_generated: true
app: MindTrace
agent: mindtrace-note-agent
exported_at: 2026-10-25T14:32:11+08:00
model: <vendorId>/<modelId>
---
```

`model` 取当前 `LlmConfig`；未配置时写 `unknown`，不允许留空。

### 3.3 为什么不做「全量导出 / 打包」

合规要求只针对「AI 生成内容对用户的可见标识」，单条 Markdown 已经能证明链路；批量打包涉及压缩、进度、失败重试，属于 v2 范围。

## 4. 验收

| 编号 | 场景 | 判定 |
|---|---|---|
| R1 | 应用内批量整理 2 张 → 小艺问「本次整理了几条」 | 回复含 `成功 2`，且与 hilog 的 `[BatchCapture] done=2` 一致 |
| R2 | 冷启后未整理就问 | 回「还没有整理记录」，不编数字 |
| R3 | 详情页导出 Markdown | 文件存在、可读，front-matter 四字段齐全，`ai_generated: true` |
| R4 | 未配置模型时导出 | `model: unknown`，其余字段正常 |
| R5 | 详情页可见「AI 生成」 | 截图 |
| R6 | 静态质量 | `node scripts/agent-gate/index.mjs --all` = PASS；新增单测覆盖 `formatReceipt` 与 front-matter 拼装 |

真机命令：

```bash
node scripts/e2e-capture/run.mjs          # 批量整理 → 落库 → 卡片
python scripts/a2a-smoke/a2a_smoke.py --text "本次整理了几条"   # 回执
```

## 5. 风险与待定

| 项 | 说明 | 处理 |
|---|---|---|
| `DocumentViewPicker` 非交互失败 | 某些设备/权限下 `save()` 直接抛错 | 先做一次性探针确认可写入，再落实现；失败时回 Toast，不静默 |
| 导出文件的模型字段 | `LlmConfig` 只读不写，扩展进程与主进程值可能不同 | 导出在主进程做，取主进程 `LlmConfig` |
| 卡片加标识 | 会挤掉现有两行指标 | 本轮不动，等两行指标的拍板结果一起做 |
| 回执被追问 | 「上一次是哪几张」需要图名，v1 不存 | 回复「只记了条数」，不猜 |
