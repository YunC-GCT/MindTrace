# 038 — 笔记写入工作调度器（WriteJob Scheduler）

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
