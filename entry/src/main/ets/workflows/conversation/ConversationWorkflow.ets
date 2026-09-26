/**
 * ConversationWorkflow.ets — 浮窗对话 StateGraph 编排
 *
 * 路径: entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets
 * 职责: 编排 text/image/regenerate 三种 ConversationRequest,经 classify_intent → load_reply_context → save_reply_input → (stream_reply|complete_reply|image_reply|note_reply|regenerate_reply) → END
 * 依赖: common (KnowledgeUnit/ClassificationResult/LlmConfig/LlmError/Logger/StateGraph/LlmErrorBodyFormatter); ../services (AiService/AgentMemoryService/IntentClassifier/ReplyService)
 *
 * 数据流:
 *   AgentFloatWindow.realReply → workflow.run(request) → buildGraph (条件边分发) → ReplyService.complete/stream (LLM 调用) → updateAiMsg(ConversationMessageEvent) → ChatMsg 更新 → finishAiMsg → safeSaveAssistantMessage (持久化)
 *
 * 设计要点:
 *   - copyState 严格字段复制 (无 map+spread) — 任意 P1 字段须显式添加,避免漏字段
 *   - isNetworkError 与 ReplyService.isNetworkError 范围不同:本类含 STREAM_FAILED + 12 个 substring fallback,顶层 catch 用
 *   - parseRegenerationRequest / isIncrementalInstruction 解析用户指令中的 noteId 与增量意图标记(从 'noteId=' / '笔记ID：' / 增量关键词)
 *   - 错误消息经 LlmErrorBodyFormatter.redactSensitiveText 脱敏后再展示给用户,防止 Bearer / api-key / sk-xxx 泄露
 *
 * ArkTS 1.1 strict 适配:
 *   - StateGraph<Node, Edge> 泛型参数显式标注 (避免 arkts-no-inferred-generic-params)
 *   - catch 块统一用 ConversationWorkflow.errorMessage(e) 兜底,不写 catch (e: Error)
 *   - copyState 用显式字段复制,不写解构赋值
 */

import { common } from '@kit.AbilityKit';
import {
  KnowledgeUnit,
  ClassificationResult,
  LlmErrorBodyFormatter,
  LlmError,
  Logger,
  StateGraph,
} from 'common';
import { ReplyContext } from '../../services/IntentClassifier';
import type { TextIntent } from '../../services/IntentClassifier';
import {
  ConversationProgressStep,
  ConversationState,
  ConversationStep,
  ConversationRequest,
  ChatMessageOrigin,
  ChatMessageOutcome,
} from './ConversationState';
import { ConversationMessageEvent, ConversationWorkflowCallbacks } from './ConversationTypes';
import { StreamReplyResult } from '../../services/ReplyService';
import { NoteDraftReadyEvent, NoteGenerationRoute, NoteGenerationRun, SourceFragment } from 'common';
import type { StreamEvent } from 'common';
import { NoteEvidenceContext } from '../../models/NoteEvidenceModels';
import { NoteEvidenceService, NoteEvidenceStreamFilter } from '../../services/NoteEvidenceService';
import { ConversationRunRef } from '../../services/ConversationIdentity';
import { requireConversationRunRef } from '../../services/ConversationIdentity';
import { CancellationToken } from 'common';
import { ConversationDraftWorkflow, IConversationDraftWorkflowHost } from './ConversationDraftWorkflow';
import { ConversationMemoryProjection, IConversationMemoryProjectionHost } from './ConversationMemoryProjection';
import {
  ConversationWorkflowPorts,
  IConversationCapturePort,
  IConversationIntentPort,
  IConversationNoteRoutePort,
  IConversationReplyPort,
} from './ConversationWorkflowPorts';

const workflowLog: Logger = new Logger('ConversationWorkflow');

interface RegenerationInstruction {
  noteId: string;
  instruction: string;
}

interface ImageNoteReplyResult {
  event?: NoteDraftReadyEvent;
  ocrResult?: ClassificationResult;
  ocrSourceId?: string;
  isOcrBlank?: boolean;
  materialPersistFailed?: boolean;
}

export class ConversationWorkflow implements IConversationDraftWorkflowHost, IConversationMemoryProjectionHost {
  private cbs: ConversationWorkflowCallbacks;
  private readonly intentClassifier: IConversationIntentPort;
  private readonly replyService: IConversationReplyPort;
  private readonly capturePort: IConversationCapturePort;
  private readonly noteRoute: IConversationNoteRoutePort;
  private evidenceService: NoteEvidenceService | null = null;
  private readonly cancellationTokens: Map<string, CancellationToken> = new Map<string, CancellationToken>();
  private readonly runOrigins: Map<string, ChatMessageOrigin> = new Map<string, ChatMessageOrigin>();
  private readonly reportedErrorRuns: Set<string> = new Set<string>();
  private readonly draftWorkflow: ConversationDraftWorkflow;
  private readonly memoryProjection: ConversationMemoryProjection;

  constructor(callbacks: ConversationWorkflowCallbacks, ports?: ConversationWorkflowPorts) {
    this.cbs = callbacks;
    const resolvedPorts: ConversationWorkflowPorts = ports
      ?? ConversationWorkflowPorts.production(callbacks.getContext());
    this.intentClassifier = resolvedPorts.intent;
    this.replyService = resolvedPorts.reply;
    this.capturePort = resolvedPorts.capture;
    this.noteRoute = resolvedPorts.noteRoute;
    this.draftWorkflow = ConversationDraftWorkflow.create(this);
    this.memoryProjection = ConversationMemoryProjection.create(this);
  }

  draftContext(): common.UIAbilityContext { return this.cbs.getContext(); }

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

  memoryContext(): common.UIAbilityContext { return this.cbs.getContext(); }

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
    this.cancellationTokens.set(runRef.runId, cancellationToken);
    this.runOrigins.set(runRef.runId, request.kind === 'image'
      ? 'image'
      : request.kind === 'regenerate' ? 'note-regeneration' : 'chat');
    this.reportedErrorRuns.delete(runRef.runId);
    const removeCancellationHook: () => void = this.cbs.registerCancellationHook(runRef, (): void => {
      this.cancellationTokens.delete(runRef.runId);
      this.runOrigins.delete(runRef.runId);
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
      this.cancellationTokens.delete(runRef.runId);
      this.runOrigins.delete(runRef.runId);
      this.reportedErrorRuns.delete(runRef.runId);
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

  async listRecoverableDrafts(): Promise<NoteGenerationRun[]> {
    return await this.draftWorkflow.listRecoverable();
  }

  private buildGraph(): StateGraph<ConversationState, ConversationStep> {
    const graph: StateGraph<ConversationState, ConversationStep> =
      new StateGraph<ConversationState, ConversationStep>('START', 'END');
    graph.addNode('classify_intent', async (input: ConversationState): Promise<ConversationState> => {
      this.setStep(input.runRef, 'intent_check');
      this.ensureNotCancelled(input.runRef);
      const token: CancellationToken | undefined = this.cancellationToken(input.runRef);
      const intent: TextIntent = token === undefined
        ? await this.intentClassifier.classify(input.request.userContent)
        : await this.intentClassifier.classifyWithCancellation(input.request.userContent, token);
      const next: ConversationState = this.copyState(input, 'classify_intent');
      next.intent = intent;
      return next;
    });
    graph.addNode('classify_image_intent', async (input: ConversationState): Promise<ConversationState> => {
      this.setStep(input.runRef, 'intent_check');
      const userText: string = input.request.userContent.trim();
      let intent: TextIntent = 'chat';
      if (userText.length > 0 && userText !== '[图片]') {
        intent = await this.intentClassifier.classifyWithCancellation(userText, this.cancellationToken(input.runRef));
      }
      const next: ConversationState = this.copyState(input, 'classify_image_intent');
      next.intent = intent;
      return next;
    });
    graph.addNode('image_reply', async (input: ConversationState): Promise<ConversationState> => {
      if (input.request.kind === 'image') {
        await this.handleImageReply(input.runRef, input.request.imageUri, input.request.userContent);
      }
      return this.copyState(input, 'image_reply');
    });
    graph.addNode('image_note_reply', async (input: ConversationState): Promise<ConversationState> => {
      if (input.request.kind !== 'image') {
        return this.copyState(input, 'image_note_reply');
      }
      const result: ImageNoteReplyResult = await this.handleImageNoteReply(
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
        next.evidence = await this.safeBuildEvidence(input.request.userContent);
      }
      return next;
    });
    graph.addNode('save_reply_input', async (input: ConversationState): Promise<ConversationState> => {
      await this.safeSaveUserMessage(input.runRef, input.request.userContent);
      return this.copyState(input, 'save_reply_input');
    });
    graph.addNode('complete_reply', async (input: ConversationState): Promise<ConversationState> => {
      await this.handleCompleteReply(
        input.runRef,
        input.memoryContext ?? '',
        input.learnerProfileContext ?? '',
        input.request.userContent,
        input.evidence,
      );
      return this.copyState(input, 'complete_reply');
    });
    graph.addNode('stream_reply', async (input: ConversationState): Promise<ConversationState> => {
      await this.handleStreamReply(
        input.runRef,
        input.memoryContext ?? '',
        input.learnerProfileContext ?? '',
        input.request.userContent,
        input.evidence,
      );
      return this.copyState(input, 'stream_reply');
    });
    graph.addNode('note_reply', async (input: ConversationState): Promise<ConversationState> => {
      const event: NoteDraftReadyEvent | undefined = await this.generateNoteFromConversation(
        input.runRef,
        input.request.userContent,
        this.noteRoute.select(input.runRef),
      );
      this.setStep(input.runRef, 'completed');
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
      this.setStep(input.runRef, 'note_context_load');
      await this.safeSaveUserMessage(input.runRef, request.userContent);
      try {
        const event: NoteDraftReadyEvent = await this.capturePort.regenerateNoteDraft(
          'regenerate-' + Date.now().toString(),
          request.noteId,
          request.userContent,
          request.userContent,
          this.cancellationToken(input.runRef),
          input.runRef.sessionId,
          input.runRef.runId,
        );
        this.cbs.onDraftReady(input.runRef, event);
        await this.addAiMessage(input.runRef, '增量预览已准备，请检查新增、修改、保留和锁定章节。');
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
      if (state.intent === 'note_generation') {
        return 'image_note_reply';
      }
      return 'image_reply';
    });
    graph.addConditionalEdge('classify_intent', (state: ConversationState): ConversationStep => {
      if (state.intent === 'note_generation') {
        return 'note_reply';
      }
      return 'load_reply_context';
    });
    graph.addEdge('load_reply_context', 'save_reply_input');
    graph.addConditionalEdge('save_reply_input', (state: ConversationState): ConversationStep => {
      if (state.request.kind === 'text' && state.request.responseMode === 'stream') {
        return 'stream_reply';
      }
      return 'complete_reply';
    });
    graph.addEdge('image_reply', 'END');
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
    if (input.memoryContext !== undefined) {
      next.memoryContext = input.memoryContext;
    }
    if (input.learnerProfileContext !== undefined) {
      next.learnerProfileContext = input.learnerProfileContext;
    }
    if (input.evidence !== undefined) {
      next.evidence = input.evidence;
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

  private async handleImageReply(ref: ConversationRunRef, imageUri: string, userText: string): Promise<void> {
    this.setStep(ref, 'image_message_save');
    try {
      await this.safeSaveUserMessage(ref, userText.trim().length > 0 ? userText : '[图片]');
      this.setStep(ref, 'image_recognize');
      const result: ClassificationResult = await this.capturePort.analyzeImage(
        imageUri,
        userText,
        this.cancellationToken(ref),
      );
      workflowLog.info('image analysis completed type=' + result.type);
      this.setStep(ref, 'image_material_save');
      const ocrSourceId: string | null = await this.safeSaveOcrResult(ref, imageUri, userText, result);
      if (ocrSourceId === null) {
        await this.addAiMessage(ref, '图片识别成功，但素材暂存失败，识别结果可能无法恢复。', this.originFor(ref), 'failed');
      }
      const reply: string = this.formatAnalyzeReply(result);
      await this.addAiMessage(ref, reply);
      this.setStep(ref, 'completed');
    } catch (e) {
      const errorMessage: string = ConversationWorkflow.errorMessage(e);
      this.finishRunFailure(ref, e);
      throw new Error(errorMessage);
    }
  }

  private async handleImageNoteReply(
    ref: ConversationRunRef,
    imageUri: string,
    userText: string,
    route?: NoteGenerationRoute,
  ): Promise<ImageNoteReplyResult> {
    this.setStep(ref, 'image_message_save');
    await this.safeSaveUserMessage(ref, userText.trim().length > 0 ? userText : '[图片]');

    this.setStep(ref, 'image_note_ocr');
    let classificationResult: ClassificationResult;
    try {
      classificationResult = await this.capturePort.analyzeImage(
        imageUri,
        userText,
        this.cancellationToken(ref),
      );
    } catch (e) {
      const errorMessage: string = ConversationWorkflow.errorMessage(e);
      this.finishRunFailure(ref, e);
      throw new Error(errorMessage);
    }

    const ocrText: string = (classificationResult.ocrText ?? '').trim();
    if (ocrText.length === 0) {
      this.setStep(ref, 'image_ocr_blank');
      if (this.cbs.onOcrBlank !== undefined) {
        this.cbs.onOcrBlank(ref, imageUri);
      }
      await this.addAiMessage(
        ref,
        '未识别到有效文字，请重新拍照或手动补充文字后再试。',
      );
      this.setStep(ref, 'completed');
      return { ocrResult: classificationResult, isOcrBlank: true };
    }

    this.setStep(ref, 'image_material_save');
    const ocrSourceId: string | null = await this.safeSaveOcrResult(ref, imageUri, userText, classificationResult);
    const materialPersistFailed: boolean = ocrSourceId === null;
    if (materialPersistFailed) {
      workflowLog.warn('material persist failed for image: ' + imageUri);
    }

    this.setStep(ref, 'image_note_draft');
    try {
      const configured: boolean = await this.replyService.isConfigured();
      if (!configured) {
        throw new Error('NO_API_KEY');
      }

      // DEV-002: 当前图片来源隔离 — 只由当前 userText + classificationResult 组成素材文本
      // 不调用 safeGetContextForNoteGeneration / getConversationText，
      // 避免本会话历史 pending OCR 文本混入导致旧图片素材重叠或当前 OCR 重复。
      // 后续如需合并历史上下文，可在此处添加条件分支（如 mergeMode 参数），本期默认当前图片优先。
      const ocrLines: string[] = [
        '图片识别材料',
        '类型: ' + classificationResult.type,
        '学科: ' + classificationResult.subject,
        'OCR:',
        ocrText,
      ];
      const trimmedUserText: string = userText.trim();
      const noteInstruction: string = trimmedUserText.length > 0 && trimmedUserText !== '[图片]'
        ? trimmedUserText
        : '请根据图片识别材料生成一份数学学习笔记，保留公式、步骤和结论';
      if (trimmedUserText.length > 0 && trimmedUserText !== '[图片]') {
        ocrLines.splice(1, 0, '用户补充: ' + trimmedUserText);
      }
      const conversation: string = ocrLines.join('\n');

      const noteGenerationRunId: string = 'img-note-' + Date.now().toString();
      const pendingSources: SourceFragment[] = [];
      if (ocrSourceId !== null) {
        pendingSources.push({
          id: ocrSourceId,
          kind: 'ocr',
          originId: imageUri,
          sequence: 1,
          fingerprint: ocrSourceId,
          text: ocrText,
        });
      }

      const event: NoteDraftReadyEvent = await this.generateNoteDraft(
        ref,
        noteGenerationRunId,
        noteInstruction,
        conversation,
        pendingSources,
        this.cancellationToken(ref),
        route,
      );
      this.setStep(ref, 'note_finalize');

      if (materialPersistFailed) {
        await this.addAiMessage(
          ref,
          '⚠️ 笔记草稿已准备，但素材暂存失败，草稿无法在重启后恢复。请尽快确认保存。',
        );
      } else {
        await this.addAiMessage(ref, '笔记草稿已准备，请预览并确认保存。');
      }
      this.cbs.onDraftReady(ref, event);
      this.setStep(ref, 'completed');
      return {
        event: event,
        ocrResult: classificationResult,
        ocrSourceId: ocrSourceId ?? undefined,
        materialPersistFailed: materialPersistFailed,
      };
    } catch (e) {
      const errMsg: string = LlmErrorBodyFormatter.redactSensitiveText(ConversationWorkflow.errorMessage(e));
      this.finishRunFailure(ref, e);
      throw new Error(errMsg);
    }
  }

  private async handleCompleteReply(
    ref: ConversationRunRef,
    memoryContext: string,
    learnerProfileContext: string,
    userContent: string,
    evidence: NoteEvidenceContext | undefined,
  ): Promise<void> {
    try {
      const configured: boolean = await this.replyService.isConfigured();
      if (!configured) {
        throw new Error('NO_API_KEY');
      }
      this.setStep(ref, 'reply_model_call');
      const replyContext: ReplyContext = this.createReplyContext(memoryContext, learnerProfileContext, userContent, evidence);
      const reply: string = await this.replyService.complete(replyContext, this.cancellationToken(ref));
      await this.addAiMessage(ref, this.applyEvidenceToAnswer(evidence, reply));
      await this.safeUpdateLearnerProfileIfNeeded(ref);
      await this.safeSummarizeIfNeeded(ref);
    } catch (e) {
      const errMsg: string = ConversationWorkflow.errorMessage(e);
      this.finishRunFailure(ref, e);
      throw new Error(errMsg);
    }
  }

  /**
   * 流式回复 — 基于 DeepSeek SSE,逐 token 实时推送 UI
   * ReplyService.stream() 在流无正文或非传输错误时执行非流式回退
   */
  private async handleStreamReply(
    ref: ConversationRunRef,
    memoryContext: string,
    learnerProfileContext: string,
    userContent: string,
    evidence: NoteEvidenceContext | undefined,
  ): Promise<void> {
    try {
      const configured: boolean = await this.replyService.isConfigured();
      if (!configured) {
        throw new Error('NO_API_KEY');
      }

      // 创建空消息占位,拿到 msgId
      const msgId: number = this.cbs.addAiMsgEmpty(ref, this.originFor(ref));
      this.setStep(ref, 'reply_model_call');
      const replyContext: ReplyContext = this.createReplyContext(memoryContext, learnerProfileContext, userContent, evidence);
      const citationFilter: NoteEvidenceStreamFilter = this.getEvidenceService().createStreamFilter(evidence);
      const streamResult: StreamReplyResult = await this.replyService.stream(
        replyContext,
        (event: StreamEvent): void => {
          if (event.type !== 'text') {
            const messageEvent: ConversationMessageEvent = { kind: 'stream', event: event };
            this.cbs.updateAiMsg(ref, msgId, messageEvent);
            return;
          }
          const safeText: string = citationFilter.push(event.delta);
          if (safeText.length > 0) {
            const safeEvent: StreamEvent = { type: 'text', delta: safeText };
            const messageEvent: ConversationMessageEvent = { kind: 'stream', event: safeEvent };
            this.cbs.updateAiMsg(ref, msgId, messageEvent);
          }
        },
        this.cancellationToken(ref),
      );
      const citationTail: string = citationFilter.flush();
      if (citationTail.length > 0) {
        const tailEvent: StreamEvent = { type: 'text', delta: citationTail };
        const messageEvent: ConversationMessageEvent = { kind: 'stream', event: tailEvent };
        this.cbs.updateAiMsg(ref, msgId, messageEvent);
      }
      if (streamResult.usedFallback) {
        await this.appendAssistantReply(ref, this.applyEvidenceToAnswer(evidence, streamResult.content), msgId);
        return;
      }
      const displayAnswer: string = evidence === undefined
        ? this.replyService.normalize(streamResult.content)
        : this.replyService.normalize(
          this.getEvidenceService().sanitizeAnswer(evidence, streamResult.content),
        );
      const normalizedEvent: ConversationMessageEvent = { kind: 'replace-content', content: displayAnswer };
      this.cbs.updateAiMsg(ref, msgId, normalizedEvent);
      if (streamResult.interrupted) {
        throw new Error('STREAM_INTERRUPTED');
      } else {
        this.setStep(ref, 'completed');
      }
      const sources: string = evidence === undefined ? '' : this.getEvidenceService().formatSources(evidence);
      if (sources.length > 0) {
        const sourcesEvent: StreamEvent = { type: 'text', delta: '\n\n' + sources };
        const messageEvent: ConversationMessageEvent = { kind: 'stream', event: sourcesEvent };
        this.cbs.updateAiMsg(ref, msgId, messageEvent);
      }
      const persistedAnswer: string = this.replyService.normalize(
        this.applyEvidenceToAnswer(evidence, streamResult.content),
      );
      this.cbs.finishAiMsg(ref, msgId, 'completed');
      await this.safeSaveAssistantMessage(ref, persistedAnswer, msgId);
      await this.safeUpdateLearnerProfileIfNeeded(ref);
      await this.safeSummarizeIfNeeded(ref);
    } catch (e) {
      const errMsg: string = ConversationWorkflow.errorMessage(e);
      const outcome: ChatMessageOutcome = errMsg === 'STREAM_INTERRUPTED'
        ? 'interrupted'
        : ConversationWorkflow.failureOutcome(e);
      this.finishRunFailure(ref, e, outcome);
      throw new Error(errMsg);
    }
  }

  private async generateNoteFromConversation(
    ref: ConversationRunRef,
    userInstruction: string,
    route?: NoteGenerationRoute,
  ): Promise<NoteDraftReadyEvent | undefined> {
    this.setStep(ref, 'note_intent_check');
    this.setStep(ref, 'note_context_load');
    const explicitRegeneration = this.parseRegenerationRequest(userInstruction);
    if (explicitRegeneration !== undefined) {
      await this.safeSaveUserMessage(ref, userInstruction);
      try {
        const event: NoteDraftReadyEvent = await this.capturePort.regenerateNoteDraft(
          'regenerate-' + Date.now().toString(),
          explicitRegeneration.noteId,
          explicitRegeneration.instruction,
          explicitRegeneration.instruction,
          this.cancellationToken(ref),
          ref.sessionId,
          ref.runId,
        );
        this.cbs.onDraftReady(ref, event);
        await this.addAiMessage(ref, '增量预览已准备，请检查新增、修改、保留和锁定章节。');
        return event;
      } catch (e) {
        const errorMessage: string = ConversationWorkflow.errorMessage(e);
        this.finishRunFailure(ref, e);
        throw new Error(errorMessage);
      }
    }
    if (this.isIncrementalInstruction(userInstruction)) {
      await this.addAiMessage(ref, '请先选择要修改的明确笔记，再提出增量修改要求。', this.originFor(ref), 'failed');
      return undefined;
    }
    const memoryContext: string = await this.safeGetContextForNoteGeneration(ref);
    this.setStep(ref, 'note_source_prepare');
    await this.safeSaveUserMessage(ref, userInstruction);
    try {
      const configured: boolean = await this.replyService.isConfigured();
      if (!configured) {
        throw new Error('NO_API_KEY');
      }

      let conversation: string = this.intentClassifier.inlineNoteMaterial(userInstruction).trim();
      if (conversation.length === 0) {
        conversation = memoryContext.trim();
      }
      if (conversation.length === 0) {
        conversation = this.cbs.getConversationText(ref, true).trim();
      }
      if (conversation.length === 0) {
        await this.addAiMessage(ref, '当前会话还没有可整理的内容', this.originFor(ref), 'failed');
        return undefined;
      }

      this.setStep(ref, 'note_structure_save');
      const noteGenerationRunId: string = 'conversation-' + Date.now().toString();
      if (!this.cbs.isCurrentRun(ref)) { return undefined; }
      const pendingSources: SourceFragment[] = await this.memoryProjection.pendingSources(ref);
      const event: NoteDraftReadyEvent = await this.generateNoteDraft(
        ref,
        noteGenerationRunId,
        userInstruction,
        conversation,
        pendingSources,
        this.cancellationToken(ref),
        route,
      );
      this.setStep(ref, 'note_finalize');
      this.cbs.onDraftReady(ref, event);
      await this.addAiMessage(ref, '笔记草稿已准备，请预览并确认保存。');
      return event;
    } catch (e) {
      const errMsg: string = LlmErrorBodyFormatter.redactSensitiveText(ConversationWorkflow.errorMessage(e));
      this.finishRunFailure(ref, e);
      throw new Error(errMsg);
    }
  }

  private formatAnalyzeReply(result: ClassificationResult): string {
    const ocrText: string = (result.ocrText ?? '').trim();
    const body: string = ocrText.length > 0 ? this.clip(ocrText, 1600) : '未识别到可展示文本';
    const chapter: string = result.chapter !== undefined && result.chapter.length > 0 ? result.chapter : '未识别';
    return '已识别内容，暂不生成笔记。\n\n'
      + '类型：' + result.type + '\n'
      + '学科：' + result.subject + '\n'
      + '章节：' + chapter + '\n'
      + '置信度：' + result.confidence.toString() + '\n\n'
      + '识别内容：\n' + body + '\n\n'
      + '需要保存时，请发送“生成笔记”或“整理成笔记”。';
  }

  private async generateNoteDraft(
    ref: ConversationRunRef,
    runId: string,
    instruction: string,
    sourceText: string,
    pendingSources: SourceFragment[],
    cancellationToken?: CancellationToken,
    route?: NoteGenerationRoute,
  ): Promise<NoteDraftReadyEvent> {
    return await this.capturePort.generateNoteDraftWithSources(
      runId,
      instruction,
      sourceText,
      pendingSources,
      cancellationToken,
      ref.sessionId,
      ref.runId,
      route,
    );
  }


  private clip(text: string, limit: number): string {
    if (text.length <= limit) { return text; }
    return text.substring(0, limit) + '\n...';
  }

  private setStep(ref: ConversationRunRef, step: ConversationProgressStep): void {
    this.ensureNotCancelled(ref);
    this.cbs.onProgress(ref, step);
  }

  private reportRunError(ref: ConversationRunRef, error: Object): void {
    if (this.reportedErrorRuns.has(ref.runId)) {
      return;
    }
    this.reportedErrorRuns.add(ref.runId);
    this.cbs.onError(ref, ConversationWorkflow.userFacingWorkflowError(error));
  }

  private finishRunFailure(
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

  private cancellationToken(ref: ConversationRunRef): CancellationToken | undefined {
    return this.cancellationTokens.get(ref.runId);
  }

  private ensureNotCancelled(ref: ConversationRunRef): void {
    this.cancellationToken(ref)?.throwIfCancelled();
    if (!this.cbs.isCurrentRun(ref)) {
      throw new Error('STALE_CONVERSATION_RUN');
    }
  }

  private async addAiMessage(
    ref: ConversationRunRef,
    content: string,
    origin?: ChatMessageOrigin,
    outcome: ChatMessageOutcome = 'completed',
  ): Promise<void> {
    await this.appendAssistantReply(ref, content, undefined, origin ?? this.originFor(ref), outcome);
  }

  private async appendAssistantReply(
    ref: ConversationRunRef,
    content: string,
    messageId?: number,
    origin: ChatMessageOrigin = 'chat',
    outcome: ChatMessageOutcome = 'completed',
  ): Promise<void> {
    if (!this.cbs.isCurrentRun(ref)) {
      return;
    }
    const displayContent: string = this.replyService.normalize(content);
    let persistedMessageId: number = messageId ?? -1;
    if (messageId === undefined) {
      persistedMessageId = this.cbs.addAiMsg(ref, displayContent, origin, outcome);
    } else {
      const textEvent: StreamEvent = { type: 'text', delta: displayContent };
      const messageEvent: ConversationMessageEvent = { kind: 'stream', event: textEvent };
      this.cbs.updateAiMsg(ref, messageId, messageEvent);
      this.cbs.finishAiMsg(ref, messageId, outcome);
    }
    if (outcome === 'completed' && persistedMessageId > 0) {
      await this.safeSaveAssistantMessage(ref, displayContent, persistedMessageId);
    }
  }

  private createReplyContext(
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
  private applyEvidenceToAnswer(evidence: NoteEvidenceContext | undefined, answer: string): string {
    if (evidence === undefined || evidence.citations.length === 0) {
      return answer;
    }
    const sanitized: string = this.getEvidenceService().sanitizeAnswer(evidence, answer);
    const sources: string = this.getEvidenceService().formatSources(evidence);
    if (sources.length === 0) {
      return sanitized;
    }
    return sanitized + '\n\n' + sources;
  }

  private getEvidenceService(): NoteEvidenceService {
    if (this.evidenceService === null) {
      this.evidenceService = new NoteEvidenceService();
    }
    return this.evidenceService;
  }

  private async safeBuildEvidence(query: string): Promise<NoteEvidenceContext | undefined> {
    try {
      return await this.getEvidenceService().build(query);
    } catch (e) {
      console.warn('[ConversationWorkflow] build evidence context failed: ' + ConversationWorkflow.errorMessage(e));
      return undefined;
    }
  }

  private async safeSaveUserMessage(ref: ConversationRunRef, content: string): Promise<void> {
    await this.memoryProjection.saveUser(ref, content);
  }

  private async safeSaveAssistantMessage(ref: ConversationRunRef, content: string, messageId: number): Promise<void> {
    await this.memoryProjection.saveAssistant(ref, content, messageId);
  }

  private originFor(ref: ConversationRunRef): ChatMessageOrigin {
    return this.runOrigins.get(ref.runId) ?? 'chat';
  }

  private async safeSaveOcrResult(
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

  private async safeGetLearnerProfileContext(ref: ConversationRunRef): Promise<string> {
    return await this.memoryProjection.learnerProfile(ref);
  }

  private async safeUpdateLearnerProfileIfNeeded(ref: ConversationRunRef): Promise<void> {
    await this.memoryProjection.updateLearnerProfile(ref);
  }

  private async safeSummarizeIfNeeded(ref: ConversationRunRef): Promise<void> {
    await this.memoryProjection.summarize(ref);
  }

  private parseRegenerationRequest(userInstruction: string): RegenerationInstruction | undefined {
    const markers: string[] = ['noteId=', 'noteId:', '笔记ID=', '笔记ID：'];
    for (const marker of markers) {
      const markerIndex: number = userInstruction.indexOf(marker);
      if (markerIndex < 0) {
        continue;
      }
      const valueStart: number = markerIndex + marker.length;
      const separatorIndex: number = userInstruction.indexOf(' ', valueStart);
      const noteId: string = (separatorIndex < 0
        ? userInstruction.substring(valueStart)
        : userInstruction.substring(valueStart, separatorIndex)).trim();
      if (noteId.length > 0) {
        const instruction: string = userInstruction.substring(valueStart + noteId.length).trim();
        const result: RegenerationInstruction = {
          noteId: noteId,
          instruction: instruction.length > 0 ? instruction : '请按新要求增量更新笔记',
        };
        return result;
      }
    }
    return undefined;
  }

  private isIncrementalInstruction(userInstruction: string): boolean {
    const markers: string[] = ['增加例子', '补充例子', '展开推导', '只修改', '增量', '重生成章节'];
    for (const marker of markers) {
      if (userInstruction.includes(marker)) {
        return true;
      }
    }
    return false;
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
    if (ConversationWorkflow.isNetworkError(error)) {
      return '网络连接失败，本轮处理未完成';
    }
    return '本轮处理失败，请重试';
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
