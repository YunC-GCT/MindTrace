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
      return await this.dispatchGeneration(req.generation, req, options, t0);
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
    this.emitGenerationProgress(options, {
      phase: 'prepare',
      state: 'running',
      activity: 'collect_sources',
    });
    const base: IncrementalBase | undefined = await options.generationRepository.getRegenerationBase(request.targetNoteId);
    if (base === undefined) {
      this.emitGenerationProgress(options, {
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
      this.emitGenerationProgress(options, {
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
    this.emitGenerationProgress(options, {
      phase: 'prepare',
      state: 'success',
      activity: 'collect_sources',
    });
    this.emitGenerationProgress(options, {
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
    this.emitGenerationProgress(options, {
      phase: 'compose',
      state: 'success',
      activity: 'repair_draft',
    });
    this.emitGenerationProgress(options, {
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
      this.emitGenerationProgress(options, {
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
    this.emitGenerationProgress(options, {
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

  private async dispatchGeneration(
    request: NoteGenerationRequest,
    req: DispatchRequest,
    options: DispatchOptions,
    startedAt: number,
  ): Promise<DispatchResult> {
    const bundle: SourceBundle = this.normalizeBundle(request);
    this.emitGenerationProgress(options, {
      phase: 'prepare',
      state: 'running',
      activity: 'collect_sources',
    });
    let route = request.route ?? selectGenerationRoute(bundle, request.instruction);
    // 2026-09-20 P0-7: deep 源预算超限时自动降级 standard — 原先 preflight 直接
    // needs-input 终止 (dbpull5 实测 3 连 missing_facts, 用户反复重试均 25ms 拒绝);
    // standard 单次调用可承载长源, 降级优于中断问询
    if (route === 'deep') {
      const deepSourceLimit: number = deepBudget().maxSourceChars ?? 0;
      if (deepSourceLimit > 0) {
        let sourceChars: number = 0;
        for (const fragment of bundle.fragments) {
          sourceChars += fragment.text.length;
        }
        if (sourceChars > deepSourceLimit) {
          log.info('generation run=' + request.runId + ' downgrade deep->standard: sourceChars='
            + sourceChars.toString() + ' > ' + deepSourceLimit.toString());
          route = 'standard';
        }
      }
    }
    const budget = route === 'deep' ? deepBudget() : route === 'standard' ? standardBudget() : lightBudget();
    const requirement = request.requirement ?? defaultRequirement(request.instruction);
    const run: NoteGenerationRun = {
      id: request.runId,
      originSessionId: request.originSessionId,
      parentConversationRunId: request.parentConversationRunId,
      route: route,
      status: 'running',
      instruction: request.instruction,
      sourceCount: bundle.fragments.length,
      tokenBudget: budget.maxTokens,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      sourceIds: bundle.fragments.map((fragment): string => fragment.id),
      pendingSourceIds: request.pendingSourceIds ?? [],
      sourceSummary: this.sourceSummary(bundle),
    };
    if (options.generationRepository !== undefined) {
      await options.generationRepository.saveRun(run, bundle);
    }
    const missing: NoteGenerationIssue[] = [];
    let processBlocked: boolean = false;
    const sourceGateIssues: NoteGenerationIssue[] = validateSourceBundle(bundle);
    for (const issue of sourceGateIssues) {
      missing.push(issue);
      processBlocked = true;
    }
    if (bundle.fragments.length === 0) {
      missing.push({ stage: 'source', code: 'MISSING_SOURCE', severity: 'hard', message: '请提供一段对话或一份 OCR 材料', repairable: false });
    }
    if (request.instruction.trim().length === 0) {
      missing.push({ stage: 'requirement', code: 'MISSING_INSTRUCTION', severity: 'hard', message: '请说明希望生成的笔记内容', repairable: false });
    }
    if (request.instruction.indexOf('缺少') >= 0 || request.instruction.indexOf('未知') >= 0) {
      missing.push({ stage: 'requirement', code: 'MISSING_USER_FACT', severity: 'hard', message: '请补充题目中的关键已知条件', repairable: false });
    }
    if (route === 'deep' && budget.maxSourceChars !== undefined) {
      let sourceChars: number = 0;
      for (const fragment of bundle.fragments) {
        sourceChars += fragment.text.length;
      }
      if (sourceChars > budget.maxSourceChars) {
        missing.push({
          stage: 'source',
          code: 'SOURCE_BUDGET_EXCEEDED',
          severity: 'hard',
          message: '材料总量超过 deep route 来源预算，请缩小范围: ' + bundle.fragments.map((item): string => item.id).join(','),
          repairable: false,
        });
      }
    }
    if (route === 'deep' && missing.length === 0) {
      const segments = segmentSourceBundle(bundle);
      const plannedOutline = buildDeepOutline(segments, requirement);
      const outlineIssues = validateDeepOutline(plannedOutline, segments, bundle, requirement);
      for (const issue of outlineIssues) {
        missing.push(issue);
        processBlocked = true;
      }
    }
    if (missing.length > 0) {
      this.emitGenerationProgress(options, {
        phase: 'prepare',
        state: 'failed',
        activity: 'collect_sources',
      });
      const questions: string[] = [];
      if (!processBlocked) {
        for (const issue of missing) {
          questions.push(issue.message);
        }
      }
      const preflightStatus = processBlocked ? 'failed' : 'needs-input';
      const preflightStopReason: string = processBlocked ? 'process_gate' : 'missing_facts';
      const generation: NoteGenerationResult = {
        runId: request.runId,
        route: route,
        status: preflightStatus,
        issues: missing,
        questions: questions,
        stopReason: preflightStopReason,
        promptTokens: 0,
        completionTokens: 0,
      };
      if (options.generationRepository !== undefined) {
        const completedRun: NoteGenerationRun = {
          id: run.id,
          originSessionId: run.originSessionId,
          parentConversationRunId: run.parentConversationRunId,
          route: run.route,
          status: preflightStatus,
          instruction: run.instruction,
          sourceCount: run.sourceCount,
          tokenBudget: run.tokenBudget,
          stopReason: preflightStopReason,
          issueCount: missing.length,
          createdAt: run.createdAt,
          updatedAt: Date.now(),
          sourceIds: run.sourceIds,
          pendingSourceIds: run.pendingSourceIds,
          sourceSummary: run.sourceSummary,
        };
        await options.generationRepository.saveRun(completedRun, bundle);
      }
      log.info('generation run=' + request.runId + ' route=' + route + ' sources=' + bundle.fragments.length.toString()
        + ' issues=' + missing.length.toString() + ' tokens=0');
      return { success: false, route: 'D1', generation: generation, errorMessage: questions.join('; '), durationMs: Date.now() - startedAt };
    }

    const generationPayload: DispatchRequest = {
      source: req.source,
      payload: { kind: 'text', text: GenerationEvaluator.bundleText(bundle) },
    };
    this.emitGenerationProgress(options, {
      phase: 'prepare',
      state: 'success',
      activity: 'collect_sources',
    });
    if (route === 'standard') {
      this.emitGenerationProgress(options, {
        phase: 'compose',
        state: 'running',
        activity: 'write_draft',
      });
      return await this.dispatchStandardGeneration(
        request,
        generationPayload,
        options,
        startedAt,
        run,
        bundle,
        budget,
        requirement,
      );
    }
    if (route === 'deep') {
      this.emitGenerationProgress(options, {
        phase: 'compose',
        state: 'running',
        activity: 'plan_structure',
      });
      return await this.dispatchDeepGeneration(
        request,
        bundle,
        options,
        startedAt,
        run,
        budget,
        requirement,
      );
    }
    const initial: AgentState = {
      captureText: GenerationEvaluator.bundleText(bundle),
      source: 'note_generation',
      payload: generationPayload.payload,
      generationRequest: {
        runId: request.runId,
        instruction: request.instruction,
        mode: request.mode,
        sources: bundle,
        requirement: requirement,
        targetNoteId: request.targetNoteId,
        baseVersion: request.baseVersion,
        pendingSourceIds: request.pendingSourceIds,
        route: route,
      },
      currentStep: 'START',
      persist: false,
      analysisOnly: false,
    };
    this.emitGenerationProgress(options, {
      phase: 'compose',
      state: 'running',
      activity: 'write_draft',
    });
    const graph: CaptureGraph = this.buildGenerationGraph(options.knowledgeModel, options.cancellationToken);
    const finalState: AgentState = await graph.run(initial, this.resolveRunContext(options));
    this.emitGenerationProgress(options, {
      phase: 'compose',
      state: finalState.error === undefined ? 'success' : 'failed',
      activity: 'write_draft',
    });
    const errors: NoteGenerationIssue[] = [];
    if (finalState.error !== undefined) {
      errors.push({ stage: finalState.error.step, code: finalState.error.kind, severity: 'hard', message: finalState.error.message, repairable: false });
    }
    const candidate: KnowledgeUnit | undefined = finalState.error === undefined ? finalState.knowledgeUnit : undefined;
    const draft = finalState.draft;
    const standardResult = finalState.standardResult;
    if (standardResult !== undefined) {
      for (const issue of standardResult.verification.issues) {
        if (!errors.some((existing: NoteGenerationIssue): boolean => existing.code === issue.code && existing.sectionId === issue.sectionId && existing.sourceId === issue.sourceId)) {
          errors.push(issue);
        }
      }
    }
    const checkpointId: string = request.runId + ':0';
    const candidateHash: string = candidate === undefined ? '' : sourceFingerprint(JSON.stringify(candidate));
    if (draft !== undefined && options.generationRepository !== undefined) {
      const checkpoint: NoteGenerationCheckpoint = {
        id: checkpointId,
        runId: request.runId,
        iteration: 0,
        stage: 'truth_check',
        candidateHash: candidateHash,
        documentJson: candidate === undefined ? JSON.stringify(draft) : JSON.stringify(candidate),
        accepted: candidate !== undefined && finalState.truthCheck?.passed === true,
        issueCodes: errors.map((issue: NoteGenerationIssue): string => issue.code),
        outlineJson: standardResult === undefined ? undefined : JSON.stringify(standardResult.outline),
        evidenceJson: standardResult === undefined ? undefined : JSON.stringify(standardResult.evidence),
        verificationJson: standardResult === undefined ? undefined : JSON.stringify(standardResult.verification),
        createdAt: Date.now(),
      };
      await options.generationRepository.saveCheckpoint(checkpoint);
    }
    const status = candidate !== undefined ? 'ready-preview' : 'failed';
    const referencedPendingSourceIds: string[] = this.referencedPendingSourceIds(
      draft,
      request.pendingSourceIds ?? [],
    );
    const result: NoteGenerationResult = {
      runId: request.runId,
      route: route,
      status: status,
      candidate: candidate,
      draft: draft,
      bestCheckpointId: candidate !== undefined && finalState.truthCheck?.passed === true ? checkpointId : undefined,
      issues: errors,
      questions: [],
      stopReason: candidate !== undefined ? 'light_complete' : 'workflow_error',
      promptTokens: 0,
      completionTokens: 0,
      sourceIds: run.sourceIds,
      outline: standardResult?.outline,
      evidence: standardResult?.evidence,
      verification: standardResult?.verification,
    };
    if (options.generationRepository !== undefined) {
      const completedRun: NoteGenerationRun = {
        id: run.id,
        originSessionId: run.originSessionId,
        parentConversationRunId: run.parentConversationRunId,
        route: run.route,
        status: status,
        instruction: run.instruction,
        sourceCount: run.sourceCount,
        tokenBudget: run.tokenBudget,
        bestCheckpointId: result.bestCheckpointId,
        stopReason: result.stopReason,
        issueCount: errors.length,
        createdAt: run.createdAt,
        updatedAt: Date.now(),
        sourceIds: run.sourceIds,
        pendingSourceIds: referencedPendingSourceIds,
        sourceSummary: run.sourceSummary,
      };
      await options.generationRepository.saveRun(completedRun, bundle);
    }
    log.info('generation run=' + request.runId + ' route=' + route + ' sources=' + bundle.fragments.length.toString()
      + ' issues=' + errors.length.toString() + ' tokens=0');
    return {
      success: candidate !== undefined,
      route: 'D1',
      data: candidate,
      generation: result,
      recognizedText: options.includeRawText === true ? finalState.captureText : undefined,
      errorMessage: candidate === undefined ? (errors.length > 0 ? errors[0].message : 'generation failed') : undefined,
      durationMs: Date.now() - startedAt,
    };
  }

  private emitGenerationProgress(options: DispatchOptions, event: NoteGenerationProgressEvent): void {
    if (options.progressSink !== undefined) {
      options.progressSink(event);
    }
  }

  private async dispatchStandardGeneration(
    request: NoteGenerationRequest,
    req: DispatchRequest,
    options: DispatchOptions,
    startedAt: number,
    run: NoteGenerationRun,
    bundle: SourceBundle,
    budget: NoteGenerationBudget,
    requirement: NoteGenerationRequirement,
  ): Promise<DispatchResult> {
    const model: KnowledgeModel = options.knowledgeModel ?? new KnowledgeModel(undefined, options.cancellationToken);
    const budgetedRequest: NoteGenerationRequest = GenerationEvaluator.withTokenBudget(
      request,
      budget.maxTokens,
      bundle,
      requirement,
    );
    let current: NoteGenerationStandardResult;
    try {
      current = await model.structureStandardDraft(budgetedRequest, options.progressSink);
    } catch (e) {
      return await GenerationEvaluator.finishStandardGeneration(request, run, bundle, options, startedAt, [], undefined, {
        round: 0,
        stopReason: 'initial_generation_failed',
        rollback: false,
        tokenBudget: budget.maxTokens,
        estimatedTokenCost: 0,
      }, 'initial generation failed: ' + (e as Error).message);
    }

    const finalEvaluation: GenerationCandidateEvaluation = await GenerationEvaluator.evaluateStandardCandidate(
      current,
      bundle,
      requirement,
      model,
    );
    const checkpointId: string = request.runId + ':0';
    const bestCheckpointId: string = checkpointId;
    const checkpoint: NoteGenerationCheckpoint = {
      id: checkpointId,
      runId: request.runId,
      iteration: 0,
      stage: 'truth_check',
      candidateHash: sourceFingerprint(JSON.stringify(finalEvaluation.candidate)),
      documentJson: JSON.stringify(finalEvaluation.candidate),
      accepted: finalEvaluation.hardIssueCount === 0,
      issueCodes: finalEvaluation.issues.map((issue: NoteGenerationIssue): string => issue.code),
      outlineJson: JSON.stringify(finalEvaluation.result.outline),
      evidenceJson: JSON.stringify(finalEvaluation.result.evidence),
      verificationJson: JSON.stringify(finalEvaluation.result.verification),
      issueFingerprint: finalEvaluation.issueFingerprint,
      coverage: finalEvaluation.coverage,
      tokenCost: finalEvaluation.tokenCost,
      changeScope: finalEvaluation.changeScope,
      decision: 'initial',
      createdAt: Date.now(),
    };
    if (options.generationRepository !== undefined) {
      await options.generationRepository.saveCheckpoint(checkpoint);
    }
    let stopReason: string = 'standard_complete';
    if (finalEvaluation.hardIssueCount === 0) {
      this.emitGenerationProgress(options, {
        phase: 'verify', state: 'success', activity: 'check_accuracy',
      });
    } else {
      stopReason = GenerationEvaluator.readOnlyVerificationStopReason(finalEvaluation.issues);
    }
    const round: number = 0;
    const rollback: boolean = false;
    const progress: NoteGenerationProgress = {
      round: round,
      stopReason: stopReason,
      rollback: rollback,
      issueCount: finalEvaluation?.issues.length ?? 0,
      issueFingerprint: finalEvaluation?.issueFingerprint,
      tokenBudget: budget.maxTokens,
      estimatedTokenCost: finalEvaluation.tokenCost,
    };
    if (finalEvaluation.hardIssueCount > 0) {
      return await GenerationEvaluator.finishStandardGeneration(
        request,
        GenerationEvaluator.completedRun(run, bestCheckpointId, stopReason),
        bundle,
        options,
        startedAt,
        finalEvaluation.issues,
        undefined,
        progress,
        GenerationEvaluator.generationFailureMessage('standard', finalEvaluation.issues, progress),
        finalEvaluation.result,
      );
    }
    const finalCandidate: KnowledgeUnit = finalEvaluation.candidate;
    return await GenerationEvaluator.finishStandardGeneration(
      request,
      GenerationEvaluator.completedRun(run, bestCheckpointId, stopReason),
      bundle,
      options,
      startedAt,
      finalEvaluation.issues,
      finalCandidate,
      progress,
      undefined,
      finalEvaluation.result,
    );
  }

  private async dispatchDeepGeneration(
    request: NoteGenerationRequest,
    bundle: SourceBundle,
    options: DispatchOptions,
    startedAt: number,
    run: NoteGenerationRun,
    budget: NoteGenerationBudget,
    requirement: NoteGenerationRequirement,
  ): Promise<DispatchResult> {
    const model: KnowledgeModel = options.knowledgeModel ?? new KnowledgeModel(undefined, options.cancellationToken);
    const budgetedRequest: NoteGenerationRequest = GenerationEvaluator.withTokenBudget(
      request,
      budget.maxTokens,
      bundle,
      requirement,
    );
    let current: NoteGenerationDeepResult;
    try {
      current = await model.structureDeepDraft(budgetedRequest, options.progressSink);
    } catch (e) {
      return await GenerationEvaluator.finishStandardGeneration(request, run, bundle, options, startedAt, [], undefined, {
        round: 0,
        stopReason: 'initial_deep_generation_failed',
        rollback: false,
        tokenBudget: budget.maxTokens,
        estimatedTokenCost: 0,
      }, 'initial deep generation failed: ' + (e as Error).message, undefined, 'deep');
    }
    const finalEvaluation: GenerationCandidateEvaluation = await GenerationEvaluator.evaluateDeepCandidate(
      current,
      bundle,
      requirement,
      model,
    );
    const checkpointId: string = request.runId + ':0';
    const bestCheckpointId: string = checkpointId;
    const checkpoint: NoteGenerationCheckpoint = {
      id: checkpointId,
      runId: request.runId,
      iteration: 0,
      stage: 'truth_check',
      candidateHash: sourceFingerprint(JSON.stringify(finalEvaluation.candidate)),
      documentJson: JSON.stringify(finalEvaluation.candidate),
      accepted: finalEvaluation.hardIssueCount === 0,
      issueCodes: finalEvaluation.issues.map((issue: NoteGenerationIssue): string => issue.code),
      outlineJson: JSON.stringify(finalEvaluation.result.outline),
      evidenceJson: JSON.stringify(finalEvaluation.result.evidence),
      verificationJson: JSON.stringify(finalEvaluation.result.verification),
      issueFingerprint: finalEvaluation.issueFingerprint,
      coverage: finalEvaluation.coverage,
      tokenCost: finalEvaluation.tokenCost,
      changeScope: finalEvaluation.changeScope,
      decision: 'initial',
      createdAt: Date.now(),
    };
    if (options.generationRepository !== undefined) {
      await options.generationRepository.saveCheckpoint(checkpoint);
    }
    let stopReason: string = 'deep_complete';
    if (finalEvaluation.hardIssueCount === 0) {
      this.emitGenerationProgress(options, {
        phase: 'verify', state: 'success', activity: 'check_accuracy',
      });
    } else {
      stopReason = GenerationEvaluator.readOnlyVerificationStopReason(finalEvaluation.issues);
    }
    const round: number = 0;
    const rollback: boolean = false;
    const progress: NoteGenerationProgress = {
      round: round,
      stopReason: stopReason,
      rollback: rollback,
      issueCount: finalEvaluation.issues.length,
      issueFingerprint: finalEvaluation.issueFingerprint,
      tokenBudget: budget.maxTokens,
      estimatedTokenCost: finalEvaluation.tokenCost,
    };
    const deepResult: NoteGenerationDeepResult | undefined = finalEvaluation.deepResult;
    if (finalEvaluation.hardIssueCount > 0) {
      return await GenerationEvaluator.finishStandardGeneration(
        request,
        GenerationEvaluator.completedRun(run, bestCheckpointId, stopReason),
        bundle,
        options,
        startedAt,
        finalEvaluation.issues,
        undefined,
        progress,
        GenerationEvaluator.generationFailureMessage('deep', finalEvaluation.issues, progress),
        deepResult,
        'deep',
      );
    }
    return await GenerationEvaluator.finishStandardGeneration(
      request,
      GenerationEvaluator.completedRun(run, bestCheckpointId, stopReason),
      bundle,
      options,
      startedAt,
      finalEvaluation.issues,
      finalEvaluation.candidate,
      progress,
      undefined,
      deepResult,
      'deep',
    );
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

  private buildGenerationGraph(model?: KnowledgeModel, cancellationToken?: CancellationToken): CaptureGraph {
    const graph: CaptureGraph = new CaptureGraph();
    const structure: KnowledgeModel = model ?? new KnowledgeModel(undefined, cancellationToken);
    const truth: TruthCheckService = new TruthCheckService();
    graph.addNode('structure', StructureNodeFactory.create(structure));
    graph.addNode('truth_check', TruthCheckNodeFactory.create(truth));
    graph.addEdge('START', 'structure');
    graph.addEdge('structure', 'truth_check');
    graph.addConditionalEdge('truth_check', (_input: AgentState): CaptureStep => 'END');
    return graph;
  }

  private normalizeBundle(request: NoteGenerationRequest): SourceBundle {
    const fragments = request.sources.fragments.slice(0);
    fragments.sort((left, right): number => left.sequence - right.sequence);
    const normalized: SourceBundle = { fragments: [] };
    let sequence: number = 0;
    for (const fragment of fragments) {
      const id: string = fragment.id.length > 0 ? fragment.id : buildSourceId(fragment.kind, fragment.originId, sequence);
      normalized.fragments.push({
        id: id,
        kind: fragment.kind,
        originId: fragment.originId,
        sequence: sequence,
        // Source text is the authority at the Dispatcher boundary. Never trust a
        // caller-supplied fingerprint that may actually be a record or OCR ID.
        fingerprint: sourceFingerprint(fragment.text),
        text: fragment.text,
        provenanceIds: this.normalizeProvenanceIds(fragment),
      });
      sequence += 1;
    }
    return normalized;
  }

  private normalizeProvenanceIds(fragment: SourceFragment): string[] {
    const result: string[] = [];
    const candidates: string[] = fragment.provenanceIds ?? [fragment.id];
    for (const value of candidates) {
      const normalized: string = value.trim();
      if (normalized.length > 0 && !result.includes(normalized)) {
        result.push(normalized);
      }
    }
    if (result.length === 0 && fragment.id.trim().length > 0) {
      result.push(fragment.id.trim());
    }
    return result;
  }

  private sourceSummary(bundle: SourceBundle): string {
    const kinds: string[] = [];
    for (const fragment of bundle.fragments) {
      if (!kinds.includes(fragment.kind)) {
        kinds.push(fragment.kind);
      }
    }
    return 'count=' + bundle.fragments.length.toString() + ';kinds=' + kinds.join(',');
  }

  private referencedPendingSourceIds(draft: NoteDraftDocument | undefined, pendingSourceIds: string[]): string[] {
    const referenced: string[] = [];
    if (draft === undefined) {
      return referenced;
    }
    for (const section of draft.sections) {
      for (const sourceId of section.sourceIds) {
        if (pendingSourceIds.includes(sourceId) && !referenced.includes(sourceId)) {
          referenced.push(sourceId);
        }
      }
    }
    return referenced;
  }

}
