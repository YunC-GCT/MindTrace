/**
 * ReviewPorts.ets — 复习读侧端口契约（ADR-0022：独立复习表）
 *
 * 路径: common/src/main/ets/ports/ReviewPorts.ets
 * 职责: 定义复习条目 / 复习日志投影与只读端口；不含 SM-2 计算、不含写入实现。
 * 依赖: ../models/CommonTypes（ReviewStatus，相对路径，避免 barrel 循环）
 *
 * 数据流:
 *   ReviewAgent / 待办 UI → listDue / getByUnit / history → 适配器 → review_item / review_log
 *
 * 边界（ADR-0022）:
 *   - SM-2 调度算法属于 `review.plan` 工具，不在端口层；端口只负责读取已落库的状态。
 *   - 写侧（schedule / record）随 ReviewAgent 实现票一起定义，本切片只做只读。
 *   - 读实现按 ADR-0021 放 `common/ports/impl`，供 entry / skill / 未来的 ReviewAgent 共用。
 */
import { ReviewStatus } from '../models/CommonTypes';

export const REVIEW_DUE_DEFAULT_LIMIT: number = 20;
export const REVIEW_DUE_MAX_LIMIT: number = 100;

// 一条复习条目（review_item 投影）。
export interface ReviewItem {
  id: string;
  unitId: string;
  subject: string;
  status: ReviewStatus;
  nextReviewAt: number;
  intervalDays: number;
  easeFactor: number;
  repetitions: number;
  lapses: number;
  lastReviewedAt: number;
  createdAt: number;
  updatedAt: number;
}

// 一条复习日志（review_log 投影）。
export interface ReviewLogEntry {
  id: string;
  reviewItemId: string;
  unitId: string;
  reviewedAt: number;
  grade: string;
  correct: boolean;
  durationMs: number;
  intervalBefore: number;
  intervalAfter: number;
}

// 读侧存储缝：契约在 common，RDB 实现（RdbReviewReadStore）也在 common/ports/impl。
export interface ReviewReadStore {
  listDue(now: number, limit: number): Promise<ReviewItem[]>;
  getByUnit(unitId: string): Promise<ReviewItem | null>;
  listLogs(unitId: string, limit: number): Promise<ReviewLogEntry[]>;
}

// 读侧端口。
export interface ReviewReadPort {
  listDue(now: number, limit?: number): Promise<ReviewItem[]>;
  getByUnit(unitId: string): Promise<ReviewItem | null>;
  history(unitId: string, limit?: number): Promise<ReviewLogEntry[]>;
}

// 读侧稳定错误码与错误类型（与其它 Port 一致）。
export const REVIEW_READ_ERROR_INVALID_QUERY: string = 'INVALID_QUERY';
export const REVIEW_READ_ERROR_READ_FAILED: string = 'REVIEW_READ_FAILED';

export class ReviewPortError extends Error {
  readonly code: string;
  readonly retryable: boolean;

  constructor(code: string, message: string, retryable: boolean) {
    super(message);
    this.name = 'ReviewPortError';
    this.code = code;
    this.retryable = retryable;
  }
}

// ==================== 写侧（schedule / record，随 ReviewAgent 票） ====================

// 写命令：operationId 必填，作为幂等键；同一 operationId 重放不产生第二次写入。
export interface ReviewWriteCommand {
  operationId: string;
}

// 写操作记录：与业务写入放在同一事务里（review_op 表）。
export interface ReviewOperationRecord {
  operationId: string;
  kind: string;      // 'schedule' | 'record'
  itemId: string;
  logId: string;     // schedule 为空串
  committedAt: number;
}

// 写回执：duplicate=true 表示同一 operationId 重放。
export interface ReviewWriteOutcome {
  item: ReviewItem;
  log?: ReviewLogEntry;
  duplicate: boolean;
}

// 写侧存储缝：契约在 common，RDB 实现（ReviewWriteStoreDao）在 entry。
// 两个写方法都必须把「业务写入 + review_op 操作记录」放在同一事务里。
export interface ReviewWriteStore {
  queryOperation(operationId: string): Promise<ReviewOperationRecord | null>;
  queryItem(id: string): Promise<ReviewItem | null>;
  queryLog(id: string): Promise<ReviewLogEntry | null>;
  upsertItem(item: ReviewItem, command: ReviewWriteCommand): Promise<ReviewItem>;
  appendLog(item: ReviewItem, entry: ReviewLogEntry, command: ReviewWriteCommand): Promise<ReviewLogEntry>;
}

// 写侧端口：只负责落库已算好的调度结果，不含 SM-2 计算（那属于 review.plan 工具）。
export interface ReviewWritePort {
  schedule(item: ReviewItem, command: ReviewWriteCommand): Promise<ReviewWriteOutcome>;
  record(item: ReviewItem, entry: ReviewLogEntry, command: ReviewWriteCommand): Promise<ReviewWriteOutcome>;
}

// 写侧稳定错误码（与其它 Port 一致）。
export const REVIEW_WRITE_ERROR_OPERATION_REQUIRED: string = 'OPERATION_ID_REQUIRED';
export const REVIEW_WRITE_ERROR_INVALID_ITEM: string = 'INVALID_REVIEW_ITEM';
export const REVIEW_WRITE_ERROR_ITEM_NOT_FOUND: string = 'REVIEW_ITEM_NOT_FOUND';
export const REVIEW_WRITE_ERROR_WRITE_FAILED: string = 'REVIEW_WRITE_FAILED';
