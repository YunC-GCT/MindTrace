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
