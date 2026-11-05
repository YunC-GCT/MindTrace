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
import { Logger, stripCitationMarkers } from 'common';

const formatLog: Logger = new Logger('ConversationFormat');

export function evidenceFooter(
  evidencePort: NoteEvidencePort,
  evidence: NoteEvidenceContext | undefined,
): string {
  if (evidence === undefined) {
    return '';
  }
  const footer: string = evidence.citations.length > 0
    ? evidencePort.formatSources(evidence)
    : evidencePort.formatRetrievalStatus(evidence);
  // noteId/version 是内部追溯信息，不展示给用户；引用校验仍用原始 citations。
  return stripCitationMarkers(footer);
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
  logCitationCoverage(evidence, answer, sanitized);
  return sanitized + '\n\n' + evidenceFooter(evidencePort, evidence);
}

/** 044 R4：回答里引用了多少 noteId、清洗后留下多少；只记日志，不改变回答。 */
export function logCitationCoverage(
  evidence: NoteEvidenceContext,
  rawAnswer: string,
  sanitizedAnswer: string,
): void {
  const rawRefs: number = countMarker(rawAnswer);
  if (rawRefs === 0) {
    return;
  }
  const keptRefs: number = countMarker(sanitizedAnswer);
  const coverage: number = keptRefs / rawRefs;
  formatLog.info('[RAG] citations=' + evidence.citations.length.toString()
    + ' answerRefs=' + rawRefs.toString()
    + ' keptRefs=' + keptRefs.toString()
    + ' droppedRefs=' + (rawRefs - keptRefs).toString()
    + ' coverage=' + coverage.toFixed(2));
}

function countMarker(text: string): number {
  let count: number = 0;
  let index: number = text.indexOf('[noteId=');
  while (index >= 0) {
    count += 1;
    index = text.indexOf('[noteId=', index + 8);
  }
  return count;
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
