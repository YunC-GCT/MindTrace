// MindTrace - entry-side NoteDao adapter for agents/ NoteDaoInterface
// 2026-09-05 · D2 Ticket #5
import { KnowledgeUnit, ReviewStatus } from 'common';
import { KnowledgeUnitExt, NoteDaoInterface } from 'agents';

export class NoteDaoAdapter implements NoteDaoInterface {
  private readonly insertUnit: (unit: KnowledgeUnit) => Promise<number>;

  constructor(insertUnit: (unit: KnowledgeUnit) => Promise<number>) {
    this.insertUnit = insertUnit;
  }

  async insert(ext: KnowledgeUnitExt): Promise<number> {
    const unit: KnowledgeUnit = {
      id: ext.id,
      title: ext.title,
      content: ext.content,
      summary: '',
      tags: ext.tags,
      subject: ext.subject,
      category: ext.type,
      chapter: ext.chapter,
      difficulty: ext.difficulty,
      source: ext.source,
      createdAt: ext.createdAt,
      updatedAt: ext.updatedAt,
      reviewStatus: ReviewStatus.NEW,
      nextReviewAt: 0,
      intervalDays: 0,
      easeFactor: 0,
      repetitions: 0,
      prerequisites: [],
      related: [],
      embedding: [],
      userId: ext.userId,
      version: 1,
    };
    return await this.insertUnit(unit);
  }
}

