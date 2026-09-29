/**
 * ConversationIdentity.test.ets - Conversation identity policy behavior tests.
 *
 * Path: entry/src/test/ConversationIdentity.test.ets
 * Responsibility: Verify session, run, and message identity generation and validation.
 * Dependencies: @ohos/hypium; services/ConversationIdentity; services/WritePathValidator.
 *
 * Data flow:
 *   DeterministicIdentitySource -> identity policies -> validation assertions
 */

import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import {
  ChatMessageIdPolicy,
  ConversationIdentitySource,
  ConversationRunRef,
  ConversationRunIdPolicy,
  ProfileScopePolicy,
  SessionIdPolicy,
} from '../main/ets/services/ConversationIdentity';
import {
  DifficultyLevel,
  KnowledgeUnit,
  NoteDraftReadyEvent,
  NoteGenerationResult,
  ReviewStatus,
} from 'common';
import { ChatMessageRecord } from '../main/ets/models/AgentMemoryModels';
import { WritePathValidator } from '../main/ets/services/WritePathValidator';
import { ConversationRunCoordinator } from '../main/ets/services/ConversationRunCoordinator';
import { AgentChatCallbacks } from '../main/ets/services/AgentChatService';
import { ConversationWorkflowAdapter } from '../main/ets/services/ConversationWorkflowAdapter';
import { ConversationMessageEvent } from '../main/ets/workflows/conversation/ConversationTypes';
import {
  ConversationSessionReduceResult,
  ConversationSessionReducer,
} from '../main/ets/services/ConversationSessionReducer';
import {
  ChatMsg,
  ChatMessageOrigin,
  ChatMessageOutcome,
  ChatSession,
  ChatStatusMeta,
} from '../main/ets/overlays/AgentFloatWindow/chat/ChatModels';

class DeterministicIdentitySource implements ConversationIdentitySource {
  private readonly time: number;
  private readonly entropyValue: number;

  constructor(time: number, entropyValue: number) {
    this.time = time;
    this.entropyValue = entropyValue;
  }

  nowMs(): number {
    return this.time;
  }

  entropy(): number {
    return this.entropyValue;
  }
}

class RecordingAgentChatCallbacks implements AgentChatCallbacks {
  aiWrites: number = 0;
  completionWrites: number = 0;
  draftWrites: number = 0;
  progressWrites: number = 0;
  busy: boolean = false;

  addUserMsg(_ref: ConversationRunRef, _content: string, _origin: ChatMessageOrigin): number { return 1; }
  addAiMsg(_ref: ConversationRunRef, _content: string): number { this.aiWrites += 1; return this.aiWrites; }
  addAiMsgEmpty(_ref: ConversationRunRef, _origin: ChatMessageOrigin): number { this.aiWrites += 1; return 1; }
  updateAiMsg(_ref: ConversationRunRef, _id: number, _event: ConversationMessageEvent): void {
    this.aiWrites += 1;
  }
  updateRunEvent(_ref: ConversationRunRef, _event: ConversationMessageEvent): void { this.aiWrites += 1; }
  finishAiMsg(_ref: ConversationRunRef, _id: number): void { this.completionWrites += 1; }
  terminateAiRun(_ref: ConversationRunRef, _outcome: ChatMessageOutcome): void { this.completionWrites += 1; }
  getUserMessageId(_ref: ConversationRunRef): number { return 1; }
  async commitHistory(_ref: ConversationRunRef): Promise<boolean> { return true; }
  reportDiagnostic(_ref: ConversationRunRef, _diagnostic: string): void {}
  async cancelDraftsBySession(_sessionId: string): Promise<void> {}
  setBusy(_ref: ConversationRunRef, value: boolean): void { this.busy = value; }
  setStatusMeta(_ref: ConversationRunRef, _meta: ChatStatusMeta | null): void {
    this.progressWrites += 1;
  }
  getContext(): common.UIAbilityContext { throw new Error('NOT_USED_BY_LIFECYCLE_TEST'); }
  getConversationText(_ref: ConversationRunRef, _excludeLatestUser: boolean): string { return ''; }
  onDraftReady(_ref: ConversationRunRef, _event: NoteDraftReadyEvent): void { this.draftWrites += 1; }
}

function makeDraftEvent(): NoteDraftReadyEvent {
  const candidate: KnowledgeUnit = {
    id: 'note-1',
    title: 'Test note',
    content: 'x = 1',
    summary: 'summary',
    tags: ['test'],
    subject: 'Mathematics',
    category: 'formula',
    chapter: 'Algebra',
    difficulty: DifficultyLevel.EASY,
    source: 'manual',
    createdAt: 1,
    updatedAt: 1,
    reviewStatus: ReviewStatus.NEW,
    nextReviewAt: 1,
    intervalDays: 1,
    easeFactor: 2.5,
    repetitions: 0,
    prerequisites: [],
    related: [],
    embedding: [],
    userId: 'test-user',
    version: 1,
  };
  const result: NoteGenerationResult = {
    runId: 'draft-run-1',
    route: 'light',
    status: 'ready-preview',
    candidate: candidate,
    issues: [],
    questions: [],
    promptTokens: 0,
    completionTokens: 0,
  };
  return {
    runId: 'draft-run-1',
    checkpointId: 'checkpoint-1',
    candidateHash: 'candidate-1',
    candidate: candidate,
    result: result,
    sourceCount: 0,
    softIssueCount: 0,
  };
}

export default function conversationIdentityTest(): void {
  describe('ConversationIdentity.issue149_policy_contract', () => {
    it('should accept legacy s1 and reject invalid session identifiers without normalization', 0, () => {
      expect(SessionIdPolicy.isValid('s1')).assertTrue();
      const invalid: string[] = [
        '',
        'a',
        'a'.repeat(65),
        'Session1',
        '会话1',
        's\u0000',
        's\n',
        's/1',
        's\\1',
        ' s1',
        's1 ',
        "s1' or '1'='1",
        's1?next=http',
      ];
      for (const value of invalid) {
        expect(SessionIdPolicy.isValid(value)).assertFalse();
      }
      expect(SessionIdPolicy.isValid('__global__')).assertFalse();
      expect(ProfileScopePolicy.isValid('__global__')).assertTrue();
      expect(ProfileScopePolicy.isValid('s1')).assertTrue();
    });

    it('should generate 10000 deterministic unique session and run identifiers', 0, () => {
      const source: DeterministicIdentitySource = new DeterministicIdentitySource(1727000000000, 37);
      const sessionPolicy: SessionIdPolicy = new SessionIdPolicy(source);
      const runPolicy: ConversationRunIdPolicy = new ConversationRunIdPolicy(source);
      const sessions: Set<string> = new Set<string>();
      const runs: Set<string> = new Set<string>();
      let index: number = 0;
      while (index < 10000) {
        const sessionId: string = sessionPolicy.create();
        const runId: string = runPolicy.create();
        expect(SessionIdPolicy.isValid(sessionId)).assertTrue();
        expect(ConversationRunIdPolicy.isValid(runId)).assertTrue();
        sessions.add(sessionId);
        runs.add(runId);
        index += 1;
      }
      expect(sessions.size).assertEqual(10000);
      expect(runs.size).assertEqual(10000);
    });

    it('should generate 10000 deterministic unique positive safe message identifiers', 0, () => {
      const source: DeterministicIdentitySource = new DeterministicIdentitySource(1727000000000, 0);
      const policy: ChatMessageIdPolicy = new ChatMessageIdPolicy(source);
      const ids: Set<number> = new Set<number>();
      let index: number = 0;
      while (index < 10000) {
        const id: number = policy.create();
        expect(ChatMessageIdPolicy.isValid(id)).assertTrue();
        ids.add(id);
        index += 1;
      }
      expect(ids.size).assertEqual(10000);
    });

    it('should validate session identity without rejecting legal message content', 0, () => {
      const record: ChatMessageRecord = {
        id: 'message-record-1',
        messageKey: 'message-record-1',
        sessionId: 's1',
        role: 'user',
        content: 'f(x) = x^2\n\t推导过程',
        sequence: 1,
        origin: 'chat',
        outcome: 'completed',
        createdAt: 1,
      };
      WritePathValidator.validateChatMessage(record);
      expect(record.content).assertContain('\n');
      expect(record.content).assertContain('\t');
    });

    it('should admit one run, reject stale events, and make terminal finish idempotent', 0, () => {
      const coordinator: ConversationRunCoordinator = new ConversationRunCoordinator();
      const first = coordinator.start('s1', { kind: 'text' });
      expect(first.accepted).assertTrue();
      expect(first.ref === undefined).assertFalse();
      if (first.ref === undefined) {
        expect(first.accepted).assertFalse();
        return;
      }
      const ref = first.ref;
      const busy = coordinator.start('s1', { kind: 'image' });
      expect(busy.accepted).assertFalse();
      expect(coordinator.isCurrent(ref)).assertTrue();
      expect(coordinator.finish({ sessionId: 's1', runId: 'r-stale' }, 'failed')).assertFalse();
      expect(coordinator.finish(ref, 'completed')).assertTrue();
      expect(coordinator.finish(ref, 'completed')).assertFalse();
      expect(coordinator.isCurrent(ref)).assertFalse();
      const second = coordinator.start('s1', { kind: 'text' });
      expect(second.accepted).assertTrue();
      if (second.ref !== undefined) {
        const current: ConversationRunRef | undefined = coordinator.currentRef('s1');
        expect(current === second.ref).assertFalse();
        expect(coordinator.isCurrent(ref)).assertFalse();
        expect(coordinator.isCurrent(second.ref)).assertTrue();
        expect(coordinator.finish(ref, 'failed')).assertFalse();
        expect(coordinator.isCurrent(second.ref)).assertTrue();
        expect(coordinator.finish(second.ref, 'cancelled')).assertTrue();
      }
    });

    it('should route a current run to one session and reject stale or duplicate message events', 0, () => {
      const sessions: ChatSession[] = [
        { id: 's1', name: 'A', messages: [] },
        { id: 's2', name: 'B', messages: [] },
      ];
      const ref: ConversationRunRef = { sessionId: 's1', runId: 'r12' };
      const message: ChatMsg = { id: 1, role: 'user', content: 'x', ts: 1, streaming: false };
      const accepted: ConversationSessionReduceResult = ConversationSessionReducer.updateMessages(
        sessions,
        ref,
        true,
        'add-user-message',
        (messages: ChatMsg[]): ChatMsg[] => [...messages, message],
      );
      expect(accepted.accepted).assertTrue();
      expect(accepted.sessions[0].messages.length).assertEqual(1);
      expect(accepted.sessions[1].messages.length).assertEqual(0);
      const stale: ConversationSessionReduceResult = ConversationSessionReducer.updateMessages(
        accepted.sessions,
        ref,
        false,
        'update-ai-message',
        (messages: ChatMsg[]): ChatMsg[] => messages,
      );
      expect(stale.accepted).assertFalse();
      expect(stale.diagnostic).assertContain('STALE_RUN_EVENT');
      const duplicate: ConversationSessionReduceResult = ConversationSessionReducer.updateMessages(
        accepted.sessions,
        ref,
        true,
        'add-ai-message',
        (messages: ChatMsg[]): ChatMsg[] => [...messages, message],
      );
      expect(duplicate.accepted).assertFalse();
      expect(duplicate.diagnostic).assertContain('DUPLICATE_CHAT_MESSAGE_ID');

      const missing: ConversationSessionReduceResult = ConversationSessionReducer.updateMessages(
        accepted.sessions,
        { sessionId: 's3', runId: 'r13' },
        true,
        'add-ai-message',
        (messages: ChatMsg[]): ChatMsg[] => messages,
      );
      expect(missing.accepted).assertFalse();
      expect(missing.diagnostic).assertContain('SESSION_NOT_FOUND');
    });

    it('should normalize streamed content through one message event sink without duplication', 0, () => {
      const placeholder: ChatMsg = {
        id: 7,
        role: 'ai',
        content: '',
        ts: 1,
        streaming: true,
        reasoning: 'reasoning',
        origin: 'chat',
        runId: 'r-stream',
      };
      const streamEvent: ConversationMessageEvent = {
        kind: 'stream',
        event: { type: 'text', delta: '\\item additive' },
      };
      const streamed: ChatMsg = ConversationSessionReducer.applyMessageEvent(placeholder, streamEvent);
      const normalizedEvent: ConversationMessageEvent = {
        kind: 'replace-content',
        content: '- additive',
      };
      const normalized: ChatMsg = ConversationSessionReducer.applyMessageEvent(streamed, normalizedEvent);
      expect(normalized.content).assertEqual('- additive');
      expect(normalized.reasoning).assertEqual('reasoning');
      expect(normalized.streaming).assertTrue();
    });

    it('should isolate run2 from every late run1 adapter event', 0, () => {
      const coordinator: ConversationRunCoordinator = new ConversationRunCoordinator();
      const callbacks: RecordingAgentChatCallbacks = new RecordingAgentChatCallbacks();
      const adapter: ConversationWorkflowAdapter = new ConversationWorkflowAdapter(callbacks, coordinator);
      const first = coordinator.start('s1', { kind: 'text' });
      if (first.ref === undefined) {
        expect(first.accepted).assertTrue();
        return;
      }
      adapter.onStart(first.ref);
      adapter.updateAiMsg(first.ref, 1, { kind: 'stream', event: { type: 'text', delta: 'first' } });
      adapter.onDraftReady(first.ref, makeDraftEvent());
      adapter.onFinish(first.ref);
      expect(coordinator.finish(first.ref, 'cancelled')).assertTrue();

      const second = coordinator.start('s1', { kind: 'text' });
      if (second.ref === undefined) {
        expect(second.accepted).assertTrue();
        return;
      }
      adapter.onStart(second.ref);
      const aiWrites: number = callbacks.aiWrites;
      const completionWrites: number = callbacks.completionWrites;
      const draftWrites: number = callbacks.draftWrites;
      const progressWrites: number = callbacks.progressWrites;

      adapter.updateAiMsg(first.ref, 1, { kind: 'stream', event: { type: 'text', delta: 'late-delta' } });
      adapter.addAiMsg(first.ref, 'late-error');
      adapter.onDraftReady(first.ref, makeDraftEvent());
      adapter.onProgress(first.ref, 'reply_model_call');
      adapter.finishAiMsg(first.ref, 1);
      adapter.onFinish(first.ref);
      adapter.onFinish(first.ref);

      expect(callbacks.aiWrites).assertEqual(aiWrites);
      expect(callbacks.completionWrites).assertEqual(completionWrites);
      expect(callbacks.draftWrites).assertEqual(draftWrites);
      expect(callbacks.progressWrites).assertEqual(progressWrites);
      expect(callbacks.busy).assertTrue();
      expect(coordinator.finish(first.ref, 'failed')).assertFalse();
      expect(coordinator.isCurrent(second.ref)).assertTrue();

      adapter.updateAiMsg(second.ref, 2, { kind: 'stream', event: { type: 'text', delta: 'current' } });
      expect(callbacks.aiWrites).assertEqual(aiWrites + 1);
      adapter.onFinish(second.ref);
      expect(coordinator.finish(second.ref, 'completed')).assertTrue();
      adapter.updateAiMsg(second.ref, 2, { kind: 'stream', event: { type: 'text', delta: 'terminal' } });
      adapter.finishAiMsg(second.ref, 2);
      expect(callbacks.aiWrites).assertEqual(aiWrites + 1);
      expect(callbacks.completionWrites).assertEqual(completionWrites);
    });
  });
}
