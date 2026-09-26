/**
 * DraftRecoveryService.ets - Recovery operations for session-bound and detached note drafts.
 *
 * Path: entry/src/main/ets/services/DraftRecoveryService.ets
 * Responsibility: Restore, cancel, and confirm note-generation drafts outside conversation orchestration.
 * Dependencies: @kit.AbilityKit; common NoteGeneration contracts; AiService.
 *
 * Data flow:
 *   persisted note-generation run -> DraftRecoveryService -> draft preview / cancel / confirm UI.
 *
 * ArkTS 1.1 strict adaptation:
 *   - Detached operations intentionally bypass ConversationWorkflow because no session owner exists.
 */
import { common } from '@kit.AbilityKit';
import { AiService } from './AiService';
import { KnowledgeUnit, NoteDraftReadyEvent } from 'common';

interface DetachedDraftContext {
  service: AiService;
  event: NoteDraftReadyEvent;
}

export class DraftRecoveryService {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async restore(runId: string): Promise<NoteDraftReadyEvent> {
    const context: DetachedDraftContext = await this.loadDetached(runId);
    return context.event;
  }

  async cancel(runId: string): Promise<void> {
    const context: DetachedDraftContext = await this.loadDetached(runId);
    await context.service.cancelDraft(runId);
  }

  async confirm(event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit> {
    DraftRecoveryService.requireDetached(event);
    const context: DetachedDraftContext = await this.loadDetached(event.runId);
    const persisted: NoteDraftReadyEvent = context.event;
    DraftRecoveryService.requireDetached(persisted);
    if (persisted.checkpointId !== event.checkpointId || persisted.candidateHash !== event.candidateHash) {
      throw new Error('DETACHED_DRAFT_CHECKPOINT_MISMATCH');
    }
    return await context.service.confirmDraft(event, candidate);
  }

  private async loadDetached(runId: string): Promise<DetachedDraftContext> {
    const service: AiService = new AiService(this.context);
    const event: NoteDraftReadyEvent = await service.restoreDraft(runId);
    DraftRecoveryService.requireDetached(event);
    return { service: service, event: event };
  }

  private static requireDetached(event: NoteDraftReadyEvent): void {
    if (event.originSessionId !== undefined || event.parentConversationRunId !== undefined) {
      throw new Error('SESSION_DRAFT_REQUIRES_CONVERSATION_ENTRY');
    }
  }
}
