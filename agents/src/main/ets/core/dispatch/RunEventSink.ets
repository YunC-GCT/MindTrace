/**
 * RunEventSink.ets — run 级事件流 seam（A4 可观测性第一片）
 *
 * 路径: agents/src/main/ets/core/dispatch/RunEventSink.ets
 * 职责: 定义「命令执行 → run 事件」的最小写出契约；CommandExecutor 在命令 seam 上发 start/terminal 事件，
 *       entry 侧实现落到 `run_store` / `run_event`（RunStorePort），测试侧可用内存 sink。
 * 依赖: 仅类型；不碰 Kit / RDB。
 *
 * 边界:
 *   - 事件写出是**尽力而为**：sink 抛错不得影响命令结果（可观测性不能反向打挂业务）。
 *   - payload 是 JSON 字符串，字段口径由 `dispatchEventPayload` 固定，避免各分支自定义格式。
 */
import type { NoteCommand, NoteOutcome } from 'common';

// 一条待写出的 run 事件（kind + JSON payload；runId 由调用方给）。
export interface DispatchRunEvent {
  kind: string;
  payloadJson: string;
}

export interface RunEventSink {
  emit(runId: string, event: DispatchRunEvent): Promise<void>;
  /** 可选：终态回写 run 记录（status / committed 事实）。未实现则只写事件。 */
  settle?(runId: string, outcome: NoteOutcome): Promise<void>;
}

// 默认 sink：不写出（旧调用方 / 未装配时使用，行为零变化）。
export class NullRunEventSink implements RunEventSink {
  async emit(_runId: string, _event: DispatchRunEvent): Promise<void> {
    // no-op
  }
}

export const DISPATCH_EVENT_START: string = 'dispatch.start';
export const DISPATCH_EVENT_TERMINAL: string = 'dispatch.terminal';
// spec 039 S3：细粒度事件（全部带 runId=operationId；payload 不落正文）
export const RUN_EVENT_NODE_ENDED: string = 'node.ended';
export const RUN_EVENT_COMMIT_COMMITTED: string = 'commit.committed';
export const RUN_EVENT_APPROVAL_REJECTED: string = 'approval.rejected';

export function dispatchStartPayload(command: NoteCommand): string {
  return JSON.stringify({
    commandKind: command.kind,
    source: command.source !== undefined ? command.source : 'app',
    commitKey: command.commitKey !== undefined ? command.commitKey : '',
  });
}

export function dispatchTerminalPayload(outcome: NoteOutcome): string {
  return JSON.stringify({
    outcomeKind: outcome.kind,
    code: outcome.code !== undefined ? outcome.code : '',
    retryable: outcome.retryable === true,
    committed: outcome.committed === true,
    noteId: outcome.noteId !== undefined ? outcome.noteId : '',
    durationMs: outcome.durationMs,
  });
}

export function nodeEndedPayload(step: string, elapsedMs: number): string {
  return JSON.stringify({
    step: step,
    durationMs: elapsedMs,
  });
}

export function commitCommittedPayload(outcome: NoteOutcome): string {
  return JSON.stringify({
    noteId: outcome.noteId !== undefined ? outcome.noteId : '',
    version: outcome.version !== undefined ? outcome.version : 0,
    commitKey: outcome.commitKey !== undefined ? outcome.commitKey : '',
  });
}

export function approvalRejectedPayload(code: string, message: string): string {
  return JSON.stringify({
    code: code,
    message: message,
  });
}
