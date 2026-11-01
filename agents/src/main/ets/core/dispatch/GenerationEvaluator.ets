/**
 * GenerationEvaluator.ets — 生成结果的评估 / 终态 / 诊断（从 CommandExecutor.ets 抽出）
 *
 * 路径: agents/src/main/ets/core/dispatch/GenerationEvaluator.ets
 * 职责: 标准/深度候选评估、问题合并与摘要、终态 run 组装、诊断日志、预算包装、bundleText。
 *       全部为静态方法，不持有 CommandExecutor 状态。
 * 依赖: common 的生成模型类型（NoteGenerationStandardResult / Issue / Coverage / Run 等）。
 *
 * 拆出原因（2026-10-31）：CommandExecutor 近 1530 行，评估/诊断/终态逻辑与分支编排混在一个类；
 * 这些方法只依赖入参与 common 类型，是低风险的第一块可整体搬走的逻辑。
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
import { KnowledgeModel } from '../../agents/KnowledgeModel';
import { AgentState } from '../../graph/AgentState';
import { PreparedBranch } from './PreparedBranch';
import type { DispatchOptions } from './DispatchOptions';
import type { NoteOutcome } from 'common';

const evaluatorLog = new Logger('GenerationEvaluator');

export interface GenerationCandidateEvaluation {
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

export interface DeepFormulaDefinition {
  formula: string;
  sectionId: string;
}

export interface DeepFormulaCandidate {
  symbol: string;
  formula: string;
}

export class GenerationEvaluator {
  static async evaluateStandardCandidate(
    result: NoteGenerationStandardResult,
    bundle: SourceBundle,
    requirement: NoteGenerationRequirement,
    model: KnowledgeModel,
  ): Promise<GenerationCandidateEvaluation> {
    const candidate: KnowledgeUnit = model.draftToKnowledgeUnit(
      result.draft,
      'note_generation',
      captureProvenanceFromFragments(bundle.fragments),
    );
    const issues: NoteGenerationIssue[] = [];
    for (const issue of result.verification.issues) {
      issues.push(issue);
    }
    const truthState: AgentState = await PreparedBranch.buildGraph(undefined).run({
      captureText: GenerationEvaluator.bundleText(bundle),
      source: 'note_generation',
      payload: { kind: 'text', text: GenerationEvaluator.bundleText(bundle) },
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
        message: truthState.error.message,
        repairable: false,
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
    for (const decision of result.verification.decisions) {
      if (decision.status === 'supported') {
        supportedCount += 1;
      }
    }
    const evidenceCoverage: number = result.evidence.length === 0 ? 0 : supportedCount / result.evidence.length;
    const coverage: NoteGenerationCoverage = {
      mustInclude: mustCoverage,
      evidence: evidenceCoverage,
      lockedPreservation: 1,
    };
    const tokenCost: number = Math.ceil(JSON.stringify(result).length / 4);
    return {
      result: result,
      candidate: candidate,
      issues: issues,
      hardIssueCount: hardIssueCount,
      contradictionCount: contradictionCount,
      coverage: coverage,
      tokenCost: tokenCost,
      changeScope: 0,
      issueFingerprint: issueCodes.join('|'),
    };
  }

  static async evaluateDeepCandidate(
    result: NoteGenerationDeepResult,
    bundle: SourceBundle,
    requirement: NoteGenerationRequirement,
    model: KnowledgeModel,
  ): Promise<GenerationCandidateEvaluation> {
    const evaluation: GenerationCandidateEvaluation = await GenerationEvaluator.evaluateStandardCandidate(
      result,
      bundle,
      requirement,
      model,
    );
    const mergeIssues: NoteGenerationIssue[] = GenerationEvaluator.deepMergeIssues(result, bundle, requirement);
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

  static deepMergeIssues(
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
    const formulaBySymbol: Map<string, DeepFormulaDefinition> = new Map<string, DeepFormulaDefinition>();
    for (const section of result.draft.sections) {
      const formulas: DeepFormulaCandidate[] = GenerationEvaluator.deepFormulaCandidates(section.content);
      for (const candidate of formulas) {
        const symbol: string = candidate.symbol;
        const formula: string = candidate.formula;
        const previous: DeepFormulaDefinition | undefined = formulaBySymbol.get(symbol);
        if (previous !== undefined && previous.formula !== formula) {
          const message: string = 'deep sections use inconsistent formula symbols: symbol=' + symbol
            + '; previousFormula=' + previous.formula
            + '; currentFormula=' + formula
            + '; previousSection=' + previous.sectionId
            + '; currentSection=' + section.id;
          issues.push({ stage: 'merge', code: 'DEEP_SYMBOL_DRIFT', severity: 'soft', message: message, repairable: true, sectionId: section.id });
        } else {
          formulaBySymbol.set(symbol, { formula: formula, sectionId: section.id });
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

  static deepFormulaCandidates(content: string): DeepFormulaCandidate[] {
    const candidates: DeepFormulaCandidate[] = [];
    const lines: string[] = content.split('\n');
    let inDisplayFormula: boolean = false;
    for (const rawLine of lines) {
      const trimmed: string = rawLine.trim();
      if (trimmed === '$$') {
        inDisplayFormula = !inDisplayFormula;
        continue;
      }
      if (inDisplayFormula) {
        const candidate: DeepFormulaCandidate | undefined = GenerationEvaluator.parseDeepFormulaCandidate(trimmed);
        if (candidate !== undefined) {
          candidates.push(candidate);
        }
        continue;
      }
      let cursor: number = 0;
      while (cursor < rawLine.length) {
        const openIndex: number = rawLine.indexOf('$', cursor);
        if (openIndex < 0 || rawLine.charAt(openIndex + 1) === '$') {
          break;
        }
        const closeIndex: number = rawLine.indexOf('$', openIndex + 1);
        if (closeIndex < 0) {
          break;
        }
        const candidateText: string = rawLine.substring(openIndex + 1, closeIndex).trim();
        const candidate: DeepFormulaCandidate | undefined = GenerationEvaluator.parseDeepFormulaCandidate(candidateText);
        if (candidate !== undefined) {
          candidates.push(candidate);
        }
        cursor = closeIndex + 1;
      }
    }
    return candidates;
  }

  static parseDeepFormulaCandidate(formula: string): DeepFormulaCandidate | undefined {
    const equalsIndex: number = formula.indexOf('=');
    if (equalsIndex <= 0) {
      return undefined;
    }
    const symbol: string = formula.substring(0, equalsIndex).replace(/&/g, '').trim();
    if (symbol.length === 0 || symbol.indexOf(' ') >= 0 || symbol.indexOf('：') >= 0 || symbol.indexOf(':') >= 0) {
      return undefined;
    }
    if (!/^[A-Za-z\\][A-Za-z0-9_]*(\([^=]*\))?$/.test(symbol)) {
      return undefined;
    }
    return { symbol: symbol, formula: formula.trim() };
  }

  static generationFailureMessage(
    route: NoteGenerationRoute,
    issues: NoteGenerationIssue[],
    progress: NoteGenerationProgress,
  ): string {
    const summary: string = GenerationEvaluator.issueSummary(issues);
    const routeLabel: string = route === 'deep' ? 'deep generation failed' : 'standard generation failed';
    const stopReason: string = progress.stopReason ?? '';
    const stopText: string = stopReason.length > 0 ? stopReason : 'unknown';
    if (summary.length === 0) {
      return routeLabel + ': stop=' + stopText + '; no issue details';
    }
    return routeLabel + ': stop=' + stopText + '; ' + summary;
  }

  static readOnlyVerificationStopReason(issues: NoteGenerationIssue[]): string {
    for (const issue of issues) {
      if (issue.severity === 'hard' && issue.code === 'VERIFIER_UNAVAILABLE') {
        return 'verifier_unavailable';
      }
    }
    for (const issue of issues) {
      if (issue.severity === 'hard' && (issue.stage === 'verifier' || issue.code === 'EVIDENCE_CONTRADICTED'
        || issue.code === 'EVIDENCE_AMBIGUOUS')) {
        return 'content_verification_failed';
      }
    }
    return 'artifact_validation_failed';
  }

  static issueSummary(issues: NoteGenerationIssue[]): string {
    const parts: string[] = [];
    const seen: string[] = [];
    for (const issue of issues) {
      const stage: string = issue.stage ?? '';
      const code: string = issue.code.length > 0 ? issue.code : 'UNKNOWN_ISSUE';
      const message: string = issue.message.trim();
      const location: string = (issue.sectionId ?? '') + ':' + (issue.sourceId ?? '');
      const key: string = code + ':' + stage + ':' + location + ':' + message;
      if (seen.includes(key)) {
        continue;
      }
      seen.push(key);
      let part: string = '[' + code + ']';
      if (stage.length > 0) {
        part += ' stage=' + stage;
      }
      if (issue.sectionId !== undefined) {
        part += ' section=' + issue.sectionId;
      }
      if (issue.sourceId !== undefined) {
        part += ' source=' + issue.sourceId;
      }
      if (message.length > 0) {
        part += ' ' + message;
      }
      parts.push(part);
    }
    return parts.join('; ');
  }

  static generationDiagnostics(
    route: NoteGenerationRoute,
    runId: string,
    issues: NoteGenerationIssue[],
    progress: NoteGenerationProgress,
    errorMessage: string,
  ): string {
    return JSON.stringify({
      route: route,
      runId: runId,
      stopReason: progress.stopReason ?? 'unknown',
      round: progress.round,
      issueCount: issues.length,
      issueFingerprint: progress.issueFingerprint ?? '',
      rollback: progress.rollback,
      tokenBudget: progress.tokenBudget ?? 0,
      estimatedTokenCost: progress.estimatedTokenCost ?? 0,
      errorMessage: errorMessage,
      issues: issues,
    });
  }

  static async finishStandardGeneration(
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
  ): Promise<NoteOutcome> {
    const operationId: string = request.runId + ':' + route;
    const status = candidate === undefined ? 'needs-input' : 'ready-preview';
    const deepResult: NoteGenerationDeepResult | undefined = route === 'deep' && standardResult !== undefined
      ? standardResult as NoteGenerationDeepResult : undefined;
    const diagnostics: string | undefined = route === 'deep' && errorMessage !== undefined
      ? GenerationEvaluator.generationDiagnostics(route, request.runId, issues, progress, errorMessage) : undefined;
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
      diagnostics: diagnostics,
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
        event: 'finished',
        checkpointId: run.bestCheckpointId,
        issueCount: issues.length,
        sourceCount: bundle.fragments.length,
        round: progress.round,
        stopReason: progress.stopReason,
        rollback: progress.rollback,
      });
      evaluatorLog.info('generation progress run=' + request.runId + ' round=' + progress.round.toString()
        + ' stop=' + progress.stopReason + ' rollback=' + progress.rollback.toString());
    }
    if (diagnostics !== undefined) {
      evaluatorLog.warn('generation diagnostics summary run=' + request.runId
        + ' route=' + route
        + ' stopReason=' + (progress.stopReason ?? 'unknown')
        + ' round=' + progress.round.toString()
        + ' issueCount=' + issues.length.toString()
        + ' issueFingerprint=' + (progress.issueFingerprint ?? '')
        + ' rollback=' + progress.rollback.toString()
        + ' tokenBudget=' + (progress.tokenBudget ?? 0).toString()
        + ' estimatedTokenCost=' + (progress.estimatedTokenCost ?? 0).toString());
      GenerationEvaluator.logDiagnosticIssues(request.runId, issues);
    }
    if (candidate === undefined) {
      const needsInput: NoteOutcome = {
        kind: 'needsInput', operationId: operationId, route: 'D1', durationMs: Date.now() - startedAt,
        reason: errorMessage !== undefined ? errorMessage : '生成未完成，需要补充信息',
        issues: issues,
        generation: result,
      };
      return needsInput;
    }
    const preview: NoteOutcome = {
      kind: 'readyPreview', operationId: operationId, route: 'D1', durationMs: Date.now() - startedAt,
      runId: request.runId,
      checkpointId: run.bestCheckpointId !== undefined ? run.bestCheckpointId : '',
      draft: candidate, generation: result,
    };
    return preview;
  }

  static logDiagnosticIssues(runId: string, issues: NoteGenerationIssue[]): void {
    const issueKeys: string[] = [];
    const issueCounts: number[] = [];
    const uniqueIssues: NoteGenerationIssue[] = [];
    for (const issue of issues) {
      const key: string = JSON.stringify(issue);
      const existingIndex: number = issueKeys.indexOf(key);
      if (existingIndex >= 0) {
        issueCounts[existingIndex] += 1;
      } else {
        issueKeys.push(key);
        issueCounts.push(1);
        uniqueIssues.push(issue);
      }
    }
    for (let index: number = 0; index < uniqueIssues.length; index += 1) {
      evaluatorLog.warn('generation diagnostics issue run=' + runId
        + ' occurrence=' + issueCounts[index].toString()
        + ' ' + JSON.stringify(uniqueIssues[index]));
    }
  }

  static completedRun(run: NoteGenerationRun, checkpointId: string | undefined, stopReason: string): NoteGenerationRun {
    return {
      id: run.id,
      originSessionId: run.originSessionId,
      parentConversationRunId: run.parentConversationRunId,
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

  static withTokenBudget(
    request: NoteGenerationRequest,
    tokenBudget: number,
    bundle: SourceBundle,
    requirement: NoteGenerationRequirement,
  ): NoteGenerationRequest {
    return {
      runId: request.runId,
      originSessionId: request.originSessionId,
      parentConversationRunId: request.parentConversationRunId,
      instruction: request.instruction,
      mode: request.mode,
      sources: bundle,
      requirement: requirement,
      targetNoteId: request.targetNoteId,
      baseVersion: request.baseVersion,
      pendingSourceIds: request.pendingSourceIds,
      route: request.route,
      tokenBudget: tokenBudget,
      incrementalPlan: request.incrementalPlan,
      incrementalSections: request.incrementalSections,
    };
  }

  static bundleText(bundle: SourceBundle): string {
    const lines: string[] = [];
    for (const fragment of bundle.fragments) {
      lines.push('[source:' + fragment.id + '] ' + fragment.text);
    }
    return lines.join('\n');
  }
}
