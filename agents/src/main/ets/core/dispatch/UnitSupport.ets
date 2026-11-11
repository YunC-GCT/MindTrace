/**
 * UnitSupport.ets — 分支模块共用的纯函数（从 CommandExecutor.ets 抽出）
 *
 * 路径: agents/src/main/ets/core/dispatch/UnitSupport.ets
 * 职责: 只放无状态、无依赖的转换函数，供 capture / prepared / generation 分支复用。
 * 依赖: common 类型（仅类型）。
 */

import type { DispatchPayload, BranchRequest, KnowledgeUnit } from 'common';

// 重新生成时保留原 unit 的元数据、只换正文并刷新 updatedAt。
export function copyRegeneratedUnit(unit: KnowledgeUnit, content: string): KnowledgeUnit {
  return {
    id: unit.id, title: unit.title, content: content, summary: unit.summary, tags: unit.tags,
    subject: unit.subject, category: unit.category, chapter: unit.chapter, difficulty: unit.difficulty,
    source: unit.source, createdAt: unit.createdAt, updatedAt: Date.now(), reviewStatus: unit.reviewStatus,
    nextReviewAt: unit.nextReviewAt, intervalDays: unit.intervalDays, easeFactor: unit.easeFactor,
    repetitions: unit.repetitions, prerequisites: unit.prerequisites, related: unit.related,
    embedding: unit.embedding, userId: unit.userId, version: unit.version,
  };
}

// capture 图的种子文本：只有 text payload 才有输入文本。
export function seedTextFromRequest(req: BranchRequest): string {
  if (req.payload.kind === 'text') {
    return req.payload.text;
  }
  return '';
}

// payload 形态 → KnowledgeUnit.source 口径（capture 分支用）。
export function sourceFromPayload(payload: DispatchPayload): string {
  if (payload.kind === 'image') { return 'camera_capture'; }
  if (payload.kind === 'text') { return 'manual'; }
  return 'file_import';
}
