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
import type { DispatchPayload, CancellationToken } from 'common';
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
        return await this.dispatchIncrementalGeneration(req.generation, req, options, t0);
      }
      return await GenerationBranch.dispatchGeneration(req.generation, req, options, this.resolveRunContext(options), t0);
    }
    // capture 分支已抽出到 ./dispatch/CaptureBranch（2026-10-31 拆分 Dispatcher）。
    return await CaptureBranch.dispatchCapture(req, options, this.resolveRunContext(options), t0);
  }

  private async dispatchIncrementalGeneration(
    request: NoteGenerationRequest,
    req: DispatchRequest,
    options: DispatchOptions,
    startedAt: number,
  ): Promise<DispatchResult> {
    if (request.targetNoteId === undefined || request.targetNoteId.trim().length === 0) {
      return { success: false, route: 'D1', errorCode: 'NOTE_ID_REQUIRED', errorMessage: '增量重生成需要明确的 noteId', durationMs: Date.now() - startedAt };
    }
    if (request.baseVersion === undefined) {
      return { success: false, route: 'D1', errorCode: 'BASE_VERSION_REQUIRED', errorMessage: '增量重生成需要 baseVersion', durationMs: Date.now() - startedAt };
    }
    if (options.generationRepository === undefined || options.generationRepository.getRegenerationBase === undefined) {
      return { success: false, route: 'D1', errorCode: 'REGENERATION_REPOSITORY_REQUIRED', errorMessage: '增量重生成基础资料不可用', durationMs: Date.now() - startedAt };
    }
    GenerationBranch.emitGenerationProgress(options, {
      phase: 'prepare',
      state: 'running',
      activity: 'collect_sources',
    });
    const base: IncrementalBase | undefined = await options.generationRepository.getRegenerationBase(request.targetNoteId);
    if (base === undefined) {
      GenerationBranch.emitGenerationProgress(options, {
        phase: 'prepare',
        state: 'failed',
        activity: 'collect_sources',
      });
      return { success: false, route: 'D1', errorCode: 'NOTE_NOT_FOUND', errorMessage: '找不到指定 KnowledgeUnit', durationMs: Date.now() - startedAt };
    }
    if (base.baseVersion !== request.baseVersion) {
      return { success: false, route: 'D1', errorCode: 'VERSION_CONFLICT', errorMessage: '笔记版本已变化，请重新预览', durationMs: Date.now() - startedAt };
    }
    const parsed: IncrementalSection[] = parseIncrementalSections(base.unit.content);
    const locked: IncrementalSection[] = detectIncrementalLocks(parsed, base.manifest);
    const requirement: IncrementalRequirement = {
      instruction: request.instruction,
      targetSectionIds: request.requirement?.targetSectionIds ?? [],
      mustInclude: request.requirement?.mustInclude ?? [],
      preserveUserEdits: request.requirement?.preserveUserEdits !== false,
    };
    const planningManifest: IncrementalManifest = {
      noteId: base.manifest.noteId,
      baseVersion: base.baseVersion,
      sections: base.manifest.sections.slice(0),
      sourceIds: base.manifest.sourceIds.slice(0),
      createdAt: base.manifest.createdAt,
    };
    const plan: IncrementalPlan = planIncrementalChange(requirement, locked, planningManifest, request.sources.fragments);
    if (plan.targetSectionIds.length === 0) {
      GenerationBranch.emitGenerationProgress(options, {
        phase: 'prepare',
        state: 'failed',
        activity: 'collect_sources',
      });
      const result: NoteGenerationResult = this.incrementalResult(request, base.manifest, plan, [], 'needs-input');
      result.issues.push({ stage: 'plan', code: 'NO_UNLOCKED_TARGET', severity: 'hard', message: '没有可安全重生成的未锁定目标章节', repairable: false });
      return { success: false, route: 'D1', generation: result, errorCode: 'NO_UNLOCKED_TARGET', errorMessage: '没有可安全重生成的未锁定目标章节', durationMs: Date.now() - startedAt };
    }
    const model: KnowledgeModel = options.knowledgeModel ?? new KnowledgeModel(undefined, options.cancellationToken);
    const sourceBundle: SourceBundle = {
      fragments: base.sources.fragments.concat(request.sources.fragments),
    };
    const run: NoteGenerationRun = {
      id: request.runId,
      originSessionId: request.originSessionId,
      parentConversationRunId: request.parentConversationRunId,
      route: 'standard',
      status: 'running',
      instruction: request.instruction,
      sourceCount: sourceBundle.fragments.length,
      tokenBudget: standardBudget().maxTokens,
      sourceIds: sourceBundle.fragments.map((fragment): string => fragment.id),
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    await options.generationRepository.saveRun(run, sourceBundle);
    GenerationBranch.emitGenerationProgress(options, {
      phase: 'prepare',
      state: 'success',
      activity: 'collect_sources',
    });
    GenerationBranch.emitGenerationProgress(options, {
      phase: 'compose',
      state: 'running',
      activity: 'repair_draft',
    });
    const patchResponse: IncrementalPatchResponse = await model.repairIncrementalSections(
      request,
      plan,
      locked,
      sourceBundle.fragments,
    );
    GenerationBranch.emitGenerationProgress(options, {
      phase: 'compose',
      state: 'success',
      activity: 'repair_draft',
    });
    GenerationBranch.emitGenerationProgress(options, {
      phase: 'verify',
      state: 'running',
      activity: 'check_accuracy',
    });
    const merged: IncrementalMergeResult = mergeIncrementalPatches(locked, plan, patchResponse.patches);
    const manifest: IncrementalManifest = buildIncrementalManifest(
      base.unit.id,
      base.baseVersion + 1,
      merged.sections,
      base.manifest.sourceIds.concat(plan.newSourceIds),
    );
    if (!merged.ok) {
      GenerationBranch.emitGenerationProgress(options, {
        phase: 'verify',
        state: 'failed',
        activity: 'check_accuracy',
      });
      const result: NoteGenerationResult = this.incrementalResult(request, manifest, plan, merged.diff, 'needs-input');
      for (const issue of merged.issues) {
        result.issues.push({ stage: 'merge', code: issue, severity: 'hard', message: issue, repairable: false });
      }
      return { success: false, route: 'D1', generation: result, errorMessage: merged.issues.join(';'), durationMs: Date.now() - startedAt };
    }
    const nextContent: string = renderIncrementalSections(merged.sections);
    const candidate: KnowledgeUnit = copyRegeneratedUnit(base.unit, nextContent);
    const checkpointId: string = request.runId + ':incremental';
    const checkpoint: NoteGenerationCheckpoint = {
      id: checkpointId,
      runId: request.runId,
      iteration: 0,
      stage: 'truth_check',
      candidateHash: sourceFingerprint(JSON.stringify(candidate)),
      documentJson: JSON.stringify(candidate),
      accepted: true,
      issueCodes: [],
      createdAt: Date.now(),
    };
    await options.generationRepository.saveCheckpoint(checkpoint);
    const generation: NoteGenerationResult = this.incrementalResult(request, manifest, plan, merged.diff, 'ready-preview');
    generation.candidate = candidate;
    generation.bestCheckpointId = checkpointId;
    generation.sourceIds = base.manifest.sourceIds.concat(plan.newSourceIds);
    generation.incrementalInstruction = request.instruction;
    await options.generationRepository.saveRun({
      id: run.id,
      originSessionId: run.originSessionId,
      parentConversationRunId: run.parentConversationRunId,
      route: run.route,
      status: 'ready-preview',
      instruction: run.instruction,
      sourceCount: run.sourceCount,
      tokenBudget: run.tokenBudget,
      bestCheckpointId: checkpointId,
      stopReason: 'incremental_complete',
      issueCount: 0,
      sourceIds: run.sourceIds,
      createdAt: run.createdAt,
      updatedAt: Date.now(),
    }, sourceBundle);
    GenerationBranch.emitGenerationProgress(options, {
      phase: 'verify',
      state: 'success',
      activity: 'check_accuracy',
    });
    return { success: true, route: 'D1', data: candidate, generation: generation, durationMs: Date.now() - startedAt };
  }

  private incrementalResult(
    request: NoteGenerationRequest,
    manifest: IncrementalManifest,
    plan: IncrementalPlan,
    diff: IncrementalDiffItem[],
    status: 'ready-preview' | 'needs-input',
  ): NoteGenerationResult {
    return {
      runId: request.runId, route: 'standard', status: status, issues: [], questions: [],
      promptTokens: 0, completionTokens: 0, stopReason: 'incremental_complete',
      incrementalPlan: plan, incrementalManifest: manifest, incrementalDiff: diff,
      baseVersion: plan.baseVersion,
    };
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
