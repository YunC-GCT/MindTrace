/**
 * WriteJobScheduler.ets — 写入工作调度器（双通道 + 观测 + feature flag）
 *
 * 路径: entry/src/main/ets/services/WriteJobScheduler.ets
 * 职责: 把「写笔记」任务放进 interactive / background 两条 lane（AsyncSemaphore 控并发，默认各 1），
 *       提供 submit/await、waitMs/runMs/queueDepth/maxConcurrent 统计、job 状态与 [WriteJob] 日志。
 *       S0 已证明 LLM 可自然并发；写区串行由 KnowledgeUnitWriteService 的 AsyncMutex 保证。
 * 依赖: WriteJobModels / WriteJobQueueCore / AsyncSemaphore（纯逻辑，可 Node 单测）。
 *
 * 约束: 不持久化（S1）；flag 默认关闭，关闭时接入点走原路径。
 */
import { WriteJob, WriteJobPriority } from './WriteJobModels';
import { WriteJobQueueCore } from './WriteJobQueueCore';
import { AsyncSemaphore } from './AsyncSemaphore';
import { WriteJobEvent, WriteJobEventMetrics, WriteJobEventPhase, WriteJobEventSink } from './WriteJobEvents';
import type { WriteJobPersistenceHooks } from './WriteJobPersistence';

export interface WriteJobSchedulerOptions {
  interactiveConcurrency?: number;
  backgroundConcurrency?: number;
  log?: (line: string) => void;
}

export interface WriteJobStats {
  submitted: number;
  completed: number;
  failed: number;
  queueDepth: number;
  maxConcurrent: number;
  lastWaitMs: number;
  lastRunMs: number;
}

interface WriteLane {
  priority: WriteJobPriority;
  queue: WriteJobQueueCore;
  sem: AsyncSemaphore;
}

interface PendingJob {
  job: WriteJob;
  run: () => Promise<Object>;
  resolve: (value: Object) => void;
  reject: (reason: Error) => void;
}

/** 调度器开关（默认关；设备验证后灰度打开，回滚即翻转）。 */
export class WriteJobFlags {
  private static enabled: boolean = false;

  static isEnabled(): boolean {
    return WriteJobFlags.enabled;
  }

  static setEnabled(value: boolean): void {
    WriteJobFlags.enabled = value;
  }
}

export class WriteJobScheduler {
  private static instance: WriteJobScheduler | null = null;
  private readonly interactiveLane: WriteLane;
  private readonly backgroundLane: WriteLane;
  private readonly lanes: WriteLane[] = [];
  private readonly pending: Map<string, PendingJob> = new Map<string, PendingJob>();
  private readonly log: (line: string) => void;
  private eventSink: WriteJobEventSink | null = null;
  private hooks: WriteJobPersistenceHooks | null = null;
  private activeCount: number = 0;
  private submittedCount: number = 0;
  private completedCount: number = 0;
  private failedCount: number = 0;
  private maxConcurrent: number = 0;
  private seq: number = 0;
  private lastWaitMs: number = 0;
  private lastRunMs: number = 0;

  constructor(options?: WriteJobSchedulerOptions) {
    const resolved: WriteJobSchedulerOptions = options !== undefined ? options : {};
    const interactiveCap: number = resolved.interactiveConcurrency !== undefined
      ? resolved.interactiveConcurrency : 1;
    const backgroundCap: number = resolved.backgroundConcurrency !== undefined
      ? resolved.backgroundConcurrency : 1;
    this.interactiveLane = {
      priority: 'interactive',
      queue: new WriteJobQueueCore(),
      sem: new AsyncSemaphore(interactiveCap),
    };
    this.backgroundLane = {
      priority: 'background',
      queue: new WriteJobQueueCore(),
      sem: new AsyncSemaphore(backgroundCap),
    };
    this.lanes.push(this.interactiveLane);
    this.lanes.push(this.backgroundLane);
    this.log = resolved.log !== undefined ? resolved.log : (line: string): void => { console.info(line); };
  }

  /** 进程级单例（生产接入用）。 */
  static shared(): WriteJobScheduler {
    if (WriteJobScheduler.instance === null) {
      WriteJobScheduler.instance = new WriteJobScheduler();
    }
    return WriteJobScheduler.instance;
  }

  /** 注册/清除观测 sink（S2：落 run_event；测试可注入 fake）。 */
  setEventSink(sink: WriteJobEventSink | null): void {
    this.eventSink = sink;
  }

  /** spec 040 P1：注册持久化 hooks（agent_job enqueue/claim/finish）；null 回到内存队列。 */
  setPersistenceHooks(hooks: WriteJobPersistenceHooks | null): void {
    this.hooks = hooks;
  }

  /** 提交一个写任务；返回与 executor 同结果的 Promise（失败向上抛）。 */
  submit(priority: WriteJobPriority, text: string, run: () => Promise<Object>): Promise<Object> {
    this.seq += 1;
    const job: WriteJob = {
      jobId: 'wj-' + Date.now().toString(36) + '-' + this.seq.toString(),
      kind: 'text_ingest',
      priority: priority,
      payloadText: text,
      status: 'queued',
      createdAt: Date.now(),
    };
    this.submittedCount += 1;
    let rejectPersist: (reason: Error) => void = (): void => {};
    const result: Promise<Object> = new Promise<Object>((resolve: (value: Object) => void,
      reject: (reason: Error) => void): void => {
      rejectPersist = reject;
      this.pending.set(job.jobId, { job: job, run: run, resolve: resolve, reject: reject });
    });
    if (this.hooks === null) {
      this.installJob(job);
      return result;
    }
    // 持久化：先入队（幂等）拿持久 jobId，再进入内存队列执行；claim 在 start 里做。
    this.hooks.enqueue(priority, text).then((persistedJobId: string): void => {
      const existing = this.pending.get(job.jobId);
      this.pending.delete(job.jobId);
      job.jobId = persistedJobId;
      if (existing !== undefined) {
        this.pending.set(persistedJobId, existing);
      }
      this.installJob(job);
    }).catch((error: Error): void => {
      this.pending.delete(job.jobId);
      rejectPersist(error);
    });
    return result;
  }

  /** 恢复路径：job 已在 DB queued，直接进内存队列（不再重复 enqueue）。 */
  submitRecovered(jobId: string, priority: WriteJobPriority, text: string,
    run: () => Promise<Object>): void {
    const job: WriteJob = {
      jobId: jobId,
      kind: 'text_ingest',
      priority: priority,
      payloadText: text,
      status: 'queued',
      createdAt: Date.now(),
    };
    this.pending.set(job.jobId, {
      job: job,
      run: run,
      resolve: (): void => {},
      reject: (): void => {},
    });
    this.log('[WriteJob] recovered enqueued id=' + jobId + ' priority=' + priority);
    this.installJob(job);
  }

  private installJob(job: WriteJob): void {
    this.laneOf(job.priority).queue.enqueue(job);
    const enqueuedDepth: number = this.stats().queueDepth;
    this.log('[WriteJob] enqueued id=' + job.jobId + ' priority=' + job.priority
      + ' kind=' + job.kind + ' chars=' + job.payloadText.length.toString()
      + ' depth=' + enqueuedDepth.toString());
    this.emitEvent(job, 'enqueued', {
      queueDepth: enqueuedDepth, waitMs: 0, runMs: 0, error: '',
    });
    this.pump();
  }

  stats(): WriteJobStats {
    let depth: number = 0;
    for (const lane of this.lanes) {
      depth += lane.queue.size();
    }
    const stats: WriteJobStats = {
      submitted: this.submittedCount,
      completed: this.completedCount,
      failed: this.failedCount,
      queueDepth: depth,
      maxConcurrent: this.maxConcurrent,
      lastWaitMs: this.lastWaitMs,
      lastRunMs: this.lastRunMs,
    };
    return stats;
  }

  private laneOf(priority: WriteJobPriority): WriteLane {
    return priority === 'interactive' ? this.interactiveLane : this.backgroundLane;
  }

  private pump(): void {
    let startedAny: boolean = true;
    while (startedAny) {
      startedAny = false;
      for (const lane of this.lanes) {
        while (lane.sem.available() > 0) {
          const job: WriteJob | undefined = lane.queue.dequeue();
          if (job === undefined) {
            break;
          }
          this.start(lane, job);
          startedAny = true;
        }
      }
    }
  }

  private start(lane: WriteLane, job: WriteJob): void {
    const pending: PendingJob | undefined = this.pending.get(job.jobId);
    if (pending === undefined) {
      return;
    }
    this.pending.delete(job.jobId);
    lane.sem.acquire();
    this.activeCount += 1;
    if (this.activeCount > this.maxConcurrent) {
      this.maxConcurrent = this.activeCount;
    }
    if (this.hooks !== null) {
      this.hooks.claim(job.jobId).then((claimed: boolean): void => {
        if (!claimed) {
          this.releaseSlot(lane);
          pending.reject(new Error('JOB_CLAIMED_ELSEWHERE: ' + job.jobId));
          return;
        }
        this.executePending(lane, pending, job);
      }).catch((error: Error): void => {
        this.releaseSlot(lane);
        pending.reject(error);
      });
      return;
    }
    this.executePending(lane, pending, job);
  }

  private releaseSlot(lane: WriteLane): void {
    this.activeCount = Math.max(0, this.activeCount - 1);
    lane.sem.release();
    this.pump();
  }

  private executePending(lane: WriteLane, pending: PendingJob, job: WriteJob): void {
    job.status = 'running';
    const waitMs: number = Date.now() - job.createdAt;
    const startedAt: number = Date.now();
    this.log('[WriteJob] started id=' + job.jobId + ' priority=' + job.priority
      + ' waitMs=' + waitMs.toString() + ' active=' + this.activeCount.toString());
    this.emitEvent(job, 'started', {
      queueDepth: this.stats().queueDepth, waitMs: waitMs, runMs: 0, error: '',
    });
    let task: Promise<Object>;
    try {
      task = pending.run();
    } catch (error) {
      // executor 同步抛错：必须走统一失败收尾，否则 lane 永久占死。
      this.settleFailure(lane, pending, (error as Error), waitMs, startedAt);
      return;
    }
    task
      .then((value: Object): void => {
        job.status = 'done';
        this.completedCount += 1;
        this.lastWaitMs = waitMs;
        this.lastRunMs = Date.now() - startedAt;
        this.log('[WriteJob] done id=' + job.jobId + ' priority=' + job.priority
          + ' runMs=' + this.lastRunMs.toString() + ' waitMs=' + waitMs.toString());
        this.emitEvent(job, 'done', {
          queueDepth: this.stats().queueDepth, waitMs: waitMs, runMs: this.lastRunMs, error: '',
        });
        this.persistFinish(job.jobId, 'done', '');
        pending.resolve(value);
        this.finish(lane);
      })
      .catch((error: Error): void => {
        this.settleFailure(lane, pending, error, waitMs, startedAt);
      });
  }

  private settleFailure(lane: WriteLane, pending: PendingJob, error: Error,
    waitMs: number, startedAt: number): void {
    pending.job.status = 'failed';
    this.failedCount += 1;
    this.lastWaitMs = waitMs;
    this.lastRunMs = Date.now() - startedAt;
    this.log('[WriteJob] failed id=' + pending.job.jobId + ' priority=' + pending.job.priority
      + ' runMs=' + this.lastRunMs.toString() + ' err=' + error.message);
    this.emitEvent(pending.job, 'failed', {
      queueDepth: this.stats().queueDepth, waitMs: waitMs, runMs: this.lastRunMs, error: error.message,
    });
    this.persistFinish(pending.job.jobId, 'failed', error.message);
    pending.reject(error);
    this.finish(lane);
  }

  private emitEvent(job: WriteJob, phase: WriteJobEventPhase, metrics: WriteJobEventMetrics): void {
    if (this.eventSink === null) {
      return;
    }
    const event: WriteJobEvent = {
      jobId: job.jobId,
      kind: job.kind,
      priority: job.priority,
      phase: phase,
      queueDepth: metrics.queueDepth,
      waitMs: metrics.waitMs,
      runMs: metrics.runMs,
      error: metrics.error,
      at: Date.now(),
    };
    try {
      this.eventSink(event);
    } catch (e) {
      // sink 异常不影响写任务
    }
  }

  private persistFinish(jobId: string, status: string, error: string): void {
    if (this.hooks === null) {
      return;
    }
    this.hooks.finish(jobId, status, error).catch((): void => {});
  }

  private finish(lane: WriteLane): void {
    this.activeCount = Math.max(0, this.activeCount - 1);
    lane.sem.release();
    this.pump();
  }
}
