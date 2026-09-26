import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const output = resolve(
  import.meta.dirname,
  '../../../entry/src/main/resources/rawfile/galaxy3d/native/galaxy-scene.glb',
);

const positions = new Float32Array([
  0, 1, 0,
  -0.866, -0.5, 0.5,
  0.866, -0.5, 0.5,
  0, -0.5, -1,
]);
const indices = new Uint16Array([
  0, 1, 2,
  0, 2, 3,
  0, 3, 1,
  1, 3, 2,
]);
const positionBytes = Buffer.from(positions.buffer);
const indexBytes = Buffer.from(indices.buffer);
const binaryLength = align4(positionBytes.length + indexBytes.length);
const binary = Buffer.alloc(binaryLength);
positionBytes.copy(binary, 0);
indexBytes.copy(binary, positionBytes.length);

const gltf = {
  asset: { version: '2.0', generator: 'MindTrace native galaxy scene generator' },
  extensionsUsed: ['KHR_lights_punctual'],
  extensions: {
    KHR_lights_punctual: {
      lights: [{ type: 'directional', color: [1, 0.94, 0.78], intensity: 2.2 }],
    },
  },
  scene: 0,
  scenes: [{ nodes: [0, 1, 2, 3, 4, 5] }],
  nodes: [
    { name: 'CenterStar', mesh: 0, scale: [2.4, 2.4, 2.4] },
    { name: 'NodeTemplate', mesh: 0, translation: [0, -1000, 0] },
    { name: 'GalaxyCamera', camera: 0, translation: [0, 0, 72] },
    { name: 'KeyLight', extensions: { KHR_lights_punctual: { light: 0 } }, rotation: [0.2, 0.2, 0, 0.96] },
    { name: 'PrerequisiteEdgeTemplate', mesh: 1, translation: [0, -1000, 0] },
    { name: 'RelatedEdgeTemplate', mesh: 2, translation: [0, -1000, 0] },
  ],
  cameras: [{ type: 'perspective', perspective: { yfov: 0.84, znear: 0.1, zfar: 650 } }],
  meshes: [
    { primitives: [{ attributes: { POSITION: 0 }, indices: 1, material: 0 }] },
    { primitives: [{ attributes: { POSITION: 0 }, indices: 1, material: 1 }] },
    { primitives: [{ attributes: { POSITION: 0 }, indices: 1, material: 2 }] },
  ],
  materials: [
    {
      name: 'GalaxyGlow',
      pbrMetallicRoughness: {
        baseColorFactor: [0.36, 0.89, 0.69, 1],
        metallicFactor: 0.18,
        roughnessFactor: 0.34,
      },
      emissiveFactor: [0.1, 0.46, 0.32],
    },
    {
      name: 'PrerequisiteEdge',
      pbrMetallicRoughness: { baseColorFactor: [0.96, 0.77, 0.43, 0.28] },
      emissiveFactor: [0.32, 0.18, 0.03],
      alphaMode: 'BLEND',
    },
    {
      name: 'RelatedEdge',
      pbrMetallicRoughness: { baseColorFactor: [0.62, 0.85, 1, 0.22] },
      emissiveFactor: [0.08, 0.26, 0.38],
      alphaMode: 'BLEND',
    },
  ],
  buffers: [{ byteLength: binary.length }],
  bufferViews: [
    { buffer: 0, byteOffset: 0, byteLength: positionBytes.length, target: 34962 },
    { buffer: 0, byteOffset: positionBytes.length, byteLength: indexBytes.length, target: 34963 },
  ],
  accessors: [
    {
      bufferView: 0,
      componentType: 5126,
      count: 4,
      type: 'VEC3',
      min: [-0.866, -0.5, -1],
      max: [0.866, 1, 0.5],
    },
    { bufferView: 1, componentType: 5123, count: 12, type: 'SCALAR' },
  ],
};

const json = Buffer.from(JSON.stringify(gltf));
const paddedJsonLength = align4(json.length);
const paddedJson = Buffer.alloc(paddedJsonLength, 0x20);
json.copy(paddedJson);
const totalLength = 12 + 8 + paddedJson.length + 8 + binary.length;
const glb = Buffer.alloc(totalLength);
glb.writeUInt32LE(0x46546c67, 0);
glb.writeUInt32LE(2, 4);
glb.writeUInt32LE(totalLength, 8);
glb.writeUInt32LE(paddedJson.length, 12);
glb.writeUInt32LE(0x4e4f534a, 16);
paddedJson.copy(glb, 20);
const binaryHeader = 20 + paddedJson.length;
glb.writeUInt32LE(binary.length, binaryHeader);
glb.writeUInt32LE(0x004e4942, binaryHeader + 4);
binary.copy(glb, binaryHeader + 8);

mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, glb);

function align4(value) {
  return (value + 3) & ~3;
}
