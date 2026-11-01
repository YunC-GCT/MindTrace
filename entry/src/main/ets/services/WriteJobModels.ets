/**
 * WriteJobModels.ets — 写入工作（WriteJob）纯类型与优先级（spec 038）
 *
 * 路径: entry/src/main/ets/services/WriteJobModels.ets
 * 职责: 定义「写笔记」任务的最小模型与优先级排序键；不依赖任何 Kit，可 Node 单测。
 */
export type WriteJobPriority = 'interactive' | 'background';

export interface WriteJob {
  jobId: string;
  priority: WriteJobPriority;
  payloadText: string;
  createdAt: number;
}

/** 排序键：interactive 先于 background；同优先级按创建时间 FIFO。 */
export function priorityRank(priority: WriteJobPriority): number {
  return priority === 'interactive' ? 0 : 1;
}

export function compareJobs(left: WriteJob, right: WriteJob): number {
  const rankDiff: number = priorityRank(left.priority) - priorityRank(right.priority);
  if (rankDiff !== 0) {
    return rankDiff;
  }
  return left.createdAt - right.createdAt;
}
