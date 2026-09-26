/**
 * ConversationWorkflowPorts.ets - Injectable external effects for conversation runs.
 *
 * Path: entry/src/main/ets/workflows/conversation/ConversationWorkflowPorts.ets
 * Responsibility: Keep LLM, OCR, and Capture effects behind testable workflow seams.
 * Dependencies: AiService; IntentClassifier; ReplyService; common contracts.
 *
 * Data flow:
 *   Workflow request -> typed port -> external service -> typed domain result.
 */
import { common } from '@kit.AbilityKit';
import {
  CancellationToken,
  ClassificationResult,
  LlmConfig,
  NoteDraftReadyEvent,
  NoteGenerationRoute,
  SourceFragment,
} from 'common';
import { AiService } from '../../services/AiService';
import { IntentClassifier, ReplyContext, TextIntent } from '../../services/IntentClassifier';
import { ReplyEventSink, ReplyService, StreamReplyResult } from '../../services/ReplyService';
import { ConversationRunRef } from '../../services/ConversationIdentity';

export interface IConversationIntentPort {
  classify(userText: string): Promise<TextIntent>;
  classifyWithCancellation(userText: string, token?: CancellationToken): Promise<TextIntent>;
  inlineNoteMaterial(userText: string): string;
}

export interface IConversationReplyPort {
  isConfigured(): Promise<boolean>;
  complete(context: ReplyContext, token?: CancellationToken): Promise<string>;
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
  ): Promise<NoteDraftReadyEvent>;
  regenerateNoteDraft(
    runId: string,
    noteId: string,
    instruction: string,
    sourceText: string,
    token?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
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

  inlineNoteMaterial(userText: string): string { return this.classifier.inlineNoteMaterial(userText); }
}

class ConversationReplyAdapter implements IConversationReplyPort {
  private readonly reply: ReplyService;

  constructor(reply: ReplyService) { this.reply = reply; }

  async isConfigured(): Promise<boolean> { return await LlmConfig.getInstance().isConfigured(); }

  async complete(context: ReplyContext, token?: CancellationToken): Promise<string> {
    return await this.reply.complete(context, token);
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
    );
  }

  async regenerateNoteDraft(
    runId: string,
    noteId: string,
    instruction: string,
    sourceText: string,
    token?: CancellationToken,
    originSessionId?: string,
    parentConversationRunId?: string,
  ): Promise<NoteDraftReadyEvent> {
    return await this.ai.regenerateNoteDraft(
      runId,
      noteId,
      instruction,
      sourceText,
      token,
      originSessionId,
      parentConversationRunId,
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
    return new ConversationWorkflowPorts(
      new ConversationIntentAdapter(classifier),
      new ConversationReplyAdapter(new ReplyService(classifier)),
      new ConversationCaptureAdapter(context),
      noteRoute,
    );
  }
}
