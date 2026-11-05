/**
 * AnswerTextSanitizer.ets — 回答展示文本的清洗（纯函数，无 IO）
 *
 * 路径: common/src/main/ets/utils/AnswerTextSanitizer.ets
 * 职责:
 *   1. stripEchoedEvidence：去掉模型复述的证据块 / 工具 JSON（这些由界面单独展示）。
 *   2. markdownToPlainText：渲染失败时的纯文本降级，去掉 $$、标题、加粗等标记。
 * 依赖: 无。
 */
const EVIDENCE_LINE_PREFIXES: string[] = [
  '- [关键词命中]', '- [前置知识]', '- [关联知识]',
  '参考来源：', '以下是从用户已保存笔记中检索到的证据',
  '引用规范：', '已确认的知识关系',
];

const JSON_ECHO_MIN_CHARS: number = 60;

export function stripEchoedEvidence(text: string): string {
  const lines: string[] = text.split('\n');
  const kept: string[] = [];
  for (let i = 0; i < lines.length; i += 1) {
    const trimmed: string = lines[i].trim();
    if (isEvidenceLine(trimmed) || looksLikeJsonEcho(trimmed)) {
      continue;
    }
    kept.push(lines[i]);
  }
  return kept.join('\n').replace(/\n{3,}/g, '\n\n').trim();
}

function isEvidenceLine(trimmed: string): boolean {
  for (let i = 0; i < EVIDENCE_LINE_PREFIXES.length; i += 1) {
    if (trimmed.indexOf(EVIDENCE_LINE_PREFIXES[i]) === 0) {
      return true;
    }
  }
  return false;
}

function looksLikeJsonEcho(trimmed: string): boolean {
  if (trimmed.length < JSON_ECHO_MIN_CHARS) {
    return false;
  }
  return trimmed.indexOf('{"') === 0 || trimmed.indexOf('[{"') === 0;
}

/** 渲染失败时的纯文本降级：保留文字，去掉 markdown / 公式分隔符。 */
export function markdownToPlainText(text: string): string {
  let plain: string = text.replace(/\$\$/g, '');
  plain = plain.replace(/\$/g, '');
  plain = plain.replace(/\\left/g, '').replace(/\\right/g, '');
  plain = plain.replace(/^#{1,6}\s*/gm, '');
  plain = plain.replace(/\*\*([^*]+)\*\*/g, '$1');
  plain = plain.replace(/(^|\s)\*([^*\n]+)\*(?=\s|$)/g, '$1$2');
  plain = plain.replace(/`([^`]+)`/g, '$1');
  plain = plain.replace(/^[-*]\s+/gm, '• ');
  plain = plain.replace(/\n{3,}/g, '\n\n');
  return plain.trim();
}
