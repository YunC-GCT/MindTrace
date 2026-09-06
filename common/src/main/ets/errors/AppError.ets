// MindTrace - AppError 统一错误 (评审前 1.5 项 / fix/demo-polish-2026-09-06)
//
// 与现有错误结构的契约:
//   - LlmError (common/.../llm/LlmTypes.ets, 12 种 LlmErrorKind): 通过 cause 链入, 顶层 kind=LlmError.classify(kind)
//   - CaptureGraphError (agents/.../graph/AgentState.ets): 同上, 顶层 kind=CaptureGraphError.classify(step)
//   - 业务新错误: AppError 直接 new
//
// Severity 三级:
//   - info:    蓝色, 1.5s 自动消失 (例: 复制成功)
//   - warn:    琥珀色, 3s, 含操作建议 (例: API key 失效, 跳设置)
//   - error:   红色, 不自动消失, 含重试按钮 (例: 网络断开)
//
// Retry 建议 (前端可表达的三种):
//   - 'none':   不需要重试 (业务逻辑错误)
//   - 'retry':  一键重试 (当前操作可重发)
//   - 'jump':   跳转 (例: 设置页 / 重拍)

export type ErrorSeverity = 'info' | 'warn' | 'error';
export type ErrorAction = 'none' | 'retry' | 'jump';

export type AppErrorKind =
  | 'NETWORK_OFFLINE'
  | 'NETWORK_TIMEOUT'
  | 'LLM_AUTH_FAIL'
  | 'LLM_RATE_LIMIT'
  | 'LLM_CONTEXT_TOO_LONG'
  | 'LLM_OUTPUT_INVALID'
  | 'OCR_NOT_RECOGNIZED'
  | 'OCR_SERVICE_DOWN'
  | 'RDB_WRITE_FAIL'
  | 'RDB_READ_FAIL'
  | 'FILE_NOT_FOUND'
  | 'INVALID_INPUT'
  | 'PERMISSION_DENIED'
  | 'UNKNOWN';

export interface AppErrorShape {
  kind: AppErrorKind;
  severity: ErrorSeverity;
  title: string;            // 用户可读分类名 (例: '网络断开' / 'API Key 失效')
  message: string;          // 详细用户消息
  action: ErrorAction;
  actionLabel?: string;     // 按钮文案 (例: '去设置' / '重试')
  cause?: Object;           // 链入的原始错误 (LlmError / CaptureGraphError / Error)
  timestamp: number;        // Date.now()
}

export class AppError implements AppErrorShape {
  public kind: AppErrorKind;
  public severity: ErrorSeverity;
  public title: string;
  public message: string;
  public action: ErrorAction;
  public actionLabel: string | undefined;
  public cause: Object | undefined;
  public timestamp: number;

  constructor(shape: AppErrorShape) {
    this.kind = shape.kind;
    this.severity = shape.severity;
    this.title = shape.title;
    this.message = shape.message;
    this.action = shape.action;
    this.actionLabel = shape.actionLabel;
    this.cause = shape.cause;
    this.timestamp = shape.timestamp;
  }

  static from(cause: Error | undefined, fallback: AppErrorShape): AppError {
    // 包装任意 Error 派生对象 (LlmError / CaptureGraphError / 普通 Error) 为 AppError;
    // kind/severity/title/action 由调用方按业务分类传入, cause 保留原始对象供日志。
    return new AppError({
      kind: fallback.kind,
      severity: fallback.severity,
      title: fallback.title,
      message: fallback.message,
      action: fallback.action,
      actionLabel: fallback.actionLabel,
      cause: cause,
      timestamp: fallback.timestamp,
    });
  }
}
