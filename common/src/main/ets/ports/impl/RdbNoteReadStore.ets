/**
 * RdbNoteReadStore.ets — NoteReadStore 的只读 RDB 实现（common 侧，跨 HAP 共享）
 *
 * 路径: common/src/main/ets/ports/impl/RdbNoteReadStore.ets
 * 职责: 用只读 SQL 把 knowledge_unit 投影成 NoteDetail，供 skill / entry 共用；
 *       只 SELECT，不 INSERT/UPDATE/DELETE，也不持有写事务（见 ADR-0021）。
 * 依赖: @kit.ArkData（relationalStore，common 已依赖）、DatabaseHelper（store 来源）、
 *       ../NoteReadPort（NoteDetail / NoteReadStore 契约）。
 *
 * 数据流:
 *   NoteReadPortAdapter → queryById / queryAllMetadata → SELECT knowledge_unit → NoteDetail
 *
 * 口径:
 *   - 列名以 entry 的 NoteDao 为准（schema source of truth 仍是 NoteDao / DatabaseHelper）。
 *   - tags 按 JSON 数组字符串存取（与 NoteDao 一致）；解析失败的 tags 降级为空数组。
 *   - difficulty 落库为数字枚举，读回后按 DifficultyLevel 解释。
 */
import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper } from '../../DatabaseHelper';
import { DifficultyLevel, ReviewStatus } from '../../models/CommonTypes';
import type { NoteDetail, NoteReadStore } from '../NoteReadPort';

const DETAIL_COLUMNS: string = 'id, title, content, summary, tags, subject, category, chapter, difficulty,'
  + ' source, source_image_id, source_region, ocr_confidence, created_at, updated_at, review_status,'
  + ' next_review_at, interval_days, ease_factor, repetitions, user_id, version';
const META_COLUMNS: string = 'id, title, summary, tags, subject, category, chapter, difficulty,'
  + ' source, source_image_id, source_region, ocr_confidence, created_at, updated_at, review_status,'
  + ' next_review_at, interval_days, ease_factor, repetitions, user_id, version';

export class RdbNoteReadStore implements NoteReadStore {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /** 组合根便利方法：DatabaseHelper 未初始化时返回 null，由调用方降级。 */
  static fromDatabase(): RdbNoteReadStore | null {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      return null;
    }
    return new RdbNoteReadStore(store);
  }

  async queryById(id: string): Promise<NoteDetail | null> {
    const sql: string = 'SELECT ' + DETAIL_COLUMNS + ' FROM knowledge_unit WHERE id = ? LIMIT 1';
    const rows: NoteDetail[] = await this.queryRows(sql, [id], true);
    if (rows.length === 0) {
      return null;
    }
    return rows[0];
  }

  async queryAllMetadata(): Promise<NoteDetail[]> {
    const sql: string = 'SELECT ' + META_COLUMNS + ' FROM knowledge_unit ORDER BY updated_at DESC';
    return await this.queryRows(sql, [], false);
  }

  private queryRows(sql: string, args: string[], withContent: boolean): Promise<NoteDetail[]> {
    return new Promise<NoteDetail[]>((resolve, reject) => {
      this.store.querySql(sql, args, (err, resultSet) => {
        if (err) {
          reject(new Error('RdbNoteReadStore.query failed: ' + err.message));
          return;
        }
        const rows: NoteDetail[] = [];
        if (resultSet.goToFirstRow()) {
          do {
            rows.push(RdbNoteReadStore.toDetail(resultSet, withContent));
          } while (resultSet.goToNextRow());
        }
        resultSet.close();
        resolve(rows);
      });
    });
  }

  private static toDetail(rs: relationalStore.ResultSet, withContent: boolean): NoteDetail {
    const detail: NoteDetail = {
      id: RdbNoteReadStore.readString(rs, 'id'),
      title: RdbNoteReadStore.readString(rs, 'title'),
      content: withContent ? RdbNoteReadStore.readString(rs, 'content') : '',
      summary: RdbNoteReadStore.readString(rs, 'summary'),
      tags: RdbNoteReadStore.parseStringArray(RdbNoteReadStore.readString(rs, 'tags')),
      subject: RdbNoteReadStore.readString(rs, 'subject'),
      category: RdbNoteReadStore.readString(rs, 'category'),
      chapter: RdbNoteReadStore.readString(rs, 'chapter'),
      difficulty: RdbNoteReadStore.readLong(rs, 'difficulty') as DifficultyLevel,
      reviewStatus: RdbNoteReadStore.readString(rs, 'review_status') as ReviewStatus,
      nextReviewAt: RdbNoteReadStore.readLong(rs, 'next_review_at'),
      intervalDays: RdbNoteReadStore.readLong(rs, 'interval_days'),
      easeFactor: RdbNoteReadStore.readDouble(rs, 'ease_factor'),
      repetitions: RdbNoteReadStore.readLong(rs, 'repetitions'),
      userId: RdbNoteReadStore.readString(rs, 'user_id'),
      createdAt: RdbNoteReadStore.readLong(rs, 'created_at'),
      updatedAt: RdbNoteReadStore.readLong(rs, 'updated_at'),
      version: RdbNoteReadStore.readLong(rs, 'version'),
      source: RdbNoteReadStore.readString(rs, 'source'),
    };
    const imageId: string = RdbNoteReadStore.readString(rs, 'source_image_id');
    if (imageId.length > 0) {
      detail.sourceImageId = imageId;
    }
    const region: string = RdbNoteReadStore.readString(rs, 'source_region');
    if (region.length > 0) {
      detail.sourceRegion = region;
    }
    const confidence: number = RdbNoteReadStore.readLong(rs, 'ocr_confidence');
    if (confidence > 0) {
      detail.ocrConfidence = confidence;
    }
    return detail;
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

  private static parseStringArray(value: string): string[] {
    if (value.length === 0) {
      return [];
    }
    try {
      return JSON.parse(value) as string[];
    } catch (e) {
      return [];
    }
  }
}
