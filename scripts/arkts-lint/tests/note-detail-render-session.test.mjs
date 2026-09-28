/**
 * #186 instance-scoped NoteDetail render session contract guard.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const sessionPath = 'entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailRenderSession.ets';

test('NoteDetail owns one instance render session with identity and cancellation', () => {
  const session = read(sessionPath);
  const overlay = read('entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailOverlay.ets');
  const body = read('entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailBody.ets');
  assert.match(session, /export class DetailRenderSession/);
  assert.match(session, /activate\(sessionKey: string\)/);
  assert.match(session, /cancel\(\)/);
  assert.match(session, /generation/);
  assert.match(session, /NoteDetailMetricSurface/);
  assert.match(session, /return identity \+ '\\|' \+ unit\.id/);
  assert.match(overlay, /new DetailRenderSession\('noteDetail'\)/);
  assert.match(overlay, /this\.renderSession\.cancel\(\)/);
  assert.match(overlay, /buildDetailRenderSessionKey/);
  assert.match(overlay, /this\.renderSession\.activate/);
  assert.doesNotMatch(body, /buildDetailRenderSessionKey/);
  assert.doesNotMatch(body, /this\.renderSession\.activate/);
});

test('all NoteDetail section and renderer families consume the instance session', () => {
  const paths = [
    'entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailSection.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailStepsSection.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailMetaFooter.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/ConceptDetailView.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/TheoremDetailView.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/FormulaDetailView.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/ProofDetailView.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/ComputationDetailView.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/renderers/FallbackDetailView.ets',
  ];
  for (const path of paths) {
    const source = read(path);
    assert.match(source, /DetailRenderSession/, path + ' must receive the instance session');
    assert.match(source, /renderSession/, path + ' must use the instance session');
  }
});

test('legacy module-global queue API is fully contracted after migration', () => {
  const production = [
    read('entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailBody.ets'),
    read('entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailSection.ets'),
    read('entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailStepsSection.ets'),
    read('entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailMetaFooter.ets'),
    read(sessionPath),
  ].join('\n');
  assert.doesNotMatch(production, /detailRenderJobs|detailRenderQueueEpoch/);
  assert.doesNotMatch(production, /enqueueDetailRender|resetDetailRenderQueue/);
  assert.doesNotMatch(production, /from ['"].*DetailRenderQueue['"]/);
});

test('registered Hypium fixtures cover isolation stale work priority and completed tasks', () => {
  const fixture = read('entry/src/test/DetailRenderSession.test.ets');
  const list = read('entry/src/test/List.test.ets');
  assert.match(fixture, /cancelling_one_session_does_not_clear_another_instance/);
  assert.match(fixture, /note_revision_invalidates_stale_callbacks_before_UI_write/);
  assert.match(fixture, /runs_lower_priority_value_before_meta_work/);
  assert.match(fixture, /same_completed_task_is_released_without_scheduling_another_timer/);
  assert.match(fixture, /same_identity_local_interaction_keeps_generation_and_completed_work/);
  assert.match(list, /detailRenderSessionTest\(\)/);
});

test('content render guard exposes stable retry semantics covered by Hypium', () => {
  const session = read(sessionPath);
  const fixture = read('entry/src/test/DetailRenderSession.test.ets');
  const paths = [
    'entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailSection.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailStepsSection.ets',
    'entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailMetaFooter.ets',
  ];
  assert.match(session, /export class DetailContentRenderGuard/);
  assert.match(session, /shouldEnqueue\(key: string, contentReady: boolean\)/);
  assert.match(session, /settle\(\)/);
  assert.match(session, /interrupt\(\)/);
  for (const path of paths) {
    const source = read(path);
    assert.match(source, /DetailContentRenderGuard/,
      path + ' must use the shared content render guard');
  }
  assert.match(fixture, /pending_content_does_not_enqueue_twice/);
  assert.match(fixture, /interrupted_content_reenqueues_same_key/);
  assert.match(fixture, /completed_content_does_not_reenqueue_same_key/);
});
