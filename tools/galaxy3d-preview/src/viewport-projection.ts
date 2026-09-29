/** Continuous visibility and viewport-edge positions for decorative galaxy endpoints. */
export interface ViewportNode {
  x: number;
  y: number;
  radius: number;
  visible: boolean;
  alpha: number;
  labelAlpha: number;
  edgeGlow: number;
}

function smooth(value: number): number {
  const t = Math.max(0, Math.min(1, value));
  return t * t * (3 - 2 * t);
}

export function projectViewportNode(x: number, y: number, depth: number, distance: number,
  width: number, height: number, radius: number): ViewportNode {
  const valid = [x, y, depth, distance, width, height].every(Number.isFinite)
    && width > 32 && height > 32 && depth > 0;
  if (!valid) return { x: 0, y: 0, radius, visible: false, alpha: 0, labelAlpha: 0, edgeGlow: 0 };
  const inset = 16;
  const dx = x - width / 2;
  const dy = y - height / 2;
  const ratio = Math.max(1, Math.abs(dx) / (width / 2 - inset), Math.abs(dy) / (height / 2 - inset));
  const margin = Math.min(x - inset, width - inset - x, y - inset, height - inset - y);
  const edgeFade = smooth(margin / 42);
  // Fade labels before the old distance=92 cutoff; keep a faint point beyond it.
  const distanceFade = 1 - smooth((distance - 76) / 40);
  const nearFade = smooth((depth - 0.1) / 6);
  const alpha = (0.12 + 0.88 * distanceFade) * (0.16 + 0.84 * edgeFade) * nearFade;
  return {
    x: width / 2 + dx / ratio, y: height / 2 + dy / ratio,
    radius: radius * (0.35 + 0.65 * edgeFade), visible: nearFade > 0,
    alpha, labelAlpha: distanceFade * edgeFade * nearFade,
    edgeGlow: (1 - edgeFade) * nearFade,
  };
}
