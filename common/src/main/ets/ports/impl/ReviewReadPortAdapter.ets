/**
 * ReviewReadPortAdapter.ets — ReviewReadPort 的只读实现（参数校验 / limit 夹取 / 错误分流）
 *
 * 路径: common/src/main/ets/ports/impl/ReviewReadPortAdapter.ets
 * 职责: 把 ReviewReadStore 的只读查询暴露成端口语义；不做 SM-2 计算、不写库。
 * 依赖: ../ReviewPorts（契约与错误类型）。
 *
 * 数据流:
 *   ReviewAgent / 待办 UI → listDue / getByUnit / history → ReviewReadStore → review_item / review_log
 */
import {
  REVIEW_DUE_DEFAULT_LIMIT,
  REVIEW_DUE_MAX_LIMIT,
  REVIEW_READ_ERROR_INVALID_QUERY,
  REVIEW_READ_ERROR_READ_FAILED,
  ReviewPortError,
} from '../ReviewPorts';
import type { ReviewItem, ReviewLogEntry, ReviewReadPort, ReviewReadStore } from '../ReviewPorts';

export class ReviewReadPortAdapter implements ReviewReadPort {
  private readonly store: ReviewReadStore;

  constructor(store: ReviewReadStore) {
    this.store = store;
  }

  async listDue(now: number, limit?: number): Promise<ReviewItem[]> {
    if (now <= 0) {
      throw new ReviewPortError(REVIEW_READ_ERROR_INVALID_QUERY, 'now must be a positive epoch ms', false);
    }
    const effectiveLimit: number = ReviewReadPortAdapter.clampLimit(limit);
    try {
      return await this.store.listDue(now, effectiveLimit);
    } catch (e) {
      if (e instanceof ReviewPortError) {
        throw new ReviewPortError(e.code, e.message, e.retryable);
      }
      throw new ReviewPortError(REVIEW_READ_ERROR_READ_FAILED, ReviewReadPortAdapter.messageOf(e), true);
    }
  }

  async getByUnit(unitId: string): Promise<ReviewItem | null> {
    if (unitId.length === 0) {
      throw new ReviewPortError(REVIEW_READ_ERROR_INVALID_QUERY, 'unitId must not be empty', false);
    }
    try {
      return await this.store.getByUnit(unitId);
    } catch (e) {
      if (e instanceof ReviewPortError) {
        throw new ReviewPortError(e.code, e.message, e.retryable);
      }
      throw new ReviewPortError(REVIEW_READ_ERROR_READ_FAILED, ReviewReadPortAdapter.messageOf(e), true);
    }
  }

  async history(unitId: string, limit?: number): Promise<ReviewLogEntry[]> {
    if (unitId.length === 0) {
      throw new ReviewPortError(REVIEW_READ_ERROR_INVALID_QUERY, 'unitId must not be empty', false);
    }
    const effectiveLimit: number = ReviewReadPortAdapter.clampLimit(limit);
    try {
      return await this.store.listLogs(unitId, effectiveLimit);
    } catch (e) {
      if (e instanceof ReviewPortError) {
        throw new ReviewPortError(e.code, e.message, e.retryable);
      }
      throw new ReviewPortError(REVIEW_READ_ERROR_READ_FAILED, ReviewReadPortAdapter.messageOf(e), true);
    }
  }

  private static clampLimit(limit?: number): number {
    if (limit === undefined) {
      return REVIEW_DUE_DEFAULT_LIMIT;
    }
    if (limit < 1) {
      return 1;
    }
    if (limit > REVIEW_DUE_MAX_LIMIT) {
      return REVIEW_DUE_MAX_LIMIT;
    }
    return limit;
  }

  private static messageOf(e: Object): string {
    return e instanceof Error ? e.message : String(e);
  }
}
