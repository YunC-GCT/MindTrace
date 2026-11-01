/**
 * WriteJobEvents.ets — WriteJob 生命周期事件（观测契约，spec 038 S2）
 *
 * 路径: entry/src/main/ets/services/WriteJobEvents.ets
 * 职责: 定义 enqueued/started/done/failed 事件形状与 sink 类型；调度器发出、recorder 落 run_event。
 * 依赖: 无（纯类型，可 Node 单测）
 */
export type WriteJobEventPhase = 'enqueued' | 'started' | 'done' | 'failed';

export interface WriteJobEvent {
  jobId: string;
  kind: string;
  priority: string;
  phase: WriteJobEventPhase;
  queueDepth: number;
  waitMs: number;
  runMs: number;
  error: string;
  at: number;
}

export type WriteJobEventSink = (event: WriteJobEvent) => void;
