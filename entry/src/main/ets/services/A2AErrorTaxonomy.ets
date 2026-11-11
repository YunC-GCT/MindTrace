/**
 * A2AErrorTaxonomy.ets — A2A 错误码、分类与用户文案的统一映射
 *
 * 路径: entry/src/main/ets/services/A2AErrorTaxonomy.ets
 * 职责: 把 A2A 的错误码收敛成一套分类 + 稳定文案；controller / ability 不再各自拼错误字符串。
 * 依赖: 无（纯函数，便于 Node 契约测试）。
 */
export type A2AErrorKind = 'protocol' | 'config' | 'model' | 'timeout' | 'ingest' | 'none';

export type A2AErrorCode =
  | 'A2A_PARSE_ERROR'
  | 'A2A_CONFIG_READ_TIMEOUT'
  | 'A2A_MODEL_UNUSABLE'
  | 'A2A_MODEL_ID_UNRESOLVED'
  | 'A2A_MODEL_NOT_READY'
  | 'A2A_LLM_TIMEOUT'
  | 'A2A_DEADLINE_EXCEEDED'
  | 'A2A_LLM_FAILED'
  | 'A2A_INGEST_TIMEOUT'
  | 'A2A_INGEST_FAILED'
  | 'A2A_REPLY_SENT';

/** 错误分类：用于日志聚合与后续统一重试/降级策略。 */
export function a2aErrorKind(code: A2AErrorCode): A2AErrorKind {
  switch (code) {
    case 'A2A_PARSE_ERROR':
      return 'protocol';
    case 'A2A_CONFIG_READ_TIMEOUT':
      return 'config';
    case 'A2A_MODEL_UNUSABLE':
    case 'A2A_MODEL_ID_UNRESOLVED':
    case 'A2A_MODEL_NOT_READY':
    case 'A2A_LLM_FAILED':
      return 'model';
    case 'A2A_LLM_TIMEOUT':
    case 'A2A_DEADLINE_EXCEEDED':
      return 'timeout';
    case 'A2A_INGEST_TIMEOUT':
    case 'A2A_INGEST_FAILED':
      return 'ingest';
    default:
      return 'none';
  }
}

/**
 * 稳定用户文案。detail 的语义按 code 区分：
 * - CONFIG_READ_TIMEOUT: 超时毫秒数
 * - MODEL_UNUSABLE / MODEL_ID_UNRESOLVED: model + 原因
 * - LLM_FAILED: 底层错误原因
 * - INGEST_FAILED: 稳定错误码
 */
export function a2aErrorText(code: A2AErrorCode, detail: string = ''): string {
  switch (code) {
    case 'A2A_PARSE_ERROR':
      return '请求解析失败，请重试。';
    case 'A2A_CONFIG_READ_TIMEOUT':
      return '模型配置读取超时（' + detail + ' ms），请稍后再试。';
    case 'A2A_MODEL_UNUSABLE':
    case 'A2A_MODEL_ID_UNRESOLVED':
      return '模型不可用：' + detail;
    case 'A2A_MODEL_NOT_READY':
      return '端侧模型未就绪（model file not found），请先在 MindTrace 设置里配置模型';
    case 'A2A_LLM_TIMEOUT':
    case 'A2A_DEADLINE_EXCEEDED':
      return '模型响应超时，稍后再试。';
    case 'A2A_LLM_FAILED':
      return '模型暂时不可用：' + detail;
    case 'A2A_INGEST_TIMEOUT':
      return '这次整理较慢，已转待整理；打开 MindTrace 会自动补齐，稍后也能在 App 里看到。';
    case 'A2A_INGEST_FAILED':
      return '这次没整理成（' + detail + '），换个说法再发一次试试。';
    default:
      return detail;
  }
}
