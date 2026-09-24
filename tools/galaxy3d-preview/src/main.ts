import './styles.css';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { GalaxyBridge } from './bridge';
import { createGalaxyLayout } from './force-layout';
import type { GalaxyEdgeDTO, GalaxyNodeDTO, GalaxySnapshotDTO, HostMessage, LayoutPoint } from './types';

const MAX_DPR = 1;
const DEGRADED_DPR = 0.5;
const HIGH_PARTICLE_BUDGET = 8000;
const LOW_PARTICLE_BUDGET = 600;
const LOW_FPS_THRESHOLD = 30;
const TAP_SLOP_PX = 8;
const ENTRY_DURATION_MS = 800;
const LABEL_DISTANCE = 92;
const PERF_SAMPLE_MS = 2000;
const DOM_STAR_COUNT = 180;

interface NodeView {
  dto: GalaxyNodeDTO;
  group: THREE.Group;
  core: THREE.Mesh;
  glow: THREE.Mesh;
  pickMesh: THREE.Mesh;
  orb: HTMLDivElement;
  label: HTMLDivElement;
  position: THREE.Vector3;
}

interface RelationLayer {
  geometry: THREE.BufferGeometry;
  lines: THREE.LineSegments;
}

const app = requireElement<HTMLDivElement>('app');
const starLayer = requireElement<HTMLDivElement>('star-layer');
const nodeLayer = requireElement<HTMLDivElement>('node-layer');
const labelLayer = requireElement<HTMLDivElement>('label-layer');
const fpsPill = requireElement<HTMLSpanElement>('fps-pill');
const resetButton = requireElement<HTMLButtonElement>('reset-camera');
const bridge = new GalaxyBridge();
const clock = new THREE.Clock();
const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();
const defaultCameraPosition = new THREE.Vector3(0, -8, 78);
const entryCameraPosition = new THREE.Vector3(0, -8, 116);
const cameraTarget = new THREE.Vector3(0, 0, 0);

let renderer: THREE.WebGLRenderer | null = null;
let scene: THREE.Scene | null = null;
let camera: THREE.PerspectiveCamera | null = null;
let controls: OrbitControls | null = null;
let particleGeometry: THREE.BufferGeometry | null = null;
let particlePoints: THREE.Points | null = null;
let relationLayers: RelationLayer[] = [];
let graph: GalaxySnapshotDTO = { nodes: [], edges: [] };
let nodeViews = new Map<string, NodeView>();
let pickMeshes: THREE.Mesh[] = [];
let selectedId: string | null = null;
let activeParticleBudget = HIGH_PARTICLE_BUDGET;
let activeDprCap = MAX_DPR;
let pausedByHost = false;
let degraded = false;
let dustMotionEnabled = true;
let entryStartedAt = performance.now();
let entryAnimating = true;
let pointerDown: { x: number; y: number } | null = null;
let fpsFrameCount = 0;
let fpsWindowMs = 0;
let lowFpsMs = 0;
let lastPerfSampleMs = 0;
let degradedProjectionFrame = 0;

bridge.onMessage(handleHostMessage);
createDomStarfield();

if (!canUseWebGL()) {
  bridge.post('scene_failure', { reason: 'webgl_unavailable' });
} else {
  try {
    initScene();
    bridge.post('scene_ready', { particles: activeParticleBudget, degraded: false });
    animate();
  } catch (error) {
    bridge.post('scene_failure', { reason: errorMessage(error) });
  }
}

function initScene(): void {
  scene = new THREE.Scene();
  scene.fog = new THREE.FogExp2(0x0a0c10, 0.012);
  camera = new THREE.PerspectiveCamera(48, window.innerWidth / window.innerHeight, 0.1, 650);
  camera.position.copy(entryCameraPosition);
  camera.lookAt(cameraTarget);

  renderer = new THREE.WebGLRenderer({ antialias: false, alpha: false, powerPreference: 'high-performance' });
  renderer.setClearColor(0x0a0c10, 1);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, activeDprCap));
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  app.appendChild(renderer.domElement);

  controls = new OrbitControls(camera, renderer.domElement);
  controls.enabled = false;
  controls.enableDamping = true;
  controls.dampingFactor = 0.07;
  controls.rotateSpeed = 0.72;
  controls.panSpeed = 0.58;
  controls.zoomSpeed = 0.74;
  controls.minDistance = 35;
  controls.maxDistance = 140;
  controls.screenSpacePanning = true;
  controls.target.copy(cameraTarget);
  controls.touches.ONE = THREE.TOUCH.ROTATE;
  controls.touches.TWO = THREE.TOUCH.DOLLY_PAN;

  scene.add(new THREE.AmbientLight(0xf5f7ff, 0.72));
  const keyLight = new THREE.DirectionalLight(0xfff0c8, 1.18);
  keyLight.position.set(18, -25, 40);
  scene.add(keyLight);

  particleGeometry = createParticleGeometry(HIGH_PARTICLE_BUDGET);
  const particleMaterial = new THREE.PointsMaterial({
    size: 0.75,
    vertexColors: true,
    transparent: true,
    opacity: 0.9,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    sizeAttenuation: true,
    fog: false,
  });
  particlePoints = new THREE.Points(particleGeometry, particleMaterial);
  particlePoints.frustumCulled = false;
  scene.add(particlePoints);
  relationLayers = createRelationLayers(scene);

  window.addEventListener('resize', handleResize);
  document.addEventListener('visibilitychange', () => { pausedByHost = document.hidden; });
  resetButton.addEventListener('click', resetCamera);
  renderer.domElement.addEventListener('pointerdown', handlePointerDown);
  renderer.domElement.addEventListener('pointerup', handlePointerUp);
  renderer.domElement.addEventListener('webglcontextlost', handleContextLost);
}

function createRelationLayers(targetScene: THREE.Scene): RelationLayer[] {
  const colors = [0xf6c56d, 0x9dd8ff, 0xffdf95, 0xd9f4ff];
  const opacities = [0.2, 0.16, 0.95, 0.88];
  return colors.map((color, index) => {
    const geometry = new THREE.BufferGeometry();
    const lines = new THREE.LineSegments(geometry, new THREE.LineBasicMaterial({
      color,
      transparent: true,
      opacity: opacities[index],
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    }));
    targetScene.add(lines);
    return { geometry, lines };
  });
}

function initGraph(snapshot: GalaxySnapshotDTO): void {
  if (!scene) return;
  graph = sanitizeGraph(snapshot);
  if (selectedId && !graph.nodes.some((node) => node.id === selectedId)) selectedId = null;
  clearNodeViews();

  const layout = createGalaxyLayout(graph.nodes, graph.edges);
  const layoutById = new Map(layout.map((point) => [point.id, point]));
  const pickMaterial = new THREE.MeshBasicMaterial({ transparent: true, opacity: 0, depthWrite: false });

  for (const dto of graph.nodes) {
    const point = layoutById.get(dto.id) ?? { id: dto.id, x: 0, y: 0, z: 0 };
    const position = new THREE.Vector3(point.x, point.y, point.z);
    const group = new THREE.Group();
    group.position.copy(position);
    const color = safeColor(dto.color);
    const coreScale = nodeCoreScale(dto);
    const glow = new THREE.Mesh(new THREE.SphereGeometry(1, 12, 8), new THREE.MeshBasicMaterial({
      color, transparent: true, opacity: 0.18,
      blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.BackSide,
    }));
    glow.scale.setScalar(coreScale * 2.35);
    group.add(glow);
    const core = new THREE.Mesh(new THREE.SphereGeometry(1, 16, 12), new THREE.MeshBasicMaterial({
      color, transparent: false, depthWrite: true,
    }));
    core.scale.setScalar(coreScale);
    group.add(core);
    scene.add(group);

    const pickMesh = new THREE.Mesh(new THREE.SphereGeometry(3.8, 12, 8), pickMaterial);
    pickMesh.userData = { id: dto.id };
    pickMesh.position.copy(position);
    scene.add(pickMesh);
    pickMeshes.push(pickMesh);

    const label = document.createElement('div');
    label.className = 'node-label';
    label.textContent = dto.label;
    labelLayer.appendChild(label);
    const orb = document.createElement('div');
    orb.className = 'node-orb';
    orb.style.setProperty('--node-color', '#' + color.getHexString());
    nodeLayer.appendChild(orb);
    nodeViews.set(dto.id, { dto, group, core, glow, pickMesh, orb, label, position });
  }

  updateSelectionVisuals();
  resetCamera();
}

function animate(): void {
  requestAnimationFrame(animate);
  const delta = Math.min(clock.getDelta(), 0.05);
  if (pausedByHost || !renderer || !scene || !camera || !controls) return;
  updateEntryCamera();
  controls.update();
  if (degraded) {
    degradedProjectionFrame = (degradedProjectionFrame + 1) % 2;
    if (degradedProjectionFrame === 0) updateLabels();
  } else {
    updateNodeAnimation(delta);
    updateLabels();
    if (dustMotionEnabled && particlePoints) particlePoints.rotation.z += delta * 0.014;
    renderer.render(scene, camera);
  }
  updatePerformance(delta);
}

function updateEntryCamera(): void {
  if (!entryAnimating || !camera || !controls) return;
  const progress = Math.min(1, (performance.now() - entryStartedAt) / ENTRY_DURATION_MS);
  const eased = 1 - Math.pow(1 - progress, 3);
  camera.position.lerpVectors(entryCameraPosition, defaultCameraPosition, eased);
  camera.lookAt(cameraTarget);
  if (progress >= 1) {
    entryAnimating = false;
    controls.enabled = true;
  }
}

function updateNodeAnimation(delta: number): void {
  for (const view of nodeViews.values()) {
    const selected = view.dto.id === selectedId;
    const base = nodeCoreScale(view.dto);
    const nextScale = THREE.MathUtils.lerp(view.core.scale.x, selected ? base * 1.42 : base, delta * 10);
    view.core.scale.setScalar(nextScale);
    view.glow.scale.setScalar(nextScale * 2.35);
    const material = view.glow.material as THREE.MeshBasicMaterial;
    material.opacity = THREE.MathUtils.lerp(material.opacity, selected ? 0.42 : 0.18, delta * 10);
  }
}

function updateLabels(): void {
  if (!camera || !renderer) return;
  const width = renderer.domElement.clientWidth;
  const height = renderer.domElement.clientHeight;
  for (const view of nodeViews.values()) {
    const projected = view.position.clone().project(camera);
    const distance = camera.position.distanceTo(view.position);
    const visible = projected.z > -1 && projected.z < 1 && distance < LABEL_DISTANCE;
    const left = (projected.x * 0.5 + 0.5) * width;
    const top = (-projected.y * 0.5 + 0.5) * height;
    const perspectiveScale = THREE.MathUtils.clamp(74 / Math.max(1, distance), 0.72, 1.55);
    const selectedScale = view.dto.id === selectedId ? 1.42 : 1;
    view.orb.dataset.visible = String(visible || view.dto.id === selectedId);
    view.orb.style.left = `${left}px`;
    view.orb.style.top = `${top}px`;
    view.orb.style.transform = `translate(-50%, -50%) scale(${perspectiveScale * selectedScale})`;
    view.orb.style.zIndex = String(Math.round((1 - projected.z) * 100));
    view.label.dataset.visible = String(visible || view.dto.id === selectedId);
    view.label.style.left = `${left}px`;
    view.label.style.top = `${top}px`;
  }
}

function setSelection(id: string | null, notifyHost: boolean): void {
  if (id && !nodeViews.has(id)) return;
  selectedId = id;
  updateSelectionVisuals();
  if (!notifyHost) return;
  bridge.post(id ? 'node_selected' : 'selection_cleared', id ? { id } : {});
}

function updateSelectionVisuals(): void {
  updateRelationLines();
  for (const view of nodeViews.values()) {
    const material = view.core.material as THREE.MeshBasicMaterial;
    material.opacity = 1;
    view.orb.dataset.selected = String(selectedId === view.dto.id);
  }
}

function nodeCoreScale(node: GalaxyNodeDTO): number {
  return 1.35 + node.mastery * 0.55;
}

function updateRelationLines(): void {
  const positions: number[][] = [[], [], [], []];
  for (const edge of graph.edges) {
    const source = nodeViews.get(edge.fromId);
    const target = nodeViews.get(edge.toId);
    if (!source || !target) continue;
    const baseIndex = edge.type === 'prerequisite' ? 0 : 1;
    pushSegment(positions[baseIndex], source.position, target.position);
    if (selectedId === edge.fromId || selectedId === edge.toId) {
      pushSegment(positions[baseIndex + 2], source.position, target.position);
    }
  }
  relationLayers.forEach((layer, index) => {
    layer.geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions[index], 3));
    layer.geometry.computeBoundingSphere();
  });
}

function pushSegment(target: number[], source: THREE.Vector3, destination: THREE.Vector3): void {
  target.push(source.x, source.y, source.z, destination.x, destination.y, destination.z);
}

function handlePointerDown(event: PointerEvent): void {
  pointerDown = { x: event.clientX, y: event.clientY };
}

function handlePointerUp(event: PointerEvent): void {
  if (!pointerDown || !renderer || !camera) return;
  const dx = event.clientX - pointerDown.x;
  const dy = event.clientY - pointerDown.y;
  pointerDown = null;
  if (Math.hypot(dx, dy) > TAP_SLOP_PX) return;
  pointer.x = event.clientX / renderer.domElement.clientWidth * 2 - 1;
  pointer.y = -(event.clientY / renderer.domElement.clientHeight) * 2 + 1;
  raycaster.setFromCamera(pointer, camera);
  const hits = raycaster.intersectObjects(pickMeshes, false);
  if (hits.length === 0) {
    setSelection(null, true);
    return;
  }
  const id = hits[0].object.userData.id;
  if (typeof id === 'string') setSelection(id, true);
}

function handleResize(): void {
  if (!camera || !renderer) return;
  camera.aspect = window.innerWidth / Math.max(1, window.innerHeight);
  camera.updateProjectionMatrix();
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, activeDprCap));
  renderer.setSize(window.innerWidth, window.innerHeight);
}

function resetCamera(): void {
  if (!camera || !controls) return;
  entryAnimating = true;
  entryStartedAt = performance.now();
  controls.enabled = false;
  camera.position.copy(entryCameraPosition);
  controls.target.copy(cameraTarget);
  controls.update();
}

function handleContextLost(event: Event): void {
  event.preventDefault();
  pausedByHost = true;
  bridge.post('scene_failure', { reason: 'webgl_context_lost' });
}

function handleHostMessage(message: HostMessage): void {
  if (message.type === 'init_graph' && message.payload.snapshot) {
    initGraph(message.payload.snapshot);
    setSelection(message.payload.selectedId ?? null, false);
  } else if (message.type === 'set_selection') {
    setSelection(message.payload.selectedId ?? null, false);
  } else if (message.type === 'set_paused') {
    pausedByHost = message.payload.paused === true;
    if (!pausedByHost) clock.start();
  } else if (message.type === 'reset_camera') {
    resetCamera();
  }
}

function sanitizeGraph(snapshot: GalaxySnapshotDTO): GalaxySnapshotDTO {
  const ids = new Set<string>();
  const nodes = snapshot.nodes.filter((node) => {
    const valid = node.id.trim().length > 0 && !ids.has(node.id);
    if (valid) ids.add(node.id);
    return valid;
  });
  const edgeIds = new Set<string>();
  const edges = snapshot.edges.filter((edge) => {
    const valid = ids.has(edge.fromId) && ids.has(edge.toId)
      && edge.fromId !== edge.toId && !edgeIds.has(edge.id)
      && (edge.type === 'prerequisite' || edge.type === 'related');
    if (valid) edgeIds.add(edge.id);
    return valid;
  });
  return { nodes, edges };
}

function clearNodeViews(): void {
  if (!scene) return;
  for (const view of nodeViews.values()) {
    scene.remove(view.group);
    scene.remove(view.pickMesh);
    view.orb.remove();
    view.label.remove();
  }
  nodeViews = new Map<string, NodeView>();
  pickMeshes = [];
}

function createParticleGeometry(count: number): THREE.BufferGeometry {
  const positions = new Float32Array(count * 3);
  const colors = new Float32Array(count * 3);
  const palette = [new THREE.Color(0x5be3b0), new THREE.Color(0xf6c56d), new THREE.Color(0x9dd8ff)];
  for (let index = 0; index < count; index += 1) {
    const radius = 50 + seededNoise(index * 1.7) * 170;
    const theta = seededNoise(index + 8.2) * Math.PI * 2;
    const phi = Math.acos(seededNoise(index + 12.3) * 2 - 1);
    const offset = index * 3;
    positions[offset] = Math.sin(phi) * Math.cos(theta) * radius;
    positions[offset + 1] = Math.sin(phi) * Math.sin(theta) * radius;
    positions[offset + 2] = Math.cos(phi) * radius;
    const color = palette[index % palette.length];
    colors[offset] = color.r; colors[offset + 1] = color.g; colors[offset + 2] = color.b;
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  geometry.setDrawRange(0, activeParticleBudget);
  return geometry;
}

function createDomStarfield(): void {
  for (let index = 0; index < DOM_STAR_COUNT; index += 1) {
    const star = document.createElement('i');
    const size = 1 + seededNoise(index + 41.7) * 2.2;
    const palette = ['#d9f4ff', '#5be3b0', '#f6c56d'];
    star.className = 'galaxy-star';
    star.style.left = `${seededNoise(index * 2.3 + 3.1) * 100}%`;
    star.style.top = `${seededNoise(index * 4.7 + 9.4) * 100}%`;
    star.style.width = `${size}px`;
    star.style.height = `${size}px`;
    star.style.color = palette[index % palette.length];
    star.style.backgroundColor = palette[index % palette.length];
    star.style.opacity = `${0.24 + seededNoise(index + 17.2) * 0.58}`;
    starLayer.appendChild(star);
  }
}

function updatePerformance(delta: number): void {
  fpsFrameCount += 1;
  fpsWindowMs += delta * 1000;
  if (fpsWindowMs < 500) return;
  const fps = Math.round(fpsFrameCount * 1000 / fpsWindowMs);
  fpsPill.textContent = degraded ? `${fps} fps · 降级` : `${fps} fps`;
  lowFpsMs = fps < LOW_FPS_THRESHOLD ? lowFpsMs + fpsWindowMs : 0;
  if (!degraded && lowFpsMs >= 2000) degradeQuality();
  const now = performance.now();
  if (now - lastPerfSampleMs > PERF_SAMPLE_MS) {
    bridge.post('perf_sample', { fps, particles: activeParticleBudget, degraded });
    lastPerfSampleMs = now;
  }
  fpsFrameCount = 0;
  fpsWindowMs = 0;
}

function degradeQuality(): void {
  degraded = true;
  dustMotionEnabled = false;
  activeParticleBudget = LOW_PARTICLE_BUDGET;
  particleGeometry?.setDrawRange(0, activeParticleBudget);
  activeDprCap = DEGRADED_DPR;
  handleResize();
}

function safeColor(value: string): THREE.Color {
  try {
    return new THREE.Color(value.replace(/^#(?:FF)?/i, '#'));
  } catch {
    return new THREE.Color(0x5be3b0);
  }
}

function seededNoise(value: number): number {
  const raw = Math.sin(value * 12.9898 + 78.233) * 43758.5453;
  return raw - Math.floor(raw);
}

function canUseWebGL(): boolean {
  const canvas = document.createElement('canvas');
  return Boolean(canvas.getContext('webgl2') ?? canvas.getContext('webgl'));
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function requireElement<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) throw new Error(`Missing #${id}`);
  return element as T;
}
