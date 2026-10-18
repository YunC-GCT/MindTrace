// Generates native glTF geometry, not a Web renderer. Keep the asset reproducible.
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { SphereGeometry, CylinderGeometry, BufferGeometry, Float32BufferAttribute } from 'three';

const output = resolve(import.meta.dirname, '../../../entry/src/main/resources/rawfile/galaxy3d/native/galaxy-scene.glb');
const chunks = [];
let byteLength = 0;
const gltf = {
  asset: { version: '2.0', generator: 'MindTrace native galaxy scene generator' },
  extensionsUsed: ['KHR_lights_punctual'],
  extensions: { KHR_lights_punctual: { lights: [
    { type: 'directional', color: [1, 0.96, 0.88], intensity: 2.4 },
    { type: 'directional', color: [0.5, 0.7, 1], intensity: 0.65 },
  ] } },
  scene: 0,
  scenes: [{ name: 'GalaxyScene', nodes: [0, 1, 2, 3, 4, 5, 6] }],
  nodes: [
    { name: 'NodeTemplate', mesh: 0, translation: [0, -1000, 0] },
    { name: 'GalaxyCamera', camera: 0, translation: [0, 0, 72] },
    { name: 'KeyLight', extensions: { KHR_lights_punctual: { light: 0 } }, rotation: [-0.220, -0.310, -0.075, 0.9226] },
    { name: 'FillLight', extensions: { KHR_lights_punctual: { light: 1 } }, rotation: [0, 0.7071067811865476, 0, 0.7071067811865476] },
    { name: 'PrerequisiteEdgeTemplate', mesh: 1, translation: [0, -1000, 0] },
    { name: 'RelatedEdgeTemplate', mesh: 2, translation: [0, -1000, 0] },
    { name: 'Starfield', mesh: 3 },
  ],
  cameras: [{ type: 'perspective', perspective: { yfov: 0.84, znear: 0.1, zfar: 650 } }],
  meshes: [],
  materials: [
    { name: 'KnowledgeSphere', pbrMetallicRoughness: { baseColorFactor: [0.36, 0.89, 0.69, 1], metallicFactor: 0.08, roughnessFactor: 0.38 }, emissiveFactor: [0.025, 0.075, 0.055] },
    { name: 'PrerequisiteEdge', pbrMetallicRoughness: { baseColorFactor: [0.96, 0.77, 0.43, 1], metallicFactor: 0, roughnessFactor: 0.7 }, emissiveFactor: [0.25, 0.14, 0.03] },
    { name: 'RelatedEdge', pbrMetallicRoughness: { baseColorFactor: [0.62, 0.85, 1, 1], metallicFactor: 0, roughnessFactor: 0.7 }, emissiveFactor: [0.03, 0.12, 0.22] },
    { name: 'Starlight', pbrMetallicRoughness: { baseColorFactor: [0.55, 0.75, 0.9, 1], metallicFactor: 0, roughnessFactor: 1 }, emissiveFactor: [0.45, 0.6, 0.8] },
  ],
  buffers: [], bufferViews: [], accessors: [],
};
const lightRotation = gltf.nodes[2].rotation;
const lightNorm = Math.hypot(...lightRotation);
gltf.nodes[2].rotation = lightRotation.map(value => value / lightNorm);

addMesh(new SphereGeometry(2.1, 40, 28), 0);
const edge = new CylinderGeometry(1, 1, 1, 10, 1);
edge.rotateZ(-Math.PI / 2); // Local X spans [-0.5, 0.5]: scale.x = world length.
addMesh(edge, 1);
addMesh(edge, 2);

// One merged 3D background mesh rather than square points or hundreds of nodes.
const starPositions = [];
const starNormals = [];
const starIndices = [];
const star = new SphereGeometry(1, 8, 6);
for (let i = 0; i < 480; i++) {
  const x = (noise(i * 3 + 1) - 0.5) * 320;
  const y = (noise(i * 3 + 2) - 0.5) * 340;
  const z = -45 - noise(i * 3 + 3) * 130;
  const size = 0.06 + noise(i + 900) * 0.15;
  const offset = starPositions.length / 3;
  const position = star.getAttribute('position');
  const normal = star.getAttribute('normal');
  for (let vertex = 0; vertex < position.count; vertex++) {
    starPositions.push(x + position.getX(vertex) * size, y + position.getY(vertex) * size, z + position.getZ(vertex) * size);
    starNormals.push(normal.getX(vertex), normal.getY(vertex), normal.getZ(vertex));
  }
  for (const index of star.index.array) starIndices.push(index + offset);
}
const stars = new BufferGeometry();
stars.setAttribute('position', new Float32BufferAttribute(starPositions, 3));
stars.setAttribute('normal', new Float32BufferAttribute(starNormals, 3));
stars.setIndex(starIndices);
addMesh(stars, 3);

gltf.buffers.push({ byteLength });
const binary = Buffer.concat(chunks);
const json = Buffer.from(JSON.stringify(gltf));
const paddedJson = Buffer.alloc(align4(json.length), 0x20);
json.copy(paddedJson);
const glb = Buffer.alloc(12 + 8 + paddedJson.length + 8 + binary.length);
glb.writeUInt32LE(0x46546c67, 0);
glb.writeUInt32LE(2, 4);
glb.writeUInt32LE(glb.length, 8);
glb.writeUInt32LE(paddedJson.length, 12);
glb.writeUInt32LE(0x4e4f534a, 16);
paddedJson.copy(glb, 20);
const binaryHeader = 20 + paddedJson.length;
glb.writeUInt32LE(binary.length, binaryHeader);
glb.writeUInt32LE(0x004e4942, binaryHeader + 4);
binary.copy(glb, binaryHeader + 8);
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, glb);

function addMesh(geometry, material) {
  geometry.computeBoundingBox();
  const box = geometry.boundingBox;
  const position = addAccessor(geometry.getAttribute('position').array, 'VEC3', 34962, box.min.toArray(), box.max.toArray());
  const normal = addAccessor(geometry.getAttribute('normal').array, 'VEC3', 34962);
  const indices = addAccessor(geometry.index.array, 'SCALAR', 34963);
  gltf.meshes.push({ primitives: [{ attributes: { POSITION: position, NORMAL: normal }, indices, material }] });
}

function addAccessor(array, type, target, min, max) {
  const data = Buffer.from(array.buffer, array.byteOffset, array.byteLength);
  const padded = Buffer.alloc(align4(data.length));
  data.copy(padded);
  const view = gltf.bufferViews.length;
  gltf.bufferViews.push({ buffer: 0, byteOffset: byteLength, byteLength: data.length, target });
  chunks.push(padded);
  byteLength += padded.length;
  const accessor = { bufferView: view, componentType: array instanceof Float32Array ? 5126 : array instanceof Uint32Array ? 5125 : 5123, count: array.length / (type === 'VEC3' ? 3 : 1), type };
  if (min) accessor.min = min;
  if (max) accessor.max = max;
  gltf.accessors.push(accessor);
  return gltf.accessors.length - 1;
}

function align4(value) { return (value + 3) & ~3; }
function noise(index) { const value = Math.sin(index * 12.9898 + 78.233) * 43758.5453; return value - Math.floor(value); }
