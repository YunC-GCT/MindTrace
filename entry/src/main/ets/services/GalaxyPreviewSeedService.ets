/**
 * GalaxyPreviewSeedService.ets — 样例笔记 RDB 导入组合根
 * 路径: entry/src/main/ets/services/GalaxyPreviewSeedService.ets
 * 职责: 组合持久化适配器，串行执行可重试的样例导入。
 * 依赖: ArkData、NoteDao、KnowledgeUnitWriteServiceFactory。
 * 数据流: Notes / Galaxy → ensureSeeded → 统一写入服务 → RDB。
 */
import { common } from '@kit.AbilityKit';
import { preferences, relationalStore } from '@kit.ArkData';
import { DatabaseHelper, KnowledgeRelation, KnowledgeUnit } from 'common';
import { NoteDao } from '../database/NoteDao';
import { KnowledgeRelationDao } from '../database/KnowledgeRelationDao';
import { KnowledgeUnitWriteResult } from '../models/KnowledgeUnitWriteModels';
import { GalaxyPreviewData, ENABLE_GALAXY_PREVIEW_UNITS } from './GalaxyPreviewData';
import { GalaxyPreviewSeeder, GalaxyPreviewSeedStore } from './GalaxyPreviewSeeder';
import { KnowledgeUnitWriteService } from './KnowledgeUnitWriteService';
import { KnowledgeUnitWriteServiceFactory } from './KnowledgeUnitWriteServiceFactory';

class RdbGalaxyPreviewSeedStore implements GalaxyPreviewSeedStore {
  private notes: NoteDao;
  private relations: KnowledgeRelationDao;
  private writer: KnowledgeUnitWriteService;
  private settings: preferences.Preferences;

  constructor(store: relationalStore.RdbStore, writer: KnowledgeUnitWriteService,
    settings: preferences.Preferences) {
    this.notes = new NoteDao(store);
    this.relations = new KnowledgeRelationDao(store);
    this.writer = writer;
    this.settings = settings;
  }

  async isComplete(): Promise<boolean> {
    return await this.settings.get('rdb_samples_v1', false) === true;
  }

  async markComplete(): Promise<void> {
    await this.settings.put('rdb_samples_v1', true);
    await this.settings.flush();
  }

  async findUnit(id: string): Promise<KnowledgeUnit | null> {
    return await this.notes.queryById(id);
  }

  async hasRevision(id: string): Promise<boolean> {
    return await this.notes.queryLatestRevision(id) !== null;
  }

  async createUnit(unit: KnowledgeUnit): Promise<void> {
    const result: KnowledgeUnitWriteResult = await this.writer.create(unit);
    for (const warning of result.warnings) {
      console.warn('[GalaxyPreviewSeedService] post-commit warning: ' + warning);
    }
  }

  async hasRelation(relation: KnowledgeRelation): Promise<boolean> {
    const edges: KnowledgeRelation[] = await this.relations.queryByUnitId(relation.fromUnitId);
    for (const edge of edges) {
      if (edge.fromUnitId === relation.fromUnitId && edge.toUnitId === relation.toUnitId
        && edge.relationType === relation.relationType) {
        return true;
      }
    }
    return false;
  }

  async createRelation(relation: KnowledgeRelation): Promise<void> {
    await this.relations.saveRelation(relation);
  }
}

export class GalaxyPreviewSeedService {
  private static loading: Promise<void> | null = null;
  private static completed: boolean = false;

  static async ensureSeeded(context: Context): Promise<void> {
    if (!ENABLE_GALAXY_PREVIEW_UNITS || GalaxyPreviewSeedService.completed) {
      return;
    }
    if (GalaxyPreviewSeedService.loading === null) {
      GalaxyPreviewSeedService.loading = GalaxyPreviewSeedService.seed(context);
    }
    try {
      await GalaxyPreviewSeedService.loading;
      GalaxyPreviewSeedService.completed = true;
    } finally {
      GalaxyPreviewSeedService.loading = null;
    }
  }

  private static async seed(context: Context): Promise<void> {
    const store: relationalStore.RdbStore = await DatabaseHelper.init(context);
    const writer: KnowledgeUnitWriteService = await KnowledgeUnitWriteServiceFactory.create(
      context as common.UIAbilityContext);
    const settings: preferences.Preferences = await preferences.getPreferences(context, 'galaxy_preview_seed');
    const storage: RdbGalaxyPreviewSeedStore = new RdbGalaxyPreviewSeedStore(store, writer, settings);
    const data: GalaxyPreviewData = new GalaxyPreviewData();
    const units: KnowledgeUnit[] = data.units();
    await new GalaxyPreviewSeeder(storage).ensureSeeded(units, data.relations(units));
  }
}
