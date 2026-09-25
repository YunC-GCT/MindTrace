import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

const reviewPage = read('entry/src/main/ets/pages/Review/ReviewPage.ets');
const host = read('entry/src/main/ets/pages/Review/KnowledgeGalaxy3DHost.ets');
const nativeAdapter = read('entry/src/main/ets/pages/Review/GalaxyComponent3DAdapter.ets');
const webAdapter = read('entry/src/main/ets/pages/Review/GalaxyWebAdapter.ets');
const webPreview = read('tools/galaxy3d-preview/src/main.ts');

test('Review knowledge galaxy is routed through the automatic 3D host', () => {
  assert.match(reviewPage, /import \{ KnowledgeGalaxy3DHost \} from "\.\/KnowledgeGalaxy3DHost"/);
  assert.match(reviewPage, /KnowledgeGalaxy3DHost\(\{ onGoAI: this\.onGoAI \}\)/);
  assert.doesNotMatch(reviewPage, /ReviewGraphView\(/);
});

test('host preserves refresh, detail, save, delete, and ordered fallback behavior', () => {
  assert.match(host, /@StorageProp\('notesVersion'\) @Watch\('onNotesVersionChange'\)/);
  assert.match(host, /this\.snapshot = projectGalaxyGraph\(this\.vm\.systems\)/);
  assert.match(host, /GalaxyComponent3DAdapter\(/);
  assert.match(host, /GalaxyWebAdapter\(/);
  assert.match(host, /ReviewGraphView\(\{ onGoAI: this\.onGoAI \}\)/);
  assert.match(host, /NoteDetailOverlay\(\{/);
  assert.match(host, /onDelete: this\.deleteNote/);
  assert.match(host, /onSaved: this\.handleSaved/);
  assert.match(host, /handleRendererFailure\('native_failure', reason\)/);
  assert.match(host, /handleRendererFailure\('web_failure', reason\)/);
  assert.match(host, /chooseInitialGalaxyRenderer\(this\.hasNativeCapability\(\)\)/);
});

test('empty snapshots stay inside the 3D galaxy renderer', () => {
  assert.doesNotMatch(host, /this\.snapshot\.nodes\.length === 0/);
  assert.doesNotMatch(host, /EmptyState\(/);
  assert.match(host, /if \(this\.rendererMode === 'native'\)/);
  assert.match(host, /else if \(this\.rendererMode === 'web'\)/);
});

test('both 3D adapters expose the shared lifecycle and interaction surface', () => {
  for (const adapter of [nativeAdapter, webAdapter]) {
    assert.match(adapter, /setSnapshot\(snapshot: GalaxyGraphSnapshot\): void/);
    assert.match(adapter, /setSelection\(id: string\): void/);
    assert.match(adapter, /resetCamera\(\): void/);
    assert.match(adapter, /pause\(\): void/);
    assert.match(adapter, /resume\(\): void/);
    assert.match(adapter, /release\(\): void/);
    assert.match(adapter, /aboutToDisappear\(\): void \{[\s\S]*?this\.release\(\)/);
  }
});

test('Web and native adapters report readiness, failure, and business selection', () => {
  assert.match(webAdapter, /\.onPageEnd\(\(\): void => \{[\s\S]*?this\.createMessageChannel\(\)[\s\S]*?this\.sendInitialGraph\(\)/);
  assert.match(webAdapter, /this\.callbacks\.onReady\(\)/);
  assert.match(webAdapter, /this\.callbacks\.onFailure\('web_renderer_ready_timeout'\)/);
  assert.match(webAdapter, /this\.callbacks\.onSelect\(id\)/);
  assert.match(webAdapter, /this\.callbacks\.onClearSelection\(\)/);
  assert.match(nativeAdapter, /Scene\.load\(\$rawfile\('galaxy3d\/native\/galaxy-scene\.glb'\)\)/);
  assert.match(nativeAdapter, /this\.callbacks\.onFailure\('native_scene_load_failed:/);
  assert.match(nativeAdapter, /this\.camera\.raycast\(/);
  assert.match(nativeAdapter, /this\.nodePathToId\.get\(hits\[0\]\.node\.path\)/);
});

test('Web preview keeps stars and knowledge nodes visible without CanvasTexture support', () => {
  assert.doesNotMatch(webPreview, /new THREE\.CanvasTexture/);
  assert.doesNotMatch(
    webPreview,
    /new THREE\.PointsMaterial\(\{[\s\S]*?map:/,
  );
  assert.match(webPreview, /const core = new THREE\.Mesh\(new THREE\.SphereGeometry/);
  assert.match(webPreview, /const glow = new THREE\.Mesh\(new THREE\.SphereGeometry/);
  assert.doesNotMatch(webPreview, /new THREE\.Sprite\(/);
  assert.match(webPreview, /createDomStarfield\(\)/);
  assert.match(webPreview, /orb\.className = 'node-orb'/);
  assert.match(webPreview, /view\.orb\.style\.transform = `translate\(-50%, -50%\) scale/);
  assert.match(webPreview, /if \(degraded\) \{[\s\S]*?degradedProjectionFrame[\s\S]*?\} else \{/);
  assert.match(webPreview, /renderer\.render\(scene, camera\)/);
});
