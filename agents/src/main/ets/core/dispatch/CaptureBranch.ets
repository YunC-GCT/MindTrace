/**
 * CaptureBranch.ets — capture 分支（从 Dispatcher.ets 抽出）
 *
 * 路径: agents/src/main/ets/core/dispatch/CaptureBranch.ets
 * 职责: 组装 AgentState → 交给 NoteAgent 跑 capture 图 → 把 AgentState 映射成 DispatchResult
 *       （失败 / analysisOnly / 缺 unit / 成功四种外壳）。
 * 依赖: NoteAgent（子 Agent 装配）、DispatchOptions、UnitSupport。
 *
 * 边界:
 *   - 不负责路由：调用方（Dispatcher.dispatchRequest）已经确认不是 generation / preparedCandidate。
 *   - 不直接碰 RDB：持久化由 NoteAgent 的 PersistNode 经 NoteWritePort 完成（A1）。
 *   - 行为等价判据：#239 capture golden 快照。
 */
import { Logger } from 'common';
import type {
  DispatchRequest,
  DispatchResult,
  KnowledgeUnit,
  RunContext,
} from 'common';
import { AgentState } from '../../graph/AgentState';
import type { CaptureGraphError } from '../../graph/AgentState';
import { NoteAgent } from '../../agents/NoteAgent';
import type { NoteAgentOptions } from '../../agents/NoteAgent';
import type { DispatchOptions } from './DispatchOptions';
import { seedTextFromRequest, sourceFromPayload } from './UnitSupport';

const log = new Logger('CaptureBranch');

export class CaptureBranch {
  static async dispatchCapture(
    req: DispatchRequest,
    options: DispatchOptions,
    runContext: RunContext,
    startedAt: number,
  ): Promise<DispatchResult> {
    log.info('dispatch enter, source=' + req.source + ', payload.kind=' + req.payload.kind);
    const initial: AgentState = {
      captureText: seedTextFromRequest(req),
      source: sourceFromPayload(req.payload),
      payload: req.payload,
      currentStep: 'START',
      persist: options.persist !== false,
      analysisOnly: options.analysisOnly === true,
      subjectVocabulary: options.subjectVocabulary ?? [],
    };
    // #241：capture 由 NoteAgent 子 Agent 装配并执行，这里只负责 run 上下文与结果映射。
    const noteOptions: NoteAgentOptions = {
      dao: options.dao,
      noteWritePort: options.noteWritePort,
      cancellationToken: options.cancellationToken,
      onNodeTiming: options.onNodeTiming,
    };
    const noteAgent: NoteAgent = new NoteAgent(noteOptions);
    // #243：预算与取消是运行时属性，只走调用参数，不经 AgentState。
    const finalState: AgentState = await noteAgent.run(initial, runContext);
    const error: CaptureGraphError | undefined = finalState.error;
    const requestCancelled: boolean = options.cancellationToken !== undefined
      && options.cancellationToken.isCancelled();
    const cancelledTerminal: boolean = requestCancelled
      || (error !== undefined && error.kind === 'CANCELLED');
    if (cancelledTerminal) {
      if (options.reportCancellation === true) {
        // ADR-0019 (e)：先看事务结果，再看 token —— 已落库的写必须报 committed=true。
        return CaptureBranch.cancelledResult(finalState, error, options, startedAt);
      }
      // 旧 dispatch()：保持 #239 golden 锁定的旧外观（capture 图内取消仍抛错）。
      options.cancellationToken?.throwIfCancelled();
    }
    if (error !== undefined) {
      log.error('capture graph failed: ' + error.kind + ' step=' + error.step + ' msg=' + error.message);
      const failed: DispatchResult = {
        success: false,
        route: 'D1',
        errorMessage: error.message,
        durationMs: Date.now() - startedAt,
      };
      if (options.reportCancellation === true) {
        failed.errorCode = error.kind;
        failed.errorRetryable = error.retriable;
      }
      if (finalState.classification !== undefined) {
        failed.classification = finalState.classification;
      }
      if (options.includeRawText === true) {
        failed.recognizedText = finalState.captureText;
      }
      return failed;
    }
    if (finalState.analysisOnly) {
      const analysis: DispatchResult = {
        success: finalState.classification !== undefined,
        route: 'D1',
        durationMs: Date.now() - startedAt,
      };
      if (finalState.classification !== undefined) {
        analysis.classification = finalState.classification;
      } else {
        analysis.errorMessage = 'capture workflow did not produce a classification';
      }
      if (options.includeRawText === true) {
        analysis.recognizedText = finalState.captureText;
      }
      log.info('dispatch analysis completed');
      return analysis;
    }
    const unit: KnowledgeUnit | undefined = finalState.knowledgeUnit;
    if (unit === undefined) {
      const missing: DispatchResult = {
        success: false,
        route: 'D1',
        errorMessage: 'capture graph did not produce a knowledge unit',
        durationMs: Date.now() - startedAt,
      };
      if (finalState.classification !== undefined) {
        missing.classification = finalState.classification;
      }
      if (options.includeRawText === true) {
        missing.recognizedText = finalState.captureText;
      }
      return missing;
    }
    const success: DispatchResult = {
      success: true,
      route: 'D1',
      data: unit,
      durationMs: Date.now() - startedAt,
    };
    if (finalState.classification !== undefined) {
      success.classification = finalState.classification;
    }
    if (options.includeRawText === true) {
      success.recognizedText = finalState.captureText;
    }
    log.info('dispatch completed persisted=' + finalState.persist.toString() + ' category=' + unit.category);
    return success;
  }

  /**
   * ADR-0019 (e)：cancelled 终态。先读事务结果再读 token：
   * commitResult 存在 → committed=true 并带 noteId/version/commitKey；否则 committed=false。
   */
  private static cancelledResult(
    finalState: AgentState,
    error: CaptureGraphError | undefined,
    options: DispatchOptions,
    startedAt: number,
  ): DispatchResult {
    const commitResult = finalState.commitResult;
    const cancelled: DispatchResult = {
      success: false,
      route: 'D1',
      errorCode: 'CANCELLED',
      errorMessage: error !== undefined ? error.message : 'CONVERSATION_CANCELLED',
      durationMs: Date.now() - startedAt,
      cancelledCommitted: commitResult !== undefined,
    };
    if (commitResult !== undefined) {
      cancelled.cancelledNoteId = commitResult.noteId;
      cancelled.cancelledVersion = commitResult.version;
      cancelled.cancelledCommitKey = commitResult.commitKey;
      if (finalState.knowledgeUnit !== undefined) {
        cancelled.data = finalState.knowledgeUnit;
      }
    }
    if (finalState.classification !== undefined) {
      cancelled.classification = finalState.classification;
    }
    if (options.includeRawText === true) {
      cancelled.recognizedText = finalState.captureText;
    }
    return cancelled;
  }
}
