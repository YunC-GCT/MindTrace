// MindTrace - P1 只读笔记工具 (spec 014 §4 / ADR-0012)
// 位置: common/src/main/ets/tools/NoteQueryTools.ets
// 职责: 首批只读 AgentTool (note_query / note_get / review_due_query), 供 ToolLoop 注册使用;
//       未来 skill/ IntentRouter 复用同一 registry (ADR-0011)
// DEV-004 新增 note_query_rag: 确定性关键词 RAG (标题/标签/摘要/正文命中, TopK 默认 5 上限 10,
//       稳定排序, 正文摘录, 只查存活 knowledge_unit); 经 createNoteRagTools 独立注册,
//       不改变 createReadOnlyNoteTools 的三工具旧契约
// schema source-of-truth: entry/src/main/ets/database/NoteDao.ets — knowledge_unit 表与列名
//       以 NoteDao 为准, 本文件只读直查; 两端漂移时以 NoteDao 为准修这里
// 安全边界: 只读 — 无 insert/update/delete; 写工具统一等 F2 (spec 014 out of scope)
// store 获取: DatabaseHelper.getStore() — entry 组合根负责 init; 未就绪返回 ok:false 'store not ready'
//
// ArkTS 1.1 严格语法: 显式类型 / 无 spread / 无 untyped 对象字面量 (Record 走 bracket 赋值)

import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper } from '../DatabaseHelper';
import { ReviewStatus } from '../models/CommonTypes';
import { AgentTool, ToolResult } from './ToolRegistry';

const TABLE: string = 'knowledge_unit';
const MAX_QUERY_RESULTS: number = 20;
const LEGAL_REVIEW_STATUSES: string[] = [
  ReviewStatus.NEW,
  ReviewStatus.LEARNING,
  ReviewStatus.REVIEW,
  ReviewStatus.GRADUATED,
  ReviewStatus.LAPSED,
];

// note_query_rag: 默认/上限 TopK 与确定性打分权重 (标题 > 标签 > 摘要 > 正文)
const RAG_DEFAULT_TOP_K: number = 5;
const RAG_MAX_TOP_K: number = 10;
const RAG_TITLE_WEIGHT: number = 4;
const RAG_TAG_WEIGHT: number = 3;
const RAG_SUMMARY_WEIGHT: number = 2;
const RAG_EXCERPT_LEAD: number = 60;
const RAG_EXCERPT_LENGTH: number = 160;

// 内部打分候选行; 仅用于本文件排序, 不对外导出
interface RagScoredHit {
  noteId: string;
  title: string;
  version: number;
  subject: string;
  chapter: string;
  tags: string;
  summary: string;
  content: string;
  updatedAt: number;
  score: number;
  matchedFields: string[];
  excerpt: string;
}

function readStr(rs: relationalStore.ResultSet, col: string): string {
  return rs.getString(rs.getColumnIndex(col));
}

function readLong(rs: relationalStore.ResultSet, col: string): number {
  return rs.getLong(rs.getColumnIndex(col));
}

function stringProp(description: string): Record<string, Object> {
  const prop: Record<string, Object> = {};
  prop['type'] = 'string';
  prop['description'] = description;
  return prop;
}

function objectSchema(props: Record<string, Object>): Record<string, Object> {
  const schema: Record<string, Object> = {};
  schema['type'] = 'object';
  schema['properties'] = props;
  return schema;
}

function numberProp(description: string): Record<string, Object> {
  const prop: Record<string, Object> = {};
  prop['type'] = 'number';
  prop['description'] = description;
  return prop;
}

function readNumberArg(value: Object): number {
  if (typeof value === 'number') {
    return value;
  }
  return Number(String(value));
}

function readOptionalNumber(value: Object | undefined): number | undefined {
  if (value === undefined || value === null || String(value).trim().length === 0) {
    return undefined;
  }
  const parsed: number = readNumberArg(value);
  if (Number.isNaN(parsed)) {
    return undefined;
  }
  return parsed;
}

function readStringFilter(value: Object | undefined): string {
  if (value === undefined || value === null) {
    return '';
  }
  return String(value).trim();
}

// 非重叠子串计数; 大小写由调用方先归一化
function countOccurrences(haystack: string, needle: string): number {
  if (needle.length === 0) {
    return 0;
  }
  let count: number = 0;
  let index: number = haystack.indexOf(needle);
  while (index >= 0) {
    count += 1;
    index = haystack.indexOf(needle, index + needle.length);
  }
  return count;
}

// 正文摘录: 命中位置前后取窗口; 无正文时退回摘要; 两端截断显式加省略号
function buildRagExcerpt(content: string, summary: string, needle: string): string {
  const trimmedContent: string = content.trim();
  const source: string = trimmedContent.length > 0 ? content : summary;
  if (source.length === 0) {
    return '';
  }
  const hit: number = needle.length === 0 ? -1 : source.toLowerCase().indexOf(needle);
  let start: number = 0;
  if (hit > RAG_EXCERPT_LEAD) {
    start = hit - RAG_EXCERPT_LEAD;
  }
  let end: number = start + RAG_EXCERPT_LENGTH;
  if (end > source.length) {
    end = source.length;
  }
  let excerpt: string = source.substring(start, end).replace(/\s+/g, ' ').trim();
  if (start > 0) {
    excerpt = '…' + excerpt;
  }
  if (end < source.length) {
    excerpt = excerpt + '…';
  }
  return excerpt;
}

// 稳定排序: 分数降序 -> 更新时间降序 -> noteId 升序
function compareRagHits(a: RagScoredHit, b: RagScoredHit): number {
  if (a.score !== b.score) {
    return b.score - a.score;
  }
  if (a.updatedAt !== b.updatedAt) {
    return b.updatedAt - a.updatedAt;
  }
  if (a.noteId < b.noteId) {
    return -1;
  }
  if (a.noteId > b.noteId) {
    return 1;
  }
  return 0;
}

function rankRagHits(rows: RagScoredHit[], needle: string, topK: number): RagScoredHit[] {
  const scored: RagScoredHit[] = [];
  for (const row of rows) {
    const titleHits: number = countOccurrences(row.title.toLowerCase(), needle);
    const tagHits: number = countOccurrences(row.tags.toLowerCase(), needle);
    const summaryHits: number = countOccurrences(row.summary.toLowerCase(), needle);
    const contentHits: number = countOccurrences(row.content.toLowerCase(), needle);
    const score: number = titleHits * RAG_TITLE_WEIGHT
      + tagHits * RAG_TAG_WEIGHT
      + summaryHits * RAG_SUMMARY_WEIGHT
      + contentHits;
    if (score <= 0) {
      continue;
    }
    row.score = score;
    const matched: string[] = [];
    if (titleHits > 0) {
      matched.push('title');
    }
    if (tagHits > 0) {
      matched.push('tags');
    }
    if (summaryHits > 0) {
      matched.push('summary');
    }
    if (contentHits > 0) {
      matched.push('content');
    }
    row.matchedFields = matched;
    row.excerpt = buildRagExcerpt(row.content, row.summary, needle);
    scored.push(row);
  }
  scored.sort((a: RagScoredHit, b: RagScoredHit): number => compareRagHits(a, b));
  const ranked: RagScoredHit[] = [];
  for (let index = 0; index < scored.length && index < topK; index += 1) {
    ranked.push(scored[index]);
  }
  return ranked;
}

function ragHitRecord(hit: RagScoredHit): Record<string, Object> {
  const row: Record<string, Object> = {};
  row['noteId'] = hit.noteId;
  row['title'] = hit.title;
  row['version'] = hit.version;
  row['subject'] = hit.subject;
  row['chapter'] = hit.chapter;
  row['tags'] = hit.tags;
  row['summary'] = hit.summary;
  row['score'] = hit.score;
  row['matchedFields'] = hit.matchedFields;
  row['excerpt'] = hit.excerpt;
  row['updatedAt'] = hit.updatedAt;
  return row;
}

// 按条件检索笔记元数据 (subject / review_status / keyword, keyword 匹配 title 或 content, 上限 20 条)
export class NoteQueryTool implements AgentTool {
  public name: string = 'note_query';
  public description: string = 'Search saved math notes (KnowledgeUnit). Filter by subject, review_status, or keyword (matches title or content). Returns at most 20 notes as a JSON array of metadata.';
  public parameters: Record<string, Object>;

  constructor() {
    const props: Record<string, Object> = {};
    props['subject'] = stringProp('exact subject name, e.g. 数学分析');
    props['review_status'] = stringProp('one of: new, learning, review, graduated, lapsed');
    props['keyword'] = stringProp('keyword matched against title or content');
    this.parameters = objectSchema(props);
  }

  async execute(args: Record<string, Object>): Promise<ToolResult> {
    const statusArg: Object | undefined = args['review_status'];
    if (statusArg !== undefined && statusArg !== null) {
      const wanted: string = String(statusArg);
      if (LEGAL_REVIEW_STATUSES.indexOf(wanted) < 0) {
        const bad: ToolResult = { ok: false, content: 'review_status must be one of: ' + LEGAL_REVIEW_STATUSES.join(', ') };
        return bad;
      }
    }
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      const notReady: ToolResult = { ok: false, content: 'store not ready' };
      return notReady;
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    const subjectArg: Object | undefined = args['subject'];
    if (subjectArg !== undefined && subjectArg !== null && String(subjectArg).length > 0) {
      predicates.equalTo('subject', String(subjectArg));
    }
    if (statusArg !== undefined && statusArg !== null) {
      predicates.equalTo('review_status', String(statusArg));
    }
    const keywordArg: Object | undefined = args['keyword'];
    if (keywordArg !== undefined && keywordArg !== null) {
      const kw: string = String(keywordArg);
      if (kw.length > 0) {
        predicates.beginWrap();
        predicates.contains('title', kw);
        predicates.or();
        predicates.contains('content', kw);
        predicates.endWrap();
      }
    }
    predicates.limitAs(MAX_QUERY_RESULTS);
    const columns: string[] = ['id', 'title', 'summary', 'subject', 'category', 'chapter', 'difficulty', 'review_status', 'updated_at'];
    return new Promise<ToolResult>((resolve: (r: ToolResult) => void, reject: (e: Error) => void): void => {
      store.query(predicates, columns, (err, rs) => {
        if (err) {
          reject(new Error('note_query failed: ' + err.message));
          return;
        }
        const rows: Record<string, Object>[] = [];
        if (rs.goToFirstRow()) {
          do {
            const row: Record<string, Object> = {};
            row['id'] = readStr(rs, 'id');
            row['title'] = readStr(rs, 'title');
            row['summary'] = readStr(rs, 'summary');
            row['subject'] = readStr(rs, 'subject');
            row['category'] = readStr(rs, 'category');
            row['chapter'] = readStr(rs, 'chapter');
            row['difficulty'] = readStr(rs, 'difficulty');
            row['review_status'] = readStr(rs, 'review_status');
            row['updated_at'] = readLong(rs, 'updated_at');
            rows.push(row);
          } while (rs.goToNextRow());
        }
        rs.close();
        const ok: ToolResult = { ok: true, content: JSON.stringify(rows) };
        resolve(ok);
      });
    });
  }
}

// 确定性关键词 RAG: 标题/标签/摘要/正文命中 + subject/chapter/tag/time 过滤, TopK 默认 5 上限 10,
// 稳定排序, 正文摘录; 只返回仍存活于 knowledge_unit 的笔记 (删除后行已不存在, 不会被召回)
export class NoteQueryRagTool implements AgentTool {
  public name: string = 'note_query_rag';
  public description: string = 'Deterministic keyword retrieval over saved math notes. Matches query against title, tags, summary and content; optional subject/chapter/tag/updated_after/updated_before filters. Returns TopK (default 5, max 10) hits with noteId, version and content excerpt in a stable order.';
  public parameters: Record<string, Object>;

  constructor() {
    const props: Record<string, Object> = {};
    props['query'] = stringProp('required keyword or phrase to retrieve');
    props['topK'] = numberProp('optional result count, default 5, maximum 10');
    props['subject'] = stringProp('optional exact subject filter');
    props['chapter'] = stringProp('optional exact chapter filter');
    props['tag'] = stringProp('optional tag filter, matched inside the tags list');
    props['updated_after'] = numberProp('optional lower bound of updated_at in epoch milliseconds');
    props['updated_before'] = numberProp('optional upper bound of updated_at in epoch milliseconds');
    const schema: Record<string, Object> = objectSchema(props);
    const required: string[] = ['query'];
    schema['required'] = required;
    this.parameters = schema;
  }

  async execute(args: Record<string, Object>): Promise<ToolResult> {
    const query: string = readStringFilter(args['query']);
    if (query.length === 0) {
      const noQuery: ToolResult = { ok: false, content: 'note_query_rag requires a non-empty query' };
      return noQuery;
    }
    let topK: number = RAG_DEFAULT_TOP_K;
    const topKArg: Object | undefined = args['topK'];
    if (topKArg !== undefined && topKArg !== null && String(topKArg).trim().length > 0) {
      const parsed: number = readNumberArg(topKArg);
      if (Number.isNaN(parsed) || parsed < 1) {
        const badTopK: ToolResult = { ok: false, content: 'topK must be a positive integer' };
        return badTopK;
      }
      topK = Math.floor(parsed);
      if (topK > RAG_MAX_TOP_K) {
        topK = RAG_MAX_TOP_K;
      }
    }
    const updatedAfter: number | undefined = readOptionalNumber(args['updated_after']);
    const updatedBefore: number | undefined = readOptionalNumber(args['updated_before']);
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      const notReady: ToolResult = { ok: false, content: 'store not ready' };
      return notReady;
    }
    const needle: string = query.toLowerCase();
    const where: string[] = [];
    const bindArgs: string[] = [];
    where.push('(instr(lower(title), ?) > 0 OR instr(lower(tags), ?) > 0 OR instr(lower(summary), ?) > 0 OR instr(lower(content), ?) > 0)');
    bindArgs.push(needle, needle, needle, needle);
    const subject: string = readStringFilter(args['subject']);
    if (subject.length > 0) {
      where.push('subject = ?');
      bindArgs.push(subject);
    }
    const chapter: string = readStringFilter(args['chapter']);
    if (chapter.length > 0) {
      where.push('chapter = ?');
      bindArgs.push(chapter);
    }
    const tag: string = readStringFilter(args['tag']);
    if (tag.length > 0) {
      where.push('instr(lower(tags), ?) > 0');
      bindArgs.push(tag.toLowerCase());
    }
    if (updatedAfter !== undefined) {
      where.push('updated_at >= ?');
      bindArgs.push(updatedAfter.toString());
    }
    if (updatedBefore !== undefined) {
      where.push('updated_at <= ?');
      bindArgs.push(updatedBefore.toString());
    }
    const columns: string = 'id, title, tags, summary, content, subject, chapter, updated_at, version';
    const sql: string = 'SELECT ' + columns + ' FROM ' + TABLE + ' WHERE ' + where.join(' AND ')
      + ' ORDER BY updated_at DESC, id ASC';
    try {
      const rs: relationalStore.ResultSet = await store.querySql(sql, bindArgs);
      const candidates: RagScoredHit[] = [];
      if (rs.goToFirstRow()) {
        do {
          const row: RagScoredHit = {
            noteId: readStr(rs, 'id'),
            title: readStr(rs, 'title'),
            version: readLong(rs, 'version'),
            subject: readStr(rs, 'subject'),
            chapter: readStr(rs, 'chapter'),
            tags: readStr(rs, 'tags'),
            summary: readStr(rs, 'summary'),
            content: readStr(rs, 'content'),
            updatedAt: readLong(rs, 'updated_at'),
            score: 0,
            matchedFields: [],
            excerpt: '',
          };
          candidates.push(row);
        } while (rs.goToNextRow());
      }
      rs.close();
      const ranked: RagScoredHit[] = rankRagHits(candidates, needle, topK);
      const hits: Record<string, Object>[] = [];
      for (const hit of ranked) {
        hits.push(ragHitRecord(hit));
      }
      const payload: Record<string, Object> = {};
      payload['query'] = query;
      payload['topK'] = topK;
      payload['count'] = hits.length;
      payload['hits'] = hits;
      if (hits.length === 0) {
        payload['message'] = 'no matches';
      }
      const ok: ToolResult = { ok: true, content: JSON.stringify(payload) };
      return ok;
    } catch (e) {
      const failed: ToolResult = { ok: false, content: 'note_query_rag failed: ' + ((e as Error).message ?? String(e)) };
      return failed;
    }
  }
}

// 按 id 取单条笔记 (含全文 content)
export class NoteGetTool implements AgentTool {
  public name: string = 'note_get';
  public description: string = 'Fetch one saved math note by id, including full Markdown content. Returns a JSON object, or a "not found" message.';
  public parameters: Record<string, Object>;

  constructor() {
    const props: Record<string, Object> = {};
    props['id'] = stringProp('KnowledgeUnit id (required)');
    const schema: Record<string, Object> = objectSchema(props);
    const required: string[] = ['id'];
    schema['required'] = required;
    this.parameters = schema;
  }

  async execute(args: Record<string, Object>): Promise<ToolResult> {
    const idArg: Object | undefined = args['id'];
    if (idArg === undefined || idArg === null || String(idArg).length === 0) {
      const noId: ToolResult = { ok: false, content: 'note_get requires id' };
      return noId;
    }
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      const notReady: ToolResult = { ok: false, content: 'store not ready' };
      return notReady;
    }
    const id: string = String(idArg);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    const columns: string[] = ['id', 'title', 'content', 'summary', 'tags', 'subject', 'category', 'chapter', 'difficulty', 'source', 'created_at', 'updated_at', 'review_status', 'next_review_at', 'interval_days', 'user_id', 'version'];
    return new Promise<ToolResult>((resolve: (r: ToolResult) => void, reject: (e: Error) => void): void => {
      store.query(predicates, columns, (err, rs) => {
        if (err) {
          reject(new Error('note_get failed: ' + err.message));
          return;
        }
        const ok: ToolResult = { ok: true, content: '' };
        if (rs.goToFirstRow()) {
          const row: Record<string, Object> = {};
          row['id'] = readStr(rs, 'id');
          row['title'] = readStr(rs, 'title');
          row['content'] = readStr(rs, 'content');
          row['summary'] = readStr(rs, 'summary');
          row['tags'] = readStr(rs, 'tags');
          row['subject'] = readStr(rs, 'subject');
          row['category'] = readStr(rs, 'category');
          row['chapter'] = readStr(rs, 'chapter');
          row['difficulty'] = readStr(rs, 'difficulty');
          row['source'] = readStr(rs, 'source');
          row['created_at'] = readLong(rs, 'created_at');
          row['updated_at'] = readLong(rs, 'updated_at');
          row['review_status'] = readStr(rs, 'review_status');
          row['next_review_at'] = readLong(rs, 'next_review_at');
          row['interval_days'] = readLong(rs, 'interval_days');
          row['user_id'] = readStr(rs, 'user_id');
          row['version'] = readLong(rs, 'version');
          ok.content = JSON.stringify(row);
        } else {
          ok.content = 'not found: no note with id ' + id;
        }
        rs.close();
        resolve(ok);
      });
    });
  }
}

// 按 review_status 聚合计数 (可选单状态过滤)
export class ReviewDueQueryTool implements AgentTool {
  public name: string = 'review_due_query';
  public description: string = 'Count saved math notes grouped by review status (new / learning / review / graduated / lapsed). Optionally pass review_status to count one status only.';
  public parameters: Record<string, Object>;

  constructor() {
    const props: Record<string, Object> = {};
    props['review_status'] = stringProp('optional, one of: new, learning, review, graduated, lapsed');
    this.parameters = objectSchema(props);
  }

  async execute(args: Record<string, Object>): Promise<ToolResult> {
    const statusArg: Object | undefined = args['review_status'];
    let status: string | null = null;
    if (statusArg !== undefined && statusArg !== null && String(statusArg).length > 0) {
      const wanted: string = String(statusArg);
      if (LEGAL_REVIEW_STATUSES.indexOf(wanted) < 0) {
        const bad: ToolResult = { ok: false, content: 'review_status must be one of: ' + LEGAL_REVIEW_STATUSES.join(', ') };
        return bad;
      }
      status = wanted;
    }
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      const notReady: ToolResult = { ok: false, content: 'store not ready' };
      return notReady;
    }
    const counts: Record<string, Object> = {};
    try {
      if (status !== null) {
        const rs: relationalStore.ResultSet = await store.querySql('SELECT review_status, COUNT(*) AS cnt FROM knowledge_unit WHERE review_status = ? GROUP BY review_status', [status]);
        if (rs.goToFirstRow()) {
          counts[readStr(rs, 'review_status')] = readLong(rs, 'cnt');
        }
        rs.close();
      } else {
        const rs: relationalStore.ResultSet = await store.querySql('SELECT review_status, COUNT(*) AS cnt FROM knowledge_unit GROUP BY review_status');
        if (rs.goToFirstRow()) {
          do {
            counts[readStr(rs, 'review_status')] = readLong(rs, 'cnt');
          } while (rs.goToNextRow());
        }
        rs.close();
      }
    } catch (e) {
      const failed: ToolResult = { ok: false, content: 'review_due_query failed: ' + ((e as Error).message ?? String(e)) };
      return failed;
    }
    const ok: ToolResult = { ok: true, content: JSON.stringify(counts) };
    return ok;
  }
}

// 组合根入口: 把三个只读工具注册进 ToolRegistry (本 spec 不含注册接线, 由调用方决定)
export function createReadOnlyNoteTools(): AgentTool[] {
  const tools: AgentTool[] = [new NoteQueryTool(), new NoteGetTool(), new ReviewDueQueryTool()];
  return tools;
}

// DEV-004 独立入口: note_query_rag 单独成组, 避免改变 createReadOnlyNoteTools 的三工具旧契约
export function createNoteRagTools(): AgentTool[] {
  const tools: AgentTool[] = [new NoteQueryRagTool()];
  return tools;
}
