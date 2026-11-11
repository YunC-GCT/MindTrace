/**
 * NoteReviewPort.ets — 复习回答计划的只读端口
 *
 * 路径: common/src/main/ets/ports/NoteReviewPort.ets
 * 职责: 让对话链路在不依赖 RDB / 证据实现的前提下产出复习计划与终答；
 *       实现（NoteReviewService）留在 entry，由组合根注入
 * 依赖: ../models/NoteReviewModels, ./NoteEvidencePort
 *
 * 数据流:
 *   用户内容 → classifyIntent → plan → createStreamFilter → finalizeModelAnswer
 */
import type { NoteReviewFinalization, NoteReviewIntent, NoteReviewPlan } from '../models/NoteReviewModels';
import type { NoteEvidenceStreamFilterPort } from './NoteEvidencePort';

export interface NoteReviewPort {
  classifyIntent(userContent: string): NoteReviewIntent | undefined;
  plan(userContent: string): Promise<NoteReviewPlan>;
  createStreamFilter(plan: NoteReviewPlan): NoteEvidenceStreamFilterPort;
  finalizeModelAnswer(plan: NoteReviewPlan, rawAnswer: string): NoteReviewFinalization;
  fallbackFailure(plan: NoteReviewPlan, reason: string): NoteReviewFinalization;
}
