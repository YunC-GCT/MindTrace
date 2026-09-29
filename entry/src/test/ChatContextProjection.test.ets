/**
 * ChatContextProjection.test.ets - #165 idempotent snapshot-to-RDB projection tests.
 *
 * Path: entry/src/test/ChatContextProjection.test.ets
 * Responsibility: Verify stable keys, ordering metadata, partial filtering, and retry diagnostics.
 * Dependencies: @ohos/hypium; ChatContextProjectionService; ConversationSnapshotModels.
 */
import { describe, expect, it } from '@ohos/hypium';
import {
  ChatContextProjectionService,
  ChatProjectionResult,
} from '../main/ets/services/ChatContextProjectionService';
import { ChatMessageWriteRequest } from '../main/ets/models/AgentMemoryModels';
import { ChatProjectionWriter, ConversationSessionSnapshot } from '../main/ets/models/ConversationSnapshotModels';

class RecordingProjectionWriter implements ChatProjectionWriter {
  readonly rows: Map<string, string> = new Map<string, string>();
  readonly sequences: number[] = [];
  failKey: string = '';

  async saveMessage(request: ChatMessageWriteRequest): Promise<void> {
    if (request.messageKey === this.failKey) { throw new Error('SIMULATED_RDB_FAILURE'); }
    this.rows.set(request.sessionId + ':' + request.messageKey, request.content);
    this.sequences.push(request.sequence);
  }
}

const PROJECTION_SESSIONS: ConversationSessionSnapshot[] = [{
  id: 's1',
  name: 'A',
  messages: [{
    sessionId: 's1', role: 'user', content: 'question', origin: 'chat', runId: 'r101',
    sequence: 10, messageKey: 'r101:user', contextEligible: true,
  }, {
    sessionId: 's1', role: 'assistant', content: 'answer', origin: 'chat', runId: 'r101',
    sequence: 11, messageKey: 'r101:assistant:11', contextEligible: true,
  }, {
    sessionId: 's1', role: 'assistant', content: 'partial', origin: 'chat', runId: 'r102',
    sequence: 12, messageKey: 'r102:assistant:12', contextEligible: false,
  }],
}];

export default function chatContextProjectionTest(): void {
  describe('ChatContextProjection.issue165_idempotence', () => {
    it('should replay completed messages with stable keys and skip partials', 0, async () => {
      const writer: RecordingProjectionWriter = new RecordingProjectionWriter();
      const projection: ChatContextProjectionService = new ChatContextProjectionService(null, writer);
      const first: ChatProjectionResult = await projection.reconcile(PROJECTION_SESSIONS);
      const second: ChatProjectionResult = await projection.reconcile(PROJECTION_SESSIONS);
      expect(first.projected).assertEqual(2);
      expect(second.projected).assertEqual(2);
      expect(writer.rows.size).assertEqual(2);
      expect(writer.rows.has('s1:r102:assistant:12')).assertFalse();
      expect(writer.sequences[0]).assertEqual(10);
      expect(writer.sequences[1]).assertEqual(11);
    });

    it('should expose a content-safe retry diagnostic when one projection fails', 0, async () => {
      const writer: RecordingProjectionWriter = new RecordingProjectionWriter();
      writer.failKey = 'r101:assistant:11';
      const result: ChatProjectionResult = await new ChatContextProjectionService(null, writer)
        .reconcile(PROJECTION_SESSIONS);
      expect(result.projected).assertEqual(1);
      expect(result.failures).assertEqual(1);
      expect(result.diagnostic).assertEqual('code=CHAT_PROJECTION_RETRY_PENDING');
      expect(result.diagnostic.indexOf('answer') < 0).assertTrue();
    });
  });
}
