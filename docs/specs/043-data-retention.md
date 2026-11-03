# 043 — 数据保留与清理（R6 / R7）

> **Status**: implemented (2026-11-03)
> **Related**: [spec 040](./040-writejob-persistence-cross-process.md) · [spec 042](./042-a2a-error-taxonomy.md)
> **Code**: `entry/src/main/ets/services/A2AContextCleanup.ets` · `A2AConversationStore.ets` · `A2AImageContextStore.ets` · `A2APlanStore.ets` · `DataRetentionService.ets` · `common/src/main/ets/DatabaseHelper.ets`
> **Verified by**: `node scripts/agent-gate/index.mjs`（pass=1221）；`build-hsp-hap` 4/4；真机 A2A `INGEST_TEXT done`

## 1. 背景

- **R6**：`<filesDir>/a2a/` 下的会话、图片材料、计划文件按 `contextId` / `taskId` 分文件，长期使用会无限增长；没有清理策略。
- **R7**：`run_store` / `run_event` / `agent_job` 只增不减；事件表没有保留期。

## 2. 策略

| 数据 | 保留期 | 清理时机 | 规则 |
|---|---|---|---|
| `a2a/chat-*.json` | 7 天 | `A2AController.prepare()`（`:agent`） | 按文件 mtime 删除过期文件 |
| `a2a/image-*.json` | 7 天 | 同上 | 同上 |
| `a2a/plan-*.json` / `plan.json` | 7 天 | 同上 | 同上 |
| `run_event` | 30 天 | `EntryAbility.onCreate` DB 就绪后 | 删除 `created_at < cutoff` 的全部事件 |
| `run_store` | 30 天 | 同上 | 只删终态：`readyPreview / committed / cancelled / failed / timedOut` |
| `agent_job` | 30 天 | 同上 | 只删终态：`done / failed / cancelled` |

- `running` / `queued` 永不删除。
- 清理是启动时的异步/同步尽力而为；失败只告警，不阻塞启动。

## 3. 索引

为保留查询新增：

```sql
idx_run_event_created_at ON run_event(created_at)
idx_run_store_created_at ON run_store(created_at)
idx_agent_job_updated ON agent_job(status, updated_at)
```

## 4. 非目标

- 不引入后台定时任务；只在进程启动时清理。
- 不做按用户/租户的保留策略。
- 不做事件压缩或归档。
