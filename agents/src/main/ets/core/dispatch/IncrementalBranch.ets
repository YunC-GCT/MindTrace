/**
 * IncrementalBranch.ets — 增量重生成分支（从 Dispatcher.ets 抽出）
 *
 * 路径: agents/src/main/ets/core/dispatch/IncrementalBranch.ets
 * 职责: 基于已提交笔记做分区增量重生成：加载 base → 计划/锁定 → 局部补丁 → 合并校验 →
 *       保存检查点与 run → 返回 ready-preview / needs-input。
 * 依赖: common 的增量模型（IncrementalBase / Plan / Manifest / Diff）与 GenerationBranch（进度事件）。
 *
 * 边界:
 *   - 不做首次生成（GenerationBranch）与确认提交（PreparedBranch）。
 *   - 行为等价判据：#239 regenerate golden 快照。
 */
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

import { GenerationBranch } from './GenerationBranch';
import { KnowledgeModel } from '../../agents/KnowledgeModel';
import type { DispatchOptions } from './DispatchOptions';
import { copyRegeneratedUnit } from './UnitSupport';

const incrementalLog = new Logger('IncrementalBranch');

export class IncrementalBranch {
  static async dispatchIncrementalGeneration(
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
      const result: NoteGenerationResult = IncrementalBranch.incrementalResult(request, base.manifest, plan, [], 'needs-input');
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
      const result: NoteGenerationResult = IncrementalBranch.incrementalResult(request, manifest, plan, merged.diff, 'needs-input');
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
    const generation: NoteGenerationResult = IncrementalBranch.incrementalResult(request, manifest, plan, merged.diff, 'ready-preview');
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

  static incrementalResult(
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
}
