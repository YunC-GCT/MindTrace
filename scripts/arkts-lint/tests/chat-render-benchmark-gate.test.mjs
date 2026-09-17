// scripts/arkts-lint/tests/chat-render-benchmark-gate.test.mjs
//
// Issue #124 / spec/ticket-0-6-chat-render-fixtures-budgets:
//   Regression gate for the chat render benchmark seam: production boundary
//   (no StreamingReplyDocument / RendererScheduler / RenderTick), MathTextRenderer
//   render logic preservation, harness page lifecycle state, and the ADR-0017 +
//   spec 021 §6 budget freeze backfill.
//
//   The final numeric values are filled by the Verification phase from device
//   evidence; this test asserts the structural presence of the frozen budget
//   identifiers and the recomputable derivation rule text, not the numbers.

import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const mathTextRendererPath = 'entry/src/main/ets/shared/atoms/MathTextRenderer.ets';
const fixturesPath = 'entry/src/main/ets/services/ChatRenderFixtures.ets';
const statsPath = 'entry/src/main/ets/services/ChatRenderBenchmarkStats.ets';
const harnessPath = 'entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatRenderBenchmarkHarness.ets';
const mainPagesPath = 'entry/src/main/resources/base/profile/main_pages.json';
const entryAbilityPath = 'entry/src/main/ets/entryability/EntryAbility.ets';
const adrPath = 'docs/adr/0017-renderer-scheduler-budget-baseline.md';
const spec021Path = 'docs/specs/021-chat-streaming-incremental-rendering.md';

const mathTextRenderer = read(mathTextRendererPath);
const fixtures = read(fixturesPath);
const stats = read(statsPath);
const mainPages = read(mainPagesPath);
const entryAbility = read(entryAbilityPath);
const adr = read(adrPath);
const spec021 = read(spec021Path);

test('No StreamingReplyDocument / RendererScheduler / RenderTick is introduced by the benchmark seam', () => {
  const productionSurface = [
    mathTextRenderer,
    fixtures,
    stats,
    read('entry/src/main/ets/shared/molecules/FormulaSplitRenderer.ets'),
    read('entry/src/main/ets/shared/molecules/MarkdownRenderer.ets'),
    read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatBubble.ets'),
    read('entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets'),
    read('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets'),
  ].join('\n');
  assert.doesNotMatch(productionSurface, /StreamingReplyDocument/);
  assert.doesNotMatch(productionSurface, /RendererScheduler/);
  assert.doesNotMatch(productionSurface, /RenderTick/);
  // the temporary harness must not introduce them either
  if (existsSync(resolve(root, harnessPath))) {
    assert.doesNotMatch(read(harnessPath), /StreamingReplyDocument/);
    assert.doesNotMatch(read(harnessPath), /RendererScheduler/);
    assert.doesNotMatch(read(harnessPath), /RenderTick/);
  }
});

test('MathTextRenderer render logic is preserved with only the measurement seam added', () => {
  assert.match(mathTextRenderer, /export struct MathTextRenderer/);
  assert.match(mathTextRenderer, /private renderContent/);
  assert.match(mathTextRenderer, /private applyCachedRender/);
  assert.match(mathTextRenderer, /private setWebHeight/);
  assert.match(mathTextRenderer, /@State private webHeight/);
  assert.match(mathTextRenderer, /MATH_RENDER_CACHE/);
  assert.match(mathTextRenderer, /onPageEnd\(/);
  assert.match(mathTextRenderer, /runJavaScript/);
  // seam calls present (counters/timestamps only)
  assert.match(mathTextRenderer, /ChatRenderBenchmarkStats\.recordWebCreate\(\)/);
  assert.match(mathTextRenderer, /ChatRenderBenchmarkStats\.recordHeightUpdate\(\)/);
  assert.match(mathTextRenderer, /ChatRenderBenchmarkStats\.recordHeightApplied\(\)/);
  assert.match(mathTextRenderer, /ChatRenderBenchmarkStats\.recordCacheHit\(\)/);
  assert.match(mathTextRenderer, /ChatRenderBenchmarkStats\.recordCacheMiss\(\)/);
  assert.match(mathTextRenderer, /ChatRenderBenchmarkStats\.recordDegradation\(\)/);
});

test('Frozen fixtures and stats seam keep their deterministic contract', () => {
  assert.match(fixtures, /FIXTURE_TARGET_CODE_UNITS: number = 2000/);
  assert.match(fixtures, /export const FIXTURE_A/);
  assert.match(fixtures, /export const FIXTURE_B/);
  assert.match(fixtures, /export const FIXTURE_C/);
  assert.match(fixtures, /export const FIXTURE_C_P/);
  assert.match(fixtures, /deriveRendererBudgets/);
  assert.match(fixtures, /BUDGET_FRAME_MS: number = 32/);
  assert.match(stats, /recordWebCreate/);
  assert.match(stats, /recordHeightUpdate/);
  assert.match(stats, /recordHeightApplied/);
  assert.match(stats, /recordCacheHit/);
  assert.match(stats, /recordCacheMiss/);
  assert.match(stats, /recordDegradation/);
  assert.match(stats, /enableForRun/);
  assert.match(stats, /snapshot\(\)/);
});

test('Harness page and its temporary registration are consistent with each other', () => {
  const harnessExists = existsSync(resolve(root, harnessPath));
  const mainPagesRegistered = /ChatRenderBenchmarkHarness/.test(mainPages);
  const entryAbilityPointed = /ChatRenderBenchmarkHarness/.test(entryAbility);
  if (harnessExists) {
    // collection state: page registered and entry pointed at it
    assert.ok(mainPagesRegistered, 'main_pages.json must register the harness while it exists');
    assert.ok(entryAbilityPointed, 'EntryAbility must load the harness while it exists');
  } else {
    // post-cleanup state: byte-restored registrations
    assert.ok(!mainPagesRegistered, 'main_pages.json must not reference the deleted harness');
    assert.ok(!entryAbilityPointed, 'EntryAbility must not reference the deleted harness');
    assert.match(entryAbility, /windowStage\.loadContent\('pages\/Index'/);
  }
});

test('ADR-0017 and spec 021 §6 carry budget identifiers, derivation rule, and corrected-evidence state', () => {
  for (const doc of [adr, spec021]) {
    assert.match(doc, /maxWebCreatesPerFrame/);
    assert.match(doc, /maxWebWorkMsPerFrame/);
    assert.match(doc, /perCreateWorkMs/);
    assert.match(doc, /clamp\(floor\(32 \/ median\(perCreateWorkMs\)\), 1, 4\)/);
    assert.match(doc, /clamp\(round\(p75\(perCreateWorkMs\)\), 1, 16\)/);
    assert.match(doc, /superseded|corrected raw evidence|corrected evidence|gate verdict FAIL/);
  }
  assert.match(adr, /ADR-0017/);
  assert.match(adr, /MatePad Pro 13/);
  assert.match(adr, /spec\/ticket-0-6-chat-render-fixtures-budgets\/raw/);
  assert.match(adr, /raw rows/);
  assert.match(adr, /webWorkDurationSamplesMs/);
  assert.match(adr, /Cold\/warm/);
  assert.match(adr, /maxWebCreatesPerFrame = 1/);
  assert.match(adr, /maxWebWorkMsPerFrame = 16/);
  assert.match(spec021, /maxWebCreatesPerFrame=1/);
  assert.match(spec021, /maxWebWorkMsPerFrame=16/);
});

test('corrected raw JSONL evidence is committed and has 20 rows per fixture', () => {
  const fixtureIds = ['A', 'B', 'C', 'C_P'];
  for (const fixtureId of fixtureIds) {
    const rawPath = resolve(root, 'spec/ticket-0-6-chat-render-fixtures-budgets/raw', fixtureId + '.jsonl');
    const lines = readFileSync(rawPath, 'utf8').trim().split('\n').filter(Boolean);
    assert.equal(lines.length, 20, fixtureId + ' raw row count');
    const first = JSON.parse(lines[0]);
    const last = JSON.parse(lines[19]);
    assert.equal(first.fixtureId, fixtureId);
    assert.equal(first.runIndex, 0);
    assert.equal(first.coldWarmTag, 'cold');
    assert.equal(last.fixtureId, fixtureId);
    assert.equal(last.runIndex, 19);
    assert.equal(last.coldWarmTag, 'warm');
    assert.ok(Object.prototype.hasOwnProperty.call(first, 'webWorkDurationSamplesMs'));
    assert.ok(Object.prototype.hasOwnProperty.call(first, 'heapUsedAtFinishPlus30s'));
  }
});

test('ADR-0017 is indexed in docs/adr/index.md', () => {
  const index = read('docs/adr/index.md');
  assert.match(index, /\[0017\]\(\.\/0017-renderer-scheduler-budget-baseline\.md\)/);
});
