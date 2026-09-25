import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const base = 'entry/src/main/ets/overlays/AgentFloatWindow/';
const panel = read(base + 'AgentInputPanel.ets');
const sheet = read(base + 'StudyModeActionSheet.ets');
const viewModel = read('entry/src/main/ets/viewmodels/AgentInputViewModel.ets');
const chatService = read('entry/src/main/ets/services/AgentChatService.ets');
const state = read('entry/src/main/ets/workflows/conversation/ConversationState.ets');
const workflow = read('entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets');
const aiService = read('entry/src/main/ets/services/AiService.ets');
const modeChip = read(base + 'ModeChip.ets');
const optionFiles = [
  ['LightModeChip.ets', '轻量模式'],
  ['StandardModeChip.ets', '标准模式'],
  ['DeepModeChip.ets', '深度模式'],
];

test('study mode selector is wired into the input panel', () => {
  assert.match(panel, /import \{ StudyModeActionSheet \}/);
  assert.match(panel, /StudyModeActionSheet\(\{/);
  assert.match(panel, /selectedRoute: this\.vm\.route/);
  assert.match(panel, /this\.vm\.setRoute\(route\)/);
  assert.doesNotMatch(panel, /ModeChip\(\{ label: '学习模式' \}\)/);
});

test('study mode popup stacks the three dedicated option components vertically', () => {
  assert.match(sheet, /Column\(\{ space: S_2 \}\)/);
  assert.match(sheet, /LightModeChip\(/);
  assert.match(sheet, /StandardModeChip\(/);
  assert.match(sheet, /DeepModeChip\(/);
  assert.match(sheet, /@Prop selectedRoute: NoteGenerationRoute = 'standard'/);
  assert.match(sheet, /selected: this\.selectedRoute === 'light'/);
  assert.match(sheet, /selected: this\.selectedRoute === 'standard'/);
  assert.match(sheet, /selected: this\.selectedRoute === 'deep'/);
  assert.match(sheet, /this\.selectRoute\('light'\)/);
  assert.match(sheet, /this\.selectRoute\('standard'\)/);
  assert.match(sheet, /this\.selectRoute\('deep'\)/);
  assert.match(modeChip, /@Prop label: string/);
});

test('study mode selection reaches note generation without changing ordinary reply ownership', () => {
  assert.match(viewModel, /route: NoteGenerationRoute = 'standard'/);
  assert.match(viewModel, /setRoute\(route: NoteGenerationRoute\)/);
  assert.match(viewModel, /captureReply\(sessionId, uri, msg, route\)/);
  assert.match(viewModel, /realReplyStream\(sessionId, msg, route\)/);
  assert.match(chatService, /route: NoteGenerationRoute = 'standard'/);
  assert.match(state, /route\?: NoteGenerationRoute/);
  assert.match(workflow, /input\.request\.kind === 'text' \? input\.request\.route : undefined/);
  assert.match(workflow, /generateNoteDraftWithSources\(/);
  assert.match(aiService, /route: NoteGenerationRoute = 'standard'/);
  assert.match(aiService, /route: route/);
});

test('study mode option components remain presentation-only', () => {
  optionFiles.forEach((entry) => {
    const source = read(base + entry[0]);
    assert.match(source, new RegExp(entry[1]));
    assert.match(source, /@Prop selected: boolean/);
    assert.match(source, /onTap\?: \(\) => void/);
    assert.doesNotMatch(source, /services|viewmodels|AgentInputViewModel|AgentChatService/);
  });
});
