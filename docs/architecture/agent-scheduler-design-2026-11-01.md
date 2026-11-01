# Agent 规划/调度器评估与优化设计（2026-11-01）

> 背景：Agent 链路目前有 4 条入口（App 图片、App 对话、小艺 A2A、草稿确认）和多个执行图。
> 问题：是否需要「规划调度器」？现有设计差在哪、怎么优化。

## 1. 结论

**现状 = 有编排，无调度。**

- **编排（有）**：每条入口都有自己的固定执行图——
  - `Dispatcher / DispatchGraph`：单命令流水线 `preflight → route → invoke → verify → hitl → publish`；
  - `CaptureGraph`（StateGraph）：`Ocr → Classify → Structure → TruthCheck → Persist`；
  - `ConversationWorkflow`：`classify_intent → load_context → (reply | note) → END`；
  - A2A：`A2AIntentRouter → (OCR | 文本计划 checkpoint) → 逐题 ingest`。
- **调度（无）**：
  - 没有统一的任务模型（`AgentTask/Step`）与任务表：4 条入口各用各的状态（ConversationState / A2APlan / inbox item / capture set）；
  - 没有全局并发控制/限流：多个入口的 LLM/OCR/写库可同时发起（这和我们观察到的 provider 72–82s 卡顿高度相关）；
  - 没有优先级/准入：前台聊天和后台补跑竞争同一模型通道，谁先拿到算谁的；
  - 没有统一重试/退避/熔断：重试散落在 `LlmGuard`、A2A attempts 等各处；
  - 没有队列可观测性：只有 `run_store/run_event` 的命令级事件，没有排队时长、准入延迟、任务级时间线。

已有可复用底座：`RunContext`（root/child、预算、CancellationToken）、`run_store/run_event`、`A2APlanStore`（单计划 checkpoint）、`AgentInboxQueue`（持久 FIFO，App 前台 5s 轮询消费）、`Dispatcher`（命令 seam）、`GenerationEvaluator`。

## 2. 现状控制流

```
App 图片 ─┐
App 对话 ─┼─ 同步调用（无队列、无准入） ─→ Dispatcher ─→ CaptureGraph/GenerationBranch ─→ 写路径
小艺 A2A ─┤                                   │
草稿确认 ─┘                                   └→ run_store/run_event（仅事件）
            A2A 多题/超时 ─→ AgentInboxQueue（持久 FIFO）─(App 前台 5s 轮询)─→ 逐条 ingest
            小艺计划 checkpoint ─→ A2APlanStore（单文件、单计划）
```

问题示意：三条入口同时发起 LLM 时没有闸门；`A2APlanStore` 只有一份计划（多会话会互相覆盖）；后台队列只有 App 前台才消费；超时兜底是「转队列」，但队列消费同样没有优先级/限流。

## 3. 目标：薄调度层（TaskPlanner + AgentScheduler + TaskStore）

```
       入口（同一意图层）
 App图片/对话   小艺A2A    草稿确认   后台补跑
        │          │          │          │
        └──────────┴────┬─────┴──────────┘
                        ▼
             ① TaskPlanner（意图 → 计划）
        AgentTask(goal, priority, deadline, steps[DAG], checkpoint)
                        ▼
             ② TaskStore（持久化 + 状态机）
        task / task_step 表（schema v20），步骤级 checkpoint，可断点续跑
                        ▼
             ③ AgentScheduler（单进程唯一调度者）
        优先级队列 + 资源池(LLM/OCR/Write 信号量) + 令牌桶限流
        + deadline 准入/降级 + 重试退避 + 熔断/模型降级 + 取消传播
                        ▼
             ④ Executor 适配器（复用现有 seam，不重写业务）
        Dispatcher.dispatchCommand / CapturePipeline / ReplyService / RAG
                        ▼
             run_store / run_event / task_event（观测：排队时长、阶段耗时、失败原因）
```

### 3.1 任务与步骤模型

```ts
interface AgentTask {
  taskId: string;
  goal: string;               // 用户目标（如「整理这 2 张图」）
  kind: 'chat' | 'note_ingest' | 'note_generate' | 'review' | 'maintenance';
  priority: 'interactive' | 'user_batch' | 'background';
  deadlineMs?: number;
  status: 'queued' | 'running' | 'waiting_user' | 'done' | 'failed' | 'deferred';
  steps: TaskStep[];          // DAG：ocr→segment→(structure→persist→index)*N
  createdAt: number;
}
interface TaskStep {
  stepId: string;
  kind: 'ocr' | 'llm' | 'db_write' | 'rag' | 'checkpoint' | 'notify';
  deps: string[];             // DAG 依赖
  state: 'pending' | 'running' | 'done' | 'failed' | 'skipped';
  attempt: number;
  budgetTokens?: number;
  resultRef?: string;         // noteId / ocrText / evidenceId
}
```

### 3.2 调度规则（最小可用版本）

1. **准入**：每个资源池有并发上限（v1：LLM=1、OCR=1、Write=1）。拿不到槽位 → 进入优先级队列；超过 deadline → 直接降级（入队/回执，不做半成品）。
2. **优先级**：前台交互 > 用户批量（多图整理）> 后台补跑。后台任务在交互任务排队时**不抢占**但延后启动；交互任务优先获得 LLM 槽。
3. **限流/熔断**：按 provider 令牌桶（例如 20 req/min）；连续 2 次「超时/长尾（>25s）」→ 暂停该 provider 30s，若配置了备用 provider/模型则切换（否则任务转队列并提示）。
4. **重试**：仅对可重试错误（NETWORK/TIMEOUT/STREAM_FAILED）指数退避；内容/校验错误不重试，直接回执。
5. **checkpoint**：每次步骤完成落 `task_step`；`waiting_user`（确认页/计划/澄清）保存并在用户回复时从该步继续。
6. **取消**：父任务取消 → 取消森林（复用 `RunContext` + `CancellationToken`）；已提交步骤保留（幂等 commitKey 保证重跑不双写）。

### 3.3 入口到计划模板（复用现有逻辑，只加模板层）

| 入口 | 计划模板 |
|---|---|
| App 对话（chat） | `[rag, llm_reply]`，priority=interactive |
| App 对话（note_generate） | `[rag, draft_llm, hitl_checkpoint]` |
| App 图片批量 | `[ocr×N, segment/merge, checkpoint, (structure+persist+index)×M]` |
| 小艺 A2A 文本 | `[dedupe, structure_llm, persist, index]`（多题则先 `checkpoint` 再逐题） |
| 小艺 A2A 图片 | `[ocr×N, plan_checkpoint, (structure+persist)×M]` |
| 后台补跑 | 同文本入口，priority=background，deadline 放宽 |

### 3.4 进程边界（关键约束）

- 小艺 `AgentExtAbility` 跑在 **`:agent` 独立进程**，不能与 UI 进程共享内存调度器。
- 方案：**UI 进程持有全局 Scheduler**（唯一调度者）；扩展进程只做「轻量前置」（意图/OCR/计划 checkpoint）并把需要长任务的 step 写入 `TaskStore + AgentInboxQueue`（跨进程经 RDB），由 UI 进程消费；扩展进程自身对短任务（回复小艺）也有本地小并发限制。
- 这样既避免跨进程锁复杂度，又能复用现有 inbox 模式。

## 4. 分阶段落地

| 阶段 | 内容 | 验收 |
|---|---|---|
| **S1**（1–2 天） | `TaskStore`（schema v20：`agent_task`/`agent_task_step`）+ `TaskPlanner` 模板（文字整理、图片批量）+ `AgentScheduler` 单进程（优先级队列 + LLM/OCR/Write 信号量）+ 把 `CapturePipeline`/`AgentIngestService` 接入调度器（feature flag 可回退） | 并发压力 e2e：3 个整理同时发起 → 串行/排队符合预期；单题 P95 不再因并发互相拖慢；gate PASS |
| **S2** | 优先级/准入/降级（deadline 到期转队列）+ 令牌桶限流 + 前台/后台区分 + run_event 增补排队/准入字段 | 前台聊天在后台补跑时首字延迟不受影响；队列等待可观测 |
| **S3** | checkpoint/断点续跑统一（A2APlanStore + captureSet + inbox 迁移到 task_step）+ 重试退避/熔断/备用模型 | 杀进程重启后任务可从最后完成步骤继续；provider 长尾自动切换/降级 |
| **S4** | 多目标规划（一句话多任务拆解）、调度面板（队列深度/等待/失败原因/模型长尾率） | 任务级时间线与指标可查；多目标不互相踩 |

## 5. 明确不做（避免过度设计）

- 不做独立 module/独立线程池服务；调度器放在 `entry/services`，契约放 `common`；
- 不做抢占式中断长 LLM 请求（成本高、易产生半成品）；只做「不启动」与「超时降级」；
- 不重写 `Dispatcher/CaptureGraph`：它们作为 Executor 被调度器调用；
- 不在扩展进程做全局调度（进程边界见 §3.4）。

## 6. 与当前 P0 的关系

- 当前 P0-2 的「provider 长尾 72–82s」与「多入口无并发闸门」直接相关：S2 的限流+准入先把互相拖慢消掉，再谈单请求优化；
- 现有 90s deadline → 队列兜底是 S1/S2 的雏形，迁移到 TaskStore 后统一。


## 7. 设计评审与修订（2026-11-01，S1 前）

### 7.1 结论

方向合理（统一任务模型/checkpoint/准入/优先级是真实缺口），但**原方案范围偏大且有 3 处判断需要修正**：

1. **收益尚未证实**：慢样本 `completionTokens=594 / NETSTACK total_time≈72s`，同 prompt 快样本 9.3s；且 e2e 是单入口顺序执行也出现长尾 → provider 长尾**不是并发造成的**。调度器能解决的是「多入口互拖/前台被后台阻塞」，**不能解决 provider 长尾**。S1 前应先做 S0 实验证明「互拖」存在，否则优先级/队列收益主要是体验策略而非性能。
2. **MVP 过重**：S1 同时上 TaskPlanner(DAG)+TaskStore(task/step 双表,schema v20)+跨进程交接，属于过度设计。应改为「单表 job + 线性步骤 + 内存优先级队列 + 现有表/事件系统」，不新增 DAG、不升 schema、不做跨进程。
3. **进程边界被低估**：A2A 扩展是 `:agent` 独立进程，原方案「UI 进程唯一全局调度」会迫使扩展把任务写 DB 再靠轮询消费，复杂且延迟不可控。MVP 明确：**扩展进程不进调度器**（保持 90s deadline + inbox），调度器先只覆盖 UI 进程写路径 + inbox 消费。

### 7.2 需要调整/补充的点

| # | 调整 | 原因 |
|---|---|---|
| A1 | 命名收窄：`WriteJob / WriteJobQueue / WriteJobScheduler`（限定「笔记写入工作」），不用泛化的 TaskPlanner/TaskStore | 避免与现有 `note_generation_run`/`run_store`/`ConversationState` 概念混淆，也避免被理解为通用 agent 调度 |
| A2 | S1 存储用**单表 `agent_job`**（jobId/kind/priority/status/payloadJson/checkpoint/attempt/时间戳），步骤事件复用 `run_event`；不升 schema v20 | 迁移成本低、回滚容易；DAG/step 表等真有需要（S3）再拆 |
| A3 | 并发模型改为**双通道**：interactive lane=1（聊天/确认）+ background lane=1（整理/补跑），总量 ≤2，可配置；OCR/write 仍各 1 | LLM 总并发=1 会让前台聊天排在 100s+ 的批量整理后面；总并发 2 兼顾吞吐与 provider 限流，需实测 |
| A4 | 准入加「前台等待标记」：后台 job 在**步骤边界**检查前台是否有排队交互，有则让出槽位（不做抢占式中断 LLM） | 步骤是结构化边界，天然可让出；避免半成品 |
| A5 | 降级策略按入口区分：App 内 = 进度 + 取消（不可静默转队列）；A2A = 超时转 inbox 队列（已有） | 前台用户不能「被转后台」而不知道 |
| A6 | 重试只允许幂等步骤：LLM 可重试（commitKey/输入指纹兜底）、写库幂等、通知不重试；错误分类沿用现有 `retriable` | 避免重复入库/重复回执 |
| A7 | 立即小修（不依赖调度器）：`A2APlanStore` 由「单全局计划」改为按 taskId/会话分 key | 当前多会话会互相覆盖计划，是现存 bug（S1 之前就能修） |
| A8 | 观测先进 `run_event`：job 状态变化（queued/admitted/started/done/degraged）+ 排队时长；配 `scripts/quality/scheduler-report.mjs` | 没有数据无法证明调度收益 |
| A9 | Feature flag `WRITE_JOB_SCHEDULER_ENABLED`（默认关→灰度开），回滚只需关 flag | 写路径是核心链路，必须可一键回退 |
| A10 | 任务保留策略：完成/失败 job 保留 200 条或 7 天，payload 脱敏；清理任务在 App 启动时执行 | 原文落库膨胀 + 隐私边界 |
| A11 | 范围锁定：S1 只覆盖 capture/ingest（写笔记）；chat/review 的 LLM 竞争留 S2 | 先闭环可验证的小范围 |
| A12 | provider 熔断先做「暂停 + 降级入队」，备用模型切换留 S3（依赖多厂商 key 配置） | 不做无数据支撑的模型切换 |

### 7.3 修订后的路线（含 S0）

| 阶段 | 内容 | 验收 |
|---|---|---|
| **S0（半天，先做）** | 并发压力实验（不改架构）：e2e 同时提交 2–3 个整理任务 + 后台 inbox 消费，记录首次/各阶段耗时；对比单任务基线 | 结论明确：并发互拖是否真实存在、量化倍数；**若无明显互拖，调度器降级为「优先级+进度」小需求** |
| **S1** | `agent_job` 单表 + `WriteJobQueue`（内存优先级队列）+ 双通道信号量 + `CapturePipeline`/`AgentIngestService`/inbox 消费接入（flag 控制） | 并发时前台/批量按通道排队；P95 不劣化；关 flag 与旧行为逐字节一致；gate PASS |
| **S2** | 准入/让出/取消/进度 + 排队指标 + A2A 扩展侧保持现状 | 后台批量时前台聊天首字延迟不劣化；run_event 可查排队时长 |
| **S3** | 跨进程任务交接（扩展写 job、UI 消费）+ 断点续跑 + A2APlan 迁移 + 熔断/备用模型 | 杀进程重启可续跑；长尾 provider 暂停/降级 |
| **S4** | 多目标拆解（一句话多任务）+ 调度面板 | 多目标不互踩，任务时间线可查 |

### 7.4 仍待决策（S0 后定）

1. 双通道总并发默认 1 还是 2（看 S0 数据与 provider 429）；
2. S0 若证明互拖不显著：是否只做「优先级 + 排队可见性」，放弃完整队列/断点续跑；
3. `agent_job` 用新表还是塞进 `run_store`（当前倾向新表单职责，S0 后确认）。

## 8. S1 实现状态（2026-11-01，spec 038）

- **S0 实验定论**：并发 ingest 的两条笔记都落库但 post-commit 阶段卡死 >10min；加 `AsyncMutex` 写区互斥（索引同步 + effects 串行）后并发正常，复跑：顺序 10.24s vs 并发 wall 4.35s（overlap 50%、slowdown 0.85）。→ S1 不串行化 LLM，只串行写区。
- **S1 已落地**（spec 038 M1–M3）：`WriteJobModels`（kind/status/priority）+ `WriteJobQueueCore` + `AsyncSemaphore` + `WriteJobScheduler`（双 lane，默认各 1；waitMs/runMs/queueDepth/maxConcurrent 统计）；`WriteJobFlags` 默认关，接入 `AgentIngestService.ingestSingleText` 与 `A2AInboxIngestService`（background lane）；`A2APlanStore` 按 taskId 隔离并迁移旧 plan.json。
- **观测**：S1 用 `[WriteJob]` hilog + `scripts/quality/scheduler-report.mjs`；A8 的 run_event 落库推迟到 S2（S1 队列不持久化）。
- **真机证据**：schedulerProbe（1 interactive + 2 background）`submitted=3 completed=3 failed=0 maxConcurrent=2`，第二个 background `lastWaitMs=75043/lastRunMs=14013`（排队生效）；schedulerIntegration `kind=committed submitted=1`。
- **S2 待办**：run_event 接入、flag 灰度打开、多入口并发压测、断点续跑（S3）。
