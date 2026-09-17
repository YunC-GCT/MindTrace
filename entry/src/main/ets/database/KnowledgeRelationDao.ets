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
    const sql: string = "SELECT * FROM kg_edge WHERE from_unit_id = ? OR to_unit_id = ? ORDER BY updated_at DESC";
    return await this.querySql(sql, [normalizedId, normalizedId]);
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
