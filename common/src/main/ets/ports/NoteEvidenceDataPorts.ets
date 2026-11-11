/**
 * NoteEvidenceDataPorts.ets — 证据链的数据访问端口
 *
 * 路径: common/src/main/ets/ports/NoteEvidenceDataPorts.ets
 * 职责: 把证据服务要的两类数据访问收成显式契约——「检索」与「图谱邻居」；
 *       读行复用已有 NoteReadPort.listByIds，不再新增第三类
 * 依赖: ../models/NoteEvidenceModels、../models/KnowledgeGraphModels
 *
 * 数据流:
 *   NoteEvidenceService（agents） → 本端口 → entry 适配器 → FTS / 工具 / RDB
 */
import type { NoteEvidenceCitation, NoteEvidenceOptions } from '../models/NoteEvidenceModels';
import type { KnowledgeRelation } from '../models/KnowledgeGraphModels';

export interface NoteGraphNode {
  unitId: string;
  depth: number;
}

export interface NoteGraphNeighborhood {
  nodes: NoteGraphNode[];
  edges: KnowledgeRelation[];
  truncated: boolean;
}

/**
 * 证据检索：一次调用拿到可直接引用的 citations（含 version）。
 * 实现负责本地 FTS 优先、工具兜底的策略——调用方只关心结果。
 */
export interface NoteEvidenceSearchPort {
  search(query: string, topK: number, options?: NoteEvidenceOptions): Promise<NoteEvidenceCitation[]>;
}

/** 图谱扩展：只返回 accepted 边与可达节点；不做引用裁剪。 */
export interface NoteGraphPort {
  expandAcceptedNeighborhood(seedIds: string[], maxDepth: number): Promise<NoteGraphNeighborhood>;
  expandAcceptedPrerequisites(seedIds: string[], maxDepth: number): Promise<NoteGraphNeighborhood>;
}
