// 路径: scripts/arkts-lint/tests/note-duplicate-actions.test.mjs
// 职责: 重复笔记的「更新 / 另存 / 保留」入口及事件链路守卫。
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('重复确认发出 merge 建议，并带目标笔记 id/标题', () => {
  const suggestion = read('common/src/main/ets/models/NoteSuggestionModels.ets');
  assert.match(suggestion, /sourceTitle\?: string/);

  const draft = read('agents/src/main/ets/conversation/ConversationDraftWorkflow.ets');
  assert.match(draft, /notifySuggestion\(ref: ConversationRunRef, suggestion: NoteSuggestion\): void/);
  assert.match(draft, /this\.host\.notifySuggestion\(ref, \{/);
  assert.match(draft, /action: 'merge'/);
  assert.match(draft, /reason: 'duplicate-on-confirm'/);
  assert.match(draft, /sourceNoteId: committed\.id/);
  assert.match(draft, /sourceTitle: committed\.title/);

  const workflow = read('agents/src/main/ets/conversation/ConversationWorkflow.ets');
  assert.match(workflow, /notifySuggestion\(ref: ConversationRunRef, suggestion: NoteSuggestion\): void/);
  assert.match(workflow, /this\.cbs\.onNoteSuggestion\(ref, suggestion\)/);
  assert.doesNotMatch(workflow, /const notify = this\.cbs\.onNoteSuggestion/);
  const noteHandler = read('agents/src/main/ets/conversation/ConversationNoteHandler.ets');
  assert.match(noteHandler, /const callbacks = this\.host\.nodeCallbacks\(\)/);
  assert.match(noteHandler, /callbacks\.onNoteSuggestion\(ref, suggestion\)/);
  assert.doesNotMatch(noteHandler, /const notifySuggestion = this\.host\.nodeCallbacks\(\)\.onNoteSuggestion/);
});

test('浮窗为重复笔记提供更新/另存/保留三个动作', () => {
  const window = read('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets');
  assert.match(window, /suggestion\.action === 'merge'/);
  assert.match(window, /scheduleDuplicateDialog/);
  assert.match(window, /更新已有笔记/);
  assert.match(window, /另存为新笔记/);
  assert.match(window, /保留现状/);
  assert.match(window, /getPromptAction\(\)\.showDialog/);
  assert.match(window, /this\.service\.requestRegeneration\(sessionId, noteId, instruction\)/);
  assert.match(window, /NoteEditService\.saveAsNew/);
});

test('更新请求贯通 service/runtime/coordinator/workflow', () => {
  const service = read('entry/src/main/ets/services/AgentChatService.ets');
  const runtime = read('entry/src/main/ets/services/ConversationRuntime.ets');
  const coordinator = read('entry/src/main/ets/services/ConversationDraftCoordinator.ets');
  assert.match(service, /async requestRegeneration\(sessionId: string, noteId: string, instruction: string\)/);
  assert.match(service, /this\.runtime\.requestRegeneration/);
  assert.match(runtime, /this\.draftCoordinator\.requestRegeneration/);
  assert.match(coordinator, /'regenerate'/);
  assert.match(coordinator, /this\.workflow\.requestRegeneration\(ref, noteId, \[noteId\], instruction\)/);
});

test('另存为新笔记跳过判重，但保留正常写入链路', () => {
  const edit = read('entry/src/main/ets/services/NoteEditService.ets');
  assert.match(edit, /static async saveAsNew/);
  assert.match(edit, /service\.create\(copy, 'save-as-new', true\)/);
  const writer = read('entry/src/main/ets/services/KnowledgeUnitWriteService.ets');
  assert.match(writer, /allowDuplicate: boolean = false/);
  assert.match(writer, /if \(!allowDuplicate\)/);
  assert.match(writer, /const duplicate: KnowledgeUnit \| null = await this\.findDuplicate\(unit\)/);
});

test('判重命中时 prepared 流程保留已有笔记 id', () => {
  const prepared = read('agents/src/main/ets/workflows/NotePreparedWorkflow.ets');
  assert.match(prepared, /const duplicateCommit: boolean = finalState\.commitResult\.duplicate === true;/);
  assert.match(prepared, /committedCandidate\.id = finalState\.commitResult\.noteId;/);
});
