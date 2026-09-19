// ============================================================================
//  models/NoteEvidenceModels.ets — 可追溯回答证据/上下文模型 (DEV-006)
// ============================================================================
// 职责: 定义 answer 引用所需的证据引用 (noteId/version/excerpt)、知识关系快照
//       和完整证据上下文; 只由 NoteEvidenceService 从真实 RDB 行构造
// 约束: 引用字段不允许由模型输入; 未出现在 citations 的 noteId 视为虚构来源

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
