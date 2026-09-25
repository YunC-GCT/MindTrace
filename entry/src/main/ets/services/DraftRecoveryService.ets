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

export class DraftRecoveryService {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async restore(runId: string): Promise<NoteDraftReadyEvent> {
    return await new AiService(this.context).restoreDraft(runId);
  }

  async cancel(runId: string): Promise<void> {
    await new AiService(this.context).cancelDraft(runId);
  }

  async confirm(event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit> {
    return await new AiService(this.context).confirmDraft(event, candidate);
  }
}
