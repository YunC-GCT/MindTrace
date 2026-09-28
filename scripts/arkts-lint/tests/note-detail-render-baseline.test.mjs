/**
 * note-detail-render-baseline.test.mjs — #185 NoteDetail benchmark contract guard
 *
 * Verifies the durable fixture, surface metrics, lifecycle wiring, and device harness seams without
 * coupling the test to private timers or renderer implementation details.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const fixturesPath = 'entry/src/main/ets/services/NoteDetailRenderFixtures.ets';
const metricsPath = 'entry/src/main/ets/services/NoteDetailRenderMetrics.ets';
const harnessPath = 'entry/src/main/ets/benchmark/NoteDetailRenderBenchmarkHarness.ets';
const hostPath = 'entry/src/main/ets/benchmark/NoteDetailRenderBenchmarkHost.ets';

test('NoteDetail baseline owns deterministic A/B/C/C-prime fixture inputs', () => {
  assert.ok(existsSync(resolve(root, fixturesPath)), fixturesPath + ' must exist');
  const fixtures = read(fixturesPath);
  assert.match(fixtures, /export type NoteDetailFixtureId = 'A' \| 'B' \| 'C' \| 'C_P'/);
  assert.match(fixtures, /NOTE_DETAIL_FIXTURE_A/);
  assert.match(fixtures, /NOTE_DETAIL_FIXTURE_B/);
  assert.match(fixtures, /NOTE_DETAIL_FIXTURE_C/);
  assert.match(fixtures, /NOTE_DETAIL_FIXTURE_C_P/);
  assert.match(fixtures, /formulaCount:\s*0/);
  assert.match(fixtures, /formulaCount:\s*2/);
  assert.match(fixtures, /formulaCount:\s*6/);
  assert.match(fixtures, /'short' \| 'long'/);
  for (const rendererFamily of ['概念', '定理', '公式', '证明题', '计算题', '兜底']) {
    assert.match(fixtures, new RegExp("'" + rendererFamily + "'"));
  }
  assert.doesNotMatch(fixtures, /summary:\s*[^\n]*\$\$/);
  assert.match(fixtures, /createNoteDetailBenchmarkFixture/);
  assert.doesNotMatch(fixtures, /Math\.random|fetch\(|http\.|request\(/);
});

test('NoteDetail metrics expose a surface-isolated run snapshot', () => {
  assert.ok(existsSync(resolve(root, metricsPath)), metricsPath + ' must exist');
  const metrics = read(metricsPath);
  assert.match(metrics, /NOTE_DETAIL_METRIC_SURFACE:\s*string\s*=\s*'noteDetail'/);
  assert.match(metrics, /NOTE_DETAIL_LONG_FRAME_MS:\s*number\s*=\s*32/);
  assert.match(metrics, /NOTE_DETAIL_STABILITY_QUIET_MS:\s*number\s*=\s*500/);
  for (const field of [
    'openToFirstVisibleMs', 'formulaVisibleMs', 'openToStableMs', 'webCreateCount',
    'webCreatesPerFrame', 'maxWebCreatesPerFrame', 'webWorkStartCount',
    'heightUpdateCount', 'heightAppliedCount', 'longFrameCount',
    'consecutiveLongFramePairCount', 'renderExitCount', 'renderExitReasons',
    'heapUsedKb', 'totalHeapKb', 'headerMountCount', 'bodyMountCount',
    'bodyInputChangeCount', 'editStateCount', 'deleteConfirmCount', 'draftStateCount',
    'webKeepAliveEnabled',
  ]) {
    assert.match(metrics, new RegExp(field));
  }
  assert.match(metrics, /enableForRun/);
  assert.match(metrics, /recordFormulaVisible/);
  assert.match(metrics, /snapshot\(\)/);
  assert.doesNotMatch(metrics, /ChatMsg|StreamingReplyDocument|ChatHistory|ChatRenderBenchmarkStats/);
});

test('NoteDetail production surface emits lifecycle metrics without changing scheduler ownership', () => {
  const math = read('entry/src/main/ets/shared/atoms/MathTextRenderer.ets');
  const markdown = read('entry/src/main/ets/shared/molecules/MarkdownRenderer.ets');
  const meta = read('entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailMeta.ets');
  const body = read('entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailBody.ets');
  const overlay = read('entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailOverlay.ets');

  assert.match(math, /metricSurface/);
  assert.match(math, /NoteDetailRenderMetrics\.recordWebCreate/);
  assert.match(math, /NoteDetailRenderMetrics\.recordHeightUpdate/);
  assert.match(math, /NoteDetailRenderMetrics\.recordHeightApplied/);
  assert.match(math, /onVisibleAreaChange/);
  assert.match(math, /NoteDetailRenderMetrics\.recordFormulaVisible/);
  assert.match(math, /NoteDetailRenderMetrics\.recordRenderExit/);
  assert.match(markdown, /metricSurface:\s*this\.profile === 'note' \? 'noteDetail' : 'none'/);
  assert.match(meta, /NoteDetailRenderMetrics\.recordHeaderMount/);
  assert.match(body, /NoteDetailRenderMetrics\.recordBodyMount/);
  assert.match(body, /NoteDetailRenderMetrics\.recordBodyInputChange/);
  assert.match(overlay, /NoteDetailRenderMetrics\.recordEditState/);
  assert.match(overlay, /NoteDetailRenderMetrics\.recordDeleteConfirm/);
  assert.match(overlay, /NoteDetailRenderMetrics\.recordViewportHeight/);

  assert.doesNotMatch(body, /NoteDetailRenderSession/);
  assert.doesNotMatch(overlay, /maxWebCreatesPerFrame|maxWebWorkMsPerFrame/);
});

test('device harness drives the real NoteDetailOverlay seam and stays off production routing', () => {
  assert.ok(existsSync(resolve(root, harnessPath)), harnessPath + ' must exist');
  const harness = read(harnessPath);
  const pages = read('entry/src/main/resources/base/profile/main_pages.json');
  const entryAbility = read('entry/src/main/ets/entryability/EntryAbility.ets');
  const listTest = read('entry/src/test/List.test.ets');

  assert.match(harness, /NoteDetailOverlay\(/);
  assert.match(harness, /AgentFloatWindow\(\{/);
  assert.match(harness, /if \(this\.aiHelperVisible\)/);
  assert.match(harness, /benchmarkFixtureMode:\s*true/);
  assert.match(harness, /BENCHMARK_AI_HELPER_MESSAGES/);
  assert.ok(harness.indexOf('NoteDetailOverlay({') < harness.indexOf('AgentFloatWindow({'));
  assert.match(harness, /createNoteDetailBenchmarkFixture/);
  assert.match(harness, /NoteDetailRenderMetrics\.enableForRun/);
  assert.match(harness, /setInterval\([^]*NoteDetailRenderMetrics\.markStable/);
  assert.match(harness, /clearInterval\(/);
  assert.match(harness, /NoteDetailRenderMetrics\.recordFrameDuration/);
  assert.match(harness, /NoteDetailRenderMetrics\.recordMemory/);
  assert.doesNotMatch(harness, /import[^\n]*WebKeepAlive|WebKeepAlive\(\)/);
  assert.doesNotMatch(pages, /NoteDetailRenderBenchmarkHarness/);
  assert.doesNotMatch(entryAbility, /NoteDetailRenderBenchmarkHarness/);
  assert.match(listTest, /noteDetailRenderBaselineTest/);
});

test('WebKeepAlive experiment is default-off, root-scoped across cold and warm overlay runs', () => {
  const index = read('entry/src/main/ets/pages/Index.ets');
  const host = read(hostPath);
  const keepAlive = read('entry/src/main/ets/shared/atoms/WebKeepAlive.ets');
  const experiment = read('entry/src/main/ets/services/WebKeepAliveExperiment.ets');
  const entryAbility = read('entry/src/main/ets/entryability/EntryAbility.ets');
  assert.match(index, /@StorageLink\(WEB_KEEP_ALIVE_EXPERIMENT_KEY\)/);
  assert.match(index, /if \(this\.webKeepAliveExperimentEnabled\) \{\s*WebKeepAlive\(\)/s);
  assert.doesNotMatch(index, /webKeepAliveExperimentEnabled:\s*boolean\s*=\s*true/);
  assert.match(index, /NoteDetailRenderBenchmarkHost\(/);
  assert.match(host, /if \(this\.overlayVisible\) \{\s*NoteDetailRenderBenchmarkHarness\(/s);
  assert.match(host, /coldWarmTag:\s*this\.coldWarmTag/);
  assert.match(host, /this\.overlayVisible = false/);
  assert.match(host, /this\.coldWarmTag = 'warm'/);
  assert.match(host, /this\.overlayVisible = true/);
  assert.doesNotMatch(host, /import[^\n]*WebKeepAlive|WebKeepAlive\(\)/);
  assert.match(experiment, /configure\(enabled: boolean\)/);
  assert.match(experiment, /\?\? false/);
  assert.match(entryAbility, /WebKeepAliveExperiment\.configure\(/);
  assert.match(keepAlive, /KEEP_ALIVE_MAX_RECOVERY:\s*number\s*=\s*3/);
  assert.match(keepAlive, /claimRecovery\(\)/);
  assert.match(keepAlive, /this\.recoveryBudget\.claimRecovery\(\)/);
});
