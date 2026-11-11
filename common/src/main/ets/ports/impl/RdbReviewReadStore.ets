/**
 * RdbReviewReadStore.ets — ReviewReadStore 的只读 RDB 实现（ADR-0022 复习表）
 *
 * 路径: common/src/main/ets/ports/impl/RdbReviewReadStore.ets
 * 职责: 只读 SQL 投影 review_item / review_log；不写库、不跑 SM-2。
 * 依赖: @kit.ArkData（relationalStore，仅类型）、DatabaseHelper（store 来源）、../ReviewPorts 契约。
 *
 * 数据流:
 *   ReviewReadPortAdapter → listDue / getByUnit / listLogs → SELECT review_item / review_log
 *
 * 查询口径:
 *   - listDue：next_review_at > 0 且 <= now，按到期时间升序；已 graduated 的不再算到期。
 *   - getByUnit：同一 unit 可能有多条历史条目，取最近创建的一条（id 兜底排序）。
 *   - listLogs：按 reviewed_at 倒序。
 */
import type { relationalStore } from '@kit.ArkData';
import { DatabaseHelper } from '../../DatabaseHelper';
import { ReviewStatus } from '../../models/CommonTypes';
import type { ReviewItem, ReviewLogEntry, ReviewReadStore } from '../ReviewPorts';

const ITEM_COLUMNS: string = 'id, unit_id, subject, status, next_review_at, interval_days, ease_factor,'
  + ' repetitions, lapses, last_reviewed_at, created_at, updated_at';
const LOG_COLUMNS: string = 'id, review_item_id, unit_id, reviewed_at, grade, correct, duration_ms,'
  + ' interval_before, interval_after';

export class RdbReviewReadStore implements ReviewReadStore {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /** 组合根便利方法：DatabaseHelper 未初始化时返回 null，由调用方降级。 */
  static fromDatabase(): RdbReviewReadStore | null {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      return null;
    }
    return new RdbReviewReadStore(store);
  }

  async listDue(now: number, limit: number): Promise<ReviewItem[]> {
    const sql: string = 'SELECT ' + ITEM_COLUMNS + ' FROM review_item'
      + ' WHERE next_review_at > 0 AND next_review_at <= ? AND status <> ?'
      + ' ORDER BY next_review_at ASC, id ASC LIMIT ?';
    const args: string[] = [now.toString(), ReviewStatus.GRADUATED, limit.toString()];
    const resultSet: relationalStore.ResultSet = await this.store.querySql(sql, args);
    return RdbReviewReadStore.mapItems(resultSet);
  }

  async getByUnit(unitId: string): Promise<ReviewItem | null> {
    const sql: string = 'SELECT ' + ITEM_COLUMNS + ' FROM review_item WHERE unit_id = ?'
      + ' ORDER BY created_at DESC, id ASC LIMIT 1';
    const resultSet: relationalStore.ResultSet = await this.store.querySql(sql, [unitId]);
    const items: ReviewItem[] = RdbReviewReadStore.mapItems(resultSet);
    if (items.length === 0) {
      return null;
    }
    return items[0];
  }

  async listLogs(unitId: string, limit: number): Promise<ReviewLogEntry[]> {
    const sql: string = 'SELECT ' + LOG_COLUMNS + ' FROM review_log WHERE unit_id = ?'
      + ' ORDER BY reviewed_at DESC, id ASC LIMIT ?';
    const resultSet: relationalStore.ResultSet = await this.store.querySql(sql, [unitId, limit.toString()]);
    return RdbReviewReadStore.mapLogs(resultSet);
  }

  private static mapItems(resultSet: relationalStore.ResultSet): ReviewItem[] {
    const items: ReviewItem[] = [];
    try {
      if (resultSet.goToFirstRow()) {
        do {
          items.push({
            id: RdbReviewReadStore.readString(resultSet, 'id'),
            unitId: RdbReviewReadStore.readString(resultSet, 'unit_id'),
            subject: RdbReviewReadStore.readString(resultSet, 'subject'),
            status: RdbReviewReadStore.readString(resultSet, 'status') as ReviewStatus,
            nextReviewAt: RdbReviewReadStore.readLong(resultSet, 'next_review_at'),
            intervalDays: RdbReviewReadStore.readLong(resultSet, 'interval_days'),
            easeFactor: RdbReviewReadStore.readDouble(resultSet, 'ease_factor'),
            repetitions: RdbReviewReadStore.readLong(resultSet, 'repetitions'),
            lapses: RdbReviewReadStore.readLong(resultSet, 'lapses'),
            lastReviewedAt: RdbReviewReadStore.readLong(resultSet, 'last_reviewed_at'),
            createdAt: RdbReviewReadStore.readLong(resultSet, 'created_at'),
            updatedAt: RdbReviewReadStore.readLong(resultSet, 'updated_at'),
          });
        } while (resultSet.goToNextRow());
      }
    } finally {
      resultSet.close();
    }
    return items;
  }

  private static mapLogs(resultSet: relationalStore.ResultSet): ReviewLogEntry[] {
    const entries: ReviewLogEntry[] = [];
    try {
      if (resultSet.goToFirstRow()) {
        do {
          entries.push({
            id: RdbReviewReadStore.readString(resultSet, 'id'),
            reviewItemId: RdbReviewReadStore.readString(resultSet, 'review_item_id'),
            unitId: RdbReviewReadStore.readString(resultSet, 'unit_id'),
            reviewedAt: RdbReviewReadStore.readLong(resultSet, 'reviewed_at'),
            grade: RdbReviewReadStore.readString(resultSet, 'grade'),
            correct: RdbReviewReadStore.readLong(resultSet, 'correct') === 1,
            durationMs: RdbReviewReadStore.readLong(resultSet, 'duration_ms'),
            intervalBefore: RdbReviewReadStore.readLong(resultSet, 'interval_before'),
            intervalAfter: RdbReviewReadStore.readLong(resultSet, 'interval_after'),
          });
        } while (resultSet.goToNextRow());
      }
    } finally {
      resultSet.close();
    }
    return entries;
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
