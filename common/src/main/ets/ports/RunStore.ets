/**
 * RunStore.ets — Run 持久化端口契约（记录 + 事件流）
 *
 * 路径: common/src/main/ets/ports/RunStore.ets
 * 职责: 定义 run 记录、事件流、端口与稳定错误类型；不含 SQL / Kit / 实现。
 * 依赖: 无（零 Kit、零模型依赖）
 *
 * 数据流（目标态）:
 *   Dispatcher / NoteAgent → RunStorePort.create / update / appendEvent → entry 适配器 → run_store / run_event
 *
 * 存储约定（schema v16，ADR-0022 之后的新迁移）:
 *   - run_store：run_id 主键、parent_run_id、status、checkpoint_id、committed_note_id / committed_version、时间戳
 *   - run_event：event_id 主键、(run_id, sequence) 唯一递增、kind、payload_json、created_at
 *   - **committed 事实不可被 cancelled 覆盖**：update 时若已有 committedNoteId，取消态必须保留它
 *
 * ArkTS 1.1 strict 适配:
 *   - status 用字符串字面量联合类型；可选字段显式声明，不使用索引签名。
 */

export type RunStatus = 'running' | 'readyPreview' | 'cancelled' | 'failed' | 'timedOut';

// 一条 run 的最小可恢复记录。
export interface RunRecord {
  runId: string;
  parentRunId?: string;
  status: RunStatus;
  checkpointId?: string;
  committedNoteId?: string;
  committedVersion?: number;
  updatedAt: number;
}

// 一条 run 事件：sequence 在同一 run 内单调递增（1 起），供重放与 Trace。
export interface RunEvent {
  eventId: string;
  runId: string;
  sequence: number;
  kind: string;
  payloadJson: string;
  createdAt: number;
}

// 端口层稳定错误：code + retryable 供 UI / A2A 分流。
export class RunStoreError extends Error {
  readonly code: string;
  readonly retryable: boolean;

  constructor(code: string, message: string, retryable: boolean) {
    super(message);
    this.name = 'RunStoreError';
    this.code = code;
    this.retryable = retryable;
  }
}

export const RUN_STORE_ERROR_RUN_NOT_FOUND: string = 'RUN_NOT_FOUND';
export const RUN_STORE_ERROR_RUN_EXISTS: string = 'RUN_EXISTS';
export const RUN_STORE_ERROR_INVALID_RUN: string = 'INVALID_RUN';
export const RUN_STORE_ERROR_FAILED: string = 'RUN_STORE_FAILED';

// 存储缝：契约在 common，实现（RunStoreDao）在 entry。
export interface RunStoreStore {
  queryRecord(runId: string): Promise<RunRecord | null>;
  insertRecord(record: RunRecord): Promise<void>;
  updateRecord(record: RunRecord): Promise<void>;
  listEvents(runId: string, afterSequence: number, limit: number): Promise<RunEvent[]>;
  appendEvent(runId: string, kind: string, payloadJson: string, createdAt: number): Promise<RunEvent>;
}

// Run 持久化端口：create / get / update 都必须保留 committed 事实，不能被 cancelled 覆盖。
export interface RunStorePort {
  create(record: RunRecord): Promise<void>;
  get(runId: string): Promise<RunRecord | null>;
  update(record: RunRecord): Promise<void>;
  appendEvent(runId: string, kind: string, payloadJson: string): Promise<RunEvent>;
  listEvents(runId: string, afterSequence?: number, limit?: number): Promise<RunEvent[]>;
}

export const RUN_EVENTS_DEFAULT_LIMIT: number = 50;
export const RUN_EVENTS_MAX_LIMIT: number = 200;
