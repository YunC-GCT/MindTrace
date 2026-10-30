/**
 * RdbNoteSearchAdapter.ets — NoteSearchPort 的 RDB 实现（common 侧，跨 HAP 共享）
 *
 * 路径: common/src/main/ets/ports/impl/RdbNoteSearchAdapter.ets
 * 职责: 只读 SQL 召回候选（标题/标签/摘要/正文 instr 命中 + 可选过滤），
 *       复用 NoteSearchRanking 打分排序，输出 NoteSearchHit；不写库。
 * 依赖: @kit.ArkData（relationalStore，仅类型）、DatabaseHelper（store 来源）、
 *       ./NoteSearchRanking（纯打分）、../NoteSearchPort（契约）。
 *
 * 行为等价：与既有 `note_query_rag` 工具同 SQL/同权重/同排序，切换实现不得改变输出。
 */
import type { relationalStore } from '@kit.ArkData';
import { DatabaseHelper } from '../../DatabaseHelper';
import { NOTE_SEARCH_MAX_TOP_K } from '../NoteSearchPort';
import type { NoteSearchHit, NoteSearchPort, NoteSearchQuery } from '../NoteSearchPort';
import { rankNoteHits } from './NoteSearchRanking';
import type { ScoredCandidate } from './NoteSearchRanking';

const TABLE: string = 'knowledge_unit';
const SEARCH_COLUMNS: string = 'id, title, tags, summary, content, subject, chapter, updated_at, version';

export class RdbNoteSearchAdapter implements NoteSearchPort {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  /** 组合根便利方法：DatabaseHelper 未初始化时返回 null，由调用方降级。 */
  static fromDatabase(): RdbNoteSearchAdapter | null {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      return null;
    }
    return new RdbNoteSearchAdapter(store);
  }

  async search(query: NoteSearchQuery): Promise<NoteSearchHit[]> {
    const needle: string = query.query.trim().toLowerCase();
    if (needle.length === 0) {
      return [];
    }
    let topK: number = query.topK;
    if (topK < 1) {
      topK = 1;
    }
    if (topK > NOTE_SEARCH_MAX_TOP_K) {
      topK = NOTE_SEARCH_MAX_TOP_K;
    }
    const where: string[] = [];
    const bindArgs: string[] = [];
    where.push('(instr(lower(title), ?) > 0 OR instr(lower(tags), ?) > 0'
      + ' OR instr(lower(summary), ?) > 0 OR instr(lower(content), ?) > 0)');
    bindArgs.push(needle, needle, needle, needle);
    const subject: string = query.subject === undefined ? '' : query.subject.trim();
    if (subject.length > 0) {
      where.push('subject = ?');
      bindArgs.push(subject);
    }
    const chapter: string = query.chapter === undefined ? '' : query.chapter.trim();
    if (chapter.length > 0) {
      where.push('chapter = ?');
      bindArgs.push(chapter);
    }
    const tag: string = query.tag === undefined ? '' : query.tag.trim();
    if (tag.length > 0) {
      where.push('instr(lower(tags), ?) > 0');
      bindArgs.push(tag.toLowerCase());
    }
    if (query.updatedAfter !== undefined) {
      where.push('updated_at >= ?');
      bindArgs.push(query.updatedAfter.toString());
    }
    if (query.updatedBefore !== undefined) {
      where.push('updated_at <= ?');
      bindArgs.push(query.updatedBefore.toString());
    }
    const sql: string = 'SELECT ' + SEARCH_COLUMNS + ' FROM ' + TABLE + ' WHERE ' + where.join(' AND ')
      + ' ORDER BY updated_at DESC, id ASC';
    const rows: ScoredCandidate[] = await this.queryCandidates(sql, bindArgs);
    const ranked: ScoredCandidate[] = rankNoteHits(rows, needle, topK);
    return ranked.map((row: ScoredCandidate): NoteSearchHit => RdbNoteSearchAdapter.toHit(row));
  }

  private queryCandidates(sql: string, bindArgs: string[]): Promise<ScoredCandidate[]> {
    return new Promise<ScoredCandidate[]>((resolve, reject) => {
      this.store.querySql(sql, bindArgs, (err, resultSet) => {
        if (err) {
          reject(new Error('RdbNoteSearchAdapter.search failed: ' + err.message));
          return;
        }
        const rows: ScoredCandidate[] = [];
        if (resultSet.goToFirstRow()) {
          do {
            const row: ScoredCandidate = {
              noteId: RdbNoteSearchAdapter.readString(resultSet, 'id'),
              title: RdbNoteSearchAdapter.readString(resultSet, 'title'),
              version: RdbNoteSearchAdapter.readLong(resultSet, 'version'),
              subject: RdbNoteSearchAdapter.readString(resultSet, 'subject'),
              chapter: RdbNoteSearchAdapter.readString(resultSet, 'chapter'),
              tags: RdbNoteSearchAdapter.readString(resultSet, 'tags'),
              summary: RdbNoteSearchAdapter.readString(resultSet, 'summary'),
              content: RdbNoteSearchAdapter.readString(resultSet, 'content'),
              updatedAt: RdbNoteSearchAdapter.readLong(resultSet, 'updated_at'),
              score: 0,
              matchedFields: [],
              excerpt: '',
            };
            rows.push(row);
          } while (resultSet.goToNextRow());
        }
        resultSet.close();
        resolve(rows);
      });
    });
  }

  private static toHit(row: ScoredCandidate): NoteSearchHit {
    const hit: NoteSearchHit = {
      noteId: row.noteId,
      title: row.title,
      version: row.version,
      subject: row.subject,
      chapter: row.chapter,
      tags: RdbNoteSearchAdapter.parseTags(row.tags),
      summary: row.summary,
      score: row.score,
      matchedFields: row.matchedFields,
      excerpt: row.excerpt,
      updatedAt: row.updatedAt,
    };
    return hit;
  }

  private static parseTags(value: string): string[] {
    if (value.length === 0) {
      return [];
    }
    try {
      return JSON.parse(value) as string[];
    } catch (e) {
      return [];
    }
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
}
