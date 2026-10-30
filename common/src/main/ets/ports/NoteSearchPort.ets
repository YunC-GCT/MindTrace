/**
 * NoteSearchPort.ets — 笔记检索端口（v1 确定性关键词检索，不是向量检索）
 *
 * 路径: common/src/main/ets/ports/NoteSearchPort.ets
 * 职责: 声明检索请求 / 命中 / 端口，供 skill、RAG 证据链与未来的 Agent 工具共用；
 *       不含 SQL、Kit 或任何实现。
 * 依赖: ../models/CommonTypes（仅类型）
 *
 * 边界（ADR-0021 §检索）:
 *   - `NoteReadPort.search` 只匹配**元数据**；正文/标签/全文命中归本端口。
 *   - v1 实现是确定性关键词打分（title×4 / tags×3 / summary×2 / content×1），
 *     不是向量召回；换向量方案时只换实现，不动调用方。
 *   - 返回 TopK（默认 5、上限 10），排序稳定：分数降序 → updatedAt 降序 → noteId 升序。
 *   - `excerpt` 是正文命中窗口（无正文时退回摘要），两端截断带省略号。
 */

export const NOTE_SEARCH_DEFAULT_TOP_K: number = 5;
export const NOTE_SEARCH_MAX_TOP_K: number = 10;

export interface NoteSearchQuery {
  /** 必填；trim 后为空视为无检索 */
  query: string;
  /** 期望条数；实现会夹到 [1, NOTE_SEARCH_MAX_TOP_K] */
  topK: number;
  subject?: string;
  chapter?: string;
  tag?: string;
  updatedAfter?: number;
  updatedBefore?: number;
}

export interface NoteSearchHit {
  noteId: string;
  title: string;
  version: number;
  subject: string;
  chapter: string;
  tags: string[];
  summary: string;
  score: number;
  /** 命中字段：title / tags / summary / content 的子集 */
  matchedFields: string[];
  excerpt: string;
  updatedAt: number;
}

export interface NoteSearchPort {
  search(query: NoteSearchQuery): Promise<NoteSearchHit[]>;
}
