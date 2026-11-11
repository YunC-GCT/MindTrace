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
import type { EvidenceMode } from 'common';
import { ConversationRunRef } from 'common';
import { ConversationRunStartResult } from './ConversationRunCoordinator';
import { AgentChatCallbacks } from './AgentChatContracts';
import { ConversationRuntime } from './ConversationRuntime';
import { IConversationNoteRoutePort } from 'agents/src/main/ets/conversation/Index';

export { AgentChatCallbacks } from './AgentChatContracts';

export class AgentChatService {
  private readonly runtime: ConversationRuntime;

  constructor(callbacks: AgentChatCallbacks, noteRoute?: IConversationNoteRoutePort) {
    this.runtime = new ConversationRuntime(callbacks, noteRoute);
  }

  async captureReply(sessionId: string, imageUri: string, userText: string,
    evidenceMode?: EvidenceMode): Promise<ConversationRunStartResult> {
    return await this.runtime.captureReply(sessionId, imageUri, userText, evidenceMode);
  }

  async realReplyStream(sessionId: string, userContent: string,
    evidenceMode?: EvidenceMode): Promise<ConversationRunStartResult> {
    return await this.runtime.realReplyStream(sessionId, userContent, evidenceMode);
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

  async resumeNoteContextClarification(
    sessionId: string,
    runId: string,
    topicId: string,
  ): Promise<NoteDraftReadyEvent> {
    return await this.runtime.resumeNoteContextClarification(sessionId, runId, topicId);
  }

  async cancelDraft(sessionId: string, runId: string): Promise<void> {
    await this.runtime.cancelDraft(sessionId, runId);
  }

  async requestRegeneration(sessionId: string, noteId: string, instruction: string): Promise<void> {
    await this.runtime.requestRegeneration(sessionId, noteId, instruction);
  }

  async listRecoverableDrafts(): Promise<NoteGenerationRun[]> {
    return await this.runtime.listRecoverableDrafts();
  }

  async checkAndRestoreDrafts(sessionId: string): Promise<NoteDraftReadyEvent | null> {
    return await this.runtime.checkAndRestoreDrafts(sessionId);
  }
}
