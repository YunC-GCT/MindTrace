/**
 * ReviewWritePortAdapter.ets — ReviewWritePort 的 entry 侧实现（幂等）
 *
 * 路径: entry/src/main/ets/database/ReviewWritePortAdapter.ets
 * 职责: 复习写入协议：operationId 幂等、错误码与 retryable 分流；
 *       持久化交给注入的 ReviewWriteStore（生产是 ReviewWriteStoreDao）。
 * 依赖: common 的契约与错误类型；运行期只依赖注入的 store。
 *
 * 数据流:
 *   ReviewAgent / review.plan → schedule / record → ReviewWriteStore → review_item / review_log / review_op
 *
 * 边界（ADR-0022）:
 *   - SM-2 的间隔与分数在调用方算好，端口只负责落库。
 *   - 同一 operationId 重放返回首次结果（duplicate=true），不再写。
 */
import {
  REVIEW_WRITE_ERROR_INVALID_ITEM,
  REVIEW_WRITE_ERROR_ITEM_NOT_FOUND,
  REVIEW_WRITE_ERROR_OPERATION_REQUIRED,
  REVIEW_WRITE_ERROR_WRITE_FAILED,
  ReviewPortError,
} from 'common';
import type {
  ReviewItem,
  ReviewLogEntry,
  ReviewOperationRecord,
  ReviewWriteCommand,
  ReviewWriteOutcome,
  ReviewWritePort,
  ReviewWriteStore,
} from 'common';

export class ReviewWritePortAdapter implements ReviewWritePort {
  private readonly store: ReviewWriteStore;

  constructor(store: ReviewWriteStore) {
    this.store = store;
  }

  async schedule(item: ReviewItem, command: ReviewWriteCommand): Promise<ReviewWriteOutcome> {
    ReviewWritePortAdapter.validateCommand(command);
    ReviewWritePortAdapter.validateItem(item);
    const replayed: ReviewWriteOutcome | null = await this.replay(command.operationId);
    if (replayed !== null) {
      return replayed;
    }
    let written: ReviewItem;
    try {
      written = await this.store.upsertItem(item, command);
    } catch (e) {
      ReviewWritePortAdapter.rethrow(e);
    }
    return { item: written, duplicate: false };
  }

  async record(item: ReviewItem, entry: ReviewLogEntry, command: ReviewWriteCommand): Promise<ReviewWriteOutcome> {
    ReviewWritePortAdapter.validateCommand(command);
    ReviewWritePortAdapter.validateItem(item);
    if (item.id.length === 0) {
      throw new ReviewPortError(REVIEW_WRITE_ERROR_INVALID_ITEM, 'record requires a review item id', false);
    }
    if (entry.reviewItemId.length > 0 && entry.reviewItemId !== item.id) {
      throw new ReviewPortError(REVIEW_WRITE_ERROR_INVALID_ITEM,
        'log reviewItemId does not match item id', false);
    }
    const replayed: ReviewWriteOutcome | null = await this.replay(command.operationId);
    if (replayed !== null) {
      return replayed;
    }
    let written: ReviewLogEntry;
    try {
      written = await this.store.appendLog(item, entry, command);
    } catch (e) {
      ReviewWritePortAdapter.rethrow(e);
    }
    return { item: item, log: written, duplicate: false };
  }

  private async replay(operationId: string): Promise<ReviewWriteOutcome | null> {
    let operation: ReviewOperationRecord | null = null;
    try {
      operation = await this.store.queryOperation(operationId);
    } catch (e) {
      ReviewWritePortAdapter.rethrow(e);
    }
    if (operation === null) {
      return null;
    }
    let item: ReviewItem | null = null;
    try {
      item = await this.store.queryItem(operation.itemId);
    } catch (e) {
      ReviewWritePortAdapter.rethrow(e);
    }
    if (item === null) {
      throw new ReviewPortError(REVIEW_WRITE_ERROR_ITEM_NOT_FOUND,
        'review item not found: ' + operation.itemId, false);
    }
    const outcome: ReviewWriteOutcome = { item: item, duplicate: true };
    if (operation.kind === 'record' && operation.logId.length > 0) {
      let log: ReviewLogEntry | null = null;
      try {
        log = await this.store.queryLog(operation.logId);
      } catch (e) {
        ReviewWritePortAdapter.rethrow(e);
      }
      if (log !== null) {
        outcome.log = log;
      }
    }
    return outcome;
  }

  private static validateCommand(command: ReviewWriteCommand): void {
    if (command.operationId.trim().length === 0) {
      throw new ReviewPortError(REVIEW_WRITE_ERROR_OPERATION_REQUIRED,
        'operationId is required', false);
    }
  }

  private static validateItem(item: ReviewItem): void {
    if (item.unitId.trim().length === 0) {
      throw new ReviewPortError(REVIEW_WRITE_ERROR_INVALID_ITEM,
        'review item requires a unitId', false);
    }
  }

  private static failure(error: Object): ReviewPortError {
    if (error instanceof ReviewPortError) {
      return error;
    }
    return new ReviewPortError(REVIEW_WRITE_ERROR_WRITE_FAILED,
      ReviewWritePortAdapter.messageOf(error), true);
  }

  /** ArkTS 只允许 `throw new Error(...)` 形态，统一在这里构造后抛出。 */
  private static rethrow(error: Object): void {
    const failure: ReviewPortError = ReviewWritePortAdapter.failure(error);
    throw new ReviewPortError(failure.code, failure.message, failure.retryable);
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}
