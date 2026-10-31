// MindTrace - Dispatcher (主 Agent 调度中枢) · D2 CaptureGraph host
// 2026-09-05 · D2 Ticket #6: 唯一最终公共入口 dispatch()
import { KnowledgeModel } from '../agents/KnowledgeModel';
import { TruthCheckService } from '../agents/TruthCheckService';
import {
  Logger,
  RunContext,
  createRootRunContext,
  KnowledgeUnit,
  DispatchRequest,
  DispatchResult,
  NoteGenerationRepository,
  NoteGenerationRequest,
  NoteGenerationResult,
  NoteGenerationRun,
  NoteGenerationIssue,
  NoteGenerationRequirement,
  NoteGenerationCheckpoint,
  NoteGenerationCoverage,
  NoteGenerationBudget,
  PreparedCandidate,
  selectGenerationRoute,
  standardBudget,
  lightBudget,
  defaultRequirement,
  sourceFingerprint,
  buildSourceId,
  SourceBundle,
  SourceFragment,
  NoteGenerationCommitResult,
  NoteDraftDocument,
  NoteDraftSection,
  NoteGenerationStandardResult,
  NoteGenerationDeepResult,
  NoteGenerationRoute,
  NoteGenerationProgress,
  NoteGenerationProgressEvent,
  NoteGenerationProgressSink,
  IncrementalBase,
  IncrementalRequirement,
  IncrementalSection,
  IncrementalPlan,
  IncrementalPatchResponse,
  IncrementalDiffItem,
  IncrementalManifest,
  IncrementalMergeResult,
  parseIncrementalSections,
  detectIncrementalLocks,
  planIncrementalChange,
  mergeIncrementalPatches,
  renderIncrementalSections,
  buildIncrementalManifest,
  validateSourceBundle,
  deepBudget,
  segmentSourceBundle,
  buildDeepOutline,
  validateDeepOutline,
  captureProvenanceFromFragments,
  CaptureSetRequest,
  CaptureSetItemResult,
  CaptureSetResult,
} from 'common';
import type {
  DispatchPayload,
  CancellationToken,
  NoteBatchOutcome,
  NoteCommand,
  NoteOutcome,
} from 'common';
import { AgentState, CaptureGraphError, CaptureStep } from '../graph/AgentState';
import { CaptureGraph } from '../graph/CaptureGraph';
import { StructureNodeFactory } from '../graph/nodes/StructureNode';
import { TruthCheckNodeFactory } from '../graph/nodes/TruthCheckNode';
import { NoteDaoInterface } from '../models/NoteDaoInterface';
import type { CaptureSetOptions, DispatchOptions } from './dispatch/DispatchOptions';
import { isBatchCancelled, skippedItem, withRunContext } from './dispatch/BatchSupport';
import { CaptureBranch } from './dispatch/CaptureBranch';
import { PreparedBranch } from './dispatch/PreparedBranch';
import { GenerationEvaluator } from './dispatch/GenerationEvaluator';
import { GenerationBranch } from './dispatch/GenerationBranch';
import { IncrementalBranch } from './dispatch/IncrementalBranch';
import { NoteOutcomeMapper } from './dispatch/NoteOutcomeMapper';
import { DISPATCH_EVENT_START, DISPATCH_EVENT_TERMINAL, dispatchStartPayload, dispatchTerminalPayload } from './dispatch/RunEventSink';
import { DispatchGraph } from './dispatch/DispatchGraph';
import type { DispatchGraphContext, DispatchStageHandlers, DispatchStageResult } from './dispatch/DispatchGraph';
import type { GenerationCandidateEvaluation } from './dispatch/GenerationEvaluator';
import { copyRegeneratedUnit } from './dispatch/UnitSupport';

// DispatchOptions / CaptureSetOptions 已抽到 ./dispatch/DispatchOptions，这里重导出保持既有 import 路径。
export type { CaptureSetOptions, DispatchOptions } from './dispatch/DispatchOptions';

const log = new Logger('Dispatcher');

// DispatchOptions / CaptureSetOptions 已抽到 ./dispatch/DispatchOptions（分支模块共享契约）。

export class Dispatcher {
  // 与 StateGraph 老的 maxNodeRuns=128 保持一致：接线不改变各条路径的可用节点数。
  private static readonly DISPATCH_RUN_BUDGET: number = 128;

  // 预算与取消只走调用参数。三条路径（capture / generation / prepared）都从这里拿上下文，
  // 免得哪条忘了转发就把刹车和预算一起丢掉。
  private resolveRunContext(options: DispatchOptions): RunContext {
    return options.runContext ?? createRootRunContext(
      'dispatch-' + Date.now().toString(),
      Dispatcher.DISPATCH_RUN_BUDGET,
      0,
      options.cancellationToken ?? null,
    );
  }

  // D2 唯一最终公共入口: 跑 CaptureGraph, 失败返回结构化错误。
  async dispatch(req: DispatchRequest, options: DispatchOptions = {}): Promise<DispatchResult> {
    return await this.dispatchRequest(req, options);
  }


  // A4：invoke 阶段 = 现有分支执行 + 旧结果 → 终态映射（失败不抛出，交给终态）。
  private async invokeCommand(
    command: NoteCommand,
    request: DispatchRequest,
    effective: DispatchOptions,
  ): Promise<NoteOutcome> {
    try {
      const result: DispatchResult = await this.dispatchRequest(request, effective);
      return NoteOutcomeMapper.toOutcome(command, result);
    } catch (e) {
      const error: Error = e instanceof Error ? e : new Error(String(e));
      return NoteOutcomeMapper.fromThrown(command, error);
    }
  }

  // A4：run 事件写出是尽力而为的 —— sink 抛错只记日志，不影响命令结果。
  private static async emitRunEvent(
    options: DispatchOptions,
    runId: string,
    kind: string,
    payloadJson: string,
  ): Promise<void> {
    const sink = options.runEventSink;
    if (sink === undefined) {
      return;
    }
    try {
      await sink.emit(runId, { kind: kind, payloadJson: payloadJson });
    } catch (e) {
      log.warn('run event sink failed kind=' + kind + ' runId=' + runId
        + ' err=' + (e instanceof Error ? e.message : String(e)));
    }
  }

  /**
   * ADR-0019 / A3d：批量命令入口（一个 set 一个 run）。
   * 顺序执行 commands，共享同一个 RunContext；逐项仍是 NoteOutcome，单项失败不打断整批；
   * 取消后剩余项记 cancelled(committed=false)，不混进 failed。
   * 旧 `dispatchSet()` 保留为迁移适配器（UI 回执契约不变）。
   */
  async dispatchSetCommand(
    commands: NoteCommand[],
    options: DispatchOptions = {},
    onOutcome?: (index: number, outcome: NoteOutcome) => void,
  ): Promise<NoteBatchOutcome> {
    const startedAt: number = Date.now();
    const shared: RunContext = this.resolveRunContext(options);
    const items: NoteOutcome[] = [];
    let committed: number = 0;
    let failed: number = 0;
    let cancelled: number = 0;
    let needsInput: number = 0;
    let stop: boolean = false;
    for (let i = 0; i < commands.length; i++) {
      const command: NoteCommand = commands[i];
      if (stop || isBatchCancelled(options)) {
        const skipped: NoteOutcome = {
          kind: 'cancelled',
          operationId: command.operationId,
          route: 'D1',
          durationMs: 0,
          committed: false,
        };
        items.push(skipped);
        cancelled += 1;
        if (onOutcome !== undefined) { onOutcome(i, skipped); }
        continue;
      }
      const outcome: NoteOutcome = await this.dispatchCommand(command, withRunContext(options, shared));
      items.push(outcome);
      if (outcome.kind === 'committed') {
        committed += 1;
      } else if (outcome.kind === 'cancelled') {
        cancelled += 1;
        stop = true;
      } else if (outcome.kind === 'needsInput') {
        needsInput += 1;
      } else {
        failed += 1;
      }
      if (onOutcome !== undefined) { onOutcome(i, outcome); }
    }
    const result: NoteBatchOutcome = {
      total: commands.length,
      committed: committed,
      failed: failed,
      cancelled: cancelled,
      needsInput: needsInput,
      items: items,
      durationMs: Date.now() - startedAt,
    };
    return result;
  }

  async dispatchCommand(command: NoteCommand, options: DispatchOptions = {}): Promise<NoteOutcome> {
    const request: DispatchRequest = NoteOutcomeMapper.toRequest(command);
    const effective: DispatchOptions = NoteOutcomeMapper.toOptions(command, options);
    await Dispatcher.emitRunEvent(options, command.operationId, DISPATCH_EVENT_START, dispatchStartPayload(command));
    // A4 切片 3b：dispatchCommand 由主图编排（preflight 取消检查 → route → invoke 现有分支 → verify/hitl/publish 待接）。
    const self: Dispatcher = this;
    const handlers: DispatchStageHandlers = {
      preflight: async (context: DispatchGraphContext): Promise<DispatchStageResult> => {
        const token = options.cancellationToken;
        if (token !== undefined && token.isCancelled()) {
          return { outcome: NoteOutcomeMapper.fromThrown(command, new Error('CONVERSATION_CANCELLED')) };
        }
        return { next: 'route' };
      },
      route: async (_context: DispatchGraphContext): Promise<DispatchStageResult> => {
        return { next: 'invoke' };
      },
      invoke: async (_context: DispatchGraphContext): Promise<DispatchStageResult> => {
        return { outcome: await self.invokeCommand(command, request, effective) };
      },
      verify: async (_context: DispatchGraphContext): Promise<DispatchStageResult> => {
        // 切片 4 待接：结果校验（committed 信封完整性 / 降级标记）。当前透传。
        return { next: 'hitl' };
      },
      hitl: async (_context: DispatchGraphContext): Promise<DispatchStageResult> => {
        // 切片 4 待接：审批哈希校验（需 v18 持久化列）。当前透传。
        return { next: 'publish' };
      },
      publish: async (context: DispatchGraphContext): Promise<DispatchStageResult> => {
        const settled: NoteOutcome | undefined = context.outcome;
        if (settled === undefined) {
          return { errorCode: 'DISPATCH_GRAPH_NO_TERMINAL', errorMessage: 'publish received no outcome' };
        }
        await Dispatcher.emitRunEvent(options, command.operationId, DISPATCH_EVENT_TERMINAL, dispatchTerminalPayload(settled));
        return { outcome: settled };
      },
    };
    const outcome: NoteOutcome = await DispatchGraph.run(
      command,
      handlers,
      Date.now(),
      (code: string, message: string, retryable: boolean): NoteOutcome => {
        const failed: NoteOutcome = {
          kind: 'failed',
          operationId: command.operationId,
          route: 'D1',
          durationMs: 0,
          code: code,
          message: message,
          retryable: retryable,
        };
        return failed;
      },
    );
    return outcome;
  }

  // spec 036 阶段 1：一个 set 一个 run。
  // 顺序执行 req.items，全部共享同一个 RunContext（预算与取消）；单项失败不打断整批；
  // 取消后未开始/未完成的项单独记 cancelled，不混进 failed。
  // 切题（一图多题）与跨图合并留给阶段 2/3，这一层只把「多张图 = 一次整理」立住。
  async dispatchSet(req: CaptureSetRequest, options: CaptureSetOptions = {}): Promise<CaptureSetResult> {
    const startedAt: number = Date.now();
    const shared: RunContext = this.resolveRunContext(options);
    const items: CaptureSetItemResult[] = [];
    let done: number = 0;
    let failed: number = 0;
    let cancelled: number = 0;
    let stop: boolean = false;
    for (let i = 0; i < req.items.length; i++) {
      const payload: DispatchPayload = req.items[i];
      const itemStart: number = Date.now();
      if (stop || isBatchCancelled(options)) {
        cancelled += 1;
        const skipped: CaptureSetItemResult = skippedItem(i, payload);
        items.push(skipped);
        if (options.onItem !== undefined) { options.onItem(skipped); }
        continue;
      }
      try {
        const result: DispatchResult = await this.dispatch(
          { source: req.source, payload: payload },
          withRunContext(options, shared),
        );
        const item: CaptureSetItemResult = {
          index: i,
          kind: payload.kind,
          success: result.success,
          cancelled: false,
          durationMs: Date.now() - itemStart,
        };
        if (result.data !== undefined) {
          item.noteId = result.data.id;
          item.title = result.data.title;
        }
        if (result.classification !== undefined) { item.category = result.classification.type; }
        if (!result.success) {
          failed += 1;
          if (result.errorMessage !== undefined) { item.errorMessage = result.errorMessage; }
          if (result.errorCode !== undefined) { item.errorCode = result.errorCode; }
        } else {
          done += 1;
        }
        items.push(item);
        if (options.onItem !== undefined) { options.onItem(item); }
      } catch (error) {
        if (isBatchCancelled(options)) {
          cancelled += 1;
          const skipped: CaptureSetItemResult = skippedItem(i, payload);
          items.push(skipped);
          if (options.onItem !== undefined) { options.onItem(skipped); }
          stop = true;
          continue;
        }
        failed += 1;
        const failedItem: CaptureSetItemResult = {
          index: i,
          kind: payload.kind,
          success: false,
          errorMessage: (error as Error).message,
          cancelled: false,
          durationMs: Date.now() - itemStart,
        };
        items.push(failedItem);
        if (options.onItem !== undefined) { options.onItem(failedItem); }
      }
    }
    const totalMs: number = Date.now() - startedAt;
    log.info('dispatchSet done total=' + req.items.length.toString() + ' ok=' + done.toString()
      + ' failed=' + failed.toString() + ' cancelled=' + cancelled.toString()
      + ' totalMs=' + totalMs.toString());
    return {
      total: req.items.length,
      done: done,
      failed: failed,
      cancelled: cancelled,
      items: items,
      durationMs: totalMs,
    };
  }

  private async dispatchRequest(req: DispatchRequest, options: DispatchOptions): Promise<DispatchResult> {
    options.cancellationToken?.throwIfCancelled();
    const t0: number = Date.now();
    if (req.preparedCandidate !== undefined) {
      return await this.dispatchPreparedCandidate(req, req.preparedCandidate, options, t0);
    }
    if (req.generation !== undefined) {
      if (req.generation.mode === 'regenerate') {
        return await IncrementalBranch.dispatchIncrementalGeneration(req.generation, req, options, t0);
      }
      return await GenerationBranch.dispatchGeneration(req.generation, req, options, this.resolveRunContext(options), t0);
    }
    // capture 分支已抽出到 ./dispatch/CaptureBranch（2026-10-31 拆分 Dispatcher）。
    return await CaptureBranch.dispatchCapture(req, options, this.resolveRunContext(options), t0);
  }

  private async dispatchPreparedCandidate(
    req: DispatchRequest,
    prepared: PreparedCandidate,
    options: DispatchOptions,
    startedAt: number,
  ): Promise<DispatchResult> {
    // 分支已抽出到 ./dispatch/PreparedBranch（2026-10-31 拆分 Dispatcher，收敛文件体积）。
    return await PreparedBranch.dispatch(req, prepared, options, startedAt, this.resolveRunContext(options));
  }

}
