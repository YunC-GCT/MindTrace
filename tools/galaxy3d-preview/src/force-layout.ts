import type { GalaxyEdgeDTO, GalaxyNodeDTO, LayoutPoint } from './types';

interface Vec3 {
  x: number;
  y: number;
  z: number;
}

const ITERATIONS = 300;
const REPULSION = 68;
const SPRING = 0.018;
const CENTER = 0.012;
const TARGET_EDGE = 22;
const MAX_STEP = 1.6;

export function createGalaxyLayout(
  nodes: GalaxyNodeDTO[],
  edges: GalaxyEdgeDTO[],
  seed = 20260920,
): LayoutPoint[] {
  const random = mulberry32(seed);
  const positions = new Map<string, Vec3>();
  const velocities = new Map<string, Vec3>();
  const nodeIds = nodes.map((node) => node.id);

  nodes.forEach((node, index) => {
    const angle = index * 2.399963 + random() * 0.35;
    const radius = 8 + Math.sqrt(index + 1) * 8.2;
    positions.set(node.id, {
      x: Math.cos(angle) * radius,
      y: Math.sin(angle) * radius * 0.68,
      z: (random() - 0.5) * 18,
    });
    velocities.set(node.id, { x: 0, y: 0, z: 0 });
  });

  for (let step = 0; step < ITERATIONS; step += 1) {
    repelNodes(nodeIds, positions, velocities);
    attractEdges(edges, positions, velocities);
    integrate(nodeIds, positions, velocities);
  }

  return nodeIds.map((id) => {
    const position = positions.get(id) ?? { x: 0, y: 0, z: 0 };
    return { id, x: round(position.x), y: round(position.y), z: round(position.z) };
  });
}

function repelNodes(ids: string[], positions: Map<string, Vec3>, velocities: Map<string, Vec3>): void {
  for (let i = 0; i < ids.length; i += 1) {
    for (let j = i + 1; j < ids.length; j += 1) {
      const a = positions.get(ids[i]);
      const b = positions.get(ids[j]);
      const va = velocities.get(ids[i]);
      const vb = velocities.get(ids[j]);
      if (!a || !b || !va || !vb) continue;
      const dx = a.x - b.x;
      const dy = a.y - b.y;
      const dz = a.z - b.z;
      const distSq = Math.max(dx * dx + dy * dy + dz * dz, 0.01);
      const dist = Math.sqrt(distSq);
      const force = REPULSION / distSq;
      const fx = dx / dist * force;
      const fy = dy / dist * force;
      const fz = dz / dist * force * 0.68;
      va.x += fx; va.y += fy; va.z += fz;
      vb.x -= fx; vb.y -= fy; vb.z -= fz;
    }
  }
}

function attractEdges(
  edges: GalaxyEdgeDTO[],
  positions: Map<string, Vec3>,
  velocities: Map<string, Vec3>,
): void {
  for (const edge of edges) {
    const a = positions.get(edge.fromId);
    const b = positions.get(edge.toId);
    const va = velocities.get(edge.fromId);
    const vb = velocities.get(edge.toId);
    if (!a || !b || !va || !vb) continue;
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const dz = b.z - a.z;
    const dist = Math.max(Math.sqrt(dx * dx + dy * dy + dz * dz), 0.01);
    const force = (dist - TARGET_EDGE) * SPRING;
    const fx = dx / dist * force;
    const fy = dy / dist * force;
    const fz = dz / dist * force;
    va.x += fx; va.y += fy; va.z += fz;
    vb.x -= fx; vb.y -= fy; vb.z -= fz;
  }
}

function integrate(ids: string[], positions: Map<string, Vec3>, velocities: Map<string, Vec3>): void {
  for (const id of ids) {
    const position = positions.get(id);
    const velocity = velocities.get(id);
    if (!position || !velocity) continue;
    velocity.x -= position.x * CENTER;
    velocity.y -= position.y * CENTER;
    velocity.z -= position.z * CENTER * 1.25;
    limitVector(velocity, MAX_STEP);
    position.x += velocity.x;
    position.y += velocity.y;
    position.z += velocity.z;
    velocity.x *= 0.82;
    velocity.y *= 0.82;
    velocity.z *= 0.82;
  }
}

function limitVector(vector: Vec3, maxLength: number): void {
  const length = Math.sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z);
  if (length <= maxLength || length === 0) return;
  const scale = maxLength / length;
  vector.x *= scale;
  vector.y *= scale;
  vector.z *= scale;
}

function round(value: number): number {
  return Math.round(value * 1000) / 1000;
}

function mulberry32(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state += 0x6d2b79f5;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}
