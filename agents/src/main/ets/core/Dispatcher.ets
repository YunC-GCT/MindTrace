// MindTrace - Dispatcher (主 Agent 调度中枢) · D2 CaptureGraph host
// 2026-09-05 · D2 Ticket #6: 唯一最终公共入口 dispatch()
import { TypeClassifier } from '../agents/TypeClassifier';
import { KnowledgeModel } from '../agents/KnowledgeModel';
import { TruthCheckService } from '../agents/TruthCheckService';
import {
  Logger,
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
  NoteGenerationCheckpointDecision,
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
  NoteGenerationCommitResult,
  NoteDraftDocument,
  NoteDraftSection,
  NoteGenerationStandardResult,
  NoteGenerationDeepResult,
  NoteGenerationRoute,
  NoteGenerationProgress,
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
} from 'common';
import type { DispatchPayload } from 'common';
import { AgentState, CaptureGraphError, CaptureNodeResult, CaptureStep, copyAgentState } from '../graph/AgentState';
import { CaptureGraph } from '../graph/CaptureGraph';
import { OcrNodeFactory } from '../graph/nodes/OcrNode';
import { ClassifyNodeFactory } from '../graph/nodes/ClassifyNode';
import { StructureNodeFactory } from '../graph/nodes/StructureNode';
import { TruthCheckNodeFactory } from '../graph/nodes/TruthCheckNode';
import { PersistNodeFactory } from '../graph/nodes/PersistNode';
import { NoteDaoInterface } from '../models/NoteDaoInterface';

const log = new Logger('Dispatcher');

export interface DispatchOptions {
  persist?: boolean;
  includeRawText?: boolean;
  analysisOnly?: boolean;
  dao?: NoteDaoInterface;
  generationRepository?: NoteGenerationRepository;
  knowledgeModel?: KnowledgeModel;
}

interface GenerationCandidateEvaluation {
  result: NoteGenerationStandardResult;
  candidate: KnowledgeUnit;
  issues: NoteGenerationIssue[];
  hardIssueCount: number;
  contradictionCount: number;
  coverage: NoteGenerationCoverage;
  tokenCost: number;
  changeScope: number;
  issueFingerprint: string;
  deepResult?: NoteGenerationDeepResult;
}

export class Dispatcher {
  private static sourceFromPayload(payload: DispatchPayload): string {
    if (payload.kind === 'image') { return 'camera_capture'; }
    if (payload.kind === 'text') { return 'manual'; }
    return 'file_import';
  }

  // D2 唯一最终公共入口: 跑 CaptureGraph, 失败返回结构化错误。
  async dispatch(req: DispatchRequest, options: DispatchOptions = {}): Promise<DispatchResult> {
    return await this.dispatchRequest(req, options);
  }

  private async dispatchRequest(req: DispatchRequest, options: DispatchOptions): Promise<DispatchResult> {
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
    log.info('dispatch enter, source=' + req.source + ', payload.kind=' + req.payload.kind);
    const initial: AgentState = {
      captureText: this.seedText(req),
      source: Dispatcher.sourceFromPayload(req.payload),
      payload: req.payload,
      currentStep: 'START',
      persist: options.persist !== false,
      analysisOnly: options.analysisOnly === true,
    };
    const graph: CaptureGraph = this.buildGraph(options);
    const finalState: AgentState = await graph.run(initial);
    const error: CaptureGraphError | undefined = finalState.error;
    if (error !== undefined) {
      log.error('capture graph failed: ' + error.kind + ' step=' + error.step + ' msg=' + error.message);
      const failed: DispatchResult = {
        success: false,
        route: 'D1',
        errorMessage: error.message,
        durationMs: Date.now() - t0,
      };
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
        durationMs: Date.now() - t0,
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
        durationMs: Date.now() - t0,
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
      durationMs: Date.now() - t0,
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
    const base: IncrementalBase | undefined = await options.generationRepository.getRegenerationBase(request.targetNoteId);
    if (base === undefined) {
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
      const result: NoteGenerationResult = this.incrementalResult(request, base.manifest, plan, [], 'needs-input');
      result.issues.push({ stage: 'plan', code: 'NO_UNLOCKED_TARGET', severity: 'hard', message: '没有可安全重生成的未锁定目标章节', repairable: false });
      return { success: false, route: 'D1', generation: result, errorCode: 'NO_UNLOCKED_TARGET', errorMessage: '没有可安全重生成的未锁定目标章节', durationMs: Date.now() - startedAt };
    }
    const model: KnowledgeModel = options.knowledgeModel ?? new KnowledgeModel();
    const sourceBundle: SourceBundle = {
      fragments: base.sources.fragments.concat(request.sources.fragments),
    };
    const run: NoteGenerationRun = {
      id: request.runId,
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
    const patchResponse: IncrementalPatchResponse = await model.repairIncrementalSections(
      request,
      plan,
      locked,
      sourceBundle.fragments,
    );
    const merged: IncrementalMergeResult = mergeIncrementalPatches(locked, plan, patchResponse.patches);
    const manifest: IncrementalManifest = buildIncrementalManifest(
      base.unit.id,
      base.baseVersion + 1,
      merged.sections,
      base.manifest.sourceIds.concat(plan.newSourceIds),
    );
    if (!merged.ok) {
      const result: NoteGenerationResult = this.incrementalResult(request, manifest, plan, merged.diff, 'needs-input');
      for (const issue of merged.issues) {
        result.issues.push({ stage: 'merge', code: issue, severity: 'hard', message: issue, repairable: false });
      }
      return { success: false, route: 'D1', generation: result, errorMessage: merged.issues.join(';'), durationMs: Date.now() - startedAt };
    }
    const nextContent: string = renderIncrementalSections(merged.sections);
    const candidate: KnowledgeUnit = this.copyRegeneratedUnit(base.unit, nextContent);
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

  private copyRegeneratedUnit(unit: KnowledgeUnit, content: string): KnowledgeUnit {
    return {
      id: unit.id, title: unit.title, content: content, summary: unit.summary, tags: unit.tags,
      subject: unit.subject, category: unit.category, chapter: unit.chapter, difficulty: unit.difficulty,
      source: unit.source, createdAt: unit.createdAt, updatedAt: Date.now(), reviewStatus: unit.reviewStatus,
      nextReviewAt: unit.nextReviewAt, intervalDays: unit.intervalDays, easeFactor: unit.easeFactor,
      repetitions: unit.repetitions, prerequisites: unit.prerequisites, related: unit.related,
      embedding: unit.embedding, userId: unit.userId, version: unit.version,
    };
  }

  private async dispatchGeneration(
    request: NoteGenerationRequest,
    req: DispatchRequest,
    options: DispatchOptions,
    startedAt: number,
  ): Promise<DispatchResult> {
    const bundle: SourceBundle = this.normalizeBundle(request);
    const route = request.route ?? selectGenerationRoute(bundle, request.instruction);
    const budget = route === 'deep' ? deepBudget() : route === 'standard' ? standardBudget() : lightBudget();
    const requirement = request.requirement ?? defaultRequirement(request.instruction);
    const run: NoteGenerationRun = {
      id: request.runId,
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
      payload: { kind: 'text', text: this.bundleText(bundle) },
    };
    if (route === 'standard') {
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
      captureText: this.bundleText(bundle),
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
    const graph: CaptureGraph = this.buildGenerationGraph(options.knowledgeModel);
    const finalState: AgentState = await graph.run(initial);
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
    const model: KnowledgeModel = options.knowledgeModel ?? new KnowledgeModel();
    const budgetedRequest: NoteGenerationRequest = this.withTokenBudget(request, budget.maxTokens);
    let current: NoteGenerationStandardResult;
    try {
      current = await model.structureStandardDraft(budgetedRequest);
    } catch (e) {
      return await this.finishStandardGeneration(request, run, bundle, options, startedAt, [], undefined, {
        round: 0,
        stopReason: 'initial_generation_failed',
        rollback: false,
      }, 'initial generation failed: ' + (e as Error).message);
    }

    let best: GenerationCandidateEvaluation | undefined = undefined;
    let bestCheckpointId: string | undefined = undefined;
    let parentId: string | undefined = undefined;
    let usedTokens: number = 0;
    let nodeRuns: number = 1;
    let round: number = 0;
    let noImprovementRounds: number = 0;
    let previous: GenerationCandidateEvaluation | undefined = undefined;
    let stopReason: string = 'repair_complete';
    let rollback: boolean = false;
    const seenFingerprints: string[] = [];

    while (true) {
      const evaluation: GenerationCandidateEvaluation = await this.evaluateStandardCandidate(
        current,
        bundle,
        requirement,
        previous,
        model,
      );
      usedTokens += evaluation.tokenCost;
      const fingerprintRepeated: boolean = seenFingerprints.includes(evaluation.issueFingerprint);
      seenFingerprints.push(evaluation.issueFingerprint);
      const isBetter: boolean = best === undefined || this.isBetterCandidate(evaluation, best);
      const checkpointId: string = request.runId + ':' + round.toString();
      const decision: NoteGenerationCheckpointDecision = isBetter
        ? (round === 0 ? 'initial' : 'best')
        : 'rejected';
      if (isBetter) {
        best = evaluation;
        bestCheckpointId = checkpointId;
      }
      const checkpoint: NoteGenerationCheckpoint = {
        id: checkpointId,
        runId: request.runId,
        iteration: round,
        stage: 'truth_check',
        parentId: parentId,
        candidateHash: sourceFingerprint(JSON.stringify(evaluation.result)),
        documentJson: JSON.stringify(evaluation.result.draft),
        accepted: isBetter,
        issueCodes: evaluation.issues.map((issue: NoteGenerationIssue): string => issue.code),
        outlineJson: JSON.stringify(evaluation.result.outline),
        evidenceJson: JSON.stringify(evaluation.result.evidence),
        verificationJson: JSON.stringify(evaluation.result.verification),
        issueFingerprint: evaluation.issueFingerprint,
        coverage: evaluation.coverage,
        tokenCost: evaluation.tokenCost,
        changeScope: evaluation.changeScope,
        decision: decision,
        createdAt: Date.now(),
      };
      if (options.generationRepository !== undefined) {
        await options.generationRepository.saveCheckpoint(checkpoint);
        await options.generationRepository.appendLifecycleLog({
          runId: request.runId,
          event: 'retried',
          checkpointId: checkpointId,
          issueCount: evaluation.issues.length,
          sourceCount: bundle.fragments.length,
          round: round,
          stopReason: undefined,
          rollback: rollback,
        });
      }
      log.info('generation progress run=' + request.runId + ' round=' + round.toString()
        + ' stop=running rollback=' + rollback.toString() + ' issues=' + evaluation.issues.length.toString());

      if (best !== undefined && best.hardIssueCount === 0) {
        stopReason = round === 0 ? 'standard_complete' : 'repair_complete';
        break;
      }
      if (fingerprintRepeated) {
        stopReason = 'repeated_issue_fingerprint';
        rollback = best !== evaluation;
        break;
      }
      if (previous !== undefined) {
        const hardReduced: boolean = evaluation.hardIssueCount < previous.hardIssueCount;
        const mustImprovement: number = evaluation.coverage.mustInclude - previous.coverage.mustInclude;
        const evidenceImprovement: number = evaluation.coverage.evidence - previous.coverage.evidence;
        if (!hardReduced && mustImprovement < 0.02 && evidenceImprovement < 0.02) {
          noImprovementRounds += 1;
        } else {
          noImprovementRounds = 0;
        }
        if (noImprovementRounds >= 2) {
          stopReason = 'diminishing_returns';
          rollback = best !== evaluation;
          break;
        }
      }
      if (round >= budget.maxRepairRounds) {
        stopReason = 'repair_budget_exhausted';
        rollback = best !== evaluation;
        break;
      }
      if (usedTokens >= budget.maxTokens) {
        stopReason = 'token_budget_exhausted';
        rollback = best !== evaluation;
        break;
      }
      if (nodeRuns + 2 > budget.maxNodeRuns) {
        stopReason = 'node_budget_exhausted';
        rollback = best !== evaluation;
        break;
      }
      previous = evaluation;
      parentId = checkpointId;
      round += 1;
      nodeRuns += 2;
      try {
        current = await model.repairStandardDraft(budgetedRequest, current, evaluation.issues);
      } catch (e) {
        stopReason = 'repair_failed';
        rollback = best !== evaluation;
        break;
      }
    }

    const finalEvaluation: GenerationCandidateEvaluation | undefined = best;
    const progress: NoteGenerationProgress = {
      round: round,
      stopReason: stopReason,
      rollback: rollback,
    };
    if (finalEvaluation === undefined || finalEvaluation.hardIssueCount > 0) {
      return await this.finishStandardGeneration(
        request,
        this.completedRun(run, bestCheckpointId, stopReason),
        bundle,
        options,
        startedAt,
        finalEvaluation === undefined ? [] : finalEvaluation.issues,
        undefined,
        progress,
        'standard generation requires additional input',
        finalEvaluation?.result,
      );
    }
    const finalCandidate: KnowledgeUnit = finalEvaluation.candidate;
    return await this.finishStandardGeneration(
      request,
      this.completedRun(run, bestCheckpointId, stopReason),
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
    const model: KnowledgeModel = options.knowledgeModel ?? new KnowledgeModel();
    const budgetedRequest: NoteGenerationRequest = this.withTokenBudget(request, budget.maxTokens);
    let current: NoteGenerationDeepResult;
    try {
      current = await model.structureDeepDraft(budgetedRequest);
    } catch (e) {
      return await this.finishStandardGeneration(request, run, bundle, options, startedAt, [], undefined, {
        round: 0,
        stopReason: 'initial_deep_generation_failed',
        rollback: false,
      }, 'initial deep generation failed: ' + (e as Error).message, undefined, 'deep');
    }
    let best: GenerationCandidateEvaluation | undefined = undefined;
    let bestCheckpointId: string | undefined = undefined;
    let parentId: string | undefined = undefined;
    let usedTokens: number = 0;
    let nodeRuns: number = 1;
    let round: number = 0;
    let noImprovementRounds: number = 0;
    let previous: GenerationCandidateEvaluation | undefined = undefined;
    let stopReason: string = 'deep_complete';
    let rollback: boolean = false;
    const seenFingerprints: string[] = [];
    while (true) {
      const evaluation: GenerationCandidateEvaluation = await this.evaluateDeepCandidate(
        current,
        bundle,
        requirement,
        previous,
        model,
      );
      usedTokens += evaluation.tokenCost;
      const repeated: boolean = seenFingerprints.includes(evaluation.issueFingerprint);
      seenFingerprints.push(evaluation.issueFingerprint);
      const better: boolean = best === undefined || this.isBetterCandidate(evaluation, best);
      const checkpointId: string = request.runId + ':' + round.toString();
      const decision: NoteGenerationCheckpointDecision = better
        ? (round === 0 ? 'initial' : 'best') : 'rejected';
      if (better) {
        best = evaluation;
        bestCheckpointId = checkpointId;
      }
      const checkpoint: NoteGenerationCheckpoint = {
        id: checkpointId,
        runId: request.runId,
        iteration: round,
        stage: 'truth_check',
        parentId: parentId,
        candidateHash: sourceFingerprint(JSON.stringify(evaluation.result)),
        documentJson: JSON.stringify(evaluation.result.draft),
        accepted: better,
        issueCodes: evaluation.issues.map((issue: NoteGenerationIssue): string => issue.code),
        outlineJson: JSON.stringify(evaluation.result.outline),
        evidenceJson: JSON.stringify(evaluation.result.evidence),
        verificationJson: JSON.stringify(evaluation.result.verification),
        issueFingerprint: evaluation.issueFingerprint,
        coverage: evaluation.coverage,
        tokenCost: evaluation.tokenCost,
        changeScope: evaluation.changeScope,
        decision: decision,
        createdAt: Date.now(),
      };
      if (options.generationRepository !== undefined) {
        await options.generationRepository.saveCheckpoint(checkpoint);
        await options.generationRepository.appendLifecycleLog({
          runId: request.runId,
          event: 'retried',
          checkpointId: checkpointId,
          issueCount: evaluation.issues.length,
          sourceCount: bundle.fragments.length,
          round: round,
          rollback: rollback,
        });
      }
      if (usedTokens > budget.maxTokens) {
        stopReason = 'token_budget_exhausted';
        rollback = best !== evaluation;
        break;
      }
      if (best !== undefined && best.hardIssueCount === 0) {
        stopReason = round === 0 ? 'deep_complete' : 'deep_repair_complete';
        break;
      }
      if (repeated) {
        stopReason = 'repeated_issue_fingerprint';
        rollback = best !== evaluation;
        break;
      }
      if (previous !== undefined) {
        const hardReduced: boolean = evaluation.hardIssueCount < previous.hardIssueCount;
        const mustImprovement: number = evaluation.coverage.mustInclude - previous.coverage.mustInclude;
        const evidenceImprovement: number = evaluation.coverage.evidence - previous.coverage.evidence;
        if (!hardReduced && mustImprovement < 0.02 && evidenceImprovement < 0.02) {
          noImprovementRounds += 1;
        } else {
          noImprovementRounds = 0;
        }
        if (noImprovementRounds >= 2) {
          stopReason = 'diminishing_returns';
          rollback = best !== evaluation;
          break;
        }
      }
      if (round >= budget.maxRepairRounds) {
        stopReason = 'repair_budget_exhausted';
        rollback = best !== evaluation;
        break;
      }
      if (usedTokens >= budget.maxTokens) {
        stopReason = 'token_budget_exhausted';
        rollback = best !== evaluation;
        break;
      }
      if (nodeRuns + 2 > budget.maxNodeRuns) {
        stopReason = 'node_budget_exhausted';
        rollback = best !== evaluation;
        break;
      }
      previous = evaluation;
      parentId = checkpointId;
      round += 1;
      nodeRuns += 2;
      try {
        current = await model.repairDeepDraft(budgetedRequest, current, evaluation.issues);
      } catch (e) {
        stopReason = 'repair_failed';
        rollback = best !== evaluation;
        break;
      }
    }
    const finalEvaluation: GenerationCandidateEvaluation | undefined = best;
    const progress: NoteGenerationProgress = { round: round, stopReason: stopReason, rollback: rollback };
    const deepResult: NoteGenerationDeepResult | undefined = finalEvaluation?.deepResult;
    if (finalEvaluation === undefined || finalEvaluation.hardIssueCount > 0 || stopReason === 'token_budget_exhausted') {
      return await this.finishStandardGeneration(
        request,
        this.completedRun(run, bestCheckpointId, stopReason),
        bundle,
        options,
        startedAt,
        finalEvaluation?.issues ?? [],
        undefined,
        progress,
        'deep generation requires additional input',
        deepResult,
        'deep',
      );
    }
    return await this.finishStandardGeneration(
      request,
      this.completedRun(run, bestCheckpointId, stopReason),
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

  private async evaluateStandardCandidate(
    result: NoteGenerationStandardResult,
    bundle: SourceBundle,
    requirement: NoteGenerationRequirement,
    previous: GenerationCandidateEvaluation | undefined,
    model: KnowledgeModel,
  ): Promise<GenerationCandidateEvaluation> {
    const candidate: KnowledgeUnit = model.draftToKnowledgeUnit(result.draft, 'note_generation');
    const issues: NoteGenerationIssue[] = [];
    for (const issue of result.verification.issues) {
      issues.push(issue);
    }
    const truthState: AgentState = await this.buildPreparedGraph(undefined).run({
      captureText: this.bundleText(bundle),
      source: 'note_generation',
      payload: { kind: 'text', text: this.bundleText(bundle) },
      generationRequest: {
        runId: 'candidate-check',
        instruction: requirement.mustInclude.join(','),
        mode: 'create',
        sources: bundle,
      },
      currentStep: 'START',
      persist: false,
      analysisOnly: false,
      knowledgeUnit: candidate,
    });
    if (truthState.error !== undefined) {
      issues.push({
        stage: 'truth_check',
        code: 'TRUTH_CHECK_ERROR',
        severity: 'hard',
        message: 'candidate truth check failed',
        repairable: true,
      });
    }
    let hardIssueCount: number = 0;
    let contradictionCount: number = 0;
    const issueCodes: string[] = [];
    for (const issue of issues) {
      if (issue.severity === 'hard') {
        hardIssueCount += 1;
      }
      if (issue.code === 'EVIDENCE_CONTRADICTED') {
        contradictionCount += 1;
      }
      const issueKey: string = issue.code + ':' + (issue.stage ?? '') + ':'
        + (issue.sectionId ?? '') + ':' + (issue.sourceId ?? '');
      if (!issueCodes.includes(issueKey)) {
        issueCodes.push(issueKey);
      }
    }
    issueCodes.sort();
    let mustMatched: number = 0;
    for (const item of requirement.mustInclude) {
      let included: boolean = false;
      for (const section of result.draft.sections) {
        if (section.content.includes(item) || section.label.includes(item)) {
          included = true;
          break;
        }
      }
      if (included) {
        mustMatched += 1;
      }
    }
    const mustCoverage: number = requirement.mustInclude.length === 0
      ? 1 : mustMatched / requirement.mustInclude.length;
    let supportedCount: number = 0;
    for (const item of result.evidence) {
      if (item.verification === 'supported') {
        supportedCount += 1;
      }
    }
    const evidenceCoverage: number = result.evidence.length === 0 ? 0 : supportedCount / result.evidence.length;
    const coverage: NoteGenerationCoverage = {
      mustInclude: mustCoverage,
      evidence: evidenceCoverage,
      lockedPreservation: this.lockedPreservation(result, previous),
    };
    let changeScope: number = 0;
    if (previous !== undefined) {
      changeScope = this.changeScope(previous.result.draft, result.draft);
    }
    const tokenCost: number = Math.ceil(JSON.stringify(result).length / 4);
    return {
      result: result,
      candidate: candidate,
      issues: issues,
      hardIssueCount: hardIssueCount,
      contradictionCount: contradictionCount,
      coverage: coverage,
      tokenCost: tokenCost,
      changeScope: changeScope,
      issueFingerprint: issueCodes.join('|'),
    };
  }

  private async evaluateDeepCandidate(
    result: NoteGenerationDeepResult,
    bundle: SourceBundle,
    requirement: NoteGenerationRequirement,
    previous: GenerationCandidateEvaluation | undefined,
    model: KnowledgeModel,
  ): Promise<GenerationCandidateEvaluation> {
    const evaluation: GenerationCandidateEvaluation = await this.evaluateStandardCandidate(
      result,
      bundle,
      requirement,
      previous,
      model,
    );
    const mergeIssues: NoteGenerationIssue[] = this.deepMergeIssues(result, bundle, requirement);
    for (const issue of mergeIssues) {
      evaluation.issues.push(issue);
      evaluation.hardIssueCount += issue.severity === 'hard' ? 1 : 0;
    }
    const issueCodes: string[] = [];
    for (const issue of evaluation.issues) {
      const key: string = issue.code + ':' + (issue.sectionId ?? '') + ':' + (issue.sourceId ?? '');
      if (!issueCodes.includes(key)) {
        issueCodes.push(key);
      }
    }
    issueCodes.sort();
    evaluation.issueFingerprint = issueCodes.join('|');
    evaluation.deepResult = result;
    return evaluation;
  }

  private deepMergeIssues(
    result: NoteGenerationDeepResult,
    bundle: SourceBundle,
    requirement: NoteGenerationRequirement,
  ): NoteGenerationIssue[] {
    const issues: NoteGenerationIssue[] = [];
    const mappedSources: string[] = [];
    const seenSections: string[] = [];
    for (const section of result.outline.sections) {
      if (seenSections.includes(section.id)) {
        issues.push({ stage: 'merge', code: 'DEEP_SECTION_DUPLICATE', severity: 'hard', message: 'deep outline contains duplicate section ids', repairable: true, sectionId: section.id });
      }
      seenSections.push(section.id);
      if (section.sourceIds.length === 0) {
        issues.push({ stage: 'outline', code: 'DEEP_ORPHAN_SECTION', severity: 'hard', message: 'deep section has no source mapping', repairable: false, sectionId: section.id });
      }
      for (const sourceId of section.sourceIds) {
        if (!mappedSources.includes(sourceId)) {
          mappedSources.push(sourceId);
        }
        if (!bundle.fragments.some((fragment): boolean => fragment.id === sourceId)) {
          issues.push({ stage: 'outline', code: 'DEEP_SOURCE_INVALID', severity: 'hard', message: 'deep outline references an unknown source', repairable: false, sourceId: sourceId, sectionId: section.id });
        }
      }
    }
    for (const fragment of bundle.fragments) {
      if (fragment.kind !== 'summary' && !mappedSources.includes(fragment.id)) {
        issues.push({ stage: 'outline', code: 'DEEP_SOURCE_ORPHANED', severity: 'hard', message: 'deep source has no section destination: ' + fragment.id, repairable: false, sourceId: fragment.id });
      }
    }
    for (const item of requirement.mustInclude) {
      let found: boolean = false;
      for (const section of result.draft.sections) {
        if (section.content.includes(item) || section.label.includes(item)) {
          found = true;
          break;
        }
      }
      if (!found) {
        issues.push({ stage: 'merge', code: 'DEEP_MUST_INCLUDE_MISSING', severity: 'hard', message: 'deep draft does not cover must-include: ' + item, repairable: true });
      }
    }
    for (let index: number = 0; index < result.draft.sections.length; index += 1) {
      const section: NoteDraftSection = result.draft.sections[index];
      for (let nextIndex: number = index + 1; nextIndex < result.draft.sections.length; nextIndex += 1) {
        const next: NoteDraftSection = result.draft.sections[nextIndex];
        if (section.content.trim().length > 0 && section.content === next.content) {
          issues.push({ stage: 'merge', code: 'DEEP_SECTION_DUPLICATE_CONTENT', severity: 'hard', message: 'deep sections duplicate the same content', repairable: true, sectionId: next.id });
        }
      }
    }
    const formulaBySymbol: Map<string, string> = new Map<string, string>();
    for (const section of result.draft.sections) {
      const lines: string[] = section.content.split('\n');
      for (const line of lines) {
        const equalsIndex: number = line.indexOf('=');
        if (equalsIndex <= 0) {
          continue;
        }
        const symbol: string = line.substring(0, equalsIndex).trim();
        const formula: string = line.trim();
        const previousFormula: string | undefined = formulaBySymbol.get(symbol);
        if (previousFormula !== undefined && previousFormula !== formula) {
          issues.push({ stage: 'merge', code: 'DEEP_SYMBOL_DRIFT', severity: 'hard', message: 'deep sections use inconsistent formula symbols', repairable: true, sectionId: section.id });
        } else {
          formulaBySymbol.set(symbol, formula);
        }
      }
      if (section.content.includes('参见') || section.content.includes('见第')) {
        let referenceResolved: boolean = false;
        for (const other of result.draft.sections) {
          if (other.id !== section.id && (section.content.includes(other.label) || section.content.includes(other.id))) {
            referenceResolved = true;
            break;
          }
        }
        if (!referenceResolved) {
          issues.push({ stage: 'merge', code: 'DEEP_REFERENCE_INVALID', severity: 'hard', message: 'deep section contains an unresolved cross-section reference', repairable: true, sectionId: section.id });
        }
      }
    }
    for (let firstIndex: number = 0; firstIndex < bundle.fragments.length; firstIndex += 1) {
      const firstText: string = bundle.fragments[firstIndex].text;
      for (let secondIndex: number = firstIndex + 1; secondIndex < bundle.fragments.length; secondIndex += 1) {
        const secondText: string = bundle.fragments[secondIndex].text;
        if ((firstText.includes('不成立') && secondText.includes('成立'))
          || (firstText.includes('成立') && secondText.includes('不成立'))) {
          issues.push({ stage: 'merge', code: 'DEEP_CONTRADICTION', severity: 'hard', message: 'deep source fragments contain contradictory conclusions', repairable: true });
        }
      }
    }
    return issues;
  }

  private isBetterCandidate(next: GenerationCandidateEvaluation, best: GenerationCandidateEvaluation): boolean {
    if (next.hardIssueCount !== best.hardIssueCount) {
      return next.hardIssueCount < best.hardIssueCount;
    }
    if (next.contradictionCount !== best.contradictionCount) {
      return next.contradictionCount < best.contradictionCount;
    }
    if (next.coverage.mustInclude !== best.coverage.mustInclude) {
      return next.coverage.mustInclude > best.coverage.mustInclude;
    }
    if (next.coverage.evidence !== best.coverage.evidence) {
      return next.coverage.evidence > best.coverage.evidence;
    }
    if (next.coverage.lockedPreservation !== best.coverage.lockedPreservation) {
      return next.coverage.lockedPreservation > best.coverage.lockedPreservation;
    }
    if (next.tokenCost !== best.tokenCost) {
      return next.tokenCost < best.tokenCost;
    }
    return next.changeScope < best.changeScope;
  }

  private lockedPreservation(
    current: NoteGenerationStandardResult,
    previous: GenerationCandidateEvaluation | undefined,
  ): number {
    if (previous === undefined) {
      return 1;
    }
    let locked: number = 0;
    let preserved: number = 0;
    for (const oldSection of previous.result.draft.sections) {
      if (oldSection.state === 'locked') {
        locked += 1;
        const nextSection = current.draft.sections.find((item: NoteDraftSection): boolean => item.id === oldSection.id);
        if (nextSection !== undefined && nextSection.content === oldSection.content) {
          preserved += 1;
        }
      }
    }
    return locked === 0 ? 1 : preserved / locked;
  }

  private changeScope(before: NoteDraftDocument, after: NoteDraftDocument): number {
    let changed: number = 0;
    const total: number = Math.max(before.sections.length, after.sections.length);
    for (let index: number = 0; index < total; index += 1) {
      const oldSection: NoteDraftSection | undefined = before.sections[index];
      const newSection: NoteDraftSection | undefined = after.sections[index];
      if (oldSection === undefined || newSection === undefined || oldSection.content !== newSection.content) {
        changed += 1;
      }
    }
    return total === 0 ? 0 : changed / total;
  }

  private async finishStandardGeneration(
    request: NoteGenerationRequest,
    run: NoteGenerationRun,
    bundle: SourceBundle,
    options: DispatchOptions,
    startedAt: number,
    issues: NoteGenerationIssue[],
    candidate: KnowledgeUnit | undefined,
    progress: NoteGenerationProgress,
    errorMessage?: string,
    standardResult?: NoteGenerationStandardResult,
    route: NoteGenerationRoute = 'standard',
  ): Promise<DispatchResult> {
    const status = candidate === undefined ? 'needs-input' : 'ready-preview';
    const deepResult: NoteGenerationDeepResult | undefined = route === 'deep' && standardResult !== undefined
      ? standardResult as NoteGenerationDeepResult : undefined;
    const result: NoteGenerationResult = {
      runId: request.runId,
       route: route,
      status: status,
      candidate: candidate,
      draft: standardResult?.draft,
      bestCheckpointId: run.bestCheckpointId,
      issues: issues,
      questions: candidate === undefined ? issues.map((issue: NoteGenerationIssue): string => issue.message) : [],
      stopReason: progress.stopReason,
      promptTokens: 0,
      completionTokens: 0,
      sourceIds: run.sourceIds,
      outline: standardResult?.outline,
      evidence: standardResult?.evidence,
       verification: standardResult?.verification,
       ledger: deepResult?.ledger,
       segments: deepResult?.segments,
      progress: progress,
    };
    if (options.generationRepository !== undefined) {
      const completedRun: NoteGenerationRun = {
        id: run.id,
        route: run.route,
        status: status,
        instruction: run.instruction,
        sourceCount: run.sourceCount,
        tokenBudget: run.tokenBudget,
        bestCheckpointId: run.bestCheckpointId,
        stopReason: progress.stopReason,
        issueCount: issues.length,
        createdAt: run.createdAt,
        updatedAt: Date.now(),
        sourceIds: run.sourceIds,
        pendingSourceIds: run.pendingSourceIds,
        sourceSummary: run.sourceSummary,
      };
      await options.generationRepository.saveRun(completedRun, bundle);
      await options.generationRepository.appendLifecycleLog({
        runId: request.runId,
        event: 'retried',
        checkpointId: run.bestCheckpointId,
        issueCount: issues.length,
        sourceCount: bundle.fragments.length,
        round: progress.round,
        stopReason: progress.stopReason,
        rollback: progress.rollback,
      });
      log.info('generation progress run=' + request.runId + ' round=' + progress.round.toString()
        + ' stop=' + progress.stopReason + ' rollback=' + progress.rollback.toString());
    }
    return {
      success: candidate !== undefined,
      route: 'D1',
      data: candidate,
      generation: result,
      errorMessage: errorMessage,
      durationMs: Date.now() - startedAt,
    };
  }

  private completedRun(run: NoteGenerationRun, checkpointId: string | undefined, stopReason: string): NoteGenerationRun {
    return {
      id: run.id,
      route: run.route,
      status: run.status,
      instruction: run.instruction,
      sourceCount: run.sourceCount,
      tokenBudget: run.tokenBudget,
      bestCheckpointId: checkpointId,
      stopReason: stopReason,
      issueCount: run.issueCount,
      createdAt: run.createdAt,
      updatedAt: run.updatedAt,
      sourceIds: run.sourceIds,
      pendingSourceIds: run.pendingSourceIds,
      sourceSummary: run.sourceSummary,
    };
  }

  private withTokenBudget(request: NoteGenerationRequest, tokenBudget: number): NoteGenerationRequest {
    return {
      runId: request.runId,
      instruction: request.instruction,
      mode: request.mode,
      sources: request.sources,
      requirement: request.requirement,
      targetNoteId: request.targetNoteId,
      baseVersion: request.baseVersion,
      pendingSourceIds: request.pendingSourceIds,
      route: request.route,
      tokenBudget: tokenBudget,
    };
  }

  private async dispatchPreparedCandidate(
    req: DispatchRequest,
    prepared: PreparedCandidate,
    options: DispatchOptions,
    startedAt: number,
  ): Promise<DispatchResult> {
    const actualHash: string = sourceFingerprint(JSON.stringify(prepared.candidate));
    if (actualHash !== prepared.candidateHash) {
      return { success: false, route: 'D1', errorMessage: '候选内容已变化', durationMs: Date.now() - startedAt };
    }
    if (options.generationRepository === undefined) {
      return { success: false, route: 'D1', errorMessage: '缺少草稿检查点', durationMs: Date.now() - startedAt };
    }
    const commitKey: string = prepared.commitKey ?? prepared.runId + ':' + prepared.checkpointId + ':' + prepared.candidateHash;
    const existingCommit: NoteGenerationCommitResult | undefined = await options.generationRepository.getCommitResult(commitKey);
    if (existingCommit !== undefined && existingCommit.candidateJson !== undefined && existingCommit.candidateJson.length > 0) {
      const restoredCandidate: KnowledgeUnit = JSON.parse(existingCommit.candidateJson) as KnowledgeUnit;
      await options.generationRepository.appendLifecycleLog({
        runId: prepared.runId,
        event: 'duplicate-confirm',
        checkpointId: prepared.checkpointId,
        sourceCount: prepared.pendingSourceIds?.length ?? 0,
      });
      return { success: true, route: 'D1', data: restoredCandidate, durationMs: Date.now() - startedAt };
    }
    const recovery = await options.generationRepository.restore(prepared.runId);
    if (recovery === undefined) {
      return { success: false, route: 'D1', errorMessage: '草稿运行不存在', durationMs: Date.now() - startedAt };
    }
    let checkpoint: NoteGenerationCheckpoint | undefined = undefined;
    for (const item of recovery.checkpoints) {
      if (item.id === prepared.checkpointId) {
        checkpoint = item;
        break;
      }
    }
    if (checkpoint === undefined || checkpoint.runId !== prepared.runId || checkpoint.candidateHash !== prepared.candidateHash) {
      return { success: false, route: 'D1', errorMessage: '草稿检查点不匹配', durationMs: Date.now() - startedAt };
    }
    const initial: AgentState = {
      captureText: this.seedText(req),
      source: 'note_generation',
      payload: req.payload,
      currentStep: 'START',
      persist: true,
      analysisOnly: false,
      preparedCandidate: prepared,
      knowledgeUnit: prepared.candidate,
    };
    const graph: CaptureGraph = this.buildPreparedGraph(options.dao);
    const finalState: AgentState = await graph.run(initial);
    if (finalState.error !== undefined) {
      const conflict: boolean = finalState.error.message.indexOf('VERSION_CONFLICT') >= 0;
      return {
        success: false,
        route: 'D1',
        errorCode: conflict ? 'VERSION_CONFLICT' : undefined,
        errorMessage: finalState.error.message,
        durationMs: Date.now() - startedAt,
      };
    }
    let committedCandidate: KnowledgeUnit = prepared.candidate;
    if (finalState.commitResult !== undefined) {
      committedCandidate = this.copyRegeneratedUnit(prepared.candidate, prepared.candidate.content);
      committedCandidate.version = finalState.commitResult.version;
      const contentChanged: boolean = prepared.incrementalDiff?.some(
        (item: IncrementalDiffItem): boolean => item.kind === 'changed' || item.kind === 'added',
      ) === true;
      if (prepared.updateExisting === true && contentChanged) {
        committedCandidate.embedding = [];
      }
      const commit: NoteGenerationCommitResult = {
        commitKey: commitKey,
        runId: prepared.runId,
        checkpointId: prepared.checkpointId,
        noteId: finalState.commitResult.noteId,
        version: finalState.commitResult.version,
        sourceIds: prepared.pendingSourceIds ?? prepared.sourceIds ?? [],
        candidateJson: JSON.stringify(committedCandidate),
        committedAt: Date.now(),
      };
      await options.generationRepository.saveCommitResult(commit);
      await options.generationRepository.appendLifecycleLog({
        runId: prepared.runId,
        event: finalState.commitResult.duplicate ? 'duplicate-confirm' : 'committed',
        checkpointId: prepared.checkpointId,
        sourceCount: commit.sourceIds.length,
      });
    }
    return { success: true, route: 'D1', data: committedCandidate, durationMs: Date.now() - startedAt };
  }

  private buildPreparedGraph(dao?: NoteDaoInterface): CaptureGraph {
    const graph: CaptureGraph = new CaptureGraph();
    const truth: TruthCheckService = new TruthCheckService();
    graph.addNode('truth_check', TruthCheckNodeFactory.create(truth));
    if (dao !== undefined) {
      graph.addNode('persist', PersistNodeFactory.create(dao));
    } else {
      graph.addNode('persist', async (input: AgentState): Promise<CaptureNodeResult> => {
        const next: AgentState = copyAgentState(input);
        next.error = {
          kind: 'PERSIST_DAO_REQUIRED',
          message: 'persist requested but no NoteDaoInterface was provided',
          step: 'persist',
          retriable: false,
        };
        return { state: next };
      });
    }
    graph.addEdge('START', 'truth_check');
    graph.addConditionalEdge('truth_check', (input: AgentState): CaptureStep => input.persist ? 'persist' : 'END');
    graph.addEdge('persist', 'END');
    return graph;
  }

  private buildGenerationGraph(model?: KnowledgeModel): CaptureGraph {
    const graph: CaptureGraph = new CaptureGraph();
    const structure: KnowledgeModel = model ?? new KnowledgeModel();
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
        fingerprint: fragment.fingerprint.length > 0 ? fragment.fingerprint : sourceFingerprint(fragment.text),
        text: fragment.text,
      });
      sequence += 1;
    }
    return normalized;
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

  private bundleText(bundle: SourceBundle): string {
    const lines: string[] = [];
    for (const fragment of bundle.fragments) {
      lines.push('[source:' + fragment.id + '] ' + fragment.text);
    }
    return lines.join('\n');
  }

  private buildGraph(options: DispatchOptions = {}): CaptureGraph {
    const graph: CaptureGraph = new CaptureGraph();
    const classifier: TypeClassifier = new TypeClassifier();
    const structure: KnowledgeModel = new KnowledgeModel();
    const truth: TruthCheckService = new TruthCheckService();
    graph.addNode('capture', OcrNodeFactory.create(classifier));
    graph.addNode('classify', ClassifyNodeFactory.create(classifier));
    graph.addNode('structure', StructureNodeFactory.create(structure));
    graph.addNode('truth_check', TruthCheckNodeFactory.create(truth));
    if (options.dao !== undefined) {
      graph.addNode('persist', PersistNodeFactory.create(options.dao));
    } else {
      graph.addNode('persist', async (input: AgentState): Promise<CaptureNodeResult> => {
        const next: AgentState = copyAgentState(input);
        const error: CaptureGraphError = {
          kind: 'PERSIST_DAO_REQUIRED',
          message: 'persist requested but no NoteDaoInterface was provided',
          step: 'persist',
          retriable: false,
        };
        next.error = error;
        const result: CaptureNodeResult = { state: next };
        return result;
      });
    }
    graph.addEdge('START', 'capture');
    graph.addEdge('capture', 'classify');
    graph.addConditionalEdge('classify', (input: AgentState): CaptureStep => {
      return input.analysisOnly ? 'END' : 'structure';
    });
    graph.addEdge('structure', 'truth_check');
    graph.addConditionalEdge('truth_check', (input: AgentState): CaptureStep => input.persist ? 'persist' : 'END');
    graph.addEdge('persist', 'END');
    return graph;
  }

  private seedText(req: DispatchRequest): string {
    if (req.payload.kind === 'text') {
      return req.payload.text;
    }
    return '';
  }
}
