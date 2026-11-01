/**
 * WriteJobEvents.ets — WriteJob 生命周期事件（观测契约，spec 038 S2）
 *
 * 路径: entry/src/main/ets/services/WriteJobEvents.ets
 * 职责: 定义 enqueued/started/done/failed 事件形状、metrics 与 sink；调度器发出、recorder 落 run_event。
 * 依赖: ./WriteJobModels（kind/priority 复用既有类型）
 * 数据流: WriteJobScheduler.emitEvent() → WriteJobEventSink → WriteJobEventRecorder（run_store/run_event）
 */
import type { WriteJobKind, WriteJobPriority } from './WriteJobModels';

export type WriteJobEventPhase = 'enqueued' | 'started' | 'done' | 'failed';

/** 事件度量：排队深度 + 等待/执行耗时 + 错误（避免六位置参数与 0/'' 哨兵散落调用点）。 */
export interface WriteJobEventMetrics {
  queueDepth: number;
  waitMs: number;
  runMs: number;
  error: string;
}

export interface WriteJobEvent {
  jobId: string;
  kind: WriteJobKind;
  priority: WriteJobPriority;
  phase: WriteJobEventPhase;
  queueDepth: number;
  waitMs: number;
  runMs: number;
  error: string;
  at: number;
}

export type WriteJobEventSink = (event: WriteJobEvent) => void;

/** run_store/run_event 的 run_id 前缀（事件唯一命名空间）。 */
export const WRITE_JOB_RUN_PREFIX: string = 'writejob:';
