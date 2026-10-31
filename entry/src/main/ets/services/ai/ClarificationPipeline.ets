/**
 * ClarificationPipeline.ets — 笔记澄清（多主题选择）与失败重试（从 AiService 抽出）
 *
 * 路径: entry/src/main/ets/services/ai/ClarificationPipeline.ets
 * 职责: 保存澄清候选（topic 列表）、用户选定主题后生成草稿（含回滚）、断点恢复与失败重试。
 * 依赖: Dispatcher.dispatchCommand / NoteGenerationRepository / ClarificationRegistry。
 *
 * 拆出原因（2026-10-31）：AiService 拆分切片 5；澄清是独立的 HITL 前置流程。
 */
// ============================================================================
//  services/AiService.ets — 拍照→AI 整链入口
//  ----------------------------------------------------------------------------
//  职责: 拍照/选图入口与对话笔记草稿、确认编排。
//
//  接口约定:
//    - capture(imageUri, userText?): Promise<KnowledgeUnit>
//        拍照/相册的入口。绝不只走 LLM 对话,必须进入 capture pipeline:
//        Dispatcher -> image/OCR/MCP 识别 -> 分类 -> 知识结构化 -> 入库。
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
  DispatchRequest,
  DispatchPayload,
  DispatchResult,
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
  IncrementalManifest,
  IncrementalSection,
  parseIncrementalSections,
  buildIncrementalManifest,
  CaptureSetResult,
  CaptureSetItemResult,
  TextPayload,
} from 'common';
import type { NoteBatchOutcome, NoteCommand, NoteOutcome } from 'common';
import { Dispatcher, NoteDaoInterface } from 'agents';
import { common } from '@kit.AbilityKit';
import { ImageUriResolver, ResolvedImageFile } from '../ImageUriResolver';
import { SubjectVocabularyService } from '../SubjectVocabularyService';
import { ConversationRunIdPolicy, SessionIdPolicy } from '../ConversationIdentity';
import { NoteGenerationRepositoryFactory } from '../NoteGenerationRepositoryFactory';
import { AgentMemoryService } from '../AgentMemoryService';
import { NoteGenerationContextBuilder } from '../NoteGenerationContextBuilder';
import { CaptureTiming } from './CaptureTiming';
import { AiServicePorts } from './AiServicePorts';
import { ClarificationRegistry } from './ClarificationRegistry';
import { DraftCommitService } from './DraftCommitService';
import { DraftPipeline } from './DraftPipeline';
import { CancellationToken } from 'common';


const log: Logger = new Logger('ClarificationPipeline');

export class ClarificationPipeline {
  private readonly context: common.Context | undefined;
  private readonly includeUiEffects: boolean;

  constructor(context: common.Context | undefined, includeUiEffects: boolean) {
    this.context = context;
    this.includeUiEffects = includeUiEffects;
  }

  async resumeNoteContextClarification(
    runId: string,
    topicId: string,
    cancellationToken?: CancellationToken,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    // restore() marks running jobs interrupted; reject duplicates before reading.
    if (ClarificationRegistry.activeRuns.has(runId)) {
      throw new Error('TOPIC_CLARIFICATION_IN_PROGRESS');
    }
    const repository = await NoteGenerationRepositoryFactory.create(AiServicePorts.requireContext(this.context));
    const recovery: NoteGenerationRecovery | undefined = await repository.restore(runId);
    if (recovery === undefined) {
      throw new Error('TOPIC_CLARIFICATION_NOT_PENDING');
    }
    if (recovery.run.status === 'cancelled') {
      throw new Error('笔记生成已取消');
    }
    if (recovery.run.clarification === undefined) {
      if (recovery.bestCheckpoint !== undefined
        && (recovery.run.status === 'ready-preview' || recovery.run.status === 'committed')) {
        return await new DraftPipeline(this.context, this.includeUiEffects).restoreDraft(runId);
      }
      throw new Error('TOPIC_CLARIFICATION_NOT_PENDING');
    }
    const clarification: NoteContextClarification = recovery.run.clarification;
    let validTopic: boolean = false;
    for (const candidate of clarification.candidates) {
      if (candidate.id === topicId && candidate.sourceIds.length > 0) { validTopic = true; }
    }
    if (!validTopic) { throw new Error('TOPIC_CLARIFICATION_INVALID_SELECTION'); }
    if (clarification.status === 'selected') {
      if (clarification.selectedTopicId !== topicId) {
        throw new Error('TOPIC_CLARIFICATION_ALREADY_SELECTED');
      }
      if (recovery.bestCheckpoint !== undefined) {
        return await new DraftPipeline(this.context, this.includeUiEffects).restoreDraft(runId);
      }
      return await this.generateSelectedClarificationDraftWithRollback(
        repository,
        recovery,
        topicId,
        false,
        cancellationToken,
        progressSink,
      );
    }
    if (recovery.run.status !== 'needs-input' || clarification.status !== 'pending') {
      throw new Error('TOPIC_CLARIFICATION_NOT_PENDING');
    }
    const selected: NoteContextClarification = {
      runId: clarification.runId,
      instruction: clarification.instruction,
      status: 'selected',
      candidates: clarification.candidates,
      selectedTopicId: topicId,
      createdAt: clarification.createdAt,
    };
    recovery.run.clarification = selected;
    return await this.generateSelectedClarificationDraftWithRollback(
      repository,
      recovery,
      topicId,
      true,
      cancellationToken,
      progressSink,
    );
  }

  private async generateSelectedClarificationDraftWithRollback(
    repository: NoteGenerationRepositoryContract,
    recovery: NoteGenerationRecovery,
    topicId: string,
    persistSelection: boolean,
    cancellationToken?: CancellationToken,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    if (ClarificationRegistry.activeRuns.has(recovery.run.id)) {
      throw new Error('TOPIC_CLARIFICATION_IN_PROGRESS');
    }
    const token: CancellationToken = cancellationToken ?? new CancellationToken();
    ClarificationRegistry.activeRuns.set(recovery.run.id, token);
    try {
      if (persistSelection) {
        recovery.run.updatedAt = Date.now();
        await repository.saveRun(recovery.run, recovery.sources);
      }
      const event: NoteDraftReadyEvent = await this.generateSelectedClarificationDraft(recovery, topicId, token, progressSink);
      token.throwIfCancelled();
      return event;
    } catch (error) {
      if (token.isCancelled()) {
        await repository.cancelRun(recovery.run.id);
      } else {
        await ClarificationRegistry.markGenerationFailed(repository, recovery);
      }
      if (error instanceof Error) {
        throw new Error(error.message);
      }
      throw new Error(JSON.stringify(error));
    } finally {
      ClarificationRegistry.activeRuns.delete(recovery.run.id);
    }
  }

  private async generateSelectedClarificationDraft(
    recovery: NoteGenerationRecovery,
    topicId: string,
    cancellationToken?: CancellationToken,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    const clarification: NoteContextClarification | undefined = recovery.run.clarification;
    if (clarification === undefined) { throw new Error('TOPIC_CLARIFICATION_NOT_PENDING'); }
    let allowedSourceIds: string[] = [];
    let topicName: string = '';
    for (const candidate of clarification.candidates) {
      if (candidate.id === topicId) {
        allowedSourceIds = candidate.sourceIds.slice(0);
        topicName = candidate.displayName;
      }
    }
    if (allowedSourceIds.length === 0) { throw new Error('TOPIC_CLARIFICATION_INVALID_SELECTION'); }
    const fragments: SourceFragment[] = [];
    for (const fragment of recovery.sources.fragments) {
      if (allowedSourceIds.includes(fragment.id)) { fragments.push(fragment); }
    }
    if (fragments.length === 0) { throw new Error('TOPIC_CLARIFICATION_SOURCE_MISSING'); }
    const selectedBundle: SourceBundle = NoteGenerationContextBuilder.trimBundleToBudget(
      { fragments: fragments },
      DraftPipeline.contextBudgetForRecovery(recovery.run),
    );
    if (selectedBundle.fragments.length === 0) { throw new Error('TOPIC_CLARIFICATION_SOURCE_MISSING'); }
    const pendingSourceIds: string[] = [];
    for (const fragment of selectedBundle.fragments) {
      if ((recovery.run.pendingSourceIds ?? []).includes(fragment.id)) { pendingSourceIds.push(fragment.id); }
    }
    return await new DraftPipeline(this.context, this.includeUiEffects).generateNoteDraftWithBundle(
      recovery.run.id,
      clarification.instruction + '\n用户已确认主题：' + topicName + '。仅整理该主题的内容。',
      selectedBundle,
      pendingSourceIds,
      DraftPipeline.contextBudgetForRecovery(recovery.run),
      cancellationToken,
      recovery.run.originSessionId,
      recovery.run.parentConversationRunId,
      recovery.run.route,
      progressSink,
    );
  }

  async saveNoteContextClarification(
    runId: string,
    instruction: string,
    bundle: SourceBundle,
    topics: NoteTopicCandidate[],
    pendingSourceIds: string[],
    contextBudgetTokens: number,
    originSessionId?: string,
    parentConversationRunId?: string,
    route: NoteGenerationRoute = 'standard',
  ): Promise<NoteContextClarification> {
    DraftPipeline.validateConversationOrigin(originSessionId, parentConversationRunId);
    const repository = await NoteGenerationRepositoryFactory.create(AiServicePorts.requireContext(this.context));
    const existing: NoteGenerationRecovery | undefined = await repository.restore(runId);
    if (existing !== undefined && existing.run.clarification !== undefined) {
      return existing.run.clarification;
    }
    const clarification: NoteContextClarification = {
      runId: runId,
      instruction: instruction,
      status: 'pending',
      candidates: topics,
      createdAt: Date.now(),
    };
    const now: number = Date.now();
    const run: NoteGenerationRun = {
      id: runId,
      originSessionId: originSessionId,
      parentConversationRunId: parentConversationRunId,
      route: route,
      status: 'needs-input',
      instruction: instruction,
      sourceCount: bundle.fragments.length,
      tokenBudget: 0,
      contextBudgetTokens: contextBudgetTokens,
      sourceIds: bundle.fragments.map((fragment): string => fragment.id),
      pendingSourceIds: pendingSourceIds,
      sourceSummary: 'topic-clarification-required',
      clarification: clarification,
      createdAt: now,
      updatedAt: now,
    };
    await repository.saveRun(run, bundle);
    return clarification;
  }

  async retryDraft(runId: string): Promise<NoteDraftReadyEvent> {
    const repository = await NoteGenerationRepositoryFactory.create(AiServicePorts.requireContext(this.context));
    const recovery: NoteGenerationRecovery | undefined = await repository.restore(runId);
    if (recovery === undefined) {
      throw new Error('没有可重试的笔记运行');
    }
    if (recovery.bestCheckpoint !== undefined) {
      return await new DraftPipeline(this.context, this.includeUiEffects).restoreDraft(runId);
    }
    const clarification: NoteContextClarification | undefined = recovery.run.clarification;
    if (clarification !== undefined && clarification.status === 'selected'
      && clarification.selectedTopicId !== undefined) {
      return await this.resumeNoteContextClarification(runId, clarification.selectedTopicId);
    }
    let conversationText: string = '';
    const pendingSources: SourceFragment[] = [];
    for (const fragment of recovery.sources.fragments) {
      if (fragment.kind === 'conversation' && conversationText.length === 0) {
        conversationText = fragment.text;
      }
      if (fragment.kind === 'ocr' && (recovery.run.pendingSourceIds ?? []).includes(fragment.id)) {
        pendingSources.push(fragment);
      }
    }
    await repository.appendLifecycleLog({ runId: runId, event: 'retried', sourceCount: recovery.sources.fragments.length });
    return await new DraftPipeline(this.context, this.includeUiEffects).generateNoteDraftWithSources(
      runId,
      recovery.run.instruction,
      conversationText,
      pendingSources,
      undefined,
      recovery.run.originSessionId,
      recovery.run.parentConversationRunId,
      recovery.run.route,
    );
  }
}
