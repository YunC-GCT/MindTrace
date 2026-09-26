/**
 * ConversationDraftCoordinator.ets - Session-owned draft command coordinator.
 *
 * Path: entry/src/main/ets/services/ConversationDraftCoordinator.ets
 * Responsibility: enumerate/filter drafts and route owned operations through the
 * conversation run executor. Detached drafts remain owned by DraftRecoveryService.
 * Dependencies: ConversationWorkflow; ConversationRunCoordinator; common draft contracts.
 *
 * Data flow:
 *   UI draft command -> ownership lookup -> conversation run executor -> workflow operation.
 */
import { KnowledgeUnit, NoteDraftReadyEvent, NoteGenerationRun } from 'common';
import { ConversationWorkflow } from '../workflows/conversation/ConversationWorkflow';
import {
  ConversationRunRequestKind,
} from './ConversationRunCoordinator';
import { ConversationRunRef } from './ConversationIdentity';

type DraftEventExecutor = (
  sessionId: string,
  kind: ConversationRunRequestKind,
  operation: (ref: ConversationRunRef) => Promise<NoteDraftReadyEvent>,
) => Promise<NoteDraftReadyEvent>;
type DraftKnowledgeExecutor = (
  sessionId: string,
  kind: ConversationRunRequestKind,
  operation: (ref: ConversationRunRef) => Promise<KnowledgeUnit>,
) => Promise<KnowledgeUnit>;
type DraftVoidExecutor = (
  sessionId: string,
  kind: ConversationRunRequestKind,
  operation: (ref: ConversationRunRef) => Promise<void>,
) => Promise<void>;

export class ConversationDraftCoordinator {
  private readonly workflow: ConversationWorkflow;
  private readonly executeEvent: DraftEventExecutor;
  private readonly executeKnowledge: DraftKnowledgeExecutor;
  private readonly executeVoid: DraftVoidExecutor;
  private readonly cancelAssociated: ((sessionId: string, parentRunId: string) => Promise<void>) | undefined;

  constructor(
    workflow: ConversationWorkflow,
    executeEvent: DraftEventExecutor,
    executeKnowledge: DraftKnowledgeExecutor,
    executeVoid: DraftVoidExecutor,
    cancelAssociated?: (sessionId: string, parentRunId: string) => Promise<void>,
  ) {
    this.workflow = workflow;
    this.executeEvent = executeEvent;
    this.executeKnowledge = executeKnowledge;
    this.executeVoid = executeVoid;
    this.cancelAssociated = cancelAssociated;
  }

  async listRecoverable(): Promise<NoteGenerationRun[]> {
    return await this.workflow.listRecoverableDrafts();
  }

  async restoreForSession(sessionId: string): Promise<NoteDraftReadyEvent | null> {
    const draft: NoteGenerationRun | undefined = await this.findOwnedDraft(sessionId);
    if (draft === undefined) {
      return null;
    }
    return await this.executeEvent(
      sessionId,
      'restore-draft',
      (ref: ConversationRunRef): Promise<NoteDraftReadyEvent> => this.workflow.restoreDraft(ref, draft.id),
    );
  }

  async confirm(
    sessionId: string,
    event: NoteDraftReadyEvent,
    candidate: KnowledgeUnit,
  ): Promise<KnowledgeUnit> {
    return await this.executeKnowledge(
      sessionId,
      'confirm-draft',
      (ref: ConversationRunRef): Promise<KnowledgeUnit> => this.workflow.confirmDraft(ref, event, candidate),
    );
  }

  async cancel(sessionId: string, runId: string): Promise<void> {
    await this.executeVoid(
      sessionId,
      'cancel-draft',
      (ref: ConversationRunRef): Promise<void> => this.workflow.cancelDraft(ref, runId),
    );
  }

  async cancelAssociatedDrafts(sessionId: string, parentRunId: string): Promise<void> {
    if (this.cancelAssociated !== undefined) {
      await this.cancelAssociated(sessionId, parentRunId);
    }
  }

  private async findOwnedDraft(sessionId: string): Promise<NoteGenerationRun | undefined> {
    const drafts: NoteGenerationRun[] = await this.listRecoverable();
    for (const draft of drafts) {
      const owned: boolean = draft.originSessionId === sessionId
        && (draft.status === 'ready-preview' || draft.status === 'running');
      if (owned) {
        return draft;
      }
    }
    return undefined;
  }
}
