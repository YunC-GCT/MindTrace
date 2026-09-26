/**
 * ConversationWorkflowAdapter.ets - Session-scoped workflow-to-UI adapter.
 *
 * Path: entry/src/main/ets/services/ConversationWorkflowAdapter.ets
 * Responsibility: Reject stale events and translate workflow lifecycle events into the run sink.
 * Dependencies: AgentChatContracts; ConversationRunCoordinator; ChatStatusMachine.
 *
 * Data flow:
 *   Workflow callback -> current-run guard -> typed UI event sink.
 */
import { common } from '@kit.AbilityKit';
import { CancellationToken, NoteDraftReadyEvent } from 'common';
import {
  ConversationMessageEvent,
  ConversationWorkflowCallbacks,
} from '../workflows/conversation/ConversationTypes';
import {
  ChatMessageOrigin,
  ChatMessageOutcome,
  ConversationProgressStep,
} from '../workflows/conversation/ConversationState';
import { ChatStatusMeta } from '../overlays/AgentFloatWindow/chat/ChatModels';
import { AgentChatCallbacks } from './AgentChatContracts';
import { ChatStatusMachine } from './ChatStatusMachine';
import { ConversationRunCoordinator } from './ConversationRunCoordinator';
import { ConversationRunRef } from './ConversationIdentity';

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

  addAiMsg(ref: ConversationRunRef, content: string, origin?: ChatMessageOrigin, outcome?: ChatMessageOutcome): number {
    return this.accepts(ref, 'add-ai-message')
      ? this.callbacks.addAiMsg(ref, content, origin ?? 'chat', outcome ?? 'completed')
      : -1;
  }

  addAiMsgEmpty(ref: ConversationRunRef, origin: ChatMessageOrigin): number {
    return this.accepts(ref, 'add-ai-placeholder') ? this.callbacks.addAiMsgEmpty(ref, origin) : -1;
  }

  updateAiMsg(ref: ConversationRunRef, id: number, event: ConversationMessageEvent): void {
    if (this.accepts(ref, 'update-ai-message')) { this.callbacks.updateAiMsg(ref, id, event); }
  }

  finishAiMsg(ref: ConversationRunRef, id: number, outcome?: ChatMessageOutcome): void {
    if (this.accepts(ref, 'finish-ai-message')) { this.callbacks.finishAiMsg(ref, id, outcome ?? 'completed'); }
  }

  onStart(ref: ConversationRunRef): void {
    if (this.accepts(ref, 'start')) { this.callbacks.setBusy(ref, true); }
  }

  onProgress(ref: ConversationRunRef, step: ConversationProgressStep): void {
    if (!this.accepts(ref, 'progress')) { return; }
    const meta: ChatStatusMeta = this.statusMachine.advance(step);
    const event: ConversationMessageEvent = {
      kind: 'status',
      content: meta.title + ' · ' + meta.detail,
      status: step === 'completed' ? 'success' : 'running',
    };
    this.callbacks.updateRunEvent(ref, event);
  }

  onError(ref: ConversationRunRef, message: string): void {
    if (!this.accepts(ref, 'error')) { return; }
    const event: ConversationMessageEvent = { kind: 'error', content: message };
    this.callbacks.updateRunEvent(ref, event);
  }

  onFinish(ref: ConversationRunRef): void {
    if (this.accepts(ref, 'finish')) { this.callbacks.setBusy(ref, false); }
  }

  isCurrentRun(ref: ConversationRunRef): boolean { return this.coordinator.isCurrent(ref); }

  getCancellationToken(ref: ConversationRunRef): CancellationToken | undefined {
    return this.coordinator.cancellationToken(ref);
  }

  registerCancellationHook(ref: ConversationRunRef, hook: () => void): () => void {
    return this.coordinator.registerCancellationHook(ref, hook);
  }

  getContext(): common.UIAbilityContext { return this.callbacks.getContext(); }

  getConversationText(ref: ConversationRunRef, excludeLatestUser: boolean): string {
    return this.accepts(ref, 'read-conversation') ? this.callbacks.getConversationText(ref, excludeLatestUser) : '';
  }

  getUserMessageId(ref: ConversationRunRef): number {
    return this.accepts(ref, 'read-user-message-id') ? this.callbacks.getUserMessageId(ref) : -1;
  }

  async commitHistory(ref: ConversationRunRef): Promise<boolean> {
    return this.accepts(ref, 'commit-history') ? await this.callbacks.commitHistory(ref) : false;
  }

  reportDiagnostic(ref: ConversationRunRef, diagnostic: string): void {
    if (this.accepts(ref, 'report-diagnostic')) { this.callbacks.reportDiagnostic(ref, diagnostic); }
  }

  onDraftReady(ref: ConversationRunRef, event: NoteDraftReadyEvent): void {
    if (this.accepts(ref, 'draft-ready')) { this.callbacks.onDraftReady(ref, event); }
  }

  onOcrBlank?(ref: ConversationRunRef, imageUri: string): void {
    if (this.accepts(ref, 'ocr-blank') && this.callbacks.onOcrBlank !== undefined) {
      this.callbacks.onOcrBlank(ref, imageUri);
    }
  }
}
