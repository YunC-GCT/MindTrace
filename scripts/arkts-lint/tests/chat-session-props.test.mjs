import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('conversation header and session list receive reactive parent state', () => {
  const parent = read('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets');
  const header = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatHeader.ets');
  const panel = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/SessionsPanel.ets');
  const chip = read('entry/src/main/ets/overlays/AgentFloatWindow/chat/SessionChip.ets');
  assert.match(parent, /@State activeSessionTitle: string/);
  assert.match(parent, /Text\(this\.activeSessionTitle\)/);
  assert.match(parent, /this\.activeSessionTitle = s\.name/);
  assert.doesNotMatch(header, /sessionTitle: string/);
  assert.match(panel, /@Prop\s+sessions: ChatSession\[\]/);
  assert.match(panel, /@Prop\s+activeSid: string/);
  assert.match(chip, /@Prop\s+name: string/);
  assert.match(chip, /@Prop\s+active: boolean/);
});
