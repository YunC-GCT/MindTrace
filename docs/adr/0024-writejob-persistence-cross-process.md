# 0024 — WriteJob 队列持久化与跨进程 handoff（038 S3）

> **Status**: accepted (2026-11-01) — 2026-11-02 修订写权威口径：A2A 单次整理内联为正式路径（§2.1 / §2.7），队列只承接兜底与恢复；实现见 spec 040（P0–P3 完成）
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

### 2.1 写权威：同一写端口，两条调度路径

写权威只有一条决定：**同一份笔记内容只经 `AgentIngestService → CapturePipeline → CommandExecutor → NoteWritePort` 写入**。调度方式按入口分两条，二者都是正式路径：

- **队列路径（UI 进程）**：`WriteJobScheduler` 承接 inbox 消费、启动恢复与显式 background 任务；`agent_job` 的 claim 租约保证队列内同一时刻只有一个执行者。
- **内联路径（`:agent` 扩展进程）**：A2A 单次整理（单题 / 多题逐题 / 「全部」）在扩展进程内联执行，完成后直接在小艺回执。产品要求「不打开 App 也能整理」，因此它不经过 `WriteJobScheduler`，也不受队列 lane / 租约约束（细节见 §2.7）。
- 两条路径共享同一套写端口与幂等语义：`commitKey` / 输入指纹 / `expectedVersion` CAS 保证跨进程重放不双写；`KnowledgeUnitWriteService.writeSection` 是**进程内**串行，不是跨进程锁。
- 跨进程写加固（2026-11-02）：DB 初始化执行 `PRAGMA busy_timeout=5000`；`run_event` 建 `(run_id, sequence)` 唯一索引（旧库有重复时跳过）；`appendEvent` 对 busy / locked / 唯一冲突做有限重试。`StoreConfig` 仍无 `busy_timeout` 配置项，靠连接级 PRAGMA。

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

- 队列交接只用于兜底：A2A 超时 / 失败 / 批量溢出时，扩展把原文写入 `agent_job`（或 inbox），并立即回执；UI 进程在前台/启动时消费；
- 正常 A2A 单次整理不写队列，直接在扩展内联完成（§2.7）；App 不在前台时队列仍保证**不丢**（RDB 持久）；
- `AgentInboxQueue`（文件 JSON）迁移：首次启动把 pending 项转成 `agent_job`（source=inbox），迁移完成后新流程不再写 inbox；保留读迁移代码 1 个版本用于回滚。

### 2.5 观测与灰度

- 复用 `WriteJobEventRecorder`：job 生命周期 → run_store/run_event（runId=jobId）；新增 `job.queued/running/recovered` 等 kind；
- `scheduler-report.mjs` 读事件/状态分布；
- 灰度 flag：`WRITE_JOB_PERSIST_ENABLED` 默认 false → 设备验证后 UI 进程打开；回滚 = flag 关闭（队列退回内存，数据保留）。

### 2.7 A2A 内联整理 / 图片问答（正式路径，2026-11-01 引入 / 2026-11-02 定稿）

- 用户明确表达「整理/存笔记」意图时，`:agent` 扩展进程**内联执行**该次整理（单题/多题逐题/「全部」），完成后在小艺里直接回执——**不需要打开 App**；这是与 §2.1 队列路径并列的正式路径，不是例外；
- 用户发图且无整理意图时，扩展先 OCR 再把文字交给对话回答（图片问答，不入库）；
- 持久队列（`agent_job`）只承接：**超时/失败兜底、批量溢出、inbox 消费与启动恢复**；不是 A2A 单次整理、也不是 App 交互式整理的必经路径；
- `JOB_CLAIMED_ELSEWHERE` 类竞态不再影响 A2A（内联执行不经过 claim），队列侧保留单执行者约束。

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
- 风险点：多进程 RDB 写竞争（claim 租约 + `commitKey` 幂等 + 失败降级 inbox；2026-11-02 已补 `PRAGMA busy_timeout=5000`、`run_event` 唯一索引与 `appendEvent` 有限重试，见 spec 040 §风险）。

## 5. 影响

- spec 040（实现计划）：schema/DAO、调度器持久化与恢复、扩展内联 + 队列兜底、真机跨进程/重启验收；
- 038 状态：S1/S2 不变，S3 由 spec 040 承接；flag 默认策略更新为「SPEC 040 P3 验证后打开」。

## 6. 修订记录

- **2026-11-02**：统一写权威口径。A2A 单次整理内联是正式路径（§2.7），队列只承接兜底与恢复；删除「只有 UI 进程写 / 扩展只入队」与「扩展内联是例外」的互斥表述。跨进程 `SQLITE_BUSY` 与 `run_event` 序列无唯一约束转为显式待办，不在本轮修复。
