/**
 * LegacyDispatchAdapter.ets — A4 4c Step1/2：NoteOutcome → 旧 DispatchResult 的过渡适配器
 *
 * 路径: agents/src/main/ets/core/dispatch/LegacyDispatchAdapter.ets
 * 职责: 分支改为返回 `NoteOutcome` 之后，旧 `dispatch()`（#239 golden / 未迁移调用方）仍需要
 *       `DispatchResult` 外观；本适配器是**唯一**允许做这层转换的地方，Step 4 删旧入口时一并删除。
 * 依赖: common NoteOutcome / DispatchResult（仅类型）。
 *
 * 映射约束（保持旧外观，不新增字段）:
 *   committed   → success + data(unit) + classification/recognizedText
 *   readyPreview→ success + data(draft) + generation
 *   needsInput  → success=false + errorMessage(reason) + generation
 *   failed      → success=false + errorCode(code) + errorMessage(message) + generation
 *   cancelled   → success=false + errorCode='CANCELLED' + errorMessage；若 committed=true 仍带 data/迁移字段
 */
import type { DispatchResult, NoteOutcome } from 'common';

export class LegacyDispatchAdapter {
  static toDispatchResult(outcome: NoteOutcome): DispatchResult {
    const result: DispatchResult = {
      success: outcome.kind === 'committed' || outcome.kind === 'readyPreview',
      route: 'D1',
      durationMs: outcome.durationMs,
    };
    if (outcome.unit !== undefined) {
      result.data = outcome.unit;
    } else if (outcome.draft !== undefined) {
      result.data = outcome.draft;
    }
    if (outcome.classification !== undefined) {
      result.classification = outcome.classification;
    }
    if (outcome.recognizedText !== undefined) {
      result.recognizedText = outcome.recognizedText;
    }
    if (outcome.generation !== undefined) {
      result.generation = outcome.generation;
    }
    if (outcome.kind === 'failed') {
      const failedCode: string = outcome.code !== undefined ? outcome.code : '';
      if (failedCode.length > 0) {
        result.errorCode = failedCode;
      }
      result.errorMessage = outcome.message;
      if (outcome.retryable !== undefined) {
        result.errorRetryable = outcome.retryable;
      }
    } else if (outcome.kind === 'needsInput') {
      result.errorMessage = outcome.reason;
      if (outcome.generation !== undefined) {
        result.generation = outcome.generation;
      }
    } else if (outcome.kind === 'cancelled') {
      result.errorCode = 'CANCELLED';
      result.errorMessage = 'CONVERSATION_CANCELLED';
      result.cancelledCommitted = outcome.committed === true;
      if (outcome.noteId !== undefined) {
        result.cancelledNoteId = outcome.noteId;
      }
      if (outcome.version !== undefined) {
        result.cancelledVersion = outcome.version;
      }
      if (outcome.commitKey !== undefined) {
        result.cancelledCommitKey = outcome.commitKey;
      }
    }
    return result;
  }
}
