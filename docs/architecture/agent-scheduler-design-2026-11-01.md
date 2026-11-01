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
