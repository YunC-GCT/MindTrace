/**
 * ReviewWriteStoreDao.ets — ReviewWriteStore 的生产实现（review_item / review_log / review_op）
 *
 * 路径: entry/src/main/ets/database/ReviewWriteStoreDao.ets
 * 职责: 复习条目 upsert 与复习日志追加，每个写操作都在**同一事务**里写业务行 + review_op，
 *       保证 operationId 幂等原子化。
 * 依赖: @kit.ArkData（relationalStore）、common 的契约类型与 uuid。
 *
 * 数据流:
 *   ReviewWritePortAdapter → upsertItem / appendLog → review_item + review_log + review_op
 *
 * schema（v23）:
 *   review_op(operation_id PK, kind, item_id, log_id, committed_at)
 */
import { relationalStore } from '@kit.ArkData';
import { REVIEW_WRITE_ERROR_ITEM_NOT_FOUND, ReviewPortError, ReviewStatus, uuid } from 'common';
import type {
  ReviewItem,
  ReviewLogEntry,
  ReviewOperationRecord,
  ReviewWriteCommand,
  ReviewWriteStore,
} from 'common';

const ITEM_COLUMNS: string = 'id, unit_id, subject, status, next_review_at, interval_days, ease_factor,'
  + ' repetitions, lapses, last_reviewed_at, created_at, updated_at';
const LOG_COLUMNS: string = 'id, review_item_id, unit_id, reviewed_at, grade, correct, duration_ms,'
  + ' interval_before, interval_after';
const OP_COLUMNS: string = 'operation_id, kind, item_id, log_id, committed_at';

export class ReviewWriteStoreDao implements ReviewWriteStore {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async queryOperation(operationId: string): Promise<ReviewOperationRecord | null> {
    const sql: string = 'SELECT ' + OP_COLUMNS + ' FROM review_op WHERE operation_id = ? LIMIT 1';
    const resultSet: relationalStore.ResultSet = await this.store.querySql(sql, [operationId]);
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      return ReviewWriteStoreDao.toOperation(resultSet);
    } finally {
      resultSet.close();
    }
  }

  async queryItem(id: string): Promise<ReviewItem | null> {
    const sql: string = 'SELECT ' + ITEM_COLUMNS + ' FROM review_item WHERE id = ? LIMIT 1';
    const resultSet: relationalStore.ResultSet = await this.store.querySql(sql, [id]);
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      return ReviewWriteStoreDao.toItem(resultSet);
    } finally {
      resultSet.close();
    }
  }

  async queryLog(id: string): Promise<ReviewLogEntry | null> {
    const sql: string = 'SELECT ' + LOG_COLUMNS + ' FROM review_log WHERE id = ? LIMIT 1';
    const resultSet: relationalStore.ResultSet = await this.store.querySql(sql, [id]);
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      return ReviewWriteStoreDao.toLog(resultSet);
    } finally {
      resultSet.close();
    }
  }

  async upsertItem(item: ReviewItem, command: ReviewWriteCommand): Promise<ReviewItem> {
    const id: string = item.id.length > 0 ? item.id : uuid();
    const now: number = Date.now();
    const transaction: relationalStore.Transaction = await this.store.createTransaction();
    try {
      const existing: ReviewItem | null = await ReviewWriteStoreDao.queryItemInTransaction(transaction, id);
      const createdAt: number = existing !== null
        ? existing.createdAt
        : (item.createdAt > 0 ? item.createdAt : now);
      const bucket: relationalStore.ValuesBucket = {
        'id': id,
        'unit_id': item.unitId,
        'subject': item.subject,
        'status': item.status.toString(),
        'next_review_at': item.nextReviewAt,
        'interval_days': item.intervalDays,
        'ease_factor': item.easeFactor,
        'repetitions': item.repetitions,
        'lapses': item.lapses,
        'last_reviewed_at': item.lastReviewedAt,
        'created_at': createdAt,
        'updated_at': now,
      };
      if (existing === null) {
        await transaction.insert('review_item', bucket);
      } else {
        const predicates = new relationalStore.RdbPredicates('review_item');
        predicates.equalTo('id', id);
        await transaction.update(bucket, predicates);
      }
      await ReviewWriteStoreDao.insertOperation(transaction, command.operationId, 'schedule', id, '', now);
      await transaction.commit();
      return {
        id: id,
        unitId: item.unitId,
        subject: item.subject,
        status: item.status,
        nextReviewAt: item.nextReviewAt,
        intervalDays: item.intervalDays,
        easeFactor: item.easeFactor,
        repetitions: item.repetitions,
        lapses: item.lapses,
        lastReviewedAt: item.lastReviewedAt,
        createdAt: createdAt,
        updatedAt: now,
      };
    } catch (e) {
      await ReviewWriteStoreDao.rollbackQuietly(transaction);
      const message: string = e instanceof Error ? e.message : String(e);
      throw new Error('ReviewWriteStoreDao.upsertItem failed: ' + message);
    }
  }

  async appendLog(item: ReviewItem, entry: ReviewLogEntry,
    command: ReviewWriteCommand): Promise<ReviewLogEntry> {
    const now: number = Date.now();
    const logId: string = entry.id.length > 0 ? entry.id : uuid();
    const reviewedAt: number = entry.reviewedAt > 0 ? entry.reviewedAt : now;
    const transaction: relationalStore.Transaction = await this.store.createTransaction();
    try {
      const existing: ReviewItem | null = await ReviewWriteStoreDao.queryItemInTransaction(transaction, item.id);
      if (existing === null) {
        throw new ReviewPortError(REVIEW_WRITE_ERROR_ITEM_NOT_FOUND,
          'review item not found: ' + item.id, false);
      }
      const logBucket: relationalStore.ValuesBucket = {
        'id': logId,
        'review_item_id': item.id,
        'unit_id': item.unitId,
        'reviewed_at': reviewedAt,
        'grade': entry.grade,
        'correct': entry.correct ? 1 : 0,
        'duration_ms': entry.durationMs,
        'interval_before': entry.intervalBefore,
        'interval_after': entry.intervalAfter,
      };
      await transaction.insert('review_log', logBucket);
      const itemBucket: relationalStore.ValuesBucket = {
        'unit_id': item.unitId,
        'subject': item.subject,
        'status': item.status.toString(),
        'next_review_at': item.nextReviewAt,
        'interval_days': item.intervalDays,
        'ease_factor': item.easeFactor,
        'repetitions': item.repetitions,
        'lapses': item.lapses,
        'last_reviewed_at': item.lastReviewedAt,
        'updated_at': now,
      };
      const predicates = new relationalStore.RdbPredicates('review_item');
      predicates.equalTo('id', item.id);
      await transaction.update(itemBucket, predicates);
      await ReviewWriteStoreDao.insertOperation(transaction, command.operationId, 'record', item.id, logId, now);
      await transaction.commit();
      return {
        id: logId,
        reviewItemId: item.id,
        unitId: item.unitId,
        reviewedAt: reviewedAt,
        grade: entry.grade,
        correct: entry.correct,
        durationMs: entry.durationMs,
        intervalBefore: entry.intervalBefore,
        intervalAfter: entry.intervalAfter,
      };
    } catch (e) {
      await ReviewWriteStoreDao.rollbackQuietly(transaction);
      if (e instanceof ReviewPortError) {
        throw new ReviewPortError(e.code, e.message, e.retryable);
      }
      const message: string = e instanceof Error ? e.message : String(e);
      throw new Error('ReviewWriteStoreDao.appendLog failed: ' + message);
    }
  }

  private static async queryItemInTransaction(transaction: relationalStore.Transaction,
    id: string): Promise<ReviewItem | null> {
    const sql: string = 'SELECT ' + ITEM_COLUMNS + ' FROM review_item WHERE id = ? LIMIT 1';
    return new Promise<ReviewItem | null>((resolve, reject) => {
      transaction.querySql(sql, [id], (err, resultSet) => {
        if (err) {
          reject(new Error('ReviewWriteStoreDao.queryItemInTransaction failed: ' + err.message));
          return;
        }
        let found: ReviewItem | null = null;
        if (resultSet.goToFirstRow()) {
          found = ReviewWriteStoreDao.toItem(resultSet);
        }
        resultSet.close();
        resolve(found);
      });
    });
  }

  private static async insertOperation(transaction: relationalStore.Transaction,
    operationId: string, kind: string, itemId: string, logId: string, committedAt: number): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'operation_id': operationId,
      'kind': kind,
      'item_id': itemId,
      'log_id': logId,
      'committed_at': committedAt,
    };
    await transaction.insert('review_op', bucket);
  }

  private static async rollbackQuietly(transaction: relationalStore.Transaction): Promise<void> {
    try {
      await transaction.rollback();
    } catch (e) {
      // 回滚失败不掩盖原始错误
    }
  }

  private static toItem(rs: relationalStore.ResultSet): ReviewItem {
    return {
      id: ReviewWriteStoreDao.readString(rs, 'id'),
      unitId: ReviewWriteStoreDao.readString(rs, 'unit_id'),
      subject: ReviewWriteStoreDao.readString(rs, 'subject'),
      status: ReviewWriteStoreDao.readString(rs, 'status') as ReviewStatus,
      nextReviewAt: ReviewWriteStoreDao.readLong(rs, 'next_review_at'),
      intervalDays: ReviewWriteStoreDao.readLong(rs, 'interval_days'),
      easeFactor: ReviewWriteStoreDao.readDouble(rs, 'ease_factor'),
      repetitions: ReviewWriteStoreDao.readLong(rs, 'repetitions'),
      lapses: ReviewWriteStoreDao.readLong(rs, 'lapses'),
      lastReviewedAt: ReviewWriteStoreDao.readLong(rs, 'last_reviewed_at'),
      createdAt: ReviewWriteStoreDao.readLong(rs, 'created_at'),
      updatedAt: ReviewWriteStoreDao.readLong(rs, 'updated_at'),
    };
  }

  private static toLog(rs: relationalStore.ResultSet): ReviewLogEntry {
    return {
      id: ReviewWriteStoreDao.readString(rs, 'id'),
      reviewItemId: ReviewWriteStoreDao.readString(rs, 'review_item_id'),
      unitId: ReviewWriteStoreDao.readString(rs, 'unit_id'),
      reviewedAt: ReviewWriteStoreDao.readLong(rs, 'reviewed_at'),
      grade: ReviewWriteStoreDao.readString(rs, 'grade'),
      correct: ReviewWriteStoreDao.readLong(rs, 'correct') === 1,
      durationMs: ReviewWriteStoreDao.readLong(rs, 'duration_ms'),
      intervalBefore: ReviewWriteStoreDao.readLong(rs, 'interval_before'),
      intervalAfter: ReviewWriteStoreDao.readLong(rs, 'interval_after'),
    };
  }

  private static toOperation(rs: relationalStore.ResultSet): ReviewOperationRecord {
    return {
      operationId: ReviewWriteStoreDao.readString(rs, 'operation_id'),
      kind: ReviewWriteStoreDao.readString(rs, 'kind'),
      itemId: ReviewWriteStoreDao.readString(rs, 'item_id'),
      logId: ReviewWriteStoreDao.readString(rs, 'log_id'),
      committedAt: ReviewWriteStoreDao.readLong(rs, 'committed_at'),
    };
  }

  private static readString(rs: relationalStore.ResultSet, column: string): string {
    try {
      return rs.getString(rs.getColumnIndex(column));
    } catch (e) {
      return '';
    }
  }

  private static readLong(rs: relationalStore.ResultSet, column: string): number {
    try {
      return rs.getLong(rs.getColumnIndex(column));
    } catch (e) {
      return 0;
    }
  }

  private static readDouble(rs: relationalStore.ResultSet, column: string): number {
    try {
      return rs.getDouble(rs.getColumnIndex(column));
    } catch (e) {
      return 0;
    }
  }
}
