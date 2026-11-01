/**
 * WriteJobEventRecorder.ets — 把 WriteJob 事件落到 run_store / run_event（spec 038 S2 A8）
 *
 * 路径: entry/src/main/ets/services/WriteJobEventRecorder.ets
 * 职责: 调度器 sink 的持久化实现：每个 job 一条 run_store（run_id=writejob:<jobId>），
 *       生命周期事件写 run_event（kind=writejob:<phase>），终态更新 run 状态。
 * 依赖: common DatabaseHelper / RunRecord；entry RunStoreDao。
* 数据流: WriteJobScheduler sink → record() → RunStoreDao.appendEvent/updateRecord（run_store/run_event）
 *
 * 约束: best-effort（DB 未就绪/失败不影响写任务）；事件按 job 顺序追加（RunStoreDao 事务内取 MAX(seq)+1）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseHelper } from 'common';
import type { RunRecord } from 'common';
import { RunStoreDao } from '../database/RunStoreDao';
import { WRITE_JOB_RUN_PREFIX } from './WriteJobEvents';
import type { WriteJobEvent, WriteJobEventSink } from './WriteJobEvents';
import { AsyncMutex } from './AsyncMutex';

const DOMAIN: number = 0xA000;
const TAG: string = 'WriteJobEvent';

export class WriteJobEventRecorder {
  /** run_event 追加是事务 + MAX(seq)+1：并发写同一 store 会互相冲突，串行化（事件量小）。 */
  private static readonly writeSection: AsyncMutex = new AsyncMutex();
  /** 构造 sink（fire-and-forget；失败只告警）。 */
  static create(): WriteJobEventSink {
    const sink: WriteJobEventSink = (event: WriteJobEvent): void => {
      WriteJobEventRecorder.writeSection.runExclusive(
        async (): Promise<void> => await WriteJobEventRecorder.record(event))
        .catch((e: Error): void => {
          hilog.warn(DOMAIN, TAG, 'persist failed job=%{public}s phase=%{public}s err=%{public}s',
            event.jobId, event.phase, e.message);
        });
    };
    return sink;
  }

  private static async record(event: WriteJobEvent): Promise<void> {
    const store = DatabaseHelper.getStore();
    if (store === null) {
      return;
    }
    const dao: RunStoreDao = new RunStoreDao(store);
    const runId: string = WRITE_JOB_RUN_PREFIX + event.jobId;
    const existing: RunRecord | null = await dao.queryRecord(runId);
    if (existing === null) {
      try {
        await dao.insertRecord({ runId: runId, status: 'running', updatedAt: event.at });
      } catch (e) {
        // 历史/重入情况下 run_store 可能已存在：忽略插入失败，继续追加事件。
      }
    }
    const payload: string = JSON.stringify({
      kind: event.kind,
      priority: event.priority,
      phase: event.phase,
      queueDepth: event.queueDepth,
      waitMs: event.waitMs,
      runMs: event.runMs,
      error: event.error,
    });
    await dao.appendEvent(runId, WRITE_JOB_RUN_PREFIX + event.phase, payload, event.at);
    if (event.phase === 'done' || event.phase === 'failed') {
      try {
        await dao.updateRecord({
          runId: runId,
          status: event.phase === 'done' ? 'committed' : 'failed',
          updatedAt: event.at,
        });
      } catch (e) {
        // 记录不存在时 update 会抛错：best-effort 忽略。
      }
    }
  }
}
