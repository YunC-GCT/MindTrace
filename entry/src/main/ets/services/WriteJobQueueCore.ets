/**
 * WriteJobQueueCore.ets — WriteJob 优先级队列（纯逻辑）
 *
 * 路径: entry/src/main/ets/services/WriteJobQueueCore.ets
 * 职责: interactive 优先、同级 FIFO；无 IO，可 Node 单测（spec 038 T1）。
 */
import { WriteJob, compareJobs } from './WriteJobModels';

export class WriteJobQueueCore {
  private jobs: WriteJob[] = [];

  enqueue(job: WriteJob): void {
    // 有序插入：保持 (priority, createdAt) 升序；同键时后到者排后，保证 FIFO。
    let index: number = this.jobs.length;
    for (let i = 0; i < this.jobs.length; i += 1) {
      if (compareJobs(job, this.jobs[i]) < 0) {
        index = i;
        break;
      }
    }
    this.jobs.splice(index, 0, job);
  }

  dequeue(): WriteJob | undefined {
    if (this.jobs.length === 0) {
      return undefined;
    }
    return this.jobs.shift();
  }

  size(): number {
    return this.jobs.length;
  }
}
