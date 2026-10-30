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
