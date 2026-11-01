/**
 * WriteJobBootstrap.ets — 持久队列启动接线/恢复（spec 040 P1）
 *
 * 路径: entry/src/main/ets/services/WriteJobBootstrap.ets
 * 职责: flag 开启且 DB 就绪时，把 AgentJobPersistence 注册给调度器，并恢复 queued job
 *       （用 ingestSingleTextDirect 执行，避免再次走调度器包装）。
 * 依赖: common DatabaseHelper、./WriteJobConfig、./WriteJobPersistence、./WriteJobScheduler、./AgentIngestService。
 * 数据流: EntryAbility(DatabaseHelper.init 后) → WriteJobBootstrap.install() → scheduler.setPersistenceHooks + recover
 */
import { DatabaseHelper } from 'common';
import type { common } from '@kit.AbilityKit';
import { WRITE_JOB_PERSIST_ENABLED } from './WriteJobConfig';
import { WriteJobScheduler } from './WriteJobScheduler';
import { AgentJobPersistence } from './WriteJobPersistence';
import { AgentJobDao } from '../database/AgentJobDao';
import type { AgentJob } from '../models/AgentJobModels';
import { AgentIngestService } from './AgentIngestService';

const MAX_RECOVERED: number = 50;
const MAX_ATTEMPT: number = 2;

export class WriteJobBootstrap {
  /** 在 DB 就绪后调用；flag 关闭或 DB 未就绪时安全跳过。 */
  static async install(context: common.Context): Promise<void> {
    if (!WRITE_JOB_PERSIST_ENABLED) {
      return;
    }
    const store = DatabaseHelper.getStore();
    if (store === null) {
      return;
    }
    const persistence: AgentJobPersistence = new AgentJobPersistence(new AgentJobDao(store));
    WriteJobScheduler.shared().setPersistenceHooks(persistence);
    const recovered: AgentJob[] = await persistence.recover();
    const jobs: AgentJob[] = recovered.length > MAX_RECOVERED ? recovered.slice(0, MAX_RECOVERED) : recovered;
    for (const job of jobs) {
      if (job.attempt >= MAX_ATTEMPT) {
        continue;
      }
      WriteJobScheduler.shared().submitRecovered(
        job.jobId,
        job.priority,
        job.payloadText,
        async (): Promise<Object> => {
          return await AgentIngestService.ingestSingleTextDirect(context, job.payloadText) as Object;
        },
      );
    }
  }
}
