/**
 * GenerationBranch.ets — 生成分支（从 CommandExecutor.ets 抽出）
 *
 * 路径: agents/src/main/ets/core/dispatch/GenerationBranch.ets
 * 职责: light / standard / deep 三条生成路径的编排：路由选择、预算包装、候选评估循环、
 *       检查点与终态组装（评估细节在 GenerationEvaluator）。
 * 依赖: GenerationEvaluator（评估/终态）、common 的生成模型与增量类型。
 *
 * 边界:
 *   - 不负责幂等提交（preparedCandidate 走 PreparedBranch）与增量重生成（IncrementalBranch）。
 *   - run 上下文由 CommandExecutor 传入（预算与取消是运行时属性）。
 *   - 行为等价判据：#239 generation golden 快照。
 */
import {
  Logger,
  RunContext,
  createRootRunContext,
  KnowledgeUnit,
  BranchRequest,
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
import { AgentState } from '../../graph/AgentState';
import type { CaptureStep } from '../../graph/AgentState';
import { CaptureGraph } from '../../graph/CaptureGraph';
import { KnowledgeModel } from '../../agents/KnowledgeModel';
import { TruthCheckService } from '../../agents/TruthCheckService';
import { StructureNodeFactory } from '../../graph/nodes/StructureNode';
import { TruthCheckNodeFactory } from '../../graph/nodes/TruthCheckNode';
import { GenerationEvaluator } from './GenerationEvaluator';
import type { GenerationCandidateEvaluation } from './GenerationEvaluator';
import type { DispatchOptions } from './DispatchOptions';
import type { NoteOutcome } from 'common';

const generationLog = new Logger('GenerationBranch');

export class GenerationBranch {
  static async dispatchGeneration(
    request: NoteGenerationRequest,
    req: BranchRequest,
    options: DispatchOptions,
    runContext: RunContext,
    startedAt: number,
  ): Promise<NoteOutcome> {
    const operationId: string = req.operationId !== undefined ? req.operationId : request.runId;
    const failedOutcome = (message: string, code: string, generation?: NoteGenerationResult): NoteOutcome => {
      const outcome: NoteOutcome = {
        kind: 'failed', operationId: operationId, route: 'D1', durationMs: Date.now() - startedAt,
        code: code, message: message,
      };
      if (generation !== undefined) { outcome.generation = generation; }
      return outcome;
    };
    const bundle: SourceBundle = GenerationBranch.normalizeBundle(request);
    GenerationBranch.emitGenerationProgress(options, {
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
          generationLog.info('generation run=' + request.runId + ' downgrade deep->standard: sourceChars='
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
      sourceSummary: GenerationBranch.sourceSummary(bundle),
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
      GenerationBranch.emitGenerationProgress(options, {
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
      generationLog.info('generation run=' + request.runId + ' route=' + route + ' sources=' + bundle.fragments.length.toString()
        + ' issues=' + missing.length.toString() + ' tokens=0');
      const needs: NoteOutcome = {
        kind: 'needsInput', operationId: operationId, route: 'D1', durationMs: Date.now() - startedAt,
        reason: questions.join('; '), issues: missing, generation: generation,
      };
      return needs;
    }

    const generationPayload: BranchRequest = {
      source: req.source,
      payload: { kind: 'text', text: GenerationEvaluator.bundleText(bundle) },
    };
    GenerationBranch.emitGenerationProgress(options, {
      phase: 'prepare',
      state: 'success',
      activity: 'collect_sources',
    });
    if (route === 'standard') {
      GenerationBranch.emitGenerationProgress(options, {
        phase: 'compose',
        state: 'running',
        activity: 'write_draft',
      });
      return await GenerationBranch.dispatchStandardGeneration(
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
      GenerationBranch.emitGenerationProgress(options, {
        phase: 'compose',
        state: 'running',
        activity: 'plan_structure',
      });
      return await GenerationBranch.dispatchDeepGeneration(
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
    GenerationBranch.emitGenerationProgress(options, {
      phase: 'compose',
      state: 'running',
      activity: 'write_draft',
    });
    const graph: CaptureGraph = GenerationBranch.buildGenerationGraph(options.knowledgeModel, options.cancellationToken);
    const finalState: AgentState = await graph.run(initial, runContext);
    GenerationBranch.emitGenerationProgress(options, {
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
    const referencedPendingSourceIds: string[] = GenerationBranch.referencedPendingSourceIds(
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
    generationLog.info('generation run=' + request.runId + ' route=' + route + ' sources=' + bundle.fragments.length.toString()
      + ' issues=' + errors.length.toString() + ' tokens=0');
    if (candidate === undefined) {
      const reason: string = errors.length > 0 ? errors[0].message : 'generation failed';
      const needs: NoteOutcome = {
        kind: 'needsInput', operationId: operationId, route: 'D1', durationMs: Date.now() - startedAt,
        reason: reason, issues: errors, generation: result,
      };
      return needs;
    }
    const preview: NoteOutcome = {
      kind: 'readyPreview', operationId: operationId, route: 'D1', durationMs: Date.now() - startedAt,
      runId: request.runId,
      checkpointId: result.bestCheckpointId !== undefined ? result.bestCheckpointId : '',
      draft: candidate, generation: result,
      recognizedText: options.includeRawText === true ? finalState.captureText : undefined,
    };
    return preview;
  }

  static emitGenerationProgress(options: DispatchOptions, event: NoteGenerationProgressEvent): void {
    if (options.progressSink !== undefined) {
      options.progressSink(event);
    }
  }

  static async dispatchStandardGeneration(
    request: NoteGenerationRequest,
    req: BranchRequest,
    options: DispatchOptions,
    startedAt: number,
    run: NoteGenerationRun,
    bundle: SourceBundle,
    budget: NoteGenerationBudget,
    requirement: NoteGenerationRequirement,
  ): Promise<NoteOutcome> {
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
      GenerationBranch.emitGenerationProgress(options, {
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

  static async dispatchDeepGeneration(
    request: NoteGenerationRequest,
    bundle: SourceBundle,
    options: DispatchOptions,
    startedAt: number,
    run: NoteGenerationRun,
    budget: NoteGenerationBudget,
    requirement: NoteGenerationRequirement,
  ): Promise<NoteOutcome> {
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
      GenerationBranch.emitGenerationProgress(options, {
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

  static buildGenerationGraph(model?: KnowledgeModel, cancellationToken?: CancellationToken): CaptureGraph {
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

  static normalizeBundle(request: NoteGenerationRequest): SourceBundle {
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
        // Source text is the authority at the CommandExecutor boundary. Never trust a
        // caller-supplied fingerprint that may actually be a record or OCR ID.
        fingerprint: sourceFingerprint(fragment.text),
        text: fragment.text,
        provenanceIds: GenerationBranch.normalizeProvenanceIds(fragment),
      });
      sequence += 1;
    }
    return normalized;
  }

  static normalizeProvenanceIds(fragment: SourceFragment): string[] {
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

  static sourceSummary(bundle: SourceBundle): string {
    const kinds: string[] = [];
    for (const fragment of bundle.fragments) {
      if (!kinds.includes(fragment.kind)) {
        kinds.push(fragment.kind);
      }
    }
    return 'count=' + bundle.fragments.length.toString() + ';kinds=' + kinds.join(',');
  }

  static referencedPendingSourceIds(draft: NoteDraftDocument | undefined, pendingSourceIds: string[]): string[] {
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
