/**
 * NoteDaoReadStore.ets — NoteReadStore 的 entry 版实现（复用 NoteDao 的既有查询）
 *
 * 路径: entry/src/main/ets/database/NoteDaoReadStore.ets
 * 职责: 把 NoteDao 查出来的 KnowledgeUnit 投影成 NoteDetail，供 entry 内消费者与测试使用；
 *       不新增 SQL、不改 DAO，只做字段投影（ADR-0021：只读实现可复用，写路径不动）。
 * 依赖: NoteDao；common 的 NoteReadStore / NoteDetail 契约（type-only）。
 *
 * 数据流:
 *   NoteReadPortAdapter(list / get / listByIds) → NoteDaoReadStore → NoteDao.queryById / queryAllMetadata
 */
import type { KnowledgeUnit, NoteDetail, NoteReadStore } from 'common';
import type { NoteDao } from './NoteDao';

export class NoteDaoReadStore implements NoteReadStore {
  private readonly dao: NoteDao;

  constructor(dao: NoteDao) {
    this.dao = dao;
  }

  async queryById(id: string): Promise<NoteDetail | null> {
    const unit: KnowledgeUnit | null = await this.dao.queryById(id);
    if (unit === null) {
      return null;
    }
    return NoteDaoReadStore.toDetail(unit);
  }

  async queryAllMetadata(): Promise<NoteDetail[]> {
    const units: KnowledgeUnit[] = await this.dao.queryAllMetadata();
    return units.map((unit: KnowledgeUnit): NoteDetail => NoteDaoReadStore.toDetail(unit));
  }

  private static toDetail(unit: KnowledgeUnit): NoteDetail {
    const detail: NoteDetail = {
      id: unit.id,
      title: unit.title,
      content: unit.content,
      summary: unit.summary,
      tags: unit.tags.slice(),
      subject: unit.subject,
      category: unit.category,
      chapter: unit.chapter,
      difficulty: unit.difficulty,
      reviewStatus: unit.reviewStatus,
      nextReviewAt: unit.nextReviewAt,
      intervalDays: unit.intervalDays,
      easeFactor: unit.easeFactor,
      repetitions: unit.repetitions,
      userId: unit.userId,
      createdAt: unit.createdAt,
      updatedAt: unit.updatedAt,
      version: unit.version,
      source: unit.source,
    };
    if (unit.sourceImageId !== undefined) {
      detail.sourceImageId = unit.sourceImageId;
    }
    if (unit.sourceRegion !== undefined) {
      detail.sourceRegion = unit.sourceRegion;
    }
    if (unit.ocrConfidence !== undefined) {
      detail.ocrConfidence = unit.ocrConfidence;
    }
    return detail;
  }
}
