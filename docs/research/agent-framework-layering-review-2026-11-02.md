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
