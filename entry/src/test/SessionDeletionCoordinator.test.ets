/**
 * SessionDeletionCoordinator.test.ets - #146 cross-store deletion protocol tests.
 *
 * Path: entry/src/test/SessionDeletionCoordinator.test.ets
 * Responsibility: Verify commit ordering, pending cleanup, and idempotent startup replay.
 * Dependencies: @ohos/hypium; SessionDeletionCoordinator.
 */
import { describe, expect, it } from '@ohos/hypium';
import {
  SessionDeletionCoordinator,
  SessionDeletionOperations,
  SessionDeletionResult,
} from '../main/ets/services/SessionDeletionCoordinator';
import { ChatHistorySaveResult } from '../main/ets/services/ChatHistoryPersistence';
import { ConversationSessionSnapshot } from '../main/ets/models/ConversationSnapshotModels';

class RecordingDeletionOperations implements SessionDeletionOperations {
  tombstones: string[] = [];
  cleanups: string[] = [];
  failCleanup: boolean = false;

  async readTombstones(): Promise<string[]> { return this.tombstones.slice(); }
  async writeTombstones(sessionIds: string[]): Promise<void> { this.tombstones = sessionIds.slice(); }
  async cleanupRdb(sessionId: string): Promise<void> {
    if (this.failCleanup) { throw new Error('SIMULATED_RDB_FAILURE'); }
    this.cleanups.push(sessionId);
  }
}

function saveResult(success: boolean): ChatHistorySaveResult {
  return {
    success: success,
    state: success ? 'completed' : 'failed',
    stage: success ? 'VERIFY' : 'COMMIT',
    transport: 'taskpool',
    retryable: !success,
    diagnostic: success ? 'code=SAVED' : 'code=SAVE_FAILED',
  };
}

const SESSION_A: ConversationSessionSnapshot = { id: 's1', name: 'A', messages: [] };
const SESSION_B: ConversationSessionSnapshot = { id: 's2', name: 'B', messages: [] };

export default function sessionDeletionCoordinatorTest(): void {
  describe('SessionDeletionCoordinator.issue146_protocol', () => {
    it('should commit the visible snapshot before cleanup and remove its tombstone on success', 0, async () => {
      const events: string[] = [];
      const operations: RecordingDeletionOperations = new RecordingDeletionOperations();
      const coordinator: SessionDeletionCoordinator = new SessionDeletionCoordinator(
        null,
        '',
        async (sessions: ConversationSessionSnapshot[]): Promise<ChatHistorySaveResult> => {
          events.push('commit:' + sessions.length.toString());
          return saveResult(true);
        },
        async (sessionId: string): Promise<void> => { events.push('quiesce:' + sessionId); },
        operations,
      );
      const result: SessionDeletionResult = await coordinator.deleteSession('s1', [SESSION_B]);
      expect(result.state).assertEqual('completed');
      expect(events[0]).assertEqual('quiesce:s1');
      expect(events[1]).assertEqual('commit:1');
      expect(operations.cleanups[0]).assertEqual('s1');
      expect(operations.tombstones.length).assertEqual(0);
    });

    it('should not clean RDB when the file commit fails', 0, async () => {
      const operations: RecordingDeletionOperations = new RecordingDeletionOperations();
      const coordinator: SessionDeletionCoordinator = new SessionDeletionCoordinator(
        null, '',
        async (_sessions: ConversationSessionSnapshot[]): Promise<ChatHistorySaveResult> => saveResult(false),
        async (_sessionId: string): Promise<void> => {},
        operations,
      );
      const result: SessionDeletionResult = await coordinator.deleteSession('s1', [SESSION_B]);
      expect(result.state).assertEqual('failed-before-commit');
      expect(operations.cleanups.length).assertEqual(0);
      expect(operations.tombstones.length).assertEqual(0);
    });

    it('should persist cleanup-pending and converge on startup replay', 0, async () => {
      const operations: RecordingDeletionOperations = new RecordingDeletionOperations();
      operations.failCleanup = true;
      const coordinator: SessionDeletionCoordinator = new SessionDeletionCoordinator(
        null, '',
        async (_sessions: ConversationSessionSnapshot[]): Promise<ChatHistorySaveResult> => saveResult(true),
        async (_sessionId: string): Promise<void> => {},
        operations,
      );
      const result: SessionDeletionResult = await coordinator.deleteSession('s1', [SESSION_B]);
      expect(result.state).assertEqual('cleanup-pending');
      expect(operations.tombstones[0]).assertEqual('s1');
      operations.failCleanup = false;
      const pending: string[] = await coordinator.replay([SESSION_B]);
      expect(pending.length).assertEqual(0);
      expect(operations.cleanups[0]).assertEqual('s1');
      expect(operations.tombstones.length).assertEqual(0);
    });

    it('should retain a tombstone when the snapshot commit did not remove the session', 0, async () => {
      const operations: RecordingDeletionOperations = new RecordingDeletionOperations();
      operations.tombstones = ['s1'];
      const coordinator: SessionDeletionCoordinator = new SessionDeletionCoordinator(
        null, '',
        async (_sessions: ConversationSessionSnapshot[]): Promise<ChatHistorySaveResult> => saveResult(true),
        async (_sessionId: string): Promise<void> => {},
        operations,
      );
      const pending: string[] = await coordinator.replay([SESSION_A, SESSION_B]);
      expect(pending.length).assertEqual(1);
      expect(operations.cleanups.length).assertEqual(0);
      expect(operations.tombstones[0]).assertEqual('s1');
    });
  });
}
