/**
 * ConversationWorkflowPorts.ets — 对话图的端口集合与默认适配器
 *
 * 路径: agents/src/main/ets/conversation/ConversationWorkflowPorts.ets
 * 职责: 定义意图 / 回复 / 抽取 / 草稿服务 / 记忆服务 / 证据 / 复习七组端口，
 *       并提供规则型默认适配器；AiService / AgentMemoryService 的实现由 entry 组合根注入
 * 依赖: common、../chat/*、./ConversationToolReplyFlags、./ConversationServicePorts
 *
 * 数据流:
 *   entry ConversationWorkflowPortsFactory → 本文件端口 → ConversationWorkflow
 */
import {
  CancellationToken,
  ChatMessage,
  ClassificationResult,
  LlmCallResult,
  LlmClient,
  LlmConfig,
  LocalChatProvider,
  Logger,
  NoteContextClarification,
  NoteDraftReadyEvent,
  NoteGenerationProgressSink,
  NoteGenerationRoute,
  NoteTopicCandidate,
  SourceBundle,
  SourceFragment,
  ToolCatalog,
  ToolLoop,
  ToolRegistry,
} from 'common';
import type { StreamEvent, ToolLoopOptions } from 'common';
import { ConversationRunRef } from 'common';
import type { NoteEvidencePort, NoteReviewPort } from 'common';
import { IntentClassifier } from '../chat/IntentClassifier';
import type { ReplyContext, TextIntent } from '../chat/IntentClassifier';
import { ReplyService } from '../chat/ReplyService';
import type { ReplyEventSink, StreamReplyResult } from '../chat/ReplyService';
import { ModelRouter } from '../chat/ModelRouter';
import type { RoutedReply } from '../chat/ModelRouter';
import { ConversationToolReplyFlags } from './ConversationToolReplyFlags';
import type { IConversationDraftServicePort, IConversationMemoryServicePort } from './ConversationServicePorts';

const replyPortLog: Logger = new Logger('ConversationReplyPort');

export interface IConversationIntentPort {
  classify(userText: string): Promise<TextIntent>;
  classifyWithCancellation(userText: string, token?: CancellationToken): Promise<TextIntent>;
  classifyLocalIntent(userText: string): TextIntent | undefined;
  inlineNoteMaterial(userText: string): string;
}

export interface IConversationReplyPort {
  isConfigured(): Promise<boolean>;
  complete(context: ReplyContext, token?: CancellationToken): Promise<string>;
  completeRouted(context: ReplyContext, token?: CancellationToken): Promise<RoutedReply>;
  stream(context: ReplyContext, sink: ReplyEventSink, token?: CancellationToken): Promise<StreamReplyResult>;
  normalize(content: string): string;
}

/** Chat 工具回复端口（spec 041，默认关闭）：只读工具循环，非流式。 */
export interface IConversationToolPort {
  isEnabled(): boolean;
  complete(context: ReplyContext, token?: CancellationToken): Promise<string>;
}

export interface IConversationCapturePort {
  analyzeImage(imageUri: string, userText: string, token?: CancellationToken): Promise<ClassificationResult>;
  generateNoteDraftWithSources(
    runId: string,
    instruction: string,
    sourceText: string,
    pendingSources: SourceFragment[],
    token?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    route?: NoteGenerationRoute,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent>;
  generateNoteDraftWithBundle(
    runId: string,
    instruction: string,
    bundle: SourceBundle,
    pendingSourceIds: string[],
    contextBudgetTokens: number,
    token?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    route?: NoteGenerationRoute,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent>;
  saveNoteContextClarification(
    runId: string,
    instruction: string,
    bundle: SourceBundle,
    topics: NoteTopicCandidate[],
    pendingSourceIds: string[],
    contextBudgetTokens: number,
    originSessionId?: string,
    parentConversationRunId?: string,
    route?: NoteGenerationRoute,
  ): Promise<NoteContextClarification>;
  resumeNoteContextClarification(
    runId: string,
    topicId: string,
    token?: CancellationToken,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent>;
  regenerateNoteDraft(
    runId: string,
    noteId: string,
    instruction: string,
    sourceText: string,
    token?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent>;
}

export interface IConversationNoteRoutePort {
  select(ref: ConversationRunRef): NoteGenerationRoute | undefined;
}

class AutomaticConversationNoteRouteAdapter implements IConversationNoteRoutePort {
  select(_ref: ConversationRunRef): NoteGenerationRoute | undefined { return undefined; }
}

class ConversationIntentAdapter implements IConversationIntentPort {
  private readonly classifier: IntentClassifier;

  constructor(classifier: IntentClassifier) { this.classifier = classifier; }

  async classify(userText: string): Promise<TextIntent> { return await this.classifier.classify(userText); }

  async classifyWithCancellation(userText: string, token?: CancellationToken): Promise<TextIntent> {
    return await this.classifier.classifyWithCancellation(userText, token);
  }

  classifyLocalIntent(userText: string): TextIntent | undefined {
    return this.classifier.classifyLocalIntent(userText);
  }

  inlineNoteMaterial(userText: string): string { return this.classifier.inlineNoteMaterial(userText); }
}

class ConversationReplyAdapter implements IConversationReplyPort {
  private readonly reply: ReplyService;
  private readonly router: ModelRouter;
  private localChat?: LocalChatProvider;

  constructor(reply: ReplyService, router: ModelRouter) {
    this.reply = reply;
    this.router = router;
  }

  /** production() 注入与 ModelRouter 共享的同一个 LocalChatProvider，避免二次 init 与状态分叉。 */
  attachLocalChat(localChat: LocalChatProvider): void {
    this.localChat = localChat;
  }

  async isConfigured(): Promise<boolean> { return await LlmConfig.getInstance().isConfigured(); }

  async completeRouted(context: ReplyContext, token?: CancellationToken): Promise<RoutedReply> {
    token?.throwIfCancelled();
    const routed: RoutedReply = await this.router.answer(context);
    replyPortLog.info('source=' + routed.source
      + ' degraded=' + routed.degraded.toString()
      + ' reason=' + routed.reason
      + ' chars=' + routed.text.length.toString());
    return routed;
  }

  async complete(context: ReplyContext, token?: CancellationToken): Promise<string> {
    const routed: RoutedReply = await this.completeRouted(context, token);
    if (routed.degraded) {
      return routed.text + '\n\n（已降级：' + routed.reason + '）';
    }
    return routed.text;
  }

  async stream(
    context: ReplyContext,
    sink: ReplyEventSink,
    token?: CancellationToken,
  ): Promise<StreamReplyResult> {
    token?.throwIfCancelled();
    const localChat: LocalChatProvider | undefined = this.localChat;

    // 端侧就绪优先：真流式回调直接转成 text delta；失败不在本层兜底，
    // 交给 ConversationWorkflow.recoverStreamReply 统一 fallback + 标注。
    if (localChat !== undefined && localChat.isReady()) {
      const startedAt: number = Date.now();
      let cancelled: boolean = false;
      replyPortLog.info('[StreamRoute] source=on_device');
      const content: string = await localChat.askStream(
        context.userContent,
        (chunk: string, _finished: boolean): void => {
          if (cancelled || chunk.length === 0) {
            return;
          }
          if (token !== undefined && token.isCancelled()) {
            cancelled = true;
            return;
          }
          const textEvent: StreamEvent = { type: 'text', delta: chunk };
          sink(textEvent);
        },
      );
      token?.throwIfCancelled();
      replyPortLog.info('[StreamRoute] source=on_device chars=' + content.length.toString()
        + ' elapsedMs=' + (Date.now() - startedAt).toString());
      const onDeviceResult: StreamReplyResult = {
        content: content,
        interrupted: false,
        usedFallback: false,
      };
      return onDeviceResult;
    }

    replyPortLog.info('[StreamRoute] source=remote');
    return await this.reply.stream(context, sink, token);
  }

  normalize(content: string): string { return this.reply.normalize(content); }
}

class ConversationToolAdapter implements IConversationToolPort {
  private readonly classifier: IntentClassifier;

  constructor(classifier: IntentClassifier) { this.classifier = classifier; }

  isEnabled(): boolean { return ConversationToolReplyFlags.isEnabled(); }

  async complete(context: ReplyContext, token?: CancellationToken): Promise<string> {
    token?.throwIfCancelled();
    const registry: ToolRegistry = ToolCatalog.createReadOnlyRegistry();
    const messages: ChatMessage[] = this.classifier.buildReplyMessages(context, 'markdown');
    const options: ToolLoopOptions = { callOptions: { cancellationToken: token } };
    const loop: ToolLoop = new ToolLoop(new LlmClient());
    const result: LlmCallResult = await loop.run(messages, registry, options);
    token?.throwIfCancelled();
    return result.text !== undefined ? result.text : '';
  }
}

export class ConversationWorkflowPorts {
  readonly intent: IConversationIntentPort;
  readonly reply: IConversationReplyPort;
  readonly capture: IConversationCapturePort;
  readonly noteRoute: IConversationNoteRoutePort;
  readonly toolReply?: IConversationToolPort;
  /** 草稿服务与记忆服务的实现留在 entry，由组合根注入。 */
  readonly draftService?: IConversationDraftServicePort;
  readonly memoryService?: IConversationMemoryServicePort;
  /** 证据 / 复习实现同样由组合根注入（entry 持有 RDB 与 RAG）。 */
  readonly evidence?: NoteEvidencePort;
  readonly review?: NoteReviewPort;

  constructor(
    intent: IConversationIntentPort,
    reply: IConversationReplyPort,
    capture: IConversationCapturePort,
    noteRoute?: IConversationNoteRoutePort,
    toolReply?: IConversationToolPort,
    draftService?: IConversationDraftServicePort,
    memoryService?: IConversationMemoryServicePort,
    evidence?: NoteEvidencePort,
    review?: NoteReviewPort,
  ) {
    this.intent = intent;
    this.reply = reply;
    this.capture = capture;
    this.noteRoute = noteRoute ?? new AutomaticConversationNoteRouteAdapter();
    this.toolReply = toolReply;
    this.draftService = draftService;
    this.memoryService = memoryService;
    this.evidence = evidence;
    this.review = review;
  }
}

/** 组合根输入：只收 entry 才能构造的实现（AiService / AgentMemoryService / RDB 证据链）。 */
export interface ConversationWorkflowPortsInput {
  filesDir: string;
  capture: IConversationCapturePort;
  draftService: IConversationDraftServicePort;
  memoryService: IConversationMemoryServicePort;
  evidence: NoteEvidencePort;
  review: NoteReviewPort;
  noteRoute?: IConversationNoteRoutePort;
}

export class ConversationWorkflowPortsFactory {
  static production(input: ConversationWorkflowPortsInput): ConversationWorkflowPorts {
    const classifier: IntentClassifier = new IntentClassifier();
    const replyService: ReplyService = new ReplyService(classifier);
    const localChat: LocalChatProvider = new LocalChatProvider();
    // 不阻塞 production()：init 失败由 provider 内部记录并返回 false，router 继续走云端/报错
    localChat.init().then((ready: boolean): void => {
      replyPortLog.info('localChat init result=' + ready.toString());
    }).catch((e: Error): void => {
      replyPortLog.error('localChat init crashed: ' + e.message);
    });
    const router: ModelRouter = new ModelRouter(input.filesDir, replyService, localChat);
    // 保持既有构造签名不变；流式路由复用同一个 localChat 实例
    const replyAdapter: ConversationReplyAdapter = new ConversationReplyAdapter(replyService, router);
    replyAdapter.attachLocalChat(localChat);
    return new ConversationWorkflowPorts(
      new ConversationIntentAdapter(classifier),
      replyAdapter,
      input.capture,
      input.noteRoute,
      new ConversationToolAdapter(classifier),
      input.draftService,
      input.memoryService,
      input.evidence,
      input.review,
    );
  }
}
