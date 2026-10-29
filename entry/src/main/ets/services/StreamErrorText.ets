/**
 * StreamErrorText.ets — 流式回复错误的中文文案映射
 *
 * 路径: entry/src/main/ets/services/StreamErrorText.ets
 * 职责: 将 LLM 错误码/原始消息按优先级映射为用户可理解的中文提示
 * 依赖: 无 (纯函数)
 *
 * 数据流:
 *   ConversationWorkflow.recoverStreamReply → streamErrorText(code, rawMessage) → 用户可见错误文案
 *
 * 设计要点:
 *   - 映射顺序敏感: 缺 key → 鉴权 → 限流 → 超时 → 5xx → 通用
 *   - 通用分支将 rawMessage 截断到 80 字, 避免长响应体撑爆气泡
 *
 * ArkTS 1.1 strict 适配:
 *   - 纯函数无状态; 入参与返回值显式标注 string/number
 */
export function streamErrorText(code: number, rawMessage: string): string {
  const message: string = rawMessage ?? '';
  const normalized: string = message.toLowerCase();
  if (message.indexOf('NO_API_KEY') >= 0) {
    return '未配置模型密钥，请到设置里填写';
  }
  if (code === 401 || code === 403
    || normalized.indexOf('auth') >= 0
    || message.indexOf('401') >= 0
    || message.indexOf('403') >= 0) {
    return '鉴权失败，请检查密钥是否正确';
  }
  if (code === 429
    || normalized.indexOf('rate') >= 0
    || normalized.indexOf('too many') >= 0
    || message.indexOf('429') >= 0) {
    return '请求太频繁，稍后再试';
  }
  if (normalized.indexOf('timeout') >= 0 || normalized.indexOf('etimedout') >= 0) {
    return '等待模型超时，可重试';
  }
  if ((code >= 500 && code <= 599)
    || message.indexOf('500') >= 0
    || message.indexOf('502') >= 0
    || message.indexOf('503') >= 0) {
    return '模型服务异常，稍后再试';
  }
  const detail: string = message.length > 80 ? message.substring(0, 80) : message;
  return '请求失败：' + detail;
}
