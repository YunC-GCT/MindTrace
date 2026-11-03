/**
 * NoteRegenerateWorkflow.ets — regenerate（增量重生成）的 workflow（spec 039）
 *
 * 路径: agents/src/main/ets/workflows/NoteRegenerateWorkflow.ets
 * 职责: 基于已提交笔记做分区增量重生成：加载 base → 计划/锁定 → 局部补丁 → 合并校验 →
 *       保存检查点与 run → 返回 ready-preview / needs-input。
 * 依赖: common 的增量模型、agents/KnowledgeModel、core/dispatch/UnitSupport、WorkflowContext。
 * 数据流: CommandExecutor.dispatchCommand() → CommandRouter.resolve()=regenerate → 本类 run()
 *       → runIncremental() → readyPreview / needs-input
 *
 * 边界: 不做首次生成（NoteGenerationWorkflow）与确认提交（NotePreparedWorkflow）；
 *       行为等价判据：#239 regenerate golden 快照。
 */
import {
  KnowledgeUnit,
  BranchRequest,
  NoteGenerationRequest,
  NoteGenerationResult,
  NoteGenerationRun,
  NoteGenerationCheckpoint,
  NoteGenerationProgressEvent,
  standardBudget,
  sourceFingerprint,
  SourceBundle,
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
} from 'common';
import type { NoteCommand, NoteOutcome } from 'common';
import { KnowledgeModel } from '../agents/KnowledgeModel';
import { copyRegeneratedUnit } from '../core/dispatch/UnitSupport';
import type { NoteWorkflow, WorkflowContext } from './WorkflowContext';

export class NoteRegenerateWorkflow implements NoteWorkflow {
  async run(command: NoteCommand, context: WorkflowContext): Promise<NoteOutcome> {
    const request: NoteGenerationRequest = command.generation !== undefined
      ? command.generation
      : { runId: command.operationId, instruction: '', mode: 'regenerate', route: 'light', sources: { fragments: [] } };
    return await this.runIncremental(request, context.request, context);
  }

  private async runIncremental(
    request: NoteGenerationRequest,
    req: BranchRequest,
    context: WorkflowContext,
  ): Promise<NoteOutcome> {
    const startedAt: number = context.startedAt;
    const operationId: string = req.operationId !== undefined ? req.operationId : 'legacy';
    const repository = context.writePorts.generationRepository;
    const failedOutcome = (message: string, code: string, generation?: NoteGenerationResult): NoteOutcome => {
      const outcome: NoteOutcome = {
        kind: 'failed', operationId: operationId, route: 'D1', durationMs: Date.now() - startedAt,
        code: code, message: message,
      };
      if (generation !== undefined) { outcome.generation = generation; }
      return outcome;
    };
    if (request.targetNoteId === undefined || request.targetNoteId.trim().length === 0) {
      return failedOutcome('增量重生成需要明确的 noteId', 'NOTE_ID_REQUIRED');
    }
    if (request.baseVersion === undefined) {
      return failedOutcome('增量重生成需要 baseVersion', 'BASE_VERSION_REQUIRED');
    }
    if (repository === undefined) {
      return failedOutcome('增量重生成基础资料不可用', 'REGENERATION_REPOSITORY_REQUIRED');
    }
    const getBase = repository.getRegenerationBase;
    if (getBase === undefined) {
      return failedOutcome('增量重生成基础资料不可用', 'REGENERATION_REPOSITORY_REQUIRED');
    }
    this.emitProgress(context, {
      phase: 'prepare',
      state: 'running',
      activity: 'collect_sources',
    });
    const base: IncrementalBase | undefined = await getBase(request.targetNoteId);
    if (base === undefined) {
      this.emitProgress(context, {
        phase: 'prepare',
        state: 'failed',
        activity: 'collect_sources',
      });
      return failedOutcome('找不到指定 KnowledgeUnit', 'NOTE_NOT_FOUND');
    }
    if (base.baseVersion !== request.baseVersion) {
      return failedOutcome('笔记版本已变化，请重新预览', 'VERSION_CONFLICT');
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
      this.emitProgress(context, {
        phase: 'prepare',
        state: 'failed',
        activity: 'collect_sources',
      });
      const result: NoteGenerationResult = NoteRegenerateWorkflow.incrementalResult(
        request, base.manifest, plan, [], 'needs-input');
      result.issues.push({ stage: 'plan', code: 'NO_UNLOCKED_TARGET', severity: 'hard', message: '没有可安全重生成的未锁定目标章节', repairable: false });
      return failedOutcome('没有可安全重生成的未锁定目标章节', 'NO_UNLOCKED_TARGET', result);
    }
    const model: KnowledgeModel = context.domain.knowledgeModel
      ?? new KnowledgeModel(undefined, context.runControl.cancellationToken);
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
    await repository.saveRun(run, sourceBundle);
    this.emitProgress(context, {
      phase: 'prepare',
      state: 'success',
      activity: 'collect_sources',
    });
    this.emitProgress(context, {
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
    this.emitProgress(context, {
      phase: 'compose',
      state: 'success',
      activity: 'repair_draft',
    });
    this.emitProgress(context, {
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
      this.emitProgress(context, {
        phase: 'verify',
        state: 'failed',
        activity: 'check_accuracy',
      });
      const result: NoteGenerationResult = NoteRegenerateWorkflow.incrementalResult(
        request, manifest, plan, merged.diff, 'needs-input');
      for (const issue of merged.issues) {
        result.issues.push({ stage: 'merge', code: issue, severity: 'hard', message: issue, repairable: false });
      }
      return failedOutcome(merged.issues.join(';'), '', result);
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
    await repository.saveCheckpoint(checkpoint);
    const generation: NoteGenerationResult = NoteRegenerateWorkflow.incrementalResult(
      request, manifest, plan, merged.diff, 'ready-preview');
    generation.candidate = candidate;
    generation.bestCheckpointId = checkpointId;
    generation.sourceIds = base.manifest.sourceIds.concat(plan.newSourceIds);
    generation.incrementalInstruction = request.instruction;
    await repository.saveRun({
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
    this.emitProgress(context, {
      phase: 'verify',
      state: 'success',
      activity: 'check_accuracy',
    });
    const ready: NoteOutcome = {
      kind: 'readyPreview', operationId: operationId, route: 'D1', durationMs: Date.now() - startedAt,
      runId: request.runId, checkpointId: checkpointId, draft: candidate, generation: generation,
    };
    return ready;
  }

  /** 进度事件：只经 context.domain.progressSink，不依赖 GenerationBranch。 */
  private emitProgress(context: WorkflowContext, event: NoteGenerationProgressEvent): void {
    if (context.domain.progressSink !== undefined) {
      context.domain.progressSink(event);
    }
  }

  private static incrementalResult(
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
