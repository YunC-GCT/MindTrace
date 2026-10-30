/**
 * NoteReadPort.ets — Note 读侧端口契约（list / get / search）
 *
 * 路径: common/src/main/ets/ports/NoteReadPort.ets
 * 职责: 声明读侧查询形状、返回投影、稳定错误码，以及 DAO 需要满足的最小存储缝；
 *       不含 DAO、SQL、Kit 或任何实现。
 * 依赖: ../models/CommonTypes（KnowledgeUnit / ReviewStatus，相对路径，避免 barrel 循环）；
 *       ./NoteWritePort（NotePortError，端口层统一错误类型）
 *
 * 数据流（目标态）:
 *   UI / ViewModel / ReviewAgent → NoteReadPort.list / get / search → entry 适配器 → note DAO
 *
 * 契约（#238 / §17.5）:
 *   - 必填项：结构化错误码 + retryable（统一用 NotePortError）。
 *   - list：先按 subject / chapter / keyword 过滤，再按 updatedAt 倒序，最后套 limit / offset 分页。
 *   - search：与 list 同一套查询形状；v1 只匹配元数据（title / summary / tags / subject / chapter），
 *     大小写不敏感；**不承诺全文检索**——正文命中属 RAG 层。
 *   - get：按 id 返回完整 KnowledgeUnit；不存在返回 null；查询失败抛 NOTE_READ_FAILED(retryable=true)。
 *   - 参数非法（limit <= 0 / offset < 0）抛 INVALID_QUERY(retryable=false)，不静默返回空数组。
 *   - 返回的 tags 是副本，调用方改投影不会污染存储。
 */
import { KnowledgeUnit, DifficultyLevel, ReviewStatus } from '../models/CommonTypes';

// 列表查询：过滤条件全部可选；limit / offset 必填，由调用方给出分页意图。
export interface NoteQuery {
  subject?: string;
  chapter?: string;
  keyword?: string;
  limit: number;
  offset: number;
}

// 列表投影：够渲染列表、跳详情，以及复习场景判断「该不该复习」。
export interface NoteSummary {
  id: string;
  title: string;
  summary: string;
  subject: string;
  chapter: string;
  category: string;
  tags: string[];
  difficulty: DifficultyLevel;
  reviewStatus: ReviewStatus;
  nextReviewAt: number;
  updatedAt: number;
  version: number;
}

// 读侧稳定错误码：与 ADR-0019 的错误分流口径一致。
export const NOTE_READ_ERROR_INVALID_QUERY: string = 'INVALID_QUERY';
export const NOTE_READ_ERROR_READ_FAILED: string = 'NOTE_READ_FAILED';

// DAO 需要满足的最小存储缝：只读两个查询，端口层不持 RDB 句柄。
// 契约放 common，实现（NoteDao）在 entry —— 依赖方向仍是 entry → common。
export interface NoteReadStore {
  queryById(id: string): Promise<KnowledgeUnit | null>;
  queryAllMetadata(): Promise<KnowledgeUnit[]>;
}

// 读侧端口。实现由 entry 侧适配器提供（NoteReadPortAdapter），common 不依赖任何 Kit。
export interface NoteReadPort {
  list(query: NoteQuery): Promise<NoteSummary[]>;
  get(id: string): Promise<KnowledgeUnit | null>;
  search(query: NoteQuery): Promise<NoteSummary[]>;
}
