# LangGraph 架构演进基线 — 2026-09-09

## 目的

本报告记录 MindTrace 在继续演进 ArkTS 原生 Agent 工作流架构前的行为与结构基线。它不是新的架构决策，不推翻 ADR-0008，也不把历史 Python LangGraph sidecar 方案作为当前目标。`CaptureGraph` 是第一个具体工作流，不是整个 Agent 工作流架构。

## 当前架构不变量

```text
entry → agents → common
entry → common
skill → agents, common
cardservice → common
```

- 生产系统只有一套后端实现；每个业务动作只有一个生产职责所有者和一条生产调用路径。
- 迁移不得采用新旧后端双轨、双写、双读、结果竞选或生产 fallback。测试 fake/stub 不属于生产后端。
- `Dispatcher.dispatch` 是 Capture 主链路的唯一公共入口。
- `CaptureGraph` 使用 `AgentState` 在 `capture → classify → structure → truth_check → persist` 间传递状态。
- `persist: false` 必须跳过持久化。
- OCR、分类、结构化、真值检查或持久化失败时，图应短路并返回结构化错误。
- 失败路径不得生成可持久化的伪 `KnowledgeUnit`。
- `LlmClient.call(request)` 是 LLM 公共入口。
- `Tool` 是可选能力，`Node` 是流程步骤，两者不混用。
- `agents` 不得依赖 `entry`；持久化通过 `NoteDaoInterface` 和 entry 侧 adapter 注入。
- Kit 业务能力通过 `common/kit/` contract 和 entry 侧实现注入。
- `KnowledgeModel` 名称保留，作为结构化编排 sub-agent 使用。

## Agent 工作流目录

| 工作流 | 当前入口/承载 | 职责所有者 | 与其他工作流的关系 |
|---|---|---|---|
| Capture | `Dispatcher` → `CaptureGraph` | `Dispatcher` / Capture nodes | 对话生成笔记必须委托此入口 |
| Conversation | `AgentChatService` | 对话编排、流式回复、记忆协调 | 可调用 Dispatcher 和 ToolLoop，不复制其实现 |
| Tool-calling | `ToolLoop` → `ToolRegistry` | 工具循环和唯一工具面 | 被对话或 skill 使用，不直接拥有业务持久化 |
| Skill intent | `SkillAbility`，`IntentRouter` 待实现 | 系统意图路由 | 只路由到 common/agents 的唯一能力入口 |

多个工作流是一个 Agent 工作流架构中的领域分解，不是多个后端。目标架构要求每个需要图编排的工作流拥有独立的类型化 State 和流程职责，相同业务能力仍只有一个生产实现。当前只有 Capture workflow 完成了显式 State/Node/Edge 化；conversation、tool-calling 和 skill intent 仍处于不同成熟度，不能把目录清单误读为迁移已经完成。

## 已确认调用链

### Capture 主链路

```text
AiService.capture / AiService.captureText
  → Dispatcher.dispatch
  → CaptureGraph.run
  → OcrNode
  → ClassifyNode
  → StructureNode
  → TruthCheckNode
  → PersistNode（仅 persist=true）
  → DispatchResult / CaptureGraphError
```

### 对话链路

```text
AgentFloatWindow
  → AgentChatService.realReply / realReplyStream / captureReply
  → IntentClassifier / ChatStatusMachine
  → AgentMemoryService
  → LlmClient.call
  → ContentProtocol
  → 可选 generateNoteFromConversation
  → AiService.captureText
  → Dispatcher.dispatch
```

### 当前 AI 写入路径

1. 对话显式生成笔记：经 `AiService.captureText`、`CaptureGraph`、`TruthCheckNode` 和 `NoteDaoAdapter`。
2. 对话记忆、摘要和画像：经 `AgentMemoryService`、`LlmGuard`、`AgentMemoryDao` 或 `ChatMessageDao`。
3. 学习计划生成：`StudyPlanViewModel.generatePlan` 经 `StudyPlanService` 生成内容后写入 `StudyPlanDao`。

这三条路径的校验边界和数据语义不同，不能在 CaptureGraph 协议演进阶段隐式合并。

## 静态回归基线

### 2026-09-09 执行结果

| 检查 | 命令 | 结果 |
|---|---|---|
| Node 回归测试 | `node --test "scripts/arkts-lint/tests/*.test.mjs"` | 基线 284 passed；重构后 309 passed, 0 failed |
| 项目 ArkTS lint | `node scripts/arkts-lint/index.mjs --quiet` | passed |
| 命名检查 | `node scripts/naming-lint/index.mjs` | 0 violations |
| 差异检查 | `git diff --check` | passed |
| 工作树 | `git status --short --branch` | clean, `feature/real-llm-agent-chain` |

## 已覆盖的行为

- CaptureGraph 正常边、条件边、错误短路和 `persist` 条件。
- OcrNode payload 到 capture text 的传递。
- ClassifyNode 将分类结果传给 StructureNode。
- StructureNode 结构化失败的错误返回。
- PersistNode 的 DAO 注入和 `persist` 语义。
- Dispatcher 单入口和图构建注入。
- LlmClient 单 `call(request)`、JSON/SSE 适配和 provider/model 选择。
- ToolRegistry、ToolLoop、只读工具、工具错误和 maxSteps 限制。
- AgentChatService 的 IntentClassifier、ChatStatusMachine 接线。
- AgentChatService 的流式 delta、图片分析和生成笔记静态接线。
- API key 的 AssetStoreKit 存储、迁移和清理。
- ReminderFacadeImpl 的 contract 覆盖、组合根注入和权限声明。

## 本阶段未声称已完成的验证

- 未以 Node 测试替代 Hypium 行为测试。
- 未声称真实设备上的 OCR、LLM、入库、重启恢复、后台任务或卡片刷新已经通过。
- 未声称七个 skill intent action 的实际平台语义已经确认。
- 未声称三条 AI 写入路径已经统一。
- 未声称 `CaptureGraph` 已具备 checkpoint、interrupt、subgraph 或并行 fan-out；这些仍是明确的非目标。

## Phase 1 退出结论

当前静态基线可信。重构后 Capture、ToolCalling、Conversation、SkillIntent 四个领域 workflow 已复用唯一 ArkTS `StateGraph` 内核；现有测试主要是 Node AST、源结构和协议守门，真正设备行为仍需由 Hypium、DevEco GUI 或真机补齐。

本轮已完成局部术语收敛、整体 Agent workflow 架构、单后端职责封口和原链路修复。后续扩展必须继续通过现有 workflow 稳定入口，不复制 Capture、Conversation、Tool 或 Skill 实现。
