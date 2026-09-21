import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const base = 'entry/src/main/ets/overlays/AgentFloatWindow/';
const panel = read(base + 'AgentInputPanel.ets');
const sheet = read(base + 'StudyModeActionSheet.ets');
const modeChip = read(base + 'ModeChip.ets');
const optionFiles = [
  ['LightModeChip.ets', '轻量模式'],
  ['StandardModeChip.ets', '标准模式'],
  ['DeepModeChip.ets', '深度模式'],
];

test('study mode selector is wired into the input panel', () => {
  assert.match(panel, /import \{ StudyModeActionSheet \}/);
  assert.match(panel, /StudyModeActionSheet\(\)/);
  assert.doesNotMatch(panel, /ModeChip\(\{ label: '学习模式' \}\)/);
});

test('study mode popup stacks the three dedicated option components vertically', () => {
  assert.match(sheet, /Column\(\{ space: S_2 \}\)/);
  assert.match(sheet, /LightModeChip\(/);
  assert.match(sheet, /StandardModeChip\(/);
  assert.match(sheet, /DeepModeChip\(/);
  assert.match(sheet, /@State selectedMode: string/);
  assert.match(sheet, /label: this\.selectedMode\.length > 0 \? this\.selectedMode : '学习模式'/);
  assert.match(sheet, /this\.selectedMode = LIGHT_MODE_LABEL/);
  assert.match(modeChip, /@Prop label: string/);
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
