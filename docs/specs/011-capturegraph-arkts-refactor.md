# D2 — CaptureGraph ArkTS 重构实施 Spec

> **Status**: implemented (2026-09-05 · D2 全链落地, 旧 API 已删; 进度以 [`index.md`](./index.md) 为准)  
> **Date**: 2026-09-05  
> **Source**: GitHub issue #9 (`[Wayfinder] D2 后端：LangGraph 风格节点与图编排`)  
> **Scope**: 仅架构规范化与主流程直接相关的现有能力重构；不增加用户可见功能

## Problem Statement

当前 MindTrace 主流程由 `Dispatcher` 直接串行调用 OCR、分类和知识结构化逻辑。虽然代码可以运行，但节点职责、状态传递、错误传播和持久化边界隐含在 `Dispatcher` 与 `KnowledgeModel` 中：同一个 `KnowledgeModel` 同时承担 prompt 构造、LLLM 调用、JSON 校验、KnowledgeUnit 组装和真值检查，导致后续维护难以定位问题、测试边界不稳定，也难以在不破坏现有业务语义的前提下替换能力。

当前还存在以下问题：

- 节点间通过局部变量和多个参数传递中间结果，没有统一的图状态。
- `Dispatcher` 拥有多个公共入口，调用方需要知道内部编排细节。
- 错误被降维为普通字符串，丢失错误类型、执行步骤和是否可重试信息。
- AI 失败时可能生成 fallback `KnowledgeUnit`，污染 RDB 与复习调度。
- `persist: false` 的语义没有显式落入可测试的持久化边界。
- Python 目前服务自研 OCR；本阶段不应再引入 Python LangGraph 服务。

## Solution

采用 ArkTS 内置轻量 `CaptureGraph`，用类型化的 `AgentState`、节点、普通边和条件边表达 MindTrace 的 Capture 主流程。`Dispatcher` 负责构造并运行图，对外保留稳定的业务入口。

图的主路径为：

`Capture → Classify → Structure → TruthCheck → Persist`

其中：

- OCR 继续使用现有自研实现。
- 分类、结构和真值检查拆为清晰的服务/节点边界。
- 只有结构化成功的 `KnowledgeUnit` 才能进入持久化节点。
- `persist: false` 明确跳过 `PersistNode`。
- 图运行失败返回结构化错误，不伪造成功结果。
- `KnowledgeModel` 暂作兼容 façade，完成调用迁移后再决定是否删除。

## User Stories

1. 作为 MindTrace 维护者，我希望 Capture 主流程具有明确的节点边界，以便定位 OCR、分类、结构化和持久化问题。
2. 作为主流程维护者，我希望节点之间通过统一 `AgentState` 传递结果，以便减少隐式参数和局部变量。
3. 作为调用方开发者，我希望 `Dispatcher` 最终只有一个稳定入口，以便不依赖内部步骤。
4. 作为现有服务调用方，我希望迁移期间旧入口仍可工作，以便分阶段降低重构风险。
5. 作为维护者，我希望 `analyze` 和 `routeDispatch` 最终删除，以便不保留两套重复实现。
6. 作为业务维护者，我希望保留 `DispatchRequest`、`DispatchResult`、`KnowledgeUnit` 和 `ContentProtocol` 的稳定语义，以便现有用户行为不变。
7. 作为分类服务维护者，我希望 `ClassifyNode` 只负责分类，以便输入输出和失败条件可独立测试。
8. 作为知识结构化维护者，我希望 `StructureNode` 负责生成和验证 `KnowledgeUnit`，以便不与真值检查或持久化混合。
9. 作为数学内容维护者，我希望 `TruthCheckNode` 独立执行真值检查，以便检查规则可以单独演进。
10. 作为数据维护者，我希望 `PersistNode` 显式消费 `persist` 选项，以便只分析场景不会写数据库。
11. 作为数据维护者，我希望失败时不生成 fallback `KnowledgeUnit`，以便 RDB 和复习调度不包含占位内容。
12. 作为运维维护者，我希望错误包含步骤和可重试信息，以便上层能够决定重试、跳过或展示错误。
13. 作为测试维护者，我希望在最高可用边界测试图行为，以便不依赖具体实现细节。
14. 作为项目维护者，我希望本次不引入 Python 图服务，以便 OCR 服务与主图编排职责保持分离。
15. 作为 HarmonyOS 开发者，我希望图运行时保持 ArkTS 友好，以便符合 DevEco Studio 开发和模块拓扑约束。
16. 作为后续 Kit 替换维护者，我希望节点接口能够隔离能力提供者，以便 D4 只替换具体适配点而不重写全链路。
17. 作为回滚维护者，我希望每个节点迁移步骤可以独立验证，以便出现问题时能安全回退。
18. 作为代码审查者，我希望明确记录本阶段不实施 Checkpoint、HITL 和 Subgraph，以便避免范围膨胀。

## Implementation Decisions

### 1. 图运行时

新增项目内轻量图运行时抽象，命名为 `CaptureGraph`：

- `AgentState` 是图运行期间的类型化状态。
- `Node` 接收 `AgentState`，返回需要合并的更新或完整状态。
- `Edge` 分为普通边和条件边。
- 图运行时提供入口、出口、节点注册、边注册和单次 `run`。
- 不引入 Python LangGraph、外部 LangGraph 库、Checkpoint 服务或新的跨语言 HTTP 图服务。

图运行时是内部实现细节，外部业务 API 不暴露通用图框架接口。

### 2. Capture 主流程

`CaptureGraph` 包含以下节点：

- `OcrNode`：调用现有自研 OCR，产出 Capture 文本。
- `ClassifyNode`：调用 `TypeClassifier`，产出分类结果。
- `StructureNode`：调用结构化服务，产出或拒绝 `KnowledgeUnit`。
- `TruthCheckNode`：执行数学 / LaTeX 真值检查。
- `PersistNode`：在允许持久化时写入 RDB。

主流程为：

`OcrNode → ClassifyNode → StructureNode → TruthCheckNode → PersistNode`

如果 `persist: false`，`TruthCheckNode` 之后的 `PersistNode` 不执行。

### 3. AgentState

`AgentState` 至少包含：

- Capture 结果及原始文本。
- 分类结果。
- 结构化 `KnowledgeUnit`。
- TruthCheck 结果。
- 当前执行步骤。
- 持久化选项。
- 结构化错误。
- 可选的运行追踪信息。

节点不得依赖未写入 `AgentState` 的隐式局部变量。节点更新采用显式字段归并；不引入 reducer、自动合并或并行写回机制。

### 4. 节点输入输出协议

每个节点：

- 只接收 `AgentState` 和其必要依赖。
- 只更新与自身职责相关的状态字段。
- 通过成功结果或结构化错误结束。
- 不直接创建另一节点的依赖对象。
- 不绕过 `CaptureGraph` 直接触发持久化。

节点之间传递业务数据，不传递 ArkUI 引用或页面状态。

### 5. 条件边与错误路由

第一阶段只实现明确的条件路由：

- OCR 失败或 Capture 文本为空 → 错误终点。
- 分类失败 → 错误终点。
- 结构化失败或 JSON 校验失败 → 错误终点。
- `persist: false` → 跳过 `PersistNode` 并正常结束。
- 持久化失败 → 错误终点。
- 真值检查失败 → 保留结构化 TruthCheck 结果；不得自动进入数据库，除非持久化策略明确允许。
- 超时或不可恢复错误 → 错误终点。

条件边只基于 `AgentState` 的类型化字段和错误字段决定下一步，不允许任意图循环或隐式 AI 自我修复。

### 6. 结构化错误

定义图/Dispatch 层错误结构，至少包含：

- `kind`：错误类别。
- `message`：可安全展示的错误信息。
- `step`：发生错误的节点或步骤。
- `retriable`：是否允许重试。
- `cause`：可选的底层错误信息。

错误可以复用现有 LLM 错误类别，但图运行时不能将所有异常都压扁成普通字符串。

### 7. Dispatcher 兼容迁移

- `dispatch(req, opts?)` 是唯一最终公共入口。
- 迁移期间 `analyze` 和 `routeDispatch` 作为 deprecated wrapper 保留。
- wrapper 只转发到 `dispatch`，不得包含另一套业务实现。
- 内部调用方逐步统一到 `dispatch`。
- 所有调用方迁移完成后删除 wrapper。
- `persist: false` 由 `PersistNode` 显式消费。
- `includeRawText` 等现有 `DispatchOptions` 语义在迁移期间保持不变。

### 8. KnowledgeModel 拆分

按照 ADR-0006 / spec 003 的边界拆分为：

- `PromptBuilder`：构造结构化 prompt。
- `TruthCheckService`：执行数学 / LaTeX 真值检查。
- `StructureService`：编排 LLM 调用、JSON 校验、归一化和 KnowledgeUnit 构造。

拆分时保持领域模型和协议语义不变。原有 `KnowledgeModel` 暂时作为兼容 façade；待所有调用方迁移并完成测试后，再决定是否删除。

### 9. 失败内容保护

以下失败不产生可持久化的 `KnowledgeUnit`：

- LLM 调用失败。
- LLM 输出无法解析为合法 JSON。
- 结构化字段不满足协议。
- 必要的数学 / LaTeX 校验未通过。
- 图状态不完整。

不得以 fallback 占位 `KnowledgeUnit` 掩盖失败并写入 RDB。

### 10. Kit 与能力隔离

节点可以依赖项目内部的 LLM、OCR 或其他能力 facade，但本阶段不批量替换 Kit。D4 决定 Kit 替换边界时，优先替换节点依赖，不改变 `CaptureGraph` 的节点契约和主流程。

## Testing Decisions

### 测试原则

- 优先测试外部可观察行为，不依赖具体类内部字段。
- 最高可用测试 seam 优先为 `Dispatcher.dispatch()` 和图运行结果；仅在外部 seam 无法覆盖时测试节点。
- 每个节点至少覆盖成功路径和失败路径。
- 使用 mock/stub 隔离 OCR、LLLM、TruthCheck 和 RDB 依赖。
- 明确断言失败不会产生可持久化 `KnowledgeUnit`。
- 现有测试风格和 Hypium / arkts-lint 测试约定优先。

### 必测模块

1. `CaptureGraph`
   - 正常主路径按 Capture → Classify → Structure → TruthCheck → Persist 执行。
   - 条件边能根据错误和 `persist` 状态正确路由。
   - `persist: false` 不调用 RDB 持久化。
   - 任一节点失败都会短路到错误终点。
2. `AgentState`
   - 节点更新只影响声明字段。
   - 错误、步骤和结果字段可以完整传递。
3. `OcrNode`
   - 成功输出 Capture 文本。
   - 空文本和 OCR 异常进入结构化错误。
4. `ClassifyNode`
   - 成功输出合法分类。
   - 分类异常不进入 StructureNode。
5. `StructureNode`
   - 合法输出生成稳定 KnowledgeUnit。
   - 非法 JSON 或协议错误不生成可持久化对象。
6. `TruthCheckNode`
   - 成功、失败和异常均产生可追踪结果。
7. `PersistNode`
   - 默认行为执行持久化。
   - `persist: false` 跳过持久化。
   - RDB 失败返回结构化错误。
8. `Dispatcher`
   - 旧 wrapper 能转发到 `dispatch`。
   - 内部调用不再依赖旧入口。
   - 最终入口保留稳定的 `DispatchResult` 语义。
9. 兼容核心类
   - `LlmClient` 既有成功、流式和错误行为保持不变。
   - `LlmGuard` 既有错误保护行为保持不变。
   - `KnowledgeModel` 兼容 façade 在迁移期间不产生回归。

### 测试验收命令

在完成实施并允许运行项目既有测试时执行：

- `node scripts/arkts-lint/index.mjs --quiet`
- `node --test scripts/arkts-lint/tests/*.test.mjs`
- 项目已有的 Hypium / ArkTS 测试命令

注意：AGENTS.md 规定 AI 不执行 DevEco build；本 spec 的验收不把 build 作为成功条件。

## Acceptance Criteria

- [ ] D2 正式 spec 已保存到 `docs/specs/`，并在 spec 索引中登记。
- [ ] `CaptureGraph` 有明确的主流程、节点契约、状态契约和错误终点。
- [ ] `AgentState` 通过统一字段承载中间结果，节点间不再依赖未声明的隐式状态。
- [ ] `persist: false` 会明确跳过 `PersistNode`，且不会调用 RDB 持久化。
- [ ] AI、JSON 解析、结构化或状态失败时不会生成 fallback `KnowledgeUnit`。
- [ ] 图错误包含 `kind`、`message`、`step`、`retriable` 和可选 `cause`。
- [ ] `Dispatcher.dispatch(req, opts?)` 作为唯一最终入口；`analyze`、`routeDispatch` 迁移后删除。
- [ ] 迁移期间 deprecated wrapper 只能转发到 `dispatch`，不存在两套并行实现。
- [ ] `PromptBuilder`、`TruthCheckService`、`StructureService` 的职责与 ADR-0006 / spec 003 一致。
- [ ] 业务语义和 `DispatchRequest`、`DispatchResult`、`KnowledgeUnit`、`ContentProtocol` 保持兼容。
- [ ] 不引入 Python LangGraph、外部图框架、Checkpoint、Subgraph、HITL 或 AI 自我修复循环。
- [ ] `node scripts/arkts-lint/index.mjs --quiet` 无错误。
- [ ] `node --test scripts/arkts-lint/tests/*.test.mjs` 全部通过。
- [ ] 相关 Hypium / ArkTS 行为测试按项目既有方式通过；若当前环境无法执行，需在交付说明中明确记录。
- [ ] 不执行 build，不执行 push，不在未授权时 commit。

## Out of Scope

- Python LangGraph 服务或 Python 图运行时。
- OCR 识别技术路线替换；OCR 必须保持自研。
- 端侧 Kit 替换的具体实施；由 D4 单独决策。
- Checkpoint、持久化恢复、Thread 数据库。
- 分布式节点、节点并行执行和 Subgraph。
- HITL interrupt / resume。
- AI 自我修复循环、公式自动重试和任意条件循环。
- 新增复习、提醒、卡片或其他产品能力。
- `AgentChatService` 的大范围产品行为重构；仅在 D2 依赖的调用边界内做必要迁移。
- 在本 spec 中删除 `KnowledgeModel`；先保留兼容 façade，完成后续决策。
- 未经明确授权的 build、commit、push。

## Further Notes

- 本 spec 是 D2 的正式实施依据；实施时应优先遵循仓库现有 ADR/spec 的原子迁移顺序。
- `CaptureGraph` 是“LangGraph 风格”而不是官方 LangGraph 兼容实现；文档和代码中应避免误导性兼容声明。
- Python 只继续承担现有自研 OCR 服务，不得承担本图编排运行时。
- 如果实施中发现现有类型与 `CONTEXT.md` 或 ADR 冲突，应停止扩大范围并记录为决策项，而不是在重构中隐式改变领域语义。
