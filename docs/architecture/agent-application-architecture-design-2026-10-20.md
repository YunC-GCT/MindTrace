# MindTrace Agent / 应用架构设计 — 2026-10-20

> **Status**: proposed (2026-10-20)
> **Related**: [ADR-0008](../adr/0008-capturegraph-self-built-runtime.md) · [spec 018](../specs/018-agent-workflow-architecture.md) · [ADR-0010](../adr/0010-mcp-tools-semantics.md) · [ADR-0012](../adr/0012-tool-calling-protocol.md) · [spec 014](../specs/014-tool-calling-protocol.md)
> **Code**: `agents/src/main/ets/core/Dispatcher.ets` · `common/src/main/ets/workflow/StateGraph.ets` · `common/src/main/ets/tools/ToolLoop.ets` · `entry/src/main/ets/database/NoteDao.ets` · `entry/src/main/ets/database/StudyPlanDao.ets`
> **Verified by**: 设计评审（2026-10-20）；图示由 archify finalize 生成（本地生成物，未入 git）

## 0. Codex 执行协议（先读这一段）

### 0.1 任务边界

- **只改设计文档，不改代码**；`AGENTS.md`、ADR、spec、`.ets` 只读。
- 目标：在本文已有设计上**修订**，不是从零重写；先核对代码事实，再改设计。
- 第一轮**只确认文件**，不写文件；确认后再改。
- 文中所有“目标”组件（Dispatcher 主图、AgentRuntime、Note/Review/Video 子图、MCP Host、RAG Layer、App Store）都不是已实现能力，不要假设它们存在。

### 0.2 第一轮：只输出文件影响清单（必须停）

第一轮回复只包含三块：

1. **文件影响清单**：表格，列为 `文件 / 存在 / 操作（读·改·禁止）/ 原因`；
2. **准备修改的章节**：章节号 + 一句话；
3. **待确认问题**：最多 3 个，必须能改变文件范围或设计结论。

第一轮禁止调用 edit / write / patch，禁止改 `.ets` / ADR / spec。回复最后一行必须是：

```text
WAITING_FOR_FILE_CONFIRMATION
```

用户回复“确认”后，才进入第二轮。

### 0.3 文件影响清单（默认基线）

| 文件 | 存在 | 操作 | 原因 |
|---|---|---|---|
| `docs/architecture/agent-application-architecture-design-2026-10-20.md` | ✅ | **改** | 本设计正文 |
| `docs/architecture/index.md` | ✅ | 按需改 | 标题 / 状态 / 索引行变化时才改 |
| `AGENTS.md` · `docs/specs/018-agent-workflow-architecture.md` · `docs/adr/0008-capturegraph-self-built-runtime.md` · `docs/adr/0010-mcp-tools-semantics.md` · `docs/adr/0012-tool-calling-protocol.md` · `docs/specs/014-tool-calling-protocol.md` | ✅ | 只读 | 约束与事实来源 |
| `build-profile.json5` · `entry|common|agents|skill|cardservice/src/main/module.json5` | ✅ | 只读 | 5 module / type / 依赖 |
| `agents/src/main/ets/core/Dispatcher.ets` · `common/src/main/ets/workflow/StateGraph.ets` · `common/src/main/ets/tools/ToolLoop.ets` · `entry/src/main/ets/database/NoteDao.ets` · `entry/src/main/ets/database/StudyPlanDao.ets` · `common/src/main/ets/kit/CardSnapshotStore.ets` · `common/src/main/ets/llm/LlmClient.ets` · `skill/src/main/ets/skillability/SkillAbility.ets` · `cardservice/src/main/ets/formability/FormAbility.ets` | ✅ | 只读 | 现状锚点 |
| `.archify/**/*.html` | ✅ | 只读 | 图示参考；不要编辑生成物 |
| 其余 `.ets` / 业务代码 / ADR / spec | ✅ | **禁止** | 本轮只改设计 |

> 存在性以仓库当前状态为准；第一轮请用 `git status --short`、`test -f` 或编辑器实际打开确认，不要凭本文表格假设。

### 0.4 允许的写入范围

- **默认**：原地修改本文。
- **可选版本化**：只有用户明确要求时，新建 `docs/architecture/agent-application-architecture-design-v2-2026-10-20.md`，并把本文标为 `superseded by ...`；否则不要新增文件。
- `docs/architecture/index.md` 只在标题 / 状态 / 索引行变化时改。
- 不改代码、不改 ADR/spec、不改 `AGENTS.md`、不改 `.archify/*.html`。

### 0.5 修改清单（按章节）

| 章节 | 修改要求 |
|---|---|
| §1 背景与目标 | 结论保留；只补“Codex 修订点”，不要改写的目标 |
| §2 现状 | 核对 5 module、目录计数、入口、数据归属；发现偏差以代码为准 |
| §3 约束 | 确认 5 module、依赖方向、ADR-0008 非目标、HITL/有界执行 |
| §4 应用架构 | 确认 Dispatcher 主 Agent、AgentRuntime 内核、3 个子图、MCP/RAG/Model 分层 |
| §5 Agent 设计 | 确认主图 6 节点、子图阶段、内核块、LangGraph 映射与差距 |
| §6 信息流 | 确认 输入 → Dispatcher → 子图/工具 → Verify → HITL → App Store → Card/APP |
| §7 契约 | 确认端口定义位置与实现方；数据归属 |
| §8 迁移 | 确认分阶段、无并行 runtime、同切片删旧 |
| §9 待决策 | 保留或收敛，不要新增没有代码依据的“已实现” |
| §10–§13 | 校验路径、链接、图示索引、Status/Related/Code 控制块 |
| 新增（可选） | “文件影响清单”“决策记录（ADR 候选）”两节；不要复制大段代码 |

### 0.6 验收标准

- 5 个 module，没有第 6 个；`common` 承担 kernel/runtime。
- `Dispatcher` = 本地主 Agent；`AgentRuntime` = 图执行器；两者边界写清。
- Note / Review / MathVideo 是子图；分类/结构化/校验是 NoteAgent 内部阶段。
- MCP / RAG / Model 在 `common`；App Store 由 `entry` 持有；卡片只读投影、不调 Agent。
- 不把目标组件写成“已实现”；所有代码路径存在；相对链接可解析。
- 改动只落在 `docs/architecture/`；`node scripts/agent-gate/index.mjs` 返回 `RESULT: PASS`。

### 0.7 第二轮输出格式

1. 修改文件列表（相对路径）；
2. 按章节的 diff 摘要（不超过 10 条）；
3. 新增 / 修改的决策（如有）；
4. 未解决风险与待确认项；
5. `agent-gate` 结果；
6. 明确写“未修改代码”。

### 0.8 一页结论（给 Codex 快速对齐）

- 5 个 module 不变：`entry`（APP + App Store）、`agents`（Dispatcher 主 Agent + 子图）、`common`（Kernel + MCP/RAG/Model/Data）、`skill`（小艺）、`cardservice`（只读卡片）。
- `Dispatcher` 是主 Agent；`AgentRuntime` 在 `common`，执行主图/子图，不是第二个 Agent。
- 三个子图：Note（classify → structure → verify）、Review（plan → ask → grade）、MathVideo（outline → script → render）。
- 唯一需要修订 ADR-0008 的点是 **Subgraph**；Checkpoint/HITL 继续留在业务层。
- 3 个待确认：AgentRuntime 是否放 common；公开入口用 `Dispatcher.dispatch` 还是 `AgentFacade`；Subgraph 用内核节点还是 Tool 调用。

**可直接发给 Codex 的启动句**：

```text
先读 docs/architecture/agent-application-architecture-design-2026-10-20.md 的 §0。
第一轮只输出文件影响清单、准备修改的章节、最多 3 个问题；
不要改任何文件，最后一行写 WAITING_FOR_FILE_CONFIRMATION。
```

## 1. 背景与目标

MindTrace 是 HarmonyOS 数学学习助手，当前形态是 **APP + 小艺 skill + 元服务卡片**，核心链路是拍照 / OCR / AI 分类 / 知识结构化 / 笔记生成 / 复习。

目标形态是 **AI 终端**：

1. `entry` 是 APP（页面、ViewModel、平台适配、笔记与复习计划存储）；
2. `skill` 是小艺入口，调用同一套 Agent 能力；
3. `cardservice` 只读 Agent 产出的结果（复习计划 / 笔记摘要），不触发 Agent；
4. `agents` 是 AI Agent 层：一个本地主 Agent（Dispatcher）+ 多个专业子图（Note / Review / MathVideo）；
5. `common` 是 Agent Framework Kernel + 能力层：StateGraph、AgentRuntime、ToolLoop、MCP、RAG、Model Gateway、Data Access；
6. 设计理念采用 **LangGraph 的图模型**（Node / Edge / State / Conditional Edge / Subgraph），但**不引入 LangGraphJS / Python 运行时**，内核在 ArkTS 自研（ADR-0008）。

## 2. 现状（as-built）

### 2.1 五个 module

| Module | `module.json5` type | 声明依赖 | 当前职责 |
|---|---|---|---|
| `entry` | `entry` | common、agents | APP 外壳、页面/浮窗、ViewModel、59 个 service 文件、6 个 conversation workflow 文件、7 个 database 文件、平台 Kit 实现 |
| `common` | `shared` | 无业务 module | LlmClient/LlmGuard、StateGraph、ToolLoop/ToolRegistry、Kit facade、ContentProtocol、DatabaseHelper |
| `agents` | `shared` | common | Dispatcher、CaptureGraph、TypeClassifier、KnowledgeModel、TruthCheckService、OcrTool、NoteDaoInterface |
| `skill` | `feature` | common、agents（声明） | SkillAbility、IntentRouter、SkillIntentWorkflow |
| `cardservice` | `feature` | common | FormAbility、CardEntryAbility、TodayReviewCard |

> 文档偏差：`AGENTS.md` 与 spec 018 写“4 HSP 全部 `type:feature`”；代码实际是 `common`/`agents` = `shared`，`skill`/`cardservice` = `feature`。Codex 以 `module.json5` 为准。

### 2.2 当前关键入口

```text
entry/EntryAbility
  → DatabaseHelper.init
  → AgentChatService → ConversationRuntime → ConversationWorkflow（entry）
      → AiService.captureText → Dispatcher.dispatch
          → preparedCandidate / regenerate / generation / capture 四条分支
          → CaptureGraph（capture → classify → structure → truth_check → persist）

skill/SkillAbility
  → IntentRouter → SkillIntentWorkflow
      → 当前只实装 SearchNote（复用 note_query），其余 6 action unsupported

cardservice/FormAbility
  → CardSnapshotStore（只读）→ TodayReviewCard
```

### 2.3 当前数据归属

| 数据 | 位置 | 说明 |
|---|---|---|
| 笔记 `knowledge_unit` | `entry/src/main/ets/database/NoteDao.ets` | schema source of truth；agents 通过 `NoteDaoInterface` 注入 |
| 复习计划 `study_plan` | `entry/src/main/ets/database/StudyPlanDao.ets` | APP 持有 |
| RDB 初始化 | `common/src/main/ets/DatabaseHelper.ets` | `EntryAbility` 初始化；common 不自建 context |
| RAG 向量 | `entry/src/main/ets/database/RagEmbeddingDao.ets` | 文件头标注 **demo-only**；不是生产 RAG 层 |
| 检索清洗 | `entry/src/main/ets/services/NoteRetrievalQuery.ets` | 只做查询词清洗，不做索引/召回 |
| 卡片快照 | `common/src/main/ets/kit/CardSnapshotStore.ets` | cardservice 只读 |

### 2.4 当前能力缺口（Codex 必须知道）

- **MCP**：`agents/src/main/ets/mcp/tools/OcrTool.ets` 只是“MCP 语义”的目录分类，没有 MCP Host / Client / Server、schema 注册或权限层（ADR-0010）。
- **RAG**：没有 `common/rag`；`RagEmbeddingDao` 是 demo-only，`NoteRetrievalQuery` 只是查询清洗。
- **ToolLoop**：`common/tools/ToolLoop.ets` + `common/workflow/tool-calling/` 已实现 ReAct 形状（`maxSteps=4`），但**生产链未接**，目前只有测试/spec 使用。
- **多 Agent**：只有一个 Dispatcher + Capture 管线，没有主图/子图、没有 ReviewAgent / MathVideoAgent。
- **订阅/卡片**：cardservice 已是只读 `CardSnapshotStore`，不调 Agent。
- **Tracing**：没有统一 RunContext / EventSink；生成有 `progressSink`，但不是通用 agent run trace。

## 3. 约束与不可破坏项

1. **5 个 module，不新增第 6 个**；`runtime` 的职责由 `common` 承担。
2. **依赖方向**：`entry / skill / cardservice → agents / common`；`agents → common`；`common` 不 import `entry` / `agents`；`cardservice` 不 import `entry`（HAP）。
3. **LangGraph 理念，自研内核**：沿用 `StateGraph` / Node / Edge / State / conditional edge / START / END 词汇；不引入 LangGraphJS / Python sidecar（ADR-0008）。
4. **有界执行**：`maxSteps` / `maxNodeRuns` 必须有上限；不做无界自主循环、并行 fan-out、后台自动续跑。
5. **写入门禁**：AI 结果先形成草稿，HITL 确认后才写入 App Store；不开放写类 AgentTool。
6. **数据归属**：笔记 / 复习计划由 `entry` 持有；`common` 定义端口与 RDB 访问；`agents` 只依赖端口，不直接写库。
7. **ADR-0008 的非目标**：Checkpoint / HITL / Subgraph 目前被列为“不做”。本文的多 Agent 需要 **Subgraph**，因此需要新增 / 修订 ADR；Checkpoint / HITL 建议继续留在业务层（草稿 / 确认），不要做成 runtime checkpoint。

## 4. 目标应用架构（v7）

### 4.1 分层

| 层 | Module | 组件 |
|---|---|---|
| 接入 | `entry` / `skill` / `cardservice` | APP、小艺、卡片 |
| 主 Agent | `agents` | `Dispatcher` 主图（preflight / route / HITL / publish） |
| 专业 Agent | `agents` | `NoteAgent`、`ReviewAgent`、`MathVideoAgent`（子图） |
| 框架内核 | `common` | `AgentRuntime`、`StateGraph`、`ToolLoop`、`RunContext`、`EventSink`、`State/Reducer`、`Checkpoint`、`Trace` |
| 能力 | `common` | MCP Host、RAG Layer、Model Gateway、Data Access |
| 存储 / 消费 | `entry` / `common` / `cardservice` | App Store（notes / plans / vectors）、Card Snapshot 投影、APP 展示、卡片 |

### 4.2 Module 职责

**entry（APP）**

- 页面 / 浮窗 / ViewModel / 平台适配（Reminder、BackgroundTask、FormCard、权限、Picker）；
- App Store：笔记、复习计划、视频产物的存储与编辑；
- 组合根：初始化 RDB、装配 DAO / Port / Dispatcher；
- 不写 prompt、不跑 Agent 循环、不直接碰 MCP/RAG。

**agents（AI Agent）**

- `Dispatcher`：本地主 Agent，持有主图与顶层状态，负责路由、子图调用、HITL、结果汇总；
- `NoteAgent`：`classify → structure → verify`，输出 NoteDraft；
- `ReviewAgent`：`plan → ask → grade`，输出 StudyPlan / ReviewSession；
- `MathVideoAgent`：`outline → script → render`，输出 VideoArtifact；
- 共享 `AgentRuntime`、`Memory`、结果发布 / HITL；
- 不直接写 RDB、不直接发 HTTP / LLM 请求。

**common（Kernel + Capability）**

- `AgentRuntime`：执行主图/子图，节点调度、状态流转、取消、事件；
- `StateGraph`：Node / Edge / State / conditional edge / `run(maxNodeRuns)`；
- `ToolLoop` / `ToolCallingWorkflow`：ReAct ToolNode（`maxSteps=4`）；
- `RunContext` / `EventSink`：runId、parentRunId、budget、node/token 事件（目标补）；
- `State / Reducer`：typed channel，减少手写 `copyState`；
- `Checkpoint` / `Trace`：业务级草稿检查点 + run/trace（不强行做 runtime checkpoint）；
- `MCP Host`：Tools / OCR / Query 的 schema、发现、执行、权限；
- `RAG Layer`：ingest / chunk / embedding / index / retrieve / rerank / citation；
- `Model Gateway`：LlmClient / LlmGuard / stream / JSON / tool_calls；
- `Data Access`：DatabaseHelper、RDB schema/迁移、基础 DAO、向量表。

**skill（小艺）**

- Want 解析、Intent Router、参数校验、`Dispatcher` 调用、结果呈现、深链回 APP 确认；
- 不写业务规则、不直接连 MCP/RAG。

**cardservice（卡片）**

- FormAbility / CardEntry / Card Renderer；
- 只读 `CardSnapshotStore`（App Store 投影），不调 Agent、不查库。

## 5. Agent 设计

### 5.1 Dispatcher 主图

```text
preflight → route → invoke → verify → HITL → publish
```

- `preflight`：校验 payload / source / 预算 / 权限；
- `route`：条件边，按 intent 选择 `NoteAgent` / `ReviewAgent` / `MathVideoAgent`；
- `invoke`：同步调用子图，传入 typed state，拿回 artifact；
- `verify`：schema / truth / 业务约束；
- `HITL`：草稿预览、用户确认；
- `publish`：写 App Store（笔记 / 计划 / 视频），不直接写库。

> 与现状的关系：现在是 `Dispatcher.dispatch` 的四条固定分支（preparedCandidate / regenerate / generation / capture）。目标把这些模式判断下沉到 `NoteAgent` 子图，Dispatcher 主图只保留“选哪个 Agent、何时确认、何时发布”。

### 5.2 三个子图

| 子图 | 阶段 | 输出 | 当前可复用 |
|---|---|---|---|
| NoteAgent | classify → structure → verify | NoteDraft / KnowledgeUnit | TypeClassifier、KnowledgeModel、TruthCheckService、CaptureGraph |
| ReviewAgent | plan → ask → grade | StudyPlan / ReviewSession | NoteReviewService、StudyPlan 数据（设计新增） |
| MathVideoAgent | outline → script → render | VideoArtifact / mp4 | 无（设计新增；渲染走外部服务） |

**粒度原则**：一个 Agent = 一个目标 + 一份上下文 + 一个 run；分类/结构化/校验是 NoteAgent 的内部阶段，不拆成三个 Agent。只有需要独立目标、独立权限或并行时才升级为子 Agent。

### 5.3 框架内核

| 内核块 | 职责 | 现状 |
|---|---|---|
| `AgentRuntime` | 执行主图/子图；节点调度、取消、事件 | 目标；当前只有 `StateGraph.run` |
| `StateGraph` | Node / Edge / State / conditional edge / maxNodeRuns | 已实现（约 100 LOC） |
| `ToolLoop` | ReAct ToolNode；模型 → 工具 → 回喂 | 已实现；生产未接 |
| `RunContext` | runId、parentRunId、cancel、budget | 目标（当前只有 CancellationToken） |
| `EventSink` | node start/end、tool call、token、approval | 目标（当前只有 progressSink） |
| `State / Reducer` | typed channel、状态合并 | 目标（当前手写 `copyAgentState`） |
| `Checkpoint` | 草稿 / 候选检查点 | 业务级（不是 runtime checkpoint） |
| `Trace Store` | run / step / token / latency | 目标 |

### 5.4 与 LangGraph 的对应

| LangGraph | MindTrace 自研 |
|---|---|
| Graph | `StateGraph` |
| Node | `addNode` |
| Edge | `addEdge` |
| Conditional Edge | `addConditionalEdge` |
| State / Channels | typed State（`AgentState` / `ToolCallingState`） |
| Subgraph | 目标能力，当前内核没有 |
| ToolNode | `ToolCallingWorkflow` / `ToolLoop` |
| Checkpoint / Interrupt | 业务级 draft / confirm；不是 runtime checkpoint |
| Stream events | 目标 `EventSink`；当前 `progressSink` |
| Run config（thread / run / cancel） | 目标 `RunContext`；当前 `CancellationToken` |

### 5.5 内核差距（按优先级）

1. **Subgraph 调用**：把 Note / Review / Video 作为子图节点，而不是普通函数硬调；
2. **RunContext**：runId / parentRunId / cancel / budget，保证每个 Agent 的 run 隔离；
3. **EventSink**：node / tool / token / approval 事件，供 UI 与 trace；
4. **State / Reducer**：子图增多后，手写 `copyAgentState` 容易漏字段；
5. **Checkpoint 决策**：建议保持业务级；若要做 runtime checkpoint，需要单独 ADR。

## 6. 端到端信息流

### 6.1 主链路

```text
APP 输入 / 小艺 Want
  → Dispatcher（preflight / route）
  → NoteAgent（classify → structure）
  → 工具 / 模型 / 知识（MCP/OCR · Model · RAG，取数 → 回填）
  → Verify
  → HITL（预览确认）
  → App Store（notes / plans / vectors）
  → 卡片（读投影） / APP 展示（笔记 · 计划 · 视频）
```

### 6.2 分支

- **ReviewAgent**：`plan → ask → grade → study plan` → App Store → 卡片 / APP；
- **MathVideoAgent**：`outline → script → render` → 视频渲染/TTS → mp4 → App Store → APP。

### 6.3 数据产物

| 阶段 | 输入 | 输出 |
|---|---|---|
| 输入 | 图片 / 文本 / 文件 / Want | `DispatchRequest` / typed intent |
| 采集 | 图片 | OCR text / formulas |
| 分类 | text | `ClassificationResult` |
| 结构化 | text + classification + evidence | `KnowledgeUnit` / NoteDraft |
| 校验 | draft | verified draft / issues |
| 确认 | verified draft | approval / commit |
| 落库 | approval | note / plan / video 行 |
| 索引 | note | embeddings / vectors（App Store 内） |
| 投影 | note / plan | Card Snapshot |
| 消费 | snapshot | 卡片 / APP 展示 |

> 图示：`.archify/dataflow-mindtrace-e2e-20261020-144000/mindtrace-e2e-flow.html`。为了可读性，图中把 OCR/LLM/RAG 合成一个“工具/模型/知识”取数环，把 Card Snapshot / RAG Index 折进 App Store 与卡片节点；分层细节在应用架构图。

## 7. 跨模块契约

| 契约 | 定义位置 | 实现 / 使用 |
|---|---|---|
| `Dispatcher.dispatch`（或 `AgentFacade`） | `agents` | entry / skill 调用 |
| `NoteReadPort` / `NoteWritePort` | `common` | entry 实现；agents 使用 |
| `StudyPlanReadPort` / `StudyPlanWritePort` | `common` | entry 实现；ReviewAgent 使用 |
| `ArtifactStorePort` | `common` | entry 实现；MathVideoAgent 使用 |
| `CardSnapshotStore` | `common` | entry 写投影；cardservice 只读 |
| `RunStore` | `common` | agents 写 run / trace；UI 只读 |
| `NoteDaoInterface` | `agents` | entry `NoteDaoAdapter` 实现（现状） |

依赖方向：

```text
entry / skill / cardservice
        ↓
      agents
        ↓
      common
```

`common` 不反向依赖任何业务 module；`agents` 不 import `entry`；`cardservice` 不 import `entry`。

## 8. 迁移顺序

1. **ADR**：修订 ADR-0008，放开 Subgraph（只放开这一项；Checkpoint/HITL 保持业务级）。
2. **Kernel**：补 `RunContext` / `EventSink` / `Subgraph` 调用；把 `ToolLoop` 接入生产链。
3. **Dispatcher 主图**：把现有四条分支收进 `NoteAgent` 子图；Dispatcher 变成 `preflight → route → invoke → verify → HITL → publish`。
4. **专业子图**：NoteAgent 先复用 CaptureGraph / TypeClassifier / KnowledgeModel / TruthCheck；再加 ReviewAgent、MathVideoAgent。
5. **能力层**：`OcrTool` 与工具协议收进 `common/mcp`；RAG 存储/检索从 entry 的 demo 收进 `common/rag`。
6. **端口与数据**：`NoteRead/WritePort`、`StudyPlanRead/WritePort`、`ArtifactStorePort` 放 common，entry 实现；App Store 仍是笔记/计划的归属。
7. **前端切换**：skill 调 `Dispatcher`；cardservice 继续只读投影；entry 只留 UI / App Store / 平台适配。
8. **删旧**：同一切片删除旧实现；不允许新旧 runtime 并行、双读/双写、feature flag 长期存在。

## 9. 待决策（给 Codex / 评审）

1. **AgentRuntime 放哪**：本文建议放 `common`（框架内核，执行所有图）。如果放 `agents`，common 就不是完整框架，需要说明边界。
2. **公开入口**：保留 `Dispatcher.dispatch`，还是加 `AgentFacade` 作为稳定 API？不建议两者都暴露。
3. **Subgraph 实现**：内核加 `invokeSubgraph` 节点，还是把子图当 Tool 调用？前者更 LangGraph，后者更简单。
4. **Checkpoint / HITL**：继续业务级（草稿 / 确认），还是做 runtime checkpoint/interrupt？本文建议业务级。
5. **数据归属**：笔记/计划由 entry 持有、common 只定义端口 + RDB 访问，是否接受？
6. **Video**：端侧只产脚本/分镜，渲染/TTS 走外部服务，是否接受？
7. **ReviewAgent 范围**：只生成计划，还是也负责出题、评分、错题追踪？本文倾向后者。

## 10. 已知偏差 / 风险

- `AGENTS.md` / spec 018 的 “4 HSP type:feature” 与 `module.json5` 不一致；
- `common` 目前没有 `mcp/`、`rag/` 目录；MCP 只是 `agents/mcp` 语义目录；RAG 是 entry 的 demo-only；
- `ToolLoop` 生产未接；
- 没有统一 `RunContext` / `EventSink` / Trace；
- 卡片已只读 `CardSnapshotStore`，不要把它画成 Agent 调用方；
- 本设计图是本地 `.archify/` 生成物，未入 git；Codex 不要把它们当代码事实。

## 11. 代码锚点

| 用途 | 路径 |
|---|---|
| Dispatcher / 四条分支 | `agents/src/main/ets/core/Dispatcher.ets` |
| CaptureGraph | `agents/src/main/ets/graph/CaptureGraph.ets` |
| StateGraph | `common/src/main/ets/workflow/StateGraph.ets` |
| ToolLoop / ToolCalling | `common/src/main/ets/tools/ToolLoop.ets` · `common/src/main/ets/workflow/tool-calling/ToolCallingWorkflow.ets` |
| ToolRegistry / 只读工具 | `common/src/main/ets/tools/ToolRegistry.ets` · `common/src/main/ets/tools/NoteQueryTools.ets` |
| OcrTool（MCP 语义） | `agents/src/main/ets/mcp/tools/OcrTool.ets` |
| LlmClient / Guard | `common/src/main/ets/llm/LlmClient.ets` · `common/src/main/ets/llm/LlmGuard.ets` |
| 笔记 / 计划 DAO | `entry/src/main/ets/database/NoteDao.ets` · `entry/src/main/ets/database/StudyPlanDao.ets` |
| RAG demo | `entry/src/main/ets/database/RagEmbeddingDao.ets` · `entry/src/main/ets/services/NoteRetrievalQuery.ets` |
| 卡片快照 | `common/src/main/ets/kit/CardSnapshotStore.ets` |
| 小艺入口 | `skill/src/main/ets/skillability/SkillAbility.ets` · `skill/src/main/ets/workflows/intent/IntentRouter.ets` |
| 卡片入口 | `cardservice/src/main/ets/formability/FormAbility.ets` · `cardservice/src/main/ets/entryability/CardEntryAbility.ets` |

## 12. 图示索引（本地生成物，未入 git）

| 图 | 路径 |
|---|---|
| 现状模块架构 | `.archify/architecture-mindtrace-modules-20261020-113037/mindtrace-module-architecture.html` |
| 目标应用架构 v7 | `.archify/architecture-mindtrace-app-v7-20261020-143320/mindtrace-app-v7.html` |
| Agent 设计架构 | `.archify/architecture-mindtrace-agent-design-20261020-143320/mindtrace-agent-design.html` |
| 端到端信息流 | `.archify/dataflow-mindtrace-e2e-20261020-144000/mindtrace-e2e-flow.html` |
| 现状 vs 目标对照 | `.archify/architecture-mindtrace-compare-20261020-120000/index.html` |

## 13. 相关文档

- [ADR-0008 — LangGraph model, native ArkTS runtime](../adr/0008-capturegraph-self-built-runtime.md)
- [spec 018 — Agent workflow architecture](../specs/018-agent-workflow-architecture.md)
- [ADR-0010 — MCP / tools semantics](../adr/0010-mcp-tools-semantics.md)
- [ADR-0012 — Tool-calling protocol](../adr/0012-tool-calling-protocol.md)
- [spec 014 — Tool-calling protocol](../specs/014-tool-calling-protocol.md)
- [Agent glossary](../agents/agent-glossary.md)
