import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

function read(path) {
  return readFileSync(new URL('../../../' + path, import.meta.url), 'utf8');
}

const history = read('entry/src/main/ets/services/ChatHistoryPersistence.ets');
const schema = read('common/src/main/ets/DatabaseHelper.ets');
const chatDao = read('entry/src/main/ets/database/ChatMessageDao.ets');
const generation = read('entry/src/main/ets/database/NoteGenerationRepository.ets');
const deletion = read('entry/src/main/ets/services/SessionDeletionCoordinator.ets');
const workflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');
const floatWindow = read('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets');
const mapper = read('entry/src/main/ets/services/ConversationSnapshotMapper.ets');
const titleService = read('entry/src/main/ets/services/ConversationTitleService.ets');

test('snapshot decoder validates an untrusted wire shape before constructing ChatSession', () => {
  assert.match(history, /interface ChatHistorySnapshotWire/);
  assert.match(history, /validateMessage\(\s*message: ChatHistoryMessageWire/);
  assert.doesNotMatch(history, /JSON\.parse\(raw\) as ChatHistorySnapshot(?:\[\])?\s*;/);
  assert.match(history, /DUPLICATE_MESSAGE_KEY/);
  assert.match(history, /MESSAGE_NOT_OBJECT/);
});

test('chat context schema and DAO use correlated atomic upsert and stable ordering', () => {
  assert.match(schema, /message_key TEXT NOT NULL/);
  assert.match(schema, /UNIQUE INDEX IF NOT EXISTS uq_chat_message_session_key/);
  assert.match(schema, /sequence INTEGER NOT NULL/);
  assert.match(chatDao, /ON_CONFLICT_REPLACE/);
  assert.match(chatDao, /orderByDesc\('sequence'\)/);
  assert.match(chatDao, /orderByAsc\('sequence'\)/);
  assert.match(workflow, /commitHistory\(ref\)[\s\S]*saveMessage\(/);
});

test('conversation note runs persist origin and deletion includes cancelled uncommitted runs', () => {
  assert.match(schema, /origin_session_id TEXT NOT NULL/);
  assert.match(schema, /parent_conversation_run_id TEXT NOT NULL/);
  assert.match(generation, /equalTo\('origin_session_id', sessionId\)/);
  assert.match(generation, /run\.status !== 'committed'/);
  assert.doesNotMatch(generation, /run\.status !== 'committed' && run\.status !== 'cancelled'/);
});

test('completed note-generation runs retain conversation ownership metadata', () => {
  const dispatcher = read('agents/src/main/ets/core/Dispatcher.ets');
  const start = dispatcher.indexOf('private completedRun(');
  assert.notEqual(start, -1);
  const completedRun = dispatcher.slice(start, start + 900);
  assert.match(completedRun, /originSessionId: run\.originSessionId,/);
  assert.match(completedRun, /parentConversationRunId: run\.parentConversationRunId,/);
});

test('confirming a legacy detached run keeps the already-validated in-memory owner', () => {
  assert.match(
    workflow,
    /const persistedEvent: NoteDraftReadyEvent = await service\.restoreDraft\(event\.runId\);[\s\S]*?if \(persistedEvent\.originSessionId !== undefined\) \{\s*this\.requireDraftOwnership\(ref, persistedEvent\);\s*\}/,
  );
});

test('conversation cancellation stays scoped to the parent run and recovery includes interrupted runs', () => {
  const service = read('entry/src/main/ets/services/AgentChatService.ets');
  const aiService = read('entry/src/main/ets/services/AiService.ets');
  assert.match(generation, /run\.status === 'running' \|\| run\.status === 'ready-preview'/);
  assert.match(generation, /equalTo\('parent_conversation_run_id', parentConversationRunId\)/);
  assert.doesNotMatch(generation, /cancelIncompleteByOriginSession/);
  assert.match(service, /cancelDraftsByRun\(sessionId, ref\.runId\)/);
  assert.doesNotMatch(service, /cancelDraftsBySession\(sessionId\)/);
  assert.doesNotMatch(aiService, /cancelDraftsByOriginSession/);
  assert.match(aiService, /cancelDraftsByParentRun\(sessionId: string, parentConversationRunId: string\)/);
});

test('session deletion tombstone covers every session-owned RDB domain but not KnowledgeUnit', () => {
  assert.match(deletion, /new relationalStore\.RdbPredicates\('chat_message'\)/);
  assert.match(deletion, /new relationalStore\.RdbPredicates\('agent_memory'\)/);
  assert.match(deletion, /new relationalStore\.RdbPredicates\('note_generation_source'\)/);
  assert.match(deletion, /new relationalStore\.RdbPredicates\('note_generation_checkpoint'\)/);
  assert.match(deletion, /new relationalStore\.RdbPredicates\('note_generation_log'\)/);
  assert.match(deletion, /new relationalStore\.RdbPredicates\('note_generation_run'\)/);
  assert.doesNotMatch(deletion, /RdbPredicates\('knowledge_unit'\)/);
  assert.doesNotMatch(deletion, /PROFILE_GLOBAL_SCOPE_ID/);
});

test('snapshot mapping is isolated from the overlay and reused by startup and deletion', () => {
  assert.match(mapper, /class ConversationSnapshotMapper/);
  assert.match(mapper, /static fromSessions\(sessions: ChatSession\[\]\)/);
  assert.match(mapper, /static retainExistingSessions\(/);
  assert.doesNotMatch(mapper, /@Component|AgentChatService|ChatHistoryPersistence/);
  assert.match(floatWindow, /ConversationSnapshotMapper\.fromSessions\(loadedSessions\)/);
  assert.match(floatWindow, /ConversationSnapshotMapper\.fromSessions\(remaining\)/);
});

test('image admission sends image provenance into both user and assistant messages', () => {
  assert.match(floatWindow, /addUserMsg: \(ref: ConversationRunRef, content: string, origin: ChatMessageOrigin\)/);
  assert.match(floatWindow, /origin: origin, outcome: 'completed'/);
  assert.match(floatWindow, /addAiMsgEmpty: \(ref: ConversationRunRef, origin: ChatMessageOrigin\)/);
  assert.match(floatWindow, /streaming: true, reasoning: '', origin: origin/);
});

test('the first conversation message derives a bounded title exactly once', () => {
  assert.match(titleService, /MAX_CONVERSATION_TITLE_LENGTH: number = 10/);
  assert.match(titleService, /fromFirstMessage\(content: string\)/);
  assert.match(floatWindow, /firstUserMessage: boolean/);
  assert.match(floatWindow, /ConversationTitleService\.fromFirstMessage\(content\)/);
  assert.match(floatWindow, /private updateSessionTitle\(sessionId: string, title: string\)/);
});
