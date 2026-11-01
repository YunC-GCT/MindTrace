/**
 * AgentJobModels.ets — WriteJob 持久队列的类型与纯函数（spec 040 P0）
 *
 * 路径: entry/src/main/ets/models/AgentJobModels.ets
 * 职责: 定义持久队列 `agent_job` 的行模型、状态机/优先级纯函数；不依赖 Kit，可 Node 单测。
 * 依赖: 无
 * 数据流: WriteJobScheduler/AgentJobDao → AgentJob 模型 → agent_job 表
 */
export type AgentJobKind = 'text_ingest' | 'image_ingest';
export type AgentJobPriority = 'interactive' | 'background';
export type AgentJobStatus = 'queued' | 'running' | 'done' | 'failed' | 'cancelled';

export interface AgentJob {
  jobId: string;
  kind: AgentJobKind;
  priority: AgentJobPriority;
  payloadText: string;
  source: string;
  status: AgentJobStatus;
  attempt: number;
  fingerprint: string;
  leaseOwner: string;
  leaseExpiresAt: number;
  error: string;
  createdAt: number;
  updatedAt: number;
}

export interface AgentJobEnqueueInput {
  kind: AgentJobKind;
  priority: AgentJobPriority;
  payloadText: string;
  source: string;
  fingerprint: string;
}

export interface AgentJobEnqueueResult {
  job: AgentJob;
  reused: boolean;
}

/** 终态集合：用于入队去重与恢复逻辑。 */
export function isTerminalAgentJobStatus(status: string): boolean {
  return status === 'done' || status === 'failed' || status === 'cancelled';
}

/** 优先级排序：interactive 先于 background。 */
export function agentJobPriorityRank(priority: string): number {
  return priority === 'interactive' ? 0 : 1;
}

/** 恢复时是否应重新入队：queued 或 running 且租约已过期。 */
export function shouldRecoverAgentJob(status: string, leaseExpiresAt: number, now: number): boolean {
  if (status === 'queued') {
    return true;
  }
  return status === 'running' && leaseExpiresAt > 0 && leaseExpiresAt < now;
}
