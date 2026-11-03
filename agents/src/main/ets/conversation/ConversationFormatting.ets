/**
 * ConversationFormatting.ets — 对话回复的纯格式化助手
 *
 * 路径: agents/src/main/ets/conversation/ConversationFormatting.ets
 * 职责: 证据脚注拼接、回答清洗、兜底文案识别；不持有状态，不碰工作流字段
 * 依赖: common（NoteEvidencePort / NoteEvidenceContext）
 *
 * 数据流:
 *   ConversationWorkflow 节点 → 本文件纯函数 → 展示文本
 */
import type { NoteEvidenceContext, NoteEvidencePort } from 'common';

export function evidenceFooter(
  evidencePort: NoteEvidencePort,
  evidence: NoteEvidenceContext | undefined,
): string {
  if (evidence === undefined) {
    return '';
  }
  return evidence.citations.length > 0
    ? evidencePort.formatSources(evidence)
    : evidencePort.formatRetrievalStatus(evidence);
}

export function applyEvidenceToAnswer(
  evidencePort: NoteEvidencePort,
  evidence: NoteEvidenceContext | undefined,
  answer: string,
): string {
  if (evidence === undefined) {
    return answer;
  }
  const sanitized: string = evidencePort.sanitizeAnswer(evidence, answer);
  return sanitized + '\n\n' + evidenceFooter(evidencePort, evidence);
}

/**
 * 重连结果是否只是兜底/检索状态文案，而不是模型对用户问题的回答。
 *
 * 局限: IConversationReplyPort.complete() 只回 string，没有 usedFallback 标记，
 * 只能按文本特征识别。判断必须在 applyEvidenceToAnswer 之前做 —— 正常回答追加的
 * 证据来源块本身就以“笔记检索：”开头，之后再判断会把成功重连误判成兜底。
 */
export function matchesFallbackShape(text: string): boolean {
  const probe: string = text.trim();
  if (probe.length === 0) {
    return false;
  }
  if (probe.indexOf('我是 MindTrace AI 数学助手') >= 0) {
    return true;
  }
  if (probe.indexOf('笔记检索：') >= 0) {
    return true;
  }
  return false;
}
