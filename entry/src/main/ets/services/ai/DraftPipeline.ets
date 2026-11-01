/**
 * DraftPipeline.ets — 草稿生成 / 增量重生成 / 恢复 / 取消（从 AiService 抽出）
 *
 * 路径: entry/src/main/ets/services/ai/DraftPipeline.ets
 * 职责: 生成命令装配（generation/regenerate）、readyPreview/needsInput 终态映射、草稿恢复与取消、
 *       上下文预算与 run 恢复事件组装。
 * 依赖: CommandExecutor.dispatchCommand / NoteGenerationRepository / AiServicePorts。
 *
 * 拆出原因（2026-10-31）：AiService 拆分切片 4；草稿生命周期是独立能力域。
 */
// ============================================================================
//  services/AiService.ets — 拍照→AI 整链入口
//  ----------------------------------------------------------------------------
//  职责: 拍照/选图入口与对话笔记草稿、确认编排。
//
//  接口约定:
//    - capture(imageUri, userText?): Promise<KnowledgeUnit>
//        拍照/相册的入口。绝不只走 LLM 对话,必须进入 capture pipeline:
//        CommandExecutor -> image/OCR/MCP 识别 -> 分类 -> 知识结构化 -> 入库。
//
//  UI 端约束: 凡是发图的,都必须调 capture() 而不是 LLM 对话。
//
//  整链调用链:
//    ImageUriResolver.resolve(uri)  // file:// URI 复制到沙箱
//    -> Dispatcher.dispatch(payload)  // 调度中枢
//      -> TypeClassifier.classify()   // OCR + DeepSeek 3×3 分类
//        -> OcrTool.recognize()       // 本地 FastAPI HTTP OCR
//      -> KnowledgeModel.structure()  // 模板填充 + 真值检验
//    -> KnowledgeUnitWriteService.create(unit) // KnowledgeUnit + revision 事务持久化
//  ============================================================================

import {
  KnowledgeUnit,
  ClassificationResult,
  BranchRequest,
  DispatchPayload,
  Logger,
  ImageSearchIndexRegistry,
  NoteDraftReadyEvent,
  NoteGenerationRequest,
  NoteGenerationRoute,
  NoteGenerationProgressSink,
  PreparedCandidate,
  NoteGenerationCheckpoint,
  NoteGenerationResult,
  NoteGenerationRun,
  NoteGenerationRepository as NoteGenerationRepositoryContract,
  SourceFragment,
  SourceBundle,
  NoteContextClarification,
  NoteTopicCandidate,
  NoteGenerationRecovery,
  sourceFingerprint,
  DatabaseHelper,
  buildSourceId,
  IncrementalManifest,
  IncrementalSection,
  parseIncrementalSections,
  buildIncrementalManifest,
  CaptureSetResult,
  CaptureSetItemResult,
  TextPayload,
} from 'common';
import type { NoteBatchOutcome, NoteCommand, NoteOutcome } from 'common';
import { CommandExecutor, NoteDaoInterface } from 'agents';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { ImageUriResolver, ResolvedImageFile } from '../ImageUriResolver';
import { SubjectVocabularyService } from '../SubjectVocabularyService';
import { ConversationRunIdPolicy, SessionIdPolicy } from '../ConversationIdentity';
import { NoteGenerationRepositoryFactory } from '../NoteGenerationRepositoryFactory';
import { AgentMemoryService } from '../AgentMemoryService';
import { RagHit, RagRetrievalService } from '../RagRetrievalService';
import { NoteGenerationContextBuilder } from '../NoteGenerationContextBuilder';
import { CaptureTiming } from './CaptureTiming';
import { AiServicePorts } from './AiServicePorts';
import { ClarificationRegistry } from './ClarificationRegistry';
import { DraftCommitService } from './DraftCommitService';
import { CancellationToken } from 'common';


const log: Logger = new Logger('DraftPipeline');

export class DraftPipeline {
  private readonly context: common.Context | undefined;
  private readonly includeUiEffects: boolean;

  constructor(context: common.Context | undefined, includeUiEffects: boolean) {
    this.context = context;
    this.includeUiEffects = includeUiEffects;
  }

  /**
   * R4：生成前注入「相关旧笔记」片段（本地 FTS 检索，topK=2，单条 clip=400 字）。
   * 失败/未就绪返回空数组，不影响生成。
   */
  private async relatedNoteFragments(query: string, cancellationToken?: CancellationToken): Promise<SourceFragment[]> {
    const fragments: SourceFragment[] = [];
    const trimmed: string = query.trim();
    if (trimmed.length < 8 || cancellationToken?.isCancelled() === true) {
      return fragments;
    }
    try {
      const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
      if (store === null) {
        return fragments;
      }
      const hits: RagHit[] = await RagRetrievalService.search(store, trimmed, 2);
      for (let i = 0; i < hits.length; i++) {
        const hit: RagHit = hits[i];
        const body: string = (hit.title + '\n' + hit.content).trim();
        if (body.length < 12) {
          continue;
        }
        const clipped: string = body.length > 400 ? body.substring(0, 400) : body;
        const fragment: SourceFragment = {
          id: buildSourceId('existing_note', hit.unitId, i),
          kind: 'existing_note',
          originId: hit.unitId,
          sequence: i,
          fingerprint: sourceFingerprint(clipped),
          text: clipped,
        };
        fragments.push(fragment);
      }
    } catch (e) {
      console.warn('[DraftPipeline] related notes retrieval failed: ' + (e as Error).message);
    }
    return fragments;
  }

  async generateNoteDraft(runId: string, instruction: string, sourceText: string): Promise<NoteDraftReadyEvent> {
    return await this.generateNoteDraftWithSources(runId, instruction, sourceText, []);
  }

  async generateNoteDraftWithSources(
    runId: string,
    instruction: string,
    sourceText: string,
    pendingSources: SourceFragment[],
    cancellationToken?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    route: NoteGenerationRoute = 'standard',
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    cancellationToken?.throwIfCancelled();
    DraftPipeline.validateConversationOrigin(originSessionId, parentConversationRunId);
    const fragments: SourceFragment[] = [{
      id: 'conversation:' + runId,
      kind: 'conversation',
      originId: runId,
      sequence: 0,
      fingerprint: sourceFingerprint(sourceText),
      text: sourceText,
    }];
    for (const pendingSource of pendingSources) {
      fragments.push(pendingSource);
    }
    const related: SourceFragment[] = await this.relatedNoteFragments(
      instruction + '\n' + sourceText, cancellationToken);
    for (const relatedFragment of related) {
      fragments.push(relatedFragment);
    }
    const request: NoteGenerationRequest = {
      runId: runId,
      originSessionId: originSessionId,
      parentConversationRunId: parentConversationRunId,
      instruction: instruction,
      mode: 'create',
      sources: {
        fragments: fragments,
      },
      pendingSourceIds: pendingSources.map((fragment): string => fragment.id),
      route: route,
    };
    return await this.dispatchNoteDraft(
      request,
      sourceText,
      request.pendingSourceIds ?? [],
      cancellationToken,
      progressSink,
    );
  }

  private async dispatchNoteDraft(
    request: NoteGenerationRequest,
    payloadText: string,
    pendingSourceIds: string[],
    cancellationToken?: CancellationToken,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    const repository = await NoteGenerationRepositoryFactory.create(AiServicePorts.requireContext(this.context));
    // A3c：草稿生成走命令 seam；readyPreview 携带 draft + checkpointId + runId。
    const command: NoteCommand = {
      kind: 'generation',
      operationId: 'draft-' + request.runId,
      generation: request,
      payload: { kind: 'text', text: payloadText },
    };
    const outcome: NoteOutcome = await new CommandExecutor().dispatchCommand(command, {
      generationRepository: repository,
      cancellationToken: cancellationToken,
      progressSink: progressSink,
      runEventSink: AiServicePorts.buildRunEventSinkIfReady(),
    });
    const previewDraft: KnowledgeUnit | undefined = outcome.draft;
    const previewGeneration: NoteGenerationResult | undefined = outcome.generation;
    const previewCheckpoint: string | undefined = outcome.checkpointId;
    if (outcome.kind !== 'readyPreview' || previewDraft === undefined || previewGeneration === undefined
      || previewCheckpoint === undefined || previewCheckpoint.length === 0) {
      const message: string = outcome.message !== undefined ? outcome.message
        : (outcome.reason !== undefined ? outcome.reason : '草稿生成失败');
      throw new Error(message);
    }
    const candidate: KnowledgeUnit = previewDraft;
    const generation: NoteGenerationResult = previewGeneration;
    const generatedSections: IncrementalSection[] = parseIncrementalSections(candidate.content);
    if (generation.draft !== undefined) {
      for (let index: number = 0; index < generatedSections.length; index += 1) {
        const draftSection = generation.draft.sections[index];
        if (draftSection !== undefined) {
          generatedSections[index].sourceIds = draftSection.sourceIds.slice(0);
        }
      }
    }
    const incrementalManifest: IncrementalManifest = buildIncrementalManifest(
      candidate.id,
      candidate.version,
      generatedSections,
      request.sources.fragments.map((fragment): string => fragment.id),
    );
    generation.incrementalManifest = incrementalManifest;
    const issues = generation.issues;
    let softIssueCount: number = 0;
    for (const issue of issues) {
      if (issue.severity === 'soft') {
        softIssueCount += 1;
      }
    }
    return {
      runId: request.runId,
      originSessionId: request.originSessionId,
      parentConversationRunId: request.parentConversationRunId,
      checkpointId: previewCheckpoint,
      candidateHash: sourceFingerprint(JSON.stringify(candidate)),
      candidate: candidate,
      result: generation,
      sourceCount: request.sources.fragments.length,
      softIssueCount: softIssueCount,
      sourceIds: request.sources.fragments.map((fragment): string => fragment.id),
      pendingSourceIds: this.referencedPendingSourceIdsFromIds(generation, pendingSourceIds),
      incrementalManifest: incrementalManifest,
      expectedVersion: candidate.version,
      incrementalInstruction: request.instruction,
    };
  }

  async generateNoteDraftWithBundle(
    runId: string,
    instruction: string,
    bundle: SourceBundle,
    pendingSourceIds: string[],
    _contextBudgetTokens: number,
    cancellationToken?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    route: NoteGenerationRoute = 'standard',
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    cancellationToken?.throwIfCancelled();
    DraftPipeline.validateConversationOrigin(originSessionId, parentConversationRunId);
    const request: NoteGenerationRequest = {
      runId: runId,
      originSessionId: originSessionId,
      parentConversationRunId: parentConversationRunId,
      instruction: instruction,
      mode: 'create',
      sources: bundle,
      pendingSourceIds: pendingSourceIds,
      route: route,
    };
    const sourceText: string = DraftPipeline.bundleText(bundle);
    return await this.dispatchNoteDraft(request, sourceText, pendingSourceIds, cancellationToken, progressSink);
  }

  async regenerateNoteDraft(
    runId: string,
    noteId: string,
    instruction: string,
    sourceText: string,
    cancellationToken?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    cancellationToken?.throwIfCancelled();
    DraftPipeline.validateConversationOrigin(originSessionId, parentConversationRunId);
    if (noteId.trim().length === 0) {
      throw new Error('增量重生成需要明确 noteId');
    }
    const repository = await NoteGenerationRepositoryFactory.create(AiServicePorts.requireContext(this.context));
    if (repository.getRegenerationBase === undefined) {
      throw new Error('增量重生成基础资料不可用');
    }
    const base = await repository.getRegenerationBase(noteId);
    if (base === undefined) {
      throw new Error('找不到指定 KnowledgeUnit');
    }
    const request: NoteGenerationRequest = {
      runId: runId,
      originSessionId: originSessionId,
      parentConversationRunId: parentConversationRunId,
      instruction: instruction,
      mode: 'regenerate',
      targetNoteId: noteId,
      baseVersion: base.baseVersion,
      sources: { fragments: [{
        id: 'conversation:' + runId,
        kind: 'conversation',
        originId: runId,
        sequence: 0,
        fingerprint: sourceFingerprint(sourceText),
        text: sourceText,
      }] },
    };
    // A3c：增量重生成走命令 seam；readyPreview 携带 draft + checkpointId + runId。
    const command: NoteCommand = {
      kind: 'regenerate',
      operationId: 'regenerate-' + runId,
      generation: request,
      payload: { kind: 'text', text: sourceText },
    };
    const outcome: NoteOutcome = await new CommandExecutor().dispatchCommand(command, {
      generationRepository: repository,
      cancellationToken: cancellationToken,
      progressSink: progressSink,
      runEventSink: AiServicePorts.buildRunEventSinkIfReady(),
    });
    const regenerateDraft: KnowledgeUnit | undefined = outcome.draft;
    const regenerateGeneration: NoteGenerationResult | undefined = outcome.generation;
    const regenerateCheckpoint: string | undefined = outcome.checkpointId;
    if (outcome.kind !== 'readyPreview' || regenerateDraft === undefined
      || regenerateGeneration === undefined || regenerateCheckpoint === undefined
      || regenerateCheckpoint.length === 0) {
      const message: string = outcome.message !== undefined ? outcome.message
        : (outcome.reason !== undefined ? outcome.reason : '增量重生成失败');
      throw new Error(message);
    }
    return {
      runId: runId,
      originSessionId: originSessionId,
      parentConversationRunId: parentConversationRunId,
      checkpointId: regenerateCheckpoint,
      candidateHash: sourceFingerprint(JSON.stringify(regenerateDraft)),
      candidate: regenerateDraft,
      result: regenerateGeneration,
      sourceCount: request.sources.fragments.length,
      softIssueCount: 0,
      sourceIds: regenerateGeneration.sourceIds,
      pendingSourceIds: [],
      incrementalManifest: regenerateGeneration.incrementalManifest,
      incrementalDiff: regenerateGeneration.incrementalDiff,
      expectedVersion: base.baseVersion,
      incrementalInstruction: instruction,
    };
  }

  async restoreDraft(runId: string): Promise<NoteDraftReadyEvent> {
    const repository = await NoteGenerationRepositoryFactory.create(AiServicePorts.requireContext(this.context));
    const recovery: NoteGenerationRecovery | undefined = await repository.restore(runId);
    if (recovery === undefined || recovery.bestCheckpoint === undefined) {
      throw new Error('没有可恢复的笔记草稿');
    }
    if (recovery.run.status === 'cancelled') {
      throw new Error('笔记草稿已取消');
    }
    const checkpoint: NoteGenerationCheckpoint = recovery.bestCheckpoint;
    const candidate: KnowledgeUnit = JSON.parse(checkpoint.documentJson) as KnowledgeUnit;
    const commitKey: string = runId + ':' + checkpoint.id + ':' + checkpoint.candidateHash;
    const committed = await repository.getCommitResult(commitKey);
    if (committed !== undefined && committed.candidateJson !== undefined && committed.candidateJson.length > 0) {
      const committedCandidate: KnowledgeUnit = JSON.parse(committed.candidateJson) as KnowledgeUnit;
      await repository.appendLifecycleLog({ runId: runId, event: 'resumed', checkpointId: checkpoint.id });
      return DraftPipeline.recoveryEvent(recovery, checkpoint, committedCandidate, 'committed');
    }
    await repository.appendLifecycleLog({
      runId: runId,
      event: 'resumed',
      checkpointId: checkpoint.id,
      issueCount: recovery.softIssueCodes.length,
      sourceCount: recovery.sources.fragments.length,
    });
    return DraftPipeline.recoveryEvent(recovery, checkpoint, candidate, recovery.run.status);
  }

  async cancelDraft(runId: string): Promise<void> {
    ClarificationRegistry.activeRuns.get(runId)?.cancel();
    const repository = await NoteGenerationRepositoryFactory.create(AiServicePorts.requireContext(this.context));
    await repository.cancelRun(runId);
    await repository.appendLifecycleLog({ runId: runId, event: 'cancelled' });
  }

  async listRecoverableDrafts(): Promise<NoteGenerationRun[]> {
    const repository = await NoteGenerationRepositoryFactory.create(AiServicePorts.requireContext(this.context));
    const runs: NoteGenerationRun[] = await repository.listRecoverableRuns();
    for (let index: number = 0; index < runs.length; index += 1) {
      const run: NoteGenerationRun = runs[index];
      const clarification: NoteContextClarification | undefined = run.clarification;
      const interruptedSelection: boolean = run.status === 'needs-input'
        && clarification !== undefined
        && clarification.status === 'selected'
        && run.bestCheckpointId === undefined
        && !ClarificationRegistry.activeRuns.has(run.id);
      if (!interruptedSelection) { continue; }
      const recovery: NoteGenerationRecovery | undefined = await repository.restore(run.id);
      if (recovery === undefined) { continue; }
      await ClarificationRegistry.markGenerationFailed(repository, recovery);
      runs[index] = recovery.run;
    }
    return runs;
  }

  async cancelDraftsByParentRun(sessionId: string, parentConversationRunId: string): Promise<void> {
    const repository = await NoteGenerationRepositoryFactory.create(AiServicePorts.requireContext(this.context));
    await repository.cancelIncompleteByParentRun(sessionId, parentConversationRunId);
  }

  private referencedPendingSourceIdsFromIds(result: NoteGenerationResult, pendingSourceIds: string[]): string[] {
    const referenced: string[] = [];
    if (result.draft !== undefined) {
      for (const section of result.draft.sections) {
        for (const sourceId of section.sourceIds) {
          if (pendingSourceIds.includes(sourceId) && !referenced.includes(sourceId)) {
            referenced.push(sourceId);
          }
        }
      }
    }
    return referenced;
  }

  static bundleText(bundle: SourceBundle): string {
    const lines: string[] = [];
    for (const fragment of bundle.fragments) {
      lines.push('[source:' + fragment.id + ']');
      lines.push(fragment.text);
    }
    return lines.join('\n\n');
  }

  static contextBudgetForRecovery(run: NoteGenerationRun): number {
    if (run.contextBudgetTokens !== undefined && run.contextBudgetTokens > 0) {
      return run.contextBudgetTokens;
    }
    return run.tokenBudget;
  }

  static recoveryEvent(
    recovery: NoteGenerationRecovery,
    checkpoint: NoteGenerationCheckpoint,
    candidate: KnowledgeUnit,
    status: string,
  ): NoteDraftReadyEvent {
    const sourceIds: string[] = recovery.run.sourceIds ?? [];
    const pendingSourceIds: string[] = [];
    for (const fragment of recovery.sources.fragments) {
      if (fragment.kind === 'ocr' && sourceIds.includes(fragment.id)
        && (recovery.run.pendingSourceIds ?? []).includes(fragment.id)) {
        pendingSourceIds.push(fragment.id);
      }
    }
    const result: NoteGenerationResult = {
      runId: recovery.run.id,
      route: recovery.run.route,
      status: status as 'running' | 'incomplete' | 'ready-preview' | 'needs-input' | 'failed' | 'cancelled' | 'committed',
      candidate: candidate,
      bestCheckpointId: checkpoint.id,
      issues: [],
      questions: [],
      stopReason: recovery.run.stopReason,
      promptTokens: 0,
      completionTokens: 0,
      sourceIds: sourceIds,
    };
    return {
      runId: recovery.run.id,
      originSessionId: recovery.run.originSessionId,
      parentConversationRunId: recovery.run.parentConversationRunId,
      checkpointId: checkpoint.id,
      candidateHash: checkpoint.candidateHash,
      candidate: candidate,
      result: result,
      sourceCount: recovery.sources.fragments.length,
      softIssueCount: recovery.softIssueCodes.length,
      sourceIds: sourceIds,
      pendingSourceIds: pendingSourceIds,
      incrementalInstruction: recovery.run.instruction,
    };
  }

  static validateConversationOrigin(
    originSessionId: string | undefined,
    parentConversationRunId: string | undefined,
  ): void {
    if (originSessionId === undefined && parentConversationRunId === undefined) { return; }
    if (originSessionId === undefined || parentConversationRunId === undefined) {
      throw new Error('INCOMPLETE_CONVERSATION_DRAFT_ORIGIN');
    }
    SessionIdPolicy.requireValid(originSessionId);
    ConversationRunIdPolicy.requireValid(parentConversationRunId);
  }
}
