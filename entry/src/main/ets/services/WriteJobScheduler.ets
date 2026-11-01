/**
 * WriteJobScheduler.ets — 写入工作调度器（双通道 + 观测 + feature flag）
 *
 * 路径: entry/src/main/ets/services/WriteJobScheduler.ets
 * 职责: 把「写笔记」任务放进 interactive / background 两条 lane（各自并发上限，默 1），
 *       提供 submit/await、waitMs/runMs/并发峰值统计；S0 已证明 LLM 可自然并发，
 *       写区串行由 KnowledgeUnitWriteService 的 AsyncMutex 保证。
 * 依赖: WriteJobModels / WriteJobQueueCore（纯逻辑，可 Node 单测）。
 *
 * 约束: 不持久化（S1）；flag 默认关闭，关闭时接入点走原路径。
 */
import { WriteJob, WriteJobPriority } from './WriteJobModels';
import { WriteJobQueueCore } from './WriteJobQueueCore';

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
  private readonly interactiveQueue: WriteJobQueueCore = new WriteJobQueueCore();
  private readonly backgroundQueue: WriteJobQueueCore = new WriteJobQueueCore();
  private readonly pending: Map<string, PendingJob> = new Map<string, PendingJob>();
  private readonly interactiveCap: number;
  private readonly backgroundCap: number;
  private readonly log: (line: string) => void;
  private runningInteractive: number = 0;
  private runningBackground: number = 0;
  private submittedCount: number = 0;
  private completedCount: number = 0;
  private failedCount: number = 0;
  private maxConcurrent: number = 0;
  private seq: number = 0;
  private lastWaitMs: number = 0;
  private lastRunMs: number = 0;

  constructor(options?: WriteJobSchedulerOptions) {
    const resolved: WriteJobSchedulerOptions = options !== undefined ? options : {};
    this.interactiveCap = resolved.interactiveConcurrency !== undefined ? resolved.interactiveConcurrency : 1;
    this.backgroundCap = resolved.backgroundConcurrency !== undefined ? resolved.backgroundConcurrency : 1;
    this.log = resolved.log !== undefined ? resolved.log : (line: string): void => { console.info(line); };
  }

  /** 进程级单例（生产接入用）。 */
  static shared(): WriteJobScheduler {
    if (WriteJobScheduler.instance === null) {
      WriteJobScheduler.instance = new WriteJobScheduler();
    }
    return WriteJobScheduler.instance;
  }

  /** 提交一个写任务；返回与 executor 同结果的 Promise（失败向上抛）。 */
  submit(priority: WriteJobPriority, text: string, run: () => Promise<Object>): Promise<Object> {
    this.seq += 1;
    const job: WriteJob = {
      jobId: 'wj-' + Date.now().toString(36) + '-' + this.seq.toString(),
      priority: priority,
      payloadText: text,
      createdAt: Date.now(),
    };
    this.submittedCount += 1;
    const result: Promise<Object> = new Promise<Object>((resolve: (value: Object) => void,
      reject: (reason: Error) => void): void => {
      this.pending.set(job.jobId, { job: job, run: run, resolve: resolve, reject: reject });
    });
    if (priority === 'interactive') {
      this.interactiveQueue.enqueue(job);
    } else {
      this.backgroundQueue.enqueue(job);
    }
    this.log('[WriteJob] enqueued id=' + job.jobId + ' priority=' + priority
      + ' depth=' + this.stats().queueDepth.toString());
    this.pump();
    return result;
  }

  stats(): WriteJobStats {
    const stats: WriteJobStats = {
      submitted: this.submittedCount,
      completed: this.completedCount,
      failed: this.failedCount,
      queueDepth: this.interactiveQueue.size() + this.backgroundQueue.size(),
      maxConcurrent: this.maxConcurrent,
      lastWaitMs: this.lastWaitMs,
      lastRunMs: this.lastRunMs,
    };
    return stats;
  }

  private pump(): void {
    let startedAny: boolean = true;
    while (startedAny) {
      startedAny = false;
      if (this.runningInteractive < this.interactiveCap) {
        const job: WriteJob | undefined = this.interactiveQueue.dequeue();
        if (job !== undefined) {
          this.start(job);
          startedAny = true;
        }
      }
      if (this.runningBackground < this.backgroundCap) {
        const job: WriteJob | undefined = this.backgroundQueue.dequeue();
        if (job !== undefined) {
          this.start(job);
          startedAny = true;
        }
      }
    }
  }

  private start(job: WriteJob): void {
    const pending: PendingJob | undefined = this.pending.get(job.jobId);
    if (pending === undefined) {
      return;
    }
    this.pending.delete(job.jobId);
    if (job.priority === 'interactive') {
      this.runningInteractive += 1;
    } else {
      this.runningBackground += 1;
    }
    const active: number = this.runningInteractive + this.runningBackground;
    if (active > this.maxConcurrent) {
      this.maxConcurrent = active;
    }
    const waitMs: number = Date.now() - job.createdAt;
    const startedAt: number = Date.now();
    this.log('[WriteJob] started id=' + job.jobId + ' priority=' + job.priority
      + ' waitMs=' + waitMs.toString() + ' active=' + active.toString());
    pending.run()
      .then((value: Object): void => {
        this.completedCount += 1;
        this.lastWaitMs = waitMs;
        this.lastRunMs = Date.now() - startedAt;
        this.log('[WriteJob] done id=' + job.jobId + ' runMs=' + this.lastRunMs.toString()
          + ' waitMs=' + waitMs.toString());
        pending.resolve(value);
        this.finish(job);
      })
      .catch((error: Error): void => {
        this.failedCount += 1;
        this.lastWaitMs = waitMs;
        this.lastRunMs = Date.now() - startedAt;
        this.log('[WriteJob] failed id=' + job.jobId + ' runMs=' + this.lastRunMs.toString()
          + ' err=' + error.message);
        pending.reject(error);
        this.finish(job);
      });
  }

  private finish(job: WriteJob): void {
    if (job.priority === 'interactive') {
      this.runningInteractive = Math.max(0, this.runningInteractive - 1);
    } else {
      this.runningBackground = Math.max(0, this.runningBackground - 1);
    }
    this.pump();
  }
}
