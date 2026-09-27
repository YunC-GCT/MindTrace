/**
 * ConversationRuntime.ets - Conversation execution and draft lifecycle owner.
 *
 * Path: entry/src/main/ets/services/ConversationRuntime.ets
 * Responsibility: Own run admission, cancellation, workflow execution, and session-owned draft operations.
 * Dependencies: ConversationWorkflow; run/draft coordinators; UI callback adapter.
 *
 * Data flow:
 *   Accepted UI request -> run coordinator -> conversation workflow -> scoped callbacks.
 */
import { CancellationToken, KnowledgeUnit, NoteDraftReadyEvent, NoteGenerationRun } from 'common';
import {
  ConversationRequest,
  ImageConversationRequest,
} from '../workflows/conversation/ConversationState';
import { ConversationWorkflow } from '../workflows/conversation/ConversationWorkflow';
import {
  ConversationWorkflowPorts,
  IConversationNoteRoutePort,
} from '../workflows/conversation/ConversationWorkflowPorts';
import { AgentChatCallbacks } from './AgentChatContracts';
import { ConversationDraftCoordinator } from './ConversationDraftCoordinator';
import { ConversationRunRef } from './ConversationIdentity';
import {
  ConversationRunCoordinator,
  ConversationRunRequest,
  ConversationRunRequestKind,
  ConversationRunStartResult,
  ConversationRunTerminal,
} from './ConversationRunCoordinator';
import { ConversationWorkflowAdapter } from './ConversationWorkflowAdapter';

type ConversationRunLifecycleOwner = 'runtime' | 'workflow';
type ConversationRunOperation<T> = (ref: ConversationRunRef) => Promise<T>;

export class ConversationRuntime {
  private readonly workflow: ConversationWorkflow;
  private readonly callbacks: AgentChatCallbacks;
  private readonly adapter: ConversationWorkflowAdapter;
  private readonly coordinator: ConversationRunCoordinator = new ConversationRunCoordinator();
  private readonly inFlight: Map<string, Promise<void>> = new Map<string, Promise<void>>();
  private readonly draftCoordinator: ConversationDraftCoordinator;

  constructor(callbacks: AgentChatCallbacks, noteRoute?: IConversationNoteRoutePort) {
    this.callbacks = callbacks;
    this.adapter = new ConversationWorkflowAdapter(callbacks, this.coordinator);
    const ports: ConversationWorkflowPorts = ConversationWorkflowPorts.production(callbacks.getContext(), noteRoute);
    this.workflow = new ConversationWorkflow(this.adapter, ports);
    this.draftCoordinator = new ConversationDraftCoordinator(
      this.workflow,
      (
        sessionId: string,
        kind: ConversationRunRequestKind,
        operation: ConversationRunOperation<NoteDraftReadyEvent>,
      ): Promise<NoteDraftReadyEvent> => this.executeOperation<NoteDraftReadyEvent>(sessionId, kind, 'runtime', operation),
      (
        sessionId: string,
        kind: ConversationRunRequestKind,
        operation: ConversationRunOperation<KnowledgeUnit>,
      ): Promise<KnowledgeUnit> => this.executeOperation<KnowledgeUnit>(sessionId, kind, 'runtime', operation),
      (
        sessionId: string,
        kind: ConversationRunRequestKind,
        operation: ConversationRunOperation<void>,
      ): Promise<void> => this.executeOperation<void>(sessionId, kind, 'runtime', operation),
      callbacks.cancelDraftsByRun,
    );
  }

  async captureReply(sessionId: string, imageUri: string, userText: string): Promise<ConversationRunStartResult> {
    const request: ImageConversationRequest = {
      kind: 'image',
      imageUri: imageUri,
      userContent: userText,
    };
    const visibleUserText: string = userText.length > 0 ? userText : '[图片]';
    return await this.executeUserRequest(sessionId, request, visibleUserText, 'image', 'image');
  }

  async realReplyStream(sessionId: string, userContent: string): Promise<ConversationRunStartResult> {
    const request: ConversationRequest = {
      kind: 'text',
      userContent: userContent,
      responseMode: 'stream',
    };
    return await this.executeUserRequest(sessionId, request, userContent, 'chat', 'text');
  }

  isCurrentRun(ref: ConversationRunRef): boolean {
    return this.coordinator.isCurrent(ref);
  }

  getCancellationToken(ref: ConversationRunRef): CancellationToken | undefined {
    return this.coordinator.cancellationToken(ref);
  }

  async cancelSessionRun(sessionId: string): Promise<void> {
    const ref: ConversationRunRef | undefined = this.coordinator.currentRef(sessionId);
    const operation: Promise<void> | undefined = this.inFlight.get(sessionId);
    if (ref !== undefined) {
      this.callbacks.terminateAiRun(ref, 'cancelled');
      this.adapter.onFinish(ref);
      this.coordinator.cancel(ref);
    }
    let cancellationError: Error | null = null;
    if (ref !== undefined) {
      try {
        await this.draftCoordinator.cancelAssociatedDrafts(sessionId, ref.runId);
      } catch (error) {
        cancellationError = ConversationRuntime.normalizeError(error);
      }
    }
    if (operation !== undefined) {
      try {
        await operation;
      } catch (_error) {
        // The cancelled operation has already emitted its terminal lifecycle.
      }
    }
    if (cancellationError !== null) {
      throw new Error(cancellationError.message);
    }
  }

  cancelAllRuns(): void {
    const refs: ConversationRunRef[] = this.coordinator.activeRefs();
    for (const ref of refs) {
      this.callbacks.terminateAiRun(ref, 'cancelled');
      this.adapter.onFinish(ref);
      this.coordinator.cancel(ref);
    }
  }

  async confirmDraft(sessionId: string, event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit> {
    return await this.draftCoordinator.confirm(sessionId, event, candidate);
  }

  async cancelDraft(sessionId: string, runId: string): Promise<void> {
    await this.draftCoordinator.cancel(sessionId, runId);
  }

  async listRecoverableDrafts(): Promise<NoteGenerationRun[]> {
    return await this.draftCoordinator.listRecoverable();
  }

  async checkAndRestoreDrafts(sessionId: string): Promise<NoteDraftReadyEvent | null> {
    return await this.draftCoordinator.restoreForSession(sessionId);
  }

  private async executeUserRequest(
    sessionId: string,
    request: ConversationRequest,
    userContent: string,
    origin: 'image' | 'chat',
    entry: string,
  ): Promise<ConversationRunStartResult> {
    const admission: ConversationRunStartResult = this.admit(sessionId, request.kind);
    if (!admission.accepted || admission.ref === undefined) {
      console.warn('[ConversationRun] ' + admission.diagnostic + '; entry=' + entry);
      return admission;
    }
    if (this.callbacks.addUserMsg(admission.ref, userContent, origin) <= 0) {
      this.coordinator.finish(admission.ref, 'cancelled');
      return { accepted: false, diagnostic: 'code=USER_MESSAGE_REJECTED' };
    }
    await this.executeAcceptedOperation<void>(
      admission.ref,
      'workflow',
      (ref: ConversationRunRef): Promise<void> => this.workflow.run(request, ref),
    );
    return admission;
  }

  private admit(sessionId: string, kind: ConversationRunRequestKind): ConversationRunStartResult {
    const request: ConversationRunRequest = { kind: kind };
    return this.coordinator.start(sessionId, request);
  }

  private async executeOperation<T>(
    sessionId: string,
    kind: ConversationRunRequestKind,
    lifecycleOwner: ConversationRunLifecycleOwner,
    operation: ConversationRunOperation<T>,
  ): Promise<T> {
    const admission: ConversationRunStartResult = this.admit(sessionId, kind);
    if (!admission.accepted || admission.ref === undefined) {
      throw new Error(admission.diagnostic);
    }
    return await this.executeAcceptedOperation<T>(admission.ref, lifecycleOwner, operation);
  }

  private async executeAcceptedOperation<T>(
    ref: ConversationRunRef,
    lifecycleOwner: ConversationRunLifecycleOwner,
    operation: ConversationRunOperation<T>,
  ): Promise<T> {
    if (lifecycleOwner === 'runtime') {
      this.adapter.onStart(ref);
    }
    let completion: Promise<void>;
    const operationPromise: Promise<T> = (async (): Promise<T> => {
      try {
        const result: T = await operation(ref);
        this.finishOperation(ref, 'completed', lifecycleOwner);
        return result;
      } catch (error) {
        this.callbacks.terminateAiRun(ref, 'failed');
        this.finishOperation(ref, 'failed', lifecycleOwner);
        throw new Error(ConversationRuntime.normalizeError(error).message);
      }
    })();
    completion = operationPromise.then((): void => {}, (): void => {});
    this.inFlight.set(ref.sessionId, completion);
    try {
      return await operationPromise;
    } finally {
      if (this.inFlight.get(ref.sessionId) === completion) {
        this.inFlight.delete(ref.sessionId);
      }
    }
  }

  private finishOperation(
    ref: ConversationRunRef,
    terminal: ConversationRunTerminal,
    lifecycleOwner: ConversationRunLifecycleOwner,
  ): void {
    if (lifecycleOwner === 'runtime') {
      this.adapter.onFinish(ref);
    }
    this.coordinator.finish(ref, terminal);
  }

  private static normalizeError(error: Object): Error {
    if (error instanceof Error) {
      return error;
    }
    if (typeof error === 'string' && error.length > 0) {
      return new Error(error);
    }
    return new Error('UNKNOWN_CONVERSATION_OPERATION_ERROR');
  }
}
