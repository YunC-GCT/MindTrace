# 后端架构推进交接 — 2026-09-07

> **给谁**:接手后端(agents/ + common/llm,kit,tools)工作的下一个 session。
> **不是**:本文不重复 [`docs/agents/handoff-2026-09-06.md`](./handoff-2026-09-06.md) 的一屏现状 / TBD / 已知坑 / 拼窗口 — 那里是**时间点交接**, 本文是**深度推进路线图**。与代码冲突时, **代码 + `docs/specs/index.md` §"Implementation status" 优先**。
> **何时读**:接手 #7 AgentChatService 拆分 / Kit 集成 / Tool 写路径 / skill IntentRouter / ReviewGraphView 拆分(C3 后续)**之前**必读。

---

## 0. 一屏

后端 5 module 单向依赖稳定:

```
entry → agents → common
entry → common
cardservice → common
skill → agents, common       (skill 不能 import entry — ADR-0011)
agents 不能 import entry      (持久化走 NoteDaoInterface 注入, ADR-0001)
```

**3 个核心 seam 已 sealed**:Dispatcher 单入口 (ADR-0003) + LlmClient 单 call (ADR-0004) + KnowledgeModel 拆三服务 (spec 015, ADR-0006)。**接活时不要重新打开** — 它们是后续推进的稳定锚。

**5 个未封口 seam**,按 forward path 优先级:

1. spec 007 PR3 — `ReplyService` 抽取 (AgentChatService 516 → ≤ 100 LOC facade)
2. ADR-0012 写路径 — `ToolRegistry` 写类工具接入 (gated on F2 write-path unification)
3. spec 013 — `BackgroundTaskFacade` + `FormCardFacade` 实现 (ReminderFacadeImpl 已落地作为模板)
4. ADR-0011 — `skill/ IntentRouter` 实装 (gated on 7 个 intent action 语义经队员确认)
5. audit C3 — `ReviewGraphView` 1880 行拆 5 模块 (纯视觉拆分)

---

## 1. 推进顺序(completion criterion 在每步内)

### Step 1 — spec 007 PR3:ReplyService 抽取

> **forward path**:完成 AgentChatService → facade 收敛,与 PR1 (IntentClassifier) + PR2 (ChatStatusMachine) 形成三件套。

- **读**:
  - [`docs/specs/007-agent-chat-service-decomposition.md` §"PR 3"](../specs/007-agent-chat-service-decomposition.md) — spec 写的设计
  - [`docs/specs/007-agent-chat-service-decomposition.md` §"Progress (2026-09-07)"](../specs/007-agent-chat-service-decomposition.md) — 现状: PR1 + PR2 已合, AgentChatService 861 → 516 LOC
- **范围**:`entry/src/main/ets/services/`
  - 新建 `ReplyService.ets` (~300 LOC) — `realReply` / `realReplyStream` / `captureReply` 编排 (classify → memory → prompt → LLM → normalize → memory-write)
  - 收敛 `AgentChatService.ets` 至 ≤ 100 LOC (纯 facade)
- **Seam 边界**(确保不引入循环依赖):
  - 构造注入 `IntentClassifier` (PR1 已抽) + `AgentMemoryService` + `ContentProtocol`
  - 不持 UI 状态 — `setBusy` / `setStatusMeta` 留在 AgentChatService facade
- **守门**:
  - Hypium 新 4 + 1 例(ReplyService 4 + AgentChatService facade 1)— **DevEco GUI 跑**, CLI 不可用
  - Source-level structural guard: `AgentChatService.ets` ≤ 100 LOC + `class ReplyService` 存在 + `delegate` 模式 (1-line 转发)
  - `node scripts/arkts-lint/index.mjs --quiet` warnings -80(随方法外迁)
- **completion criterion**:`AgentChatService.ets` 行数 ≤ 100 + `ReplyService.ets` 存在且 `realReply/realReplyStream/captureReply` 三方法齐全 + 10 个 Hypium 例全绿 + 实机对话路径表现不变(reply 同 / 状态转换同 / 记忆读写同)。
- **避开**:不要在 PR3 顺手改 ChatStatusMachine 的 observable `step` 字段 + `reset()` (spec L59/L61 已标 **PR2 未实现, 留给 PR3 裁决**); PR3 scope 仅限 ReplyService 抽取 + facade 收敛。

### Step 2 — ADR-0012 写路径:Tool 写类接入

> **forward path**:让 LLM 能主动写笔记/创建清单/调状态,完成 spec 014 §"写类"全部 5 项(Note insert/update/delete + study_plan create/update + review_state transition)。
> **gated on**:F2 写库路径统一(项目当前有 3+ 处 note 写入路径,gating 不统一,inventory F2)— 这是赛前已知缺口,先做 F2 再开写工具。

- **读**:
  - [`docs/architecture/agent-tools-inventory-2026-09-06.md`](../architecture/agent-tools-inventory-2026-09-06.md) — F2 三入口列出
  - [`docs/specs/014-tool-calling-protocol.md` §"Out of scope"](../specs/014-tool-calling-protocol.md) — 写路径不写的原因
  - [`docs/adr/0012-tool-calling-protocol.md`](../adr/0012-tool-calling-protocol.md) §"Considered Options" §3 — rejected 的核心理由
- **先做 F2**(在 spec 014 之外另立 spec):
  - 把 `entry/services/StudyPlanService` 等写库调用统一走**单一 validation gate**(`WritePathValidator`)
  - 干掉 inventory 列出的"双入口 Middle Man" + "normalize 哨兵三重复"
- **再做写工具**:F2 落地后,新增写工具只需在 `common/src/main/ets/tools/NoteWriteTools.ets` 注册 `AgentTool`,沿用 `ToolRegistry.execute()` 路径。
- **completion criterion**:F2 spec 落地 + 3+ 处写路径统一走 WritePathValidator + 至少 2 个写工具(NoteWriteTool + StudyPlanWriteTool)落地 + ToolLoop 端到端跑通(模型决策 → 写 → 持久化)。

### Step 3 — spec 013 P0 剩余:BackgroundTask + FormCard

> **forward path**:完成 Kit 接线的 P0 三件套(Reminder 已闭环作为模板)。

- **读**:
  - [`docs/specs/013-kit-adoption-boundary.md` §"Priority matrix"](../specs/013-kit-adoption-boundary.md) — P0 三个 Kit 的接缝已写
  - [`entry/src/main/ets/kit/ReminderFacadeImpl.ets`](../../entry/src/main/ets/kit/ReminderFacadeImpl.ets) — **唯一可参考实现**(81 行),**复制其模式**(契约 → impl → 组合根注入 AppStorage)
- **范围**:
  - `common/src/main/ets/kit/BackgroundTaskFacade.ets` 契约已存在, 新建 `entry/src/main/ets/kit/BackgroundTaskFacadeImpl.ets`
  - `common/src/main/ets/kit/FormCardFacade.ets` 契约已存在, 新建 `entry/src/main/ets/kit/FormCardFacadeImpl.ets`
  - `EntryAbility.onCreate` 增加 2 行组合根注入
- **守门**(mirror ReminderImpl 已做的):
  - Source-level:契约方法在 impl 中全覆盖 (no throw "not implemented")
  - Hypium 新 2 例 — DevEco GUI 跑
- **completion criterion**:2 个 impl 存在 + 组合根注入 + 实机验证(后台拉取触发 / 卡片刷新)— UI 入口是否挂仍按用户裁决,不擅自加。
- **避开**:`@kit.ArkUI` 的 `visualEffect` / `Filter` / `V2` 装饰器不可用(API 12+,当前 API 9)— background/卡片自定义 UI 受约束。

### Step 4 — ADR-0011:skill IntentRouter 实装

> **forward path**:让小艺 7 个 intent action 真正能路由到 ToolRegistry。
> **gated on**:**7 个 intent action 语义需队员确认**(spec L20, open item)。这是先决 blocker,不解决不能动。

- **读**:
  - [`docs/adr/0011-skill-xiaoyi-reservation.md`](../adr/0011-skill-xiaoyi-reservation.md) §"Consequences" — 7 个 intent action 名 + IntentRouter 路径
  - [`docs/research/agent-toolkit-and-skill-dispatch-2026-09-06.md`](../research/agent-toolkit-and-skill-dispatch-2026-09-06.md) §4-5 — 实装细节(InsightIntent 装饰器, API 11+)
- **范围**:
  - **先**与队员确认 7 个 intent action 的语义(写新 doc `docs/agents/skill-intent-semantics.md`,逐个写"输入 → 触发条件 → 落点工具")
  - 然后新建 `skill/src/main/ets/IntentRouter.ets` — `want.action` → ToolRegistry.execute()
- **避坑**:`@InsightIntent{Link,Page,Function,Form,Entry}` 装饰器 API 11+, MindTrace 兼容 SDK 6.1.1 (API 24) 支持, 但需在 `skill/src/main/module.json5` 声明 `entity.system.intent`
- **completion criterion**:7 个 intent 语义 doc 已签字 + IntentRouter 实装 + ToolRegistry reuse + 实机小艺入口触发 → 工具调用走通。
- **状态**:**不开工**(队员语义确认是 blocker)— 这一步更多是"等"而非"做"。

### Step 5 — audit C3:ReviewGraphView 1880 行拆 5 模块

> **forward path**:C3 Worth exploring, 不在复赛窗口;赛后第一步。
> **优先级**:低 — 不挡 demo / 不挡 release; 审查看 C3 是 ReviewGraphView 1880 行 + 96 处 rgba 字面量 + 8 处 setInterval 硬编码 (与 PR-A 的 GradientRing 同病)。

- **读**:
  - [`docs/research/frontend-component-audit-2026-09-06.md`](../research/frontend-component-audit-2026-09-06.md) §"审核 1-原子化/分子化标准" + §"加深机会候选 C3"
- **范围**(纯视觉拆分, 改 行为):
  - 把 1880 行按主题切 5 文件:`GalaxyCamera` / `KnowledgeOrbit` / `SubjectChip` / `NoteDetailPanel` / `PlanStats`
  - 共享子模块:`Camera`, `OrbitMath`, `SubjectColor`
- **守门**:复用 spec 015 / PR-A 的**纯提取纪律**(字节级 diff 只允许"文件名/import/转发移除"三类差异)— 用户要求, 见 [`docs/agents/handoff-2026-09-06.md` §3.4](./handoff-2026-09-06.md)。
- **completion criterion**:5 个新文件 ≤ 500 LOC each + ReviewGraphView ≤ 200 LOC(facade)+ Hypium 视觉测试覆盖 + 实机 demo 表现不变。

---

## 2. 后端 5 层地图(reference)

### 2.1 `common/` — 共享基础

| 路径 | 责任 | sealed? |
|---|---|---|
| `common/src/main/ets/llm/` | `LlmClient` (单 call, ADR-0004) / `LlmConfig` / `LlmGuard` / `LlmTypes` / `LlmOutputRules` | ✅ spec 005 |
| `common/src/main/ets/tools/` | `ToolRegistry` + `ToolLoop` + `NoteQueryTools`(P1 只读,spec 014) | ✅ spec 014 §1-3 |
| `common/src/main/ets/render/` | `ContentProtocol` (MM-MD-v1) + `ContentExcerptBuilder` + `MathRenderCache` (PR-B) | ✅ spec 016 PR-B |
| `common/src/main/ets/motion/` | `MotionPolicy` (single entry + MOTION_TABLE, issue #65) | ✅ spec 016 PR-A |
| `common/src/main/ets/kit/` | 3 facade contracts(`Reminder` / `BackgroundTask` / `FormCard`),impl 留在 entry | ✅ spec 013 契约 |
| `common/src/main/ets/agents/` 共享类型 | `CaptureChain` (DispatchRequest 等) / `CommonTypes` (KnowledgeUnit 等) | — |
| `common/src/main/ets/constants/ColorTokens.ets` | 颜色 + 字号 + 间距 + DUR_* + 曲线令牌 | — |
| `common/src/main/ets/utils/` | `logger` (统一hilog) / `uuid` / `timeWindow` / `FileUriUtils` / `LatexRiskNormalizer` / `confidenceSort` | — |

**关键不变量**:`common/` 不 import `agents/` 或 `entry/`(拓扑红线)— `agents/Index.ets` 与 `entry/` 可 import 自 `common`。

### 2.2 `agents/` — AI 业务(HSP)

```
agents/src/main/ets/
├── Index.ets                     # 模块入口 (导出 Dispatcher / NoteDaoInterface / KnowledgeCategory)
├── core/
│   └── Dispatcher.ets            # 单入口 dispatch(req, opts) → CaptureGraph host (ADR-0003)
├── graph/
│   ├── AgentState.ets            # CaptureStep / CaptureNode / CaptureGraphError / AgentState
│   ├── CaptureGraph.ets          # 128 行 minimal LangGraph: addNode/addEdge/addConditionalEdge/run
│   └── nodes/
│       ├── OcrNode.ets           # capture (读 state.payload — PR #58 fix)
│       ├── ClassifyNode.ets      # TypeClassifier.classifyText
│       ├── StructureNode.ets     # KnowledgeModel.structure (PR2 用 StructureService)
│       ├── TruthCheckNode.ets    # TruthCheckService.check
│       └── PersistNode.ets       # NoteDaoInterface 注入
├── agents/
│   ├── KnowledgeModel.ets        # 564 行 (PR1-3 拆后), 编排 agent — **名字经用户裁决保留**
│   ├── PromptBuilder.ets         # 49 行, 提示词常量 + buildPrompt
│   ├── TruthCheckService.ets     # 283 行, 真值检查 4 项 (括号/除零/方程/LaTeX)
│   ├── TypeClassifier.ets        # OCR + 5 类题型 + 学科
│   └── ... (其他子代理)
├── mcp/tools/
│   └── OcrTool.ets               # MCP 语义工具 (ADR-0010 supersede ADR-0005; mcp/ 目录名保留)
├── models/                        # KnowledgeCategory / KnowledgeUnitExt / NoteDaoInterface / TruthCheckResult
└── oh-package.json5
```

**关键 seam**:`Dispatcher` 经 `agents/Index.ets` 暴露 `DispatchRequest` / `DispatchResult` 类型给 `entry/`,后者 `AiService` 调用 `new Dispatcher().dispatch(req, opts)` — `entry/src/main/ets/services/AiService.ets:87,134`(两条独立路径,共用 Dispatcher 实例化)。

### 2.3 `entry/` — UI + 集成(HAP)

```
entry/src/main/ets/
├── pages/                         # 5 Tab + 详情页
├── overlays/                      # 浮 浮 (AgentFloatWindow / CameraOverlay / NoteDetailOverlay)
├── shared/                        # atoms (AppApp / IconButton) + molecules (Markdown / FormulaSplit / MathText / MathPreview)
├── services/                      # 业务服务 (AiService / AgentChatService / AgentMemoryService / ...)
├── kit/                           # ReminderFacadeImpl (entry 端实现)
├── database/                      # NoteDao / StudyPlanDao (RDB 封装)
├── adapters/                      # NoteDaoAdapter (agents/NoteDaoInterface 在 entry 的实现)
├── utils/                         # entry-local utils
└── viewmodels/                    # MVVM
```

**关键 seam**:`entry` 是 `agents` 的**唯一消费方**(Topology 单向)。`Dispatcher` / `KnowledgeModel` / `ToolRegistry` 等都从 entry 调用。

### 2.4 `cardservice/` + `skill/` — 卡片 + 小艺

- `cardservice/`:FormAbility 服务,当前 mock 数据 — spec 013 §"P0 适配 FormKit" 待实装。
- `skill/`:7 个 intent action 已声明(`skill/src/main/module.json5`),**IntentRouter 未实装** — 取决于 Step 4 队员语义确认。

---

## 3. 关键不变量与约束(踩了会痛)

### 3.1 拓扑红线

- `common/` 不 import `agents/` 或 `entry/`
- `agents/` 不 import `entry/`(用 `NoteDaoInterface` 注入)
- `entry/` 可以 import `common/` + `agents/`
- `skill/` 可以 import `common/` + `agents/`,**不** import `entry/`
- `cardservice/` 只可 import `common/`

**唯一例外**:`DevEco template 模块`(entry 的 UIAbility / cardservice 的 FormAbility / EntryAbility)可 import `@kit.*` 直接用 kit API — 这是**模板角色**不是业务耦合(ADR-0009 §"Consequences")。

### 3.2 提取纪律

用户要求**纯提取**(无功能变更):

- 字节级 diff 只允许三类差异:
  1. **类名** 改名
  2. **调用直连**(原本转发 → 直接调用)
  3. **转发移除**(类外迁后删除原转发)
- 提示词 / 常量 / 业务逻辑 一字不改
- 字节级 diff 证据要在 PR description 中给出
- 例:spec 015 PR1-3 是这一纪律的范本(PR #40/#41)

### 3.3 ArkTS 1.1 严格语法(踩了 = build fail)

| 红线 | 例 | 替代 |
|---|---|---|
| `any` / `unknown` | `function f(x: any)` | 显式类型 + `catch (e) { (e as Error).message ?? String(e) }` |
| destructuring decl | `export const { X, Y } from ...` | `export { X, Y } from ...` |
| destructuring params | `function f({a, b})` | 显式命名参数 |
| spread | `[...arr, x]` 或 `f(...args)` | 显式列举 / `Object.assign` |
| typed catch | `catch (e: ErrorType)` | `catch (e)` + `(e as Error).message` |

**完整规则** [`docs/style/arkts-1.1.md`](../style/arkts-1.1.md) + 项目偏好 §"ArkUI 项目级约束"(struct 内禁普通方法 / 禁 get accessor / 字段名避开 CommonAttribute)。

**血泪**:本次 PR-C 撞了 destructuring decl(PR-B commit 在 `Index.ets:144` 写了 `export const { ... } from` → hvigor 报 10605074 → 必须改 `export { ... } from`)。**Source-level 测试不抓语法**(我们只 grep 名字存在),arkts-lint Node v0.3 报 parse-error 静默忽略 — **必须 hvigor build 才能抓**。

### 3.4 Hypium 只能 DevEco GUI 跑

`node --test` 跑不通 Hypium(.ets 文件不是 Node 可执行)—。交付新 Hypium 例后**必须请用户跑 DevEco**,不能用"我跑通了"为结案理由。

---

## 4. 关键 ADR 决策摘要(已 sealed,不要翻案)

- **ADR-0001**: `entry/services/` 可直接 import `agents/`(不强制接口)— 唯一例外是 ADR-0009 sealed 后
- **ADR-0003**: Dispatcher 单入口 `dispatch(req, opts?)`, 旧 `analyze` / `routeDispatch` 已删
- **ADR-0004**: LlmClient 单 `call(request)`, 适配器选 `opts.stream`, 死路径 `callSseTokens` 已删
- **ADR-0006**: KnowledgeModel 拆分 — **名字保留**(用户命名裁决), 三协作服务已抽 (spec 015)
- **ADR-0008**: LangGraph 设计根, ArkTS 自建承载(CaptureGraph)— **不要**换框架
- **ADR-0009**: Kit facade **契约先,实装注入**(非 import 禁令)— 实现留在 entry
- **ADR-0010**: `mcp/` 保留 MCP 语义目录, `tools/` 留给 CRUD 工具(已 supersede ADR-0005)
- **ADR-0011**: `skill/` 是小艺预留位, **stub 状态是故意**
- **ADR-0012**: Tool-calling OpenAI 兼容 + ToolRegistry 在 `common/`(不是 entry)— skill IntentRouter 也复用

完整 12 ADR [`docs/adr/index.md`](../adr/index.md)。

---

## 5. 接力前必读(用 Pointer, 不复述)

| 想知道 | 读 |
|---|---|
| 项目现状 / TBD / 已知坑 | [`docs/agents/handoff-2026-09-06.md`](./handoff-2026-09-06.md) |
| 整体进度 (权威) | [`docs/specs/index.md`](../specs/index.md) §"Implementation status" |
| 项目规则 (7 红线 + ArkTS 1.1 + 命名) | [`AGENTS.md`](../../AGENTS.md) + [`docs/style/arkts-1.1.md`](../style/arkts-1.1.md) |
| 项目术语 (Order/KnowledgeUnit/NoteType/...) | [`CONTEXT.md`](../../CONTEXT.md) |
| 通用 agent 术语 (Node/Edge/State/HITL) | [`docs/agents/agent-glossary.md`](./agent-glossary.md) |
| Spec 007 PR3 范围 | [`docs/specs/007-agent-chat-service-decomposition.md`](../specs/007-agent-chat-service-decomposition.md) |
| Spec 013 Kit 范围 | [`docs/specs/013-kit-adoption-boundary.md`](../specs/013-kit-adoption-boundary.md) |
| 工具库存盘点 (F1/F2) | [`docs/architecture/agent-tools-inventory-2026-09-06.md`](../architecture/agent-tools-inventory-2026-09-06.md) |
| 前端审查 (C1/C2/C3/C4/C5/C6) | [`docs/research/frontend-component-audit-2026-09-06.md`](../research/frontend-component-audit-2026-09-06.md) |
| git 工作流 | [`docs/agents/git-flow-lightweight-2026-09-04.md`](./git-flow-lightweight-2026-09-04.md) + [`docs/agents/git-conventions.md`](./git-conventions.md) |
| D2 CaptureGraph 踩坑经验 | [`docs/agents/d2-capturegraph-teaching-2026-09-05.md`](./d2-capturegraph-teaching-2026-09-05.md) §6 (尤其 §6.3 + §6.11) |

---

## 6. Last updated

2026-09-07(本次探查生成;下一 session 接手前 `git pull` 后再读 — spec 007 PR3 可能已合, Kit 实现可能已新增, skill IntentRouter 可能已开)

---

## 7. Workstreams & 边界(2026-09-07, 并行 LLM 适配)

> **为什么需要这一节**: YunCeH 正在并行做**新架构接入 + 大模型流式输出**(基础映射见 [`docs/research/langgraph-mapping-verification-2026-09-06.md`](../research/langgraph-mapping-verification-2026-09-06.md),49 行 LangGraph × 鸿蒙资源核查)。两条流**共享部分基础设施**,不画线会互踩。

### 7.1 双流责任一览

| 流 | 负责人 | 范围 | 节奏 |
|---|---|---|---|
| **Backend 推进流**(本文主体 §1 Step 1-5) | 接手 agent (**你**) | spec 007 PR3 / Kit P0 剩余 / Tool 写路径 / skill IntentRouter / audit C3 | 这次 session 起 |
| **LLM 适配流**(新架构 + 流式输出) | YunCeH | LangGraph 风格新架构(term 改名) + 大模型流式调用 + 鸿蒙 Kit 适配 | 同步推进中 |
| **共享基础设施**(两流都可能动) | 见 §7.3 表格 | 仅限 seam 文件, 需 24h 通知 | — |

### 7.2 YunCeH 流(LLM 适配)—接手 agent 不要碰

> 接手 agent (你):**默认全部不要碰下列 YunCeH 流相关位置**,除非 §7.5 显式声明 Y/N。

| 位置 | 描述 | 状态 |
|---|---|---|
| 整个新架构所在 module/目录 | YunCeH 自定(待补) | ❓ 待 YunCeH 填 §7.2 |
| `common/src/main/ets/llm/LlmClient.ets` | 已有 SSE 路径(`stream:true` + `onDelta` 回调)— 若 YunCeH 加 streaming tool-call, **可能扩展** | ⚠️ 保持 `call(opts)` 现有签名; 若扩展, 走加 overload/options bag,不破坏现有调用方 |
| `common/src/main/ets/llm/LlmGuard.ets` 暴露的 `LlmCaller` seam | ToolLoop + 新流都消费 | ⚠️ 改 seam 签名需双方确认 |
| `agents/src/main/ets/graph/CaptureGraph.ets` | 已 sealed(ADR-0008)— 除非你明确知道新架构也走 CaptureGraph 模式 | ❌ 默认不碰 |

### 7.3 接手 agent 流(§1 Step 1-5)—YunCeH 不要碰

| 位置 | Step | 备注 |
|---|---|---|
| `entry/src/main/ets/services/AgentChatService.ets` + 3 新文件 | Step 1 (spec 007 PR3) | ReplyService 抽取 + facade ≤100 LOC |
| `entry/src/main/ets/kit/BackgroundTaskFacadeImpl.ets` + `FormCardFacadeImpl.ets` (新建) | Step 3 | 复制 ReminderFacadeImpl 模式 |
| `common/src/main/ets/tools/NoteWriteTools.ets` (新建) | Step 2 (gated on F2) | F2 写路径统一后开 |
| `skill/src/main/ets/IntentRouter.ets` (新建) | Step 4 (gated on 队员语义确认) | 7 个 intent action 名 |
| `entry/src/main/ets/pages/Review/ReviewGraphView.ets` 拆 5 文件 | Step 5 (audit C3) | 仅视觉拆分 |

### 7.4 共享 seam — 任何一方变更前 24h 通知另一方

| 文件 / seam | 共享原因 | 协调要求 |
|---|---|---|
| `common/src/main/ets/llm/LlmTypes.ets` | 双方都消费 `ChatMessage` / `LlmCallRequest` / `LlmToolCall` | 加字段双方确认, 别动既有字段语义 |
| `common/src/main/ets/Index.ets` re-export 列表 | 双方都依赖模块入口 | 加 re-export 双方确认, **禁止 `export const { X, Y } from ...`**(arkts-no-destruct-decls 10605074, 血泪) |
| `agents/src/main/ets/agents/` 子代理(除 KnowledgeModel 已拆外) | 双方都可能扩展 | 若你新增, 走 `agents/agents/<newname>.ets` 平行结构, 不改既有 |

### 7.5 边界冲突时的升级路径

1. **小冲突**(字段重名 / 单文件改动): 双方在 PR 描述里挂 `// coordination: <reason>` 注释, 各 PR 合前自己协调
2. **大冲突**(seam 文件 / 公开接口): **暂停合并**, 在 docs/agents/decisions/ 开新 ADR 决议, 走 Git Flow PR 流程
3. **不可调和**(新架构与 CaptureGraph 设计根冲突): 用户裁决, 可能触发 ADR-0008 修订

### 7.6 worktree 隔离(红线 7, 必做)

```
开工前:
  git status        # 确认 working tree 干净
  git log --oneline -3  # 确认 HEAD 正确

并行时(任YunCeH 也用 git worktree add):
  git worktree add ../MindTrace-yc <yc-branch>   # YunCeH
  git worktree add ../MindTrace-me <my-branch>    # 你

禁止:
  - 共用 clone 里互相切分支
  - 把他人未完成改动带进自己 PR(就算 "顺手 fix 一下")
```

---

## 8. Last updated

2026-09-07(本次探查生成;接手前 `git pull` + 读 §7 确认边界;spec 007 PR3 / Kit 实现 / skill IntentRouter 可能已新增, 需重新核实现场)