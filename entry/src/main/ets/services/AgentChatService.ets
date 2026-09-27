/**
 * AgentChatService.ets - Thin conversation UI facade.
 *
 * Path: entry/src/main/ets/services/AgentChatService.ets
 * Responsibility: Expose UI-facing conversation commands and delegate execution to ConversationRuntime.
 * Dependencies: AgentChatContracts; ConversationRuntime; public conversation contracts.
 *
 * Data flow:
 *   UI command -> AgentChatService -> ConversationRuntime.
 */
import { KnowledgeUnit, NoteDraftReadyEvent, NoteGenerationRun } from 'common';
import { ConversationRunRef } from './ConversationIdentity';
import { ConversationRunStartResult } from './ConversationRunCoordinator';
import { AgentChatCallbacks } from './AgentChatContracts';
import { ConversationRuntime } from './ConversationRuntime';
import { IConversationNoteRoutePort } from '../workflows/conversation/ConversationWorkflowPorts';

export { AgentChatCallbacks } from './AgentChatContracts';

export class AgentChatService {
  private readonly runtime: ConversationRuntime;

  constructor(callbacks: AgentChatCallbacks, noteRoute?: IConversationNoteRoutePort) {
    this.runtime = new ConversationRuntime(callbacks, noteRoute);
  }

  async captureReply(sessionId: string, imageUri: string, userText: string): Promise<ConversationRunStartResult> {
    return await this.runtime.captureReply(sessionId, imageUri, userText);
  }

  async realReplyStream(sessionId: string, userContent: string): Promise<ConversationRunStartResult> {
    return await this.runtime.realReplyStream(sessionId, userContent);
  }

  isCurrentRun(ref: ConversationRunRef): boolean {
    return this.runtime.isCurrentRun(ref);
  }

  async cancelSessionRun(sessionId: string): Promise<void> {
    await this.runtime.cancelSessionRun(sessionId);
  }

  cancelAllRuns(): void {
    this.runtime.cancelAllRuns();
  }

  async confirmDraft(sessionId: string, event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit> {
    return await this.runtime.confirmDraft(sessionId, event, candidate);
  }

  async cancelDraft(sessionId: string, runId: string): Promise<void> {
    await this.runtime.cancelDraft(sessionId, runId);
  }

  async listRecoverableDrafts(): Promise<NoteGenerationRun[]> {
    return await this.runtime.listRecoverableDrafts();
  }

  async checkAndRestoreDrafts(sessionId: string): Promise<NoteDraftReadyEvent | null> {
    return await this.runtime.checkAndRestoreDrafts(sessionId);
  }
}
