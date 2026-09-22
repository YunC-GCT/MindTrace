// ============================================================================
//  database/KnowledgeRelationDao.ets — kg_edge data access
// ============================================================================

import { relationalStore } from '@kit.ArkData';
import {
  KnowledgeRelation,
  KnowledgeRelationSource,
  KnowledgeRelationStatus,
  KnowledgeRelationType,
} from 'common';

// DEV-005: accepted prerequisite/related 有限深度扩展契约
// - 默认深度 1, 硬上限 2; 节点硬上限 20; 边硬上限 40
// - 只走 status='accepted' 且 relation_type in (prerequisite, related) 的边
// - 两端 note id 必须仍存活于 knowledge_unit, 删除后产生的孤儿边被排除
export interface GraphExpansionLimits {
  maxDepth?: number;
  maxNodes?: number;
  maxEdges?: number;
}

export interface GraphExpansionNode {
  unitId: string;
  depth: number;
}

export interface GraphExpansion {
  nodes: GraphExpansionNode[];
  edges: KnowledgeRelation[];
  truncated: boolean;
}

const EXPANSION_DEFAULT_DEPTH: number = 1;
const EXPANSION_MAX_DEPTH: number = 2;
const EXPANSION_MAX_NODES: number = 20;
const EXPANSION_MAX_EDGES: number = 40;
const EXPANSION_RELATION_TYPES: string = "('prerequisite', 'related')";

export class KnowledgeRelationDao {
  private store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async saveRelation(relation: KnowledgeRelation): Promise<KnowledgeRelation> {
    const existing: KnowledgeRelation | null = await this.queryByUnique(
      relation.fromUnitId,
      relation.toUnitId,
      relation.relationType,
    );
    if (existing !== null) {
      const updated: KnowledgeRelation = {
        id: existing.id,
        fromUnitId: relation.fromUnitId,
        toUnitId: relation.toUnitId,
        relationType: relation.relationType,
        source: relation.source,
        status: relation.status,
        confidence: relation.confidence,
        weight: relation.weight,
        reason: relation.reason,
        createdAt: existing.createdAt,
        updatedAt: relation.updatedAt,
        version: existing.version + 1,
      };
      const predicates = new relationalStore.RdbPredicates('kg_edge');
      predicates.equalTo('id', existing.id);
      await this.updateByPredicates(KnowledgeRelationDao.toBucket(updated), predicates);
      return updated;
    }
    await this.insertRelation(relation);
    return relation;
  }

  async queryAcceptedEdges(): Promise<KnowledgeRelation[]> {
    const predicates = new relationalStore.RdbPredicates('kg_edge');
    predicates.equalTo('status', 'accepted');
    predicates.orderByDesc('updated_at');
    return await this.queryByPredicates(predicates);
  }

  async queryPendingRelations(): Promise<KnowledgeRelation[]> {
    const predicates = new relationalStore.RdbPredicates('kg_edge');
    predicates.equalTo('status', 'pending');
    predicates.orderByDesc('updated_at');
    return await this.queryByPredicates(predicates);
  }

  async queryByUnitId(unitId: string): Promise<KnowledgeRelation[]> {
    const normalizedId: string = unitId.trim();
    if (normalizedId.length === 0) {
      return [];
    }
    const sql: string = "SELECT edge.* FROM kg_edge AS edge"
      + " INNER JOIN knowledge_unit AS from_unit ON from_unit.id = edge.from_unit_id"
      + " INNER JOIN knowledge_unit AS to_unit ON to_unit.id = edge.to_unit_id"
      + " WHERE (edge.from_unit_id = ? OR edge.to_unit_id = ?)"
      + " ORDER BY edge.updated_at DESC";
    return await this.querySql(sql, [normalizedId, normalizedId]);
  }

  // 从 seed 笔记出发做有限深度 BFS: 只扩展 accepted prerequisite/related, 去重防环,
  // 节点/边数量受限, 两端笔记必须存活 (孤儿边被丢弃)
  async expandAcceptedNeighborhood(
    seedUnitIds: string[],
    limits?: GraphExpansionLimits,
  ): Promise<GraphExpansion> {
    const depthLimit: number = KnowledgeRelationDao.clampLimit(limits?.maxDepth, EXPANSION_DEFAULT_DEPTH, 1, EXPANSION_MAX_DEPTH);
    const nodeLimit: number = KnowledgeRelationDao.clampLimit(limits?.maxNodes, EXPANSION_MAX_NODES, 1, EXPANSION_MAX_NODES);
    const edgeLimit: number = KnowledgeRelationDao.clampLimit(limits?.maxEdges, EXPANSION_MAX_EDGES, 1, EXPANSION_MAX_EDGES);
    const seeds: string[] = KnowledgeRelationDao.normalizeUnitIds(seedUnitIds);
    if (seeds.length === 0) {
      return { nodes: [], edges: [], truncated: false };
    }
    const nodes: GraphExpansionNode[] = [];
    const edges: KnowledgeRelation[] = [];
    const edgeSeen: Map<string, boolean> = new Map<string, boolean>();
    const visited: Map<string, number> = new Map<string, number>();
    let truncated: boolean = false;
    const liveSeeds: string[] = await this.queryLiveUnitIds(seeds);
    if (liveSeeds.length < seeds.length) {
      truncated = true;
    }
    const frontier: string[] = [];
    for (const seedId of liveSeeds) {
      if (nodes.length >= nodeLimit) {
        truncated = true;
        break;
      }
      nodes.push({ unitId: seedId, depth: 0 });
      visited.set(seedId, 0);
      frontier.push(seedId);
    }
    let depth: number = 1;
    let current: string[] = frontier;
    while (depth <= depthLimit && current.length > 0) {
      const levelEdges: KnowledgeRelation[] = await this.queryAcceptedEdgesForUnits(current);
      const candidates: string[] = [];
      for (const edge of levelEdges) {
        const fromVisited: boolean = visited.has(edge.fromUnitId);
        const toVisited: boolean = visited.has(edge.toUnitId);
        if (fromVisited && !toVisited) {
          KnowledgeRelationDao.addUnique(candidates, edge.toUnitId);
        } else if (toVisited && !fromVisited) {
          KnowledgeRelationDao.addUnique(candidates, edge.fromUnitId);
        }
      }
      const liveCandidates: string[] = await this.queryLiveUnitIds(candidates);
      const next: string[] = [];
      for (const edge of levelEdges) {
        if (edgeSeen.has(edge.id)) {
          continue;
        }
        const fromVisited: boolean = visited.has(edge.fromUnitId);
        const toVisited: boolean = visited.has(edge.toUnitId);
        let neighbor: string = '';
        if (fromVisited && !toVisited) {
          neighbor = edge.toUnitId;
        } else if (toVisited && !fromVisited) {
          neighbor = edge.fromUnitId;
        } else if (!fromVisited && !toVisited) {
          continue;
        }
        if (neighbor.length > 0) {
          // 孤儿边 / 已删除笔记: 直接跳过, 不进入证据
          if (liveCandidates.indexOf(neighbor) < 0) {
            continue;
          }
          if (nodes.length >= nodeLimit) {
            truncated = true;
            continue;
          }
          nodes.push({ unitId: neighbor, depth: depth });
          visited.set(neighbor, depth);
          next.push(neighbor);
        }
        if (edges.length >= edgeLimit) {
          truncated = true;
          continue;
        }
        edgeSeen.set(edge.id, true);
        edges.push(edge);
      }
      current = next;
      depth += 1;
    }
    const expansion: GraphExpansion = { nodes: nodes, edges: edges, truncated: truncated };
    return expansion;
  }

  async acceptRelation(id: string): Promise<boolean> {
    return await this.updateStatus(id, 'accepted');
  }

  async rejectRelation(id: string): Promise<boolean> {
    return await this.updateStatus(id, 'rejected');
  }

  async updateStatus(id: string, status: KnowledgeRelationStatus): Promise<boolean> {
    const normalizedId: string = id.trim();
    if (normalizedId.length === 0) {
      return false;
    }
    const predicates = new relationalStore.RdbPredicates('kg_edge');
    predicates.equalTo('id', normalizedId);
    const bucket: relationalStore.ValuesBucket = {
      'status': status,
      'updated_at': Date.now(),
    };
    const rows: number = await this.updateByPredicates(bucket, predicates);
    return rows > 0;
  }

  private async insertRelation(relation: KnowledgeRelation): Promise<number> {
    const bucket: relationalStore.ValuesBucket = KnowledgeRelationDao.toBucket(relation);
    return new Promise<number>((resolve, reject) => {
      this.store.insert('kg_edge', bucket, (err: Error, rowId: number) => {
        if (err) {
          reject(new Error('KnowledgeRelationDao.insertRelation failed: ' + err.message));
          return;
        }
        resolve(rowId);
      });
    });
  }

  private async updateByPredicates(
    bucket: relationalStore.ValuesBucket,
    predicates: relationalStore.RdbPredicates,
  ): Promise<number> {
    return new Promise<number>((resolve, reject) => {
      this.store.update(bucket, predicates, (err: Error, rows: number) => {
        if (err) {
          reject(new Error('KnowledgeRelationDao.updateByPredicates failed: ' + err.message));
          return;
        }
        resolve(rows);
      });
    });
  }

  private async queryByUnique(
    fromUnitId: string,
    toUnitId: string,
    relationType: KnowledgeRelationType,
  ): Promise<KnowledgeRelation | null> {
    const predicates = new relationalStore.RdbPredicates('kg_edge');
    predicates.equalTo('from_unit_id', fromUnitId);
    predicates.equalTo('to_unit_id', toUnitId);
    predicates.equalTo('relation_type', relationType);
    const relations: KnowledgeRelation[] = await this.queryByPredicates(predicates);
    if (relations.length === 0) {
      return null;
    }
    return relations[0];
  }

  private async queryByPredicates(predicates: relationalStore.RdbPredicates): Promise<KnowledgeRelation[]> {
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates, ['*']);
    const relations: KnowledgeRelation[] = KnowledgeRelationDao.readRelations(resultSet);
    resultSet.close();
    return relations;
  }

  private async querySql(sql: string, bindArgs: string[]): Promise<KnowledgeRelation[]> {
    return new Promise<KnowledgeRelation[]>((resolve, reject) => {
      this.store.querySql(sql, bindArgs, (err, resultSet) => {
        if (err) {
          reject(new Error('KnowledgeRelationDao.querySql failed: ' + err.message));
          return;
        }
        const relations: KnowledgeRelation[] = KnowledgeRelationDao.readRelations(resultSet);
        resultSet.close();
        resolve(relations);
      });
    });
  }

  // 只取 accepted 的 prerequisite/related 边; 固定排序保证 BFS 结果确定
  private async queryAcceptedEdgesForUnits(unitIds: string[]): Promise<KnowledgeRelation[]> {
    const placeholders: string = KnowledgeRelationDao.placeholders(unitIds.length);
    const sql: string = "SELECT * FROM kg_edge WHERE status = 'accepted' AND relation_type IN "
      + EXPANSION_RELATION_TYPES
      + ' AND (from_unit_id IN (' + placeholders + ') OR to_unit_id IN (' + placeholders + '))'
      + ' ORDER BY relation_type ASC, from_unit_id ASC, to_unit_id ASC, id ASC';
    const bindArgs: string[] = [];
    for (const unitId of unitIds) {
      bindArgs.push(unitId);
    }
    for (const unitId of unitIds) {
      bindArgs.push(unitId);
    }
    return await this.querySql(sql, bindArgs);
  }

  // 存活校验: knowledge_unit 中不存在的笔记视为已删除, 其关系边不进入证据
  private async queryLiveUnitIds(unitIds: string[]): Promise<string[]> {
    if (unitIds.length === 0) {
      return [];
    }
    const placeholders: string = KnowledgeRelationDao.placeholders(unitIds.length);
    const sql: string = 'SELECT id FROM knowledge_unit WHERE id IN (' + placeholders + ') ORDER BY id ASC';
    return new Promise<string[]>((resolve, reject) => {
      this.store.querySql(sql, unitIds, (err, resultSet) => {
        if (err) {
          reject(new Error('KnowledgeRelationDao.queryLiveUnitIds failed: ' + err.message));
          return;
        }
        const ids: string[] = [];
        if (resultSet.goToFirstRow()) {
          do {
            ids.push(KnowledgeRelationDao.readString(resultSet, 'id', ''));
          } while (resultSet.goToNextRow());
        }
        resultSet.close();
        resolve(ids);
      });
    });
  }

  private static placeholders(count: number): string {
    const parts: string[] = [];
    for (let index = 0; index < count; index += 1) {
      parts.push('?');
    }
    return parts.join(',');
  }

  private static normalizeUnitIds(unitIds: string[]): string[] {
    const unique: string[] = [];
    for (const raw of unitIds) {
      KnowledgeRelationDao.addUnique(unique, raw.trim());
    }
    unique.sort((a: string, b: string): number => {
      if (a < b) {
        return -1;
      }
      if (a > b) {
        return 1;
      }
      return 0;
    });
    return unique;
  }

  private static addUnique(target: string[], value: string): void {
    if (value.length > 0 && target.indexOf(value) < 0) {
      target.push(value);
    }
  }

  private static clampLimit(value: number | undefined, fallback: number, min: number, max: number): number {
    if (value === undefined || Number.isNaN(value)) {
      return fallback;
    }
    let clamped: number = Math.floor(value);
    if (clamped < min) {
      clamped = min;
    }
    if (clamped > max) {
      clamped = max;
    }
    return clamped;
  }

  private static readRelations(resultSet: relationalStore.ResultSet): KnowledgeRelation[] {
    const relations: KnowledgeRelation[] = [];
    if (resultSet.goToFirstRow()) {
      do {
        relations.push(KnowledgeRelationDao.rowToRelation(resultSet));
      } while (resultSet.goToNextRow());
    }
    return relations;
  }

  private static rowToRelation(rs: relationalStore.ResultSet): KnowledgeRelation {
    return {
      id: KnowledgeRelationDao.readString(rs, 'id', ''),
      fromUnitId: KnowledgeRelationDao.readString(rs, 'from_unit_id', ''),
      toUnitId: KnowledgeRelationDao.readString(rs, 'to_unit_id', ''),
      relationType: KnowledgeRelationDao.parseRelationType(KnowledgeRelationDao.readString(rs, 'relation_type', 'related')),
      source: KnowledgeRelationDao.parseSource(KnowledgeRelationDao.readString(rs, 'source', 'manual')),
      status: KnowledgeRelationDao.parseStatus(KnowledgeRelationDao.readString(rs, 'status', 'accepted')),
      confidence: KnowledgeRelationDao.readDouble(rs, 'confidence', 1),
      weight: KnowledgeRelationDao.readDouble(rs, 'weight', 1),
      reason: KnowledgeRelationDao.readString(rs, 'reason', ''),
      createdAt: KnowledgeRelationDao.readLong(rs, 'created_at', 0),
      updatedAt: KnowledgeRelationDao.readLong(rs, 'updated_at', 0),
      version: KnowledgeRelationDao.readLong(rs, 'version', 1),
    };
  }

  private static toBucket(relation: KnowledgeRelation): relationalStore.ValuesBucket {
    return {
      'id': relation.id,
      'from_unit_id': relation.fromUnitId,
      'to_unit_id': relation.toUnitId,
      'relation_type': relation.relationType,
      'source': relation.source,
      'status': relation.status,
      'confidence': relation.confidence,
      'weight': relation.weight,
      'reason': relation.reason,
      'created_at': relation.createdAt,
      'updated_at': relation.updatedAt,
      'version': relation.version,
    };
  }

  private static parseRelationType(value: string): KnowledgeRelationType {
    if (value === 'prerequisite') {
      return 'prerequisite';
    }
    if (value === 'derived') {
      return 'derived';
    }
    return 'related';
  }

  private static parseSource(value: string): KnowledgeRelationSource {
    if (value === 'llm') {
      return 'llm';
    }
    if (value === 'legacy') {
      return 'legacy';
    }
    return 'manual';
  }

  private static parseStatus(value: string): KnowledgeRelationStatus {
    if (value === 'pending') {
      return 'pending';
    }
    if (value === 'rejected') {
      return 'rejected';
    }
    return 'accepted';
  }

  private static readString(rs: relationalStore.ResultSet, columnName: string, fallback: string): string {
    const index: number = rs.getColumnIndex(columnName);
    if (index < 0) {
      return fallback;
    }
    return rs.getString(index);
  }

  private static readLong(rs: relationalStore.ResultSet, columnName: string, fallback: number): number {
    const index: number = rs.getColumnIndex(columnName);
    if (index < 0) {
      return fallback;
    }
    return rs.getLong(index);
  }

  private static readDouble(rs: relationalStore.ResultSet, columnName: string, fallback: number): number {
    const index: number = rs.getColumnIndex(columnName);
    if (index < 0) {
      return fallback;
    }
    return rs.getDouble(index);
  }
}
