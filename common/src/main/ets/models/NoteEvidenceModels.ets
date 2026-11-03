/**
 * NoteEvidenceModels.ets — 可追溯回答的证据 / 上下文模型（DEV-006）
 *
 * 路径: common/src/main/ets/models/NoteEvidenceModels.ets
 * 职责: 定义回答引用所需的证据引用（noteId/version/excerpt）、知识关系快照和完整证据上下文
 * 依赖: 无
 *
 * 数据流:
 *   NoteEvidenceService → 真实 RDB 行 → 本文件 DTO → 对话 / 复习回答
 *
 * 约束: 引用字段不允许由模型输入；未出现在 citations 的 noteId 视为虚构来源
 */

// 证据角色: 关键词命中 / 前置知识 / 一般关联
export type NoteEvidenceRole = 'hit' | 'prerequisite' | 'related';

// 单条可追溯引用: noteId + version + excerpt 必须来自存活 knowledge_unit 行
export interface NoteEvidenceCitation {
  noteId: string;
  version: number;
  title: string;
  excerpt: string;
  role: NoteEvidenceRole;
  score: number;
  matchedFields: string[];
  subject: string;
  chapter: string;
}

// 已确认关系快照 (只含 accepted prerequisite/related)
export interface NoteEvidenceRelation {
  edgeId: string;
  fromNoteId: string;
  toNoteId: string;
  relationType: 'prerequisite' | 'related';
  reason: string;
}

// 回答证据上下文: contextText 注入 prompt, citations/relations 用于离线校验与来源回链
export interface NoteEvidenceContext {
  query: string;
  topK: number;
  citations: NoteEvidenceCitation[];
  relations: NoteEvidenceRelation[];
  contextText: string;
  degraded: boolean;
  reason: string;
}

/** 证据检索的可选裁剪参数（深度 / 学科 / 章节 / 标签 / 图谱模式）。 */
export interface NoteEvidenceOptions {
  topK?: number;
  maxDepth?: number;
  subject?: string;
  chapter?: string;
  tag?: string;
  graphMode?: 'neighborhood' | 'prerequisite-incoming' | 'none';
}

/** 允许被引用的笔记版本句柄。 */
export interface CitationVersionRef {
  noteId: string;
  version: number;
}
