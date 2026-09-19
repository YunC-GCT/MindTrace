// ============================================================================
//  services/NoteEvidenceService.ets — 可追溯回答证据上下文 (DEV-004/005/006)
// ============================================================================
// 路径: entry/src/main/ets/services/NoteEvidenceService.ets
// 职责: 组合 note_query_rag (关键词检索) 与 accepted kg_edge 有限深度扩展,
//       产出可追溯证据上下文: prompt 注入文本 + noteId/version/excerpt 引用 +
//       已确认关系快照; 并对模型输出做虚构引用清洗
// 依赖: common DatabaseHelper/ToolCatalog/ToolRegistry/ToolResult;
//       ../database/KnowledgeRelationDao; ../models/NoteEvidenceModels
// 约束: 引用只来自真实 knowledge_unit 行; 不写库; 不引入向量检索
// ============================================================================

import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper, ToolCatalog, ToolRegistry, ToolResult } from 'common';
import { KnowledgeRelationDao, GraphExpansion, GraphExpansionLimits } from '../database/KnowledgeRelationDao';
import {
  NoteEvidenceCitation,
  NoteEvidenceContext,
  NoteEvidenceRelation,
  NoteEvidenceRole,
} from '../models/NoteEvidenceModels';

const EVIDENCE_TOOL_NAME: string = 'note_query_rag';
const EVIDENCE_DEFAULT_TOP_K: number = 5;
const EVIDENCE_MAX_TOP_K: number = 10;
const EVIDENCE_DEFAULT_DEPTH: number = 1;
const EVIDENCE_MAX_DEPTH: number = 2;
const EVIDENCE_MAX_CITATIONS: number = 10;
const EVIDENCE_EXCERPT_LIMIT: number = 160;
const CITATION_MARKER: string = '[noteId=';
const CITATION_UNVERIFIED: string = '[未验证引用]';

export interface NoteEvidenceOptions {
  topK?: number;
  maxDepth?: number;
  subject?: string;
  chapter?: string;
  tag?: string;
}

// 内部行: 图谱邻居的存活笔记元数据
interface NoteEvidenceRow {
  noteId: string;
  title: string;
  version: number;
  subject: string;
  chapter: string;
  summary: string;
  content: string;
}

interface TextSplit {
  text: string;
  carry: string;
}

export class NoteEvidenceService {
  // 构建证据上下文; 任何失败都降级为 degraded 上下文, 不阻断回答
  async build(query: string, options?: NoteEvidenceOptions): Promise<NoteEvidenceContext> {
    const normalizedQuery: string = query.trim();
    const topK: number = NoteEvidenceService.clampTopK(options?.topK);
    const maxDepth: number = NoteEvidenceService.clampDepth(options?.maxDepth);
    if (normalizedQuery.length === 0) {
      return NoteEvidenceService.emptyContext(normalizedQuery, topK, 'empty-query');
    }
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      return NoteEvidenceService.degradedContext(normalizedQuery, topK, 'store-not-ready');
    }
    let citations: NoteEvidenceCitation[] = [];
    try {
      citations = await this.queryHits(normalizedQuery, topK, options);
    } catch (e) {
      return NoteEvidenceService.degradedContext(normalizedQuery, topK, 'search-failed');
    }
    if (citations.length === 0) {
      return NoteEvidenceService.emptyContext(normalizedQuery, topK, 'no-match');
    }
    const relations: NoteEvidenceRelation[] = [];
    let degraded: boolean = false;
    let reason: string = '';
    try {
      await this.expandGraph(store, citations, relations, maxDepth);
    } catch (e) {
      degraded = true;
      reason = 'graph-failed';
    }
    const context: NoteEvidenceContext = {
      query: normalizedQuery,
      topK: topK,
      citations: citations,
      relations: relations,
      contextText: NoteEvidenceService.formatContext(citations, relations),
      degraded: degraded,
      reason: reason,
    };
    return context;
  }

  // 回答末尾的确定性来源块: 只列真实 noteId/version/excerpt
  formatSources(context: NoteEvidenceContext): string {
    if (context.citations.length === 0) {
      return '';
    }
    const limited: NoteEvidenceCitation[] = NoteEvidenceService.capCitations(context.citations);
    const lines: string[] = [];
    lines.push('参考来源：');
    for (const citation of limited) {
      lines.push('- ' + NoteEvidenceService.roleLabel(citation.role)
        + ' [noteId=' + citation.noteId + ' version=' + citation.version.toString() + '] '
        + '《' + citation.title + '》：' + citation.excerpt);
    }
    if (context.citations.length > limited.length) {
      lines.push('- 其余 ' + (context.citations.length - limited.length).toString() + ' 条证据已省略。');
    }
    return lines.join('\n');
  }

  // 清洗模型正文里的虚构引用: 允许集外的 [noteId=...] 替换为未验证标记
  sanitizeAnswer(context: NoteEvidenceContext, answer: string): string {
    if (context.citations.length === 0) {
      return answer;
    }
    const filter: NoteEvidenceStreamFilter = this.createStreamFilter(context);
    return filter.push(answer) + filter.flush();
  }

  // 流式增量清洗器: 未启用时原样透传
  createStreamFilter(context: NoteEvidenceContext | undefined): NoteEvidenceStreamFilter {
    const allowed: string[] = [];
    if (context !== undefined) {
      for (const citation of context.citations) {
        NoteEvidenceService.addUnique(allowed, citation.noteId);
      }
    }
    return new NoteEvidenceStreamFilter(allowed);
  }

  private async queryHits(
    query: string,
    topK: number,
    options?: NoteEvidenceOptions,
  ): Promise<NoteEvidenceCitation[]> {
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
    return NoteEvidenceService.parseHits(result.content);
  }

  private async expandGraph(
    store: relationalStore.RdbStore,
    citations: NoteEvidenceCitation[],
    relations: NoteEvidenceRelation[],
    maxDepth: number,
  ): Promise<void> {
    const seeds: string[] = [];
    for (const citation of citations) {
      NoteEvidenceService.addUnique(seeds, citation.noteId);
    }
    const dao: KnowledgeRelationDao = new KnowledgeRelationDao(store);
    const limits: GraphExpansionLimits = { maxDepth: maxDepth };
    const expansion: GraphExpansion = await dao.expandAcceptedNeighborhood(seeds, limits);
    const relationSeen: string[] = [];
    for (const edge of expansion.edges) {
      if (relationSeen.indexOf(edge.id) >= 0) {
        continue;
      }
      relationSeen.push(edge.id);
      relations.push({
        edgeId: edge.id,
        fromNoteId: edge.fromUnitId,
        toNoteId: edge.toUnitId,
        relationType: edge.relationType === 'prerequisite' ? 'prerequisite' : 'related',
        reason: edge.reason,
      });
    }
    const known: string[] = [];
    for (const citation of citations) {
      NoteEvidenceService.addUnique(known, citation.noteId);
    }
    const missing: string[] = [];
    for (const node of expansion.nodes) {
      if (known.indexOf(node.unitId) < 0) {
        NoteEvidenceService.addUnique(missing, node.unitId);
      }
    }
    if (missing.length === 0) {
      return;
    }
    const rows: NoteEvidenceRow[] = await this.queryLiveRows(store, missing);
    for (const row of rows) {
      citations.push({
        noteId: row.noteId,
        version: row.version,
        title: row.title,
        excerpt: NoteEvidenceService.buildExcerpt(row.content, row.summary),
        role: NoteEvidenceService.roleFor(row.noteId, relations),
        score: 0,
        matchedFields: [],
        subject: row.subject,
        chapter: row.chapter,
      });
    }
  }

  private queryLiveRows(store: relationalStore.RdbStore, unitIds: string[]): Promise<NoteEvidenceRow[]> {
    if (unitIds.length === 0) {
      const empty: NoteEvidenceRow[] = [];
      return Promise.resolve(empty);
    }
    const placeholders: string = NoteEvidenceService.placeholders(unitIds.length);
    const sql: string = 'SELECT id, title, version, subject, chapter, summary, content FROM knowledge_unit'
      + ' WHERE id IN (' + placeholders + ') ORDER BY id ASC';
    return new Promise<NoteEvidenceRow[]>((resolve, reject) => {
      store.querySql(sql, unitIds, (err, resultSet) => {
        if (err) {
          reject(new Error('NoteEvidenceService.queryLiveRows failed: ' + err.message));
          return;
        }
        const rows: NoteEvidenceRow[] = [];
        if (resultSet.goToFirstRow()) {
          do {
            rows.push({
              noteId: NoteEvidenceService.readString(resultSet, 'id'),
              title: NoteEvidenceService.readString(resultSet, 'title'),
              version: NoteEvidenceService.readLong(resultSet, 'version'),
              subject: NoteEvidenceService.readString(resultSet, 'subject'),
              chapter: NoteEvidenceService.readString(resultSet, 'chapter'),
              summary: NoteEvidenceService.readString(resultSet, 'summary'),
              content: NoteEvidenceService.readString(resultSet, 'content'),
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
        matchedFields: NoteEvidenceService.readStringArray(record['matchedFields']),
        subject: String(record['subject'] ?? ''),
        chapter: String(record['chapter'] ?? ''),
      });
    }
    return citations;
  }

  private static formatContext(citations: NoteEvidenceCitation[], relations: NoteEvidenceRelation[]): string {
    if (citations.length === 0 && relations.length === 0) {
      return '';
    }
    const lines: string[] = [];
    lines.push('以下是从用户已保存笔记中检索到的证据，只可引用其中出现的 noteId 与 version：');
    const limited: NoteEvidenceCitation[] = NoteEvidenceService.capCitations(citations);
    for (const citation of limited) {
      const matched: string = citation.matchedFields.length > 0
        ? '命中字段: ' + citation.matchedFields.join(',')
        : '图谱关联';
      lines.push('- [noteId=' + citation.noteId + ' version=' + citation.version.toString() + '] '
        + '《' + citation.title + '》（' + matched + '）摘录：' + citation.excerpt);
    }
    if (relations.length > 0) {
      lines.push('已确认的知识关系（方向: 前置 -> 后续）：');
      for (const relation of relations) {
        lines.push('- ' + relation.fromNoteId + ' -' + relation.relationType + '-> ' + relation.toNoteId);
      }
    }
    lines.push('引用规范：正文引用证据时写成 [noteId=... version=...]；上面没有出现的 noteId 一律不得引用，也不得编造来源。');
    return lines.join('\n');
  }

  private static capCitations(citations: NoteEvidenceCitation[]): NoteEvidenceCitation[] {
    const limited: NoteEvidenceCitation[] = [];
    for (let index = 0; index < citations.length && index < EVIDENCE_MAX_CITATIONS; index += 1) {
      limited.push(citations[index]);
    }
    return limited;
  }

  private static roleFor(noteId: string, relations: NoteEvidenceRelation[]): NoteEvidenceRole {
    for (const relation of relations) {
      if (relation.relationType !== 'prerequisite') {
        continue;
      }
      if (relation.fromNoteId === noteId || relation.toNoteId === noteId) {
        return 'prerequisite';
      }
    }
    return 'related';
  }

  private static roleLabel(role: NoteEvidenceRole): string {
    if (role === 'hit') {
      return '[关键词命中]';
    }
    if (role === 'prerequisite') {
      return '[前置知识]';
    }
    return '[关联知识]';
  }

  private static buildExcerpt(content: string, summary: string): string {
    const source: string = content.trim().length > 0 ? content.trim() : summary.trim();
    if (source.length === 0) {
      return '';
    }
    const normalized: string = source.replace(/\s+/g, ' ').trim();
    if (normalized.length <= EVIDENCE_EXCERPT_LIMIT) {
      return normalized;
    }
    return normalized.substring(0, EVIDENCE_EXCERPT_LIMIT) + '…';
  }

  private static emptyContext(query: string, topK: number, reason: string): NoteEvidenceContext {
    const context: NoteEvidenceContext = {
      query: query,
      topK: topK,
      citations: [],
      relations: [],
      contextText: '',
      degraded: false,
      reason: reason,
    };
    return context;
  }

  private static degradedContext(query: string, topK: number, reason: string): NoteEvidenceContext {
    const context: NoteEvidenceContext = {
      query: query,
      topK: topK,
      citations: [],
      relations: [],
      contextText: '',
      degraded: true,
      reason: reason,
    };
    return context;
  }

  private static clampTopK(value: number | undefined): number {
    if (value === undefined || Number.isNaN(value)) {
      return EVIDENCE_DEFAULT_TOP_K;
    }
    let clamped: number = Math.floor(value);
    if (clamped < 1) {
      clamped = 1;
    }
    if (clamped > EVIDENCE_MAX_TOP_K) {
      clamped = EVIDENCE_MAX_TOP_K;
    }
    return clamped;
  }

  private static clampDepth(value: number | undefined): number {
    if (value === undefined || Number.isNaN(value)) {
      return EVIDENCE_DEFAULT_DEPTH;
    }
    let clamped: number = Math.floor(value);
    if (clamped < 1) {
      clamped = 1;
    }
    if (clamped > EVIDENCE_MAX_DEPTH) {
      clamped = EVIDENCE_MAX_DEPTH;
    }
    return clamped;
  }

  private static placeholders(count: number): string {
    const parts: string[] = [];
    for (let index = 0; index < count; index += 1) {
      parts.push('?');
    }
    return parts.join(',');
  }

  private static addUnique(target: string[], value: string): void {
    if (value.length > 0 && target.indexOf(value) < 0) {
      target.push(value);
    }
  }

  private static readStringArray(value: Object | undefined): string[] {
    const values: string[] = [];
    if (value === undefined || value === null || !Array.isArray(value)) {
      return values;
    }
    const items: Object[] = value as Object[];
    for (const item of items) {
      values.push(String(item));
    }
    return values;
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

// 流式引用清洗: 缓冲可能被拆分的 [noteId=...] 片段, 允许集外替换为未验证标记
export class NoteEvidenceStreamFilter {
  private readonly allowed: string[];
  private readonly enabled: boolean;
  private carry: string = '';

  constructor(allowedNoteIds: string[]) {
    this.allowed = allowedNoteIds;
    this.enabled = allowedNoteIds.length > 0;
  }

  push(delta: string): string {
    if (!this.enabled) {
      return delta;
    }
    const split: TextSplit = this.split(this.carry + delta, false);
    this.carry = split.carry;
    return split.text;
  }

  flush(): string {
    if (!this.enabled || this.carry.length === 0) {
      return '';
    }
    const split: TextSplit = this.split(this.carry, true);
    this.carry = '';
    return split.text;
  }

  private split(buffer: string, final: boolean): TextSplit {
    let output: string = '';
    let cursor: number = 0;
    while (cursor < buffer.length) {
      const start: number = buffer.indexOf(CITATION_MARKER, cursor);
      if (start < 0) {
        const holdFrom: number = final ? buffer.length : NoteEvidenceStreamFilter.tailHoldStart(buffer);
        output += buffer.substring(cursor, holdFrom);
        const carry: string = final ? '' : buffer.substring(holdFrom);
        const split: TextSplit = { text: output, carry: carry };
        return split;
      }
      output += buffer.substring(cursor, start);
      const end: number = buffer.indexOf(']', start + CITATION_MARKER.length);
      if (end < 0) {
        if (final) {
          output += CITATION_UNVERIFIED;
          const closed: TextSplit = { text: output, carry: '' };
          return closed;
        }
        const open: TextSplit = { text: output, carry: buffer.substring(start) };
        return open;
      }
      const rawId: string = buffer.substring(start + CITATION_MARKER.length, end);
      const noteId: string = NoteEvidenceStreamFilter.readNoteId(rawId);
      output += this.allowed.indexOf(noteId) >= 0 ? buffer.substring(start, end + 1) : CITATION_UNVERIFIED;
      cursor = end + 1;
    }
    const done: TextSplit = { text: output, carry: '' };
    return done;
  }

  private static readNoteId(raw: string): string {
    let end: number = raw.length;
    for (let index = 0; index < raw.length; index += 1) {
      const ch: string = raw.charAt(index);
      if (ch === ' ' || ch === ',' || ch === '|' || ch === '"' || ch === '\'') {
        end = index;
        break;
      }
    }
    return raw.substring(0, end).trim();
  }

  private static tailHoldStart(buffer: string): number {
    const max: number = Math.min(CITATION_MARKER.length - 1, buffer.length);
    for (let length = max; length > 0; length -= 1) {
      if (buffer.substring(buffer.length - length) === CITATION_MARKER.substring(0, length)) {
        return buffer.length - length;
      }
    }
    return buffer.length;
  }
}
