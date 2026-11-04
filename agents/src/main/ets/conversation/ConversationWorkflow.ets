/**
 * ConversationWorkflow.ets — 浮窗对话 StateGraph 编排
 *
 * 路径: entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets
 * 职责: 编排 text/image/regenerate 三种 ConversationRequest,经 classify_intent → load_reply_context → save_reply_input → (stream_reply|complete_reply|image_reply|note_reply|regenerate_reply) → END
 * 依赖: common (KnowledgeUnit/ClassificationResult/LlmConfig/LlmError/Logger/StateGraph/LlmErrorBodyFormatter); ../services (AiService/AgentMemoryService/IntentClassifier/ReplyService/StreamErrorText)
 *
 * 数据流:
 *   AgentFloatWindow.realReply → workflow.run(request) → buildGraph (条件边分发) → ReplyService.complete/stream (LLM 调用) → updateAiMsg(ConversationMessageEvent) → ChatMsg 更新 → finishAiMsg → safeSaveAssistantMessage (持久化)
 *
 * 设计要点:
 *   - copyState 严格字段复制 (无 map+spread) — 任意 P1 字段须显式添加,避免漏字段
 *   - isNetworkError 与 ReplyService.isNetworkError 范围不同:本类含 STREAM_FAILED + 12 个 substring fallback,顶层 catch 用
 *   - 笔记生成与指令解析在 ConversationNoteHandler；本类只负责图装配与生命周期
 *   - 错误消息经 LlmErrorBodyFormatter.redactSensitiveText 脱敏后再展示给用户,防止 Bearer / api-key / sk-xxx 泄露
 *
 * ArkTS 1.1 strict 适配:
 *   - StateGraph<Node, Edge> 泛型参数显式标注 (避免 arkts-no-inferred-generic-params)
 *   - catch 块统一用 ConversationWorkflow.errorMessage(e) 兜底,不写 catch (e: Error)
 *   - copyState 用显式字段复制,不写解构赋值
 */

import {
  KnowledgeUnit,
  ClassificationResult,
  LlmErrorBodyFormatter,
  LlmError,
  Logger,
  StateGraph,
} from 'common';
import { ReplyContext } from '../chat/IntentClassifier';
import type { TextIntent } from '../chat/IntentClassifier';
import { AppIntentRouter } from '../chat/AppIntentRouter';
import type { AppIntentDecision } from '../chat/AppIntentRules';
import {
  ConversationProgressStep,
  ConversationState,
  ConversationStep,
  ConversationRequest,
  ChatMessageOrigin,
  ChatMessageOutcome,
} from './ConversationState';
import { ConversationMessageEvent, ConversationWorkflowCallbacks } from './ConversationTypes';
import { applyEvidenceToAnswer, evidenceFooter, matchesFallbackShape } from './ConversationFormatting';
import type { StreamReplyResult } from '../chat/ReplyService';
import { streamErrorText } from '../chat/StreamErrorText';
import {
  NoteDraftReadyEvent,
  NoteContextClarification,
  NoteGenerationProgressEvent,
  NoteGenerationProgressSink,
  NoteGenerationRoute,
  NoteGenerationRun,
  SourceFragment,
  sourceFingerprint,
} from 'common';
import type { StreamEvent } from 'common';
import { NoteEvidenceContext } from 'common';
import { NoteGenerationContextResult } from 'common';
import type { NoteEvidencePort, NoteEvidenceStreamFilterPort } from 'common';
import type { IConversationDraftServicePort, IConversationMemoryServicePort } from './ConversationServicePorts';
import { NoteReviewAnswer } from 'common';
import type { NoteReviewFinalization, NoteReviewPlan, NoteReviewPort } from 'common';
import { ConversationRunRef } from 'common';
import { requireConversationRunRef } from 'common';
import { CancellationToken } from 'common';
import { ConversationDraftWorkflow, IConversationDraftWorkflowHost } from './ConversationDraftWorkflow';
import { ConversationMemoryProjection, IConversationMemoryProjectionHost } from './ConversationMemoryProjection';
import { ConversationRunRegistry } from './ConversationRunRegistry';
import { ConversationReviewHandler } from './ConversationReviewHandler';
import { ConversationNoteHandler } from './ConversationNoteHandler';
import { ConversationReplyHandler } from './ConversationReplyHandler';
import type { ImageNoteReplyResult } from './ConversationReplyHandler';
import type { IConversationNodeHost } from './ConversationNodeHost';
import {
  ConversationWorkflowPorts,
  IConversationCapturePort,
  IConversationIntentPort,
  IConversationNoteRoutePort,
  IConversationReplyPort,
  IConversationToolPort,
} from './ConversationWorkflowPorts';

const workflowLog: Logger = new Logger('ConversationWorkflow');

/** 触发 recoverStreamReply 的路径: empty=流正常但内容为空; interrupted=有部分内容后断流; throw=stream 抛异常 */
/**
 * StreamTiming 观测口径 (与 @ship 的指标表契约对齐, 仅观测不改业务):
 *   - path=text|ocr|recover
 *   - usedFallback=true|false|unknown —— unknown 表示拿不到 streamResult 或 complete() 无标记,
 *     聚合时必须单列一档, 不允许并入 false (否则"未降级"组里躺着没测过的样本)
 *   - text/ocr: firstChunkMs totalMs chars outcome interrupted
 *   - recover : recoverMs (不带 firstChunkMs/totalMs —— 同一数值挂两个名字必被误聚合)
 *   - sessionId/runId 取自已存在的 ConversationRunRef, 供 @ship 按会话聚合
 *   - 失败时 firstChunkMs=-1 (0 是合法首字延迟, 不能当哨兵)
 */

export class ConversationWorkflow implements IConversationDraftWorkflowHost, IConversationMemoryProjectionHost, IConversationNodeHost {
  private cbs: ConversationWorkflowCallbacks;
  private readonly ports: ConversationWorkflowPorts;
  private readonly intentClassifier: IConversationIntentPort;
  private readonly appIntentRouter: AppIntentRouter = new AppIntentRouter();
  private readonly replyService: IConversationReplyPort;
  private readonly toolReplyService: IConversationToolPort | undefined;
  private readonly capturePortRef: IConversationCapturePort;
  private readonly noteRoute: IConversationNoteRoutePort;
  private evidenceService: NoteEvidencePort | null = null;
  private reviewService: NoteReviewPort | null = null;
  private readonly runs: ConversationRunRegistry = new ConversationRunRegistry();
  private readonly draftWorkflow: ConversationDraftWorkflow;
  private readonly memoryProjection: ConversationMemoryProjection;
  private readonly reviewNodes: ConversationReviewHandler;
  private readonly noteHandler: ConversationNoteHandler;
  private readonly replyHandler: ConversationReplyHandler;

  constructor(callbacks: ConversationWorkflowCallbacks, ports: ConversationWorkflowPorts) {
    this.cbs = callbacks;
    this.ports = ports;
    const resolvedPorts: ConversationWorkflowPorts = ports;
    this.intentClassifier = resolvedPorts.intent;
    this.replyService = resolvedPorts.reply;
    this.toolReplyService = resolvedPorts.toolReply;
    this.capturePortRef = resolvedPorts.capture;
    this.noteRoute = resolvedPorts.noteRoute;
    this.draftWorkflow = ConversationDraftWorkflow.create(this);
    this.memoryProjection = ConversationMemoryProjection.create(this);
    this.reviewNodes = new ConversationReviewHandler(this);
    this.noteHandler = new ConversationNoteHandler(this);
    this.replyHandler = new ConversationReplyHandler(this);
  }

  nodeCallbacks(): ConversationWorkflowCallbacks { return this.cbs; }

  replyPort(): IConversationReplyPort { return this.replyService; }

  reviewPort(): NoteReviewPort { return this.getReviewService(); }

  capturePort(): IConversationCapturePort { return this.capturePortRef; }

  reviewHandler(): ConversationReviewHandler { return this.reviewNodes; }

  toolReplyPort(): IConversationToolPort | undefined { return this.toolReplyService; }

  evidencePort(): NoteEvidencePort { return this.getEvidenceService(); }

  rawErrorMessage(error: Object): string { return ConversationWorkflow.rawErrorMessage(error); }

  errorCodeOf(error: Object): number { return ConversationWorkflow.errorCode(error); }

  userFacingError(error: Object): string { return ConversationWorkflow.userFacingWorkflowError(error); }

  failureOutcome(error: Object): ChatMessageOutcome { return ConversationWorkflow.failureOutcome(error); }

  intentPort(): IConversationIntentPort { return this.intentClassifier; }

  errorMessage(error: Object): string { return ConversationWorkflow.errorMessage(error); }

  draftService(): IConversationDraftServicePort { return ConversationWorkflow.requireDraftService(this.ports); }

  acceptsDraftRun(ref: ConversationRunRef): boolean { return this.cbs.isCurrentRun(ref); }

  publishDraft(ref: ConversationRunRef, event: NoteDraftReadyEvent): void { this.cbs.onDraftReady(ref, event); }

  async addDraftMessage(
    ref: ConversationRunRef,
    content: string,
    origin: ChatMessageOrigin,
    outcome: ChatMessageOutcome,
  ): Promise<void> {
    await this.addAiMessage(ref, content, origin, outcome);
  }

  draftOrigin(ref: ConversationRunRef): ChatMessageOrigin { return this.originFor(ref); }

  memoryService(): IConversationMemoryServicePort { return ConversationWorkflow.requireMemoryService(this.ports); }

  acceptsMemoryRun(ref: ConversationRunRef): boolean { return this.cbs.isCurrentRun(ref); }

  memoryOrigin(ref: ConversationRunRef): ChatMessageOrigin { return this.originFor(ref); }

  async commitMemoryHistory(ref: ConversationRunRef): Promise<boolean> {
    return await this.cbs.commitHistory(ref);
  }

  userMessageId(ref: ConversationRunRef): number { return this.cbs.getUserMessageId(ref); }

  reportMemoryDiagnostic(ref: ConversationRunRef, diagnostic: string): void {
    this.cbs.reportDiagnostic(ref, diagnostic);
  }

  memoryCancellationToken(ref: ConversationRunRef): CancellationToken | undefined {
    return this.cancellationToken(ref);
  }

  async run(request: ConversationRequest, runRef: ConversationRunRef): Promise<void> {
    requireConversationRunRef(runRef);
    if (!this.cbs.isCurrentRun(runRef)) {
      throw new Error('STALE_CONVERSATION_RUN');
    }
    const cancellationToken: CancellationToken | undefined = this.cbs.getCancellationToken(runRef);
    if (cancellationToken === undefined) {
      throw new Error('STALE_CONVERSATION_RUN');
    }
    this.runs.begin(runRef, request.kind === 'image'
      ? 'image'
      : request.kind === 'regenerate' ? 'note-regeneration' : 'chat', cancellationToken);
    const removeCancellationHook: () => void = this.cbs.registerCancellationHook(runRef, (): void => {
      this.runs.dropCancellation(runRef);
    });
    const initial: ConversationState = {
      request: request,
      runRef: runRef,
      currentStep: 'START',
    };
    const graph: StateGraph<ConversationState, ConversationStep> = this.buildGraph();
    workflowLog.info('run start kind=' + request.kind);
    this.cbs.onStart(runRef);
    try {
      await graph.run(initial);
    } catch (error) {
      this.reportRunError(runRef, error);
      throw new Error(ConversationWorkflow.errorMessage(error));
    } finally {
      this.cbs.onFinish(runRef);
      removeCancellationHook();
      this.runs.end(runRef);
      workflowLog.info('run finish kind=' + request.kind);
    }
  }

  async confirmDraft(ref: ConversationRunRef, event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit> {
    // Ownership validation lives in ConversationDraftWorkflow. It performs the
    // persisted-event check before confirmation (the former inline seam was:
    // const persistedEvent: NoteDraftReadyEvent = await service.restoreDraft(event.runId);
    // this.requireDraftOwnership(ref, persistedEvent);
    return await this.draftWorkflow.confirm(ref, event, candidate);
  }

  async restoreDraft(ref: ConversationRunRef, runId: string): Promise<NoteDraftReadyEvent> {
    return await this.draftWorkflow.restore(ref, runId);
  }

  async cancelDraft(ref: ConversationRunRef, runId: string): Promise<void> {
    await this.draftWorkflow.cancel(ref, runId);
  }

  async regenerateNote(ref: ConversationRunRef, noteId: string, instruction: string): Promise<void> {
    if (noteId.trim().length === 0) {
      throw new Error('增量重生成需要明确 noteId');
    }
    await this.run({ kind: 'regenerate', noteId: noteId, userContent: instruction }, ref);
  }

  async requestRegeneration(ref: ConversationRunRef, noteReference: string, noteIds: string[], instruction: string): Promise<void> {
    const candidates: string[] = [];
    for (const noteId of noteIds) {
      if (!candidates.includes(noteId)) {
        candidates.push(noteId);
      }
    }
    if (candidates.length !== 1 || candidates[0] !== noteReference) {
      await this.addAiMessage(ref, '请先选择要修改的明确笔记，再提出增量修改要求。', this.originFor(ref), 'failed');
      return;
    }
    await this.regenerateNote(ref, candidates[0], instruction);
  }

  async retryDraft(ref: ConversationRunRef, runId: string): Promise<NoteDraftReadyEvent> {
    return await this.draftWorkflow.retry(ref, runId);
  }

  async resumeNoteContextClarification(
    ref: ConversationRunRef,
    runId: string,
    topicId: string,
  ): Promise<NoteDraftReadyEvent> {
    const event: NoteDraftReadyEvent = await this.capturePortRef.resumeNoteContextClarification(
      runId,
      topicId,
      this.cbs.getCancellationToken(ref),
      this.noteGenerationProgressSink(ref),
    );
    this.cbs.onDraftReady(ref, event);
    this.cbs.completeProgress(ref);
    return event;
  }

  async listRecoverableDrafts(): Promise<NoteGenerationRun[]> {
    return await this.draftWorkflow.listRecoverable();
  }

  /** Chat 工具回复默认关闭；开启后 text 请求走 tool_reply（非流式）。 */
  private toolReplyEnabled(): boolean {
    return this.toolReplyService !== undefined && this.toolReplyService.isEnabled();
  }

  private buildGraph(): StateGraph<ConversationState, ConversationStep> {
    const graph: StateGraph<ConversationState, ConversationStep> =
      new StateGraph<ConversationState, ConversationStep>('START', 'END');
    graph.addNode('classify_intent', async (input: ConversationState): Promise<ConversationState> => {
      this.setStep(input.runRef, 'intent_check');
      const token = this.cancellationToken(input.runRef);
      const decision: AppIntentDecision = await this.appIntentRouter.classify(
        input.request.userContent, false, token);
      workflowLog.info('intent kind=' + decision.kind + ' source=' + decision.source
        + ' confidence=' + decision.confidence.toString() + ' reason=' + decision.reason);
      const next: ConversationState = this.copyState(input, 'classify_intent');
      next.intent = decision.kind === 'note_generate' ? 'note_generation' : 'chat';
      next.appIntent = decision.kind;
      next.appIntentConfidence = decision.confidence;
      next.appIntentSource = decision.source;
      next.appIntentClarify = decision.kind === 'clarify';
      return next;
    });
    graph.addNode('classify_image_intent', async (input: ConversationState): Promise<ConversationState> => {
      this.setStep(input.runRef, 'intent_check');
      const decision: AppIntentDecision = await this.appIntentRouter.classify(
        input.request.userContent, true, this.cancellationToken(input.runRef));
      workflowLog.info('image intent kind=' + decision.kind + ' source=' + decision.source
        + ' confidence=' + decision.confidence.toString() + ' reason=' + decision.reason);
      const next: ConversationState = this.copyState(input, 'classify_image_intent');
      next.intent = decision.kind === 'image_note' ? 'note_generation' : 'chat';
      next.appIntent = decision.kind;
      next.appIntentConfidence = decision.confidence;
      next.appIntentSource = decision.source;
      next.appIntentClarify = decision.kind === 'clarify';
      return next;
    });
    graph.addNode('clarify_reply', async (input: ConversationState): Promise<ConversationState> => {
      const hasImage: boolean = input.request.kind === 'image';
      await this.addAiMessage(input.runRef, ConversationWorkflow.clarifyPrompt(hasImage),
        this.originFor(input.runRef));
      return this.copyState(input, 'clarify_reply');
    });
    graph.addNode('image_reply', async (input: ConversationState): Promise<ConversationState> => {
      if (input.request.kind === 'image') {
        await this.replyHandler.handleImage(input.runRef, input.request.imageUri, input.request.userContent);
      }
      return this.copyState(input, 'image_reply');
    });
    graph.addNode('image_note_reply', async (input: ConversationState): Promise<ConversationState> => {
      if (input.request.kind !== 'image') {
        return this.copyState(input, 'image_note_reply');
      }
      const result: ImageNoteReplyResult = await this.replyHandler.handleImageNote(
        input.runRef,
        input.request.imageUri,
        input.request.userContent,
        this.noteRoute.select(input.runRef),
      );
      const next: ConversationState = this.copyState(input, 'image_note_reply');
      if (result.event !== undefined) {
        next.draftRunId = result.event.runId;
        next.draftCheckpointId = result.event.checkpointId;
        next.draftCandidateHash = result.event.candidateHash;
        next.draftStatus = 'ready-preview';
      }
      if (result.ocrResult !== undefined) {
        next.ocrResult = result.ocrResult;
      }
      if (result.ocrSourceId !== undefined) {
        next.ocrSourceId = result.ocrSourceId;
      }
      if (result.isOcrBlank === true) {
        next.isOcrBlank = true;
        next.draftStatus = undefined;
      }
      if (result.materialPersistFailed === true) {
        next.materialPersistFailed = true;
        next.draftStatus = undefined;
      }
      return next;
    });
    graph.addNode('load_reply_context', async (input: ConversationState): Promise<ConversationState> => {
      this.setStep(input.runRef, 'reply_context_load');
      const next: ConversationState = this.copyState(input, 'load_reply_context');
      next.memoryContext = await this.safeGetContextForReply(input.runRef);
      next.learnerProfileContext = await this.safeGetLearnerProfileContext(input.runRef);
      if (input.request.kind === 'text') {
        const reviewPlan: NoteReviewPlan = await this.getReviewService().plan(input.request.userContent);
        if (reviewPlan.kind !== 'none') {
          next.noteReviewPlan = reviewPlan;
          if (reviewPlan.evidence !== undefined) {
            next.evidence = reviewPlan.evidence;
          }
        } else {
          next.evidence = await this.safeBuildEvidence(input.request.userContent);
        }
      }
      return next;
    });
    graph.addNode('save_reply_input', async (input: ConversationState): Promise<ConversationState> => {
      await this.safeSaveUserMessage(input.runRef, input.request.userContent);
      return this.copyState(input, 'save_reply_input');
    });
    graph.addNode('complete_reply', async (input: ConversationState): Promise<ConversationState> => {
      await this.replyHandler.handleComplete(
        input.runRef,
        input.memoryContext ?? '',
        input.learnerProfileContext ?? '',
        input.request.userContent,
        input.evidence,
        input.noteReviewPlan,
      );
      return this.copyState(input, 'complete_reply');
    });
    graph.addNode('stream_reply', async (input: ConversationState): Promise<ConversationState> => {
      await this.replyHandler.handleStream(
        input.runRef,
        input.memoryContext ?? '',
        input.learnerProfileContext ?? '',
        input.request.userContent,
        input.evidence,
        input.noteReviewPlan,
      );
      return this.copyState(input, 'stream_reply');
    });
    if (this.toolReplyEnabled()) {
      graph.addNode('tool_reply', async (input: ConversationState): Promise<ConversationState> => {
        await this.replyHandler.handleComplete(
          input.runRef,
          input.memoryContext ?? '',
          input.learnerProfileContext ?? '',
          input.request.userContent,
          input.evidence,
          input.noteReviewPlan,
          true,
        );
        return this.copyState(input, 'tool_reply');
      });
      graph.addEdge('tool_reply', 'END');
    }
    graph.addNode('note_reply', async (input: ConversationState): Promise<ConversationState> => {
      const event: NoteDraftReadyEvent | undefined = await this.noteHandler.handle(
        input.runRef,
        input.request.userContent,
        this.noteRoute.select(input.runRef),
      );
      const next: ConversationState = this.copyState(input, 'note_reply');
      if (event !== undefined) {
        next.draftRunId = event.runId;
        next.draftCheckpointId = event.checkpointId;
        next.draftCandidateHash = event.candidateHash;
        next.draftStatus = 'ready-preview';
      }
      return next;
    });
    graph.addNode('regenerate_reply', async (input: ConversationState): Promise<ConversationState> => {
      const request = input.request;
      if (request.kind !== 'regenerate') {
        return this.copyState(input, 'regenerate_reply');
      }
      await this.safeSaveUserMessage(input.runRef, request.userContent);
      try {
        const event: NoteDraftReadyEvent = await this.capturePortRef.regenerateNoteDraft(
          'regenerate-' + Date.now().toString(),
          request.noteId,
          request.userContent,
          request.userContent,
          this.cancellationToken(input.runRef),
          input.runRef.sessionId,
          input.runRef.runId,
          this.noteGenerationProgressSink(input.runRef),
        );
        this.cbs.onDraftReady(input.runRef, event);
        this.cbs.completeProgress(input.runRef);
      } catch (e) {
        const errorMessage: string = ConversationWorkflow.errorMessage(e);
        this.finishRunFailure(input.runRef, e);
        throw new Error(errorMessage);
      }
      return this.copyState(input, 'regenerate_reply');
    });
    graph.addConditionalEdge('START', (state: ConversationState): ConversationStep => {
      if (state.request.kind === 'image') {
        return 'classify_image_intent';
      }
      if (state.request.kind === 'regenerate') {
        return 'regenerate_reply';
      }
      return 'classify_intent';
    });
    graph.addConditionalEdge('classify_image_intent', (state: ConversationState): ConversationStep => {
      if (state.appIntentClarify === true) {
        return 'clarify_reply';
      }
      if (state.intent === 'note_generation') {
        return 'image_note_reply';
      }
      return 'image_reply';
    });
    graph.addConditionalEdge('classify_intent', (state: ConversationState): ConversationStep => {
      if (state.appIntentClarify === true) {
        return 'clarify_reply';
      }
      if (state.intent === 'note_generation') {
        return 'note_reply';
      }
      return 'load_reply_context';
    });
    graph.addEdge('load_reply_context', 'save_reply_input');
    graph.addConditionalEdge('save_reply_input', (state: ConversationState): ConversationStep => {
      if (this.toolReplyEnabled() && state.request.kind === 'text') {
        return 'tool_reply';
      }
      if (state.request.kind === 'text' && state.request.responseMode === 'stream') {
        return 'stream_reply';
      }
      return 'complete_reply';
    });
    graph.addEdge('image_reply', 'END');
    graph.addEdge('clarify_reply', 'END');
    graph.addEdge('image_note_reply', 'END');
    graph.addEdge('complete_reply', 'END');
    graph.addEdge('stream_reply', 'END');
    graph.addEdge('note_reply', 'END');
    graph.addEdge('regenerate_reply', 'END');
    return graph;
  }

  private copyState(input: ConversationState, step: ConversationStep): ConversationState {
    const next: ConversationState = {
      request: input.request,
      runRef: input.runRef,
      currentStep: step,
    };
    if (input.intent !== undefined) {
      next.intent = input.intent;
    }
    if (input.appIntent !== undefined) {
      next.appIntent = input.appIntent;
    }
    if (input.appIntentConfidence !== undefined) {
      next.appIntentConfidence = input.appIntentConfidence;
    }
    if (input.appIntentSource !== undefined) {
      next.appIntentSource = input.appIntentSource;
    }
    if (input.appIntentClarify !== undefined) {
      next.appIntentClarify = input.appIntentClarify;
    }
    if (input.memoryContext !== undefined) {
      next.memoryContext = input.memoryContext;
    }
    if (input.learnerProfileContext !== undefined) {
      next.learnerProfileContext = input.learnerProfileContext;
    }
    if (input.evidence !== undefined) {
      next.evidence = input.evidence;
    }
    if (input.noteReviewPlan !== undefined) {
      next.noteReviewPlan = input.noteReviewPlan;
    }
    if (input.draftRunId !== undefined) {
      next.draftRunId = input.draftRunId;
    }
    if (input.draftCheckpointId !== undefined) {
      next.draftCheckpointId = input.draftCheckpointId;
    }
    if (input.draftCandidateHash !== undefined) {
      next.draftCandidateHash = input.draftCandidateHash;
    }
    if (input.draftStatus !== undefined) {
      next.draftStatus = input.draftStatus;
    }
    if (input.ocrResult !== undefined) {
      next.ocrResult = input.ocrResult;
    }
    if (input.ocrSourceId !== undefined) {
      next.ocrSourceId = input.ocrSourceId;
    }
    if (input.isOcrBlank !== undefined) {
      next.isOcrBlank = input.isOcrBlank;
    }
    if (input.materialPersistFailed !== undefined) {
      next.materialPersistFailed = input.materialPersistFailed;
    }
    return next;
  }

  /**
   * 流式回复 — 基于 DeepSeek SSE,逐 token 实时推送 UI
   * ReplyService.stream() 在流无正文或非传输错误时执行非流式回退
   */

  private noteGenerationProgressSink(ref: ConversationRunRef): NoteGenerationProgressSink {
    return (event: NoteGenerationProgressEvent): void => {
      this.cbs.onNoteGenerationProgress(ref, event);
    };
  }

  setStep(ref: ConversationRunRef, step: ConversationProgressStep): void {
    this.ensureNotCancelled(ref);
    this.cbs.onProgress(ref, step);
  }

  private reportRunError(ref: ConversationRunRef, error: Object): void {
    if (!this.runs.markErrorReported(ref)) {
      return;
    }
    this.cbs.onError(ref, ConversationWorkflow.userFacingWorkflowError(error));
  }

  finishRunFailure(
    ref: ConversationRunRef,
    error: Object,
    outcome?: ChatMessageOutcome,
  ): void {
    const messageId: number = this.cbs.addAiMsgEmpty(ref, this.originFor(ref));
    this.reportRunError(ref, error);
    if (messageId > 0) {
      this.cbs.finishAiMsg(ref, messageId, outcome ?? ConversationWorkflow.failureOutcome(error));
    }
  }

  /**
   * 流式调用的耗时观测 (StreamTiming)。
   *
   * 只写日志, 不参与任何业务分支 —— 唯一目的是让 @ship 的指标表能按 key=value 解析。
   * 一律走 workflowLog (DOMAIN 0x0001 / TAG 'MindTrace'), 不再用 console.*,
   * 因为 console 最终落到 hilog 的哪个 tag 在真机上未验证, 抓不到就没有"未测"以外的状态。
   * interrupted 是附加维度: outcome=error 的行按约定不进延迟分布, 但 interrupted 且
   * firstChunkMs>=0 的样本本身是有效首字延迟, 聚合时可按 interrupted 单独取回。
   */
  /**
   * 断流恢复 (非流式单次 complete) 的耗时观测。
   *
   * recoverMs = 调用发起 → Promise 落定 (resolve 或 reject 都要出这条)。
   * complete() 只返回 string, 没有 usedFallback 标记 (见 matchesFallbackShape 注释),
   * 所以这一路恒为 usedFallback=unknown, 不写 false 冒充"未降级"。
   * 不带 firstChunkMs / totalMs: 单次请求一次落定, 同一数值挂三个名字必被误聚合。
   */
  /**
   * 断流后自动降级重取一次: 保留已得内容, 成功替换并标注重连; 失败保留部分内容并追加中文错误。
   * reason 区分触发路径 (empty / interrupted / throw), 真机日志用它区分"空回复"与"真断流"。
   */
  cancellationToken(ref: ConversationRunRef): CancellationToken | undefined {
    return this.runs.token(ref);
  }

  ensureNotCancelled(ref: ConversationRunRef): void {
    this.cancellationToken(ref)?.throwIfCancelled();
    if (!this.cbs.isCurrentRun(ref)) {
      throw new Error('STALE_CONVERSATION_RUN');
    }
  }

  /** 意图不明时的追问文案（不调模型，低延迟）。 */
  private static clarifyPrompt(hasImage: boolean): string {
    if (hasImage) {
      return '这张图你想：① 我先讲解这道题；② 整理成笔记保存？回我 ① 或 ② 就行。';
    }
    return '你想：① 直接回答/讲解；② 整理成笔记保存？回我 ① 或 ②（也可以直接说「存笔记」）。';
  }

  async addAiMessage(
    ref: ConversationRunRef,
    content: string,
    origin?: ChatMessageOrigin,
    outcome: ChatMessageOutcome = 'completed',
  ): Promise<void> {
    await this.replyHandler.appendAssistantReply(ref, content, undefined, origin ?? this.originFor(ref), outcome);
  }

  createReplyContext(
    memoryContext: string,
    learnerProfileContext: string,
    userContent: string,
    evidence: NoteEvidenceContext | undefined,
  ): ReplyContext {
    return {
      memoryContext: memoryContext,
      learnerProfileContext: learnerProfileContext,
      userContent: userContent,
      evidenceContext: evidence === undefined ? '' : evidence.contextText,
    };
  }

  // DEV-006: 模型正文只保留真实 noteId 引用, 并追加由 RDB 证据生成的确定性来源块
  private getEvidenceService(): NoteEvidencePort {
    if (this.evidenceService === null) {
      this.evidenceService = ConversationWorkflow.requireEvidence(this.ports);
    }
    return this.evidenceService;
  }

  private getReviewService(): NoteReviewPort {
    if (this.reviewService === null) {
      this.reviewService = ConversationWorkflow.requireReview(this.ports);
    }
    return this.reviewService;
  }

  private static requireDraftService(ports: ConversationWorkflowPorts): IConversationDraftServicePort {
    if (ports.draftService === undefined) { throw new Error('CONVERSATION_DRAFT_SERVICE_MISSING'); }
    return ports.draftService;
  }

  private static requireMemoryService(ports: ConversationWorkflowPorts): IConversationMemoryServicePort {
    if (ports.memoryService === undefined) { throw new Error('CONVERSATION_MEMORY_SERVICE_MISSING'); }
    return ports.memoryService;
  }

  private static requireEvidence(ports: ConversationWorkflowPorts): NoteEvidencePort {
    if (ports.evidence === undefined) { throw new Error('CONVERSATION_EVIDENCE_PORT_MISSING'); }
    return ports.evidence;
  }

  private static requireReview(ports: ConversationWorkflowPorts): NoteReviewPort {
    if (ports.review === undefined) { throw new Error('CONVERSATION_REVIEW_PORT_MISSING'); }
    return ports.review;
  }

  private async safeBuildEvidence(query: string): Promise<NoteEvidenceContext | undefined> {
    try {
      return await this.getEvidenceService().build(query);
    } catch (e) {
      console.warn('[ConversationWorkflow] build evidence context failed: ' + ConversationWorkflow.errorMessage(e));
      return {
        query: query, topK: 5, citations: [], relations: [], contextText: '',
        degraded: true, reason: 'search-failed',
      };
    }
  }

  async safeSaveUserMessage(ref: ConversationRunRef, content: string): Promise<void> {
    await this.memoryProjection.saveUser(ref, content);
  }

  async safeSaveAssistantMessage(ref: ConversationRunRef, content: string, messageId: number): Promise<void> {
    await this.memoryProjection.saveAssistant(ref, content, messageId);
  }

  originFor(ref: ConversationRunRef): ChatMessageOrigin {
    return this.runs.origin(ref);
  }

  async safeSaveOcrResult(
    ref: ConversationRunRef,
    imageUri: string,
    userText: string,
    result: ClassificationResult,
  ): Promise<string | null> {
    return await this.memoryProjection.saveOcr(ref, imageUri, userText, result);
  }

  private async safeGetContextForReply(ref: ConversationRunRef): Promise<string> {
    return await this.memoryProjection.contextForReply(ref);
  }

  private async safeGetContextForNoteGeneration(ref: ConversationRunRef): Promise<string> {
    return await this.memoryProjection.contextForNote(ref);
  }

  async safeGetStructuredContextForNoteGeneration(
    ref: ConversationRunRef,
    instruction: string,
    inlineMaterial: string,
    currentConversationText: string,
  ): Promise<NoteGenerationContextResult | undefined> {
    return await this.memoryProjection.structuredContextForNote(
      ref,
      instruction,
      inlineMaterial,
      currentConversationText,
    );
  }

  private async safeGetLearnerProfileContext(ref: ConversationRunRef): Promise<string> {
    return await this.memoryProjection.learnerProfile(ref);
  }

  async safeUpdateLearnerProfileIfNeeded(ref: ConversationRunRef): Promise<void> {
    await this.memoryProjection.updateLearnerProfile(ref);
  }

  async safeSummarizeIfNeeded(ref: ConversationRunRef): Promise<void> {
    await this.memoryProjection.summarize(ref);
  }

  private static rawErrorMessage(error: Object): string {
    const message: string = ConversationWorkflow.errorMessage(error);
    if (error instanceof LlmError) {
      return error.kind + ' ' + message;
    }
    return message;
  }

  private static errorCode(error: Object): number {
    const message: string = ConversationWorkflow.errorMessage(error);
    const codes: string[] = ['401', '403', '429', '500', '501', '502', '503', '504'];
    for (const code of codes) {
      if (message.indexOf(code) >= 0) {
        return Number(code);
      }
    }
    return 0;
  }

  private static errorMessage(e: Object): string {
    if (e instanceof Error && e.message.length > 0) {
      return e.message;
    }
    return JSON.stringify(e);
  }

  private static userFacingWorkflowError(error: Object): string {
    const message: string = ConversationWorkflow.errorMessage(error);
    if (message.indexOf('CONVERSATION_CANCELLED') >= 0) {
      return '本轮处理已取消';
    }
    if (message.indexOf('NO_API_KEY') >= 0) {
      return '请先在「我的 → 设置」中配置 API Key';
    }
    if (message.indexOf('STREAM_INTERRUPTED') >= 0) {
      return 'AI 回复中断，请重试';
    }
    // Keep the upstream reason in the terminal run event; redact before clipping
    // so partial credentials cannot escape through the preview boundary.
    const safeMessage: string = LlmErrorBodyFormatter.redactSensitiveText(message).trim();
    const detail: string = safeMessage.length > 6000
      ? safeMessage.substring(0, 6000) + '…（原因较长，已截取）'
      : safeMessage;
    if (detail.length === 0 || detail === '{}' || detail === 'null') {
      return '本轮处理失败：服务未提供具体原因，请重试；若仍失败，请反馈本轮操作。';
    }
    if (ConversationWorkflow.isNetworkError(error)) {
      return '网络连接失败，本轮处理未完成。请检查网络或服务地址后重试。\n原因：' + detail;
    }
    let suggestion: string = '';
    if (/\b429\b|rate.?limit/i.test(message)) {
      suggestion = '\n服务请求过多或额度受限，请稍后重试并检查服务额度。';
    } else if (/\b(401|403)\b/.test(message)) {
      suggestion = '\n请检查 API Key、模型权限与服务配置。';
    } else if (/timeout|timed out|超时/i.test(message)) {
      suggestion = '\n服务响应超时，请稍后重试。';
    }
    return '本轮处理失败，原因：' + detail + suggestion;
  }

  private static failureOutcome(error: Object): ChatMessageOutcome {
    return ConversationWorkflow.isNetworkError(error) ? 'interrupted' : 'failed';
  }

  private static isNetworkError(e: Object): boolean {
    if (e instanceof LlmError) {
      return e.kind === 'NETWORK_ERROR' || e.kind === 'TIMEOUT' || e.kind === 'STREAM_FAILED';
    }
    const message: string = ConversationWorkflow.errorMessage(e).toLowerCase();
    const markers: string[] = [
      'network error',
      'failed to resolve',
      'could not resolve host',
      'network is unreachable',
      'could not connect to server',
      'couldn\'t connect to server',
      'couldnt connect to server',
      'connection refused',
      'connection reset',
      'connection timed out',
      'connect timeout',
      'request timed out',
      'curlcode result 6',
    ];
    for (const marker of markers) {
      if (message.includes(marker)) {
        return true;
      }
    }
    return false;
  }
}
