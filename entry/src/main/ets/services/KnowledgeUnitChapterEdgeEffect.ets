/**
 * KnowledgeUnitChapterEdgeEffect.ets — 新笔记同章节增量补边
 *
 * 路径: entry/src/main/ets/services/KnowledgeUnitChapterEdgeEffect.ets
 * 职责: 新笔记提交后，为它与同 chapter 最近 20 条笔记写入 same_unit 边
 * 依赖: relationalStore, NoteDao, KnowledgeRelationDao, common
 *
 * 数据流:
 *   KnowledgeUnitWriteService(create) → effect.run
 *     → NoteDao.queryRecentUnitIdsByChapter
 *     → KnowledgeRelationDao.insertRelationIfAbsent → kg_edge
 */

import { relationalStore } from '@kit.ArkData';
import { KnowledgeRelation, KnowledgeUnit, uuid } from 'common';
import { KnowledgeRelationDao } from '../database/KnowledgeRelationDao';
import { NoteDao } from '../database/NoteDao';
import { KnowledgeUnitPostCommitEffect } from '../models/KnowledgeUnitWriteModels';

const SAME_CHAPTER_NEIGHBOR_LIMIT: number = 20;

export class KnowledgeUnitChapterEdgeEffect implements KnowledgeUnitPostCommitEffect {
  name: string = 'same_chapter_edges';
  createOnly: boolean = true;
  private notes: NoteDao;
  private relations: KnowledgeRelationDao;

  constructor(store: relationalStore.RdbStore) {
    this.notes = new NoteDao(store);
    this.relations = new KnowledgeRelationDao(store);
  }

  async run(unit: KnowledgeUnit): Promise<void> {
    const chapter: string = unit.chapter.trim();
    if (chapter.length === 0 || chapter === '未知') {
      return;
    }
    const neighborIds: string[] = await this.notes.queryRecentUnitIdsByChapter(
      chapter,
      unit.id,
      SAME_CHAPTER_NEIGHBOR_LIMIT,
    );
    const now: number = Date.now();
    for (const neighborId of neighborIds) {
      if (neighborId.length === 0 || neighborId === unit.id) {
        continue;
      }
      const relation: KnowledgeRelation = {
        id: uuid(),
        fromUnitId: unit.id,
        toUnitId: neighborId,
        relationType: 'same_unit',
        source: 'auto',
        status: 'accepted',
        confidence: 1,
        weight: 1,
        reason: 'same_chapter',
        createdAt: now,
        updatedAt: now,
        version: 1,
      };
      await this.relations.insertRelationIfAbsent(relation);
    }

    // TODO(similar): 当前写入链路（CaptureStructurer / draftToKnowledgeUnit）固定产出
    // embedding: []，rag_embedding 也只有 demo 种子数据，没有可用的两端向量。
    // 因此这里只补 same_unit，不计算也不伪造相似度。待 embedding 生成接入后，
    // 再对本批同章节笔记按 cosine 相似度写 relation_type='similar' 的边。
  }
}
