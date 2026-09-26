/**
 * ConversationDraftOwnership.test.ets - Session-owned draft recovery behavior tests.
 *
 * Path: entry/src/test/ConversationDraftOwnership.test.ets
 * Responsibility: Verify detached, mismatched, and valid ownership through the draft workflow interface.
 * Dependencies: @ohos/hypium; ConversationDraftWorkflow; common note-generation contracts.
 */
import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import {
  DifficultyLevel,
  KnowledgeUnit,
  NoteDraftReadyEvent,
  NoteGenerationResult,
  NoteGenerationRun,
  ReviewStatus,
} from 'common';
import {
  ConversationDraftWorkflow,
  IConversationDraftGateway,
  IConversationDraftWorkflowHost,
} from '../main/ets/workflows/conversation/ConversationDraftWorkflow';
import { ConversationRunRef } from '../main/ets/services/ConversationIdentity';
import { ChatMessageOrigin, ChatMessageOutcome } from '../main/ets/workflows/conversation/ConversationState';

class RecordingDraftHost implements IConversationDraftWorkflowHost {
  published: number = 0;

  draftContext(): common.UIAbilityContext { throw new Error('DRAFT_GATEWAY_MUST_BE_INJECTED'); }
  acceptsDraftRun(_ref: ConversationRunRef): boolean { return true; }
  publishDraft(_ref: ConversationRunRef, _event: NoteDraftReadyEvent): void { this.published += 1; }
  async addDraftMessage(
    _ref: ConversationRunRef,
    _content: string,
    _origin: ChatMessageOrigin,
    _outcome: ChatMessageOutcome,
  ): Promise<void> {}
  draftOrigin(_ref: ConversationRunRef): ChatMessageOrigin { return 'chat'; }
}

class FixedDraftGateway implements IConversationDraftGateway {
  private readonly event: NoteDraftReadyEvent;

  constructor(event: NoteDraftReadyEvent) { this.event = event; }

  async restore(_runId: string): Promise<NoteDraftReadyEvent> { return this.event; }
  async confirm(_event: NoteDraftReadyEvent, candidate: KnowledgeUnit): Promise<KnowledgeUnit> { return candidate; }
  async cancel(_runId: string): Promise<void> {}
  async retry(_runId: string): Promise<NoteDraftReadyEvent> { return this.event; }
  async listRecoverable(): Promise<NoteGenerationRun[]> { return []; }
  async regenerate(
    _runId: string,
    _noteId: string,
    _instruction: string,
    _sessionId: string,
    _parentRunId: string,
  ): Promise<NoteDraftReadyEvent> { return this.event; }
}

function draftEvent(owner: string | null): NoteDraftReadyEvent {
  const candidate: KnowledgeUnit = {
    id: 'note-ownership', title: 'Ownership', content: 'x = 1', summary: 'summary', tags: ['test'],
    subject: 'Mathematics', category: 'formula', chapter: 'Algebra', difficulty: DifficultyLevel.EASY,
    source: 'manual', createdAt: 1, updatedAt: 1, reviewStatus: ReviewStatus.NEW, nextReviewAt: 1,
    intervalDays: 1, easeFactor: 2.5, repetitions: 0, prerequisites: [], related: [], embedding: [],
    userId: 'test-user', version: 1,
  };
  const result: NoteGenerationResult = {
    runId: 'draft-ownership', route: 'light', status: 'ready-preview', candidate: candidate,
    issues: [], questions: [], promptTokens: 0, completionTokens: 0,
  };
  const event: NoteDraftReadyEvent = {
    runId: 'draft-ownership', checkpointId: 'checkpoint-ownership', candidateHash: 'hash-ownership',
    candidate: candidate, result: result, sourceCount: 0, softIssueCount: 0,
  };
  if (owner !== null) { event.originSessionId = owner; }
  return event;
}

async function restoreError(owner: string | null): Promise<string> {
  const host: RecordingDraftHost = new RecordingDraftHost();
  const gateway: FixedDraftGateway = new FixedDraftGateway(draftEvent(owner));
  const workflow: ConversationDraftWorkflow = ConversationDraftWorkflow.create(host, gateway);
  try {
    await workflow.restore({ sessionId: 'session-a', runId: 'conversation-a' }, 'draft-ownership');
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  }
  return '';
}

export default function conversationDraftOwnershipTest(): void {
  describe('ConversationDraftOwnership.issue173_behavior', () => {
    it('should reject a draft with empty ownership', 0, async () => {
      expect(await restoreError(null)).assertEqual('DETACHED_DRAFT_REQUIRES_RECOVERY_ENTRY');
    });

    it('should reject a draft owned by a different session', 0, async () => {
      expect(await restoreError('session-b')).assertEqual('DRAFT_SESSION_MISMATCH');
    });

    it('should publish a draft owned by the current session', 0, async () => {
      const host: RecordingDraftHost = new RecordingDraftHost();
      const gateway: FixedDraftGateway = new FixedDraftGateway(draftEvent('session-a'));
      const workflow: ConversationDraftWorkflow = ConversationDraftWorkflow.create(host, gateway);
      const restored: NoteDraftReadyEvent = await workflow.restore(
        { sessionId: 'session-a', runId: 'conversation-a' },
        'draft-ownership',
      );
      expect(restored.originSessionId).assertEqual('session-a');
      expect(host.published).assertEqual(1);
    });
  });
}
