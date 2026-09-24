import { ConversationWorkflow } from '../workflows/conversation/ConversationWorkflow';
import { ConversationWorkflowCallbacks } from '../workflows/conversation/ConversationTypes';
import { ConversationProgressStep, ConversationRequest, ImageConversationRequest } from '../workflows/conversation/ConversationState';
import { ChatStatusMachine } from './ChatStatusMachine';
import { common } from '@kit.AbilityKit';
import { ChatStatusMeta } from '../overlays/AgentFloatWindow/chat/ChatModels';
import { KnowledgeUnit, NoteDraftReadyEvent, NoteGenerationRun } from 'common';
import type { StreamEvent } from 'common';
import {
  ConversationRunCoordinator,
  ConversationRunRequest,
  ConversationRunRequestKind,
  ConversationRunStartResult,
  ConversationRunTerminal,
} from './ConversationRunCoordinator';
import { ConversationRunRef } from './ConversationIdentity';

type ConversationRunLifecycleOwner = 'facade' | 'workflow';
type ConversationRunOperation<T> = (ref: ConversationRunRef) => Promise<T>;

export interface AgentChatCallbacks {
  addUserMsg: (ref: ConversationRunRef, content: string) => boolean;
  addAiMsg: (ref: ConversationRunRef, content: string) => void;
  addAiMsgEmpty: (ref: ConversationRunRef) => number;
  appendAiMsg: (ref: ConversationRunRef, id: number, event: StreamEvent) => void;
  finishAiMsg: (ref: ConversationRunRef, id: number) => void;
  setBusy: (ref: ConversationRunRef, value: boolean) => void;
  setStatusMeta: (ref: ConversationRunRef, meta: ChatStatusMeta | null) => void;
  getContext: () => common.UIAbilityContext;
  getConversationText: (ref: ConversationRunRef, excludeLatestUser: boolean) => string;
  onDraftReady: (ref: ConversationRunRef, event: NoteDraftReadyEvent) => void;
  onOcrBlank?: (ref: ConversationRunRef, imageUri: string) => void;
}

export class ConversationWorkflowAdapter implements ConversationWorkflowCallbacks {
  private readonly callbacks: AgentChatCallbacks;
  private readonly statusMachine: ChatStatusMachine = new ChatStatusMachine();
  private readonly coordinator: ConversationRunCoordinator;
  constructor(callbacks: AgentChatCallbacks, coordinator: ConversationRunCoordinator) {
    this.callbacks = callbacks;
    this.coordinator = coordinator;
  }

  private accepts(ref: ConversationRunRef, event: string): boolean {
    const accepted: boolean = this.coordinator.isCurrent(ref);
    if (!accepted) {
      console.warn('[ConversationRun] code=STALE_RUN_EVENT; event=' + event
        + '; sessionId=' + ref.sessionId + '; runId=' + ref.runId);
    }
    return accepted;
  }
  addAiMsg(ref: ConversationRunRef, content: string): void { if (this.accepts(ref, 'add-ai-message')) { this.callbacks.addAiMsg(ref, content); } }
  addAiMsgEmpty(ref: ConversationRunRef): number { return this.accepts(ref, 'add-ai-placeholder') ? this.callbacks.addAiMsgEmpty(ref) : -1; }
  appendAiMsg(ref: ConversationRunRef, id: number, event: StreamEvent): void {
    if (this.accepts(ref, 'append-ai-message')) { this.callbacks.appendAiMsg(ref, id, event); }
  }
  finishAiMsg(ref: ConversationRunRef, id: number): void { if (this.accepts(ref, 'finish-ai-message')) { this.callbacks.finishAiMsg(ref, id); } }
  onStart(ref: ConversationRunRef): void {
    if (this.accepts(ref, 'start')) { this.callbacks.setBusy(ref, true); }
  }
  onProgress(ref: ConversationRunRef, step: ConversationProgressStep): void {
    if (this.accepts(ref, 'progress')) { this.callbacks.setStatusMeta(ref, this.statusMachine.advance(step)); }
  }
  onFinish(ref: ConversationRunRef): void {
    if (this.accepts(ref, 'finish') && this.coordinator.activeCount() <= 1) {
      this.callbacks.setStatusMeta(ref, null);
      this.callbacks.setBusy(ref, false);
    }
  }
  isCurrentRun(ref: ConversationRunRef): boolean { return this.coordinator.isCurrent(ref); }
  getContext(): common.UIAbilityContext { return this.callbacks.getContext(); }
  getConversationText(ref: ConversationRunRef, excludeLatestUser: boolean): string {
    return this.accepts(ref, 'read-conversation') ? this.callbacks.getConversationText(ref, excludeLatestUser) : '';
  }
  onDraftReady(ref: ConversationRunRef, event: NoteDraftReadyEvent): void { if (this.accepts(ref, 'draft-ready')) { this.callbacks.onDraftReady(ref, event); } }
  onOcrBlank?(ref: ConversationRunRef, imageUri: string): void {
    if (this.accepts(ref, 'ocr-blank') && this.callbacks.onOcrBlank !== undefined) {
      this.callbacks.onOcrBlank(ref, imageUri);
    }
  }
}

export class AgentChatService {
  private readonly workflow: ConversationWorkflow;
  private readonly callbacks: AgentChatCallbacks;
  private adapter: ConversationWorkflowAdapter | null = null;
  private readonly coordinator: ConversationRunCoordinator = new ConversationRunCoordinator();

  constructor(callbacks: AgentChatCallbacks) {
    this.callbacks = callbacks;
    this.adapter = new ConversationWorkflowAdapter(callbacks, this.coordinator);
    this.workflow = new ConversationWorkflow(this.adapter);
  }

  async captureReply(sessionId: string, imageUri: string, userText: string): Promise<void> {
    const request: ImageConversationRequest = {
      kind: 'image',
      imageUri: imageUri,
      userContent: userText,
    };
    const admission: ConversationRunStartResult = this.admit(sessionId, request.kind);
    if (!admission.accepted || admission.ref === undefined) {
      console.warn('[ConversationRun] ' + admission.diagnostic + '; entry=image');
      return;
    }
    if (!this.callbacks.addUserMsg(admission.ref, userText.length > 0 ? userText : '[图片]')) {
      this.coordinator.finish(admission.ref, 'cancelled');
      return;
    }
    await this.executeAcceptedOperation<void>(
      admission.ref,
      'workflow',
      (ref: ConversationRunRef): Promise<void> => this.workflow.run(request, ref),
    );
  }

  async realReplyStream(sessionId: string, userContent: string): Promise<void> {
    const request: ConversationRequest = {
      kind: 'text',
      userContent: userContent,
      responseMode: 'stream',
    };
    const admission: ConversationRunStartResult = this.admit(sessionId, request.kind);
    if (!admission.accepted || admission.ref === undefined) {
      console.warn('[ConversationRun] ' + admission.diagnostic + '; entry=text');
      return;
    }
    if (!this.callbacks.addUserMsg(admission.ref, userContent)) {
      this.coordinator.finish(admission.ref, 'cancelled');
      return;
    }
    await this.executeAcceptedOperation<void>(
      admission.ref,
      'workflow',
      (ref: ConversationRunRef): Promise<void> => this.workflow.run(request, ref),
    );
  }

  isCurrentRun(ref: ConversationRunRef): boolean {
    return this.coordinator.isCurrent(ref);
  }

  cancelSessionRun(sessionId: string): void {
    const ref: ConversationRunRef | undefined = this.coordinator.currentRef(sessionId);
    if (ref === undefined) { return; }
    if (this.adapter !== null) { this.adapter.onFinish(ref); }
    this.coordinator.finish(ref, 'cancelled');
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
    if (lifecycleOwner === 'facade' && this.adapter !== null) {
      this.adapter.onStart(ref);
    }
    try {
      const result: T = await operation(ref);
      this.finishOperation(ref, 'completed', lifecycleOwner);
      return result;
    } catch (error) {
      this.finishOperation(ref, 'failed', lifecycleOwner);
      throw AgentChatService.normalizeError(error);
    }
  }

  private finishOperation(
    ref: ConversationRunRef,
    terminal: ConversationRunTerminal,
    lifecycleOwner: ConversationRunLifecycleOwner,
  ): void {
    if (lifecycleOwner === 'facade' && this.adapter !== null) {
      this.adapter.onFinish(ref);
    }
    this.coordinator.finish(ref, terminal);
  }

  async confirmDraft(sessionId: string, event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit> {
    return await this.executeOperation<KnowledgeUnit>(
      sessionId,
      'confirm-draft',
      'facade',
      (ref: ConversationRunRef): Promise<KnowledgeUnit> => this.workflow.confirmDraft(ref, event, candidate),
    );
  }

  async restoreDraft(sessionId: string, runId: string): Promise<NoteDraftReadyEvent> {
    return await this.executeOperation<NoteDraftReadyEvent>(
      sessionId,
      'restore-draft',
      'facade',
      (ref: ConversationRunRef): Promise<NoteDraftReadyEvent> => this.workflow.restoreDraft(ref, runId),
    );
  }

  async retryDraft(sessionId: string, runId: string): Promise<NoteDraftReadyEvent> {
    return await this.executeOperation<NoteDraftReadyEvent>(
      sessionId,
      'retry-draft',
      'facade',
      (ref: ConversationRunRef): Promise<NoteDraftReadyEvent> => this.workflow.retryDraft(ref, runId),
    );
  }

  async cancelDraft(sessionId: string, runId: string): Promise<void> {
    await this.executeOperation<void>(
      sessionId,
      'cancel-draft',
      'facade',
      (ref: ConversationRunRef): Promise<void> => this.workflow.cancelDraft(ref, runId),
    );
  }

  async regenerateNote(sessionId: string, noteId: string, instruction: string): Promise<void> {
    await this.executeOperation<void>(
      sessionId,
      'regenerate',
      'workflow',
      (ref: ConversationRunRef): Promise<void> => this.workflow.regenerateNote(ref, noteId, instruction),
    );
  }

  async requestRegeneration(sessionId: string, noteReference: string, noteIds: string[], instruction: string): Promise<void> {
    await this.executeOperation<void>(
      sessionId,
      'regenerate',
      'workflow',
      (ref: ConversationRunRef): Promise<void> => this.workflow.requestRegeneration(
        ref,
        noteReference,
        noteIds,
        instruction,
      ),
    );
  }
  async listRecoverableDrafts(): Promise<NoteGenerationRun[]> { return await this.workflow.listRecoverableDrafts(); }

  async checkAndRestoreDrafts(sessionId: string): Promise<NoteDraftReadyEvent | null> {
    const drafts: NoteGenerationRun[] = await this.workflow.listRecoverableDrafts();
    if (drafts.length === 0) {
      return null;
    }
    const latest: NoteGenerationRun = drafts[0];
    if (latest.status === 'ready-preview' || latest.status === 'running') {
      return await this.restoreDraft(sessionId, latest.id);
    }
    return null;
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
