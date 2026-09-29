# LangGraph 术语收敛表 — 2026-09-09

## 用途

本表只规范 MindTrace 对 LangGraph Agent 工作流架构概念的局部称呼，不改变运行时、不改变持久化字段、不改变用户可见文案，也不宣称项目嵌入了官方 LangGraph runtime。`CaptureGraph` 是 Capture 工作流实现，不是整体架构的别名。

## 术语映射

| LangGraph 概念 | MindTrace 当前名称 | 处理 |
|---|---|---|
| Agent workflow | Capture / conversation / tool-calling / skill intent workflow | 统一使用 LangGraph 设计原则，但按领域拆分，不合并为超级图 |
| StateGraph | `CaptureGraph` 等具体工作流承载 | `CaptureGraph` 只代表 Capture workflow；后续工作流按职责命名 |
| graph state | `AgentState` 等领域 State | `AgentState` 当前是 Capture State；其他工作流不得无边界复用它 |
| node | `CaptureNode` / `OcrNode` 等 | 保留；节点只负责一个流程步骤 |
| edge | `addEdge` | 保留；普通边表示固定转移 |
| conditional route | `GraphRoute` | 作为内部路由函数别名；不扩大为动态图 DSL |
| START / END | `CaptureStep` 的 sentinel 值 | 保留大写拼写 |
| Command / goto | 当前未公开实现 | 仅作为未来内部路由形状参考，本轮未引入 |
| Tool | `AgentTool` / `ToolRegistry` | 与 Node 分离；Tool 是能力，Node 是流程 |
| Dispatcher | `Dispatcher` | 保留；它是业务编排入口，不改名为 Controller 或 Manager |
| sub-agent | `TypeClassifier` / `KnowledgeModel` | 保留当前代码名；`KnowledgeModel` 名称已由项目裁决保留 |
| checkpoint / interrupt / subgraph | 当前未实现 | 明确为非目标，不添加无需求脚手架 |

## 本次允许的局部昵称转换

- 内部条件路由函数类型：`ConditionalRouter` → `GraphRoute`。
- 图相关注释中使用 `graph state`、`node`、`edge`、`conditional route`，避免泛化为 pipeline/context/handler。
- 文档标题和架构说明优先使用 `CaptureGraph`、`AgentState`、`CaptureNode` 等实际代码名。

## 明确禁止的转换

- 不把 `CaptureGraph` 改名为 `StateGraph`，避免造成官方 runtime 兼容性误解。
- 不把 `CaptureGraph` 当作整个 Agent 工作流架构，也不把对话、工具和 skill 逻辑全部塞进它。
- 不为每个工作流复制 LLM、DAO、ToolRegistry 或 Kit 实现；工作流之间通过唯一能力所有者协作。
- 不把 `AgentState` 改名为 `GraphState`，除非另立公共接口迁移决策。
- 不把 `KnowledgeModel` 改名为 `StructureAgent` 或 `StructureService`；后者是协作服务概念，不是当前编排 agent 的替代名称。
- 不修改 `KnowledgeUnit`、`captureText`、`classification`、`truthCheck`、`persist` 等协议或持久化字段。
- 不将用户界面中的 assistant/AI helper 文案改成 agent。

## Phase 2 退出条件

- 术语映射可被后续阶段引用。
- 只发生局部内部别名和注释变化。
- `Dispatcher.dispatch`、图状态字段、节点顺序和外部调用方不变。
- Node 回归测试、ArkTS lint、命名检查和差异检查全部通过。

## 实施结果

- `StateGraph<State, Step>` 是唯一 ArkTS 工作流执行内核。
- Capture、ToolCalling、Conversation、SkillIntent 分别拥有独立 State 与边，不共享超级 State。
- `CaptureGraph` 保留为 Capture 领域装配器；`Dispatcher.dispatch` 是唯一业务入口。
- Tool、LLM、DAO 和 Kit 均保留单一生产所有者；不存在 legacy/new 运行时双轨。
