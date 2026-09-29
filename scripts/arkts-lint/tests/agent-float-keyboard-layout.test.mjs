import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { resolve } from 'node:path';
import test from 'node:test';

const source = readFileSync(resolve(import.meta.dirname,
  '../../../entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindowLayout.ets'), 'utf8');
const compiled = stripTypeScriptTypes(source, { mode: 'strip' });
const { agentSheetBottomInset } = await import(
  `data:text/javascript;base64,${Buffer.from(compiled).toString('base64')}`);

test('floating input meets the keyboard instead of leaving the old 74 vp tab gap', () => {
  // Device reproduction: screen 2856 px, keyboard 1099 px, density 3.5.
  const screenBottom = 2856;
  const keyboardHeight = 1099;
  const density = 3.5;
  const panelBottom = screenBottom - agentSheetBottomInset(keyboardHeight / density) * density;
  assert.equal(panelBottom, screenBottom - keyboardHeight);
});

test('keyboard height changes and dismissals do not accumulate offsets', () => {
  assert.deepEqual([0, 314, 400, 240, 0, 314].map(agentSheetBottomInset),
    [74, 314, 400, 240, 74, 314]);
});
