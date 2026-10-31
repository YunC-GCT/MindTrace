/**
 * CaptureBranch.ets — capture 分支（从 Dispatcher.ets 抽出）
 *
 * 路径: agents/src/main/ets/core/dispatch/CaptureBranch.ets
 * 职责: 组装 AgentState → 交给 NoteAgent 跑 capture 图 → 把 AgentState 映射成 NoteOutcome 终态
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
  BranchRequest,
  KnowledgeUnit,
  RunContext,
} from 'common';
import { AgentState } from '../../graph/AgentState';
import type { CaptureGraphError } from '../../graph/AgentState';
import { NoteAgent } from '../../agents/NoteAgent';
import type { NoteAgentOptions } from '../../agents/NoteAgent';
import type { DispatchOptions } from './DispatchOptions';
import type { NoteOutcome } from 'common';
import { seedTextFromRequest, sourceFromPayload } from './UnitSupport';

const log = new Logger('CaptureBranch');

export class CaptureBranch {
  static async dispatchCapture(
    req: BranchRequest,
    options: DispatchOptions,
    runContext: RunContext,
    startedAt: number,
  ): Promise<NoteOutcome> {
    const operationId: string = req.operationId !== undefined ? req.operationId : 'legacy';
    const failedOutcome = (message: string, code: string, retryable: boolean): NoteOutcome => {
      const outcome: NoteOutcome = {
        kind: 'failed', operationId: operationId, route: 'D1', durationMs: Date.now() - startedAt,
        code: code, message: message,
      };
      if (retryable) { outcome.retryable = true; }
      return outcome;
    };
    log.info('dispatch enter, source=' + req.source + ', payload.kind=' + req.payload.kind);
    const initial: AgentState = {
      captureText: seedTextFromRequest(req),
      source: sourceFromPayload(req.payload),
      payload: req.payload,
      currentStep: 'START',
      persist: options.persist !== false,
      analysisOnly: options.analysisOnly === true,
      subjectVocabulary: options.subjectVocabulary ?? [],
      commitKey: req.commitKey,
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
      // ADR-0019 (e)：先看事务结果，再看 token —— 已落库的写必须报 committed=true。
      return CaptureBranch.cancelledResult(req, finalState, error, options, startedAt);
    }
    if (error !== undefined) {
      log.error('capture graph failed: ' + error.kind + ' step=' + error.step + ' msg=' + error.message);
      const failed: NoteOutcome = failedOutcome(error.message, error.kind, error.retriable === true);
      if (finalState.classification !== undefined) {
        failed.classification = finalState.classification;
      }
      if (options.includeRawText === true) {
        failed.recognizedText = finalState.captureText;
      }
      return failed;
    }
    if (finalState.analysisOnly) {
      if (finalState.classification === undefined) {
        log.info('dispatch analysis completed');
        return failedOutcome('capture workflow did not produce a classification', '', false);
      }
      const classificationOutcome: NoteOutcome = {
        kind: 'readyPreview', operationId: operationId, route: 'D1', durationMs: Date.now() - startedAt,
        runId: '', checkpointId: '', classification: finalState.classification,
        recognizedText: options.includeRawText === true ? finalState.captureText : undefined,
      };
      log.info('dispatch analysis completed');
      return classificationOutcome;
    }
    const unit: KnowledgeUnit | undefined = finalState.knowledgeUnit;
    if (unit === undefined) {
      const missing: NoteOutcome = failedOutcome('capture graph did not produce a knowledge unit', '', false);
      if (finalState.classification !== undefined) {
        missing.classification = finalState.classification;
      }
      if (options.includeRawText === true) {
        missing.recognizedText = finalState.captureText;
      }
      return missing;
    }
    const success: NoteOutcome = {
      kind: 'committed', operationId: operationId, route: 'D1', durationMs: Date.now() - startedAt,
      noteId: unit.id, version: unit.version, unit: unit,
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
    req: BranchRequest,
    finalState: AgentState,
    error: CaptureGraphError | undefined,
    options: DispatchOptions,
    startedAt: number,
  ): NoteOutcome {
    const commitResult = finalState.commitResult;
    const cancelled: NoteOutcome = {
      kind: 'cancelled',
      operationId: req.operationId !== undefined ? req.operationId : 'legacy',
      route: 'D1',
      durationMs: Date.now() - startedAt,
      committed: commitResult !== undefined,
    };
    if (commitResult !== undefined) {
      cancelled.noteId = commitResult.noteId;
      cancelled.version = commitResult.version;
      cancelled.commitKey = commitResult.commitKey;
      if (finalState.knowledgeUnit !== undefined) {
        cancelled.unit = finalState.knowledgeUnit;
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
