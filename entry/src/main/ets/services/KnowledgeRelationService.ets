// ============================================================================
//  services/KnowledgeRelationService.ets — unified relation write flow
// ============================================================================

import {
  KnowledgeRelation,
  KnowledgeRelationStatus,
  KnowledgeRelationType,
  uuid,
} from 'common';
import { KnowledgeRelationDao } from '../database/KnowledgeRelationDao';

export interface KnowledgeRelationRequest {
  fromUnitId: string;
  toUnitId: string;
  relationType: KnowledgeRelationType;
  confidence: number;
  weight: number;
  reason: string;
}

export class KnowledgeRelationService {
  private dao: KnowledgeRelationDao;

  constructor(dao: KnowledgeRelationDao) {
    this.dao = dao;
  }

  async saveManualRelation(request: KnowledgeRelationRequest): Promise<KnowledgeRelation> {
    return await this.saveRelation(request, 'accepted', 'manual');
  }

  async saveLlmSuggestion(request: KnowledgeRelationRequest): Promise<KnowledgeRelation> {
    return await this.saveRelation(request, 'pending', 'llm');
  }

  async acceptRelation(id: string): Promise<boolean> {
    return await this.dao.acceptRelation(id);
  }

  async rejectRelation(id: string): Promise<boolean> {
    return await this.dao.rejectRelation(id);
  }

  async queryPendingRelations(): Promise<KnowledgeRelation[]> {
    return await this.dao.queryPendingRelations();
  }

  async queryAcceptedRelations(): Promise<KnowledgeRelation[]> {
    return await this.dao.queryAcceptedEdges();
  }

  async queryRelationsByUnitId(unitId: string): Promise<KnowledgeRelation[]> {
    return await this.dao.queryByUnitId(unitId);
  }

  private async saveRelation(
    request: KnowledgeRelationRequest,
    status: KnowledgeRelationStatus,
    source: 'manual' | 'llm',
  ): Promise<KnowledgeRelation> {
    const normalizedFrom: string = request.fromUnitId.trim();
    const normalizedTo: string = request.toUnitId.trim();
    if (normalizedFrom.length === 0 || normalizedTo.length === 0) {
      throw new Error('KnowledgeRelation requires non-empty unit ids');
    }
    if (normalizedFrom === normalizedTo) {
      throw new Error('KnowledgeRelation cannot point to itself');
    }
    const fromUnitId: string = this.normalizeFromUnitId(normalizedFrom, normalizedTo, request.relationType);
    const toUnitId: string = this.normalizeToUnitId(normalizedFrom, normalizedTo, request.relationType);
    const now: number = Date.now();
    const relation: KnowledgeRelation = {
      id: uuid(),
      fromUnitId: fromUnitId,
      toUnitId: toUnitId,
      relationType: request.relationType,
      source: source,
      status: status,
      confidence: this.clamp01(request.confidence),
      weight: this.clamp01(request.weight),
      reason: request.reason,
      createdAt: now,
      updatedAt: now,
      version: 1,
    };
    return await this.dao.saveRelation(relation);
  }

  private normalizeFromUnitId(fromUnitId: string, toUnitId: string, relationType: KnowledgeRelationType): string {
    if (relationType !== 'related') {
      return fromUnitId;
    }
    return fromUnitId < toUnitId ? fromUnitId : toUnitId;
  }

  private normalizeToUnitId(fromUnitId: string, toUnitId: string, relationType: KnowledgeRelationType): string {
    if (relationType !== 'related') {
      return toUnitId;
    }
    return fromUnitId < toUnitId ? toUnitId : fromUnitId;
  }

  private clamp01(value: number): number {
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }
}
