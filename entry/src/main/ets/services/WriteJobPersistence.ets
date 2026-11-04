/**
 * WriteJobPersistence.ets — WriteJob 持久化 hooks 与 agent_job 适配（spec 040 P1）
 *
 * 路径: entry/src/main/ets/services/WriteJobPersistence.ets
 * 职责: 把调度器的持久化接缝（enqueue/claim/finish/recover）落到 AgentJobDao；
 *       输入指纹复用 capture-input 算法（normalizeForDedupe + sourceFingerprint）。
 * 依赖: common（sourceFingerprint、AgentJobModels）、./NoteDedupe、../database/AgentJobDao。
 * 数据流: WriteJobScheduler hooks → AgentJobPersistence → AgentJobDao → agent_job
 */
import { sourceFingerprint } from 'common';

import { AgentJobDao } from '../database/AgentJobDao';
import type { AgentJob } from 'common';
import { normalizeForDedupe } from 'agents';

export interface WriteJobPersistenceHooks {
  /** 入队（幂等）：返回持久 jobId，调度器用它执行/claim。 */
  enqueue(priority: string, text: string): Promise<string>;
  /** claim 指定 job；false 表示被别人抢走/已不在 queued。 */
  claim(jobId: string): Promise<boolean>;
  /** 终态回写。 */
  finish(jobId: string, status: string, error: string): Promise<void>;
}

const LEASE_OWNER: string = 'ui-process';
const LEASE_MS: number = 5 * 60 * 1000;

/** 与 capture-input commitKey 相同的指纹算法（跨进程/重启去重）。 */
export function writeJobFingerprint(text: string): string {
  return sourceFingerprint(normalizeForDedupe(text));
}

export class AgentJobPersistence implements WriteJobPersistenceHooks {
  private readonly dao: AgentJobDao;

  constructor(dao: AgentJobDao) {
    this.dao = dao;
  }

  async enqueue(priority: string, text: string): Promise<string> {
    return await this.enqueueForSource(priority, text, 'app');
  }

  /** 跨进程 producer（A2A 扩展/inbox）指定 source；幂等仍在 DAO 层。 */
  async enqueueForSource(priority: string, text: string, source: string): Promise<string> {
    const result = await this.dao.enqueue({
      kind: 'text_ingest',
      priority: priority === 'interactive' ? 'interactive' : 'background',
      payloadText: text,
      source: source,
      fingerprint: writeJobFingerprint(text),
    });
    return result.job.jobId;
  }

  async claim(jobId: string): Promise<boolean> {
    const job: AgentJob | null = await this.dao.claimJob(jobId, LEASE_OWNER, LEASE_MS);
    return job !== null;
  }

  async finish(jobId: string, status: string, error: string): Promise<void> {
    if (status === 'done') {
      await this.dao.markDone(jobId);
      return;
    }
    await this.dao.markFailed(jobId, error);
  }

  /** 启动恢复：过期 running 回 queued，返回可执行的 queued 列表。 */
  async recover(): Promise<AgentJob[]> {
    await this.dao.recoverExpired(Date.now());
    return await this.dao.listQueued(50);
  }
}
