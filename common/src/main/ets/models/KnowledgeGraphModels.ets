// ============================================================================
//  models/KnowledgeGraphModels.ets — knowledge graph and RAG storage contracts
// ============================================================================

export type KnowledgeRelationType = 'prerequisite' | 'related' | 'derived';
export type KnowledgeRelationSource = 'manual' | 'llm' | 'legacy';
export type KnowledgeRelationStatus = 'pending' | 'accepted' | 'rejected';

export interface KnowledgeRelation {
  id: string;
  fromUnitId: string;
  toUnitId: string;
  relationType: KnowledgeRelationType;
  source: KnowledgeRelationSource;
  status: KnowledgeRelationStatus;
  confidence: number;
  weight: number;
  reason: string;
  createdAt: number;
  updatedAt: number;
  version: number;
}

export interface RagChunk {
  id: string;
  unitId: string;
  chunkIndex: number;
  title: string;
  content: string;
  contentHash: string;
  tokenCount: number;
  createdAt: number;
  updatedAt: number;
}

export interface RagEmbedding {
  id: string;
  chunkId: string;
  provider: string;
  model: string;
  dimension: number;
  metric: string;
  vectorJson: string;
  createdAt: number;
  updatedAt: number;
}
