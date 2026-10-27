/**
 * RunErrors.ets — run 停止原因的类型化错误与跨 realm 判定函数。
 *
 * 路径: common/src/main/ets/workflow/RunErrors.ets
 * 职责: 定义 CancellationError / DeadlineExceededError，并提供不依赖 instanceof 的判定函数。
 * 依赖: 无。
 *
 * 数据流:
 *   RunContext.throwIfStopped() → 抛 CancellationError / DeadlineExceededError
 *   CaptureGraph / Dispatcher 边界（步骤 3）→ isCancellationError / isDeadlineExceededError 分流
 *
 * 判定为什么不用 instanceof:
 *   生产代码里 `extends Error` 是允许的（StateGraphError / NotePortError 已如此），
 *   但契约测试用 note-review-ets-loader 的 vm 装载真实 .ets，每个装载模块各有自己的 realm，
 *   跨 realm 的构造函数不共享原型链，`instanceof` 会恒为 false（v7-note-contracts.test.mjs 已踩过）。
 *   因此判定只看 `name` + 自有 `code` 字段。
 *
 * 与 ADR-0019 的关系:
 *   code 取 ADR-0019 (c) 错误码表的 CANCELLED / DEADLINE_EXCEEDED，两者 retryable=false。
 *   DEADLINE_EXCEEDED 不复用 TIMEOUT：TIMEOUT 是 LLM 传输层瞬时超时（retryable=true），语义不同。
 *
 * ArkTS 1.1 strict 适配:
 *   - 显式字段 + 构造器赋值；`this.name` 在 super() 之后设置，日志里能看到稳定名字。
 *   - 判定入参是 Object，先挡空值再 `as` 读字段，不做解构。
 */

export class CancellationError extends Error {
  readonly code: string;

  constructor(message: string = 'run cancelled') {
    super(message);
    this.name = 'CancellationError';
    this.code = 'CANCELLED';
  }
}

export class DeadlineExceededError extends Error {
  readonly code: string;

  constructor(message: string = 'run deadline exceeded') {
    super(message);
    this.name = 'DeadlineExceededError';
    this.code = 'DEADLINE_EXCEEDED';
  }
}

// 两个错误类都声明了 readonly code；这里只读该字段，不用于 instanceof 判断。
function matchesRunError(error: Object, expectedName: string, expectedCode: string): boolean {
  const candidate: Error = error as Error;
  if (!candidate) {
    return false;
  }
  if (candidate.name !== expectedName) {
    return false;
  }
  const coded: CancellationError = error as CancellationError;
  return coded.code === expectedCode;
}

export function isCancellationError(error: Object): boolean {
  return matchesRunError(error, 'CancellationError', 'CANCELLED');
}

export function isDeadlineExceededError(error: Object): boolean {
  return matchesRunError(error, 'DeadlineExceededError', 'DEADLINE_EXCEEDED');
}
