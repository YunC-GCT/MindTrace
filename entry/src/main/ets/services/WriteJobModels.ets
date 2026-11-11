/**
 * WriteJobModels.ets — 写入工作（WriteJob）纯类型与优先级（spec 038）
 *
 * 路径: entry/src/main/ets/services/WriteJobModels.ets
 * 职责: 定义「写笔记」任务模型（kind/status/priority）、状态与优先级排序键；不依赖任何 Kit。
 * 依赖: 无
 */
export type WriteJobKind = 'text_ingest';
export type WriteJobPriority = 'interactive' | 'background';
export type WriteJobStatus = 'queued' | 'running' | 'done' | 'failed';

export interface WriteJob {
  jobId: string;
  kind: WriteJobKind;
  priority: WriteJobPriority;
  payloadText: string;
  status: WriteJobStatus;
  createdAt: number;
}

/** 排序键：interactive 先于 background；同优先级按创建时间 FIFO。 */
function priorityRank(priority: WriteJobPriority): number {
  return priority === 'interactive' ? 0 : 1;
}

export function compareJobs(left: WriteJob, right: WriteJob): number {
  const rankDiff: number = priorityRank(left.priority) - priorityRank(right.priority);
  if (rankDiff !== 0) {
    return rankDiff;
  }
  return left.createdAt - right.createdAt;
}
