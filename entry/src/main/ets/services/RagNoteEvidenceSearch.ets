/**
 * RagNoteEvidenceSearch.ets — 证据检索的 entry 实现
 *
 * 路径: entry/src/main/ets/services/RagNoteEvidenceSearch.ets
 * 职责: 实现 NoteEvidenceSearchPort：本地 FTS（note_fts trigram/LIKE）优先，
 *       无命中回退 note_query_rag 工具；再把命中 join 成可直接引用的 citations
 * 依赖: @kit.ArkData、common（ToolCatalog / NoteReadPort）、./RagRetrievalService
 *
 * 数据流:
 *   NoteEvidenceService（agents） → 本适配器 → FTS / 工具 → NoteEvidenceCitation
 */
import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper, ToolCatalog, ToolRegistry, ToolResult } from 'common';
import type {
  NoteDetail,
  NoteEvidenceCitation,
  NoteEvidenceOptions,
  NoteEvidenceSearchPort,
  NoteReadPort,
} from 'common';
import { RagHit, RagRetrievalService } from './RagRetrievalService';
import { LlmEvidenceJudge } from './LlmEvidenceJudge';

const EVIDENCE_TOOL_NAME: string = 'note_query_rag';
const EVIDENCE_EXCERPT_LIMIT: number = 160;

interface NoteEvidenceRow {
  noteId: string;
  title: string;
  version: number;
  subject: string;
  chapter: string;
  summary: string;
  content: string;
}

export class RagNoteEvidenceSearch implements NoteEvidenceSearchPort {
  private readonly readPort: NoteReadPort | undefined;

  constructor(readPort?: NoteReadPort) {
    this.readPort = readPort;
  }

  async search(query: string, topK: number, options?: NoteEvidenceOptions): Promise<NoteEvidenceCitation[]> {
    // R3：优先用本地 FTS 检索（自管 note_fts，trigram/LIKE），失败或无命中回退既有 note.search。
    const ragCitations: NoteEvidenceCitation[] | undefined = await this.queryHitsByFts(query, topK, options);
    if (ragCitations !== undefined && ragCitations.length > 0) {
      return ragCitations;
    }
    const registry: ToolRegistry = ToolCatalog.createReadOnlyRegistry();
    const args: Record<string, Object> = {};
    args['query'] = query;
    args['topK'] = topK;
    if (options !== undefined) {
      const subject: string = options.subject === undefined ? '' : options.subject.trim();
      const chapter: string = options.chapter === undefined ? '' : options.chapter.trim();
      const tag: string = options.tag === undefined ? '' : options.tag.trim();
      if (subject.length > 0) {
        args['subject'] = subject;
      }
      if (chapter.length > 0) {
        args['chapter'] = chapter;
      }
      if (tag.length > 0) {
        args['tag'] = tag;
      }
    }
    const result: ToolResult = await registry.execute(EVIDENCE_TOOL_NAME, JSON.stringify(args));
    if (!result.ok) {
      throw new Error('note_query_rag failed: ' + result.content);
    }
    return RagNoteEvidenceSearch.parseHits(result.content);
  }

  /**
   * R3：本地 FTS 召回 → join knowledge_unit（取 version）→ NoteEvidenceCitation。
   * 返回 undefined 表示「无法使用 FTS」（表未就绪/查询异常），调用方回退 note.search；
   * 返回空数组表示 FTS 可用但无命中。
   */
  private async queryHitsByFts(
    query: string,
    topK: number,
    options?: NoteEvidenceOptions,
  ): Promise<NoteEvidenceCitation[] | undefined> {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      return undefined;
    }
    let hits: RagHit[] = [];
    try {
      hits = await RagRetrievalService.search(store, query, topK);
    } catch (e) {
      return undefined;
    }
    if (hits.length === 0) {
      return [];
    }
    const ids: string[] = [];
    for (const hit of hits) {
      this.addUnique(ids, hit.unitId);
    }
    let rows: NoteEvidenceRow[] = [];
    try {
      rows = await this.queryLiveRows(store, ids);
    } catch (e) {
      return undefined;
    }
    const subjectFilter: string = options !== undefined && options.subject !== undefined ? options.subject.trim() : '';
    const chapterFilter: string = options !== undefined && options.chapter !== undefined ? options.chapter.trim() : '';
    const citations: NoteEvidenceCitation[] = [];
    const judgeDocs: string[] = [];
    for (const hit of hits) {
      let row: NoteEvidenceRow | undefined = undefined;
      for (const candidate of rows) {
        if (candidate.noteId === hit.unitId) {
          row = candidate;
          break;
        }
      }
      if (row === undefined) {
        continue;
      }
      if (subjectFilter.length > 0 && row.subject !== subjectFilter) {
        continue;
      }
      if (chapterFilter.length > 0 && row.chapter !== chapterFilter) {
        continue;
      }
      citations.push({
        noteId: row.noteId,
        version: row.version,
        title: row.title,
        excerpt: RagNoteEvidenceSearch.buildExcerpt(row.content, row.summary),
        role: 'hit',
        score: 0,
        matchedFields: ['content'],
        subject: row.subject,
        chapter: row.chapter,
      });
      judgeDocs.push(row.title + '：' + (row.summary.trim().length > 0 ? row.summary : row.content));
    }
    // 语料里没有对应主题时不要让模型拿无关片段硬答；判定失败按「能回答」处理。
    if (citations.length > 0) {
      const answerable: boolean = await LlmEvidenceJudge.isAnswerable(query, judgeDocs);
      if (!answerable) {
        console.info('[EvidenceJudge] drop n=' + citations.length.toString() + ' q=' + query);
        const empty: NoteEvidenceCitation[] = [];
        return empty;
      }
    }
    return citations;
  }

  private async queryLiveRows(store: relationalStore.RdbStore, unitIds: string[]): Promise<NoteEvidenceRow[]> {
    if (unitIds.length === 0) {
      const empty: NoteEvidenceRow[] = [];
      return empty;
    }
    const port: NoteReadPort | undefined = this.readPort;
    if (port !== undefined) {
      try {
        const details: NoteDetail[] = await port.listByIds(unitIds);
        const rows: NoteEvidenceRow[] = [];
        for (const detail of details) {
          rows.push({
            noteId: detail.id,
            title: detail.title,
            version: detail.version,
            subject: detail.subject,
            chapter: detail.chapter,
            summary: detail.summary,
            content: detail.content,
          });
        }
        return rows;
      } catch (e) {
        const message: string = e instanceof Error ? e.message : String(e);
        throw new Error('RagNoteEvidenceSearch.queryLiveRows failed: ' + message);
      }
    }
    const placeholders: string = RagNoteEvidenceSearch.placeholders(unitIds.length);
    const sql: string = 'SELECT id, title, version, subject, chapter, summary, content FROM knowledge_unit'
      + ' WHERE id IN (' + placeholders + ') ORDER BY id ASC';
    return new Promise<NoteEvidenceRow[]>((resolve, reject) => {
      store.querySql(sql, unitIds, (err, resultSet) => {
        if (err) {
          reject(new Error('RagNoteEvidenceSearch.queryLiveRows failed: ' + err.message));
          return;
        }
        const rows: NoteEvidenceRow[] = [];
        if (resultSet.goToFirstRow()) {
          do {
            rows.push({
              noteId: RagNoteEvidenceSearch.readString(resultSet, 'id'),
              title: RagNoteEvidenceSearch.readString(resultSet, 'title'),
              version: RagNoteEvidenceSearch.readLong(resultSet, 'version'),
              subject: RagNoteEvidenceSearch.readString(resultSet, 'subject'),
              chapter: RagNoteEvidenceSearch.readString(resultSet, 'chapter'),
              summary: RagNoteEvidenceSearch.readString(resultSet, 'summary'),
              content: RagNoteEvidenceSearch.readString(resultSet, 'content'),
            });
          } while (resultSet.goToNextRow());
        }
        resultSet.close();
        resolve(rows);
      });
    });
  }

  private static parseHits(content: string): NoteEvidenceCitation[] {
    const citations: NoteEvidenceCitation[] = [];
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(content) as Record<string, Object>;
    } catch (e) {
      return citations;
    }
    const hitsValue: Object | undefined = parsed['hits'];
    if (hitsValue === undefined || hitsValue === null || !Array.isArray(hitsValue)) {
      return citations;
    }
    const hits: Object[] = hitsValue as Object[];
    for (const item of hits) {
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        continue;
      }
      const record: Record<string, Object> = item as Record<string, Object>;
      const noteId: string = String(record['noteId'] ?? '');
      if (noteId.length === 0) {
        continue;
      }
      citations.push({
        noteId: noteId,
        version: Number(record['version'] ?? 0),
        title: String(record['title'] ?? ''),
        excerpt: String(record['excerpt'] ?? ''),
        role: 'hit',
        score: Number(record['score'] ?? 0),
        matchedFields: RagNoteEvidenceSearch.readStringArray(record['matchedFields']),
        subject: String(record['subject'] ?? ''),
        chapter: String(record['chapter'] ?? ''),
      });
    }
    return citations;
  }

  private static buildExcerpt(content: string, summary: string): string {
    const text: string = content.trim();
    const source: string = text.length > 0 ? text : summary.trim();
    if (source.length <= EVIDENCE_EXCERPT_LIMIT) {
      return source;
    }
    return source.substring(0, EVIDENCE_EXCERPT_LIMIT) + '…';
  }

  private static readStringArray(value: Object | undefined): string[] {
    const out: string[] = [];
    if (value === undefined || value === null || !Array.isArray(value)) {
      return out;
    }
    const items: Object[] = value as Object[];
    for (const item of items) {
      const text: string = String(item ?? '');
      if (text.length > 0) {
        out.push(text);
      }
    }
    return out;
  }

  private static placeholders(count: number): string {
    const parts: string[] = [];
    for (let index: number = 0; index < count; index += 1) {
      parts.push('?');
    }
    return parts.join(',');
  }

  private addUnique(target: string[], value: string): void {
    if (value.length > 0 && target.indexOf(value) < 0) {
      target.push(value);
    }
  }

  private static readString(resultSet: relationalStore.ResultSet, column: string): string {
    const index: number = resultSet.getColumnIndex(column);
    if (index < 0) {
      return '';
    }
    return resultSet.getString(index);
  }

  private static readLong(resultSet: relationalStore.ResultSet, column: string): number {
    const index: number = resultSet.getColumnIndex(column);
    if (index < 0) {
      return 0;
    }
    return resultSet.getLong(index);
  }
}
