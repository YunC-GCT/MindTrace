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
} from 'common';
import { Dispatcher, NoteDaoInterface } from 'agents';
import { common } from '@kit.AbilityKit';
import { ImageUriResolver, ResolvedImageFile } from './ImageUriResolver';
import { NoteDaoAdapter } from '../adapters/NoteDaoAdapter';
import { SubjectVocabularyService } from './SubjectVocabularyService';
import { ConversationRunIdPolicy, SessionIdPolicy } from './ConversationIdentity';
import { KnowledgeUnitWriteService } from './KnowledgeUnitWriteService';
import { KnowledgeUnitWriteServiceFactory } from './KnowledgeUnitWriteServiceFactory';
import { NoteGenerationRepositoryFactory } from './NoteGenerationRepositoryFactory';
import { AgentMemoryService } from './AgentMemoryService';
import { NoteGenerationContextBuilder } from './NoteGenerationContextBuilder';
import { CancellationToken } from 'common';

const log: Logger = new Logger('AiService');
const captureLog: Logger = new Logger('AICapture');
export class AiService {
  private static readonly activeClarificationRuns: Map<string, CancellationToken> = new Map<string, CancellationToken>();
  private static captureSeq: number = 0;

  // UIAbilityContext 引用,capture() 准备图片文件时用
  private context?: common.UIAbilityContext;

  constructor(context?: common.UIAbilityContext) {
    this.context = context;
  }

  // 拍照/相册入口:把图片处理成 KnowledgeUnit 并持久化
  async capture(imageUri: string, userText?: string): Promise<KnowledgeUnit> {
    const startedAt: number = Date.now();
    const seq: number = ++AiService.captureSeq;
    let resolveMs: number = 0;
    let outcome: string = 'ok';
    const nodeTotals: Map<string, number> = new Map<string, number>();
    const nodeVisits: Map<string, number> = new Map<string, number>();
    const onNodeTiming = (step: string, elapsedMs: number): void => {
      nodeTotals.set(step, (nodeTotals.get(step) ?? 0) + elapsedMs);
      nodeVisits.set(step, (nodeVisits.get(step) ?? 0) + 1);
    };
    log.info('capture start, imageUri=' + imageUri);
    try {
      if (this.context === undefined) {
        throw new Error('AiService.capture 需要 UIAbilityContext 来准备图片文件');
      }

      // 1) 把 file:// URI 复制到沙箱(本地路径,OCR/Dao 都能访问)
      const resolveStartedAt: number = Date.now();
      const resolved: ResolvedImageFile = await new ImageUriResolver(this.context).resolve(imageUri);
      resolveMs = Date.now() - resolveStartedAt;
      log.info('capture 图片已准备,本地路径=' + resolved.localPath);

      // 2) 走整链
      const unit: KnowledgeUnit = await this.processAndPersist({
        kind: 'image',
        imageUri: resolved.localPath,
        userText: userText,
      }, onNodeTiming);

      // 3) 落库后再建文搜图索引：索引失败不影响笔记本身，只记日志
      await this.indexForSearch(resolved.localPath, unit.id);
      return unit;
    } catch (error) {
      outcome = 'error';
      if (error instanceof Error) {
        throw new Error(error.message);
      }
      throw new Error(String(error));
    } finally {
      const totalMs: number = Date.now() - startedAt;
      captureLog.info(AiService.formatCaptureTiming(seq, outcome, resolveMs, nodeTotals, nodeVisits, totalMs));
    }
  }

  // spec 036 阶段 1：一次整理 = 用户选中的 1..N 张图。
  // 与 capture() 的差别只有三处：准备 N 张图 → 走 dispatchSet（一个 set 一个 run，
  // 共享预算与取消）→ 返回逐项回执。单张时语义与 capture() 等价。
  // 切题与跨图合并不在这里（阶段 2/3），本方法只保证「N 张图是一次整理，不是 N 个任务」。
  async captureSet(imageUris: string[], userText?: string, token?: CancellationToken,
    onItem?: (item: CaptureSetItemResult) => void): Promise<CaptureSetResult> {
    const startedAt: number = Date.now();
    const seq: number = ++AiService.captureSeq;
    const context: common.UIAbilityContext = this.requireContext();
    const resolver: ImageUriResolver = new ImageUriResolver(context);
    const items: DispatchPayload[] = [];
    // items[i] 对应用户选中的第几张；准备失败的图不进 items，但必须回到原始下标
    const indexOfItem: number[] = [];
    const localPaths: string[] = [];
    const preFailed: CaptureSetItemResult[] = [];

    // 1) 逐张把 file:// URI 复制到沙箱；单张失败不拖垮整批
    for (let i = 0; i < imageUris.length; i++) {
      try {
        const resolved: ResolvedImageFile = await resolver.resolve(imageUris[i]);
        items.push({ kind: 'image', imageUri: resolved.localPath, userText: userText });
        indexOfItem.push(i);
        localPaths.push(resolved.localPath);
      } catch (error) {
        preFailed.push({
          index: i,
          kind: 'image',
          success: false,
          cancelled: false,
          errorMessage: (error as Error).message,
          durationMs: 0,
        });
      }
    }

    // 2) 一次 set：公共入口 dispatchSet，持久化仍走注入的 dao。
    // 回调时序：准备失败的项不在 items 里，若边跑边透传，它们只能在整批结束后补发，
    // 行序会与本图下标交错。于是全部准备成功时直接透传（逐项真进度）；一旦有准备失败项，
    // 就收集到 merged 后按原始 index 统一回调一次，保证 ①②③ 的编号与顺序一致。
    const canStreamItems: boolean = preFailed.length === 0;
    const dao: NoteDaoInterface = await this.buildNoteDao();
    const dispatcher: Dispatcher = new Dispatcher();
    const run: CaptureSetResult = await dispatcher.dispatchSet({
      source: 'app',
      items: items,
    }, {
      persist: true,
      dao: dao,
      cancellationToken: token,
      subjectVocabulary: await SubjectVocabularyService.list(),
      onItem: (item: CaptureSetItemResult): void => {
        if (canStreamItems && onItem !== undefined) {
          onItem(item);
        }
      },
    });

    // 3) 把 dispatchSet 的结果按原始下标合回（含准备失败项）
    const merged: CaptureSetItemResult[] = [];
    for (let i = 0; i < imageUris.length; i++) {
      merged.push({
        index: i,
        kind: 'image',
        success: false,
        cancelled: false,
        errorMessage: 'not processed',
        durationMs: 0,
      });
    }
    for (let k = 0; k < run.items.length; k++) {
      merged[indexOfItem[run.items[k].index]] = run.items[k];
    }
    for (let k = 0; k < preFailed.length; k++) {
      merged[preFailed[k].index] = preFailed[k];
    }

    // 4) 有准备失败项时，按原始 index 逐项补发一次；无准备失败项时上面已逐项透传
    if (!canStreamItems && onItem !== undefined) {
      for (let i = 0; i < merged.length; i++) {
        onItem(merged[i]);
      }
    }

    // 5) 落库成功的项再建文搜图索引：索引失败只记日志，不影响笔记
    for (let k = 0; k < run.items.length; k++) {
      const item: CaptureSetItemResult = run.items[k];
      if (item.success && item.noteId !== undefined && item.noteId.length > 0) {
        await this.indexForSearch(localPaths[item.index], item.noteId);
      }
    }

    const failed: number = run.failed + preFailed.length;
    const result: CaptureSetResult = {
      total: imageUris.length,
      done: run.done,
      failed: failed,
      cancelled: run.cancelled,
      items: merged,
      durationMs: Date.now() - startedAt,
    };
    log.info('captureSet done, total=' + result.total.toString() + ', done=' + result.done.toString()
      + ', failed=' + failed.toString() + ', cancelled=' + result.cancelled.toString());
    captureLog.info('CAPTURE_SET_TIMING seq=' + seq.toString() + ' total=' + result.total.toString()
      + ' done=' + result.done.toString() + ' failed=' + failed.toString()
      + ' cancelled=' + result.cancelled.toString() + ' totalMs=' + result.durationMs.toString());
    return result;
  }

  private static formatCaptureTiming(
    seq: number,
    outcome: string,
    resolveMs: number,
    nodeTotals: Map<string, number>,
    nodeVisits: Map<string, number>,
    totalMs: number,
  ): string {
    const ocrMs: number = nodeTotals.get('capture') ?? 0;
    const classifyMs: number = nodeTotals.get('classify') ?? 0;
    const draftMs: number = nodeTotals.get('structure') ?? 0;
    const truthCheckMs: number = nodeTotals.get('truth_check') ?? 0;
    const persistMs: number = nodeTotals.get('persist') ?? 0;
    const accountedMs: number = resolveMs + ocrMs + classifyMs + draftMs + truthCheckMs + persistMs;
    const otherMs: number = Math.max(0, totalMs - accountedMs);
    return 'CAPTURE_TIMING seq=' + seq.toString()
      + ' outcome=' + outcome
      + ' resolveMs=' + resolveMs.toString()
      + ' ocrMs=' + ocrMs.toString()
      + ' classifyMs=' + classifyMs.toString()
      + ' draftMs=' + draftMs.toString()
      + ' truthCheckMs=' + truthCheckMs.toString()
      + ' persistMs=' + persistMs.toString()
      + ' otherMs=' + otherMs.toString()
      + ' totalMs=' + totalMs.toString()
      + ' visits=capture:' + (nodeVisits.get('capture') ?? 0).toString()
      + ',classify:' + (nodeVisits.get('classify') ?? 0).toString()
      + ',structure:' + (nodeVisits.get('structure') ?? 0).toString()
      + ',truth_check:' + (nodeVisits.get('truth_check') ?? 0).toString()
      + ',persist:' + (nodeVisits.get('persist') ?? 0).toString();
  }

  /** 把已落库的图片写进 textSearchImage 索引；端口未安装时静默跳过。 */
  private async indexForSearch(localPath: string, unitId: string): Promise<void> {
    if (!ImageSearchIndexRegistry.isInstalled()) {
      log.warn('capture 跳过文搜图索引: 端口未安装');
      return;
    }
    const startedAt: number = Date.now();
    try {
      const ok: boolean = await ImageSearchIndexRegistry.require().insert(localPath);
      log.info('capture 建索引 unitId=' + unitId + ' ok=' + (ok ? '1' : '0')
        + ' ms=' + (Date.now() - startedAt).toString());
    } catch (e) {
      const err: Error = e as Error;
      log.warn('capture 建索引失败 unitId=' + unitId + ' err=' + err.message);
    }
  }

  // 图片识别入口: 只 OCR + 分类，返回识别内容，不生成笔记、不入库
  async analyzeImage(imageUri: string, userText?: string, cancellationToken?: CancellationToken): Promise<ClassificationResult> {
    cancellationToken?.throwIfCancelled();
    log.info('analyzeImage start, imageUri=' + imageUri);
    if (this.context === undefined) {
      throw new Error('AiService.analyzeImage 需要 UIAbilityContext 来准备图片文件');
    }

    const resolved: ResolvedImageFile = await new ImageUriResolver(this.context).resolve(imageUri);
    const req: DispatchRequest = {
      source: 'app',
      payload: {
        kind: 'image',
        imageUri: resolved.localPath,
        userText: userText,
      },
    };

    const dispatcher: Dispatcher = new Dispatcher();
    const result: DispatchResult = await dispatcher.dispatch(req, {
      persist: false,
      includeRawText: true,
      analysisOnly: true,
      cancellationToken: cancellationToken,
    });
    if (!result.success || result.classification === undefined) {
      throw new Error(result.errorMessage ?? '识别失败');
    }
    return result.classification;
  }

  // 内部: 把 entry 端 NoteDao 适配成 agents 端 NoteDaoInterface
  private async buildNoteDao(): Promise<NoteDaoInterface> {
    if (this.context === undefined) {
      throw new Error('AiService.buildNoteDao 需要 UIAbilityContext');
    }
    const service: KnowledgeUnitWriteService = await KnowledgeUnitWriteServiceFactory.create(this.context);
    const adapter: NoteDaoAdapter = new NoteDaoAdapter(service);
    return adapter;
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
    AiService.validateConversationOrigin(originSessionId, parentConversationRunId);
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

  async resumeNoteContextClarification(
    runId: string,
    topicId: string,
    cancellationToken?: CancellationToken,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    // restore() marks running jobs interrupted; reject duplicates before reading.
    if (AiService.activeClarificationRuns.has(runId)) {
      throw new Error('TOPIC_CLARIFICATION_IN_PROGRESS');
    }
    const repository = await NoteGenerationRepositoryFactory.create(this.requireContext());
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
        return await this.restoreDraft(runId);
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
        return await this.restoreDraft(runId);
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
    if (AiService.activeClarificationRuns.has(recovery.run.id)) {
      throw new Error('TOPIC_CLARIFICATION_IN_PROGRESS');
    }
    const token: CancellationToken = cancellationToken ?? new CancellationToken();
    AiService.activeClarificationRuns.set(recovery.run.id, token);
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
        await this.markClarificationGenerationFailed(repository, recovery);
      }
      if (error instanceof Error) {
        throw new Error(error.message);
      }
      throw new Error(JSON.stringify(error));
    } finally {
      AiService.activeClarificationRuns.delete(recovery.run.id);
    }
  }

  private async markClarificationGenerationFailed(
    repository: NoteGenerationRepositoryContract,
    recovery: NoteGenerationRecovery,
  ): Promise<void> {
    const clarification: NoteContextClarification | undefined = recovery.run.clarification;
    if (clarification === undefined || clarification.status !== 'selected') { return; }
    const latest: NoteGenerationRecovery | undefined = await repository.restore(recovery.run.id);
    if (latest === undefined || latest.run.status === 'cancelled' || latest.run.status === 'committed') { return; }
    // A failed execution does not revoke the user's confirmed topic.
    latest.run.status = 'failed';
    latest.run.stopReason = latest.run.stopReason ?? 'topic_generation_failed';
    latest.run.updatedAt = Date.now();
    await repository.saveRun(latest.run, latest.sources);
    recovery.run = latest.run;
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
      AiService.contextBudgetForRecovery(recovery.run),
    );
    if (selectedBundle.fragments.length === 0) { throw new Error('TOPIC_CLARIFICATION_SOURCE_MISSING'); }
    const pendingSourceIds: string[] = [];
    for (const fragment of selectedBundle.fragments) {
      if ((recovery.run.pendingSourceIds ?? []).includes(fragment.id)) { pendingSourceIds.push(fragment.id); }
    }
    return await this.generateNoteDraftWithBundle(
      recovery.run.id,
      clarification.instruction + '\n用户已确认主题：' + topicName + '。仅整理该主题的内容。',
      selectedBundle,
      pendingSourceIds,
      AiService.contextBudgetForRecovery(recovery.run),
      cancellationToken,
      recovery.run.originSessionId,
      recovery.run.parentConversationRunId,
      recovery.run.route,
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
    const repository = await NoteGenerationRepositoryFactory.create(this.requireContext());
    const result: DispatchResult = await new Dispatcher().dispatch({
      source: 'app',
      payload: { kind: 'text', text: payloadText },
      generation: request,
    }, {
      persist: false,
      generationRepository: repository,
      cancellationToken: cancellationToken,
      progressSink: progressSink,
    });
    if (!result.success || result.generation === undefined || result.data === undefined || result.generation.bestCheckpointId === undefined) {
      throw new Error(result.errorMessage ?? '草稿生成失败');
    }
    const candidate: KnowledgeUnit = result.data;
    const generation: NoteGenerationResult = result.generation;
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
    const issues = result.generation.issues;
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
      checkpointId: result.generation.bestCheckpointId,
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
    AiService.validateConversationOrigin(originSessionId, parentConversationRunId);
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
    const sourceText: string = AiService.bundleText(bundle);
    return await this.dispatchNoteDraft(request, sourceText, pendingSourceIds, cancellationToken, progressSink);
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
    AiService.validateConversationOrigin(originSessionId, parentConversationRunId);
    const repository = await NoteGenerationRepositoryFactory.create(this.requireContext());
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
    AiService.validateConversationOrigin(originSessionId, parentConversationRunId);
    if (noteId.trim().length === 0) {
      throw new Error('增量重生成需要明确 noteId');
    }
    const repository = await NoteGenerationRepositoryFactory.create(this.requireContext());
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
    const result: DispatchResult = await new Dispatcher().dispatch({
      source: 'app',
      payload: { kind: 'text', text: sourceText },
      generation: request,
    }, {
      persist: false,
      generationRepository: repository,
      cancellationToken: cancellationToken,
      progressSink: progressSink,
    });
    if (!result.success || result.data === undefined || result.generation === undefined
      || result.generation.bestCheckpointId === undefined) {
      throw new Error(result.errorMessage ?? '增量重生成失败');
    }
    return {
      runId: runId,
      originSessionId: originSessionId,
      parentConversationRunId: parentConversationRunId,
      checkpointId: result.generation.bestCheckpointId,
      candidateHash: sourceFingerprint(JSON.stringify(result.data)),
      candidate: result.data,
      result: result.generation,
      sourceCount: request.sources.fragments.length,
      softIssueCount: 0,
      sourceIds: result.generation.sourceIds,
      pendingSourceIds: [],
      incrementalManifest: result.generation.incrementalManifest,
      incrementalDiff: result.generation.incrementalDiff,
      expectedVersion: base.baseVersion,
      incrementalInstruction: instruction,
    };
  }

  async restoreDraft(runId: string): Promise<NoteDraftReadyEvent> {
    const repository = await NoteGenerationRepositoryFactory.create(this.requireContext());
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
      return AiService.recoveryEvent(recovery, checkpoint, committedCandidate, 'committed');
    }
    await repository.appendLifecycleLog({
      runId: runId,
      event: 'resumed',
      checkpointId: checkpoint.id,
      issueCount: recovery.softIssueCodes.length,
      sourceCount: recovery.sources.fragments.length,
    });
    return AiService.recoveryEvent(recovery, checkpoint, candidate, recovery.run.status);
  }

  async cancelDraft(runId: string): Promise<void> {
    AiService.activeClarificationRuns.get(runId)?.cancel();
    const repository = await NoteGenerationRepositoryFactory.create(this.requireContext());
    await repository.cancelRun(runId);
    await repository.appendLifecycleLog({ runId: runId, event: 'cancelled' });
  }

  async retryDraft(runId: string): Promise<NoteDraftReadyEvent> {
    const repository = await NoteGenerationRepositoryFactory.create(this.requireContext());
    const recovery: NoteGenerationRecovery | undefined = await repository.restore(runId);
    if (recovery === undefined) {
      throw new Error('没有可重试的笔记运行');
    }
    if (recovery.bestCheckpoint !== undefined) {
      return await this.restoreDraft(runId);
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
    return await this.generateNoteDraftWithSources(
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

  async listRecoverableDrafts(): Promise<NoteGenerationRun[]> {
    const repository = await NoteGenerationRepositoryFactory.create(this.requireContext());
    const runs: NoteGenerationRun[] = await repository.listRecoverableRuns();
    for (let index: number = 0; index < runs.length; index += 1) {
      const run: NoteGenerationRun = runs[index];
      const clarification: NoteContextClarification | undefined = run.clarification;
      const interruptedSelection: boolean = run.status === 'needs-input'
        && clarification !== undefined
        && clarification.status === 'selected'
        && run.bestCheckpointId === undefined
        && !AiService.activeClarificationRuns.has(run.id);
      if (!interruptedSelection) { continue; }
      const recovery: NoteGenerationRecovery | undefined = await repository.restore(run.id);
      if (recovery === undefined) { continue; }
      await this.markClarificationGenerationFailed(repository, recovery);
      runs[index] = recovery.run;
    }
    return runs;
  }

  async cancelDraftsByParentRun(sessionId: string, parentConversationRunId: string): Promise<void> {
    const repository = await NoteGenerationRepositoryFactory.create(this.requireContext());
    await repository.cancelIncompleteByParentRun(sessionId, parentConversationRunId);
  }

  async updateDraftCheckpoint(event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<NoteGenerationCheckpoint> {
    const repository = await NoteGenerationRepositoryFactory.create(this.requireContext());
    const recovery = await repository.restore(event.runId);
    if (recovery === undefined) {
      throw new Error('草稿运行不存在');
    }
    let previous: NoteGenerationCheckpoint | undefined = undefined;
    for (const checkpoint of recovery.checkpoints) {
      if (checkpoint.id === event.checkpointId) {
        previous = checkpoint;
        break;
      }
    }
    if (previous === undefined || previous.candidateHash !== event.candidateHash) {
      throw new Error('草稿检查点已变化');
    }
    const updated: NoteGenerationCheckpoint = {
      id: event.runId + ':user-edit',
      runId: previous.runId,
      iteration: previous.iteration + 1,
      stage: previous.stage,
      parentId: previous.id,
      candidateHash: sourceFingerprint(JSON.stringify(candidate)),
      documentJson: JSON.stringify(candidate),
      accepted: previous.accepted,
      issueCodes: previous.issueCodes,
      createdAt: previous.createdAt,
    };
    await repository.saveCheckpoint(updated);
    return updated;
  }

  async confirmDraft(event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit> {
    const checkpoint: NoteGenerationCheckpoint = await this.updateDraftCheckpoint(event, candidate);
    const repository = await NoteGenerationRepositoryFactory.create(this.requireContext());
    const dao: NoteDaoInterface = await this.buildNoteDao();
    const prepared: PreparedCandidate = {
      runId: event.runId,
      checkpointId: checkpoint.id,
      candidateHash: sourceFingerprint(JSON.stringify(candidate)),
      candidate: candidate,
      commitKey: event.runId + ':' + checkpoint.id + ':' + sourceFingerprint(JSON.stringify(candidate)),
      sourceIds: event.sourceIds,
      pendingSourceIds: event.pendingSourceIds,
      expectedVersion: event.expectedVersion,
      updateExisting: event.result.incrementalPlan !== undefined && event.expectedVersion !== undefined,
      incrementalManifest: event.incrementalManifest,
      incrementalDiff: event.incrementalDiff,
    };
    const result: DispatchResult = await new Dispatcher().dispatch({
      source: 'app',
      payload: { kind: 'text', text: candidate.content },
      preparedCandidate: prepared,
    }, { persist: true, dao: dao, generationRepository: repository });
    if (!result.success || result.data === undefined) {
      const prefix: string = result.errorCode === 'VERSION_CONFLICT' ? 'VERSION_CONFLICT: ' : '';
      throw new Error(prefix + (result.errorMessage ?? '笔记确认失败'));
    }
    if (event.pendingSourceIds !== undefined && event.pendingSourceIds.length > 0) {
      try {
        const pendingMemoryIds: string[] = await this.resolvePendingMemoryIds(
          repository,
          event.runId,
          event.pendingSourceIds,
        );
        await new AgentMemoryService(this.requireContext()).markPendingMaterialsUsed(pendingMemoryIds);
      } catch (e) {
        log.warn('pending source cleanup warning runId=' + event.runId + ' count=' + event.pendingSourceIds.length.toString());
      }
    }
    return result.data;
  }

  private async resolvePendingMemoryIds(
    repository: NoteGenerationRepositoryContract,
    runId: string,
    referencedFragmentIds: string[],
  ): Promise<string[]> {
    const recovery: NoteGenerationRecovery | undefined = await repository.restore(runId);
    if (recovery === undefined) {
      return referencedFragmentIds.slice(0);
    }
    const result: string[] = [];
    for (const fragment of recovery.sources.fragments) {
      if (fragment.kind !== 'ocr' || !referencedFragmentIds.includes(fragment.id)) {
        continue;
      }
      const provenanceIds: string[] = fragment.provenanceIds ?? [fragment.id];
      for (const provenanceId of provenanceIds) {
        if (!result.includes(provenanceId)) { result.push(provenanceId); }
      }
    }
    return result.length > 0 ? result : referencedFragmentIds.slice(0);
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

  private static bundleText(bundle: SourceBundle): string {
    const lines: string[] = [];
    for (const fragment of bundle.fragments) {
      lines.push('[source:' + fragment.id + ']');
      lines.push(fragment.text);
    }
    return lines.join('\n\n');
  }

  private static contextBudgetForRecovery(run: NoteGenerationRun): number {
    if (run.contextBudgetTokens !== undefined && run.contextBudgetTokens > 0) {
      return run.contextBudgetTokens;
    }
    return run.tokenBudget;
  }

  private static recoveryEvent(
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

  private static validateConversationOrigin(
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

  // 内部: 调度 -> 校验 -> 入库
  private async processAndPersist(
    payload: DispatchPayload,
    onNodeTiming?: (step: string, elapsedMs: number) => void,
  ): Promise<KnowledgeUnit> {
    // 1) 构造调度请求
    const req: DispatchRequest = { source: 'app', payload };

    // 2) 准备 NoteDao 适配器, 注入到 Dispatcher 持久化选项
    const dao: NoteDaoInterface = await this.buildNoteDao();

    // 3) 通过 Dispatcher 公共入口执行整链并显式注入 dao
    const dispatcher: Dispatcher = new Dispatcher();
    const result: DispatchResult = await dispatcher.dispatch(req, {
      persist: true,
      dao: dao,
      subjectVocabulary: await SubjectVocabularyService.list(),
      onNodeTiming: onNodeTiming,
    });
    if (!result.success) {
      throw new Error('处理失败: ' + (result.errorMessage ?? 'Capture workflow failed'));
    }
    const unit: KnowledgeUnit | undefined = result.data;
    if (unit === undefined) {
      throw new Error('处理失败: Dispatcher 未生成 KnowledgeUnit');
    }

    // 4) Only metadata is logged; note content never enters production logs.
    log.info('done, noteId=' + unit.id + ', category=' + unit.category);

    return unit;
  }

  private requireContext(): common.UIAbilityContext {
    if (this.context === undefined) {
      throw new Error('AiService 需要 UIAbilityContext');
    }
    return this.context;
  }
}
