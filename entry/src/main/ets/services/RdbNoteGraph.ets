/**
 * RdbNoteGraph.ets — 证据图谱扩展的 entry 实现
 *
 * 路径: entry/src/main/ets/services/RdbNoteGraph.ets
 * 职责: 实现 NoteGraphPort：把 KnowledgeRelationDao 的 accepted 邻居/前置扩展
 *       适配成 agents 侧可直接消费的节点与边
 * 依赖: @kit.ArkData、common（NoteGraphPort）、./database/KnowledgeRelationDao
 *
 * 数据流:
 *   NoteEvidenceService（agents） → 本适配器 → KnowledgeRelationDao → kg_edge
 */
import { DatabaseHelper } from 'common';
import type { NoteGraphNeighborhood, NoteGraphPort } from 'common';
import { relationalStore } from '@kit.ArkData';
import {
  GraphExpansion,
  GraphExpansionLimits,
  KnowledgeRelationDao,
} from '../database/KnowledgeRelationDao';

export class RdbNoteGraph implements NoteGraphPort {
  async expandAcceptedNeighborhood(seedIds: string[], maxDepth: number): Promise<NoteGraphNeighborhood> {
    return await this.expand(seedIds, maxDepth, false);
  }

  async expandAcceptedPrerequisites(seedIds: string[], maxDepth: number): Promise<NoteGraphNeighborhood> {
    return await this.expand(seedIds, maxDepth, true);
  }

  private async expand(
    seedIds: string[],
    maxDepth: number,
    prerequisites: boolean,
  ): Promise<NoteGraphNeighborhood> {
    const empty: NoteGraphNeighborhood = { nodes: [], edges: [], truncated: false };
    if (seedIds.length === 0) {
      return empty;
    }
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      return empty;
    }
    const dao: KnowledgeRelationDao = new KnowledgeRelationDao(store);
    const limits: GraphExpansionLimits = { maxDepth: maxDepth };
    const expansion: GraphExpansion = prerequisites
      ? await dao.expandAcceptedPrerequisites(seedIds, limits)
      : await dao.expandAcceptedNeighborhood(seedIds, limits);
    return { nodes: expansion.nodes, edges: expansion.edges, truncated: expansion.truncated };
  }
}
