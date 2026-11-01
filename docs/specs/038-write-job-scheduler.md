# 038 — 笔记写入工作调度器（WriteJob Scheduler）

> **Status**: implemented (2026-11-01) — S1/S2 已落地；S3（跨进程 handoff + 队列持久化/断点续跑）由 [spec 040](./040-writejob-persistence-cross-process.md) / [ADR-0024](../adr/0024-writejob-persistence-cross-process.md) 承接（proposed）
> **Related**: [ADR-0019](../adr/0019-note-command-and-outcome.md) · [ADR-0021](../adr/0021-shared-read-port-implementation-in-common.md) · [spec 036](./036-multi-image-single-pass-consolidation.md) · [scheduler design](../architecture/agent-scheduler-design-2026-11-01.md)
> **Code**: `entry/src/main/ets/services/WriteJobScheduler.ets` · `entry/src/main/ets/services/WriteJobEventRecorder.ets` · `entry/src/main/ets/services/AsyncMutex.ets` · `entry/src/main/ets/services/KnowledgeUnitWriteService.ets`
> **Verified by**: `node scripts/agent-gate/index.mjs --all` · e2e `schedulerProbe` / `schedulerIntegration` / `schedulerStress` · `node scripts/quality/scheduler-report.mjs`


> 目标：为「写笔记」这类长任务引入一个**薄调度层**（规划 → 队列 → 双通道并发 → 可观测），
> 解决多入口互拖/前后台争抢；不做通用 Agent 调度框架。
> 上游设计评估见 [`docs/architecture/agent-scheduler-design-2026-11-01.md`](../architecture/agent-scheduler-design-2026-11-01.md)。

## 1. 背景与问题

- 4 条入口（App 图片、App 对话、小艺 A2A、草稿确认）+ inbox 补跑各自直接调用写路径，**无统一任务模型/并发准入/优先级**；
- 实测 provider 长尾（594 tokens / 72s vs 同 prompt 9.3s）与单入口顺序也出现 → 调度器不能治长尾，但能治「多入口互拖、前台被后台阻塞」；
- `A2APlanStore` 是单全局计划文件，**多会话会互相覆盖**（独立 bug，先行修复）。

## 2. 范围

### S0（先做，不改架构）
并发实验：同时提交 2 个写笔记任务 vs 顺序执行，量化互拖倍数。
实现：`e2e=concurrencyProbe`（DebugCaptureRunner），输出每任务开始/结束/总耗时与重叠时间。

### S1（本 spec 主体）
- **WriteJob 模型**（纯类型）：jobId / kind(text_ingest) / priority(interactive|background) / payload(text) / status / createdAt；
- **WriteJobQueueCore**（纯函数）：按 (priority, createdAt) 取出下一个任务；
- **AsyncSemaphore**（纯逻辑）：限制并发槽位；
- **WriteJobScheduler**（entry/services）：双通道（interactive=1 / background=1，总 ≤2）、执行器注入、统计与日志；
- **接入点**（feature flag 控制，默认关）：
  - `AgentIngestService.ingestSingleText`（小艺逐题/文本整理）；
  - `A2AInboxIngestService.consume`（后台补跑逐条）；
- **观测**：`[WriteJob] enqueued/started/done priority=... waitMs=... runMs=...` + 调度统计；
- **A2APlanStore 多会话修复**：计划按 taskId 分 key（不依赖调度器）。

### 非目标（本 spec 不做）
- 不做 DAG/多目标规划、不做断点续跑与任务表持久化（S3）；
- A2A 扩展进程（`:agent`）**不接入**调度器（保持 90s deadline + inbox）；
- 不改 chat/review 的 LLM 调用；不改 Dispatcher/CaptureGraph 内部；
- 不做备用模型切换/熔断（S3）。

## 3. 设计要点

```
AgentIngestService / A2AInboxIngestService
        │  submit(job) → Promise<outcome>
        ▼
WriteJobScheduler（单例，entry/services）
  ├─ WriteJobQueueCore：interactive 队列 + background 队列（FIFO by createdAt）
  ├─ 双通道信号量：interactive=1、background=1（总 ≤2）
  ├─ executor(job) → 现成写路径（CapturePipeline/ingest）
  └─ 统计/日志：waitMs、runMs、并发数、队列深度
```

- **可测 seam**：`WriteJobQueueCore`（纯函数）与 `AsyncSemaphore`（纯逻辑）用 Node 单测；
  `WriteJobScheduler` 以「注入 executor」构造，测试用假 executor 验证顺序/并发/统计；
- **feature flag**：`WriteJobFlags.enabled`（默认 false），关闭时接入点走原路径（逐字节一致）；设备验证后灰度打开；
- **错误传播**：executor 抛错 → job 失败并向上抛给调用方（保持现有错误语义）；不重试（重试策略 S2）；
- **取消**：S1 沿用调用方现有 cancellation（不新增调度级取消）；任务不抢占。

## 4. TDD 切片（每片先红后绿）

| # | 切片 | 测试（seam） |
|---|---|---|
| T1 | WriteJobQueueCore：interactive 优先、同级 FIFO、空队列 | `v7-write-job-core.test.mjs`（纯函数） |
| T2 | AsyncSemaphore：acquire/release 顺序、并发上限、等待者按 FIFO 唤醒 | 同上（纯逻辑） |
| T3 | WriteJobScheduler：双通道并发上限、统计（waitMs/runMs）、提交即返回 Promise | 注入 fake executor |
| T4 | 接入 flag：关闭时不经过调度器；开启时经过（source/behavior guard） | 契约测试 + 可注入 executor 的集成测试 |
| T5 | A2APlanStore：同 taskId 读写、不同 taskId 隔离、旧全局计划可读迁移 | 以 mock fileIo 或纯 key 函数测试 |
| T6 | 观测日志字段：enqueued/started/done 字段齐全 | source guard + 日志格式断言 |
| T7 | 观测事件（S2）：phase/metrics 齐全、失败相带 error、sink 抛错不影响 job | `v7-write-job.test.mjs`（fake sink） |
| T8 | S2 接线守卫：UI 灰度开关、recorder 前缀/落库调用、扩展进程不读配置 | source guard |

## 5. 验收

1. `node scripts/agent-gate/index.mjs --all` **RESULT: PASS**；
2. 新增单测覆盖 T1–T2（纯函数必须绿），T3 用 fake executor 全覆盖；
3. 真机 `e2e=concurrencyProbe`（S0）输出：并发 vs 顺序的任务耗时/重叠数据；结论写入 spec；
4. 真机 `e2e=schedulerProbe`（S1）：3 个任务（interactive×1 + background×2）→ 观察排队顺序、waitMs/runMs、并发峰值 ≤2；
5. flag 关闭时旧路径回归：`e2e=latencyProbe` / `dedupeProbe` 仍通过；
6. 文档：本 spec + architecture 索引更新；代码审查（code-review skill）两轴通过或问题登记。

## 6. 风险与回滚

- 写路径核心链路 → feature flag 默认关，回滚=翻转开关；
- 调度器单例与 inbox 轮询叠加：S1 只让 inbox 消费者走后台通道，避免重复入队；
- provider 长尾不影响调度公平性（任务串行于自身通道内）；
- 不做持久化 → App 进程被杀后内存队列丢失；S1 接受（inbox 本身持久化，原文不丢）。

## 7. 里程碑与提交

```
M1  计划 + S0 并发实验 + A2APlanStore 修复
M2  T1–T3 核心（queue/semaphore/scheduler）+ 单测
M3  T4–T6 接入/观测 + flag + 真机 schedulerProbe
M4  gate 全绿 + code-review 两轴审查 + 文档收尾
```


## 8. 执行记录

### M1（2026-11-01）

- [x] 计划（本 spec）
- [x] `A2APlanStore` 多会话修复：计划文件按 `taskId` 分 key（`plan-<sanitize(taskId)>.json`），旧 `plan.json` 仅 default 兼容读取；`sanitizePlanKey` 纯函数 + 单测。
- [x] `e2e=concurrencyProbe`（S0 实验，只读观测 + 顺序/并发对照）
- [x] **S0 发现并发 bug**：两条 ingest 并发时，两条笔记都落库，但探针 10+ 分钟不返回（post-commit 阶段卡死）。
- [x] 修复：`AsyncMutex` 全局写区互斥，`KnowledgeUnitWriteService.finalizeWrite` 把「索引同步 + post-commit effects」串行化；effect 增加耗时日志；并发探针加 120s 单任务超时防挂死。
- [x] S0 复跑（修复后，真机）：

```
stage=concurrency seq a=7097 b=3143 sum=10240
stage=concurrency conc a=4352 b=4319 sum=8671 wall=4352 overlapPct=50 slowdown=0.85
stage=done concurrency=1
```

**S0 结论与设计调整**：

1. 并发卡死根因在 **post-commit 写区**（native 副作用不可重入），与 LLM 并发无关；互斥后并发可跑、且 LLM 侧天然重叠（overlap 50%），并发不劣化（slowdown 0.85，样本小）。
2. 因此 **S1 不需要串行化 LLM**；`WriteJobScheduler` 改为：队列/优先级/背压 + **写区继续用 `AsyncMutex`（lane=1）**；interactive/background 双通道仅用于调度顺序与观测，LLM 可自然并发（上限留可配置）。
3. 修复本身独立于调度器，先于 S1 生效（当前所有写入已串行 post-commit）。

### M2（下一步）

- T1 `WriteJobQueueCore`（纯函数：interactive 优先、同级 FIFO）
- T2 `AsyncSemaphore`（或复用 AsyncMutex 的 lane 语义）
- T3 `WriteJobScheduler`（注入 executor、统计 waitMs/runMs、flag）
- T4 接入 `AgentIngestService.ingestSingleText` + `A2AInboxIngestService.consume`
- T5/T6 观测与真机 `schedulerProbe`


### M2（2026-11-01 完成）

- [x] T1 `WriteJobQueueCore`（interactive 优先/同级 FIFO）
- [x] T2 `AsyncSemaphore`（容量上限 + FIFO 唤醒）
- [x] T3 `WriteJobScheduler`（interactive/background 双 lane，默认各 1；`waitMs/runMs/queueDepth/maxConcurrent` 统计；`[WriteJob]` 日志）
- [x] T3b 失败传播与 failed 统计
- [x] T4 feature flag `WriteJobFlags`（默认关）+ 接入 `AgentIngestService.ingestSingleText`、`A2AInboxIngestService.consume`（background lane）；关闭时走 `ingestSingleTextDirect` 旧路径
- [x] 真机 `e2e=schedulerProbe`（flag 开，interactive+background 各一条真实 ingest）：

```
stage=scheduler done interactiveMs=7040 backgroundMs=18017
submitted=2 completed=2 failed=0 queueDepth=0 maxConcurrent=2
lastWaitMs=0 lastRunMs=18016
stage=done scheduler=1 ms=18017
```

结论：双 lane 并发（maxConcurrent=2）按预期工作、失败 0；写区串行仍由 `AsyncMutex` 保证（S0 结论），LLM 允许自然重叠。

- 测试：`v7-write-job` 5 条 + `v7-write-section` 3 条 + `v7-a2a-plan` 7 条；gate --all PASS（pass=1157）。

### M3（下一步）

- 真机验证 flag=true 时的 `AgentIngestService.ingestSingleText` 包装路径（schedulerIntegration e2e）
- flag 关闭回归（latencyProbe/dedupeProbe）+ 打开灰度决策
- code-review skill 两轴审查（Standards/Spec）并修问题


### M3（2026-11-01 完成）

- [x] 集成路径真机验证 `e2e=schedulerIntegration`（flag 开 → `AgentIngestService.ingestSingleText` → 调度器 → 写路径）：

```
stage=scheduler-integration kind=committed submitted=1 completed=1 failed=0 maxConcurrent=1 noteId=KB-mvxlgwjp-zc56zo
stage=done schedulerIntegration=1 ms=16175
```

- [x] flag 关闭回归（默认关闭）：
  - `dedupeProbe`：`same=1 notesBefore=notesAfter added=0 / 21ms`（输入指纹幂等正常）；
  - `latencyProbe`：第一次命 provider 长尾（structure 调用 >300s 未返回，非调度器路径，flag 关闭）；重试 `committed totalMs=79201`。记录为 provider 波动，非回归。
- [x] 灰度决策：**flag 默认保持关闭**。原因：S1 队列是进程内内存队列，A2A 扩展进程与 UI 进程各自独立；等 S3 跨进程 handoff + 持久化后再默认开启。当前通过 e2e 开关验证路径与行为。

### M4（收尾）

- code-review skill：Standards / Spec 双轴审查（fixed point = `552fca1`），修复 findings 后 gate 全绿。


### M4（2026-11-01 完成）：code-review 双轴审查 + 修复

固定比较点 `552fca1`（`git diff 552fca1...HEAD`），并行两个子代理（Standards / Spec），聚合后逐条修复：

**Standards 轴**
- [x] Hard：`AsyncSemaphore` / `WriteJobModels` / `WriteJobQueueCore` 文件头补「依赖」字段；
- [x] Data Clumps / Repeated Switches：调度器改为 Lane{queue, sem}（interactive/background 各一条），删除双队列/双 cap/双 running 平行字段与重复 priority 分支；
- [x] Speculative Generality：`AsyncSemaphore` 成为生产 lane 并发控制（不再只被测试使用）；`WriteJob.payloadText` 在 enqueued 日志读取 chars；`timed(label,…)` 未用参数删除；
- [x] Duplicated Code：探针超时统一复用 `DebugCaptureRunner.withTimeout`（120s/150s 两处内联竞速删除）；EntryAbility 探针分支统一走 `runDebugProbe`（17 处同形分支收敛）；
- [x] Primitive Obsession：`PLAN_KEY_DEFAULT` 导出并在 store 复用；`A2APlanStore.save(context, taskId, plan)` 与 load/clear 的 key API 对齐；
- [x] 同模块双 import 合并；`for…of` 替换新增 C-style for（队列/plan key）。
- 备注：`AsyncMutex.isBusy()` 与 `priorityRank` 导出已在 review 前清理。

**Spec 轴**
- [x] `WriteJob` 补 `kind(text_ingest)` + `status(queued/running/done/failed)` 与状态迁移；
- [x] `AsyncSemaphore` 接入生产调度（见上）；
- [x] 补 T4b（executor 注入语义）、T6（日志格式断言）与 T3c（executor 同步抛错不占死 lane）；
- [x] `schedulerProbe` 改为 3 任务（interactive×1 + background×2）：`submitted=3 completed=3 failed=0 maxConcurrent=2`，`lastWaitMs=75043/lastRunMs=14013` 作为排队证据；
- [x] 旧全局 `plan.json` 迁移：任何 taskId 首次读取旧计划时迁移到自己的 keyed 文件（不再丢失）；
- [x] duplicate 写路径恢复旧行为：跳过索引同步但仍执行 post-commit effects（flag 关时逐字节一致）；
- [x] done/failed 日志补 `priority=`；executor 同步抛错走统一失败收尾；
- [x] 新增 `scripts/quality/scheduler-report.mjs`（A8 观测）。
- 记录（未在本轮做，留 S2）：A8 的 run_event 落库（S1 队列不持久化，先用 hilog + 报告）；flag 默认保持关闭，待 S3 跨进程 + 持久化后灰度。

**验收证据**：`agent-gate --all` RESULT: PASS（pass=1160 fail=0）；真机 schedulerProbe/schedulerIntegration/dedupeProbe 均通过；scheduler-report 可复跑。


## 9. S2（2026-11-01 完成）：观测落库 + 压测 + flag 灰度

### 9.1 run_event 观测落库（A8）

- `WriteJobEvents`（零依赖契约：事件/metrics 类型 + `WRITE_JOB_RUN_PREFIX` 常量，kind/priority 复用 `WriteJobKind`/`WriteJobPriority`）：`WriteJobEvent{jobId,kind,priority,phase,queueDepth,waitMs,runMs,error,at}` + sink；
- `WriteJobScheduler.setEventSink()`：enqueued/started/done/failed 发事件；sink 抛错不影响 job；
- `WriteJobEventRecorder`：每个 job 一条 `run_store`（`run_id=writejob:<jobId>`，终态 `committed/failed`），事件追加到 `run_event`（`kind=writejob:<phase>`，payload 含 priority/queueDepth/waitMs/runMs）；**写事件用 `AsyncMutex` 串行**（run_event 的 MAX(seq)+1 事务并发会冲突，实测丢 2/18 事件）。
- EntryAbility 启动接线：`WriteJobScheduler.shared().setEventSink(WriteJobEventRecorder.create())`。

### 9.2 flag 灰度（UI 进程启用）

- `WriteJobConfig.WRITE_JOB_UI_ENABLED = true`，仅 `EntryAbility.onCreate`（UI 进程）调用 `WriteJobFlags.setEnabled(true)`；
- A2A `AgentExtAbility` 是独立 `:agent` 进程，不读该配置 → 仍是默认关闭、走旧路径（跨进程统一留 S3）；
- 回滚：把常量改 false 重新发版，即完全回到旧行为。
- **决策更新（supersedes M3「flag 默认保持关闭」）**：S2 已完成观测落库与压测，UI 进程启用、A2A 扩展进程保持关闭；原「等 S3 再开」的约束随 S2 收敛——跨进程统一仍在 S3，但不再阻塞 UI 进程灰度。

### 9.3 真机验证

- `e2e=schedulerStress`（2 interactive + 4 background 假 executor，验证排队/并发/落库）：

```
submitted=6 completed=6 failed=0 maxConcurrent=2 queueDepth=0
lastWaitMs=362 lastRunMs=121 persistedEvents=18（6 job × enqueued/started/done）/ 691ms
```

- `e2e=schedulerProbe`（lane 机制：直接注入 executor，flag 接线由 schedulerIntegration 覆盖，3 真实 ingest）：`submitted=3 completed=3 failed=0 maxConcurrent=2`；
- `e2e=schedulerIntegration`（flag 开 → ingestSingleText 包装路径，按单次 delta 统计）：`kind=committed submittedDelta=1 completedDelta=1 failedDelta=0 / 8.8s`；
- `e2e=schedulerInbox`（多入口：inbox 队列 → flag 开 → background lane）：`claimed=1 done=1 failed=0 submittedDelta=1 completedDelta=1 maxConcurrent=2 / 11.2s`；
- `e2e=dedupeProbe`（flag 开）：`same=1 added=1`（首条新建、第二条复用输入指纹），通过；
- `agent-gate --all` RESULT: PASS（pass=1165 fail=0）。

### 9.4 已知偏差/后续

- ~~同进程多次探针的 scheduler 统计是累计值~~ → S2 复查已改：integration/stress 全部按 **delta** 输出，不再受跨场景污染；
- S3：跨进程 handoff（扩展写 job、UI 消费）、队列持久化/断点续跑 → 已立 [spec 040](./040-writejob-persistence-cross-process.md) + [ADR-0024](../adr/0024-writejob-persistence-cross-process.md)；事件表清理策略另行排期。

### 9.5 Spec 轴复查修复（2026-11-01）

- **A8 闭环**：`scheduler-report.mjs` 增加解析 `schedulerStress`（`persistedEvents` + `terminalCommitted/terminalFailed`）与 `schedulerInbox`；`RunStoreDao` 增加 `countRecordsByRunPrefixAndStatus`，stress 用 run_store 终态核对 6 committed / 1 failed；
- **失败相验证**：stress 增加 1 个必失败 job（`failedDelta=1`、events 21=7×3、terminalFailed=1），单元测试 T3d 覆盖 `phase=failed + error`；
- **多入口压测补全**：新增 `e2e=schedulerInbox`，覆盖 `A2AInboxIngestService.consume` 的 flag-on background lane（真实 ingest，claimed=1 done=1）；
- **schedulerProbe 语义修正**：不再自切 flag（lane 机制直接注入 executor），flag 接线由 schedulerIntegration 验证；
- **integration 证据修正**：改为单次 delta（submittedDelta=1/completedDelta=1），不再引用跨场景累计值。
- 遗留（S3）：跨进程 handoff、队列持久化/断点续跑、事件清理。
