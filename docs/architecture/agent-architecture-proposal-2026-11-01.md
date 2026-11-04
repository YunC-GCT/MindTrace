# Agent 架构重构提案：workflow-first 目标架构（2026-11-01）

> **Status**: proposed (2026-11-01)
> **Related**: [ADR-0008](../adr/0008-capturegraph-self-built-runtime.md) · [ADR-0019](../adr/0019-note-command-and-outcome.md) · [ADR-0021](../adr/0021-shared-read-port-implementation-in-common.md) · [spec 018](../specs/018-agent-workflow-architecture.md) · [spec 038](../specs/038-write-job-scheduler.md) · [v7 外评审](./review-v7-2026-10-27.md)
> **Code**: `agents/src/main/ets/core/Dispatcher.ets` · `agents/src/main/ets/core/dispatch/DispatchGraph.ets` · `agents/src/main/ets/subagents/NoteAgent.ets` · `common/src/main/ets/workflow/StateGraph.ets` · `entry/src/main/ets/services/ai/RunStoreEventSink.ets` · `entry/src/main/ets/services/WriteJobScheduler.ets`
> **Verified by**: 现状基线 `node scripts/agent-gate/index.mjs` → `RESULT: PASS`（pass=1165，0 lint error）；本提案尚未实现，实施证据待各切片补齐

## 1. 结论

**问题不是「分层不够」，而是「Agent 的名与实不符」。**

现状是**确定性流水线**（OCR → 分类 → 结构化 → 校验 → 落库）套了一层 LangGraph 风格外壳：六阶段主图里 `route` / `hitl` 是空实现，分支选择埋在 `invoke`；`NoteAgent` 只被 `CaptureBranch` 当函数调；`ToolLoop` 生产零引用；没有 checkpoint/interrupt。这层壳增加认知税，却没有增加能力。

**建议改造，但不重写。** 目标架构是 workflow-first：

1. 删掉通用六阶段主图，用「**命令执行器 + 命令路由**」替代；
2. 每个 `NoteCommand.kind` 一条自己的 workflow 图，跨切面（run、预算、事件、错误映射）由执行器统一做；
3. **只有对话需要 agent 回路**（LLM 决定调不调工具）；笔记域是 workflow，不是 agent；
4. 观测补到 node/tool/approval/commit 级，runId 贯通；
5. 遵守 [ADR-0008](../adr/0008-capturegraph-self-built-runtime.md)：**不做 runtime checkpoint、不做图内 HITL**，checkpoint 留在业务级（草稿/审批）。

实施 spec：[`039-agent-workflow-first.md`](../specs/039-agent-workflow-first.md)（S1–S3 + golden 零重录判据；S4 另立 spec 040）。

代价估计 **约 4–6 人日**（Slice 0–3，一人熟 ArkTS）；不改协议、不改数据模型、不动 golden 语义。

---

## 2. 现状复盘（三个硬事实）

| 事实 | 证据 | 影响 |
|---|---|---|
| 没有 LLM 路由 / 规划 | `Dispatcher.dispatchCommand` 按 `NoteCommand.kind` 硬分派；`route` 直接 `{ next: 'invoke' }` | 「Agent 主图」实际是命令分派器 |
| 生产没有 agent 回路 | `ToolLoop` 只在 `common/src/test/LlmToolCalling.test.ets` 被构造；`NoteEvidenceService` 直接 `ToolRegistry.execute` | 工具是确定性调用，不是 ReAct |
| 没有可恢复执行 | `StateGraph` 103 行串行执行器，无 checkpoint；HITL 在图外（三次独立调用） | 长任务只能靠重试，不能续跑 |

另外两处结构冗余：

- **五层调用**：`DispatchGraph → invoke → CaptureBranch → NoteAgent → CaptureGraph → StateGraph → 节点`；
- **空阶段**：`route`、`hitl` 无行为；`verify` 只校验 committed 信封；真正有行为的是 `preflight` / `invoke` / `publish`。

---

## 3. 设计原则

1. **Workflow-first**：确定性任务用图（节点 = 纯函数 + 注入能力），**不要**为了「像 Agent」加规划层。[Anthropic 的 workflows vs agents 区分](https://www.anthropic.com/research/building-effective-agents)：能固定路径就别让模型决定路径。
2. **一个 Runtime**：`StateGraph` + `RunContext` 是唯一执行内核；不新增第二套调度器（ADR-0008）。
3. **一个写入口**：所有写操作收口到 `NoteCommand → CommandRouter`；UI、A2A、skill、chat 都只投命令。
4. **接缝在端口**：能力在 `common`，平台/存储在 `entry`；workflow 只依赖端口 DTO（ADR-0021）。
5. **观测是契约**：事件 schema 与 `NoteOutcome` 一样是稳定契约，先定 schema 再加节点。
6. **不建死代码**：没有第二个消费者就不建通用能力（ADR-0008「no dead scaffolding」）。
7. **进程薄**：`:agent` 扩展进程只做协议 adapter；编排逻辑只存在一份。

---

## 4. 目标分层

```
┌─ L1 入口 ──────────────────────────────────────────────────────────────┐
│ 应用内：拍照/选图 · 对话浮窗 · 卡片(只读)   小艺 A2A(:agent)   skill/cardservice │
└───────────────┬───────────────────────────────┬────────────────────────┘
                │ NoteCommand                    │ A2A adapter → NoteCommand
┌─ L2 编排(agents) ──────────────────────────────────────────────────────┐
│ CommandExecutor（run 作用域/预算/事件/错误映射）                          │
│        └→ CommandRouter（按 kind 选 workflow，无业务逻辑）                │
│              ├→ NoteCaptureWorkflow    capture / captureSet             │
│              ├→ NoteGenerationWorkflow generation(light/standard/deep)  │
│              ├→ NoteRegenerateWorkflow regenerate(range)                │
│              └→ NotePreparedWorkflow   preparedCandidate(hash) → commit │
│ entry/workflows/conversation/ChatWorkflow（对话回路，含 ToolLoop）         │
└───────────────┬─────────────────────────────────────────────────────────┘
┌─ L3 能力(common) ───────────────────────────────────────────────────────┐
│ LlmClient/LlmGuard · OCR 端口 · RAG 检索(FTS5) · ToolRegistry/ToolLoop    │
└───────────────┬─────────────────────────────────────────────────────────┘
┌─ L4 数据 ───────────────────────────────────────────────────────────────┐
│ common/ports（8 个）← entry adapters/DAO/RDB；run_store/run_event         │
└───────────────┬─────────────────────────────────────────────────────────┘
┌─ L5 观测 ───────────────────────────────────────────────────────────────┐
│ EventSink → run_event · hilog 分段 · scheduler-report · trace 查询        │
└──────────────────────────────────────────────────────────────────────────┘
```

与现状的差别只在 L2：**主图消失，命令路由 + 每命令一条 workflow**。L1/L3/L4/L5 基本不动。

---

## 5. 运行时契约（common/workflow）

| 契约 | 现状 | 目标 | 动作 |
|---|---|---|---|
| `StateGraph` | 串行执行、条件边、预算 | 保留 | 不改 |
| `RunContext` | runId/parentRunId/deadline/budget/token | 保留，**强制**所有 workflow 必须带 | 接线补齐 |
| `RunScope` | 无 | 新建：统一创建 run、发 `run.started`、兜底 `run.terminal`、透传父 run | 新增（薄） |
| `EventSink` | 只有 `dispatch.start/terminal` | 扩展为 node/tool/approval/commit 事件，schema 见 §8 | 扩展 |
| `SubgraphNode` | 无（ADR-0008 允许子图作节点） | **暂不实现**：当前无第二个消费者（ReviewWorkflow 出现时再落） | 不做 |
| Checkpoint | 业务级（草稿/审批） | 保持业务级；runtime checkpoint 需新 ADR | 不做 |
| HITL | 图外三次调用 | 保持图外：`readyPreview → 确认命令 → preparedCandidate` | 不做 |

> 「子图即节点」之前的 v7 计划要做的能力，在本提案里被**主动降级**：它是为了满足「Agent 图」的形态，而不是当前需求。等 ReviewAgent 真的复用时再加，符合 ADR-0008 的非目标条款。

---

## 6. 编排层：执行器 + 路由 + 四条 workflow

### 6.1 职责切分

| 组件 | 职责 | 不做什么 |
|---|---|---|
| `CommandExecutor` | 建 run、解析/透传 `RunContext`、发 run 事件、调 workflow、把异常映射成 `NoteOutcome` | 不碰业务分支、不碰 DAO |
| `CommandRouter` | 按 `NoteCommand.kind` 选 workflow；命令形状校验（preflight） | 不执行节点、不做写 |
| `NoteCaptureWorkflow` | capture / captureSet：`ocr → classify → structure → truth_check → persist` | 不装配 dispatch、不写 run 事件 |
| `NoteGenerationWorkflow` | generation 三档 + verify + readyPreview | 不落库（由 prepared commit 落） |
| `NoteRegenerateWorkflow` | regenerate(range)：版本冲突、章节锁 | 不复用 capture 节点 |
| `NotePreparedWorkflow` | hash/checkpoint 校验 → commit → 投影 | 不生成 |
| `ChatWorkflow`（entry） | 意图分类 → 证据检索 → ToolLoop（只读工具）→ 回复；写意图转命令 | 不直接写库 |

### 6.2 为什么删掉六阶段主图

- `route` 空、`hitl` 空、`verify` 只校验信封 → 六阶段名不副实；
- 阶段语义已经在四个 workflow 里各自成立（capture 的 verify = truth_check；generation 的 verify = 校验/评估）；
- 跨切面（预算、取消、事件）**应该**由执行器统一做——这比「一张万能图」更少认知负担，也更符合 LangGraph 的做法（每个 graph 自己的节点集）。

保留的能力：`DispatchGraph` 里的 **阶段校验思路** 移到 `CommandRouter` 的 preflight（命令形状 + 取消 + 审批哈希）。

### 6.3 路由表

| command.kind | workflow | 终态 |
|---|---|---|
| `capture`（含 captureSet） | NoteCaptureWorkflow | committed / readyPreview / needsInput / failed / cancelled |
| `generation` | NoteGenerationWorkflow | readyPreview（或 failed/needsInput） |
| `regenerate` | NoteRegenerateWorkflow | readyPreview / failed |
| `preparedCandidate` | NotePreparedWorkflow | committed / failed |
| `analysisOnly` | NoteCaptureWorkflow（persist=false） | committed（仅分析产物） |
| 对话 / 问句 | ChatWorkflow（不产生 NoteCommand） | — |

---

## 7. Agent 回路（只给对话）

对话是唯一「模型决定下一步」的地方，也是 `ToolLoop` 唯一该上岗的地方。

```
classify_intent ─→ (write intent?) ──yes──→ CommandRouter（chat 不写库）
       │
       no
       ▼
retrieve_evidence（RAG/FTS5 + 旧笔记证据）
       ▼
tool_loop（只读工具：note_query / note_get / review_due；maxSteps=4，预算/取消走 RunContext）
       ▼
compose_reply（LlmClient 流式；引用校验）
```

硬约束：

- loop 内**只读**；任何写意图必须退出 loop，转成 `NoteCommand`；
- loop 的每一步发 `tool.called/tool.result` 事件；
- `ToolLoop` 若在本切片内不接，就**删掉**（当前生产零引用，留着是死代码）。

---

## 8. 观测：事件 schema

| kind | 关键字段 | 写入 |
|---|---|---|
| `run.started` | runId, parentRunId, commandKind, source | run_store + run_event |
| `run.terminal` | runId, outcome.kind, durationMs, code | run_store.status + run_event |
| `node.started` / `node.ended` | runId, node, durationMs, status | run_event |
| `tool.called` / `tool.result` | runId, tool, durationMs, ok, errorCode | run_event |
| `approval.requested` / `approval.granted` | runId/checkpointId/hash | run_event |
| `commit.started` / `commit.committed` | noteId, version, commitKey | run_event |
| `projection.updated` | noteId, version, source | run_event |
| `writejob.enqueued/started/done/failed` | jobId, lane, waitMs, runMs | run_event（已实现，S2） |

约束：全部带 `runId`；子 run 带 `parentRunId`；`payload_json` 只放元数据，不落正文/token 明文。

---

## 9. 失败、取消、重试

- 五终态不变（[ADR-0019](../adr/0019-note-command-and-outcome.md)）：`needsInput` / `readyPreview` / `committed` / `failed` / `cancelled`；
- 取消：写成功后取消 = `cancelled(committed=true)`（已实现，保留）；
- 重试：只在 `LlmGuard`/provider 层；workflow 不自动重试业务写（幂等键由 `commitKey` 保证）；
- deadline：由 `RunContext` 单一来源；A2A 的 35s/90s 在 adapter 层设置，不进入 workflow。

---

## 10. 进程模型

| 进程 | 职责 | 不做什么 |
|---|---|---|
| UI（entry） | UI/VM、组合根、ChatWorkflow、`IngestScheduler`（写准入） | 不复制 A2A 协议逻辑 |
| `:agent`（AgentExtAbility） | A2A 协议 adapter：解析 → `NoteCommand` → 共享 execute 入口 | 不建第二套 workflow、不读 UI 灰度配置 |
| skill | Want 解析 → `NoteCommand` | 不写业务规则 |
| cardservice | 只读投影 | 不调 Agent |

跨进程长任务（S3）由 `IngestGateway` 端口承载：UI 与扩展进程投递同一种任务，底层可以是内存队列（现在）或持久队列（S3）。

---

## 11. 测试与架构适应度函数

| 层 | 要求 |
|---|---|
| 行为基线 | 每个 command 一份 golden（现有 18 条必须**零重录**；新增 command 补快照） |
| 契约 | 每个端口一组契约测试（已有 43 条 + RunStore 8 条） |
| 事件 | 事件 schema 单测：字段、顺序（run.started 必先于 terminal）、必带 runId |
| 边界 | gate 增两条：① workflow 不得直接调另一 workflow（只能经 CommandRouter）；② 不得新增第二套 runtime/调度器 |
| 死代码 | CI/评审检查：`ToolLoop`、`SubgraphNode` 若 0 生产引用则删或标注「预留 ADR」 |

---

## 12. 改造切片（原子、可回退、无双跑）

| # | 内容 | 删除项 | 验收 | 工作量 |
|---|---|---|---|---|
| S0 | 命名与文档收敛：`Dispatcher` → `CommandExecutor`+`CommandRouter` 的术语先落文档；本提案评审后更新 ADR/spec | — | 文档 gate PASS；评审通过 | 0.5 人日 |
| S1 | 拆 `Dispatcher`：执行器 + 路由 + 四条 workflow；preflight/verify 收进路由/各 workflow | `DispatchGraph` 六阶段骨架、`route`/`hitl` 空阶段 | golden 18 零重录；gate PASS；A2A smoke `ok:true` | 1.5 人日 |
| S2 | capture：`NoteAgent` 直接作为 workflow；删 `CaptureBranch` 包装层 | 一层间接 | golden 零重录；`e2e-capture` PASS | 1 人日 |
| S3 | 事件 schema：node/tool/approval/commit 事件 + runId 贯通 + report 解析 | — | 事件契约测试；真机 e2e 输出含 node 事件 | 1–1.5 人日 |
| S4 | ChatWorkflow 启用 ToolLoop（或删除 ToolLoop）；A2A 收敛到同一 executor | `ReplyService` 里的重复编排（若合并） | 对话 golden/冒烟；a2a_smoke 双用例 | 2–3 人日（可延后） |
| S5 | runtime checkpoint / interrupt / 持久队列 | — | **需新 ADR**；不排期 | — |

每个切片独立 commit，旧实现与接线**同切片原子删除**（ADR-0008 明确禁止双跑/长期 flag）。

---

## 13. 是否改造：决策矩阵

| 项 | 判断 | 理由 |
|---|---|---|
| 删空阶段 + 拆执行器/路由（S1） | **建议做** | 认知税最高、风险最低、golden 兜底 |
| 命名诚实化（S0） | **必做** | 现在叫 Agent 但没 agent 语义，误导评审与后续开发 |
| 事件贯通（S3） | **建议做** | S3 跨进程/排障的前置；现在只有 start/terminal |
| ChatWorkflow 接 ToolLoop（S4） | 视时间 | 产品价值有限（对话已可用），先删死代码更划算 |
| 子图即节点 | **暂不做** | 无第二个消费者，做了就是死代码 |
| runtime checkpoint / 图内 HITL | **暂不做** | 需新 ADR；当前业务级 checkpoint 已满足确认流 |
| 多 Agent 规划器 / 向量 RAG | 不做 | 超出 v1 范围，任务本身确定性强 |

**停止条件**：S1 若导致 golden 快照必须重录，说明行为真的变了 → 停下评估，不许「重录顺手过」。

---

## 14. 与现有 ADR 的关系

- [ADR-0008](../adr/0008-capturegraph-self-built-runtime.md)：本提案**遵守**其非目标（无 runtime checkpoint、无图内 HITL），并把「子图有限放开」降级为「有需求再实现」；
- [ADR-0019](../adr/0019-note-command-and-outcome.md)：命令/终态契约不变，只是执行者从「大图」换成「执行器 + 路由」；
- [ADR-0021](../adr/0021-shared-read-port-implementation-in-common.md)：端口归属不变；
- [ADR-0022](../adr/0022-review-and-video-scope.md)：Review/Video 的 workflow 在各自票里再加，不预建。

## 15. 风险与回退

| 风险 | 缓解 |
|---|---|
| 拆 `Dispatcher` 时行为漂移 | golden 18 零重录 + A2A smoke + `e2e-capture` 三重判据 |
| 事件补全影响性能 | 事件异步 best-effort（同 WriteJob sink），失败只告警 |
| 命名变更面大 | S0 只改文档与类名，不改协议；`NoteCommand/NoteOutcome` 不动 |
| 与 S3 排期冲突 | S1/S3 与本提案解耦，可并行（都只动 orchestration/observability） |

## 16. 参考

- [Anthropic — Building effective agents](https://www.anthropic.com/research/building-effective-agents)（workflows vs agents 的判据）
- [LangGraph — Subgraphs / Persistence](https://langchain-ai.github.io/langgraph/concepts/subgraphs/)（本提案只借鉴「图即节点」的形态，不引入 runtime）
- 现状快照：[agent-chain-2026-11-01.md](./agent-chain-2026-11-01.md) · [scheduler 设计](./agent-scheduler-design-2026-11-01.md)
- 外评审：[review-v7-2026-10-27.md](./review-v7-2026-10-27.md)
