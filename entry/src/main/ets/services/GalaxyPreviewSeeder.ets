/**
 * GalaxyPreviewSeeder.ets — 一次性样例笔记导入
 * 路径: entry/src/main/ets/services/GalaxyPreviewSeeder.ets
 * 职责: 协调样例笔记与关系的持久化。
 * 依赖: common 模型、持久化边界 GalaxyPreviewSeedStore。
 * 数据流: ensureSeeded → store → RDB / 完成标记。
 */
import { KnowledgeRelation, KnowledgeUnit } from 'common';

export interface GalaxyPreviewSeedStore {
  isComplete(): Promise<boolean>;
  markComplete(): Promise<void>;
  findUnit(id: string): Promise<KnowledgeUnit | null>;
  hasRevision(id: string): Promise<boolean>;
  createUnit(unit: KnowledgeUnit): Promise<void>;
  hasRelation(relation: KnowledgeRelation): Promise<boolean>;
  createRelation(relation: KnowledgeRelation): Promise<void>;
}

export class GalaxyPreviewSeeder {
  private store: GalaxyPreviewSeedStore;
  private loading: Promise<void> | null = null;

  constructor(store: GalaxyPreviewSeedStore) {
    this.store = store;
  }

  async ensureSeeded(units: KnowledgeUnit[], relations: KnowledgeRelation[]): Promise<void> {
    if (this.loading === null) {
      this.loading = this.seed(units, relations);
    }
    try {
      await this.loading;
    } finally {
      this.loading = null;
    }
  }

  private async seed(units: KnowledgeUnit[], relations: KnowledgeRelation[]): Promise<void> {
    if (await this.store.isComplete()) {
      return;
    }
    for (const unit of units) {
      if (await this.store.findUnit(unit.id) === null && !await this.store.hasRevision(unit.id)) {
        await this.store.createUnit(unit);
      }
    }
    for (const relation of relations) {
      if (await this.store.findUnit(relation.fromUnitId) !== null
        && await this.store.findUnit(relation.toUnitId) !== null
        && !await this.store.hasRelation(relation)) {
        await this.store.createRelation(relation);
      }
    }
    await this.store.markComplete();
  }
}
