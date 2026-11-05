/**
 * A2AConstants.ets — 小艺端A2A 的共享常量
 *
 * 路径: entry/src/main/ets/services/A2AConstants.ets
 * 职责: 日志域/标签与整理 deadline；控制器与整理处理器共用，避免两处各写一份
 * 依赖: 无
 *
 * 数据流: A2AController / A2AIngestHandler → hilog 与超时判断
 */
export const TAG: string = 'MindTraceA2A';
export const DOMAIN: number = 0xA2A0;
export const INGEST_DEADLINE_MS: number = 90000;

/** #234：小艺渲染层会吞掉 $...$ / LaTeX，扩展通道只发纯文本数学 */
export const A2A_REPLY_STYLE: 'plain_text_math' = 'plain_text_math';

/** A2A 单次回复预算；自洽关系 35000 >= 4000 + 1 * (25000 + 0) + 6000 */
export interface A2APolicy {
  configTimeoutMs: number;
  maxRetries: number;
  requestTimeoutMs: number;
  backoffMs: number;
  marginMs: number;
  deadlineMs: number;
  taskNeedTokens: number;
}

export const A2A_POLICY: A2APolicy = {
  configTimeoutMs: 4000,
  maxRetries: 0,
  requestTimeoutMs: 25000,
  backoffMs: 0,
  marginMs: 6000,
  deadlineMs: 35000,
  taskNeedTokens: 4096,
};

export function a2aAttempts(): number {
  return A2A_POLICY.maxRetries + 1;
}

export function a2aBudgetMs(): number {
  return A2A_POLICY.configTimeoutMs
    + a2aAttempts() * (A2A_POLICY.requestTimeoutMs + A2A_POLICY.backoffMs)
    + A2A_POLICY.marginMs;
}

/** 与 TaskSnapshot.unicodeCharCount 同口径：日志里的 chars= 不能拿 string.length 冒充「字」。 */
export function unicodeCharCount(text: string): number {
  let count: number = 0;
  for (let i = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length) {
      const next: number = text.charCodeAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        i += 1;
      }
    }
    count += 1;
  }
  return count;
}
