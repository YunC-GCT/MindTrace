import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('manual and AI KnowledgeUnit writes share one entry-side service', () => {
  const service = read('entry/src/main/ets/services/KnowledgeUnitWriteService.ets');
  const factory = read('entry/src/main/ets/services/KnowledgeUnitWriteServiceFactory.ets');
  const manual = read('entry/src/main/ets/services/NoteEditService.ets');
  const adapter = read('entry/src/main/ets/adapters/NoteDaoAdapter.ets');
  const ai = read('entry/src/main/ets/services/AiService.ets');

  assert.match(service, /export class KnowledgeUnitWriteService/);
  assert.match(factory, /new KnowledgeUnitWriteService\(new NoteDao\(store\), effects\)/);
  assert.match(manual, /KnowledgeUnitWriteService/);
  assert.match(adapter, /KnowledgeUnitWriteService/);
  assert.match(ai, /KnowledgeUnitWriteServiceFactory\.create\(this\.context\)/);
  assert.doesNotMatch(manual, /new NoteDao|dao\.insert|dao\.update/);
  assert.doesNotMatch(adapter, /WritePathValidator|insertUnit/);
  assert.doesNotMatch(ai, /from ['"]\.\.\/database\/NoteDao['"]|new NoteDao\(|noteDao\.insert/);
  assert.match(adapter, /post-commit warning/);
});

test('NoteDao owns transactional KnowledgeUnit and immutable revision persistence', () => {
  const dao = read('entry/src/main/ets/database/NoteDao.ets');

  assert.match(dao, /createTransaction\(\)/);
  assert.match(dao, /transaction\.insert\('knowledge_unit'/);
  assert.match(dao, /transaction\.insert\('note_revision'/);
  assert.match(dao, /predicates\.equalTo\('id', unit\.id\)/);
  assert.match(dao, /predicates\.equalTo\('version', expectedVersion\)/);
  assert.match(dao, /if \(rows === 0\)/);
  assert.match(dao, /VERSION_CONFLICT/);
  assert.match(dao, /await transaction\.commit\(\)/);
  assert.match(dao, /await transaction\.rollback\(\)/);
  assert.match(dao, /queryRevision\(/);
});

test('schema migration is additive and idempotently backfills revisions', () => {
  const schema = read('common/src/main/ets/DatabaseHelper.ets');

  assert.match(schema, /CREATE TABLE IF NOT EXISTS note_revision/);
  assert.match(schema, /PRIMARY KEY \(note_id, version\)/);
  assert.match(schema, /INSERT OR IGNORE INTO note_revision/);
});

test('write result distinguishes committed data from post-commit warnings', () => {
  const service = read('entry/src/main/ets/services/KnowledgeUnitWriteService.ets');

  assert.match(service, /committed: true/);
  assert.match(service, /warnings: string\[\]/);
  assert.match(service, /VERSION_CONFLICT/);
  assert.match(service, /runPostCommit/);
});

test('callers do not duplicate centralized notesVersion and cache side effects', () => {
  const editor = read('entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailOverlay.ets');
  const conversation = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');
  const conversationTypes = read('entry/src/main/ets/workflows/conversation/ConversationTypes.ets');
  const chatService = read('entry/src/main/ets/services/AgentChatService.ets');
  const effects = read('entry/src/main/ets/services/KnowledgeUnitPostCommitEffects.ets');

  assert.doesNotMatch(editor, /AppStorage\.setOrCreate\('notesVersion'/);
  assert.doesNotMatch(editor, /UiDataCacheService\.invalidateNote/);
  assert.doesNotMatch(conversation, /this\.cbs\.bumpNotesVersion\(\)/);
  assert.doesNotMatch(conversationTypes, /bumpNotesVersion/);
  assert.doesNotMatch(chatService, /bumpNotesVersion/);
  assert.match(effects, /UiDataCacheService\.invalidateNote\(unit\.id\)/);
  assert.match(effects, /AppStorage\.setOrCreate\('notesVersion', version \+ 1\)/);
  assert.match(effects, /CardSnapshotService\.refresh\(this\.context\)/);
});
