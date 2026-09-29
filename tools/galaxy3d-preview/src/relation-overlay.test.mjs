import assert from 'node:assert/strict';
import test from 'node:test';
import { incidentRelations, relationSegment } from './relation-overlay.ts';
import { projectViewportNode } from './viewport-projection.ts';

const edges = [
  { id: 'ab', fromId: 'a', toId: 'b', type: 'prerequisite' },
  { id: 'cb', fromId: 'c', toId: 'b', type: 'related' },
  { id: 'cd', fromId: 'c', toId: 'd', type: 'related' },
];

test('selection includes incoming and outgoing relationships while preserving direction and type', () => {
  assert.deepEqual(incidentRelations(edges, 'b'), edges.slice(0, 2));
  assert.deepEqual(incidentRelations(edges, 'c'), edges.slice(1));
  assert.deepEqual(incidentRelations(edges, null), []);
  assert.deepEqual(incidentRelations(edges, 'isolated'), []);
});

test('projected lines meet orb boundaries as camera positions and selection sizes change', () => {
  const source = { x: 10, y: 10, radius: 20, visible: true };
  const target = { x: 110, y: 10, radius: 10, visible: true };
  assert.deepEqual(relationSegment(source, target), [30, 10, 100, 10]);
  assert.deepEqual(relationSegment({ ...source, x: 50, y: 50 },
    { ...target, x: 50, y: 150 }), [50, 70, 50, 140]);
});

test('hidden, overlapping and invalid projected endpoints do not produce misleading lines', () => {
  const point = { x: 0, y: 0, radius: 12, visible: true };
  assert.equal(relationSegment(point, { ...point, x: 100, visible: false }), null);
  assert.equal(relationSegment(point, point), null);
  assert.equal(relationSegment(point, { ...point, x: 20 }), null);
  assert.equal(relationSegment(point, { ...point, x: NaN }), null);
});

test('zooming past the old label cutoff fades gradually and retains a faint node', () => {
  const project = (distance) => projectViewportNode(200, 300, distance, distance, 400, 600, 14);
  assert.ok(Math.abs(project(91.99).alpha - project(92.01).alpha) < 0.002);
  assert.ok(project(80).labelAlpha > project(100).labelAlpha);
  assert.equal(project(130).labelAlpha, 0);
  assert.ok(project(130).alpha > 0);
});

test('offscreen endpoints stay on their viewport bearing and retain a fading connection', () => {
  const center = projectViewportNode(200, 300, 40, 40, 400, 600, 14);
  const outside = projectViewportNode(800, 450, 40, 40, 400, 600, 14);
  assert.equal(outside.x, 384);
  assert.equal(outside.y, 346);
  assert.equal(outside.edgeGlow, 1);
  assert.equal(outside.labelAlpha, 0);
  assert.ok(outside.alpha > 0 && outside.alpha < center.alpha);
  assert.ok(relationSegment(center, outside));
});

test('camera crossing fades before clipping and never mirrors behind-camera nodes', () => {
  const near = projectViewportNode(200, 300, 0.2, 30, 400, 600, 14);
  const front = projectViewportNode(200, 300, 6.1, 30, 400, 600, 14);
  assert.ok(near.alpha < front.alpha * 0.01);
  assert.equal(projectViewportNode(200, 300, -1, 30, 400, 600, 14).visible, false);
  assert.equal(projectViewportNode(Infinity, 300, 1, 30, 400, 600, 14).visible, false);
});
