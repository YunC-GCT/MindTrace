/**
 * NoteReviewModels.ets — 笔记可追溯复习回答的冻结契约
 *
 * 路径: common/src/main/ets/models/NoteReviewModels.ets
 * 职责: 定义复习意图、状态、反馈、来源解析结果、只读端口与拷纯函数
 * 依赖: ./NoteEvidenceModels
 *
 * 数据流:
 *   NoteReviewService → 本文件类型 → 对话 workflow / 复习来源卡片
 *
 * 约束: UI 和测试只消费本文件的类型；来源必须来自 NoteEvidenceService 构造的真实引用
 */

import { NoteEvidenceCitation, NoteEvidenceContext } from './NoteEvidenceModels';

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

/** 复习回答的计划类型：直接可答 / 硬拒答 / 走模型。 */
export type NoteReviewPlanKind = 'none' | 'terminal' | 'model';

export interface NoteReviewPlan {
  kind: NoteReviewPlanKind;
  answer: NoteReviewAnswer;
  displayText: string;
  modelUserContent: string;
  evidence?: NoteEvidenceContext;
  quizCount: number;
}

export interface NoteReviewFinalization {
  answer: NoteReviewAnswer;
  displayText: string;
}
