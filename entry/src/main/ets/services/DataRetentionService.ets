/**
 * DataRetentionService.ets — 运行记录与终态任务的保留清理
 *
 * 路径: entry/src/main/ets/services/DataRetentionService.ets
 * 职责: 删除超过 30 天的 run_event、终态 run_store、终态 agent_job，避免事件表无限增长；
 *       只清历史，running / queued 不动。
 * 依赖: common DatabaseHelper、@kit.ArkData relationalStore。
 */
import type { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseHelper } from 'common';

const DOMAIN: number = 0x0000;
const TAG: string = 'Retention';
const RETENTION_DAYS: number = 30;
const DAY_MS: number = 24 * 60 * 60 * 1000;
const RUN_TERMINAL_STATUSES: string[] = ['readyPreview', 'committed', 'cancelled', 'failed', 'timedOut'];
const JOB_TERMINAL_STATUSES: string[] = ['done', 'failed', 'cancelled'];

export interface RetentionSummary {
  runEvents: number;
  runs: number;
  jobs: number;
}

export class DataRetentionService {
  static async run(context: common.Context): Promise<RetentionSummary> {
    const store: relationalStore.RdbStore = DatabaseHelper.getStore() ?? await DatabaseHelper.init(context);
    const cutoff: number = Date.now() - RETENTION_DAYS * DAY_MS;
    const runEvents: number = await DataRetentionService.deleteOlder(store, 'run_event', 'created_at', cutoff);
    const runs: number = await DataRetentionService.deleteTerminalOlder(
      store, 'run_store', 'created_at', cutoff, RUN_TERMINAL_STATUSES);
    const jobs: number = await DataRetentionService.deleteTerminalOlder(
      store, 'agent_job', 'updated_at', cutoff, JOB_TERMINAL_STATUSES);
    const summary: RetentionSummary = { runEvents: runEvents, runs: runs, jobs: jobs };
    if (runEvents + runs + jobs > 0) {
      hilog.info(DOMAIN, TAG, 'pruned runEvents=%{public}d runs=%{public}d jobs=%{public}d',
        runEvents, runs, jobs);
    }
    return summary;
  }

  private static deleteOlder(store: relationalStore.RdbStore, table: string, column: string,
    cutoff: number): Promise<number> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(table);
    predicates.lessThan(column, cutoff);
    return store.delete(predicates);
  }

  private static deleteTerminalOlder(store: relationalStore.RdbStore, table: string, column: string,
    cutoff: number, statuses: string[]): Promise<number> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(table);
    predicates.lessThan(column, cutoff).and().in('status', statuses);
    return store.delete(predicates);
  }
}
