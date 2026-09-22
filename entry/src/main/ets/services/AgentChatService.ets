import { ConversationWorkflow } from '../workflows/conversation/ConversationWorkflow';
import { ConversationWorkflowCallbacks } from '../workflows/conversation/ConversationTypes';
import { ConversationProgressStep, ConversationRequest, ImageConversationRequest } from '../workflows/conversation/ConversationState';
import { ChatStatusMachine } from './ChatStatusMachine';
import { common } from '@kit.AbilityKit';
import { ChatStatusMeta } from '../overlays/AgentFloatWindow/chat/ChatModels';
import { KnowledgeUnit, NoteDraftReadyEvent, NoteGenerationRun } from 'common';
import type { StreamEvent } from 'common';

export interface AgentChatCallbacks {
  addAiMsg: (content: string) => void;
  addAiMsgEmpty: () => number;
  appendAiMsg: (id: number, event: StreamEvent) => void;
  finishAiMsg: (id: number) => void;
  setBusy: (value: boolean) => void;
  setStatusMeta: (meta: ChatStatusMeta | null) => void;
  getContext: () => common.UIAbilityContext;
  getConversationText: (excludeLatestUser: boolean) => string;
  getSessionId: () => string;
  onDraftReady: (event: NoteDraftReadyEvent) => void;
}

class ConversationWorkflowAdapter implements ConversationWorkflowCallbacks {
  private readonly callbacks: AgentChatCallbacks;
  private readonly statusMachine: ChatStatusMachine = new ChatStatusMachine();
  private activeRuns: number = 0;
  private readonly serviceRef: AgentChatService;
  constructor(callbacks: AgentChatCallbacks, serviceRef: AgentChatService) {
    this.callbacks = callbacks;
    this.serviceRef = serviceRef;
  }

  addAiMsg(content: string): void { this.callbacks.addAiMsg(content); }
  addAiMsgEmpty(): number { return this.callbacks.addAiMsgEmpty(); }
  appendAiMsg(id: number, event: StreamEvent): void {
    this.callbacks.appendAiMsg(id, event);
  }
  finishAiMsg(id: number): void { this.callbacks.finishAiMsg(id); }
  onStart(): void {
    this.activeRuns += 1;
    this.serviceRef.notifyBusyChange(true);
    this.callbacks.setBusy(true);
  }
  onProgress(step: ConversationProgressStep): void {
    this.callbacks.setStatusMeta(this.statusMachine.advance(step));
  }
  onFinish(): void {
    if (this.activeRuns <= 0) {
      return;
    }
    this.activeRuns -= 1;
    if (this.activeRuns > 0) {
      return;
    }
    this.serviceRef.notifyBusyChange(false);
    this.callbacks.setStatusMeta(null);
    this.callbacks.setBusy(false);
  }
  getContext(): common.UIAbilityContext { return this.callbacks.getContext(); }
  getConversationText(excludeLatestUser: boolean): string {
    return this.callbacks.getConversationText(excludeLatestUser);
  }
  getSessionId(): string { return this.callbacks.getSessionId(); }
  onDraftReady(event: NoteDraftReadyEvent): void { this.callbacks.onDraftReady(event); }
  onOcrBlank?(imageUri: string): void { return; }
}

export class AgentChatService {
  private readonly workflow: ConversationWorkflow;
  private busyRunCount: number = 0;
  private adapter: ConversationWorkflowAdapter | null = null;

  constructor(callbacks: AgentChatCallbacks) {
    this.adapter = new ConversationWorkflowAdapter(callbacks, this);
    this.workflow = new ConversationWorkflow(this.adapter);
  }

  notifyBusyChange(busy: boolean): void {
    if (busy) {
      this.busyRunCount += 1;
    } else {
      this.busyRunCount = Math.max(0, this.busyRunCount - 1);
    }
  }

  async captureReply(imageUri: string, userText: string): Promise<void> {
    if (this.busyRunCount > 0) {
      return;
    }
    const request: ImageConversationRequest = {
      kind: 'image',
      imageUri: imageUri,
      userContent: userText,
    };
    await this.workflow.run(request);
  }

  async realReplyStream(userContent: string): Promise<void> {
    if (this.busyRunCount > 0) {
      return;
    }
    const request: ConversationRequest = {
      kind: 'text',
      userContent: userContent,
      responseMode: 'stream',
    };
    await this.workflow.run(request);
  }

  async confirmDraft(event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit> {
    return this.workflow.confirmDraft(event, candidate);
  }

  async restoreDraft(runId: string): Promise<NoteDraftReadyEvent> { return await this.workflow.restoreDraft(runId); }
  async retryDraft(runId: string): Promise<NoteDraftReadyEvent> { return await this.workflow.retryDraft(runId); }
  async cancelDraft(runId: string): Promise<void> { await this.workflow.cancelDraft(runId); }
  async regenerateNote(noteId: string, instruction: string): Promise<void> { await this.workflow.regenerateNote(noteId, instruction); }
  async requestRegeneration(noteReference: string, noteIds: string[], instruction: string): Promise<void> { await this.workflow.requestRegeneration(noteReference, noteIds, instruction); }
  async listRecoverableDrafts(): Promise<NoteGenerationRun[]> { return await this.workflow.listRecoverableDrafts(); }

  async checkAndRestoreDrafts(): Promise<NoteDraftReadyEvent | null> {
    const drafts: NoteGenerationRun[] = await this.workflow.listRecoverableDrafts();
    if (drafts.length === 0) {
      return null;
    }
    const latest: NoteGenerationRun = drafts[0];
    if (latest.status === 'ready-preview' || latest.status === 'running') {
      return await this.workflow.restoreDraft(latest.id);
    }
    return null;
  }
}
