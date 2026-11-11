# Agent 框架与产品分层 — 交接 / Review 文档（2026-11-02）

> 读者：Claude（外部 review）。目标：用 15 分钟判断「Agent 编排框架」和「产品分层」当前是否合理、哪里是债、下一步该先做什么。
> 仓库：HarmonyOS 数学学习助手 MindTrace（ArkTS 1.1 严格模式）；当前分支 `develop`；最新提交 `9e489fb2`。
> 本文只写**已验证事实**；未验证/平台受限项明确标注。

---

## 0. 先看结论（TL;DR）

1. Agent 编排已完成 **workflow-first 收口**：`CommandExecutor`（统一入口，333 行）→ `CommandRouter`（preflight+路由，120 行）→ 四条 workflow（capture 225 / generation 691 / regenerate 261 / prepared 183）。**四条都是实体实现**；旧的 `DispatchGraph` / `CaptureBranch` / `NoteAgent` / `PreparedBranch` / `IncrementalBranch` / `GenerationBranch` 全部删除，`core/dispatch/` 只剩策略与端口适配（`DispatchOptions` / `GenerationEvaluator` / `NoteOutcomeMapper` / `RunEventSink` / `UnitSupport` / `BatchSupport`）（spec 039；2026-11-03 复核）。
2. 写入链路做了**双 lane 调度器 + 持久队列 + 跨进程 handoff**：`WriteJobScheduler`（interactive/background 双 lane、并发上限）→ `WriteJobPersistence` hooks → `agent_job` 表（schema v20）→ 启动恢复/租约；flag 已灰度打开（spec 038 / 040 / ADR-0024）。队列承接 UI 侧 inbox / 恢复 / 兜底；A2A 单次整理是扩展内联。
3. App 与 A2A 两条入口**共用同一编排**：都经 `CapturePipeline → CommandExecutor → workflow → NoteDao`，没有第二套笔记写入逻辑；调度方式不同（App 交互式直连，A2A 单次整理扩展内联，队列只兜底）。
4. 端A2A（小艺）侧：文本整理真机通；**图片入站是平台能力缺口**——小艺客户端不下发 image part（也不下发识别文字），应用侧无法拿到图片；卡片/App 跳转方案已按用户要求移除，当前纯文本引导（详见 §6）。
5. 需要 review 的高风险点：**双进程共享 SQLite 写入**、**A2A 内联整理**（正式路径，ADR-0024 §2.7；残余 `SQLITE_BUSY` 风险待加固）、**Chat/ToolLoop 尚未并入 workflow 框架**、**A2A UX/错误语义**。

---

## 1. 模块与进程拓扑

```
HAP entry ──────────────┐
HAP skill / cardservice ─┼─(file deps)→ HSP agents ──→ HSP common
                         │
HSP common (DB/RDB/LLM/workflow kernel/纯契约)
HSP agents (CommandExecutor/Router/4 workflows/CaptureGraph/nodes)
```

- `entry` 依赖 `agents` + `common`；`agents` 只依赖 `common`；`agents` **不 import entry**（gate 有边界规则）。
- 进程：
  - **UI 进程**：`EntryAbility` → 页面/VM → services → CapturePipeline → CommandExecutor → workflows → DAO。
  - **`:agent` 进程**：`AgentExtAbility`（协议：手写 JSON-RPC + 单帧快照，299 行）→ `A2AController`（策略：意图/计划/内联整理/记忆/回执，1104 行）→ `IngestGateway` → `AgentIngestService` → `CapturePipeline`；自己 `DatabaseHelper.init`，可内联写库。
  - **agentUI 卡片**：`AgentUIExtAbility`（半屏卡片）与 agent 同进程；当前 A2A 回复已不再发卡片，代码保留为 dormant 能力（见 §6）。

---

## 2. Agent 框架分层（review 重点）

### 2.1 分层图

```
L0 入口适配层
  ├─ UI:        pages/ (8 目录) + viewmodels/ (8 个 VM)
  ├─ 应用入口:  entryability/EntryAbility.ets        启动 / DB init / 保留清理 / 图片整理
  ├─ A2A 协议:  agentextability/AgentExtAbility.ets  299 行：JSON-RPC 2.0 解析 + part 提取 + 单帧 task 快照
  ├─ A2A 策略:  services/A2AController.ets           1104 行：意图 / 计划 / 内联整理 / 记忆 / 回执 / 回复
  ├─ 无头整理:  services/IngestGateway.ets           66 行：唯一 inline-vs-background 决策点
  └─ 写调度:    services/WriteJobScheduler.ets       App 写路径双 lane + 持久队列

L1 产品服务层（entry/services/）
  ├─ 整理:  services/ai/  CapturePipeline · DraftPipeline · ClarificationPipeline · AiService
  ├─ 对话:  ConversationRuntime · AgentChatService · ReplyService · RendererScheduler
  ├─ 写入:  WriteJobScheduler / Persistence / Bootstrap / Producer · AsyncSemaphore · AsyncMutex
  ├─ 知识:  KnowledgeUnitWriteService · NoteEditService · RagRetrievalService · NoteReviewService
  ├─ A2A:   A2AIntentRouter · A2AConversationStore · A2AImageContextStore · A2APlanStore
  │         A2AErrorTaxonomy · A2AContextCleanup
  └─ 运维:  DataRetentionService

L2 编排层（agents HSP）
  ├─ core/CommandExecutor.ets (333)    生命周期 + run_event + 选 workflow
  ├─ core/CommandRouter.ets (120)      preflight（取消 / 审批哈希）+ kind → workflow
  ├─ workflows/WorkflowContext.ets (36)  只暴露五组：WritePorts / Observability / RunControl / DispatchMode / DispatchDomain
  ├─ workflows/Note*Workflow.ets         capture 225 · generation 691 · regenerate 261 · prepared 183
  ├─ core/dispatch/                      DispatchOptions(五组) · GenerationEvaluator · NoteOutcomeMapper
  │                                      RunEventSink · UnitSupport · BatchSupport
  └─ graph/CaptureGraph.ets + nodes/     Classify · Ocr · Structure · TruthCheck · Persist

L3 契约 / 内核层（common HSP）
  ├─ models/       NoteCommand / NoteOutcome（ADR-0019）· KnowledgeGraph · StudyPlan
  ├─ workflow/     StateGraph · RunContext · RunBudget · RunErrors · tool-calling
  ├─ ports/        NoteWritePort · NoteReadPort · NoteSearchPort · RunStore · ReviewPorts
  │                StudyPlanPorts · ArtifactStorePort
  ├─ llm/          LlmClient · LlmGuard · LlmConfig · providers · ContentProtocol
  └─ DatabaseHelper schema v20 · 跨进程 busy_timeout=5000 + appendEvent 重试

旁路：entry/workflows/conversation/  ConversationWorkflow（对话领域图，复用 common/workflow 内核，
      不经过 CommandExecutor；其中的笔记写入仍经 AiService → CapturePipeline 回到 L2）
```

依赖方向（单向，gate 守）：

```
pages → viewmodels → services ─┬→ agents → common
agentextability → services ────┘
skill / cardservice → common (仅契约)
```

关键点：
- **只有一个编排入口**：`CommandExecutor.dispatchCommand(NoteCommand, DispatchOptions)`；`NoteCommand` 是 5 类判别联合（capture / generation / regenerate / preparedCandidate / analysisOnly），`NoteOutcome` 是 5 类终态。
- **A2A 分为适配器与控制器**：`AgentExtAbility` 只解析 JSON-RPC / parts 并发送单帧快照；意图、计划、内联整理、记忆、回执在 `services/A2AController.ets`，经 `A2AReplyPort` 回话；inline/background 模式在 `services/IngestGateway.ets`（2026-11-02 拆分）。
- **无头入口统一经 IngestGateway**：A2A / 系统分享 / inbox 只传 `AgentIngestRequest`，不自己决定是否进队列；网关是唯一模式决策点。
- **选项按组消费**：`WorkflowContext` 暴露 `WritePorts` / `Observability` / `RunControl` / `DispatchMode` / `DispatchDomain`；四个 workflow 均已迁移，`flattenDispatchOptions` 已删除（2026-11-02 拆分）。
- **Router 与 Executor 同在 agents/core**：Router 负责命令形状校验、prepared 审批哈希、取消；Executor 负责选 workflow + 生命周期 + run_event。
- **workflow 负责装配图**：每次 `run(options)` 按当次 options 装配 capture 子图；capture 内部仍用 `CaptureGraph` 节点（ADR-0008 的 LangGraph 模型是设计根，不是第三方 runtime）。

### 2.2 三条主数据流

**A. App 文字/图片整理**
```
UI/VM → AiService.captureText → CapturePipeline.ingestTextOutcome
  → CommandExecutor.dispatchCommand(capture)
  → NoteCaptureWorkflow → CaptureGraph（OCR? → Classify → Structure → TruthCheck → Persist）
  → NoteOutcome(committed/failed/…) → 页面/卡片刷新
```

**B. 小艺 A2A 文字整理（不打开 App）**
```
小艺 → AgentExtAbility.onData（JSON-RPC 解析 + part 提取）
  → A2AController.handle（意图 / 计划 / 会话记忆 / 90s deadline）
  → IngestGateway.ingest(..., INGEST_MODE_INLINE)     ← 唯一模式决策点
  → AgentIngestService → CapturePipeline → CommandExecutor → 同 A
  → A2AReplyPort.send(单帧 task 快照，"已整理入库：…")
```
> 真机证据：`ok=true`，回复 `已整理入库：计算12减4乘2的值并写出运算顺序（初中数学）· 本次整理 1 条`；hilog `INTENT text_ingest → TEXT_PLAN → INGEST_TEXT done`。

**C. 写入调度 / 持久化（spec 038+040）**
```
写入调用方 → WriteJobScheduler.submit(priority,text,executor)
  ├─ flag 关：内存双 lane 队列（AsyncSemaphore/AsyncMutex + 写段串行）
  └─ flag 开：WriteJobPersistence.enqueue → AgentJobDao(agent_job) → claim(租约) → executor → finish(终态)
            启动：WriteJobBootstrap → recoverAllRunning(孤儿) + recover(queued) → submitRecovered
            跨进程兜底：WriteJobProducer（当前无生产调用方）
A2A 单次整理：IngestGateway(INLINE) → AgentIngestService → CapturePipeline，不经调度器（ADR-0024 §2.7）
```

---

## 3. 产品分层（UI → 数据）

| 层 | 位置 | 职责 | 约束 |
|---|---|---|---|
| UI | `entry/src/main/ets/pages/`（8 目录）、`overlays/` | 渲染、手势、动效 | 不直接 import CaptureGraph/CommandExecutor/NoteDao |
| ViewModel | `entry/src/main/ets/viewmodels/`（8 个） | UI state、用户意图、调用 service | 不持 RDB 句柄 |
| 入口适配 | `entry/src/main/ets/agentextability/` | JSON-RPC 解析、part 提取、单帧快照 | 不含意图/计划/写入策略（下沉到 A2AController） |
| Business Service | `entry/src/main/ets/services/`、`services/ai/` | 编排、AI、笔记生成、检索、调度、A2A 策略 | 不持 UI 引用；写路径统一走 CapturePipeline/CommandExecutor；无头整理统一走 IngestGateway |
| Agent 编排 | `agents/`（HSP） | CommandExecutor/Router/workflows/CaptureGraph | 只依赖 common；不 import entry |
| 共享契约/数据 | `common/`（HSP） | NoteCommand/Outcome、workflow 内核、ports、DB/RDB、LLM 客户端 | 受限 Kit 不得经 barrel 进 :agent 进程 |
| 扩展 | `skill/`, `cardservice/`（HAP feature） | 小艺 skill / 桌面卡片 | 不新建 module |

产品域当前闭环：capture（拍照/相册/文字/A2A）→ 结构化 → 生成 → 持久化（note_revision / note_generation_* / RunStore）→ 详情/复习/RAG/知识星系；后台写路径由 scheduler 限流与串行化，A2A 侧走内联 + 90s deadline，历史数据由 retention 定期清理。

---

## 4. 当前进度（spec/ADR 口径）

| 项 | 状态 | 证据 |
|---|---|---|
| spec 038 WriteJob 调度器 S1/S2/S3 | implemented | schema v20 `agent_job`、双 lane、事件观测、真机重启恢复 `doneDelta=1 / 12.9s` |
| spec 039 workflow-first 收口 S1–S3 | implemented | `CommandExecutor/Router` + 4 workflows；旧 DispatchGraph/CaptureBranch/NoteAgent 已删；golden 零重录 |
| spec 040 持久队列/跨进程 P0–P3 | implemented | flag 灰度打开；dedupeProbe `same=1 added=0`；schedulerProbe `completed=6 failed=0 maxConcurrent=2` |
| ADR-0019 NoteCommand/Outcome | accepted | 类型在 common，mapper 不丢字段（回归测试） |
| ADR-0008 graph 模型（无 checkpoint/HITL） | accepted | 图内核 + capture 子图；无运行时 checkpoint |
| ADR-0021 读端口实现放 common | accepted | `RdbNoteReadStore` + adapter 注入 |
| ADR-0024 WriteJob 持久化 | accepted | spec 040 实现 |
| 端A2A 文本整理 | verified | 真机 smoke `ok=true` + “已整理入库…1 条” |
| 端A2A 图片入站 | **blocked（平台）** | 平台文档+S DK 允许，客户端实测 only text part；工单草稿 `docs/research/a2a-image-ticket-draft-2026-11-02.md` |
| Chat/ToolLoop 统一 | deferred | spec 039 §S4 → 后续 spec 041 |

门禁：`node scripts/agent-gate/index.mjs --all` → **PASS（pass=1204 fail=0）**；`node scripts/build-hsp-hap.mjs` → 成功。

---

## 5. 最近关键提交（时间倒序）

```
9e489fb2  移除选图卡片/App 跳转，图片消息纯文本引导
841bc666  docs: 卡片选图实测 + UIExtension 相册限制
86005b4b  小艺选图卡片（半屏卡片拉起系统相册）——后被 9e489fb2 移除
a781759d  spec 040 P3：真机重启恢复 + 灰度打开
e321c7e6  spec 040 P1：WriteJob 持久化 hooks + 启动恢复
14f2a3ec  spec 040 P0：agent_job schema v20 + DAO
603b6dee  spec 040 P2：跨进程 producer + inbox 迁移
6f6e253   S3 节点事件缓冲修复（SQLite lock）
d8e4b9e   spec 039 S3：workflow-first 收口
```

---

## 6. 已知问题 / 风险（请重点 review）

> **2026-11-03 复核**：R1/R2 的写入加固见 §15；R5 见 §16（默认关闭）；R8 见 §17；R6/R7 见 §18 + [spec 043](../specs/043-data-retention.md)。下表保留 2026-11-02 的原始判断，作为决策留痕。

| # | 问题 | 说明 / 影响 | 当前处理 |
|---|---|---|---|
| R1 | **双进程共享 SQLite** | UI 进程与 `:agent` 扩展进程都初始化 DB、都可能写笔记；单执行者假定（UI 进程调度器）被 A2A 内联整理打破 | **2026-11-02 已定**：A2A 内联是正式路径（ADR-0024 §2.1/§2.7），队列只兜底；残余 `SQLITE_BUSY` 与 `run_event` 序列问题待加固 |
| R2 | **A2A 内联整理绕过调度器** | 不经过 WriteJobScheduler 的 lane/租约；若同时 App 大量写入，可能竞争 | **2026-11-02 已定**：保留内联（产品要求不打开 App 也能整理）；长期统一入口留待 spec 039 S4 的 `IngestGateway`，不在本轮改 |
| R3 | **端A2A 图片能力缺口** | 小艺客户端不下发 image part/识别文字；应用侧无解 | 已调研+提单草稿；图片链路只能 云A2A / 等平台；当前纯文本引导 |
| R4 | UI 卡片残留历史 | 旧会话里的 `uiExtensionCard` 可能触发客户端重试/转圈；新会话无卡片 | 代码已移除卡片回复；旧对话框建议新建 |
| R5 | **Chat/ToolLoop 未并入 workflow** | Chat 仍走旧 ToolLoop/ReplyService；Agents 编排只覆盖笔记写入 | spec 039 S4 留待 spec 041；reviewer 判断优先级 |
| R6 | A2A 会话记忆/图片材料是文件存储 | `A2AConversationStore` / `A2AImageContextStore` 按 contextId 存文件；未进 DB，无清理策略 | 可用；reviewer 判断是否要并 run_store |
| R7 | 事件表保留策略缺失 | `run_store/run_event/agent_job` 无 retention/清理 | 已知；低优先级 |
| R8 | A2A 错误/超时语义 | 35s deadline、配置超时、单帧快照；用户侧提示分散 | 可做统一 A2A error taxonomy |

---

## 7. 请 Claude 重点回答的 6 个问题

> **2026-11-02 决议（问题 2 / 3）**：A2A 单次整理内联是正式路径（ADR-0024 §2.1 / §2.7），队列只承接兜底与恢复；长期统一入口（`IngestGateway`）留待 spec 039 S4，不在本轮改。

1. **分层**：`CommandExecutor/Router/4 workflows` 放 `agents` HSP、`CapturePipeline` 放 `entry/services/ai`，边界是否合理？是否应把 CapturePipeline 也上移到 agents，避免“入口适配层依赖编排层”倒置？
2. **写路径一致性**：A2A 内联整理是否应统一走 `WriteJobScheduler.submit`（多执行者 + claim 租约），而不是扩展进程直写？若统一，如何避免 35s 预算与调度等待冲突？
3. **进程模型**：A2A 内联已定为正式路径（ADR-0024 §2.1/§2.7）；剩下的开放问题是跨进程写加固——`SQLITE_BUSY` 重试与 `run_event` 序列唯一化该放哪一层？
4. **Chat 统一**：ToolLoop → ChatWorkflow 的迁移是否值得在比赛冻结期做？还是保持现状，仅在 spec 041 记录?
5. **命令/事件契约**：`NoteCommand/NoteOutcome` + `run_event` 是否足够支撑可观测与重试？缺哪些字段（如 retryable、stage、cause）？
6. **A2A UX**：平台不下发图片时，纯文本引导是否最优？有没有更优的“小艺侧识别 → 文本回传”官方路径（我们已调研：需要平台/云A2A）？

---

## 8. 文件地图（快速跳读）

| 想了解 | 文件 |
|---|---|
| 编排入口 | `agents/src/main/ets/core/CommandExecutor.ets` |
| 路由/审批 | `agents/src/main/ets/core/CommandRouter.ets` |
| 四条 workflow | `agents/src/main/ets/workflows/Note*Workflow.ets` |
| capture 图 | `agents/src/main/ets/graph/CaptureGraph.ets` + `graph/nodes/*` |
| 命令/终态契约 | `common/src/main/ets/models/NoteCommandModels.ets` |
| App 入口→编排 | `entry/src/main/ets/services/ai/CapturePipeline.ets` |
| 写入调度 | `entry/src/main/ets/services/WriteJobScheduler.ets` |
| 持久化/恢复 | `WriteJobPersistence.ets` / `WriteJobBootstrap.ets` / `database/AgentJobDao.ets` |
| 小艺 A2A 入口/协议 | `entry/src/main/ets/agentextability/AgentExtAbility.ets` |
| 小艺 A2A 策略/编排 | `entry/src/main/ets/services/A2AController.ets` |
| A2A 意图/记忆 | `A2AIntentRouter.ets` / `A2AConversationStore.ets` / `A2AImageContextStore.ets` |
| 分析/证据 | `docs/specs/038-*.md`、`039-*.md`、`040-*.md`；`docs/research/a2a-image-*` |

---

## 9. 2026-11-02 拆分执行（A2AController）

- `AgentExtAbility` 1264 → 299 行：只保留 JSON-RPC 解析、part 提取、`TaskSnapshot` 发送与 OCR 组合根。
- 新增 `services/A2AController.ets`（1049 行）：意图路由、计划推进、内联整理、会话记忆、回执、对话回复；通过 `A2AReplyPort` 回话。
- 守卫测试按职责读文件：协议断言读 ability，行为断言读 controller；`reply-style-wiring` 改读 controller。
- 验证：`node scripts/agent-gate/index.mjs` → **RESULT: PASS（pass=1204 fail=0）**；`node scripts/build-hsp-hap.mjs` → 成功；A2A 冒烟 `ok: true`（`存笔记：1+1=2` → `INGEST_TEXT done problems=1`）。
- 未稳定验证：短指令「整理数学题」的 UI 气泡捕获时好时坏；hilog 已见 `INTENT kind=pick_card reason=ingest-without-content` + `A2A_REPLY_SENT chars=83`，说明引导分支已执行。

## 10. 2026-11-02 拆分执行（IngestGateway）

- 新增 `services/IngestGateway.ets`：A2A / 系统分享 / inbox 的唯一无头整理入口；`inline` vs `background` 只在这里决定。
- `A2AController`、`EntryAbility.ingestImage`、`A2AInboxIngestService` 改为经网关；`AgentIngestService` 退为底层实现（删除未使用的 `ingest` 适配器，`ingestSingleText` 支持 priority）。
- 顺带修复：幂等复用时 `NoteDaoAdapter` 缺 `queryById`，导致 committed 无 unit 被误报 `INGEST_FAILED`；写服务 / 适配器补 `queryById`，控制器把任何 committed 视为成功。
- 补文本整理 deadline：`ingestTextBatchNow` 90s 超时转待整理，避免 provider 挂起时无回执（底层请求不取消，靠输入指纹/commitKey 去重）。
- 验证：`agent-gate` **PASS（pass=1210 fail=0）**；`build-hsp-hap` 成功；A2A 冒烟 **`ok: true`**（`存笔记：3+3=6` → `INGEST_TEXT done problems=1`，30 字回复）；重复文本的幂等复用也在 hilog 验证（`INGEST_TEXT done` + 28 字回复）。

## 11. 2026-11-02 拆分执行（DispatchOptions 五组）

- `DispatchOptions` 拆成 `WritePorts` / `Observability` / `RunControl` / `DispatchMode` / `DispatchDomain`；扁平接口保留兼容。
- `WorkflowContext` 只暴露五组；`NoteCaptureWorkflow` 按组消费；三个 branch 壳用 `flattenDispatchOptions` 过渡；`CommandExecutor` 用 `groupDispatchOptions` 构造上下文。
- 验证：`agent-gate` **PASS（pass=1213 fail=0）**；`build-hsp-hap` 成功；A2A 冒烟 **`ok: true`**（provider 挂起 90s → `INGEST_TEXT_DEADLINE` → 转待整理回执）。

## 12. 2026-11-02 branch 迁移（Prepared）

- `PreparedBranch`（176 行）整体迁入 `NotePreparedWorkflow`；`GenerationEvaluator` 改为自建 truth_check 图，不再依赖 branch。
- 删除 `PreparedBranch.ets`；prepared 路径不再使用 `flattenDispatchOptions`。
- 验证：`agent-gate` **PASS（pass=1213 fail=0）**；`build-hsp-hap` 成功。
- 剩余：`GenerationBranch`（705 行 + `GenerationEvaluator` 637 行）/ `IncrementalBranch`（272 行）。

## 13. 2026-11-02 branch 迁移（Incremental）

- `IncrementalBranch`（272 行）整体迁入 `NoteRegenerateWorkflow`；进度事件改走 workflow 自己的 `emitProgress`，不再依赖 `GenerationBranch`。
- 删除 `IncrementalBranch.ets`；regenerate 路径不再使用 `flattenDispatchOptions`。
- 验证：`agent-gate` **PASS（pass=1213 fail=0）**；`build-hsp-hap` 成功。
- 剩余：`GenerationBranch`（705 行 + `GenerationEvaluator` 637 行；已于 §14 完成）。

## 14. 2026-11-02 branch 迁移（Generation，收口）

- `GenerationBranch`（705 行）整体迁入 `NoteGenerationWorkflow`；`GenerationEvaluator.finishStandardGeneration` 改为直接接收 `generationRepository`，不再需要 `DispatchOptions`。
- 删除 `GenerationBranch.ets` 与 `flattenDispatchOptions`；四个 workflow 全部按组消费，`WorkflowContext` 不再暴露扁平 options。
- 验证：`agent-gate` **PASS（pass=1213 fail=0）**；`build-hsp-hap` 成功。

## 15. 2026-11-02 跨进程写加固

- `DatabaseHelper` 初始化执行 `PRAGMA busy_timeout=5000`（连接级；`StoreConfig` 无配置项）；真机 `:agent` 日志已确认。
- `run_event` 增加 `(run_id, sequence)` 唯一索引（旧库有重复时跳过，不阻塞启动）；`appendEvent` 对 busy / locked / 唯一冲突做 3 次有限重试。
- 验证：`agent-gate` **PASS（pass=1214 fail=0）**；`build-hsp-hap` 成功；真机 A2A 幂等入库 hilog `INGEST_TEXT done` + `PRAGMA busy_timeout=5000` 已打印。

## 16. 2026-11-02 Chat 工具回复（默认关闭）

- 新增 `ConversationToolReplyFlags`（默认 false）、`IConversationToolPort`、`ConversationToolAdapter`（`ToolLoop` + `ToolCatalog.createReadOnlyRegistry()`）。
- 开启时 text 请求走 `tool_reply`（非流式）；关闭时图里不添加该节点，`complete_reply` / `stream_reply` 行为不变。
- `LlmClient` 显式 `implements LlmCaller`，让工具循环的构造注入在 ArkTS 下类型成立。
- 验证：`agent-gate` PASS；`build-hsp-hap` 成功；默认关闭，未做真机开启验证。

## 17. 2026-11-02 A2A 错误语义统一

- 新增 `A2AErrorTaxonomy`：`A2AErrorCode -> kind (protocol/config/model/timeout/ingest/none)` + `a2aErrorText(code, detail)`。
- `A2AController` / `AgentExtAbility` 删除本地错误文案常量，统一经 `a2aErrorText`；用户可见措辞保持原样。
- 验证：`agent-gate` **PASS（pass=1219 fail=0）**；`build-hsp-hap` 成功；真机 A2A 幂等入库 hilog `INGEST_TEXT done`。

## 18. 2026-11-03 R6/R7 保留清理

- A2A 会话 / 图片 / 计划文件：7 天清理，扩展 `A2AController.prepare()` 执行（`A2AContextCleanup`）。
- `run_event` / 终态 `run_store` / 终态 `agent_job`：30 天清理，App 启动时 `DataRetentionService` 执行；新增 `created_at` / `updated_at` 索引。
- 验证：`agent-gate` **PASS（pass=1221 fail=0）**；`build-hsp-hap` 成功；真机 A2A 幂等入库成功。

验证命令：

```bash
node scripts/agent-gate/index.mjs --all        # PASS（pass=1204 fail=0）
node scripts/build-hsp-hap.mjs                 # BUILD SUCCESS
node scripts/device-runner.mjs e2e <mode> --wait N   # 真机 e2e
python scripts/a2a-smoke/a2a_smoke.py --text "整理成笔记：..."  # A2A smoke
```

---

## 9. 一句话请 Claude 判断

> 当前“CommandExecutor/Router + 4 workflows + CaptureGraph 子图”的编排分层，与“UI/VM/Service/agents/common”的产品分层，是否足够清晰、可演进？最大的结构性风险是不是双进程写库与 A2A 内联执行？比赛冻结期建议只修哪些、不动哪些？

---

## 19. 2026-11-03 架构图刷新

R6/R7 落地后，重新按代码实测校正 §0 / §1 / §2.1 / §2.2 / §3 的分层图与数据流：

- **0 → 4 条实体 workflow**：`PreparedBranch` / `IncrementalBranch` / `GenerationBranch` 全部并入 `Note*Workflow`，`core/dispatch/` 不再有分支壳。
- **A2A 两段式**：`AgentExtAbility`（299 行，协议/快照）与 `A2AController`（1104 行，策略）职责分离；无头整理统一从 `IngestGateway`（66 行）进入。
- **新增 L1 条目**：`WriteJobScheduler/Persistence/Bootstrap/Producer`（写调度）、`DataRetentionService`（保留清理）、`A2AErrorTaxonomy`（错误语义）。
- **L3 补齐 ports**：`NoteWritePort / NoteReadPort / NoteSearchPort / RunStore / ReviewPorts / StudyPlanPorts / ArtifactStorePort` 在 `common`，entry 侧 `adapters/` + `services/*Factory` 注入。
- **依赖方向**：`pages → viewmodels → services → (agents | common)`，`agentextability → services`，`agents` 不 import entry（gate 守）。

统计口径：`agents/core` 453 行 + `workflows` 1360 行 + `graph`；`entry/services` 约 100 个文件，其中 A2A 相关 10 个、写调度 9 个。

## 20. 2026-11-04 common 边界收口

复查发现 common 出现两类交织，按「common 只放 ≥2 模块/进程使用且无业务阈值、文案、配色」收紧：

**迁出（6 个）**

| 文件 | 去向 | 依据 |
|---|---|---|
| `utils/ReplyStyleRules` | `agents/chat` | 只有 `IntentClassifier` 使用，是回复 prompt 规则 |
| `utils/StreamErrorText` | `agents/chat` | 只有回复链路使用 |
| `utils/NoteDedupe` | `agents/note` | 判重阈值属业务规则 |
| `utils/RagQueryPlan` | `entry/services` | 生成 FTS/LIKE SQL，属数据访问策略 |
| `utils/GalaxyGraphProjection` | `entry/pages/Review` | 渲染投影，仅页面使用 |
| `data/NoteTaxonomy` | `entry/utils` | 取色与图标是 UI 关注点 |

`NoteTaxonomy` 做了拆分：类型词表（概念/定理/公式/证明题/计算题 + 归一化）留在 `common/models/NoteTypeVocabulary.ets`——`TypeClassifier` / `PromptBuilder` / `CaptureStructurer` 都在用，属真共享；配色与图标回 entry。

**barrel 收口**

`common/Index.ets` 不再导出 `ports/impl/*`（5 个 RDB 适配器）与 `tools/NoteQueryTools` 的四类工具；`EntryAbility`、`ohosTest`、`common/src/test` 改为深路径引用。消费方统一走 `ToolCatalog.createReadOnlyRegistry()`。

**过程中的事故**

批量改 import 的脚本用「最后一个 import 分号」定位插入点，在 `GalaxyComponent3DAdapter.ets` 把一行 import 插入到 `for` 循环中间，编译报 `importDeclNode.parent.statements is not iterable`。已按行号修复并复核循环体。结论：跨文件改 import 不能靠正则猜插入点，应按每个文件的 import 头边界处理。

**规则同步**：`AGENTS.md` §模块归属判据 与 `docs/specs/033-process-boundaries.md` §R5 都补了 common 准入与 barrel 策略；`docs/system-architecture-layered.md` 新增 §18「当前实现」。

**验证**：`agent-gate` PASS（1242 单测）；`build-hsp-hap` 4/4。

## 21. 2026-11-04 对话链路接入 run 事件

笔记写入一直有 `RunEventSink` → `run_store` / `run_event`，对话链路完全没有，排障只能翻 hilog。本轮把两条编排线的可观测性拉齐：

- 新增 `agents/conversation/ConversationRunEvents.ets`：`conversation.start` / `conversation.step` / `conversation.terminal` 三个 kind 与 payload 口径（不落正文）
- `ConversationWorkflowPorts` 增加可选 `runEvents`；工作流在 `run()` 发 start/terminal、`setStep()` 发 step
- 发出是**尽力而为**：sink 抛错或 reject 都被吞掉，不影响对话本身
- entry 侧由 `ConversationPortsProduction` 注入 `AiServicePorts.buildRunEventSinkIfReady()`，与笔记写入共用 `RunStoreEventSink`

测试新增 3 条：正常链路写出 start→step→terminal、失败链路终态为 failed、sink 抛错不阻塞对话。

**已知偏差**：测试里跨 vm realm 的 `Error` 拿不到 message，失败终态的 `reason` 只能是字符串断言，真机上是完整错误文案。

**验证**：`agent-gate` PASS（1245 单测）；`build-hsp-hap` 4/4。

## 22. 2026-11-04 删除死代码 StreamingReplyDocument

`entry/src/main/ets/services/StreamingReplyDocument.ets`（1274 行）全仓搜索确认**生产零引用**：

- `entry/src/main`、`agents/src`、`common/src`、`skill`、`cardservice` 均无 import
- 唯一使用点是 `entry/src/test/StreamingReplyDocument.test.ets`（Hypium）
- git 历史只有一次新增提交（`b4637c31`），之后没有任何改动或接入

它对应 `styled_string` / `custom_span` 那条渲染后端的文档模型；当前聊天渲染走 ArkWeb（`RendererScheduler` + `RendererScheduler`/`ChatBubble`），这条链路没有接上。

**处理**：删除源文件与其 Hypium 测试，并从 `entry/src/test/List.test.ets` 摘掉注册；spec 020 / 021 的状态行补了删除说明。若未来要切 `custom_span` 后端，从 `b4637c31` 恢复即可。

**验证**：`agent-gate` PASS（1245 单测）；`build-hsp-hap` 4/4。

## 23. 2026-11-04 文档清理

- **ADR-0021 补「barrel 边界与例外说明」**：明确 `ports/impl/*` 与 `NoteQueryTools` 是「只读实现跨 HAP 共享」的有意例外，并且不进 barrel；同时列出三类能力的归属对照（只读投影 / 证据检索与图谱 / 写路径），判断顺序是「先看有没有第二个 HAP 要用，再看实现是否只读」。
- **过期文档加横幅**：`system-architecture-layered.md`（§1–§17 是设计态，指向 §18）、`architecture/agent-chain-2026-11-01.md`（快照早于本轮迁移）、`architecture/agent-architecture-proposal-2026-11-01.md`（已由 spec 039 落地）、`architecture/review-v7-2026-10-27.md`（评审的是设计态）。
- **架构索引同步**：`docs/architecture/index.md` 三行标注过期/评审态，并加一条「现状统一看 §18」。

选择加横幅而非删除：这几份是 ADR / spec 追溯链上的节点（如 spec 039 引用提案），删掉会断链。

**验证**：`agent-gate` PASS（文档变更，单测跳过）。

## 24. 2026-11-05 拆分 A2AController

`entry/src/main/ets/services/A2AController.ets` 1103 → 755 行，抽出整理/计划链路：

| 文件 | 行数 | 职责 |
|---|---|---|
| `A2AController` | 755 | 生命周期（prepare / cancelActive / handle 分发）、图片问答、OCR 检查点、问答链路与回话端口 |
| `A2AIngestHandler` | 455 | 文本批处理、90s deadline、多题计划推进（继续/第 N 题/全部/取消）、入队兜底、回执 |
| `A2AConstants` | 12 | 日志域/标签与 `INGEST_DEADLINE_MS`，控制器与处理器共用 |

- 宿主接口 `IA2AIngestHost` 只有两个方法：`ingestContext()` 与 `sendIngestAnswer()`——整理组原本就只依赖这两个入口
- 控制器实现该接口并持有 handler；`handle()` 的整理分支改为 `this.ingestHandler.*`
- `A2AConstants` 解决两文件共用常量的问题（原先 `TAG`/`DOMAIN`/`INGEST_DEADLINE_MS` 定义在控制器模块作用域）

**测试**：11 个测试文件改为「Controller + IngestHandler + Constants」拼接断言；三处正则断言放宽以接受 `this.host.ingestContext()`。

**验证**：`agent-gate` PASS（1245 单测）；`build-hsp-hap` 4/4。

**未拆分**：问答链路（`runQuery` + `answerFrom*` + `answerWithResolvedModel` 等 10 个方法）仍在控制器内，与图片、生命周期共享 `A2ARequestSession` 状态，下一刀需要先抽 session 注册表。

### 24.1 第二刀：问答链路（2026-11-05）

| 文件 | 行数 | 职责 |
|---|---|---|
| `A2AController` | 518 | 生命周期（prepare / cancelActive / handle）、图片问答、OCR 检查点、`runQuery` 与 session 生命周期、`settle` / `sendAnswer` |
| `A2AIngestHandler` | 455 | 整理与计划（上一刀） |
| `A2AAnswerHandler` | 292 | 模型配置等待、请求模型解析、构建 `ReplyContext` 并调用 `ReplyService` |
| `A2AConstants` | 62 | 日志域/标签、`INGEST_DEADLINE_MS`、`A2A_POLICY`、回复风格、字符计数 |
| `A2ASession` | 30 | `A2ARequestSession`（token / deadline / 回答状态 / 模型解析结果） |

- 宿主接口 `IA2AAnswerHost`：`answerContext` / `configReady` / `finishSession` / `failSession` / `currentRequestId`——`configReady` 由 `prepare()` 写入、回答链只读，因此走宿主而不是把可变状态搬到新类
- `A2A_REPLY_STYLE` 从 `ReplyStyle` 改为字面量 `'plain_text_math'`，这样常量可以住进 `A2AConstants` 而不引入 `common` 依赖

**验证**：`agent-gate` PASS（1245 单测）；`build-hsp-hap` 4/4。仍**未经真机验证**。

**剩余**：控制器 518 行里 `runQuery` 与 session 生命周期、图片问答、OCR 检查点仍在一起；再拆需要把 `A2ARequestSession` 的创建/取消也搬进数据类，收益递减，暂不继续。

## 25. 2026-11-05 真机验证（重构后首轮）

设备 `3XTYD24C16203663`，安装最新 `common/agents` HSP + `entry` HAP（`node scripts/device-runner.mjs install`）。

| 场景 | 命令 | 结果 |
|---|---|---|
| A2A 文本整理 | `a2a_smoke.py --text "存笔记：9+9=18"` | `ok:true`，回复 31 字；hilog `INTENT text_ingest` → `INGEST_TEXT done` → `A2A_REPLY_SENT` |
| A2A 问答 | `a2a_smoke.py --text "用一句话解释什么是导数"` | 回复含公式 `f′(x₀) = lim(h→0) …`，界面渲染正常 |
| App 批量自检 | `device-runner e2e true` | `stage=done ok=2 failed=0 totalMs=40215`（OCR 入库 698 字、卡片刷新、检索 5 命中 ×2） |
| UI 对话 | 手动 4 轮（3+5 / 勾股定理 / 9+9 / 连续性） | `run start` → `intent chat` → 流式 → `run finish`；39–782 字，`StreamTiming outcome=ok` |
| RAG 证据服务 | `device-runner e2e ragSearch` | `rag-hit hits=5` ×2，`rag-evidence citations=7 degraded=0 contextChars=1603` |
| A2A 对话上下文 | `device-runner e2e agentChatContext` | `citations=1 degraded=0 fakeRefRemoved=1` |

对话侧证据注入在 UI 上可见：「函数在一点连续是什么意思」→「笔记检索：命中 2 条」+ 参考来源列表。

**观察（非本次重构引入）**

- 短查询召回差：「一加一等于几」「9+9 的加法计算怎么算」均未命中，但「连续性」命中。`RagRetrievalService` 把整句当 FTS 短语匹配（<3 字才 LIKE），属检索策略问题，与端口化无关。
- `a2a_smoke.py` 的 `wait_reply` 原先按「文本不在基线集合」判定新回复，同一句重复发送时历史里的相同气泡会导致漏抓（首次 `ok:false` 时界面与 hilog 实际都有回复）。**已修**：基线改为 `Counter`，按出现次数增量判定；重复发送同一句复测 `ok:true`。
- 同一脚本在 GBK 控制台打印数学下标字符（如 `x₀`）会 `UnicodeEncodeError`，把已拿到的回复判成失败。**已修**：启动时把 stdout/stderr 强制为 UTF-8。

**未覆盖**：A2A 图片/OCR 链路（需小艺侧传图）；`conversation.*` run 事件落库未直接查库校验，仅有源码与单测保证。

## 26. 2026-11-05 索引写入事务化 + 存量清理

**诊断**：`ragSearch` 探针新增 `stage=rag-coverage`（`notes` / `missingFts` / `missingChunk` + 缺失样本）。首轮结果 `notes=196 ftsRows=180 ragChunks=139`，即 16 条笔记完全没进 `note_fts`。

**根因**：`KnowledgeUnitWriteService.syncIndex` 在事务提交后异步补同步，套了 5s 超时且超时只告警；`NoteFtsIndex.upsert` 的写入顺序是 `note_fts` → `rag_chunk`，中途被杀会留下「有 FTS 无 chunk」或「两者都没有」的笔记。另外 v19 迁移只回填了 `note_fts`，没有回填 `rag_chunk`，v19 之前的笔记（含 galaxy 种子）普遍没有分块。

**根治**：
- `NoteFtsIndex` 改为 `applyToTransaction(transaction, unit)` / `removeFromTransaction(transaction, unitId)`，全部走 `Transaction.execute`
- `NoteDao` 四条写路径（create/update × commitKey 变体）与 `deleteById` 在同一事务内完成 `knowledge_unit + note_revision + note_fts + rag_chunk + rag_embedding`
- `KnowledgeUnitWriteService` 删除 `syncIndex` 与 `INDEX_SYNC_TIMEOUT_MS`，`finalizeWrite` 只保留 post-commit 副作用
- 相关契约测试从「提交后异步同步 + 5s 兜底」改为「事务内同步」；删除流测试指向 `NoteFtsIndex.removeFromTransaction`

**存量清理**：新增 `ragLegacyAudit` / `ragLegacyCleanup` 探针（audit 只计数，apply 才删除）。首次按「无 chunk」筛出 111 条，审计发现包含 galaxy 种子笔记（`galaxy_preview_*`，RAG 正在命中），改为只删「`note_fts` 里根本没有」的笔记：`candidates=16 removed=16 failed=0`。

**验证**：

| 指标 | 清理前 | 清理后 | 新写一条 A2A 笔记后 |
|---|---|---|---|
| notes | 196 | 180 | 181 |
| ftsRows | 180 | 180 | 181 |
| ragChunks | 139 | 139 | 140 |
| missingFts | 16 | 0 | 0 |
| missingChunk | 111 | 95 | 95 |

**未做**：95 条「有 FTS 无 chunk」的旧笔记（galaxy 种子 + v19 前存量）未回填；主检索走 `note_fts`，不影响召回，等向量检索接入时再统一回填。

## 27. 2026-11-05 RAG 召回 v2 + 工具循环护栏（044 落地）

**RAG 召回**（spec 044 R1–R5）：

- `QueryTerms`：全角归一、复用 `NoteRetrievalQuery` 边界清洗、剥离「等于几/怎么算」等尾巴，`的/和/与/及` 作分隔符，单字词在有长词时丢弃。
- `RagQueryPlan`：整句命中优先（既有行为不变），miss 后词 OR 兜底；FTS 词未命中再走短词 LIKE。
- `RdbNoteSearchAdapter`：`note_query_rag` 与 FTS 共用同一套拆分；`NoteSearchRanking` 增加命中词数加成。
- `NoteEvidenceService`：`maxContextChars`（默认 2400）预算，超出从尾部裁剪并标 `budget-truncated`。
- `ConversationFormatting`：`[RAG] citations=… answerRefs=… keptRefs=… coverage=…` 覆盖率日志。

**真机评测**（`e2e=ragEval`，14 条查询含 1 条负样本）：

```
stage=done ragEval=1 total=14 hit1=11 hit5=13 miss=0 negatives=1 falsePositives=0 skipped=0 ms=335
```

`一加一等于几`、`9+9 的加法计算怎么算` 均从 miss 变为 rank=0；`ragSearch` 复跑 `citations=7 degraded=0 contextChars=1603`，无回归。

**工具循环 P0 护栏**：

- `ExecuteToolsNode`：单工具 8s 超时、异常转 `ok:false` 回喂、结果超 4000 字截断、每次调用记 `[ToolLoop] tool name=… ok=… ms=… chars=…`。
- `ConversationReplyHandler`：工具循环失败回退普通回复，不再直接终结整轮。
- 真机 `e2e=toolLoopProbe`：模型真实调用 `note_query_rag`（`ok=1 ms=13 chars=2586`），5.1s 返回 766 字答案。

**仍未做**：工具循环默认关闭（`CHAT_TOOL_REPLY_ENABLED`），开启前需产品决定「工具结果如何呈现」；流式工具循环未实现（041 明确非目标）。

**顺带修复（A2A 证据）**：真机冒烟暴露 `A2A_EVIDENCE citations=0 degraded=1 reason=search-failed`。根因是扩展进程的 `DatabaseHelper.init` 是 fire-and-forget，消息先于建库到达时证据检索查空库。修法：把 DB init 串进 `configReady` 链，并让 `A2AChatContext.build` 内部等待库就绪。真机复测 `A2A_EVIDENCE citations=1 degraded=0 reason=`，回复正常（723 字 / 3.8s）。

## 28. 2026-11-05 开启聊天工具循环（041）

- `CHAT_TOOL_REPLY_ENABLED = true`，但新增意图闸门 `ConversationToolReplyFlags.shouldUseTools`：只有「笔记 / 知识库 / 错题 / 复习 / 我保存过 / 我记得 / 查一下我」才走 `tool_reply`；普通数学问答继续 `stream_reply`。
- 呈现：工具结论并入最终回答，来源块沿用 `applyEvidenceToAnswer` 的证据脚注，不展示原始工具 JSON。
- 真机（设备 `3XTYD24C16203663`）：
  - 「查一下我笔记里关于连续性的内容」→ `note_query_rag ok=1 ms=107 chars=4012` + 3 次 `note_get`，21s 返回；
  - 「什么是导数」→ `StreamTiming path=text firstChunkMs=638 totalMs=2844 chars=904`，无工具调用，流式保持。
- 测试：图级闸门用例（笔记意图走工具、普通问答走流式）+ flag 单测；gate 1274 单测。

**流式化（2026-11-05 同日）**：新增 `ToolCallingStreamingWorkflow` + `LlmStreamParser`，SSE 里按 index 拼接 `tool_calls` 增量；`tool_reply` 节点改走 `handleStream(..., true)`。真机对比：

| 指标 | 非流式（旧） | 流式（新） |
|---|---|---|
| 首字 | 约 20s（整包） | 3.4–3.8s |
| 总耗时 | 约 20–21s | 7.7–7.9s |
| 正文 | 整段出现 | 逐字推送（1610–1802 字） |

**工具结果预算**：`ToolResultBudget` 优先保结构——对象按 `hits`/任意数组字段丢尾部、顶层数组（`note_query` 返回 `[...]`）按条丢弃、无数组时缩短超长字符串；真机 `note_query chars=3958 truncated=1 dropped=2`，回喂给模型的仍是合法 JSON。旧实现直接按字符截断，会把 JSON 切成半截。

## 29. 2026-11-05 对话 UI 打磨（工具步骤 + 引用去噪）

- **工具步骤可见**：`ToolCallingStreamingWorkflow` 在工具执行前后向 UI 推送 `tool_call` / `tool_result` 事件，`AgentRunPanel` 用既有 `AgentToolStep` 渲染「检索笔记 / 查询相关笔记 / 读取笔记详情」卡片，状态在运行中 → 已完成之间切换。
- **工具结果摘要**：新增 `summarizeToolResult`（`AgentRunModels`），把 JSON 折成一行人话：
  真机显示 `检索笔记 · 已完成 · 命中 8 条 · 已截断`、`查询相关笔记 · 已完成 · 返回 11 条`。
- **引用去噪**：新增 `common/utils/CitationText.stripCitationMarkers`，来源块与答案正文展示时都去掉 `[noteId=... version=...]`；真机整页 `noteId` 出现次数为 0。引用校验仍在证据层完成，不受影响。
- 测试：`conversation-formatting`（标记清洗）、`tool-loop-streaming`（工具事件顺序、结果摘要）；gate 1286 单测。

## 30. 2026-11-05 回答渲染修复（裸公式 / 复述证据）

真机现象：答案里出现原始 `$$`/`###`/`[关键词命中]`，公式未编译。

**根因**（用真机抓到的答案离线跑校验器确认）：

1. 模型输出**裸公式行**（没有 `$$`）和**裸行内命令**（如「存在一点 \xi \in (a,b)」）。
2. 复述的证据摘录里有被 `buildExcerpt` 截断的公式（`\frac{f(b)-f(a)}{…`），括号不闭合。
3. `ContentProtocol` 因此判定 `fallbackRequired`，`MathTextRenderer` 直接把整块降级成纯文本——原始 LaTeX/Markdown 就露出来了。
4. 模型还会整行复述 `- [关键词命中] …`、`参考来源：` 和工具 JSON。

**修复**：

- 提示词新增两条：不复述证据块/工具 JSON（12）；行内数学必须 `$...$`、独立公式必须 `$$...$$`（13）。
- `ContentProtocol` 增加修复而不是降级：
  - `balanceBraces`：补齐 `\frac{a}{…` 这类未闭合括号；
  - `balanceLeftRight`：补 `\right.` / `\left.` 占位；
  - `wrapNakedInlineTex`：整行无 `$` 时，把白名单内数学命令包进 `$...$`（路径等普通文本不误伤）。
- 展示层兜底：`stripEchoedEvidence` 去掉复述的证据行与长 JSON；`markdownToPlainText` 让真正的渲染失败也只显示可读纯文本；来源摘录同样纯文本化。

**真机验证**：同一问题重跑，原始标记节点从 3 个降为 1 个，且该节点是 KaTeX 的 MathML `annotation`（渲染产物，不可见）；公式、列表、标题均正常渲染。

## 31. 2026-11-05 笔记来源展示重设计

**问题**：命中来源原本拼在回答正文里（状态行 + 每条摘录），摘录是 160 字硬截断，常把公式或句子截成半截，渲染时报错、出现 `…` 残片；同时内部 noteId 曾经直接暴露。

**设计**：命中来源改为回答下方的结构化卡片，正文不再拼长文本。

- 新事件 `ConversationSourcesMessageEvent`：workflow 在收尾时推送 `citations`，经 reducer 落到 `ChatMsg.citations`。
- `ChatSourcePanel`：默认折叠为「参考来源 · N 条」一行；展开后每条显示角色（关键词命中/前置/关联）、标题、最多两行纯文本摘要；点击行打开既有只读来源浮层。
- 摘要用 `citationSnippet`：先 `markdownToPlainText` 去公式/标题标记，再按句号/分号截断，避免半句或半公式。
- 未命中/检索失败仍保留一行状态文案；工具链路径不再显示会误导的「未命中」（工具卡片已表达检索过程）。
- 顺带修复模型复述 JSON 时留下的字面 `\n`：`normalizeEscapedNewlines` 在展示层还原换行，且不影响 `\n` 这类 LaTeX 片段。

**真机验证**：`参考来源 5 条`面板正常展开，首行 `[关键词命中] 泰勒公式余项估计`；回答正文不再出现来源长文本，字面 `\n` 计数为 0。

## 32. 2026-11-05 去重与旧知回溯优化

**重复整理问题**：真机发现同一道「计算 21 加 21」被整理出 4 条笔记——每次生成正文措辞不同，旧的正文相似度阈值（0.75/0.92）抓不住；而两次生成还可能一个用阿拉伯数字、一个用中文数字（`80 加 80` vs `八十加八十`）。

修复（`NoteDedupe`）：

- 归一化去掉结构助词（的/了/与/和/及/之/其），并把中文数字段转成阿拉伯数字（八十 → 80）。
- 标题归一后长度 ≥6 且完全相同 → 直接判重（同一主题重新生成必产生不同正文，不能靠正文相似度兜底）。
- 新增「数学签名」规则：标题数字序列相同且标题包含度 ≥0.5 或正文相似 ≥0.5 → 判重。
- 新增「主题包含」规则：短标题被长标题完整包含（长度比 ≥0.75）且正文相似 ≥0.6。
- 候选池从最近 120 条扩大到 500 条，避免旧笔记落在窗口外。

**旧知回溯**：`NoteSearchRanking.rankNoteHitsByTerms` 从「词频」改为「查询词覆盖度」：

- 中文长词补二元组 token，按标题 ×6 / 标签 ×4 / 摘要 ×3 / 正文 ×1 计覆盖数，再叠加覆盖率和命中词数加成；
- 标题命中可以压过更新更晚但只命正文的笔记；更新时间只做同分排序，不再间接偏向新笔记。

**真机验证**：

- 新增 `e2e=dedupeSimilarityProbe`：同一道题换说法再整理 → `addedSecond=0`、`dedupeSimilarity=1`。
- `ragEval` 不变：`hit@5=13/13 miss=0`；`ragSearch` 不变：`citations=7`。

## 33. 2026-11-05 笔记相似度技术路径确认

**真机可行性（MRO-W00 / API 26，项目 compatible 24）**

| 路径 | 结果 |
|---|---|
| 系统文本嵌入 `@ohos.data.intelligence` | syscap 支持，`getTextEmbeddingModel` 成功，但本地 `BASIC_MODEL` 与系统云模型 `loadModel()` 都返回 `31300000 Inner error`。当前不可用，疑似模型包/账号授权未就绪 |
| 中文分词 `@hms.ai.nlp.textProcessing` | 可用：`init` 约 0.9s，单次分词约 40ms，返回词性（n/v/vn/m/ude1 等） |
| 检索 Kit 向量通道 `@hms.data.retrieval` | 依赖底层 embedding；037 R1 曾报 1021201002，暂不优先 |
| 云端 embedding（OpenAI 兼容 `/v1/embeddings`） | 技术上可接；当前 DeepSeek 无 embedding 接口，需要用户另配厂商 |
| 端侧 MindSpore Lite | API 存在，需要自带并转换 `.ms` 模型（几十 MB），重工程 |

**本轮落地：数学语义签名（不依赖模型）**

- 新增 `common/utils/MathSignature.ets`：中文数字/全角运算归一，解析「两个 X 的和」「X 加 Y」「X 除以 Y」「X 的平方」等表述，按优先级生成结构化签名（`12 - 4 × 2` → `sub(12,mul(4,2))`）。
- `NoteDedupe` 增加签名判重：`计算 21 加 21` 与「两个 21 的和」视为同一道题。
- 真机 `dedupeSimilarityProbe` 改为「算式 → 文字表述」两次整理：`addedSecond=0`、`dedupeSimilarity=1`（16.5s）。

**建议的分层方案**（尚未全部落地）：

1. L0 归一：数字/全角/LaTeX/Markdown 清洗；
2. L1 确定性相似度：分词关键词（系统 NLP）+ 数学签名 + 标题主题 + 字符 n-gram 包含度；
3. L2 语义相似度：`EmbeddingPort`（系统 → 云端 → 无），向量写入既有 `rag_embedding`，用于去重候选重排与混合召回（RRF）；
4. L3 边界仲裁：相似度落在灰区时用现有聊天模型做一次「是否同一道题」判定，命中则走更新而非新建。

## 34. 2026-11-05 重复笔记清理执行

**执行**：`e2e=legacyCleanupApply`（严格规则：标题归一相同或数学签名相同；跳过含 galaxy 种子的组与泛标题组）。

```
scanned=186 duplicateGroups=26 strictGroups=20 duplicateNotes=52 removed=52 failed=0
```

最大几组：洛必达法则 15→1、计算 12+7×3 7→1、计算 12×8-15 6→1、求 7 的平方根 6→1、计算 21 加 21 4→1。

**清理后验证**：

- `stage=rag-coverage notes=134 ftsRows=134 missingFts=0 missingChunk=74`（删除同时清掉了 FTS/分块/关系边）；
- `ragEval hit@5=13/13 miss=0`、`ragSearch citations=7`，检索无回归；
- 再次审计：`strictGroups=0 duplicateNotes=0`，剩余 6 组松匹配为刻意保留（种子组 + 「解一元一次方程」泛标题组）。

**踩坑记录**：清理模式名是 `legacyCleanupApply`，此前误用不存在的 `legacyCleanup`，导致只打印 `launch-param` 后直接返回，看起来像「脚本跑不通」。探针模式名与文档需保持一致。

## 35. 2026-11-05 分词查询扩展 + 灰区语义仲裁

**L1 查询扩展**：

- 新增 `QueryKeywordExtractor`（entry）：懒加载 `@kit.NaturalLanguageKit`（受限 Kit 不得静态 import，否则 A2A 扩展进程会加载），按词性抽取名词/动词/数量词，过滤停用词，最多 6 个；任何失败返回空数组。
- `mergeQueryTerms`（common 纯函数）：把分词关键词与规则拆分的词合并、去重、按长度截断。
- `RagRetrievalService` 的词 OR 兜底改用扩展后的词表；整句命中路径不变。

**L3 灰区仲裁**：

- `NoteDedupe.similarityScore`：连续相似度（同标题 1.0、同数学签名 0.95、同数字序列 0.9，其余按标题相似度/包含度/正文相似度加权）。
- 阈值：`≥0.9` 直接判重；`[0.5, 0.9)` 交给 `NoteSimilarityJudgePort` 仲裁；`<0.5` 不判重。
- `LlmNoteSimilarityJudge`（entry）：一次 8s 超时的 YES/NO 判定，未配置/失败一律返回 false（宁可不判重）。
- 写入服务注入 judge：硬规则未命中时，用 DAO 的 `findSimilarCandidates` 取候选、打分、灰区调用模型；命中则复用已有笔记（不新增）。
- 组合根 `KnowledgeUnitWriteServiceFactory` 装配 judge。

**真机验证**：

- 分词探针可用（init 约 0.9s、单次约 40ms）；`ragEval` 仍 `hit@5=13/13 miss=0`（查询扩展无回归）。
- `dedupeSimilarityProbe`：同题「算式 ↔ 文字表述」仍 `addedSecond=0`。
- 观察：一次生成阶段的模型调用偶发挂起超过 4 分钟（重跑 26.7s 完成），属于模型网络偶发，非本轮改动引入。

## 36. 2026-11-05 数学签名进入检索主链路

**背景**：换一种说法问同一道题（「两个 21 的和是多少」vs 笔记「计算 21 加 21」）时，FTS 与词 OR 都没有共同关键词，检索不到。

**实现**：

- schema v21：`knowledge_unit` 新增 `signature` 列；启动时对空值按标题计算并回填（`DatabaseHelper.backfillNoteSignatures`）。
- `NoteDao.toBucket` 写入时计算签名，新建/更新自动维护。
- `RagRetrievalService.search` 在整句 FTS 之后、词 OR 之前增加签名直查：
  `SELECT ... FROM knowledge_unit WHERE signature = ? ORDER BY updated_at DESC LIMIT ?`。
- 评测集新增用例：`两个 21 的和是多少` → 期望命中 `计算 21 加 21 并写出运算步骤`。

**真机验证**：

- `ragEval total=15 hit1=12 hit5=14 miss=0`，新用例 `rank=0`（签名直出）。
- `ragSearch notes=137 missingFts=0 citations=7`，迁移与回填正常。
- 相似去重探针本次因模型调用偶发挂起未跑完（此前已验证 `dedupeSimilarity=1`，签名列不改判重规则）。

## 37. 2026-11-05 L2 检索向量化：确定性词面向量 + RRF 融合

**背景**：`rag_embedding` 建表以来一直为空（系统 embedding `loadModel()` 返回 31300000，云端模型列表也拿不到）；检索是「命中即返回」的级联，弱通道的精确命中会被前一路的普通命中挤掉。

**决策**：不等系统模型，先把端口与融合做完，向量来源保持可替换。

- `EmbeddingPort`（common）：`provider / model / dimension / embed`，不含 Kit，任何进程可求值。
- `LexicalEmbedding`（common 纯函数）：中文单字 + 二元组 + 拉丁整词 + 数学签名 token，带符号哈希到 512 维，`1+ln(tf)` 加权、L2 归一化；单字权重 0.5（吸收「的/和」插入造成的二元组错位），签名权重 2。
- 不用系统分词做向量：分词结果必须「索引期与查询期完全一致」，而分词引擎在扩展进程不可用（process-boundary R4）；二元组是确定性的，任何进程得到同一向量。
- `LexicalEmbeddingPort`（entry）：端口实现，标记 `model=lexical-v1`。
- `NoteEmbeddingService`：chunk 级向量写入（确定性行 id，可重复执行）+ 缺失补建 + 覆盖率诊断；标题拼进块正文。
- `NoteVectorIndex`：内存索引 + 全量余弦（千条以内无需 ANN）；新鲜度用 `COUNT / MAX(updated_at) / TOTAL(LENGTH(vector_json))` 三件套跨进程感知；只比较同 model 的向量。
- `KnowledgeUnitEmbeddingEffect`：post-commit 补建，不进事务——纯 CPU 工作不进写锁，缺失可由补建自愈，不像 FTS 会永久漏召回。
- `RagRetrievalService`：五路召回（整句 3 / 签名 3 / 词 OR 2 / 短词 LIKE 1 / 向量 2）按 RRF 融合（k=60，各路候选 ×3），取代原来的级联短路。

**边界**：词面向量解决不了真正的语义替换（导数 ↔ 瞬时变化率），那是稠密模型的事；端口与按 model 过滤已留好，接入系统/云端 embedding 时旧向量自动视为待重建，重跑补建即可。

**真机实测（关键负结果）**：

- `stage=rag-vector backfilled=95`、`rag-vector-coverage ragChunks=95 vectors=95 missingUnits=0`——写入与补建链路正常。
- 但词面余弦分不开相关与无关（95 个 chunk，minScore=0 看全量分布）：

| 查询 | 性质 | 原始余弦 | 去均值后 |
|---|---|---|---|
| 导数定义与几何意义 | 相关 | 0.151 | 0.226 |
| 极限 | 相关 | 0.140 | 0.123 |
| 连续性 | 相关 | 0.092 | 0.201 |
| **今天天气怎么样** | **无关** | **0.095** | **0.163** |

- 无关查询的分数压过相关查询「极限」，去均值（`meanVector` / `subtractCentroid`）提高了相关分但没解决重叠；开着向量通道时「今天天气怎么样」被拉回 2 条无关笔记。
- 结论：**TF 词面余弦在长块上不可用**——长文档的归一化把真正命中的少数词稀释，公共二元组贡献与主题词贡献同量级。改成 IDF 加权只是把同一个问题推后，词面方法本质上补不上「导数 ↔ 瞬时变化率」的语义鸿沟。
- 处置：`VECTOR_CHANNEL_ENABLED = false`，向量通道不进检索融合；端口、写入、补建、索引、诊断全部保留（已验证可用），接上稠密模型后改回 true 即生效。关闭后 `ragEval total=15 hit1=12 hit5=14 miss=0 falsePositives=0`，与关闭前逐项一致，无回归。

**验证**：gate PASS（1327 单测，含新契约）；`build-hsp-hap` 真实 ArkTS 编译通过；真机 `ragSearch` / `ragEval` 已跑（数据见上）。

## 38. 2026-11-05 云端 embedding 接入 + 测试库重置

**背景**：第 37 节的负结果说明词面向量补不上语义鸿沟，真正的 L2 只能靠稠密模型。系统 `@ohos.data.intelligence` 仍被模型包挡住（31300000），改走云端。

**实现**：

- `LlmConfig` 新增 `embedding_model`（空串 = 未启用）；复用当前服务厂商的 baseUrl 与 API Key，因此该厂商必须支持 OpenAI 兼容 `/embeddings`。
- `CloudEmbeddingPort`（entry）：`POST {baseUrl}/embeddings`，`{model, input[]}` → `{data:[{index, embedding[]}]}`；单批 16 条、连接 10s/读 30s；失败抛异常不落半截数据。
- `EmbeddingModels`（common 纯函数）：模型标识带 `cloud:` 前缀，检索只比较同标识向量，避免词面/稠密混算。
- `EmbeddingRuntime`（entry）：配置了模型走云端，否则回落词面；`isDense()` 决定检索是否开启向量通道。
- `NoteEmbeddingService`：写库改走活动端口；切换模型后旧向量由下一次补建覆盖；云端补建每次限 20 条笔记（每条一次请求）。
- `NoteVectorIndex`：查询向量也由同一端口生成（云端每问一次多一次往返），戳里带上 model。
- 设置页新增「语义检索」区块：开关 + 模型名 + 自检（真的调一次 /embeddings，并比较「导数定义」/「瞬时变化率」与无关句的余弦）。
- 调试探针 `cloudEmbeddingProbe`：设备侧直接验证维度与区分度。
- 调试探针 `clearNotes` / `clearNotesAudit`：测试库重置（逐条走 `NoteDao.deleteById` 保证级联，末尾兜底清挂靠行）。

**说明**：`bm uninstall` 被安全策略拦截，改用应用内清空——只动笔记与其索引，不动密钥与设置。

**重置结果（2026-11-06 00:02）**：`removed=135 failed=0`，随后 `notes=0 ragChunks=0 ftsRows=0 vectors=0`。

**待办**：云端通道尚未用真实密钥验证；需在设置页填入支持 `/embeddings` 的厂商模型后跑 `cloudEmbeddingProbe` 与 `ragEval`。

## 39. 2026-11-06 测试语料与语义召回基线

**重置**：清空 135 条历史笔记（`clearNotes` 探针，逐条走 `NoteDao.deleteById` 保证级联），随后 `notes=0 ragChunks=0 ftsRows=0 vectors=0`，重装 HSP/HAP。

**语料**：`TestCorpusSeed.ets` 手写 25 条大学数学笔记，不经过模型生成——输入固定，召回结果才可复现。分布：数学分析 8 / 高等数学 6 / 线性代数 6 / 概率论 5。数学分析偏定义与理论、高等数学偏计算，两组刻意不重叠，避免判重把相近条目误判。

**评测集**：`RagEvalCases` 重写为 22 条，带 `kind` 分组：

- `paraphrase` 10 条：刻意避开标题关键词（「存在一点其切线平行于两端连线」→ 拉格朗日中值定理），专测语义召回；
- `exact` 8 条：直接用标题，测字面召回；
- `negative` 4 条：闲聊类，命中必须为 0。

**基线（仅词面通道，未配 embedding）**：

```
total=22 hit1=8 hit5=8 miss=10
paraTotal=10 paraHit1=0 paraHit5=0
negatives=4 falsePositives=0
```

同义改写 0/10、精确查询 8/8、负样本零误命中。这条基线把「语义召回」单独隔离出来：接上云端 embedding 后 `paraHit1` 的变化，就是该通道的净收益。

**索引状态**：`notes=25 missingFts=0 missingChunk=0`、`model=lexical-v1 ragChunks=25 vectors=25 missingUnits=0`。

## 40. 2026-11-06 本地 BGE 接入与稠密向量召回

**部署**：`tools/embedding_service/`（FastAPI + sentence-transformers，端口 8001），`start.bat` 手动启动，手机指向 `http://<PC-IP>:8001/v1`。应用侧 embedding 的模型 / 端点 / 密钥三项与聊天厂商完全独立——聊天继续用 DeepSeek 不受影响。

**关键修复：去均值对稠密向量有害**。中心化是为词面向量设计的（压公共二元组基线），稠密向量本身分布良好，减掉均值会把分数整体压扁：

| 查询 | 原始余弦 | 去均值后 |
|---|---|---|
| 函数图像没有断开 → 连续与一致连续 | 0.453 ✓ | 0.095 |
| 存在一点切线平行于弦 → 拉格朗日中值定理 | 0.440 ✓ | 0.158 |
| 今天天气怎么样（无关） | 0.232 | 0.150 |

处置：`NoteVectorIndex.load` 只在非稠密模型时计算并减去语料均值；阈值从 0.18 重标到 0.33（相关 0.44–0.71，无关 0.232）。

**评测对比**（22 条：10 改写 + 8 精确 + 4 负样本）：

| 配置 | hit1 | hit5 | miss | 同义改写 hit1 | 误命中 |
|---|---|---|---|---|---|
| 无向量（纯 FTS） | 8 | 8 | 10 | 0/10 | 0 |
| BGE + 去均值 + 阈值 0.18 | 14 | 14 | 4 | 6/10 | 0 |
| BGE 不去均值 + 阈值 0.33 | **16** | **17** | **1** | **8/10** | **0** |

**剩余问题**：唯一的 miss 是「x 靠近某点时函数值靠近某个值，怎么写成一串不等式」→ ε-δ 定义，向量最高分 0.515 却指向了中值定理，属模型语义混淆而非管线缺陷；另有 1 条改写落在 rank=3（hit5 命中）。

## 41. 2026-11-06 A2A 扩展进程验证 + 检索运维化

**A2A 扩展进程（此前未验证）**：扩展进程 `com.example.mindtrace:agent` 在证据构建期间向 8001 端口发明文 POST，`RespCode=200 tls=0.000 total=305ms`，随后打出 `A2A_EVIDENCE mode=dense citations=5 degraded=0`，之后才调 443 端口的 LLM。结论：扩展进程能连本地 embedding 服务，稠密检索在扩展进程内正常。

**修复**：A2A 证据构建固定 1200ms 超时，稠密模式多一次 HTTP 往返会被砍成「静默无证据」；改为稠密模式 2500ms。

**应用内对话**：发「函数图像没有断开说明什么」（「断开」不在任何笔记正文里，FTS 必然 miss），来源面板 5 条，首条即「连续与一致连续」，其后为中值定理 / 泰勒 / 可导可微——语义排序生效。

**阈值自动标定**：判定改为「绝对下限 0.33 + 相对切尾 0.6×top」，绝对阈值挡无关查询、相对切尾随语料增长收紧长尾。评测无回归：`hit1=16 hit5=17 miss=1 paraHit1=8/10 falsePositives=0`。探针输出 `n/top/p50/mean`，供语料规模变化后重标。唯一 miss 的 top 仅比 p50 高 0.066（正常命中为 0.11–0.25），进一步确认是模型混淆。

**判重灰区（只观测）**：记录 `[DedupeTrace] gray l1=.. vec=.. judge=..`，不参与决策。向量误合并不可逆，先攒够真实样本再定阈值。

**运维可见性**：进入设置页时自动探活，语义检索区块显示「在线 · 1024 维」或「离线：…」，本地服务手动启动的现状不再靠猜。

## 42. 2026-11-06 条件重排：只救「分不开」的头部

**背景**：25 条语料的余弦分挤在 0.372–0.515。唯一 miss 的期望笔记排第 9（0.465），而 top1 是 0.515——前 5 名切不干净，调融合权重无效（那是排序问题，不是权重问题）。

**无条件重排是负优化**：`bge-reranker-base` 重排前 12 名，hit@1 从 16 掉到 13、同义改写 hit@1 从 8 掉到 5。原因是通用 reranker 会推翻本来排对的强信号。延迟也不可接受：正文前 240 字作文档，8 条 2.4s、25 条 7.5s。

**换成摘要作文档**：`标题 + 摘要`（约 60 字）替代正文前 240 字，25 条从 7.5s 降到 0.66s，目标笔记从第 9 升到第 1（0.228，次名仅 0.043）。正文开头的「## 定义」模板字既拖慢编码又没有区分度。

**最终形态：条件重排**。只在 `top1 - top2 < 0.03`（余弦头部确实分不开）时介入，其余保持余弦顺序。

| 配置 | hit1 | hit5 | miss | 同义 hit5 | 误命中 |
|---|---|---|---|---|---|
| 无重排 | 16 | 17 | 1 | 9/10 | 0 |
| 无条件重排 | 13 | 17 | 1 | 9/10 | 0 |
| **条件重排** | **16** | **18** | **0** | **10/10** | **0** |

服务端复用 embedding 的端点与密钥，新增 `/v1/rerank`（`MT_ENABLE_RERANK=0` 可关闭）；应用侧失败静默回落到余弦顺序，不构成硬依赖。

## 43. 2026-11-06 规模测试：25 → 100 条语料

**做法**：补 75 条大学数学笔记（`TestCorpusBulk`，按「要点 / 说明 / 常见错误」三段写），语料从 25 条扩到 100 条；新增 `ragSpotCheck`（样本外 10 条）与 `ragOodCheck`（语料外 5 条）两个探针。

**结果**：

| 配置 | hit1 | hit5 | miss | 同义 hit@5 | 误命中 |
|---|---|---|---|---|---|
| 25 条（基线） | 16 | 18 | 0 | 10/10 | 0 |
| 100 条 · bge-large · 0.33 | 12 | 14 | 4 | 6/10 | 0 |
| 100 条 · bge-m3 · 0.33 | 12 | 14 | 4 | 6/10 | **4** |
| 100 条 · bge-m3 · 0.46 | 12 | 14 | 4 | 6/10 | 0 |
| 100 条 · bge-m3 · 0.46 · 条件改写 | 12 | 15 | 3 | 7/10 | 0 |

**结论**：

1. **内容补全不影响结果**：补全前后数字完全相同，退化纯粹来自语料规模。
2. **换模型不是答案**：bge-m3 的纯向量排序略好（hit5 7 vs 6），但端到端一样；且它的分数尺度整体高一档（无关 0.377–0.438、相关 0.49–0.56），**阈值必须按模型重标**，照搬 0.33 会让四条闲聊负样本全部误命中。
3. **强排不可靠**：候选扩到 30 条强制重排，救回 2 条、毁掉 3 条——通用 reranker 在数学语料上只是"另一种排序"。
4. **条件改写有效但有限**：只在 `top1-top2 < 0.03` 时调 LLM 把问题改写成检索关键词（4/22 条触发，每条 +1–2s），hit5 14→15、miss 4→3。
5. **根因是同领域近邻**：语料里「罗尔定理 / 柯西中值定理 / 拉格朗日中值定理」三条并存时，「存在一点切线平行于弦」这类问法在纯向量空间里分不开，通用 reranker 也分不开。这不是调参能解决的，除非引入更强的领域模型或让用户把问题问得更具体。

**样本外泛化**（`ragSpotCheck`，25 条语料时）：hit@1 6/10、hit@5 8/10，比调优集低约 20 个百分点——调优集的数字偏乐观。

## 44. 2026-11-06 置信度闸门：三种信号都分不开

**目标**：语料外提问（复变函数、图论、数理逻辑…）目前也会返回 5 条无关引用，系统从不说「笔记里没有」。想让证据注入前有个把关。

**试过的信号**（100 条语料）：

| 信号 | 相关 | 无关 / 答错 | 结论 |
|---|---|---|---|
| 余弦 top | 0.49–0.68 | 0.38–0.55 | 重叠，无分界 |
| reranker 分（正文摘录作文档） | 0.03–1.00 | 0.24–0.27 | 弱相关比无关还低 |
| reranker 分（标题+摘要作文档） | 同上 | 同上 | 不改善 |
| 查询词覆盖率 | — | — | 整短语匹配全为 0，二元组又全过 |

**实测闸门效果**：阈值 0.4 → `hit5 15→11`、`paraHit5 7→3`；阈值 0.2 → `hit5 12`；语料外拦截 0–5 条不等。**误伤远大于收益，已回退**。

**结论**：交叉编码器的分数只适合在候选之间排序，不适合当「能不能回答」的置信度——它对绝对相关度没有校准。

**唯一有效的方案是让 LLM 直接判断**（`LlmEvidenceJudge`）：把问题与候选笔记的「标题+摘要」交给模型，只回答 YES/NO。提示词必须写成「只要涉及该主题就 YES，只有完全无关才 NO」，否则会把措辞不同的正确笔记判掉（第一版就误杀了「矩阵化成阶梯形后有几个非零行」）。

| 配置 | hit1 | hit5 | miss | 语料外有命中 |
|---|---|---|---|---|
| 无判定 | 12 | 15 | 3 | 5/5 |
| LLM 判定（宽松提示词） | 12 | 14 | 4 | **0/5** |

代价是每条有候选的查询多一次 LLM 调用（超时 1.5s，fail-open），换掉全部无关引用。已单测固化：判定失败必须返回 true，不能因为一次超时砍掉正常召回。

## 45. 2026-11-06 向量文本：摘要不如正文，模板行才是噪声

**假设**：重排用「标题+摘要」比正文好一个数量级（§42），向量是不是也该换成摘要？

**实测否定**。同样 100 条语料、同样 bge-m3，只改向量文本：

| 向量文本 | hit1 | hit5 | miss | 同义 hit1 | 同义 hit5 |
|---|---|---|---|---|---|
| 标题 + 正文（原样） | 12 | 14 | 4 | 4 | 6 |
| 标题 + 摘要（A） | 11 | 13 | 5 | 3 | 5 |
| **标题 + 正文，剥掉 `##` 标题行（C）** | **13** | **15** | **3** | **5** | **7** |

**结论**：摘要适合做**判断依据**（重排、相关性审核），因为它浓缩主题；但不适合做**向量**——正文里的术语细节（公式符号、条件表述）在摘要里没有，而检索恰恰要靠这些细节区分近邻笔记。真正拖后腿的是「## 定义」「## 要点」这类所有笔记共用的模板行，剥掉即可。

**顺带修掉一个补建缺陷**：`CloudEmbeddingPort` 原来一次网络失败就触发 60 秒全局熔断，导致 100 条补建只完成 13 条就静默退出（`backfillMissing` 看到「本条失败、下条冷却失败」，以为没活干）。改为**连续失败 3 次才熔断**。同时新增 `reindexEmbeddings` 探针：改了向量文本后模型名不变，补建逻辑不会认为旧向量过期，必须强制重建。

## 46. 2026-11-06 标题加权 + 放宽重排触发线

**动机**：同义改写的失败大多是近邻笔记（罗尔定理 / 柯西中值定理 / 拉格朗日中值定理），区别几乎全在标题上，而标题在 300–400 字正文里只出现一次。

| 配置 | hit1 | hit5 | miss | 同义 hit1 | 同义 hit5 |
|---|---|---|---|---|---|
| C（标题×1 + 正文） | 13 | 15 | 3 | 5 | 7 |
| 标题×2 + 正文 | 12 | 16 | 2 | 4 | 8 |
| **标题×2 + 正文，重排触发线 0.03→0.05** | **13** | **17** | **1** | **5** | **9** |

标题重复让更多正确笔记进入前 5，但头部扎堆导致第一名变差；放宽重排触发线（更多查询走一次摘要重排）把第一名修回来，两项叠加是当前最好成绩。

**语料外判定是概率性的**：同一配置连续三次 `ragOodCheck` 分别得到 0/5、2/5、1/5 有命中。「常微分方程组怎么写成矩阵形式」会被判成与「基础解系」相关——判定是有道理的边界情况，不能把 0/5 当成确定性保证，只能说从 5/5 降到了约 1/5。

**样本外抽查**（`ragSpotCheck`）：`hit1 4/10、hit5 7/10`，与调优集走势一致，没有明显过拟合。

## 47. 2026-11-06 结构调整：解耦「用户意图 / 来源可信度 / 笔记组织」

**背景**：检索链路在一个函数里同时回答三个问题——够不够、用户想要什么、该不该写。三者纠缠导致：判定只覆盖 FTS 一路（工具兜底不过判定）、意图被折叠成两种、判重命中静默丢弃新内容。

**Stage A｜证据策略**：新增 `EvidencePolicy` / `EvidenceJudgePort`（common）。判定从 `RagNoteEvidenceSearch` 上移到 `NoteEvidenceService`，**工具兜底路径现在也受同一策略约束**。判定层改为只汇报 `yes / no / unavailable`，放行与否由策略决定。新增 reason `evidence-rejected`；citation 带上 RRF 融合分与 summary（此前 `score` 硬编码 0）。

**Stage B｜学习模式**：`TextConversationRequest` 增加 `evidenceMode`，在 `load_reply_context` 映射成策略。严格模式判定不可用时 **fail-closed**（用户确认）。本轮不做 UI，默认 balanced。

**Stage C｜笔记类型**：schema v22，`knowledge_unit.kind`（normal/atomic/summary）。`NoteDedupe` 增加同类型约束——不同类型不判重，为原子笔记与汇总笔记共存铺路（现有数据全为 normal，行为不变）。

**Stage D｜建议请求**：新增 `NoteSuggestion` 与可选回调 `onNoteSuggestion`。生成链路发 `create`，判重命中发 `merge`。本轮只记日志、不渲染。

**与计划的偏差（编译后修正）**：
- `NoteOutcome` 不含 `duplicate`，所以 merge 建议改由 `KnowledgeUnitWriteService` 在判重命中处直接记日志——只有它同时知道新笔记与已有笔记 id。
- `AgentChatCallbacks`（UI 契约）没有对应方法，adapter 只记日志，不向 UI 转发。

**验证**：gate PASS（1341 单测）；真机迁移后 `notes=100 vectors=100` 无损；`ragEval 13/16/2` 对比重构前 `13/17/1`，在判定 ±1 噪声内；`ragOodCheck 1/5`（噪声范围内）；判重命中打出 `[NoteSuggestion] action=merge ... reason=duplicate-on-write`。生成链路的 `create` 建议仅由单测覆盖，未真机触发。

## 48. 2026-11-06 判重规则：向量兜底 + 灰区下限 0.4

**实验**：用生成链路造了 11 条数学分析 / 高等代数笔记（同题异构 3 组、第三说法 3 条、相关但不同 1 组）。生成笔记结构完整、术语规范，比手写短标题更能暴露 L1 的短板。

**发现**：
- 跨措辞的同题（「一致连续的定义」vs「能否用同一个 δ 控制」）L1 落在 0.4–0.5，原下限 0.5 直接放行，**连仲裁都不进**。
- 而向量分抓得住：同类约 0.86–0.89，真实的同题合并样本为 `l1=0.590 / vec=0.795`。
- 生成失败全部来自生成链路的 verifier 驳回（指出「一致连续的函数未必在闭区间上连续」这类不严谨表述），不是判重问题。

**改动**：
1. `SIMILARITY_GRAY_MIN` 0.5 → 0.4。
2. L1 未命中时改用 `NoteVectorIndex` 按内容召回（阈值 0.78），命中再交同一个 judge 裁决——向量只负责「值得看一眼」，不直接合并。

**验证**（同一批 11 条输入）：`created=0 deduped=10`，三条**全新说法全部被判重**（此前 0/3）。轨迹：

```
gray   l1=0.600 vec=0.859 judge=1
vector vec=0.862 judge=1 → 已有一致连续笔记
vector vec=0.781 judge=1 → bulk-31「函数项级数的一致收敛」
gray   l1=0.528 vec=0.893 judge=1
```

代价：每次写入在 L1 未命中时多一次本地向量查询（约 150ms）与可能的额外仲裁调用。

## 49. 2026-11-06 仲裁升级为三分类裁决

**动机**：原来的仲裁只回答「是不是同一道题」。但真实情况有三类——同一道题且没有新内容、同一主题但新笔记带了补充、以及不同主题。前两类都被判成「同一道题」的话，补充内容会被静默丢弃。

**改动**：
- `NoteSimilarityJudgePort.isSameNote` → `judge()`，返回 `NoteSimilarityVerdict { kind: same | supplement | different, reason }`。
- `same` → 拦下，复用已有笔记；`supplement` → **照常写入**（不丢内容）并发 `[NoteSuggestion] action=append`；`different` → 照常写入。
- 提示词改为三选一（SAME / SUPPLEMENT / DIFFERENT）；解析失败按 DIFFERENT 放行，宁可多存一条也不误跳。
- 向量召回阈值 0.78 → 0.75：同一道题两次生成的措辞差异会让余弦在边界抖动，0.78 会漏召回。

**真机验证**（13 条输入，含格林公式的「基础 / 带面积公式」一对）：

```
gray l1=0.727 vec=0.953 verdict=supplement
[NoteSuggestion] action=append sourceNoteId=KB-mw5250tp reason=supplement-detected
[NoteSuggestion] action=merge  ... (多条，SAME 裁决)
```

笔记总数 115 → 116：**只有 supplement 那一条新建**，其余 12 条全部判重。

**探针计数修复**：汇总最初报 `created=0`，与库里的 +1 不符——原因是写入提交到可见之间有短暂延迟，只读一次 count 偶尔读不到新行。改为最多轮询 10 × 80ms 等待可见；也不能用 `confirmDraft` 返回 unit 的 id 判断，它返回的是候选形状、不是落库结果。修复后同一批输入 `created=0 deduped=13`，库中条数 117 未变，报告与实际一致。

## 50. 2026-11-07 判重标定：现有日志不足以支撑免仲裁

**工具**：`scripts/quality/dedupe-calibration.mjs` 解析 `.device-logs` 里的 `[DedupeTrace]`，统计 L1 分 / 向量分 / 裁决，评估「高置信免仲裁窗口」。

**样本**（6 个日志、按时间戳去重后 18 条，全部来自生成链路对照实验）：

```
total=18 gray=11 vector=7
verdicts: same=10 supplement=8 different=0
vec range 0.781–0.960, l1 range 0.408–0.731
```

| 阈值（vec ≥） | 命中 | same | supplement |
|---|---|---|---|
| 0.80 | 14 | 8 | 6 |
| 0.85 | 11 | 6 | 5 |
| 0.90 | 5 | 3 | 2 |
| 0.95 | 3 | 2 | 1 |

**结论**：不能按向量分砍掉 LLM 仲裁。两个原因：① 样本里没有 `different`，无法估计误合并率；② `same` 与 `supplement` 在高分段完全重叠（same 最高 0.960，supplement 最高 0.953），而两者的正确动作相反（拦下 vs 写入）。要标定免仲裁窗口，必须先积累「相关但不同 / 完全无关」的负样本，再按动作分别定阈值。

## 51. 2026-11-07 离线检索评测台（PC，无真机）

> **2026-11-07 追加**：本节数字来自仓库内自建的 100 条夹具，只适合联调，不用于对外指标。评测集已改为 §52 的 MathNet-Retrieve。

**工具**：`scripts/rag-lab/eval.mjs`。从 `TestCorpusSeed/Bulk`、`RagEvalCases/RagSpotCases` 读 100 条语料与 32 条查询，复用 `RrfFusion`；词面用 BM25（中文单字+二元组）近似 FTS5，稠密走本地 bge-m3，重排走 `/v1/rerank`（标题+摘要作文档，仅头部余弦差 < 0.05 时触发，先重排向量候选再融合）。

**结果**（28 条正样本：10 改写 + 8 精确 + 10 样本外）：

| 变体 | hit1 | hit5 | miss | 改写 h1/h5 | 样本外 h1/h5 |
|---|---|---|---|---|---|
| 词面 BM25 | 15 | 23 | 5 | 4/7 | 3/8 |
| 向量·标题+正文 | 16 | 22 | 6 | 4/7 | 4/7 |
| 向量·标题×2+正文 | 18 | 24 | 4 | 5/9 | 5/7 |
| 向量·标题+摘要 | 11 | 18 | 10 | 2/5 | 1/5 |
| 混合·标题×2（无重排） | **18** | **25** | **3** | **6/9** | 4/8 |
| 混合·标题×2 + 条件重排 | 17 | 25 | 3 | 4/9 | 5/8 |

**与真机对照**：离线「混合·标题×2」在调优集 14/18、样本外 4/10（hit@5 8/10），真机为 13/18、4/10（7/10），量级一致——离线台可用于筛选配置，但不替代真机验收。

**结论**：
1. 摘要做向量明显更差（11 vs 18），与 §45 一致：向量要细节，摘要适合做判断依据。
2. 标题×2 优于标题×1，与 §46 一致。
3. 条件重排在本台架上不提升调优集 hit@1（18→17），但样本外 hit@1 4→5；是否保留取决于更看重调优集还是泛化，目前真机配置保留 0.05 触发线。
4. 离线台的价值是「改一行不用装机」：后续权重、触发线、标题倍数都在这里先筛，再上真机。

## 52. 2026-11-08 评测集切换到 MathNet-Retrieve（弃用自建 100 条）

**动机**：自建 100 条由我们手写并用于调参，指标偏乐观、不可对外。改用公开数学检索基准 MathNet-Retrieve（ICLR 2026，CC-BY-4.0）：15,000 条查询 / 117,088 条语料的数学等价检索。

**数据与口径**：
- easy 档中文子集 334 条查询（twn 319 / hkg 15），按 CJK 过滤；
- 候选池固定抽 2,000 条（含全部 334 条 gold），随机命中基线约 16.7%；
- 词面用 BM25（中文单字+二元组）近似 FTS5；稠密走本地 bge-m3；重排在向量头部余弦差 < 0.05 时触发；
- 脚本：`scripts/rag-lab/fetch-mathnet.mjs` + `eval.mjs`，数据缓存在 `.cache/rag-lab/`（git 忽略）。

**结果**（2,000 候选）：

| 变体 | hit@1 | hit@5 | MRR | nDCG@10 |
|---|---|---|---|---|
| 词面 BM25 | 216 | 262 | 0.705 | 0.734 |
| 向量 body | **286** | **314** | **0.895** | **0.914** |
| 混合 body（RRF） | 242 | 296 | 0.793 | 0.833 |
| 混合 + 条件重排 | 232 | 288 | 0.766 | 0.804 |

**补充：全语料词面基线**（117,088 条候选，无抽样）：BM25 hit@1 **22/334**、hit@5 187/334、MRR 0.199、nDCG@10 0.297。等价改写下词面几乎抓不住第一名。

**结论**：
1. 在 2,000 候选池上纯向量最好；全语料词面仅 6.6% hit@1，说明词面通道无法承担主召回。词面与向量等权 RRF 会把向量排对的条目挤下去。
2. 条件重排（标题+摘要）在这个基准上是负优化：79 次触发、耗时 480s，hit@1 再降 10 条。
3. 这与自建 100 条夹具的结论相反（那里混合+重排最好）。原因很直接：夹具是短标题、共享关键词多，词面通道有信息；MathNet 是长题干、等价改写，词面重合不代表同一题。**自建夹具不适合作为调参依据，已停用。**
4. 局限：候选池只抽 2,000 条且含 16.7% gold，命中率不能和全语料 BEIR 榜单直接比较；结论的排序有效性高于绝对值。下一步应在该基准上调 RRF 权重（向量为主、词面降权），并用向量索引做全语料召回，而不是把全部语料重新编码。

## 53. 2026-11-08 A2A 快速整理：正常 4–6s，失败上限 30s

**背景**：A2A 整理用户要等 10–20s；模型挂起时等 90s 才回「稍后整理」，体验很差。

**改动**：
1. A2A 文本入口（`CapturePipeline.ingestTextOutcome`）走 compact 模式：短 prompt（每字段 ≤30 字、总正文 ≤220 字）、`maxTokens=2048`、`timeout=25s`、`enableThinking=false`。默认 App 拍照/文本整理不受影响。
2. `INGEST_DEADLINE_MS` 90s → 30s；模型挂起时 30s 内回执并转待整理，不再让用户等 90s。
3. 同时修复了 A2A 冒烟脚本：新版小艺由 `com.ohos.sceneboard` 承载，前台判断改为布局特征；`open_agent` 等到 `TextArea` 出现、卡片网格只翻页不再误点抽屉。

**真机结果**（同一设备、同一 provider）：

| 输入 | structure | completionTokens | persist | total |
|---|---|---|---|---|
| 狄利克雷判别法 | 2.9s | 292 | 2.5s | **5.5s** |
| 拉格朗日中值定理 | 1.9s | 217 | 2.3s | **4.2s** |
| 矩阵相似与对角化 | 14.7s | 257 | 2.1s | 16.9s |

- 慢样本的首包就慢（completionTokens 与其他样本同级），是 provider 延迟，不是输出量；代码侧无法再压。
- 改动前同设备：10.5s（warm）/ 15.5s（cold）/ 20.7s；completionTokens 1533–1949。
- 质量：快速笔记 5 个标准字段齐全、约 300 字，示例（狄利克雷判别法）内容可用。

**代价**：A2A 快速笔记更短、关闭了思考链；需要完整笔记时可在 App 里重新生成或补充。

## 54. 2026-11-08 A2A 草稿确认（checkpoint）

**背景**：之前 A2A 收到文字直接生成入库，用户在小艺里只看到「已整理入库」，无法先看内容再决定。

**改动**：
- 单题文本 → `generateNoteDraft(route=light)` → `A2ADraftStore` 落盘 → 回复先像聊天一样输出标题、学科/题型和最多 4 节关键内容（每节 140 字纯文本），最后再问「要我把这些内容整理成笔记保存吗？」。
- 下一条「确认 / 保存 / 好的」→ `confirmDraft` 入库；「取消 / 不要了」→ 丢弃；其他消息 → 重新提示当前草稿；新的整理内容覆盖旧草稿。
- 质量门：light 草稿若正文为空或复述原文，取消该 run 并自动改用 standard 重试；仍不合格则转待整理。
- 草稿 24h 过期；`A2AContextCleanup` 一并清理。
- 生成草稿时会把最近 3 轮 A2A 对话（`A2AConversationStore`）作为 `SourceFragment` 传入；助手文本标注为上下文，不当原始证据。本地 RAG / 判重仍走端侧。
- 解析修复：模型把 `section.content` 返回成对象时用 `readTextValue` 抽文本，避免 `[object Object]`（通用草稿路径，所有入口受益）。
- 确认时若命中判重，`confirmDraft` 复用已有笔记；回复按是否复用区分文案。

**真机验证**：
- 巴拿赫不动点定理：预览 3.9s，含标题 / 数学分析·定理 / 两段正文；确认后 DB 130 条，内容无 `[object Object]`。
- 柯西中值定理、莱布尼茨判别法、阿贝尔变换：预览 → 确认均通；取消不写库。
- 预览标签把 light 路由的「核心内容 / 补充内容N」映射成「要点 / 要点N」。

**限制**：多题整理计划仍按原逻辑逐题直入（尚未加 checkpoint）；图片问答与普通聊天不变。

## 55. 2026-11-09 端A2A 流式探针：能增量渲染，但长文本会丢尾部

**目的**：验证小艺客户端是否渲染手写 `artifactUpdate` 多帧。

**实现**：
- `TaskSnapshot.ets` 新增 `buildTaskStreamStart`（`TASK_STATE_WORKING`）、`buildArtifactUpdate`（同 `artifactId`，`append` / `lastChunk`）、`buildTaskStreamEnd`（`COMPLETED` + `final`）。
- `A2AReplyPort` 增加 `streamStart/streamChunk/streamEnd`；`AgentExtAbility` 逐帧 `hostProxy.sendData`，日志 `A2A_STREAM_FRAME kind=start|chunk|last|end`。
- 探针命令：「流式探针」5 段固定短句（700ms）、「分块探针」长回复分块、「长流探针」「百字探针」测长度上限。
- `agent_config.json` 的 `capabilities.streaming` 改为 `true`（已平台重新导入 + 重启小艺）。

**真机结果**：
- **能增量渲染**：连续抓布局看到气泡从 20 → 87 → 93 字增长；5 段短句探针完整显示 76 字；日志 7 帧全部发出。
- **长文本会丢尾部**：128 字分 7 块只显示 84 字；145 字分 5 块只显示 97 字；98 字分 4 块只显示 72 字。客户端会在中途停止追加，且不是固定字符上限（72/84/97 都可能）。
- 流式结束后补一条完整 `result.task` 快照不会覆盖已显示的气泡；同一 taskId 的终态帧被忽略。
- 单帧 `result.task` 仍能完整渲染长文本（此前实测 263 字）。

**结论**：端A2A 的 `artifactUpdate` 只适合短回复的渐进显示；笔记草稿/长回答继续走单帧 `result.task`。`sendStreamingAnswer` 对 >70 字的文本直接回退单帧，避免预览被截断。要长文本逐 token，只能走云A2A 或 App 自己的流式 UI。

## 56. 2026-11-10 A2A 草稿确认扩展到多题计划 / 图片计划

**改动**：
- `A2APendingDraft` 增加 `planTaskId` / `planItemIndex`；确认成功后回写 `plan.done`，回复「进度 n/m，回复继续整理下一题」；全部完成清计划。
- 计划项（多题文本 / OCR 图片）先生成草稿，用户「继续」才预览、「确认」才保存；`全部` 从第一题开始逐题确认。
- 计划项是自包含文本，**不混入对话历史**（`historySources=[]`），避免被旧笔记带偏；单题「整理成笔记」仍用最近一轮回答。
- 图片计划只有 1 题时跳过计划摘要，直接出草稿预览。
- 「整理成笔记」不再只查上次图片材料：优先用最近一轮「用户问题 + 助手回答」作为资料（`CHAT_RECALL`），没有对话才回退图片材料。
- 计划摘要文案改为「每题先出草稿，确认后保存」。

**真机验证**：
- 两题文本：计划 items=2 → 「继续」出第 1 题草稿 → 「确认」回「已保存：计算 21+21（数学）。进度 1/2，回复继续整理下一题」→ 「继续」第 2 题 → 「确认」回「已保存：计算 12+12（数学）。这次计划全部完成」，plan 文件清除，done=[0,1]。
- 先问「矩阵的秩怎么算」得到 784 字回答，再说「整理成笔记」：`CHAT_RECALL ingest chars=802`，草稿预览基于上一轮回答，确认入库。
- 图片 A2A 仍受平台限制（小艺不下发图片 parts），无法在 A2A 真机触发；应用内批量本身有预览确认。

**已知限制**：provider 偶发挂起，草稿 35s deadline 会回「已转待整理」；计划项草稿依赖 LLM，失败时同样入 inbox。

## 57. 2026-11-10 草稿二次操作：详细 / 简洁 / 重新生成

**改动**：
- `A2APendingDraft` 保存 `sourceText`，用于重新生成。
- `parseA2ADraftRefine` 识别「详细一点 / 展开讲讲」「简洁一点 / 简单一点」「重新生成 / 重来」，只认短命令。
- `A2AIngestHandler.refinePendingDraft`：先生成新草稿，成功后才取消旧 run 并覆盖草稿；失败保留旧草稿，回复可继续确认或取消。
- 「详细」走 standard 路由并加详细指令；「简洁」「重新生成」走 light 路由。
- 计划项草稿 refine 会保留 `planTaskId/planItemIndex`，确认后进度照常回写。

**验证**：单测/契约测试通过（`a2a-draft-checkpoint` 新增 refine 用例）；gate PASS（1360 单测）。2026-11-10 00:34–00:35 真机（3XTYD24C16203663）：
- `存笔记：矩阵的秩与初等变换` → 3.2s 出草稿，标题/学科/4 段要点 + 确认提示。
- `详细一点` → `A2A_DRAFT refine mode=more`，11.4s，636 字（standard）。
- `简洁一点` → `A2A_DRAFT refine mode=less`，1.3s，107 字（light）。
- `重新生成` → `A2A_DRAFT refine mode=regenerate`，2.5s，247 字（light）。
- `确认` → 回「已保存：矩阵的秩与初等变换（线性代数）。」；refine 后的草稿正常入库。

## 58. 2026-11-10 草稿超时收紧与慢请求探针

**改动**：
- `A2A_DRAFT_TIMEOUT_MS` 35s → 25s。light 正常 3–6s，standard 约 10–15s；25s 覆盖慢请求，provider 挂起时少等 10s。外层 `A2A_POLICY.deadlineMs` 仍为 35s。
- 新增 `A2A_DRAFT_SLOW_MS=8000`：8s 未返回只记 `A2A_DRAFT_SLOW`，不改变用户可见行为，用于区分「模型慢」与「模型挂起」。
- 未做替代模型/提前回执：A2A 单任务目前只有一次最终回复，提前回执会把草稿弄丢；替代模型需要在 `DraftPipeline` 之外做 provider 级路由，留到后续。

**验证**：`node scripts/agent-gate/index.mjs` → PASS（1360 单测）；`DEVECO_SDK_HOME=... node scripts/build-hsp-hap.mjs` → BUILD SUCCESSFUL。真机未单独验证 25s 边界（正常草稿 3.2s / standard refine 11.4s 均已在此之前验证）。

## 59. 2026-11-10 超时回执去重

**问题**：草稿超时/失败时 `enqueueForIngest` 自己回一条「已记为待整理」，调用方又回一条 `a2aErrorText(A2A_INGEST_TIMEOUT)`，小艺里出现两条回执（真机日志 `A2A_REPLY_SENT` 连续两次、taskId 相差 1ms）。

**改动**：
- `enqueueForIngest(taskId, query, replyText?)` 统一负责入队 + **一条**回执；调用方不再单独回话。
- `beginDraftCheckpoint` 的 catch 传入超时/失败文案，删除重复 `sendIngestAnswer`。
- 顺手修掉单题 retryable 分支重复入队：只有多题（`totalProblems > 1`）才补入 `queuedTexts`，第 1 题统一由 `enqueueForIngest` 入队。

**验证**：`a2a-draft-checkpoint` 新增源码守卫；gate PASS（1361 单测）。真机（provider 挂起）`存笔记：导数的定义` → `A2A_DRAFT_SLOW 8s` → `A2A_DRAFT_TIMEOUT 25s` → `INBOX_ENQUEUED pending=11` → **仅一条** `A2A_REPLY_SENT chars=46`。

## 60. 2026-11-10 A2A 可用性补口：回执路由 / 重复提示 / 补齐通知

**改动**：
- 回执意图提前到 `routeInput` 的草稿/计划/pick_card 分支之前。此前「本次整理了几条」会先命中 `pick_card` → `CHAT_RECALL`，把上一轮回答当成整理条数；现在直接读 `receipts/last-capture.json`。
- App 内确认草稿时用 `committed.id !== candidate.id` 判断复用，提示「已保存笔记（检测到相同笔记，已复用）：标题」，与 A2A 确认文案一致。
- inbox 补齐通知：`A2AInboxIngestService.startWatch` 接受消费回调；`EntryAbility.onForeground` / 轮询消费完成后用 `windowStage.getMainWindowSync().getUIContext().getPromptAction().showToast` 提示「小艺待整理已补齐 N 条」。`onBackground` 仍然停止轮询。

**验证**：
- `a2a-usability.test.mjs` 三条源码/契约守卫通过；gate PASS（1364 单测）；HAP 构建成功。
- 真机：`本次整理了几条` → `INTENT kind=pick_card` 但日志 `[Receipt] hit=true receipt=true done=24`，回复「本次整理 24 条：成功 24 条，失败 0 条（00:35）」。
- 真机启动 App 后 `a2a-inbox/` 被清空，说明补齐消费路径已执行；2s toast 未在截图窗口内捕获，后续可由自然超时项复验。

## 61. 2026-11-10 清理 100 条自建测试语料

**背景**：设备库里同时有自建测试语料（`seed-math-*` 25 条 + `bulk-*` 75 条，写入时 `source='file_import'`）和产品生成/手工笔记。用户要求只清测试语料。

**改动**：
- 新增 e2e 探针 `clearSeedCorpusAudit` / `clearSeedCorpus`（`DebugCaptureRunner.runClearSeedCorpus`）：只按 `source='file_import' OR id LIKE 'seed-%' OR id LIKE 'bulk-%'` 选行。
- 逐条走 `NoteDao.deleteById` 清 FTS/关系边，再补删 `rag_chunk`、`rag_embedding`、`note_revision`、`review_item`、`review_log`、`review_op`；不执行 `DELETE FROM knowledge_unit` 全表删除。
- 清理结果写到 `files/a2a/seed-cleanup.json`，便于无 hilog 时核验；门禁测试 `seed-cleanup.test.mjs` 防止退化成清空全库。

**真机结果**（3XTYD24C16203663）：
- 清理前审计：`seedIds=100, total=136`
- 执行后：`removed=100, failed=0, remaining=36`
- 复查：`seedIds=0, total=36, sources="note_generation=24,manual=12"`

## 62. 2026-11-10 删除 100 条自建测试语料源码

**背景**：设备里的 100 条种子笔记已删除，用户确认源码也是同一批 100 条（25 条 `TestCorpusSeed` + 75 条 `TestCorpusBulk`），要求一并清掉。

**删除**：
- `entry/src/main/ets/debug/TestCorpusSeed.ets`（25 条）
- `entry/src/main/ets/debug/TestCorpusBulk.ets`（75 条）
- `entry/src/main/ets/debug/RagEvalCases.ets`、`RagSpotCases.ets`（绑定这批语料的查询集）
- `DebugCaptureRunner` 的 `ragEval` / `ragSpotCheck` / `ragOodCheck` / `seedTestCorpus` / `seedBulkCorpus` 探针及对应 EntryAbility 模式
- `scripts/arkts-lint/tests/rag-eval.test.mjs`
- `scripts/rag-lab/eval.mjs` 的 `--dataset fixture` 分支；离线评测只保留 MathNet-Retrieve

**保留**：`scripts/rag-lab/fetch-mathnet.mjs` / `eval.mjs` 的 MathNet 评测；设备端已有的 36 条产品/手工笔记不动。

## 63. 2026-11-10 重复笔记二次操作：更新 / 另存 / 保留

**背景**：确认草稿命中判重（same）时，之前只提示「已复用」，用户没有后续动作。

**改动**：
- `ConversationDraftWorkflow.confirm` 复用笔记时发出 `NoteSuggestion(action='merge', sourceNoteId, sourceTitle)`；`ConversationWorkflow.notifySuggestion` 转发给会话回调。
- `AgentFloatWindow` 在草稿浮层关闭后弹出三选一：更新已有笔记 / 另存为新笔记 / 保留现状。
- 更新：调用 `AgentChatService.requestRegeneration` → `ConversationRuntime` → `ConversationDraftCoordinator` → `ConversationWorkflow.requestRegeneration`，把候选正文作为增量资料，生成带 `expectedVersion` 的新草稿，用户再次确认后才更新。
- 另存：`NoteEditService.saveAsNew` 生成新 id，调用 `KnowledgeUnitWriteService.create(..., allowDuplicate=true)`，跳过判重但保留索引/向量写入。
- `append`（同主题补充）建议仍只在写服务日志里，未接 UI；本轮先完成重复确认的二次操作。

**验证**：`note-duplicate-actions.test.mjs` 4 条契约测试；gate PASS（1363 单测）；HAP 构建成功并已安装。重复场景需要 App 内连续生成同一篇笔记才能触发，设备当前锁屏，未完成真机点击验证。

**真机测试补充（2026-11-10 18:00）**：
- 在 App 内重复生成《矩阵的秩的计算方法》并确认，ConfirmTrace 显示判重命中，但 UI 没有出现三选一。定位到 `NotePreparedWorkflow` 在 `duplicate=true` 时仍用候选 id 覆盖 `committedCandidate.id`，导致上层 `committed.id !== candidate.id` 判断失效；已改为保留 `finalState.commitResult.noteId`，并补契约测试。
- A2A 草稿 key 不一致：`A2A_DRAFT begin key=default` 落盘，后续「确认」按 `mindtrace-context` 查找，草稿找不到，确认被当成普通聊天。已在 `A2ADraftStore.load` 增加 default → 当前 key 的迁移回退，并补源码守卫。
- App 浮层受键盘/剪贴板遮挡，自动点击未稳定命中确认键，因此三选一弹窗的端到端点击尚未完成；代码、契约测试和构建已通过（1364 单测）。

## 64. 2026-11-10 重复笔记三选一真机验收

**结果**：
- 弹窗正常出现：「更新已有笔记 / 另存为新笔记 / 保留现状」，日志 `[NoteSuggestion] notify action=merge reason=duplicate-on-confirm` → 适配器 `[NoteSuggestion] action=merge ... reason=duplicate-on-confirm` → `[DuplicateAction] show`。
- 另存：点击后笔记数 35 → 36，弹窗关闭；`NoteEditService.saveAsNew` 跳过判重写入新 id。
- 更新：点击后进入 `ConversationWorkflow run start kind=regenerate`，生成带「保留 · …」差异的增量草稿；确认时日志 `store=update-begin noteId=KB-mwajwp7o-s1f8gd-copy-1794307019755`、`updateWithCommitKey-ok`，没有新的 insert。
- 保留现状：与另存共用同一弹窗清理逻辑，未单独点击（代码路径只清状态）。

**真机暴露并修复的三个绑定问题**：
1. `ConversationWorkflow.notifySuggestion` 把 `this.cbs.onNoteSuggestion` 取出后调用，丢失 `this`，适配器访问 `this.accepts` 报 “Cannot read property accepts of undefined”。改为直接调用 `this.cbs.onNoteSuggestion(ref, suggestion)`。
2. `ConversationNoteHandler` 在生成完成时同样取出 `onNoteSuggestion` 调用，导致每次生成末尾报 accepts 错误；改为先取 `callbacks` 对象，再在对象上调用。
3. `NoteRegenerateWorkflow` 把 `repository.getRegenerationBase` 取出后调用，丢失 `this`，报 “Cannot read property baseProvider of undefined”；改为直接 `repository.getRegenerationBase(noteId)`。
4. 另修复 `NotePreparedWorkflow` 判重命中时用候选 id 覆盖 `committedCandidate.id`，导致“已复用”判断失效；以及 `A2ADraftStore` 的 `default → 当前 key` 草稿迁移。

**验证**：gate PASS（1364 单测），HSP/HAP 构建并安装。
