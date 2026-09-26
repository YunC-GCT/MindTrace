/**
 * ConversationWorkflowFailure.test.ets - Typed failure timeline behavior tests.
 *
 * Path: entry/src/test/ConversationWorkflowFailure.test.ets
 * Responsibility: Verify route failures surface through the workflow error event interface.
 * Dependencies: @ohos/hypium; ConversationWorkflow; injected workflow ports.
 */
import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import {
  CancellationToken,
  ClassificationResult,
  NoteDraftReadyEvent,
  NoteGenerationRoute,
  SourceFragment,
} from 'common';
import { ConversationWorkflow } from '../main/ets/workflows/conversation/ConversationWorkflow';
import {
  ConversationRequest,
  ConversationProgressStep,
  ChatMessageOrigin,
  ChatMessageOutcome,
} from '../main/ets/workflows/conversation/ConversationState';
import {
  ConversationMessageEvent,
  ConversationWorkflowCallbacks,
} from '../main/ets/workflows/conversation/ConversationTypes';
import {
  ConversationWorkflowPorts,
  IConversationCapturePort,
  IConversationIntentPort,
  IConversationReplyPort,
} from '../main/ets/workflows/conversation/ConversationWorkflowPorts';
import { ConversationRunRef } from '../main/ets/services/ConversationIdentity';
import { ReplyContext, TextIntent } from '../main/ets/services/IntentClassifier';
import { ReplyEventSink, StreamReplyResult } from '../main/ets/services/ReplyService';

class RecordingWorkflowCallbacks implements ConversationWorkflowCallbacks {
  errors: string[] = [];
  addedAnswers: string[] = [];
  terminalOutcomes: ChatMessageOutcome[] = [];
  streamTextEvents: number = 0;
  private messageId: number = 10;
  private readonly token: CancellationToken = new CancellationToken();

  addAiMsg(_ref: ConversationRunRef, content: string, _origin?: ChatMessageOrigin, _outcome?: ChatMessageOutcome): number {
    this.addedAnswers.push(content);
    this.messageId += 1;
    return this.messageId;
  }
  addAiMsgEmpty(_ref: ConversationRunRef, _origin: ChatMessageOrigin): number {
    this.messageId += 1;
    return this.messageId;
  }
  updateAiMsg(_ref: ConversationRunRef, _id: number, event: ConversationMessageEvent): void {
    if (event.kind === 'stream' && event.event.type === 'text') { this.streamTextEvents += 1; }
  }
  finishAiMsg(_ref: ConversationRunRef, _id: number, outcome?: ChatMessageOutcome): void {
    this.terminalOutcomes.push(outcome ?? 'completed');
  }
  getUserMessageId(_ref: ConversationRunRef): number { return 1; }
  async commitHistory(_ref: ConversationRunRef): Promise<boolean> { return true; }
  reportDiagnostic(_ref: ConversationRunRef, _diagnostic: string): void {}
  onStart(_ref: ConversationRunRef): void {}
  onProgress(_ref: ConversationRunRef, _step: ConversationProgressStep): void {}
  onError(_ref: ConversationRunRef, message: string): void { this.errors.push(message); }
  onFinish(_ref: ConversationRunRef): void {}
  isCurrentRun(_ref: ConversationRunRef): boolean { return true; }
  getCancellationToken(_ref: ConversationRunRef): CancellationToken | undefined { return this.token; }
  registerCancellationHook(_ref: ConversationRunRef, _hook: () => void): () => void { return noopHook; }
  getContext(): common.UIAbilityContext { throw new Error('WORKFLOW_PORTS_MUST_BE_INJECTED'); }
  getConversationText(_ref: ConversationRunRef, _excludeLatestUser: boolean): string { return 'test material'; }
  onDraftReady(_ref: ConversationRunRef, _event: NoteDraftReadyEvent): void {}
}

function noopHook(): void {}

class FixedIntentPort implements IConversationIntentPort {
  private readonly intent: TextIntent;

  constructor(intent: TextIntent) { this.intent = intent; }

  async classify(_userText: string): Promise<TextIntent> { return this.intent; }
  async classifyWithCancellation(_userText: string, _token?: CancellationToken): Promise<TextIntent> {
    return this.intent;
  }
  inlineNoteMaterial(_userText: string): string { return 'test material'; }
}

class FailingReplyPort implements IConversationReplyPort {
  private readonly route: string;

  constructor(route: string) { this.route = route; }

  async isConfigured(): Promise<boolean> { return true; }
  async complete(_context: ReplyContext, _token?: CancellationToken): Promise<string> {
    if (this.route === 'complete') { throw new Error('COMPLETE_FAILED'); }
    return 'ok';
  }
  async stream(
    _context: ReplyContext,
    _sink: ReplyEventSink,
    _token?: CancellationToken,
  ): Promise<StreamReplyResult> {
    if (this.route === 'stream') { throw new Error('STREAM_FAILED'); }
    if (this.route === 'interrupted') {
      return { content: 'partial answer', interrupted: true, usedFallback: false };
    }
    return { content: 'ok', interrupted: false, usedFallback: false };
  }
  normalize(content: string): string { return content; }
}

class FailingCapturePort implements IConversationCapturePort {
  private readonly route: string;

  constructor(route: string) { this.route = route; }

  async analyzeImage(
    _imageUri: string,
    _userText: string,
    _token?: CancellationToken,
  ): Promise<ClassificationResult> {
    throw new Error(this.route === 'image' ? 'IMAGE_FAILED' : 'UNEXPECTED_IMAGE_CALL');
  }
  async generateNoteDraftWithSources(
    _runId: string,
    _instruction: string,
    _sourceText: string,
    _pendingSources: SourceFragment[],
    _token?: CancellationToken,
    _originSessionId?: string,
    _parentConversationRunId?: string,
    _route?: NoteGenerationRoute,
  ): Promise<NoteDraftReadyEvent> {
    throw new Error(this.route === 'note' ? 'NOTE_FAILED' : 'UNEXPECTED_NOTE_CALL');
  }
  async regenerateNoteDraft(
    _runId: string,
    _noteId: string,
    _instruction: string,
    _sourceText: string,
    _token?: CancellationToken,
    _originSessionId?: string,
    _parentConversationRunId?: string,
  ): Promise<NoteDraftReadyEvent> {
    throw new Error('REGENERATE_FAILED');
  }
}

async function executeFailure(
  request: ConversationRequest,
  intent: TextIntent,
  route: string,
): Promise<RecordingWorkflowCallbacks> {
  const callbacks: RecordingWorkflowCallbacks = new RecordingWorkflowCallbacks();
  const ports: ConversationWorkflowPorts = new ConversationWorkflowPorts(
    new FixedIntentPort(intent),
    new FailingReplyPort(route),
    new FailingCapturePort(route),
  );
  const workflow: ConversationWorkflow = new ConversationWorkflow(callbacks, ports);
  try {
    await workflow.run(request, { sessionId: 's1', runId: 'r' + route });
  } catch (_error) {}
  return callbacks;
}

function expectExclusiveFailure(callbacks: RecordingWorkflowCallbacks, outcome: ChatMessageOutcome): void {
  expect(callbacks.errors.length).assertEqual(1);
  expect(callbacks.addedAnswers.length).assertEqual(0);
  expect(callbacks.streamTextEvents).assertEqual(0);
  expect(callbacks.terminalOutcomes.length).assertEqual(1);
  expect(callbacks.terminalOutcomes[0]).assertEqual(outcome);
}

export default function conversationWorkflowFailureTest(): void {
  describe('ConversationWorkflow.issue174_failure_timeline', () => {
    it('should emit a typed error for complete reply failure', 0, async () => {
      const callbacks = await executeFailure(
        { kind: 'text', userContent: 'question', responseMode: 'complete' },
        'chat',
        'complete',
      );
      expectExclusiveFailure(callbacks, 'failed');
    });

    it('should emit a typed error for stream reply failure', 0, async () => {
      const callbacks = await executeFailure(
        { kind: 'text', userContent: 'question', responseMode: 'stream' },
        'chat',
        'stream',
      );
      expectExclusiveFailure(callbacks, 'failed');
    });

    it('should emit a typed error for image failure', 0, async () => {
      const callbacks = await executeFailure(
        { kind: 'image', imageUri: 'file://image.jpg', userContent: 'question' },
        'chat',
        'image',
      );
      expectExclusiveFailure(callbacks, 'failed');
    });

    it('should emit a typed error for note generation failure', 0, async () => {
      const callbacks = await executeFailure(
        { kind: 'text', userContent: 'generate note', responseMode: 'complete' },
        'note_generation',
        'note',
      );
      expectExclusiveFailure(callbacks, 'failed');
    });

    it('should keep an interrupted stream partial out of failed answer content', 0, async () => {
      const callbacks = await executeFailure(
        { kind: 'text', userContent: 'question', responseMode: 'stream' },
        'chat',
        'interrupted',
      );
      expectExclusiveFailure(callbacks, 'interrupted');
    });
  });
}
