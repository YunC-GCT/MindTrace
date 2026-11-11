import type { GalaxyEdgeDTO } from './types';

const SVG_NS = 'http://www.w3.org/2000/svg';

export interface ProjectedNode {
  x: number;
  y: number;
  radius: number;
  visible: boolean;
  alpha?: number;
  edgeGlow?: number;
}

export function incidentRelations(edges: GalaxyEdgeDTO[], selectedId: string | null): GalaxyEdgeDTO[] {
  return selectedId ? edges.filter((edge) => edge.fromId === selectedId || edge.toId === selectedId) : [];
}

/** Trim lines to the visible orb boundary; never connect through the back of the camera. */
export function relationSegment(source: ProjectedNode, target: ProjectedNode): number[] | null {
  if (!source.visible || !target.visible) return null;
  const dx = target.x - source.x;
  const dy = target.y - source.y;
  const length = Math.hypot(dx, dy);
  if (!Number.isFinite(length) || length <= source.radius + target.radius) return null;
  return [source.x + dx / length * source.radius, source.y + dy / length * source.radius,
    target.x - dx / length * target.radius, target.y - dy / length * target.radius];
}

/** Screen-space relationships stay readable even when WebGL rendering is degraded. */
export class GalaxyRelationOverlay {
  private root = document.createElementNS(SVG_NS, 'svg');
  private group = document.createElementNS(SVG_NS, 'g');
  private defs = document.createElementNS(SVG_NS, 'defs');
  private hint = document.createElement('div');
  private lines: { edge: GalaxyEdgeDTO; element: SVGLineElement;
    gradient: SVGLinearGradientElement; stops: SVGStopElement[] }[] = [];

  constructor(container: HTMLElement) {
    this.root.id = 'relation-layer';
    this.root.setAttribute('aria-hidden', 'true');
    this.root.append(this.defs, this.group);
    this.hint.id = 'relation-hint';
    this.hint.setAttribute('role', 'status');
    container.append(this.root, this.hint);
    this.select([], null);
  }

  select(edges: GalaxyEdgeDTO[], selectedId: string | null): void {
    this.group.replaceChildren();
    this.defs.replaceChildren();
    this.lines = incidentRelations(edges, selectedId).map((edge, index) => {
      const element = document.createElementNS(SVG_NS, 'line');
      element.setAttribute('class', `galaxy-relation galaxy-relation--${edge.type}`);
      const color = edge.type === 'prerequisite' ? '#d78c9b' : '#b4a0e5';
      const gradient = document.createElementNS(SVG_NS, 'linearGradient');
      gradient.id = `relation-fade-${index}`;
      gradient.setAttribute('gradientUnits', 'userSpaceOnUse');
      const stops = [0, 0.5, 1].map((offset) => {
        const stop = document.createElementNS(SVG_NS, 'stop');
        stop.setAttribute('offset', String(offset));
        stop.setAttribute('stop-color', color);
        gradient.appendChild(stop);
        return stop;
      });
      this.defs.appendChild(gradient);
      element.setAttribute('stroke', `url(#${gradient.id})`);
      this.group.appendChild(element);
      return { edge, element, gradient, stops };
    });
    this.hint.textContent = selectedId
      ? this.lines.length > 0
        ? `${this.lines.length} 条关联 · 紫色为相关，微红为前置 · 再点打开笔记`
        : '暂无已记录关联 · 再点打开笔记'
      : '单击知识点查看关联 · 再点打开笔记';
  }

  update(nodes: Map<string, ProjectedNode>, width: number, height: number): void {
    this.root.setAttribute('viewBox', `0 0 ${width} ${height}`);
    for (const { edge, element, gradient, stops } of this.lines) {
      const source = nodes.get(edge.fromId);
      const target = nodes.get(edge.toId);
      const segment = source && target ? relationSegment(source, target) : null;
      element.style.display = segment ? '' : 'none';
      if (!segment) continue;
      ['x1', 'y1', 'x2', 'y2'].forEach((attribute, index) => {
        element.setAttribute(attribute, String(segment[index]));
        gradient.setAttribute(attribute, String(segment[index]));
      });
      const sourceAlpha = source?.alpha ?? 1;
      const targetAlpha = target?.alpha ?? 1;
      const alphas = [sourceAlpha * 0.4, Math.max(sourceAlpha, targetAlpha) * 0.3, targetAlpha * 0.4];
      stops.forEach((stop, index) => stop.setAttribute('stop-opacity', String(alphas[index])));
    }
  }
}
