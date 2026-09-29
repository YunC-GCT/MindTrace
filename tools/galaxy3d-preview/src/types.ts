export type GalaxyEdgeType = 'prerequisite' | 'related';

export interface GalaxyNodeDTO {
  id: string;
  label: string;
  subject: string;
  chapter: string;
  mastery: number;
  color: string;
}

export interface GalaxyEdgeDTO {
  id: string;
  fromId: string;
  toId: string;
  type: GalaxyEdgeType;
}

export interface GalaxySnapshotDTO {
  nodes: GalaxyNodeDTO[];
  edges: GalaxyEdgeDTO[];
}

export interface LayoutPoint {
  id: string;
  x: number;
  y: number;
  z: number;
}

export interface HostMessage {
  version: number;
  type: string;
  payload: {
    snapshot?: GalaxySnapshotDTO;
    selectedId?: string | null;
    paused?: boolean;
  };
}

export interface RendererMessage {
  version: number;
  type: string;
  payload: {
    id?: string;
    reason?: string;
    fps?: number;
    particles?: number;
    degraded?: boolean;
  };
}
