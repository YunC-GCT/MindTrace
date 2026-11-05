/**
 * NoteEvidenceService.ets — 可追溯回答的证据上下文
 *
 * 路径: agents/src/main/ets/evidence/NoteEvidenceService.ets
 * 职责: 组合检索命中与 accepted kg_edge 有限深度扩展，产出可追溯证据上下文
 *       （prompt 注入文本 + noteId/version/excerpt 引用 + 已确认关系快照），
 *       并对模型输出做虚构引用清洗
 * 依赖: common（NoteEvidenceModels / NoteEvidenceSearchPort / NoteGraphPort / NoteReadPort）；
 *       检索与图谱的数据访问由 entry 适配器实现
 *
 * 数据流:
 *   用户问题 → search.search → citations → graph.expand → 邻接引用 → NoteEvidenceContext
 *
 * 约束: 引用只来自真实 knowledge_unit 行；不写库；不引入向量检索
 */
import type {
  CitationVersionRef,
  NoteDetail,
  NoteEvidenceOptions,
  NoteEvidencePort,
  NoteEvidenceSearchPort,
  NoteEvidenceStreamFilterPort,
  NoteGraphNeighborhood,
  NoteGraphPort,
  NoteReadPort,
} from 'common';
import { markdownToPlainText, NoteRetrievalQuery } from 'common';
import {
  NoteEvidenceCitation,
  NoteEvidenceContext,
  NoteEvidenceRelation,
  NoteEvidenceRole,
} from 'common';


const EVIDENCE_DEFAULT_TOP_K: number = 5;
const EVIDENCE_MAX_TOP_K: number = 10;
const EVIDENCE_DEFAULT_DEPTH: number = 1;
const EVIDENCE_MAX_DEPTH: number = 2;
const EVIDENCE_MAX_CITATIONS: number = 10;
const EVIDENCE_DEFAULT_CONTEXT_CHARS: number = 2400;
const EVIDENCE_MIN_CONTEXT_CHARS: number = 400;
const EVIDENCE_MAX_CONTEXT_CHARS: number = 8000;
const EVIDENCE_EXCERPT_LIMIT: number = 160;
const CITATION_MARKER: string = '[noteId=';
const CITATION_UNVERIFIED: string = '[未验证引用]';

interface TextSplit {
  text: string;
  carry: string;
}

export class NoteEvidenceService implements NoteEvidencePort {
  private readonly search: NoteEvidenceSearchPort;
  private readonly graph: NoteGraphPort;
  private readonly read: NoteReadPort | undefined;

  constructor(search: NoteEvidenceSearchPort, graph: NoteGraphPort, read?: NoteReadPort) {
    this.search = search;
    this.graph = graph;
    this.read = read;
  }

  // 构建证据上下文; 任何失败都降级为 degraded 上下文, 不阻断回答
  async build(query: string, options?: NoteEvidenceOptions): Promise<NoteEvidenceContext> {
    const normalizedQuery: string = NoteRetrievalQuery.normalize(query);
    const topK: number = NoteEvidenceService.clampTopK(options?.topK);
    const maxDepth: number = NoteEvidenceService.clampDepth(options?.maxDepth);
    if (normalizedQuery.length === 0) {
      return NoteEvidenceService.emptyContext(normalizedQuery, topK, 'empty-query');
    }
    let citations: NoteEvidenceCitation[] = [];
    try {
      citations = await this.search.search(normalizedQuery, topK, options);
    } catch (e) {
      return NoteEvidenceService.degradedContext(normalizedQuery, topK, 'search-failed');
    }
    if (citations.length === 0) {
      return NoteEvidenceService.emptyContext(normalizedQuery, topK, 'no-match');
    }
    const relations: NoteEvidenceRelation[] = [];
    let degraded: boolean = false;
    let reason: string = '';
    const graphMode: 'neighborhood' | 'prerequisite-incoming' | 'none' =
      options?.graphMode === undefined ? 'neighborhood' : options.graphMode;
    if (graphMode !== 'none') {
      try {
        if (graphMode === 'prerequisite-incoming') {
          await this.expandPrerequisites(citations, relations, maxDepth);
        } else {
          await this.expandGraph(citations, relations, maxDepth);
        }
      } catch (e) {
        degraded = true;
        reason = 'graph-failed';
      }
    }
    citations = NoteEvidenceService.capCitations(citations);
    NoteEvidenceService.filterRelationsForCitations(relations, citations);
    NoteEvidenceService.refreshCitationRoles(citations, relations);
    const budget: number = NoteEvidenceService.clampContextChars(options?.maxContextChars);
    if (NoteEvidenceService.trimToBudget(citations, relations, budget) && reason.length === 0) {
      reason = 'budget-truncated';
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
  formatRetrievalStatus(context: NoteEvidenceContext): string {
    if (context.citations.length > 0) {
      const count: number = Math.min(context.citations.length, EVIDENCE_MAX_CITATIONS);
      const partial: string = context.degraded ? '；知识关系扩展不完整，仅使用已取得的笔记证据' : '';
      return '笔记检索：命中 ' + count.toString() + ' 条' + partial + '。';
    }
    if (context.degraded) {
      const reason: string = context.reason === 'store-not-ready' ? '笔记库尚未就绪' : '查询异常';
      return '笔记检索：失败（' + reason + '），本次回答未使用个人笔记证据。';
    }
    if (context.reason === 'empty-query') {
      return '笔记检索：未检索（没有明确主题），本次回答未使用个人笔记证据。';
    }
    return '笔记检索：未命中已保存笔记，本次回答未使用个人笔记证据。';
  }

  formatSources(context: NoteEvidenceContext): string {
    if (context.citations.length === 0) {
      return '';
    }
    const limited: NoteEvidenceCitation[] = NoteEvidenceService.capCitations(context.citations);
    const lines: string[] = [];
    lines.push(this.formatRetrievalStatus(context));
    lines.push('参考来源：');
    for (const citation of limited) {
      lines.push('- ' + NoteEvidenceService.roleLabel(citation.role)
        + ' [noteId=' + citation.noteId + ' version=' + citation.version.toString() + '] '
        + '《' + citation.title + '》：' + markdownToPlainText(citation.excerpt));
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

  sanitizeAnswerStrict(citations: NoteEvidenceCitation[], answer: string): string {
    const filter: NoteEvidenceStreamFilter = this.createStrictStreamFilter(citations);
    return filter.push(answer) + filter.flush();
  }

  // 流式增量清洗器: 未启用时原样透传
  createStreamFilter(context: NoteEvidenceContext | undefined): NoteEvidenceStreamFilter {
    const allowed: CitationVersionRef[] = [];
    if (context !== undefined) {
      for (const citation of context.citations) {
        NoteEvidenceService.addUniqueRef(allowed, citation.noteId, citation.version);
      }
    }
    return new NoteEvidenceStreamFilter(allowed, false);
  }

  createStrictStreamFilter(citations: NoteEvidenceCitation[]): NoteEvidenceStreamFilter {
    const allowed: CitationVersionRef[] = [];
    for (const citation of citations) {
      NoteEvidenceService.addUniqueRef(allowed, citation.noteId, citation.version);
    }
    return new NoteEvidenceStreamFilter(allowed, true);
  }

  hasVerifiedCitation(citations: NoteEvidenceCitation[], answer: string): boolean {
    const allowed: CitationVersionRef[] = [];
    for (const citation of citations) {
      NoteEvidenceService.addUniqueRef(allowed, citation.noteId, citation.version);
    }
    return NoteEvidenceService.hasAllowedCitation(allowed, answer);
  }

  /**
   * R3：本地 FTS 召回 → join knowledge_unit（取 version）→ NoteEvidenceCitation。
   * 返回 undefined 表示「无法使用 FTS」（表未就绪/查询异常），调用方回退 note.search；
   * 返回空数组表示 FTS 可用但无命中。
   */
  private async expandGraph(
    citations: NoteEvidenceCitation[],
    relations: NoteEvidenceRelation[],
    maxDepth: number,
  ): Promise<void> {
    const seeds: string[] = [];
    for (const citation of citations) {
      NoteEvidenceService.addUnique(seeds, citation.noteId);
    }
    const expansion: NoteGraphNeighborhood = await this.graph.expandAcceptedNeighborhood(seeds, maxDepth);
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
    if (missing.length > 0) {
      const rows: NoteDetail[] = this.read === undefined ? [] : await this.read.listByIds(missing);
      for (const row of rows) {
        citations.push({
          noteId: row.id,
          version: row.version,
          title: row.title,
          excerpt: NoteEvidenceService.buildExcerpt(row.content, row.summary),
          role: 'related',
          score: 0,
          matchedFields: [],
          subject: row.subject,
          chapter: row.chapter,
        });
      }
    }
    const relationSeen: string[] = [];
    for (const edge of expansion.edges) {
      if (relationSeen.indexOf(edge.id) >= 0) {
        continue;
      }
      if (NoteEvidenceService.containsNoteId(citations, edge.fromUnitId)
        && NoteEvidenceService.containsNoteId(citations, edge.toUnitId)) {
        relationSeen.push(edge.id);
        relations.push({
          edgeId: edge.id,
          fromNoteId: edge.fromUnitId,
          toNoteId: edge.toUnitId,
          relationType: edge.relationType === 'prerequisite' ? 'prerequisite' : 'related',
          reason: edge.reason,
        });
      }
    }
    NoteEvidenceService.refreshCitationRoles(citations, relations);
  }

  private async expandPrerequisites(
    citations: NoteEvidenceCitation[],
    relations: NoteEvidenceRelation[],
    maxDepth: number,
  ): Promise<void> {
    const seeds: string[] = [];
    for (const citation of citations) {
      NoteEvidenceService.addUnique(seeds, citation.noteId);
    }
    const expansion: NoteGraphNeighborhood = await this.graph.expandAcceptedPrerequisites(seeds, maxDepth);
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
        relationType: 'prerequisite',
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
    const rows: NoteDetail[] = this.read === undefined ? [] : await this.read.listByIds(missing);
    for (const row of rows) {
      citations.push({
        noteId: row.id,
        version: row.version,
        title: row.title,
        excerpt: NoteEvidenceService.buildExcerpt(row.content, row.summary),
        role: 'prerequisite',
        score: 0,
        matchedFields: [],
        subject: row.subject,
        chapter: row.chapter,
      });
    }
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

  private static clampContextChars(value: number | undefined): number {
    if (value === undefined || value <= 0) {
      return EVIDENCE_DEFAULT_CONTEXT_CHARS;
    }
    if (value < EVIDENCE_MIN_CONTEXT_CHARS) {
      return EVIDENCE_MIN_CONTEXT_CHARS;
    }
    if (value > EVIDENCE_MAX_CONTEXT_CHARS) {
      return EVIDENCE_MAX_CONTEXT_CHARS;
    }
    return value;
  }

  /** 044 R4：按字符预算从尾部裁引用与关系；返回是否发生了截断。 */
  private static trimToBudget(citations: NoteEvidenceCitation[], relations: NoteEvidenceRelation[],
    budget: number): boolean {
    let truncated: boolean = false;
    while (citations.length > 0
      && NoteEvidenceService.formatContext(citations, relations).length > budget) {
      citations.pop();
      NoteEvidenceService.filterRelationsForCitations(relations, citations);
      truncated = true;
    }
    while (relations.length > 0
      && NoteEvidenceService.formatContext(citations, relations).length > budget) {
      relations.pop();
      truncated = true;
    }
    return truncated;
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

  private static containsNoteId(citations: NoteEvidenceCitation[], noteId: string): boolean {
    for (const citation of citations) {
      if (citation.noteId === noteId) {
        return true;
      }
    }
    return false;
  }

  private static filterRelationsForCitations(relations: NoteEvidenceRelation[], citations: NoteEvidenceCitation[]): void {
    const kept: NoteEvidenceRelation[] = [];
    for (const relation of relations) {
      if (NoteEvidenceService.containsNoteId(citations, relation.fromNoteId)
        && NoteEvidenceService.containsNoteId(citations, relation.toNoteId)) {
        kept.push(relation);
      }
    }
    relations.splice(0, relations.length);
    for (const relation of kept) {
      relations.push(relation);
    }
  }

  private static refreshCitationRoles(citations: NoteEvidenceCitation[], relations: NoteEvidenceRelation[]): void {
    for (const citation of citations) {
      if (citation.role !== 'hit') {
        citation.role = NoteEvidenceService.roleFor(citation.noteId, relations);
      }
    }
  }

  private static addUniqueRef(target: CitationVersionRef[], noteId: string, version: number): void {
    if (noteId.length === 0 || version <= 0) {
      return;
    }
    for (const item of target) {
      if (item.noteId === noteId && item.version === version) {
        return;
      }
    }
    target.push({ noteId: noteId, version: version });
  }

  private static hasAllowedCitation(allowed: CitationVersionRef[], text: string): boolean {
    let cursor: number = 0;
    while (cursor < text.length) {
      const start: number = text.indexOf(CITATION_MARKER, cursor);
      if (start < 0) {
        return false;
      }
      const end: number = text.indexOf(']', start + CITATION_MARKER.length);
      if (end < 0) {
        return false;
      }
      const raw: string = text.substring(start + CITATION_MARKER.length, end);
      const citation: CitationVersionRef = NoteEvidenceStreamFilter.readCitationRef(raw);
      if (NoteEvidenceService.refAllowed(allowed, citation)) {
        return true;
      }
      cursor = end + 1;
    }
    return false;
  }

  static refAllowed(allowed: CitationVersionRef[], citation: CitationVersionRef): boolean {
    if (citation.noteId.length === 0 || citation.version <= 0) {
      return false;
    }
    for (const item of allowed) {
      if (item.noteId === citation.noteId && item.version === citation.version) {
        return true;
      }
    }
    return false;
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

}

// 流式引用清洗: 缓冲可能被拆分的 [noteId=...] 片段, 允许集外替换为未验证标记
export class NoteEvidenceStreamFilter implements NoteEvidenceStreamFilterPort {
  private readonly allowed: CitationVersionRef[];
  private readonly enabled: boolean;
  private carry: string = '';

  constructor(allowedCitations: CitationVersionRef[], strictEmptySet: boolean = false) {
    this.allowed = allowedCitations;
    this.enabled = allowedCitations.length > 0 || strictEmptySet;
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
      const raw: string = buffer.substring(start + CITATION_MARKER.length, end);
      const citation: CitationVersionRef = NoteEvidenceStreamFilter.readCitationRef(raw);
      output += NoteEvidenceService.refAllowed(this.allowed, citation) ? buffer.substring(start, end + 1) : CITATION_UNVERIFIED;
      cursor = end + 1;
    }
    const done: TextSplit = { text: output, carry: '' };
    return done;
  }

  static readCitationRef(raw: string): CitationVersionRef {
    const normalized: string = raw.trim();
    let separator: number = -1;
    for (let index = 0; index < normalized.length; index += 1) {
      const ch: string = normalized.charAt(index);
      if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
        separator = index;
        break;
      }
    }
    if (separator <= 0) {
      return { noteId: '', version: 0 };
    }
    const noteId: string = normalized.substring(0, separator);
    const versionPart: string = normalized.substring(separator).trim();
    const marker: string = 'version=';
    if (!versionPart.startsWith(marker)) {
      return { noteId: noteId, version: 0 };
    }
    const digits: string = versionPart.substring(marker.length);
    if (digits.length === 0) {
      return { noteId: noteId, version: 0 };
    }
    for (let index = 0; index < digits.length; index += 1) {
      const ch: string = digits.charAt(index);
      if (ch < '0' || ch > '9') {
        return { noteId: noteId, version: 0 };
      }
    }
    const version: number = Number(digits);
    if (Number.isNaN(version) || version <= 0) {
      return { noteId: noteId, version: 0 };
    }
    return { noteId: noteId, version: version };
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
