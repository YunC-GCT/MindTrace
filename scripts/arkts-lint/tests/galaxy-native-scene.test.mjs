import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../../../entry/src/main/ets/pages/Review/GalaxyNativeScene.ets', import.meta.url), 'utf8');
const api = await import(`data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(source)).toString('base64')}`);
const node = (name, children = [], type = 1) => ({ name, nodeType: type, path: `import-root/${name}`, children: { count: () => children.length, get: i => children[i] ?? null } });

test('native raycast uses top-left-origin unit screen coordinates, not signed NDC', () => {
  assert.equal(typeof api.galaxyRaycastPosition, 'function');
  assert.deepEqual(api.galaxyRaycastPosition(100, 150, 400, 600), { x: 0.25, y: 0.25 });
  assert.deepEqual(api.galaxyRaycastPosition(200, 300, 400, 600), { x: 0.5, y: 0.5 });
});

test('template lookup finds GLB nodes under importer-created wrapper nodes', () => {
  const camera = node('GalaxyCamera', [], 3);
  const sphere = node('NodeTemplate', [], 2);
  const scene = { root: node('import-root', [node('scene-wrapper', [camera, sphere])]), getNodeByPath: () => null };
  assert.equal(api.findGalaxyTemplate(scene, 'GalaxyCamera'), camera);
  assert.equal(api.findGalaxyTemplate(scene, 'NodeTemplate'), sphere);
  assert.equal(api.findGalaxyTemplate(scene, 'missing'), null);
});

test('template lookup fails clearly on duplicate names and handles an empty scene', () => {
  assert.equal(api.findGalaxyTemplate({ root: null }, 'NodeTemplate'), null);
  const scene = { root: node('root', [node('NodeTemplate'), node('NodeTemplate')]) };
  assert.throws(() => api.findGalaxyTemplate(scene, 'NodeTemplate'), /ambiguous/);
});

test('horizontal and vertical orbit move nodes through depth without changing radius', () => {
  assert.equal(typeof api.rotateGalaxyPoint, 'function');
  const yaw = api.rotateGalaxyPoint({ x: 10, y: 0, z: 0 }, Math.PI / 2, 0);
  assert.ok(Math.abs(yaw.x) < 1e-8);
  assert.ok(Math.abs(yaw.z + 10) < 1e-8);
  const pitch = api.rotateGalaxyPoint({ x: 0, y: 10, z: 0 }, 0, Math.PI / 2);
  assert.ok(Math.abs(pitch.y) < 1e-8);
  assert.ok(Math.abs(pitch.z - 10) < 1e-8);
});

test('edge quaternion aligns the unit X cylinder with a depth-only edge', () => {
  assert.equal(typeof api.galaxyEdgeRotation, 'function');
  const q = api.galaxyEdgeRotation({ x: 0, y: 0, z: 10 });
  assert.ok(Math.abs(q.y + Math.SQRT1_2) < 1e-8);
  assert.ok(Math.abs(q.w - Math.SQRT1_2) < 1e-8);
  const opposite = api.galaxyEdgeRotation({ x: -10, y: 0, z: 0 });
  assert.deepEqual(opposite, { x: 0, y: 0, z: 1, w: 0 });
});

test('projection follows perspective depth and rejects points behind the camera', () => {
  assert.equal(typeof api.projectGalaxyPoint, 'function');
  const identity = { x: { x: 1, y: 0, z: 0, w: 0 }, y: { x: 0, y: 1, z: 0, w: 0 }, z: { x: 0, y: 0, z: 1, w: 0 }, w: { x: 0, y: 0, z: 0, w: 1 } };
  // Native projection contains the Vulkan render-target Y flip (verified on API 24).
  const perspective = { ...identity, y: { x: 0, y: -1, z: 0, w: 0 }, z: { x: 0, y: 0, z: -1, w: -1 }, w: { x: 0, y: 0, z: -0.2, w: 0 } };
  const p = api.projectGalaxyPoint({ x: 1, y: 1, z: -2 }, identity, perspective, 400, 400);
  assert.deepEqual(p, { x: 300, y: 100 });
  assert.equal(api.projectGalaxyPoint({ x: 1, y: 1, z: 2 }, identity, perspective, 400, 400), null);
});
