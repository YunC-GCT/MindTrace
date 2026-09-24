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
  assert.match(parent, /@State sessions: ChatSession\[\] = \[\]/);
  assert.match(parent, /@State activeSid: string = ''/);
  assert.match(parent, /@State activeSessionTitle: string = '新对话'/);
  assert.match(parent, /Text\(this\.activeSessionTitle\)/);
  assert.match(parent, /\.id\('chat-session-title-' \+ this\.activeSid\)/);
  assert.match(parent, /private activateSession\(session: ChatSession\)/);
  assert.match(parent, /private ensureActiveSession\(\): string/);
  assert.match(parent, /\(\): string => this\.ensureActiveSession\(\)/);
  assert.match(parent, /session\.id !== 's1' \|\| session\.messages\.length > 0/);
  assert.match(parent, /this\.activateSession\(s\)/);
  assert.match(parent, /this\.activateSession\(session\)/);
  assert.doesNotMatch(header, /sessionTitle: string/);
  assert.match(panel, /@Prop\s+sessions: ChatSession\[\]/);
  assert.match(panel, /@Prop\s+activeSid: string/);
  assert.match(chip, /@Prop\s+name: string/);
  assert.match(chip, /@Prop\s+active: boolean/);
});
