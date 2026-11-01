# 0024 — WriteJob 队列持久化与跨进程 handoff（038 S3）

> **Status**: proposed (2026-11-01)
> **Related**: [spec 038](../specs/038-write-job-scheduler.md) · [spec 039](../specs/039-agent-workflow-first.md) · [ADR-0008](./0008-capturegraph-self-built-runtime.md) · [ADR-0019](./0019-note-command-and-outcome.md) · [ADR-0021](./0021-shared-read-port-implementation-in-common.md)
> **Code**: `entry/src/main/ets/services/WriteJobScheduler.ets` · `entry/src/main/ets/services/A2AInboxIngestService.ets` · `entry/src/main/ets/agentextability/AgentExtAbility.ets` · `common/src/main/ets/DatabaseHelper.ets`
> **Verified by**: 本 ADR 仅定决策；实现验收见 spec 040（待排期）

## 1. 背景（为什么需要这个决定）

- 038 S1/S2 的 `WriteJobScheduler` 是**进程内内存队列**：App 被杀/重启后 queued/running job 丢失；
- A2A `AgentExtAbility` 跑在独立 `:agent` 进程，当前会**自己执行 ingest**（超时 90s → 转 inbox），与 UI 进程的调度器各自为政；
- `AgentInboxQueue` 是文件 JSON 持久队列，但只有「排队」语义（无状态机/租约/重试/优先级）；
- ADR-0008 明确**不做 runtime graph checkpoint、不做图内 HITL**；恢复粒度只能是「整个命令」而不是图中间态。

结论：需要一个**持久、可跨进程交接、单执行者**的写任务队列；不引入图级 checkpoint。

## 2. 决定

### 2.1 单执行者（UI 进程）

- **只有 UI 进程**执行写任务（调度器 + 写路径）；`:agent` 扩展进程**只入队、不执行**长任务。
- 扩展在 A2A 文本/图片整理请求上：写 job → 立刻回「已受理，稍后自动整理」，不再占用 90s deadline 等 LLM。
- 这样跨进程竞争只在「入队写」，不在「执行/写笔记」。

### 2.2 持久队列 `agent_job`（schema v20）

新表（additive，不改既有表）：

```
agent_job(
  job_id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,                 -- text_ingest | image_ingest
  priority TEXT NOT NULL,             -- interactive | background
  payload_text TEXT NOT NULL,
  source TEXT NOT NULL,               -- app | xiaoyi | inbox
  status TEXT NOT NULL,               -- queued | running | done | failed | cancelled
  attempt INTEGER NOT NULL DEFAULT 0,
  fingerprint TEXT NOT NULL,          -- 输入指纹（capture-input 同一算法）
  lease_owner TEXT,                   -- 进程标识（UI 进程）
  lease_expires_at INTEGER,           -- 租约到期（ms）
  error TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
```

- 索引：`(status, priority, created_at)`、`(fingerprint)`；
- 入队幂等：同 fingerprint 且 status 非终态 → 复用现有 job（不重复排队）；
- 执行幂等：沿用 capture-input commitKey / 写端口 CAS（ADR-0019），job 重跑不双写。

### 2.3 租约与恢复

- UI 进程启动时：`queued` 全部入内存队列；`running` 且租约未过期的跳过（另一个 UI 实例/前台还在跑）；租约过期的置回 `queued`（attempt+1，达上限 → failed）；
- claim：事务内 `UPDATE ... SET status='running', lease_owner=?, lease_expires_at=? WHERE job_id=? AND status='queued'`；失败即被别人抢走；
- 任务完成/失败写终态并释放租约；进程内调度器继续用 `AsyncSemaphore` 双 lane，DB 只负责持久化与跨进程交接；
- 失败重试：仅 `retryable` 错误重试（最多 2 次），attempt 写库；不可重试直接 failed，事件记原因。

### 2.4 跨进程交接

- 扩展进程写 `agent_job`（只 INSERT/幂等 upsert），并立即 A2A 回执「已受理」；
- UI 进程在前台/启动时消费；App 不在前台也保证**队列不丢**（RDB 持久）；
- `AgentInboxQueue`（文件 JSON）迁移：首次启动把 pending 项转成 `agent_job`（source=inbox），迁移完成后新流程不再写 inbox；保留读迁移代码 1 个版本用于回滚。

### 2.5 观测与灰度

- 复用 `WriteJobEventRecorder`：job 生命周期 → run_store/run_event（runId=jobId）；新增 `job.queued/running/recovered` 等 kind；
- `scheduler-report.mjs` 读事件/状态分布；
- 灰度 flag：`WRITE_JOB_PERSIST_ENABLED` 默认 false → 设备验证后 UI 进程打开；回滚 = flag 关闭（队列退回内存，数据保留）。

### 2.6 明确不做

- 不做 runtime graph checkpoint / 图内 HITL（ADR-0008 不变）；
- 不做多执行者分布式调度、精确一次语义（幂等写已是兜底）；
- 不做模型熔断/备用 provider（038 S3 的另一项，单独评估）；
- 不做 job payload 加密（沿用现有笔记数据边界；payload 只存待整理原文，完成后可清理）。

## 3. 备选方案与取舍

| 方案 | 结论 | 原因 |
|---|---|---|
| A. 继续用文件 inbox 扩展 | 否 | 无状态机/租约/重试/优先级；跨进程并发追加难保证 |
| B. 新建 `agent_job` 表 + 单执行者 + 租约（**本 ADR**） | 采纳 | 增量小、可恢复、可观测、回滚简单 |
| C. 引入消息队列/后台服务 | 否 | 竞技/交付阶段过重，无跨设备需求 |

## 4. 可逆性

- **高**：新表 additive、不动协议/既有表；flag 关闭即回到 038 S2 行为；
- 回滚时 `agent_job` 可保留（数据无害）或删表；迁移仅 inbox→job 单向，回滚后 inbox 仍可读；
- 风险点：多进程 RDB 写竞争（用 `busy_timeout` + 租约 + 重试缓解，见 spec 040 §风险）。

## 5. 影响

- spec 040（实现计划）：schema/DAO、调度器持久化与恢复、扩展只入队、真机跨进程/重启验收；
- 038 状态：S1/S2 不变，S3 由 spec 040 承接；flag 默认策略更新为「SPEC 040 P3 验证后打开」。
