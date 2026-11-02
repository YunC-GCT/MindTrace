# Agent 框架与产品分层 — 交接 / Review 文档（2026-11-02）

> 读者：Claude（外部 review）。目标：用 15 分钟判断「Agent 编排框架」和「产品分层」当前是否合理、哪里是债、下一步该先做什么。
> 仓库：HarmonyOS 数学学习助手 MindTrace（ArkTS 1.1 严格模式）；当前分支 `develop`；最新提交 `9e489fb2`。
> 本文只写**已验证事实**；未验证/平台受限项明确标注。

---

## 0. 先看结论（TL;DR）

1. Agent 编排已完成 **workflow-first 收口**：`CommandExecutor`（统一入口）→ `CommandRouter`（preflight+路由）→ 四条 workflow（capture / generation / regenerate / prepared）；旧的 `DispatchGraph` / `CaptureBranch` / `NoteAgent` 已删除（spec 039）。
2. 写入链路做了**双 lane 调度器 + 持久队列 + 跨进程 handoff**：`WriteJobScheduler`（interactive/background 双 lane、并发上限）→ `WriteJobPersistence` hooks → `agent_job` 表（schema v20）→ 启动恢复/租约；flag 已灰度打开（spec 038 / 040 / ADR-0024）。
3. App 与 A2A 两条入口**共用同一编排**：都经 `CapturePipeline → CommandExecutor → workflow → NoteDao`，没有第二套笔记写入逻辑。
4. 端A2A（小艺）侧：文本整理真机通；**图片入站是平台能力缺口**——小艺客户端不下发 image part（也不下发识别文字），应用侧无法拿到图片；卡片/App 跳转方案已按用户要求移除，当前纯文本引导（详见 §6）。
5. 需要 review 的高风险点：**双进程共享 SQLite 写入**、**A2A 内联整理绕过调度器**（有意例外）、**Chat/ToolLoop 尚未并入 workflow 框架**、**A2A UX/错误语义**。

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
  - **`:agent` 进程**：`AgentExtAbility`（小艺端A2A，手写 JSON-RPC 单帧快照）→ IntentRouter → text/OCR/chat 处理；自己 `DatabaseHelper.init`，可内联写库。
  - **agentUI 卡片**：`AgentUIExtAbility`（半屏卡片）与 agent 同进程；当前 A2A 回复已不再发卡片，代码保留为 dormant 能力（见 §6）。

---

## 2. Agent 框架分层（review 重点）

### 2.1 分层图

```
入口适配层
  ├─ UI:        pages/ + viewmodels/            (用户操作)
  ├─ A2A:       entry/agentextability/AgentExtAbility.ets
  └─ 调度:      entry/services/WriteJobScheduler.ets  (App 写路径)

编排层（agents module）
  ├─ agents/core/CommandExecutor.ets   dispatchCommand / dispatchSetCommand
  ├─ agents/core/CommandRouter.ets     preflight(审批哈希/取消) + resolve(kind)→workflow
  ├─ agents/workflows/WorkflowContext.ets
  ├─ agents/workflows/NoteCaptureWorkflow.ets
  ├─ agents/workflows/NoteGenerationWorkflow.ets
  ├─ agents/workflows/NoteRegenerateWorkflow.ets
  ├─ agents/workflows/NotePreparedWorkflow.ets
  ├─ agents/core/dispatch/*            Generation/Incremental/Prepared branch + Evaluator/Mapper/Sink
  └─ agents/graph/CaptureGraph.ets     capture 子图（Classify/Structure/TruthCheck/Persist/Ocr 节点）

领域 / 数据层（common）
  ├─ common NoteCommand / NoteOutcome（ADR-0019）
  ├─ common/workflow 内核（LangGraph 模型，ADR-0008：无 runtime checkpoint / 无图内 HITL）
  ├─ common DatabaseHelper（schema v20）
  └─ DAO：NoteDao / RunStoreDao / AgentJobDao / 各 generation/log 表
```

关键点：
- **只有一个编排入口**：`CommandExecutor.dispatchCommand(NoteCommand, DispatchOptions)`；`NoteCommand` 是 5 类判别联合（capture / generation / regenerate / preparedCandidate / analysisOnly），`NoteOutcome` 是 5 类终态。
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
小艺 → AgentExtAbility.onData → A2AIntentRouter（text_ingest / image_qa / ocr / …）
  → AgentIngestService.ingestTextBatch → AiService.ingestTextOutcome
  → CapturePipeline → CommandExecutor → 同 A
  → sendAnswer("已整理入库：…")
```
> 真机证据：`ok=true`，回复 `已整理入库：计算12减4乘2的值并写出运算顺序（初中数学）· 本次整理 1 条`；hilog `INTENT text_ingest → TEXT_PLAN → INGEST_TEXT done`。

**C. 写入调度 / 持久化（spec 038+040）**
```
写入调用方 → WriteJobScheduler.submit(priority,text,executor)
  ├─ flag 关：内存双 lane 队列（AsyncSemaphore/AsyncMutex + 写段串行）
  └─ flag 开：WriteJobPersistence.enqueue → AgentJobDao(agent_job) → claim(租约) → executor → finish(终态)
            启动：WriteJobBootstrap → recoverAllRunning(孤儿) + recover(queued) → submitRecovered
            跨进程：WriteJobProducer（:agent 扩展只入队）
```

---

## 3. 产品分层（UI → 数据）

| 层 | 位置 | 职责 | 约束 |
|---|---|---|---|
| UI | `entry/src/main/ets/pages/`, `overlays/` | 渲染、手势、动效 | 不直接 import CaptureGraph/CommandExecutor/NoteDao |
| ViewModel | `entry/src/main/ets/viewmodels/` | UI state、用户意图、调用 service | 不持 RDB 句柄 |
| Business Service | `entry/src/main/ets/services/` | 编排、AI、笔记生成、检索、A2A 适配 | 不持 UI 引用；写路径统一走 CapturePipeline/CommandExecutor |
| Agent 编排 | `agents/` | CommandExecutor/Router/workflows/Graph | 只依赖 common；不 import entry |
| 共享契约/数据 | `common/` | NoteCommand/Outcome、workflow 内核、DB/RDB、LLM 客户端 | 受限 Kit 不得经 barrel 进 :agent 进程 |
| 扩展 | `skill/`, `cardservice/` | 小艺 skill / 桌面卡片 | 不新建 module |

产品域当前闭环：capture（拍照/相册/文字/A2A）→ 结构化 → 生成 → 持久化（note_revision / note_generation_* / RunStore）→ 详情/复习/RAG/知识星系；后台写路径由 scheduler 限流与串行化。

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

| # | 问题 | 说明 / 影响 | 当前处理 |
|---|---|---|---|
| R1 | **双进程共享 SQLite** | UI 进程与 `:agent` 扩展进程都初始化 DB、都可能写笔记；单执行者假定（UI 进程调度器）被 A2A 内联整理打破 | A2A 单题整理在扩展内联执行（有意例外，ADR-0024 §2.7 记录）；事件写入加 mutex/缓冲规避锁；reviewer 判断是否需要“扩展也只入队” |
| R2 | **A2A 内联整理绕过调度器** | 不经过 WriteJobScheduler 的 lane/租约；若同时 App 大量写入，可能竞争 | 评估：A2A 走 scheduler.submit 是否更一致（代价：需 App/扩展 executor 协议） |
| R3 | **端A2A 图片能力缺口** | 小艺客户端不下发 image part/识别文字；应用侧无解 | 已调研+提单草稿；图片链路只能 云A2A / 等平台；当前纯文本引导 |
| R4 | UI 卡片残留历史 | 旧会话里的 `uiExtensionCard` 可能触发客户端重试/转圈；新会话无卡片 | 代码已移除卡片回复；旧对话框建议新建 |
| R5 | **Chat/ToolLoop 未并入 workflow** | Chat 仍走旧 ToolLoop/ReplyService；Agents 编排只覆盖笔记写入 | spec 039 S4 留待 spec 041；reviewer 判断优先级 |
| R6 | A2A 会话记忆/图片材料是文件存储 | `A2AConversationStore` / `A2AImageContextStore` 按 contextId 存文件；未进 DB，无清理策略 | 可用；reviewer 判断是否要并 run_store |
| R7 | 事件表保留策略缺失 | `run_store/run_event/agent_job` 无 retention/清理 | 已知；低优先级 |
| R8 | A2A 错误/超时语义 | 35s deadline、配置超时、单帧快照；用户侧提示分散 | 可做统一 A2A error taxonomy |

---

## 7. 请 Claude 重点回答的 6 个问题

1. **分层**：`CommandExecutor/Router/4 workflows` 放 `agents` HSP、`CapturePipeline` 放 `entry/services/ai`，边界是否合理？是否应把 CapturePipeline 也上移到 agents，避免“入口适配层依赖编排层”倒置？
2. **写路径一致性**：A2A 内联整理是否应统一走 `WriteJobScheduler.submit`（多执行者 + claim 租约），而不是扩展进程直写？若统一，如何避免 35s 预算与调度等待冲突？
3. **进程模型**：UI 进程单写者（ADR-0024）与扩展内联写（R1/R2）目前并存；长期应选哪种？是否需要扩展侧只入队 + 前台补偿？
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
| 小艺 A2A 入口 | `entry/src/main/ets/agentextability/AgentExtAbility.ets` |
| A2A 意图/记忆 | `A2AIntentRouter.ets` / `A2AConversationStore.ets` / `A2AImageContextStore.ets` |
| 分析/证据 | `docs/specs/038-*.md`、`039-*.md`、`040-*.md`；`docs/research/a2a-image-*` |
| 进度唯一口径 | `docs/agents/phase-tracker.md` |

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
