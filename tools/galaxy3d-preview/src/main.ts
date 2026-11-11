import './styles.css';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { GalaxyBridge } from './bridge';
import { BackgroundStarfield } from './background-starfield';
import { createStarMaterial, createGlowMaterial, createKnowledgeMaterial } from './particle-material';
import { GalaxyRelationOverlay, incidentRelations } from './relation-overlay';
import type { ProjectedNode } from './relation-overlay';
import { projectViewportNode } from './viewport-projection';
import { createGalaxyLayout } from './force-layout';
import type { GalaxyEdgeDTO, GalaxyNodeDTO, GalaxySnapshotDTO, HostMessage, LayoutPoint } from './types';

const MAX_DPR = 1.5;
const DEGRADED_DPR = 1;
const HIGH_PARTICLE_BUDGET = 4000;
const LOW_PARTICLE_BUDGET = 300;
const LOW_FPS_THRESHOLD = 30;
const TAP_SLOP_PX = 8;
const ENTRY_DURATION_MS = 800;
const PERF_SAMPLE_MS = 2000;

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

const app = requireElement<HTMLDivElement>('app');
const nodeLayer = requireElement<HTMLDivElement>('node-layer');
const labelLayer = requireElement<HTMLDivElement>('label-layer');
const fpsPill = requireElement<HTMLSpanElement>('fps-pill');
const resetButton = requireElement<HTMLButtonElement>('reset-camera');
const bridge = new GalaxyBridge();
const relations = new GalaxyRelationOverlay(document.body);
const clock = new THREE.Clock();
const backgroundStars = new BackgroundStarfield(HIGH_PARTICLE_BUDGET);
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
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
let graph: GalaxySnapshotDTO = { nodes: [], edges: [] };
let nodeViews = new Map<string, NodeView>();
let pickMeshes: THREE.Mesh[] = [];
let selectedId: string | null = null;
let activeParticleBudget = HIGH_PARTICLE_BUDGET;
let activeDprCap = MAX_DPR;
let pausedByHost = false;
let degraded = false;
let entryStartedAt = performance.now();
let entryAnimating = true;
let pointerDown: { id: number; x: number; y: number } | null = null;
let fpsFrameCount = 0;
let fpsWindowMs = 0;
let lowFpsMs = 0;
let lastPerfSampleMs = 0;
let degradedProjectionFrame = 0;

bridge.onMessage(handleHostMessage);

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

  renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, powerPreference: 'high-performance' });
  renderer.setClearColor(0x0a0c10, 1);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, activeDprCap));
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.15;
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

  scene.add(new THREE.HemisphereLight(0xcbdcff, 0x202635, 0.45));
  // Camera-relative side lighting keeps the sphere's highlight and dark side
  // readable while the user orbits, without changing knowledge positions.
  const keyLight = new THREE.DirectionalLight(0xfff4df, 2.4);
  keyLight.position.set(-60, 45, -20);
  const rimLight = new THREE.DirectionalLight(0xc2ebff, 0.6);
  rimLight.position.set(40, 10, -120);
  const lightTarget = new THREE.Object3D();
  lightTarget.position.set(0, 0, -70);
  camera.add(lightTarget, keyLight, rimLight);
  keyLight.target = lightTarget;
  rimLight.target = lightTarget;
  scene.add(camera);

  particleGeometry = createParticleGeometry();
  const particleMaterial = createStarMaterial();
  particlePoints = new THREE.Points(particleGeometry, particleMaterial);
  particlePoints.frustumCulled = false;
  scene.add(particlePoints);

  window.addEventListener('resize', handleResize);
  document.addEventListener('visibilitychange', () => { clock.start(); });
  resetButton.addEventListener('click', resetCamera);
  renderer.domElement.addEventListener('pointerdown', handlePointerDown);
  renderer.domElement.addEventListener('pointerup', handlePointerUp);
  renderer.domElement.addEventListener('pointercancel', () => { pointerDown = null; });
  renderer.domElement.addEventListener('webglcontextlost', handleContextLost);
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
    const glow = new THREE.Mesh(new THREE.SphereGeometry(1, 32, 24), createGlowMaterial(color));
    glow.scale.setScalar(coreScale * 1.18);
    group.add(glow);
    const core = new THREE.Mesh(new THREE.SphereGeometry(1, 40, 32), createKnowledgeMaterial(color));
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
  if (pausedByHost || document.hidden || !renderer || !scene || !camera || !controls) return;
  updateBackground(delta);
  updateEntryCamera();
  controls.update();
  if (degraded) {
    degradedProjectionFrame = (degradedProjectionFrame + 1) % 2;
    if (degradedProjectionFrame === 0) {
      updateNodeAnimation(delta * 2);
      updateLabels();
      renderer.render(scene, camera);
    }
  } else {
    updateNodeAnimation(delta);
    updateLabels();
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
    view.core.scale.setScalar(base);
    view.glow.scale.setScalar(base * 1.3);
    const surface = view.core.material as THREE.MeshPhysicalMaterial;
    surface.emissive.copy(surface.color);
    surface.emissiveIntensity = THREE.MathUtils.lerp(surface.emissiveIntensity, selected ? 0.12 : 0, delta * 8);
    const material = view.glow.material as THREE.ShaderMaterial;
    material.uniforms.strength.value = THREE.MathUtils.lerp(material.uniforms.strength.value, selected ? 0.14 : 0, delta * 8);
  }
}

function updateLabels(): void {
  if (!camera || !renderer) return;
  // SVG and labels must use the same camera transform as this frame's WebGL draw.
  camera.updateMatrixWorld();
  const width = renderer.domElement.clientWidth;
  const height = renderer.domElement.clientHeight;
  const projectedNodes = new Map<string, ProjectedNode>();
  for (const view of nodeViews.values()) {
    const projected = view.position.clone().project(camera);
    const distance = camera.position.distanceTo(view.position);
    const cameraSpace = view.position.clone().applyMatrix4(camera.matrixWorldInverse);
    const left = (projected.x * 0.5 + 0.5) * width;
    const top = (-projected.y * 0.5 + 0.5) * height;
    const perspectiveScale = THREE.MathUtils.clamp(74 / Math.max(1, distance), 0.72, 1.55);
    // Use the rendered sphere's perspective size, not the retired 18px DOM orb.
    const projectedRadius = view.core.scale.x * height * camera.projectionMatrix.elements[5]
      / (2 * Math.max(0.1, -cameraSpace.z));
    const endpoint = projectViewportNode(left, top, -cameraSpace.z, distance,
      width, height, projectedRadius + 2);
    projectedNodes.set(view.dto.id, endpoint);
    const dimmed = view.orb.dataset.dimmed === 'true';
    // Both quality levels draw actual lit meshes, never DOM replacement discs.
    view.orb.style.opacity = '0';
    view.orb.style.left = `${left}px`;
    view.orb.style.top = `${top}px`;
    view.orb.style.transform = `translate(-50%, -50%) scale(${perspectiveScale})`;
    view.orb.style.zIndex = String(Math.round((1 - projected.z) * 100));
    view.label.style.opacity = String(endpoint.labelAlpha * (dimmed ? 0.5 : 1));
    view.label.style.left = `${left}px`;
    view.label.style.top = `${top}px`;
  }
  relations.update(projectedNodes, width, height);
}

function setSelection(id: string | null, notifyHost: boolean): void {
  if (id && !nodeViews.has(id)) return;
  selectedId = id;
  updateSelectionVisuals();
  if (!notifyHost) return;
  bridge.post(id ? 'node_selected' : 'selection_cleared', id ? { id } : {});
}

function updateSelectionVisuals(): void {
  relations.select(graph.edges, selectedId);
  const connected = new Set<string>();
  for (const edge of incidentRelations(graph.edges, selectedId)) {
    connected.add(edge.fromId);
    connected.add(edge.toId);
  }
  for (const view of nodeViews.values()) {
    const material = view.core.material as THREE.MeshStandardMaterial;
    material.opacity = 1;
    view.orb.dataset.selected = String(selectedId === view.dto.id);
    const dimmed = selectedId !== null && view.dto.id !== selectedId && !connected.has(view.dto.id);
    view.orb.dataset.dimmed = String(dimmed);
    view.label.dataset.dimmed = String(dimmed);
  }
  updateLabels();
}

function nodeCoreScale(node: GalaxyNodeDTO): number {
  return 1.35 + node.mastery * 0.55;
}

function handlePointerDown(event: PointerEvent): void {
  // A second finger starts a pinch, never the second click that opens a note.
  pointerDown = event.isPrimary ? { id: event.pointerId, x: event.clientX, y: event.clientY } : null;
}

function handlePointerUp(event: PointerEvent): void {
  if (!pointerDown || pointerDown.id !== event.pointerId || !renderer || !camera) return;
  const dx = event.clientX - pointerDown.x;
  const dy = event.clientY - pointerDown.y;
  pointerDown = null;
  if (Math.hypot(dx, dy) > TAP_SLOP_PX) return;
  pointer.x = event.clientX / renderer.domElement.clientWidth * 2 - 1;
  pointer.y = -(event.clientY / renderer.domElement.clientHeight) * 2 + 1;
  camera.updateMatrixWorld();
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

function createParticleGeometry(): THREE.BufferGeometry {
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(backgroundStars.positions, 3)
    .setUsage(THREE.DynamicDrawUsage));
  geometry.setAttribute('starOpacity', new THREE.BufferAttribute(backgroundStars.opacities, 1)
    .setUsage(THREE.DynamicDrawUsage));
  geometry.setDrawRange(0, activeParticleBudget);
  return geometry;
}

function updateBackground(delta: number): void {
  if (!particleGeometry) return;
  // Accessibility suppresses drift, not the independent slow fade lifecycle.
  backgroundStars.advance(delta, false, reducedMotion.matches ? 0 : 1);
  particleGeometry.getAttribute('position').needsUpdate = true;
  particleGeometry.getAttribute('starOpacity').needsUpdate = true;
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
  // Reduce particle/pixel budgets, not the dimensionality of knowledge nodes.
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
