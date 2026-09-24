import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { resolve } from 'node:path';
import test from 'node:test';

const root = resolve(import.meta.dirname, '../../..');
const sourcePath = resolve(
  root,
  'entry/src/main/ets/pages/Review/GalaxyRendererSelection.ets',
);

async function loadSelection() {
  const source = readFileSync(sourcePath, 'utf8');
  const compiled = stripTypeScriptTypes(source, { mode: 'strip' });
  return import(`data:text/javascript;base64,${Buffer.from(compiled).toString('base64')}`);
}

test('renderer selection prefers native then falls back through web to 2D', async () => {
  const { chooseInitialGalaxyRenderer, nextGalaxyRendererMode } = await loadSelection();
  assert.equal(chooseInitialGalaxyRenderer(true), 'native');
  assert.equal(nextGalaxyRendererMode('native', 'native_failure'), 'web');
  assert.equal(nextGalaxyRendererMode('web', 'web_failure'), 'fallback');
});

test('renderer selection starts with web when native capability is absent', async () => {
  const { chooseInitialGalaxyRenderer, nextGalaxyRendererMode } = await loadSelection();
  assert.equal(chooseInitialGalaxyRenderer(false), 'web');
  assert.equal(nextGalaxyRendererMode('web', 'web_ready'), 'web');
  assert.equal(nextGalaxyRendererMode('native', 'native_ready'), 'native');
});

test('stale renderer events cannot replace the active renderer', async () => {
  const { nextGalaxyRendererMode } = await loadSelection();
  assert.equal(nextGalaxyRendererMode('web', 'native_failure'), 'web');
  assert.equal(nextGalaxyRendererMode('fallback', 'web_ready'), 'fallback');
});
