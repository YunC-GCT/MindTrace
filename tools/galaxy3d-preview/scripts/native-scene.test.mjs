import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const bytes = readFileSync(new URL('../../../entry/src/main/resources/rawfile/galaxy3d/native/galaxy-scene.glb', import.meta.url));
const jsonLength = bytes.readUInt32LE(12);
const scene = JSON.parse(bytes.subarray(20, 20 + jsonLength).toString());
const binaryOffset = 20 + jsonLength + 8;
function values(index) {
  const accessor = scene.accessors[index];
  const view = scene.bufferViews[accessor.bufferView];
  const count = accessor.count * (accessor.type === 'VEC3' ? 3 : 1);
  const start = binaryOffset + view.byteOffset + (accessor.byteOffset ?? 0);
  return Array.from({ length: count }, (_, i) => accessor.componentType === 5126
    ? bytes.readFloatLE(start + i * 4) : bytes.readUInt16LE(start + i * 2));
}

test('native knowledge mesh is a smooth sphere with outward unit normals', () => {
  const template = scene.nodes.find(node => node.name === 'NodeTemplate');
  const primitive = scene.meshes[template.mesh].primitives[0];
  assert.ok(scene.accessors[primitive.attributes.POSITION].count >= 500, 'tetrahedron is not a sphere');
  assert.notEqual(primitive.attributes.NORMAL, undefined);
  const positions = values(primitive.attributes.POSITION);
  const normals = values(primitive.attributes.NORMAL);
  const radius = Math.hypot(...positions.slice(0, 3));
  for (let i = 0; i < positions.length; i += 3) {
    assert.ok(Math.abs(Math.hypot(...positions.slice(i, i + 3)) - radius) < 1e-5);
    assert.ok(Math.abs(Math.hypot(...normals.slice(i, i + 3)) - 1) < 1e-5);
    assert.ok(positions[i] * normals[i] + positions[i + 1] * normals[i + 1] + positions[i + 2] * normals[i + 2] > 0);
  }
});
