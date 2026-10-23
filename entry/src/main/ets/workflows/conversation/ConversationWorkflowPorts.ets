/**
 * ConversationWorkflowPorts.ets - Injectable external effects for conversation runs.
 *
 * Path: entry/src/main/ets/workflows/conversation/ConversationWorkflowPorts.ets
 * Responsibility: Keep LLM, OCR, and Capture effects behind testable workflow seams.
 * Dependencies: AiService; IntentClassifier; ReplyService; ModelRouter; LocalChatProvider; common contracts.
 *
 * Data flow:
 *   Workflow request -> typed port -> external service -> typed domain result.
 */
import { common } from '@kit.AbilityKit';
import {
  CancellationToken,
  ClassificationResult,
  LlmConfig,
  LocalChatProvider,
  Logger,
  NoteDraftReadyEvent,
  NoteGenerationRoute,
  NoteGenerationProgressSink,
  NoteContextClarification,
  SourceFragment,
  SourceBundle,
  NoteTopicCandidate,
} from 'common';
import { AiService } from '../../services/AiService';
import { IntentClassifier, ReplyContext, TextIntent } from '../../services/IntentClassifier';
import { ReplyEventSink, ReplyService, StreamReplyResult } from '../../services/ReplyService';
import { ConversationRunRef } from '../../services/ConversationIdentity';
import { ModelRouter } from '../../services/ModelRouter';
import type { RoutedReply } from '../../services/ModelRouter';

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

  constructor(reply: ReplyService, router: ModelRouter) {
    this.reply = reply;
    this.router = router;
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
    return await this.reply.stream(context, sink, token);
  }

  normalize(content: string): string { return this.reply.normalize(content); }
}

class ConversationCaptureAdapter implements IConversationCapturePort {
  private readonly ai: AiService;

  constructor(context: common.UIAbilityContext) { this.ai = new AiService(context); }

  async analyzeImage(
    imageUri: string,
    userText: string,
    token?: CancellationToken,
  ): Promise<ClassificationResult> {
    return await this.ai.analyzeImage(imageUri, userText, token);
  }

  async generateNoteDraftWithSources(
    runId: string,
    instruction: string,
    sourceText: string,
    pendingSources: SourceFragment[],
    token?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    route?: NoteGenerationRoute,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    return await this.ai.generateNoteDraftWithSources(
      runId,
      instruction,
      sourceText,
      pendingSources,
      token,
      originSessionId,
      parentConversationRunId,
      route,
      progressSink,
    );
  }

  async generateNoteDraftWithBundle(
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
  ): Promise<NoteDraftReadyEvent> {
    return await this.ai.generateNoteDraftWithBundle(
      runId,
      instruction,
      bundle,
      pendingSourceIds,
      contextBudgetTokens,
      token,
      originSessionId,
      parentConversationRunId,
      route,
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
    route?: NoteGenerationRoute,
  ): Promise<NoteContextClarification> {
    return await this.ai.saveNoteContextClarification(
      runId,
      instruction,
      bundle,
      topics,
      pendingSourceIds,
      contextBudgetTokens,
      originSessionId,
      parentConversationRunId,
      route,
    );
  }

  async resumeNoteContextClarification(
    runId: string,
    topicId: string,
    token?: CancellationToken,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    return await this.ai.resumeNoteContextClarification(runId, topicId, token, progressSink);
  }

  async regenerateNoteDraft(
    runId: string,
    noteId: string,
    instruction: string,
    sourceText: string,
    token?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
    progressSink?: NoteGenerationProgressSink,
  ): Promise<NoteDraftReadyEvent> {
    return await this.ai.regenerateNoteDraft(
      runId,
      noteId,
      instruction,
      sourceText,
      token,
      originSessionId,
      parentConversationRunId,
      progressSink,
    );
  }
}

export class ConversationWorkflowPorts {
  readonly intent: IConversationIntentPort;
  readonly reply: IConversationReplyPort;
  readonly capture: IConversationCapturePort;
  readonly noteRoute: IConversationNoteRoutePort;

  constructor(
    intent: IConversationIntentPort,
    reply: IConversationReplyPort,
    capture: IConversationCapturePort,
    noteRoute?: IConversationNoteRoutePort,
  ) {
    this.intent = intent;
    this.reply = reply;
    this.capture = capture;
    this.noteRoute = noteRoute ?? new AutomaticConversationNoteRouteAdapter();
  }

  static production(
    context: common.UIAbilityContext,
    noteRoute?: IConversationNoteRoutePort,
  ): ConversationWorkflowPorts {
    const classifier: IntentClassifier = new IntentClassifier();
    const replyService: ReplyService = new ReplyService(classifier);
    const localChat: LocalChatProvider = new LocalChatProvider();
    // 不阻塞 production()：init 失败由 provider 内部记录并返回 false，router 继续走云端/报错
    localChat.init().then((ready: boolean): void => {
      replyPortLog.info('localChat init result=' + ready.toString());
    }).catch((e: Error): void => {
      replyPortLog.error('localChat init crashed: ' + e.message);
    });
    const router: ModelRouter = new ModelRouter(context.filesDir, replyService, localChat);
    return new ConversationWorkflowPorts(
      new ConversationIntentAdapter(classifier),
      new ConversationReplyAdapter(replyService, router),
      new ConversationCaptureAdapter(context),
      noteRoute,
    );
  }
}
