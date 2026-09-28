// ============================================================================
//  models/NoteReviewModels.ets — 笔记可追溯复习回答冻结契约
// ============================================================================
// 职责: 定义复习回答的意图、状态、反馈、来源解析结果和后端只读端口。
// 约束: UI 和测试只消费本文件的类型; 来源必须来自 NoteEvidenceService 构造的真实引用。
// ============================================================================

import { NoteEvidenceCitation } from './NoteEvidenceModels';

export type NoteReviewIntent = 'explain' | 'compare' | 'prerequisite' | 'locate' | 'quiz';

export type NoteReviewStatus = 'grounded' | 'insufficient' | 'unavailable';

export type NoteReviewFeedback = 'helpful' | 'unhelpful' | 'citation-incorrect';

export type NoteReviewSourceStatus = 'current' | 'historical' | 'deleted' | 'missing-version' | 'unavailable';

export interface NoteReviewAnswer {
  intent: NoteReviewIntent;
  query: string;
  status: NoteReviewStatus;
  reason: string;
  citations: NoteEvidenceCitation[];
  createdAt: number;
  feedback?: NoteReviewFeedback;
}

export interface NoteReviewSourceResult {
  status: NoteReviewSourceStatus;
  citation: NoteEvidenceCitation;
  content: string;
  currentVersion: number;
  message: string;
}

export interface NoteReviewSourceResolver {
  resolve(citation: NoteEvidenceCitation): Promise<NoteReviewSourceResult>;
}

export function copyNoteReviewAnswer(review: NoteReviewAnswer): NoteReviewAnswer {
  const next: NoteReviewAnswer = {
    intent: review.intent,
    query: review.query,
    status: review.status,
    reason: review.reason,
    citations: copyNoteEvidenceCitations(review.citations),
    createdAt: review.createdAt,
  };
  if (review.feedback !== undefined) {
    next.feedback = review.feedback;
  }
  return next;
}

export function copyNoteEvidenceCitations(citations: NoteEvidenceCitation[]): NoteEvidenceCitation[] {
  const copied: NoteEvidenceCitation[] = [];
  for (const citation of citations) {
    copied.push(copyNoteEvidenceCitation(citation));
  }
  return copied;
}

export function copyNoteEvidenceCitation(citation: NoteEvidenceCitation): NoteEvidenceCitation {
  return {
    noteId: citation.noteId,
    version: citation.version,
    title: citation.title,
    excerpt: citation.excerpt,
    role: citation.role,
    score: citation.score,
    matchedFields: citation.matchedFields.slice(0),
    subject: citation.subject,
    chapter: citation.chapter,
  };
}
