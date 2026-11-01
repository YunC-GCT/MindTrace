# 040 — WriteJob 持久队列与跨进程 handoff（038 S3）

> **Status**: proposed (2026-11-01)
> **Related**: [ADR-0024](../adr/0024-writejob-persistence-cross-process.md) · [spec 038](./038-write-job-scheduler.md) · [spec 039](./039-agent-workflow-first.md) · [ADR-0008](../adr/0008-capturegraph-self-built-runtime.md) · [ADR-0019](../adr/0019-note-command-and-outcome.md)
> **Code**: `common/src/main/ets/DatabaseHelper.ets` · `entry/src/main/ets/database/`（新 `AgentJobDao.ets`） · `entry/src/main/ets/services/WriteJobScheduler.ets` · `entry/src/main/ets/agentextability/AgentExtAbility.ets` · `entry/src/main/ets/services/A2AInboxIngestService.ets`
> **Verified by**: 实现后回填（gate / 真机跨进程与重启 e2e / scheduler-report）

## 1. 目标

把 038 S1/S2 的进程内 `WriteJob` 队列升级为**持久、可恢复、可跨进程交接**的队列：

- App 被杀/重启后 queued job 不丢；
- A2A `:agent` 进程只把长任务**交接**给 UI 进程执行，不再自己跑 ingest；
- 保持 038 已有的双 lane / 观测 / 幂等 / flag 回滚能力。

决策依据见 [ADR-0024](../adr/0024-writejob-persistence-cross-process.md)。

## 2. 范围

### In scope

1. schema v20：`agent_job` 表 + `AgentJobDao`（additive，不动既有表）；
2. `WriteJobScheduler` 持久化：enqueue 落库、启动恢复、claim（租约）、终态回写、失败重试策略；
3. 跨进程 producer：`AgentExtAbility` / `AgentIngestService` 改为「入队 + 回执已受理」，UI 进程消费；
4. inbox 迁移：pending `AgentInboxQueue` 项 → `agent_job`（一次），保留回滚读路径；
5. 观测：job 生命周期事件 + `scheduler-report` 状态分布；flag `WRITE_JOB_PERSIST_ENABLED`（默认关 → 验证后开）；
6. 测试与真机验收（跨进程/重启/幂等/灰度回退）。

### Out of scope

- runtime checkpoint / 图内 HITL（ADR-0008）；
- 模型熔断/备用 provider；多执行者分布式调度；payload 加密；事件表清理策略（单独排期）。

## 3. 设计要点（ADR-0024 展开）

- **状态机**：`queued → running → done|failed|cancelled`；attempt 上限 2（仅 retryable 重试）；
- **单执行者**：UI 进程调度器 + `AsyncMutex` 写区；扩展进程只 INSERT；
- **租约**：claim 事务条件更新；启动时 `running` 且租约过期 → 回 queued（attempt+1）；
- **幂等**：fingerprint 去重入队；执行侧沿用 capture-input commitKey/写端口 CAS；
- **inbox 迁移**：首启一次性迁移（记录 migration 标记），回滚版本仍读 inbox；
- **观测**：`[WriteJob]` 日志 + run_event（runId=jobId；`job.recovered` 等新增 kind）；
- **flag**：默认 false；P3 真机通过后 UI 进程打开；扩展进程仍只入队（不读 flag 也可安全入队）。

## 4. TDD 切片

| # | 内容 | 测试 |
|---|---|---|
| P0 | schema v20 + `AgentJobDao`（insert/claim/lease/finish/list/recover） | `v7-agent-job-dao.test.mjs`（内存 RDB 桩或 SQL guard）+ 迁移纯函数 |
| P1 | `WriteJobScheduler` 持久化：enqueue write、startup recovery、claim 失败跳过、终态回写、重试 | `v7-write-job-persist.test.mjs`（注入 fake repository；恢复/租约/attempt） |
| P2 | 跨进程 producer：`AgentIngestService` 入队并回执；`A2AInboxIngestService` 先迁移/后消费；扩展进程不执行 | 契约守卫 + `v7-a2a-inbox` 更新 |
| P3 | 真机 e2e：`schedulerPersist`（重启恢复/跨进程入队/幂等/flag 开关） | 设备 e2e 模式 + scheduler-report |

每片一个可回滚 commit；旧内存路径在 flag 关时保留（同 S2 行为）。

## 5. 验收

- [ ] `agent-gate --all` RESULT: PASS（单测数不下降）；
- [ ] schema v20 迁移可重复执行（fresh + 老库各一次），inbox 迁移幂等；
- [ ] 真机：A2A 整理请求返回「已受理」后，UI 进程消费并落库；App 重启后 queued job 继续执行（e2e=schedulerPersist）；
- [ ] 同 fingerprint 重复入队不双写；两进程同时发请求只执行一次（租约）；
- [ ] flag 关闭时回到 038 S2 内存行为（旧 e2e 通过）；
- [ ] 文档：ADR-0024 / 本 spec / 038 S3 状态 / scheduler-report 状态分布。

## 6. 风险与回退

| 风险 | 缓解 |
|---|---|
| 多进程 RDB 写竞争 | `busy_timeout` + 入队重试 + claim 事务；失败降级 inbox |
| payload 变长/隐私 | 只存待整理原文；完成后可清理策略 |
| 迁移失败 | 迁移标记 + 可重入；inbox 原文件保留一个版本 |
| A2A UX 变化（立即回执） | 回执文案「已受理，稍后自动整理」；deadline 路径保留 |
| 回滚 | flag 关闭 → 内存队列；表保留；inbox 仍可读 |

## 7. 顺序

```
P0 schema/DAO → P1 scheduler 持久化/恢复 → P2 跨进程 producer + inbox 迁移 → P3 真机验收 + 灰度
```

P3 通过后再更新 038 状态为「实现完成（含 S3）」并把 flag 灰度打开。
