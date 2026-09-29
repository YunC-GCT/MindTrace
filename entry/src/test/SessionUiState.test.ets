/**
 * SessionUiState.test.ets - #164 session-owned composer and attachment state.
 *
 * Path: entry/src/test/SessionUiState.test.ets
 * Responsibility: Verify composer, attachment, draft, progress, error, and retry isolation.
 * Dependencies: @ohos/hypium; AgentInputViewModel session state store; common note contracts.
 *
 * Data flow:
 *   session-scoped writes -> SessionUiStateStore -> isolated reads and deletion cleanup.
 *
 * ArkTS 1.1 strict adaptation:
 *   - Tests use explicit domain types and assert deleted sessions reject late writes.
 */
import { describe, expect, it } from '@ohos/hypium';
import { SessionUiState, SessionUiStateStore } from '../main/ets/viewmodels/AgentInputViewModel';
import {
  DifficultyLevel,
  KnowledgeUnit,
  NoteDraftReadyEvent,
  NoteGenerationResult,
  ReviewStatus,
} from 'common';

function draftEvent(sessionId: string): NoteDraftReadyEvent {
  const candidate: KnowledgeUnit = {
    id: 'note-1', title: 'Draft', content: 'content', summary: 'summary', tags: [],
    subject: 'Math', category: 'concept', chapter: 'Algebra', difficulty: DifficultyLevel.EASY,
    source: 'note_generation', createdAt: 1, updatedAt: 1, reviewStatus: ReviewStatus.NEW,
    nextReviewAt: 2, intervalDays: 1, easeFactor: 2.5, repetitions: 0,
    prerequisites: [], related: [], embedding: [], userId: '', version: 1,
  };
  const result: NoteGenerationResult = {
    runId: 'draft-1', route: 'light', status: 'ready-preview', candidate: candidate,
    bestCheckpointId: 'checkpoint-1', issues: [], questions: [], promptTokens: 0, completionTokens: 0,
  };
  return {
    runId: 'draft-1', originSessionId: sessionId, parentConversationRunId: 'r101',
    checkpointId: 'checkpoint-1', candidateHash: 'hash-1', candidate: candidate,
    result: result, sourceCount: 1, softIssueCount: 0, sourceIds: ['source-1'],
  };
}

export default function sessionUiStateTest(): void {
  describe('SessionUiState.issue164_isolation', () => {
    it('should keep composer and attachment state in the originating session', 0, () => {
      const store: SessionUiStateStore = new SessionUiStateStore();
      store.register('s1');
      store.register('s2');
      const a: SessionUiState = { composerText: 'A draft', imageUri: 'file://a' };
      expect(store.write('s1', a)).assertTrue();
      expect(store.read('s2').composerText).assertEqual('');
      expect(store.read('s2').imageUri).assertEqual('');
      expect(store.read('s1').composerText).assertEqual('A draft');
      expect(store.read('s1').imageUri).assertEqual('file://a');
    });

    it('should route late picker results to the captured session and reject deleted sessions', 0, () => {
      const store: SessionUiStateStore = new SessionUiStateStore();
      store.register('s1');
      store.register('s2');
      expect(store.setImage('s1', 'file://late-a')).assertTrue();
      expect(store.read('s2').imageUri).assertEqual('');
      store.remove('s1');
      expect(store.setImage('s1', 'file://orphan')).assertFalse();
      expect(store.read('s2').imageUri).assertEqual('');
    });

    it('should isolate draft, progress, error, and retry state and remove all state on deletion', 0, () => {
      const store: SessionUiStateStore = new SessionUiStateStore();
      store.register('s1');
      store.register('s2');
      expect(store.setDraft('s1', draftEvent('s1'))).assertTrue();
      expect(store.setProgress('s1', 'generating')).assertTrue();
      expect(store.setError('s1', 'code=PROJECTION_PENDING')).assertTrue();
      expect(store.setRetryTarget('s1', 'r101')).assertTrue();
      expect(store.read('s2').draft === undefined).assertTrue();
      expect(store.read('s2').progress === undefined).assertTrue();
      store.remove('s1');
      expect(store.has('s1')).assertFalse();
      expect(store.setDraft('s1', draftEvent('s1'))).assertFalse();
    });
  });
}
