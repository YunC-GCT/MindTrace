/**
 * AgentJobDao.ets — agent_job 持久队列 DAO（spec 040 P0 / ADR-0024）
 *
 * 路径: entry/src/main/ets/database/AgentJobDao.ets
 * 职责: `agent_job` 表的入队去重、claim（租约）、恢复、终态回写与状态统计；
 *       跨进程时 producer 只入队（兜底路径），执行侧 claim 保证同一时刻只有一个队列执行者；
 *       A2A 单次整理内联执行，不经过队列（ADR-0024 §2.7）。
 * 依赖: @kit.ArkData（relationalStore）、common uuid、AgentJobModels。
 * 数据流: WriteJobScheduler/AgentExtAbility → AgentJobDao.enqueue/claim/finish → agent_job 表
 *
 * 约束:
 *   - 入队去重：同 fingerprint 且 status ∈ queued/running 复用现有 job（部分唯一索引兜底跨进程竞争）；
 *   - claim 必须事务内条件更新（status='queued'），失败即被别人抢走；
 *   - 恢复：running 且租约过期的 job 回 queued（attempt+1，达上限 → failed）。
 */
import { relationalStore } from '@kit.ArkData';
import { uuid } from 'common';
import type {
  AgentJob,
  AgentJobEnqueueInput,
  AgentJobEnqueueResult,
  AgentJobKind,
  AgentJobPriority,
  AgentJobStatus,
} from 'common';
import { shouldRecoverAgentJob } from 'common';

const COLUMNS: string = 'job_id, kind, priority, payload_text, source, status, attempt,'
  + ' fingerprint, lease_owner, lease_expires_at, error, created_at, updated_at';
const MAX_ATTEMPT: number = 2;

export class AgentJobDao {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /** 入队（同 fingerprint 的 queued/running job 复用）；跨进程竞争由部分唯一索引 + 重查兜底。 */
  async enqueue(input: AgentJobEnqueueInput): Promise<AgentJobEnqueueResult> {
    const existing: AgentJob | null = await this.findActiveByFingerprint(input.fingerprint);
    if (existing !== null) {
      return { job: existing, reused: true };
    }
    const now: number = Date.now();
    const job: AgentJob = {
      jobId: uuid(),
      kind: input.kind,
      priority: input.priority,
      payloadText: input.payloadText,
      source: input.source,
      status: 'queued',
      attempt: 0,
      fingerprint: input.fingerprint,
      leaseOwner: '',
      leaseExpiresAt: 0,
      error: '',
      createdAt: now,
      updatedAt: now,
    };
    try {
      await this.store.insert('agent_job', AgentJobDao.toBucket(job));
    } catch (e) {
      const again: AgentJob | null = await this.findActiveByFingerprint(input.fingerprint);
      if (again !== null) {
        return { job: again, reused: true };
      }
      throw new Error('AgentJobDao.enqueue failed: ' + (e instanceof Error ? e.message : String(e)));
    }
    return { job: job, reused: false };
  }

  /** interactive 优先、同级 FIFO 取一条 queued 并 claim（事务内条件更新，抢不到返回 null）。 */
  async claim(owner: string, leaseMs: number): Promise<AgentJob | null> {
    const transaction: relationalStore.Transaction = await this.store.createTransaction();
    try {
      const resultSet: relationalStore.ResultSet = await transaction.querySql(
        "SELECT " + COLUMNS + " FROM agent_job WHERE status = 'queued'"
        + " ORDER BY CASE priority WHEN 'interactive' THEN 0 ELSE 1 END, created_at ASC LIMIT 1",
        [],
      );
      let job: AgentJob | null = null;
      try {
        if (resultSet.goToFirstRow()) {
          job = AgentJobDao.toJob(resultSet);
        }
      } finally {
        resultSet.close();
      }
      if (job === null) {
        await transaction.commit();
        return null;
      }
      const predicates = new relationalStore.RdbPredicates('agent_job');
      predicates.equalTo('job_id', job.jobId);
      predicates.equalTo('status', 'queued');
      const now: number = Date.now();
      const bucket: relationalStore.ValuesBucket = {
        'status': 'running',
        'lease_owner': owner,
        'lease_expires_at': now + leaseMs,
        'updated_at': now,
      };
      const rows: number = await transaction.update(bucket, predicates);
      if (rows === 0) {
        await transaction.rollback();
        return null;
      }
      await transaction.commit();
      job.status = 'running';
      job.leaseOwner = owner;
      job.leaseExpiresAt = now + leaseMs;
      job.updatedAt = now;
      return job;
    } catch (e) {
      try {
        await transaction.rollback();
      } catch (rollbackError) {
        // 回滚失败不掩盖原始错误
      }
      throw new Error('AgentJobDao.claim failed: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  /** 按 jobId claim（内存队列恢复用）；条件更新失败返回 null。 */
  async claimJob(jobId: string, owner: string, leaseMs: number): Promise<AgentJob | null> {
    const now: number = Date.now();
    const predicates = new relationalStore.RdbPredicates('agent_job');
    predicates.equalTo('job_id', jobId);
    predicates.equalTo('status', 'queued');
    const bucket: relationalStore.ValuesBucket = {
      'status': 'running',
      'lease_owner': owner,
      'lease_expires_at': now + leaseMs,
      'updated_at': now,
    };
    const rows: number = await this.store.update(bucket, predicates);
    if (rows === 0) {
      return null;
    }
    return await this.queryJob(jobId);
  }

  /** 启动恢复：queued 列表（按优先级/FIFO）。 */
  async listQueued(limit: number): Promise<AgentJob[]> {
    const resultSet: relationalStore.ResultSet = await this.store.querySql(
      "SELECT " + COLUMNS + " FROM agent_job WHERE status = 'queued'"
      + " ORDER BY CASE priority WHEN 'interactive' THEN 0 ELSE 1 END, created_at ASC LIMIT ?",
      [limit.toString()],
    );
    try {
      const jobs: AgentJob[] = [];
      if (resultSet.goToFirstRow()) {
        do {
          jobs.push(AgentJobDao.toJob(resultSet));
        } while (resultSet.goToNextRow());
      }
      return jobs;
    } finally {
      resultSet.close();
    }
  }

  /** 恢复租约过期的 running：attempt+1；达上限置 failed，否则回 queued。返回处理行数。 */
  async recoverExpired(now: number, maxAttempt: number = MAX_ATTEMPT): Promise<number> {
    const countResult: relationalStore.ResultSet = await this.store.querySql(
      "SELECT COUNT(*) AS c FROM agent_job WHERE status = 'running'"
      + " AND lease_expires_at > 0 AND lease_expires_at < ?", [now.toString()]);
    let count: number = 0;
    try {
      if (countResult.goToFirstRow()) {
        count = countResult.getLong(countResult.getColumnIndex('c'));
      }
    } finally {
      countResult.close();
    }
    if (count === 0) {
      return 0;
    }
    // 启动恢复路径：先统计再条件更新（单执行者启动时无并发 claim，可接受非原子）。
    await this.store.executeSql(
      "UPDATE agent_job SET attempt = attempt + 1,"
      + " status = CASE WHEN attempt + 1 >= ? THEN 'failed' ELSE 'queued' END,"
      + " lease_owner = '', lease_expires_at = 0, updated_at = ?"
      + " WHERE status = 'running' AND lease_expires_at > 0 AND lease_expires_at < ?",
      [maxAttempt.toString(), now.toString(), now.toString()],
    );
    return count;
  }

  /** 单执行者启动接管：所有 running 视为孤儿（进程崩溃/被杀，租约可能未过期）。 */
  async recoverAllRunning(now: number, maxAttempt: number = MAX_ATTEMPT): Promise<number> {
    const countResult: relationalStore.ResultSet = await this.store.querySql(
      "SELECT COUNT(*) AS c FROM agent_job WHERE status = 'running'", []);
    let count: number = 0;
    try {
      if (countResult.goToFirstRow()) {
        count = countResult.getLong(countResult.getColumnIndex('c'));
      }
    } finally {
      countResult.close();
    }
    if (count === 0) {
      return 0;
    }
    await this.store.executeSql(
      "UPDATE agent_job SET attempt = attempt + 1,"
      + " status = CASE WHEN attempt + 1 >= ? THEN 'failed' ELSE 'queued' END,"
      + " lease_owner = '', lease_expires_at = 0, updated_at = ?"
      + " WHERE status = 'running'",
      [maxAttempt.toString(), now.toString()],
    );
    return count;
  }

  async markDone(jobId: string): Promise<void> {
    await this.finish(jobId, 'done', '');
  }

  async markFailed(jobId: string, error: string): Promise<void> {
    await this.finish(jobId, 'failed', error);
  }

  async markCancelled(jobId: string, error: string = ''): Promise<void> {
    await this.finish(jobId, 'cancelled', error);
  }

  async countByStatus(status: AgentJobStatus): Promise<number> {
    const resultSet: relationalStore.ResultSet = await this.store.querySql(
      'SELECT COUNT(*) AS c FROM agent_job WHERE status = ?', [status]);
    try {
      return resultSet.goToFirstRow() ? resultSet.getLong(resultSet.getColumnIndex('c')) : 0;
    } finally {
      resultSet.close();
    }
  }

  /** 读一条 job（调度器/测试用）。 */
  async queryJob(jobId: string): Promise<AgentJob | null> {
    const resultSet: relationalStore.ResultSet = await this.store.querySql(
      'SELECT ' + COLUMNS + ' FROM agent_job WHERE job_id = ?', [jobId]);
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      return AgentJobDao.toJob(resultSet);
    } finally {
      resultSet.close();
    }
  }

  private async finish(jobId: string, status: AgentJobStatus, error: string): Promise<void> {
    const now: number = Date.now();
    const predicates = new relationalStore.RdbPredicates('agent_job');
    predicates.equalTo('job_id', jobId);
    const bucket: relationalStore.ValuesBucket = {
      'status': status,
      'error': error,
      'lease_owner': '',
      'lease_expires_at': 0,
      'updated_at': now,
    };
    const rows: number = await this.store.update(bucket, predicates);
    if (rows === 0) {
      throw new Error('AgentJobDao.finish: job not found ' + jobId);
    }
  }

  private async findActiveByFingerprint(fingerprint: string): Promise<AgentJob | null> {
    const resultSet: relationalStore.ResultSet = await this.store.querySql(
      "SELECT " + COLUMNS + " FROM agent_job WHERE fingerprint = ?"
      + " AND status IN ('queued', 'running') ORDER BY created_at ASC LIMIT 1",
      [fingerprint],
    );
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      return AgentJobDao.toJob(resultSet);
    } finally {
      resultSet.close();
    }
  }

  private static toBucket(job: AgentJob): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'job_id': job.jobId,
      'kind': job.kind,
      'priority': job.priority,
      'payload_text': job.payloadText,
      'source': job.source,
      'status': job.status,
      'attempt': job.attempt,
      'fingerprint': job.fingerprint,
      'lease_owner': job.leaseOwner,
      'lease_expires_at': job.leaseExpiresAt,
      'error': job.error,
      'created_at': job.createdAt,
      'updated_at': job.updatedAt,
    };
    return bucket;
  }

  private static toJob(resultSet: relationalStore.ResultSet): AgentJob {
    const job: AgentJob = {
      jobId: resultSet.getString(resultSet.getColumnIndex('job_id')),
      kind: resultSet.getString(resultSet.getColumnIndex('kind')) as AgentJobKind,
      priority: resultSet.getString(resultSet.getColumnIndex('priority')) as AgentJobPriority,
      payloadText: resultSet.getString(resultSet.getColumnIndex('payload_text')),
      source: resultSet.getString(resultSet.getColumnIndex('source')),
      status: resultSet.getString(resultSet.getColumnIndex('status')) as AgentJobStatus,
      attempt: resultSet.getLong(resultSet.getColumnIndex('attempt')),
      fingerprint: resultSet.getString(resultSet.getColumnIndex('fingerprint')),
      leaseOwner: resultSet.getString(resultSet.getColumnIndex('lease_owner')),
      leaseExpiresAt: resultSet.getLong(resultSet.getColumnIndex('lease_expires_at')),
      error: resultSet.getString(resultSet.getColumnIndex('error')),
      createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
      updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at')),
    };
    return job;
  }
}
