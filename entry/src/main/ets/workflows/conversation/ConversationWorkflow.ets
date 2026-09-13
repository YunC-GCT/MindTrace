import {
  KnowledgeUnit,
  ClassificationResult,
  LlmConfig,
  LlmError,
  Logger,
  StateGraph,
} from 'common';
import { AiService } from '../../services/AiService';
import { AgentMemoryService } from '../../services/AgentMemoryService';
import { IntentClassifier, ReplyContext } from '../../services/IntentClassifier';
import type { TextIntent } from '../../services/IntentClassifier';
import {
  ConversationProgressStep,
  ConversationState,
  ConversationStep,
  ConversationRequest,
} from './ConversationState';
import { ConversationWorkflowCallbacks } from './ConversationTypes';
import { ReplyService, StreamReplyResult } from '../../services/ReplyService';
import { NoteDraftReadyEvent, NoteGenerationRun, SourceFragment } from 'common';
import type { StreamEvent } from 'common';

const workflowLog: Logger = new Logger('ConversationWorkflow');

interface RegenerationInstruction {
  noteId: string;
  instruction: string;
}

export class ConversationWorkflow {
  private cbs: ConversationWorkflowCallbacks;
  private memory: AgentMemoryService | null = null;
  private intentClassifier: IntentClassifier = new IntentClassifier();
  private replyService: ReplyService = new ReplyService(this.intentClassifier);

  constructor(callbacks: ConversationWorkflowCallbacks) {
    this.cbs = callbacks;
  }

  async run(request: ConversationRequest): Promise<void> {
    const initial: ConversationState = {
      request: request,
      sessionId: this.currentSessionId(),
      currentStep: 'START',
    };
    const graph: StateGraph<ConversationState, ConversationStep> = this.buildGraph();
    workflowLog.info('run start kind=' + request.kind);
    this.cbs.onStart();
    try {
      await graph.run(initial);
    } finally {
      this.cbs.onFinish();
      workflowLog.info('run finish kind=' + request.kind);
    }
  }

  async confirmDraft(event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit> {
    const service: AiService = new AiService(this.cbs.getContext());
    try {
      const committed: KnowledgeUnit = await service.confirmDraft(event, candidate);
      await this.addAiMessage(this.currentSessionId(), '已保存笔记：' + committed.title);
      return committed;
    } catch (e) {
      const conflict: boolean = ConversationWorkflow.errorMessage(e).indexOf('VERSION_CONFLICT') >= 0;
      if (conflict && event.incrementalManifest !== undefined && event.expectedVersion !== undefined) {
        const refreshed: NoteDraftReadyEvent = await new AiService(this.cbs.getContext()).regenerateNoteDraft(
          'replan-' + Date.now().toString(),
          event.incrementalManifest.noteId,
          event.incrementalInstruction ?? '请重新规划增量修改',
          event.incrementalInstruction ?? '请重新规划增量修改',
        );
        this.cbs.onDraftReady(refreshed);
        await this.addAiMessage(this.currentSessionId(), '笔记版本已变化，已重新加载并生成新的预览，请再次确认。');
      }
      await this.addAiMessage(this.currentSessionId(), '保存笔记失败: ' + ConversationWorkflow.errorMessage(e).substring(0, 120));
      throw new Error(ConversationWorkflow.errorMessage(e));
    }
  }

  async restoreDraft(runId: string): Promise<NoteDraftReadyEvent> {
    const event: NoteDraftReadyEvent = await new AiService(this.cbs.getContext()).restoreDraft(runId);
    this.cbs.onDraftReady(event);
    await this.addAiMessage(this.currentSessionId(), '已恢复笔记草稿，请预览并确认。');
    return event;
  }

  async cancelDraft(runId: string): Promise<void> {
    await new AiService(this.cbs.getContext()).cancelDraft(runId);
    await this.addAiMessage(this.currentSessionId(), '已取消笔记草稿，待整理材料仍可使用。');
  }

  async regenerateNote(noteId: string, instruction: string): Promise<void> {
    if (noteId.trim().length === 0) {
      throw new Error('增量重生成需要明确 noteId');
    }
    await this.run({ kind: 'regenerate', noteId: noteId, userContent: instruction });
  }

  async requestRegeneration(noteReference: string, noteIds: string[], instruction: string): Promise<void> {
    const candidates: string[] = [];
    for (const noteId of noteIds) {
      if (!candidates.includes(noteId)) {
        candidates.push(noteId);
      }
    }
    if (candidates.length !== 1 || candidates[0] !== noteReference) {
      await this.addAiMessage(this.currentSessionId(), '请先选择要修改的明确笔记，再提出增量修改要求。');
      return;
    }
    await this.regenerateNote(candidates[0], instruction);
  }

  async retryDraft(runId: string): Promise<NoteDraftReadyEvent> {
    const event: NoteDraftReadyEvent = await new AiService(this.cbs.getContext()).retryDraft(runId);
    this.cbs.onDraftReady(event);
    return event;
  }

  async listRecoverableDrafts(): Promise<NoteGenerationRun[]> {
    return await new AiService(this.cbs.getContext()).listRecoverableDrafts();
  }

  private buildGraph(): StateGraph<ConversationState, ConversationStep> {
    const graph: StateGraph<ConversationState, ConversationStep> =
      new StateGraph<ConversationState, ConversationStep>('START', 'END');
    graph.addNode('classify_intent', async (input: ConversationState): Promise<ConversationState> => {
      this.setStep('intent_check');
      const intent: TextIntent = await this.intentClassifier.classify(input.request.userContent);
      const next: ConversationState = this.copyState(input, 'classify_intent');
      next.intent = intent;
      return next;
    });
    graph.addNode('image_reply', async (input: ConversationState): Promise<ConversationState> => {
      if (input.request.kind === 'image') {
        await this.handleImageReply(input.sessionId, input.request.imageUri, input.request.userContent);
      }
      return this.copyState(input, 'image_reply');
    });
    graph.addNode('load_reply_context', async (input: ConversationState): Promise<ConversationState> => {
      this.setStep('reply_context_load');
      const next: ConversationState = this.copyState(input, 'load_reply_context');
      next.memoryContext = await this.safeGetContextForReply(input.sessionId);
      next.learnerProfileContext = await this.safeGetLearnerProfileContext(input.sessionId);
      return next;
    });
    graph.addNode('save_reply_input', async (input: ConversationState): Promise<ConversationState> => {
      await this.safeSaveUserMessage(input.sessionId, input.request.userContent);
      return this.copyState(input, 'save_reply_input');
    });
    graph.addNode('complete_reply', async (input: ConversationState): Promise<ConversationState> => {
      await this.handleCompleteReply(
        input.sessionId,
        input.memoryContext ?? '',
        input.learnerProfileContext ?? '',
        input.request.userContent,
      );
      return this.copyState(input, 'complete_reply');
    });
    graph.addNode('stream_reply', async (input: ConversationState): Promise<ConversationState> => {
      await this.handleStreamReply(
        input.sessionId,
        input.memoryContext ?? '',
        input.learnerProfileContext ?? '',
        input.request.userContent,
      );
      return this.copyState(input, 'stream_reply');
    });
    graph.addNode('note_reply', async (input: ConversationState): Promise<ConversationState> => {
      const event: NoteDraftReadyEvent | undefined = await this.generateNoteFromConversation(
        input.sessionId,
        input.request.userContent,
      );
      this.setStep('completed');
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
      this.setStep('note_context_load');
      await this.safeSaveUserMessage(input.sessionId, request.userContent);
      try {
        const event: NoteDraftReadyEvent = await new AiService(this.cbs.getContext()).regenerateNoteDraft(
          'regenerate-' + Date.now().toString(),
          request.noteId,
          request.userContent,
          request.userContent,
        );
        this.cbs.onDraftReady(event);
        await this.addAiMessage(input.sessionId, '增量预览已准备，请检查新增、修改、保留和锁定章节。');
      } catch (e) {
        await this.addAiMessage(input.sessionId, '增量重生成失败: ' + ConversationWorkflow.errorMessage(e).substring(0, 120));
      }
      return this.copyState(input, 'regenerate_reply');
    });
    graph.addConditionalEdge('START', (state: ConversationState): ConversationStep => {
      if (state.request.kind === 'image') {
        return 'image_reply';
      }
      if (state.request.kind === 'regenerate') {
        return 'regenerate_reply';
      }
      return 'classify_intent';
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
    graph.addEdge('complete_reply', 'END');
    graph.addEdge('stream_reply', 'END');
    graph.addEdge('note_reply', 'END');
    graph.addEdge('regenerate_reply', 'END');
    return graph;
  }

  private copyState(input: ConversationState, step: ConversationStep): ConversationState {
    const next: ConversationState = {
      request: input.request,
      sessionId: input.sessionId,
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
    return next;
  }

  private async handleImageReply(sessionId: string, imageUri: string, userText: string): Promise<void> {
    this.setStep('image_message_save');
    try {
      await this.safeSaveUserMessage(sessionId, userText.trim().length > 0 ? userText : '[图片]');
      this.setStep('image_recognize');
      const result: ClassificationResult = await new AiService(this.cbs.getContext()).analyzeImage(imageUri, userText);
      workflowLog.info('image analysis completed type=' + result.type);
      this.setStep('image_material_save');
      await this.safeSaveOcrResult(sessionId, imageUri, userText, result);
      const reply: string = this.formatAnalyzeReply(result);
      await this.addAiMessage(sessionId, reply);
      this.setStep('completed');
    } catch (e) {
      await this.addAiMessage(sessionId, '图片识别失败: ' + ConversationWorkflow.errorMessage(e).substring(0, 120));
    }
  }

  private async handleCompleteReply(
    sessionId: string,
    memoryContext: string,
    learnerProfileContext: string,
    userContent: string,
  ): Promise<void> {
    try {
      const configured: boolean = await LlmConfig.getInstance().isConfigured();
      if (!configured) {
        await this.addAiMessage(sessionId, '⚠️ 请先在「我的 → 设置」中配置 API Key');
        this.setStep('completed');
        return;
      }
      this.setStep('reply_model_call');
      const replyContext: ReplyContext = this.createReplyContext(memoryContext, learnerProfileContext, userContent);
      const reply: string = await this.replyService.complete(replyContext);
      await this.addAiMessage(sessionId, reply);
      await this.safeUpdateLearnerProfileIfNeeded(sessionId);
      await this.safeSummarizeIfNeeded(sessionId);
    } catch (e) {
      const errMsg: string = ConversationWorkflow.errorMessage(e);
      if (errMsg.indexOf('NO_API_KEY') >= 0) {
        await this.addAiMessage(sessionId, '⚠️ 请先在「我的 → 设置」中配置 API Key');
      } else if (ConversationWorkflow.isNetworkError(e)) {
        await this.addAiMessage(sessionId, '⚠️ 网络连接失败，请检查网络后重试');
      } else {
        await this.addAiMessage(sessionId, '⚠️ AI 回复异常: ' + errMsg.substring(0, 100));
      }
    }
  }

  /**
   * 流式回复 — 基于 DeepSeek SSE,逐 token 实时推送 UI
   * 非流式 realReply() 作为回退保留,当 callStream 失败时自动降级
   */
  private async handleStreamReply(
    sessionId: string,
    memoryContext: string,
    learnerProfileContext: string,
    userContent: string,
  ): Promise<void> {
    let streamMsgId: number | undefined = undefined;
    try {
      const configured: boolean = await LlmConfig.getInstance().isConfigured();
      if (!configured) {
        await this.addAiMessage(sessionId, '⚠️ 请先在「我的 → 设置」中配置 API Key');
        this.setStep('completed');
        return;
      }

      // 创建空消息占位,拿到 msgId
      const msgId: number = this.cbs.addAiMsgEmpty();
      streamMsgId = msgId;
      this.setStep('reply_model_call');
      const replyContext: ReplyContext = this.createReplyContext(memoryContext, learnerProfileContext, userContent);
      const streamResult: StreamReplyResult = await this.replyService.stream(
        replyContext,
        (event: StreamEvent): void => this.cbs.appendAiMsg(msgId, event),
      );
      if (streamResult.usedFallback) {
        await this.appendAssistantReply(sessionId, streamResult.content, msgId);
        return;
      }
      if (streamResult.interrupted) {
        const interruptedEvent: StreamEvent = { type: 'text', delta: '\n\n⚠️ *AI 回复中断，请重试*' };
        this.cbs.appendAiMsg(msgId, interruptedEvent);
      } else {
        this.setStep('completed');
      }
      this.cbs.finishAiMsg(msgId);
      await this.safeSaveAssistantMessage(sessionId, streamResult.content);
      if (streamResult.interrupted) {
        return;
      }
      await this.safeUpdateLearnerProfileIfNeeded(sessionId);
      await this.safeSummarizeIfNeeded(sessionId);
    } catch (e) {
      const errMsg: string = ConversationWorkflow.errorMessage(e);
      const displayError: string = errMsg.indexOf('NO_API_KEY') >= 0
        ? '⚠️ 请先在「我的 → 设置」中配置 API Key'
        : ConversationWorkflow.isNetworkError(e)
          ? '⚠️ 网络连接失败，请检查网络后重试'
          : '⚠️ AI 回复异常: ' + errMsg.substring(0, 100);
      if (streamMsgId !== undefined) {
        await this.appendAssistantReply(sessionId, displayError, streamMsgId);
      } else {
        await this.addAiMessage(sessionId, displayError);
      }
    }
  }

  private async generateNoteFromConversation(sessionId: string, userInstruction: string): Promise<NoteDraftReadyEvent | undefined> {
    this.setStep('note_intent_check');
    this.setStep('note_context_load');
    const explicitRegeneration = this.parseRegenerationRequest(userInstruction);
    if (explicitRegeneration !== undefined) {
      await this.safeSaveUserMessage(sessionId, userInstruction);
      try {
        const event: NoteDraftReadyEvent = await new AiService(this.cbs.getContext()).regenerateNoteDraft(
          'regenerate-' + Date.now().toString(),
          explicitRegeneration.noteId,
          explicitRegeneration.instruction,
          explicitRegeneration.instruction,
        );
        this.cbs.onDraftReady(event);
        await this.addAiMessage(sessionId, '增量预览已准备，请检查新增、修改、保留和锁定章节。');
        return event;
      } catch (e) {
        await this.addAiMessage(sessionId, '增量重生成失败: ' + ConversationWorkflow.errorMessage(e).substring(0, 120));
        return undefined;
      }
    }
    if (this.isIncrementalInstruction(userInstruction)) {
      await this.addAiMessage(sessionId, '请先选择要修改的明确笔记，再提出增量修改要求。');
      return undefined;
    }
    const memoryContext: string = await this.safeGetContextForNoteGeneration(sessionId);
    this.setStep('note_source_prepare');
    await this.safeSaveUserMessage(sessionId, userInstruction);
    try {
      const configured: boolean = await LlmConfig.getInstance().isConfigured();
      if (!configured) {
        await this.addAiMessage(sessionId, '⚠️ 请先在「我的 → 设置」中配置 API Key');
        return undefined;
      }

      let conversation: string = memoryContext.trim();
      if (conversation.length === 0) {
        conversation = this.cbs.getConversationText(true).trim();
      }
      if (conversation.length === 0) {
        conversation = this.intentClassifier.inlineNoteMaterial(userInstruction);
      }
      if (conversation.length === 0) {
        await this.addAiMessage(sessionId, '当前会话还没有可整理的内容');
        return undefined;
      }

      this.setStep('note_structure_save');
      const runId: string = 'conversation-' + Date.now().toString();
      const pendingRecords = await this.getMemory().getPendingNoteMaterials(sessionId);
      const pendingSources: SourceFragment[] = [];
      for (let index = 0; index < pendingRecords.length; index += 1) {
        const pending = pendingRecords[index];
        pendingSources.push({
          id: pending.id,
          kind: 'ocr',
          originId: pending.source,
          sequence: index + 1,
          fingerprint: pending.id,
          text: pending.content,
        });
      }
      const event: NoteDraftReadyEvent = await this.generateNoteDraft(runId, userInstruction, conversation, pendingSources);
      this.setStep('note_finalize');
      this.cbs.onDraftReady(event);
      await this.addAiMessage(sessionId, '笔记草稿已准备，请预览并确认保存。');
      return event;
    } catch (e) {
      const errMsg: string = ConversationWorkflow.errorMessage(e);
      await this.addAiMessage(sessionId, '生成笔记失败: ' + errMsg.substring(0, 120));
      return undefined;
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
    runId: string,
    instruction: string,
    sourceText: string,
    pendingSources: SourceFragment[],
  ): Promise<NoteDraftReadyEvent> {
    return await new AiService(this.cbs.getContext()).generateNoteDraftWithSources(
      runId,
      instruction,
      sourceText,
      pendingSources,
    );
  }


  private clip(text: string, limit: number): string {
    if (text.length <= limit) { return text; }
    return text.substring(0, limit) + '\n...';
  }

  private setStep(step: ConversationProgressStep): void {
    this.cbs.onProgress(step);
  }

  private currentSessionId(): string {
    const sessionId: string = this.cbs.getSessionId();
    return sessionId.length > 0 ? sessionId : 's1';
  }

  private getMemory(): AgentMemoryService {
    if (this.memory === null) {
      this.memory = new AgentMemoryService(this.cbs.getContext());
    }
    return this.memory;
  }

  private async addAiMessage(sessionId: string, content: string): Promise<void> {
    await this.appendAssistantReply(sessionId, content);
  }

  private async appendAssistantReply(sessionId: string, content: string, messageId?: number): Promise<void> {
    const displayContent: string = this.replyService.normalize(content);
    if (messageId === undefined) {
      this.cbs.addAiMsg(displayContent);
    } else {
      const textEvent: StreamEvent = { type: 'text', delta: displayContent };
      this.cbs.appendAiMsg(messageId, textEvent);
      this.cbs.finishAiMsg(messageId);
    }
    await this.safeSaveAssistantMessage(sessionId, displayContent);
  }

  private createReplyContext(
    memoryContext: string,
    learnerProfileContext: string,
    userContent: string,
  ): ReplyContext {
    return {
      memoryContext: memoryContext,
      learnerProfileContext: learnerProfileContext,
      userContent: userContent,
    };
  }

  private async safeSaveUserMessage(sessionId: string, content: string): Promise<void> {
    try {
      await this.getMemory().saveMessage(sessionId, 'user', content);
    } catch (e) {
      console.warn('[ConversationWorkflow] save user memory failed: ' + ConversationWorkflow.errorMessage(e));
    }
  }

  private async safeSaveAssistantMessage(sessionId: string, content: string): Promise<void> {
    try {
      await this.getMemory().saveMessage(sessionId, 'assistant', content);
    } catch (e) {
      console.warn('[ConversationWorkflow] save assistant memory failed: ' + ConversationWorkflow.errorMessage(e));
    }
  }

  private async safeSaveOcrResult(
    sessionId: string,
    imageUri: string,
    userText: string,
    result: ClassificationResult,
  ): Promise<void> {
    try {
      await this.getMemory().saveOcrResult(sessionId, imageUri, userText, result);
    } catch (e) {
      console.warn('[ConversationWorkflow] save ocr memory failed: ' + ConversationWorkflow.errorMessage(e));
    }
  }

  private async safeGetContextForReply(sessionId: string): Promise<string> {
    try {
      return await this.getMemory().getContextForReply(sessionId);
    } catch (e) {
      console.warn('[ConversationWorkflow] load reply memory failed: ' + ConversationWorkflow.errorMessage(e));
      return '';
    }
  }

  private async safeGetContextForNoteGeneration(sessionId: string): Promise<string> {
    try {
      return await this.getMemory().getContextForNoteGeneration(sessionId);
    } catch (e) {
      console.warn('[ConversationWorkflow] load note memory failed: ' + ConversationWorkflow.errorMessage(e));
      return '';
    }
  }

  private async safeGetLearnerProfileContext(sessionId: string): Promise<string> {
    try {
      return await this.getMemory().getLearnerProfileContext(sessionId);
    } catch (e) {
      console.warn('[ConversationWorkflow] load learner profile failed: ' + ConversationWorkflow.errorMessage(e));
      return '';
    }
  }

  private async safeUpdateLearnerProfileIfNeeded(sessionId: string): Promise<void> {
    try {
      await this.getMemory().updateLearnerProfileIfNeeded(sessionId);
    } catch (e) {
      console.warn('[ConversationWorkflow] update learner profile failed: ' + ConversationWorkflow.errorMessage(e));
    }
  }

  private async safeSummarizeIfNeeded(sessionId: string): Promise<void> {
    try {
      await this.getMemory().summarizeSessionIfNeeded(sessionId);
    } catch (e) {
      console.warn('[ConversationWorkflow] summarize memory failed: ' + ConversationWorkflow.errorMessage(e));
    }
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
