# 018 — LangGraph Agent 工作流架构原地重构

> **Status**: implemented, device acceptance pending (2026-09-10)
> **Source**: ADR-0008 scope clarification + Issue #12 CaptureGraph tracer-bullet follow-up
> **Related**: spec 007 conversation decomposition · spec 011 Capture workflow · spec 014 tool-calling workflow · spec 013 Kit seams

## Problem Statement

MindTrace 已通过 Issue #12 和 spec 011 建立 `CaptureGraph` 最小闭环，但该成果只覆盖 Capture 工作流。当前 conversation 仍由 `AgentChatService` 过程式编排，tool-calling 由 `ToolLoop` 自有循环承载，skill intent 仍是占位。若继续只扩充 CaptureGraph，LangGraph 会退化为单类昵称；若各领域各写一套能力和持久化实现，又会形成新旧后端并行、双写或职责冲突。

本次重构需要把 LangGraph 明确为整个 Agent 工作流架构的设计根，同时保留现有功能、职责、模块拓扑和单一生产后端。

## Solution

将 Capture、conversation、tool-calling 和 skill intent 定义为同一架构下的领域 Agent workflow。每个 workflow 拥有自己的类型化 State、Node、Edge、条件路由、入口和结束语义；共享的 OCR、LLM、ToolRegistry、DAO 和 Kit 能力仍各自只有一个生产所有者。

`CaptureGraph` 继续作为首个 canonical workflow。先封闭 `Dispatcher.dispatch` 唯一入口并修复 State channel 丢失，再将 ToolLoop 显式 State/Node/Edge 化。只有两个真实生产 workflow 证明存在稳定且相同的执行机制后，才允许提取共享运行内核。conversation 在 spec 007 行为拆分完成后原子切换为 workflow；skill intent 在七个 action 语义确认后接入。

迁移不使用新旧 runtime 并行、feature flag、shadow execution、双读、双写、结果竞选或生产 fallback。调用点切换与旧业务体删除必须位于同一实施切片。

## User Stories

1. 作为架构维护者，我希望 LangGraph 描述整个 Agent 工作流架构，而不是 CaptureGraph 的别名，以便后续工作流遵循同一模型。
2. 作为 Capture 调用方，我希望只依赖 `Dispatcher.dispatch`，以便不读取内部 Graph 或 State。
3. 作为对话维护者，我希望 conversation 有独立的类型化 State 和流程边，以便不把 UI、记忆和流式控制混在一个大类中。
4. 作为工具维护者，我希望 ToolLoop 明确表达模型调用、工具执行和终止条件，以便循环行为可测试且不会失控。
5. 作为 skill 维护者，我希望系统意图只路由到现有唯一能力入口，以便不复制 Capture、conversation 或写入后端。
6. 作为数据维护者，我希望所有 KnowledgeUnit 写入仍经过 Capture TruthCheck 和唯一 DAO adapter，以便重构不污染数据。
7. 作为用户，我希望拍照、OCR、分类、结构化、生成笔记、聊天、流式回复、记忆和复习行为在重构前后保持一致。
8. 作为维护者，我希望每个业务动作只有一个生产所有者，以便新旧实现不会互相阻塞。
9. 作为测试维护者，我希望 workflow 通过稳定入口测试，以便内部节点重排不破坏行为测试。
10. 作为 HarmonyOS 开发者，我希望架构符合 ArkTS strict 和五模块拓扑，以便不引入无法编译的动态框架抽象。
11. 作为 Kit 集成维护者，我希望 workflow 通过 facade 使用系统能力，以便 Kit 生命周期和业务流程保持分离。
12. 作为回滚维护者，我希望每个切片整体可 revert，以便回退不需要保留两套生产实现。

## Implementation Decisions

### 1. 工作流目录

| Workflow | 稳定入口 | 当前所有者 | 目标 |
|---|---|---|---|
| Capture | `Dispatcher.dispatch` | `agents` | canonical workflow；外部不读取 Graph/State |
| Conversation | `AgentChatService` UI facade | `entry` | 内部收敛为独立 workflow；需要 Capture 时只调用 Dispatcher |
| Tool-calling | `ToolLoop.run` | `common` | 显式模型调用节点、工具执行节点和条件循环 |
| Skill intent | `SkillAbility` platform adapter | `skill` | 类型化 action 路由；只调用 common/agents 稳定能力 |

workflow 数量不等于 backend 数量。共享能力只有一个生产实现，跨 workflow 只传 request/result，不读取对方 State 或 import 对方 Node。

### 2. Capture 封口

- `Dispatcher.dispatch` 是唯一公开业务入口。
- `AiService` 不得调用 `buildGraph`，不得 import `CaptureGraph` 或 `AgentState`。
- `DispatchResult` 以可选字段承载调用方需要的 classification 和 recognized text，保留现有 KnowledgeUnit 结果语义。
- `buildGraph` 收回 Dispatcher 内部；Graph/State 不再从 agents HSP 公共入口导出。
- Capture 初始 State 由 Dispatcher 构造，不把请求初始化职责泄漏给 entry。
- 每个 Capture Node 返回完整 State 时必须保留仍有效的 channel；在引入安全 State 更新机制前，用测试锁定 `knowledgeUnit`、classification、payload 和 truthCheck 的传递。

### 3. Tool-calling workflow

- `ToolLoop` 是 workflow，不是 Tool，也不是单个 Node。
- State 至少包含 messages、step count、max steps、last result 和 tool calls。
- Node 至少包括模型调用和工具执行。
- 条件边根据 tool calls 是否为空和 max steps 决定 END、继续或结构化错误。
- `ToolLoop.run` 保持稳定；旧 `while` 编排在 workflow 切换时删除，不保留 legacy loop。
- ToolRegistry 和 AgentTool 仍是能力面；不为每个 Tool 创建 Node。

### 4. Conversation workflow

- spec 007 的 IntentClassifier、ChatStatusMachine 和行为要求继续有效。
- `AgentChatService` 最终只保留 UI facade、busy 生命周期和 workflow 调用。
- conversation 使用独立 State；不复用 Capture State。
- State 不包含 UIAbilityContext、ArkUI 引用、callback、DAO、LlmClient 或 ToolRegistry 实例。
- 流式 delta 和 progress 通过注入的 event sink 交付。
- 生成笔记只调用 Dispatcher；工具循环只调用 ToolLoop；不得复制两者逻辑。
- conversation 新 workflow 的生产接线与 AgentChatService 旧编排删除在同一切片完成，不设置双轨 flag。

### 5. Skill intent workflow

- `SkillAbility` 只负责 Want/platform adapter。
- 原始 Want 转换为类型化请求后再进入 workflow。
- 已明确 action 可直接执行 ToolRegistry 或构造 entry handoff；不得复制 entry DAO、Capture 或 conversation 编排。
- 七个 action 的输入、权限和落点未确认前，不按名称猜测实现。
- API 26 A2A 能力仍是 roadmap，不进入 API 24 实现。

### 6. 共享运行内核门槛

Capture 与 ToolLoop 两个生产 workflow 已完成显式 State/Node/Edge 化，并证明节点登记、普通边、条件边、错误路由和运行上限机制相同，因此已提取唯一共享 `StateGraph<State, Step>` 内核。Conversation 与 Skill intent 随后复用该内核。

提取时只上移机械执行机制，不上移领域 State、领域错误、依赖对象、持久化、流式事件或 Kit 行为。提取必须同步迁移两个调用方并删除原执行器，禁止保留第二套 runtime。

### 7. 单后端硬约束

- 每个业务职责只有一个生产所有者。
- 临时 wrapper 只能单向转发且无业务逻辑，并在当前切片闭合。
- 禁止新旧 workflow/runtime 同时处理生产请求。
- 禁止双写、双读、shadow run、结果竞选和旧实现 fallback。
- LLM 流式 transport 失败后走同一个 `LlmClient` 的非流式请求属于 transport 恢复，不属于旧后端 fallback。
- 测试 fake/stub 可以存在于测试边界，但不得进入生产组合根。

### 8. Kit 定位

Kit facade 是 workflow 可调用的系统能力 adapter，不是 workflow 或 Node。contract 继续位于 common，真实实现位于 entry 或系统模板模块。每项 Kit 能力只有一个生产数据源，不保留 mock/real 双生产来源。

## Testing Decisions

测试优先经过稳定 workflow 入口，断言外部行为而非私有 Map 或节点字段。

1. Capture 通过 `Dispatcher.dispatch` 测试成功、analysis、persist false、持久化、错误短路和 channel 保留。
2. Tool-calling 通过 `ToolLoop.run` 测试无工具、单轮工具、工具错误恢复和 max steps，保留现有 wire 形状断言。
3. Conversation 通过 UI facade 或 workflow 入口测试文本、图片、笔记生成、非流式、SSE、记忆软失败和 fatal error。
4. Skill 通过类型化 request 测试 action 路由、未知 action 和 capability failure；单独测试 Want normalization。
5. Source guard 检查 entry 不 import CaptureGraph/AgentState、skill 不 import entry、同一职责没有 legacy/new 双实现。
6. 修改 `.ets` 后运行 `arkts_check`；阶段结束运行 ArkTS lint、Node tests、naming-lint、diff check 和完整 build。
7. Hypium 和真机验证负责 Capture、conversation、Kit 和 Intent 的运行行为，Node AST 测试不能替代设备验收。

## Migration Slices

1. 修复 Capture State channel 断链并增加回归测试。
2. 收回 Capture 内部边界：AiService 统一走 Dispatcher，Graph/State 不再公开给 entry。
3. 将 ToolLoop 原地改造成显式 tool-calling workflow，删除旧过程式循环。
4. 对 Capture 与 ToolLoop 做机制对比；满足门槛才提取共享 runtime，否则保持领域实现。
5. 完成 conversation characterization 和 spec 007 未完成职责拆分。
6. 原子切换 conversation workflow 并删除 AgentChatService 旧编排。
7. 统一写入验证后接入写类 Tool；Tool 不另建 DAO 写入实现。
8. action 语义确认后实现 skill intent workflow。
9. 接入必要 Kit adapter，完成全链路审查和设备验收。

## Acceptance Criteria

- [x] LangGraph 在文档和代码中表示整体 Agent workflow 架构，CaptureGraph 明确为具体 workflow。
- [x] `AiService` 只通过 `Dispatcher.dispatch` 使用 Capture workflow。
- [x] Capture 的 source、KnowledgeUnit、classification、payload 和 TruthCheck channel 不在节点间丢失。
- [x] ToolLoop 具有显式 State、Node 和条件路由，外部 `run` 行为不变。
- [x] conversation 具有独立 State 和 workflow，AgentChatService 不再承载重复编排。
- [x] skill intent 的 SearchNote 只路由到唯一 `note_query` 能力；其余 action 明确拒绝，不 import entry 或复制后端。
- [x] 同一生产职责不存在 legacy/new 双实现、双写、双读或 feature flag 双轨。
- [ ] 所有稳定用户行为通过静态、Hypium 和真机验收。
- [x] ArkTS strict、项目 lint、Node tests、naming-lint、diff check 和完整 build 通过。

## Out of Scope

- Python LangGraph、langgraphjs、LangChain runtime 或远程 Agent sidecar。
- Checkpoint、Interrupt、HITL、Subgraph、Reducer、并行 fan-out 和任意自修复循环。
- API 26 A2A、AgentExtensionAbility 或动态 Skill engine。
- 为统一命名而建立一个超级 Agent State 或超级 Graph。
- 未经确认的 skill action 产品语义。
- 与工作流架构无关的 UI 视觉拆分。

## Further Notes

Issue #12 证明了 Capture workflow 最小闭环可行，但不代表整体 Agent workflow 架构迁移完成。后续进度以本 spec 和 `docs/specs/index.md` 为准；早期 Python sidecar 调研只作为历史背景。

实现同时修复了三处原链路损害：TruthCheckNode 丢失 KnowledgeUnit、TruthCheck 通过语义反向且失败仍可持久化、PersistNode 重建 KnowledgeUnit 并覆盖分类/难度。设备侧 Hypium、真实 OCR/LLM、Form 卡片和小艺入口仍需人工验收。
