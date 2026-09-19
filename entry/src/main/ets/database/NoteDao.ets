// ============================================================================
//  database/NoteDao.ets — 知识单元数据访问层
//  ----------------------------------------------------------------------------
//  职责: RDB CRUD、KnowledgeUnit/revision 事务写入与 ValuesBucket 互转。
//  接口:
//    createWithRevision(unit, metadata): Promise<KnowledgeUnitPersistenceResult>
//    updateWithRevision(unit, expectedVersion, metadata): Promise<KnowledgeUnitPersistenceResult>
//    queryById(id): Promise<KnowledgeUnit | null> — 按 id 查询
//    queryRevision(id, version): Promise<KnowledgeUnitRevision | null>
//    rowToUnit(rs): KnowledgeUnit         — ResultSet → KnowledgeUnit
//  验证方式: 事务写入 → queryById / queryRevision 验证
//  ============================================================================

import { relationalStore } from '@kit.ArkData';
import { KnowledgeUnit, DifficultyLevel, ReviewStatus, NoteGenerationCommitResult } from 'common';
import {
  KnowledgeUnitPersistenceResult,
  KnowledgeUnitRevision,
  KnowledgeUnitWriteError,
  KnowledgeUnitWriteErrorCode,
  KnowledgeUnitWriteRepository,
  NoteGenerationBaseProvider,
} from '../models/KnowledgeUnitWriteModels';

interface NoteCommitLookup {
  noteId: string;
}

const NOTE_METADATA_COLUMNS: string[] = [
  'id', 'title', 'summary', 'tags', 'subject', 'category', 'chapter', 'difficulty', 'source',
  'created_at', 'updated_at', 'review_status', 'next_review_at', 'interval_days',
  'ease_factor', 'repetitions', 'user_id', 'version',
];

export class NoteDao implements KnowledgeUnitWriteRepository, NoteGenerationBaseProvider {
  private store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async createWithRevision(
    unit: KnowledgeUnit,
    generationMetadata: string,
  ): Promise<KnowledgeUnitPersistenceResult> {
    const transaction: relationalStore.Transaction = await this.store.createTransaction();
    try {
      const rowId: number = await transaction.insert('knowledge_unit', NoteDao.toBucket(unit));
      await transaction.insert('note_revision', NoteDao.toRevisionBucket(unit, generationMetadata));
      await transaction.commit();
      const result: KnowledgeUnitPersistenceResult = { rowId: rowId, unit: unit };
      return result;
    } catch (e) {
      await NoteDao.rollback(transaction);
      if (e instanceof KnowledgeUnitWriteError) {
        throw new KnowledgeUnitWriteError(e.code, e.message);
      }
      if (e instanceof Error) {
        throw new Error(e.message);
      }
      throw new Error(String(e));
    }
  }

  async createWithRevisionAndCommitKey(
    unit: KnowledgeUnit,
    generationMetadata: string,
    commit: NoteGenerationCommitResult,
  ): Promise<KnowledgeUnitPersistenceResult> {
    const transaction: relationalStore.Transaction = await this.store.createTransaction();
    try {
      const existing = await NoteDao.queryCommitInTransaction(transaction, commit.commitKey);
      if (existing !== null) {
        const existingUnit: KnowledgeUnit | null = await NoteDao.queryByIdInTransaction(transaction, existing.noteId);
        if (existingUnit === null) {
          throw new Error('idempotent commit record has no KnowledgeUnit');
        }
        await transaction.commit();
        return { rowId: 0, unit: existingUnit, duplicate: true };
      }
      const rowId: number = await transaction.insert('knowledge_unit', NoteDao.toBucket(unit));
      await transaction.insert('note_revision', NoteDao.toRevisionBucket(unit, generationMetadata));
      const commitBucket: relationalStore.ValuesBucket = {
        'commit_key': commit.commitKey,
        'run_id': commit.runId,
        'checkpoint_id': commit.checkpointId,
        'note_id': commit.noteId,
        'version': commit.version,
        'source_ids': JSON.stringify(commit.sourceIds),
        'candidate_json': commit.candidateJson ?? JSON.stringify(unit),
        'committed_at': commit.committedAt ?? Date.now(),
        'generation_metadata': generationMetadata,
      };
      await transaction.insert('note_generation_commit', commitBucket);
      await transaction.commit();
      return { rowId: rowId, unit: unit, duplicate: false };
    } catch (e) {
      await NoteDao.rollback(transaction);
      if (e instanceof KnowledgeUnitWriteError) {
        throw new KnowledgeUnitWriteError(e.code, e.message);
      }
      if (e instanceof Error) {
        throw new Error(e.message);
      }
      throw new Error(String(e));
    }
  }

  async updateWithRevision(
    unit: KnowledgeUnit,
    expectedVersion: number,
    generationMetadata: string,
  ): Promise<KnowledgeUnitPersistenceResult> {
    const transaction: relationalStore.Transaction = await this.store.createTransaction();
    try {
      const current: KnowledgeUnit | null = await NoteDao.queryByIdInTransaction(transaction, unit.id);
      if (current === null || current.version !== expectedVersion) {
        throw new KnowledgeUnitWriteError(
          KnowledgeUnitWriteErrorCode.VERSION_CONFLICT,
          'KnowledgeUnit version conflict for id=' + unit.id,
        );
      }
      const updated: KnowledgeUnit = NoteDao.mergeUpdate(current, unit, expectedVersion + 1);
      const predicates = new relationalStore.RdbPredicates('knowledge_unit');
      predicates.equalTo('id', unit.id);
      predicates.equalTo('version', expectedVersion);
      const rows: number = await transaction.update(NoteDao.toBucket(updated), predicates);
      if (rows === 0) {
        throw new KnowledgeUnitWriteError(
          KnowledgeUnitWriteErrorCode.VERSION_CONFLICT,
          'KnowledgeUnit version conflict for id=' + unit.id,
        );
      }
      await transaction.insert('note_revision', NoteDao.toRevisionBucket(updated, generationMetadata));
      await transaction.commit();
      const result: KnowledgeUnitPersistenceResult = { rowId: 0, unit: updated };
      return result;
    } catch (e) {
      await NoteDao.rollback(transaction);
      if (e instanceof KnowledgeUnitWriteError) {
        throw new KnowledgeUnitWriteError(e.code, e.message);
      }
      if (e instanceof Error) {
        throw new Error(e.message);
      }
      throw new Error(String(e));
    }
  }

  async updateWithRevisionAndCommitKey(
    unit: KnowledgeUnit,
    expectedVersion: number,
    generationMetadata: string,
    commit: NoteGenerationCommitResult,
  ): Promise<KnowledgeUnitPersistenceResult> {
    const transaction: relationalStore.Transaction = await this.store.createTransaction();
    try {
      const existingCommit = await NoteDao.queryCommitInTransaction(transaction, commit.commitKey);
      if (existingCommit !== null) {
        const existingUnit: KnowledgeUnit | null = await NoteDao.queryByIdInTransaction(transaction, existingCommit.noteId);
        if (existingUnit === null) {
          throw new Error('idempotent update record has no KnowledgeUnit');
        }
        await transaction.commit();
        return { rowId: 0, unit: existingUnit, duplicate: true };
      }
      const current: KnowledgeUnit | null = await NoteDao.queryByIdInTransaction(transaction, unit.id);
      if (current === null || current.version !== expectedVersion) {
        throw new KnowledgeUnitWriteError(KnowledgeUnitWriteErrorCode.VERSION_CONFLICT, 'KnowledgeUnit version conflict for id=' + unit.id);
      }
      const updated: KnowledgeUnit = NoteDao.mergeUpdate(current, unit, expectedVersion + 1);
      const predicates = new relationalStore.RdbPredicates('knowledge_unit');
      predicates.equalTo('id', unit.id);
      predicates.equalTo('version', expectedVersion);
      const rows: number = await transaction.update(NoteDao.toBucket(updated), predicates);
      if (rows === 0) {
        throw new KnowledgeUnitWriteError(KnowledgeUnitWriteErrorCode.VERSION_CONFLICT, 'KnowledgeUnit version conflict for id=' + unit.id);
      }
      await transaction.insert('note_revision', NoteDao.toRevisionBucket(updated, generationMetadata));
      const commitBucket: relationalStore.ValuesBucket = {
        'commit_key': commit.commitKey,
        'run_id': commit.runId,
        'checkpoint_id': commit.checkpointId,
        'note_id': updated.id,
        'version': updated.version,
        'source_ids': JSON.stringify(commit.sourceIds),
      'candidate_json': commit.candidateJson ?? JSON.stringify(updated),
      'committed_at': commit.committedAt ?? Date.now(),
      'generation_metadata': generationMetadata,
      };
      await transaction.insert('note_generation_commit', commitBucket);
      await transaction.commit();
      return { rowId: 0, unit: updated, duplicate: false };
    } catch (e) {
      await NoteDao.rollback(transaction);
      if (e instanceof KnowledgeUnitWriteError) {
        throw new KnowledgeUnitWriteError(e.code, e.message);
      }
      if (e instanceof Error) {
        throw new Error(e.message);
      }
      throw new Error(String(e));
    }
  }

  async queryRevision(noteId: string, version: number): Promise<KnowledgeUnitRevision | null> {
    const predicates = new relationalStore.RdbPredicates('note_revision');
    predicates.equalTo('note_id', noteId);
    predicates.equalTo('version', version);
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates, ['*']);
    if (!resultSet.goToFirstRow()) {
      resultSet.close();
      return null;
    }
    const revision: KnowledgeUnitRevision = NoteDao.rowToRevision(resultSet);
    resultSet.close();
    return revision;
  }

  async queryCurrentUnit(noteId: string): Promise<KnowledgeUnit | null> {
    return await this.queryById(noteId);
  }

  async queryLatestRevision(noteId: string): Promise<KnowledgeUnitRevision | null> {
    const predicates = new relationalStore.RdbPredicates('note_revision');
    predicates.equalTo('note_id', noteId);
    predicates.orderByDesc('version');
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates, ['*']);
    if (!resultSet.goToFirstRow()) {
      resultSet.close();
      return null;
    }
    const revision: KnowledgeUnitRevision = NoteDao.rowToRevision(resultSet);
    resultSet.close();
    return revision;
  }

  async queryLatestGeneratedRevision(noteId: string): Promise<KnowledgeUnitRevision | null> {
    const predicates = new relationalStore.RdbPredicates('note_revision');
    predicates.equalTo('note_id', noteId);
    predicates.orderByDesc('version');
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates, ['*']);
    if (!resultSet.goToFirstRow()) {
      resultSet.close();
      return null;
    }
    let revision: KnowledgeUnitRevision | null = null;
    do {
      const candidate: KnowledgeUnitRevision = NoteDao.rowToRevision(resultSet);
      if (candidate.generationMetadata.trim().startsWith('{')
        && candidate.generationMetadata.includes('"sections"')) {
        revision = candidate;
        break;
      }
    } while (resultSet.goToNextRow());
    resultSet.close();
    return revision;
  }

  // 删除知识单元
  async deleteById(id: string): Promise<void> {
    const transaction: relationalStore.Transaction = await this.store.createTransaction();
    try {
      const edgeFromPredicates = new relationalStore.RdbPredicates('kg_edge');
      edgeFromPredicates.equalTo('from_unit_id', id);
      await transaction.delete(edgeFromPredicates);

      const edgeToPredicates = new relationalStore.RdbPredicates('kg_edge');
      edgeToPredicates.equalTo('to_unit_id', id);
      await transaction.delete(edgeToPredicates);

      const chunkPredicates = new relationalStore.RdbPredicates('rag_chunk');
      chunkPredicates.equalTo('unit_id', id);
      const chunkResultSet: relationalStore.ResultSet = await transaction.query(chunkPredicates, ['id']);
      const chunkIds: string[] = [];
      try {
        if (chunkResultSet.goToFirstRow()) {
          do {
            const chunkId: string = chunkResultSet.getString(chunkResultSet.getColumnIndex('id'));
            chunkIds.push(chunkId);
          } while (chunkResultSet.goToNextRow());
        }
      } finally {
        chunkResultSet.close();
      }

      for (const chunkId of chunkIds) {
        const embeddingPredicates = new relationalStore.RdbPredicates('rag_embedding');
        embeddingPredicates.equalTo('chunk_id', chunkId);
        await transaction.delete(embeddingPredicates);
      }
      await transaction.delete(chunkPredicates);

      const predicates = new relationalStore.RdbPredicates('knowledge_unit');
      predicates.equalTo('id', id);
      // Keep the final hard delete on the same transaction object as all dependent cleanup.
      const store: relationalStore.Transaction = transaction;
      await store.delete(predicates);
      await transaction.commit();
    } catch (e) {
      await NoteDao.rollback(transaction);
      const message: string = e instanceof Error ? e.message : String(e);
      throw new Error('NoteDao.deleteById failed: ' + message);
    }
  }

  // 按 id 查询
  async queryById(id: string): Promise<KnowledgeUnit | null> {
    const predicates = new relationalStore.RdbPredicates('knowledge_unit');
    predicates.equalTo('id', id);

    return new Promise<KnowledgeUnit | null>((resolve, reject) => {
      this.store.query(predicates, ['*'], (_err, resultSet) => {
        if (_err) {
          reject(new Error('NoteDao.queryById failed: ' + _err.message));
          return;
        }
        if (resultSet.goToFirstRow()) {
          const unit: KnowledgeUnit = NoteDao.rowToUnit(resultSet);
          resultSet.close();
          resolve(unit);
        } else {
          resultSet.close();
          resolve(null);
        }
      });
    });
  }

  // 查询全部
  async queryAll(): Promise<KnowledgeUnit[]> {
    const predicates = new relationalStore.RdbPredicates('knowledge_unit');
    predicates.orderByDesc('created_at');

    return new Promise<KnowledgeUnit[]>((resolve, reject) => {
      this.store.query(predicates, ['*'], (_err, resultSet) => {
        if (_err) {
          reject(new Error('NoteDao.queryAll failed: ' + _err.message));
          return;
        }
        const units: KnowledgeUnit[] = [];
        if (resultSet.goToFirstRow()) {
          do {
            units.push(NoteDao.rowToUnit(resultSet));
          } while (resultSet.goToNextRow());
        }
        resultSet.close();
        resolve(units);
      });
    });
  }

  // List and grouping pages only need metadata. Full content is loaded by id when a detail opens.
  async queryAllMetadata(): Promise<KnowledgeUnit[]> {
    const predicates = new relationalStore.RdbPredicates('knowledge_unit');
    predicates.orderByDesc('created_at');

    return new Promise<KnowledgeUnit[]>((resolve, reject) => {
      this.store.query(predicates, NOTE_METADATA_COLUMNS, (_err, resultSet) => {
        if (_err) {
          reject(new Error('NoteDao.queryAllMetadata failed: ' + _err.message));
          return;
        }
        const units: KnowledgeUnit[] = [];
        if (resultSet.goToFirstRow()) {
          do {
            units.push(NoteDao.rowToMetadataUnit(resultSet));
          } while (resultSet.goToNextRow());
        }
        resultSet.close();
        resolve(units);
      });
    });
  }

  // Knowledge graph needs only display/review metadata. It intentionally skips content and embedding.
  async queryAllGraphMetadata(): Promise<KnowledgeUnit[]> {
    const predicates = new relationalStore.RdbPredicates('knowledge_unit');
    predicates.orderByDesc('updated_at');

    return new Promise<KnowledgeUnit[]>((resolve, reject) => {
      this.store.query(predicates, NOTE_METADATA_COLUMNS, (_err, resultSet) => {
        if (_err) {
          reject(new Error('NoteDao.queryAllGraphMetadata failed: ' + _err.message));
          return;
        }
        const units: KnowledgeUnit[] = [];
        if (resultSet.goToFirstRow()) {
          do {
            units.push(NoteDao.rowToMetadataUnit(resultSet));
          } while (resultSet.goToNextRow());
        }
        resultSet.close();
        resolve(units);
      });
    });
  }

  // 按复习状态查询
  async queryByReviewStatus(status: ReviewStatus): Promise<KnowledgeUnit[]> {
    const predicates = new relationalStore.RdbPredicates('knowledge_unit');
    predicates.equalTo('review_status', status.valueOf());
    predicates.orderByAsc('next_review_at');

    return new Promise<KnowledgeUnit[]>((resolve, reject) => {
      this.store.query(predicates, ['*'], (_err, resultSet) => {
        if (_err) {
          reject(new Error('NoteDao.queryByReviewStatus failed: ' + _err.message));
          return;
        }
        const units: KnowledgeUnit[] = [];
        if (resultSet.goToFirstRow()) {
          do {
            units.push(NoteDao.rowToUnit(resultSet));
          } while (resultSet.goToNextRow());
        }
        resultSet.close();
        resolve(units);
      });
    });
  }

  // ResultSet 转为 KnowledgeUnit
  static rowToUnit(rs: relationalStore.ResultSet): KnowledgeUnit {
    return {
      id: NoteDao.readString(rs, 'id', ''),
      title: NoteDao.readString(rs, 'title', ''),
      content: NoteDao.readString(rs, 'content', ''),
      summary: NoteDao.readString(rs, 'summary', ''),
      tags: NoteDao.parseArray(NoteDao.readString(rs, 'tags', '[]')),
      subject: NoteDao.readString(rs, 'subject', ''),
      category: NoteDao.readString(rs, 'category', ''),
      chapter: NoteDao.readString(rs, 'chapter', ''),
      difficulty: NoteDao.parseDifficulty(NoteDao.readLong(rs, 'difficulty', DifficultyLevel.EASY)),
      source: NoteDao.readString(rs, 'source', ''),
      createdAt: NoteDao.readLong(rs, 'created_at', 0),
      updatedAt: NoteDao.readLong(rs, 'updated_at', 0),
      reviewStatus: NoteDao.parseReviewStatus(NoteDao.readString(rs, 'review_status', ReviewStatus.NEW)),
      nextReviewAt: NoteDao.readLong(rs, 'next_review_at', 0),
      intervalDays: NoteDao.readLong(rs, 'interval_days', 0),
      easeFactor: NoteDao.readDouble(rs, 'ease_factor', 2.5),
      repetitions: NoteDao.readLong(rs, 'repetitions', 0),
      prerequisites: NoteDao.parseArray(NoteDao.readString(rs, 'prerequisites', '[]')),
      related: NoteDao.parseArray(NoteDao.readString(rs, 'related', '[]')),
      embedding: NoteDao.parseNumberArray(NoteDao.readString(rs, 'embedding', '[]')),
      userId: NoteDao.readString(rs, 'user_id', ''),
      version: NoteDao.readLong(rs, 'version', 1),
    };
  }

  private static rowToMetadataUnit(rs: relationalStore.ResultSet): KnowledgeUnit {
    return {
      id: NoteDao.readString(rs, 'id', ''),
      title: NoteDao.readString(rs, 'title', ''),
      content: '',
      summary: NoteDao.readString(rs, 'summary', ''),
      tags: NoteDao.parseArray(NoteDao.readString(rs, 'tags', '[]')),
      subject: NoteDao.readString(rs, 'subject', ''),
      category: NoteDao.readString(rs, 'category', ''),
      chapter: NoteDao.readString(rs, 'chapter', ''),
      difficulty: NoteDao.parseDifficulty(NoteDao.readLong(rs, 'difficulty', DifficultyLevel.EASY)),
      source: NoteDao.readString(rs, 'source', ''),
      createdAt: NoteDao.readLong(rs, 'created_at', 0),
      updatedAt: NoteDao.readLong(rs, 'updated_at', 0),
      reviewStatus: NoteDao.parseReviewStatus(NoteDao.readString(rs, 'review_status', ReviewStatus.NEW)),
      nextReviewAt: NoteDao.readLong(rs, 'next_review_at', 0),
      intervalDays: NoteDao.readLong(rs, 'interval_days', 0),
      easeFactor: NoteDao.readDouble(rs, 'ease_factor', 2.5),
      repetitions: NoteDao.readLong(rs, 'repetitions', 0),
      prerequisites: [],
      related: [],
      embedding: [],
      userId: NoteDao.readString(rs, 'user_id', ''),
      version: NoteDao.readLong(rs, 'version', 1),
    };
  }

  private static toBucket(unit: KnowledgeUnit): relationalStore.ValuesBucket {
    return {
      'id': unit.id,
      'title': unit.title,
      'content': unit.content,
      'summary': unit.summary,
      'tags': NoteDao.stringifyArray(unit.tags),
      'subject': unit.subject,
      'category': unit.category,
      'chapter': unit.chapter,
      'difficulty': unit.difficulty.valueOf(),
      'source': unit.source,
      'created_at': unit.createdAt,
      'updated_at': unit.updatedAt,
      'review_status': unit.reviewStatus.valueOf(),
      'next_review_at': unit.nextReviewAt,
      'interval_days': unit.intervalDays,
      'ease_factor': unit.easeFactor,
      'repetitions': unit.repetitions,
      'prerequisites': NoteDao.stringifyArray(unit.prerequisites),
      'related': NoteDao.stringifyArray(unit.related),
      'embedding': NoteDao.stringifyNumberArray(unit.embedding),
      'user_id': unit.userId,
      'version': unit.version,
    };
  }

  private static toRevisionBucket(
    unit: KnowledgeUnit,
    generationMetadata: string,
  ): relationalStore.ValuesBucket {
    return {
      'note_id': unit.id,
      'version': unit.version,
      'title': unit.title,
      'content': unit.content,
      'summary': unit.summary,
      'tags': NoteDao.stringifyArray(unit.tags),
      'subject': unit.subject,
      'category': unit.category,
      'chapter': unit.chapter,
      'difficulty': unit.difficulty.valueOf(),
      'source': unit.source,
      'created_at': unit.createdAt,
      'updated_at': unit.updatedAt,
      'review_status': unit.reviewStatus.valueOf(),
      'next_review_at': unit.nextReviewAt,
      'interval_days': unit.intervalDays,
      'ease_factor': unit.easeFactor,
      'repetitions': unit.repetitions,
      'prerequisites': NoteDao.stringifyArray(unit.prerequisites),
      'related': NoteDao.stringifyArray(unit.related),
      'embedding': NoteDao.stringifyNumberArray(unit.embedding),
      'user_id': unit.userId,
      'generation_metadata': generationMetadata,
      'revised_at': Date.now(),
    };
  }

  private static rowToRevision(rs: relationalStore.ResultSet): KnowledgeUnitRevision {
    const unit: KnowledgeUnit = {
      id: NoteDao.readString(rs, 'note_id', ''),
      title: NoteDao.readString(rs, 'title', ''),
      content: NoteDao.readString(rs, 'content', ''),
      summary: NoteDao.readString(rs, 'summary', ''),
      tags: NoteDao.parseArray(NoteDao.readString(rs, 'tags', '[]')),
      subject: NoteDao.readString(rs, 'subject', ''),
      category: NoteDao.readString(rs, 'category', ''),
      chapter: NoteDao.readString(rs, 'chapter', ''),
      difficulty: NoteDao.parseDifficulty(NoteDao.readLong(rs, 'difficulty', DifficultyLevel.EASY)),
      source: NoteDao.readString(rs, 'source', ''),
      createdAt: NoteDao.readLong(rs, 'created_at', 0),
      updatedAt: NoteDao.readLong(rs, 'updated_at', 0),
      reviewStatus: NoteDao.parseReviewStatus(NoteDao.readString(rs, 'review_status', ReviewStatus.NEW)),
      nextReviewAt: NoteDao.readLong(rs, 'next_review_at', 0),
      intervalDays: NoteDao.readLong(rs, 'interval_days', 0),
      easeFactor: NoteDao.readDouble(rs, 'ease_factor', 2.5),
      repetitions: NoteDao.readLong(rs, 'repetitions', 0),
      prerequisites: NoteDao.parseArray(NoteDao.readString(rs, 'prerequisites', '[]')),
      related: NoteDao.parseArray(NoteDao.readString(rs, 'related', '[]')),
      embedding: NoteDao.parseNumberArray(NoteDao.readString(rs, 'embedding', '[]')),
      userId: NoteDao.readString(rs, 'user_id', ''),
      version: NoteDao.readLong(rs, 'version', 1),
    };
    const revision: KnowledgeUnitRevision = {
      noteId: unit.id,
      version: unit.version,
      unit: unit,
      generationMetadata: NoteDao.readString(rs, 'generation_metadata', ''),
      revisedAt: NoteDao.readLong(rs, 'revised_at', unit.updatedAt),
    };
    return revision;
  }

  private static async queryByIdInTransaction(
    transaction: relationalStore.Transaction,
    id: string,
  ): Promise<KnowledgeUnit | null> {
    const predicates = new relationalStore.RdbPredicates('knowledge_unit');
    predicates.equalTo('id', id);
    const resultSet: relationalStore.ResultSet = await transaction.query(predicates, ['*']);
    if (!resultSet.goToFirstRow()) {
      resultSet.close();
      return null;
    }
    const unit: KnowledgeUnit = NoteDao.rowToUnit(resultSet);
    resultSet.close();
    return unit;
  }

  private static async queryCommitInTransaction(
    transaction: relationalStore.Transaction,
    commitKey: string,
  ): Promise<NoteCommitLookup | null> {
    const predicates = new relationalStore.RdbPredicates('note_generation_commit');
    predicates.equalTo('commit_key', commitKey);
    const resultSet: relationalStore.ResultSet = await transaction.query(predicates, ['note_id']);
    if (!resultSet.goToFirstRow()) {
      resultSet.close();
      return null;
    }
    const result: NoteCommitLookup = { noteId: resultSet.getString(resultSet.getColumnIndex('note_id')) };
    resultSet.close();
    return result;
  }

  private static mergeUpdate(current: KnowledgeUnit, changed: KnowledgeUnit, version: number): KnowledgeUnit {
    const updated: KnowledgeUnit = {
      id: current.id,
      title: changed.title,
      content: changed.content,
      summary: changed.summary,
      tags: changed.tags,
      subject: changed.subject,
      category: changed.category,
      chapter: changed.chapter,
      difficulty: changed.difficulty,
      source: current.source,
      createdAt: current.createdAt,
      updatedAt: changed.updatedAt,
      reviewStatus: current.reviewStatus,
      nextReviewAt: current.nextReviewAt,
      intervalDays: current.intervalDays,
      easeFactor: current.easeFactor,
      repetitions: current.repetitions,
      prerequisites: current.prerequisites,
      related: current.related,
       embedding: current.content === changed.content ? changed.embedding : [],
      userId: current.userId,
      version: version,
    };
    return updated;
  }

  private static async rollback(transaction: relationalStore.Transaction): Promise<void> {
    try {
      await transaction.rollback();
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      console.error('[NoteDao] transaction rollback failed: ' + message);
    }
  }

  private static stringifyArray(value: string[]): string {
    try { return JSON.stringify(value); } catch (e) { return '[]'; }
  }

  private static stringifyNumberArray(value: number[]): string {
    try { return JSON.stringify(value); } catch (e) { return '[]'; }
  }

  private static parseArray(json: string): string[] {
    try { return JSON.parse(json) as string[]; } catch (e) { return []; }
  }

  private static parseNumberArray(json: string): number[] {
    try { return JSON.parse(json) as number[]; } catch (e) { return []; }
  }

  private static parseDifficulty(value: number): DifficultyLevel {
    if (value === DifficultyLevel.EASY) { return DifficultyLevel.EASY; }
    if (value === DifficultyLevel.MEDIUM) { return DifficultyLevel.MEDIUM; }
    if (value === DifficultyLevel.HARD) { return DifficultyLevel.HARD; }
    if (value === DifficultyLevel.EXPERT) { return DifficultyLevel.EXPERT; }
    return DifficultyLevel.EASY;
  }

  private static parseReviewStatus(value: string): ReviewStatus {
    if (value === ReviewStatus.LEARNING) { return ReviewStatus.LEARNING; }
    if (value === ReviewStatus.REVIEW) { return ReviewStatus.REVIEW; }
    if (value === ReviewStatus.GRADUATED) { return ReviewStatus.GRADUATED; }
    if (value === ReviewStatus.LAPSED) { return ReviewStatus.LAPSED; }
    return ReviewStatus.NEW;
  }

  private static readString(rs: relationalStore.ResultSet, columnName: string, fallback: string): string {
    const index: number = NoteDao.safeColumnIndex(rs, columnName);
    if (index < 0) {
      return fallback;
    }
    return rs.getString(index);
  }

  private static readLong(rs: relationalStore.ResultSet, columnName: string, fallback: number): number {
    const index: number = NoteDao.safeColumnIndex(rs, columnName);
    if (index < 0) {
      return fallback;
    }
    return rs.getLong(index);
  }

  private static readDouble(rs: relationalStore.ResultSet, columnName: string, fallback: number): number {
    const index: number = NoteDao.safeColumnIndex(rs, columnName);
    if (index < 0) {
      return fallback;
    }
    return rs.getDouble(index);
  }

  private static safeColumnIndex(rs: relationalStore.ResultSet, columnName: string): number {
    try {
      return rs.getColumnIndex(columnName);
    } catch (e) {
      console.warn('[NoteDao.rowToUnit] missing column ' + columnName + ': ' + ((e as Error).message ?? String(e)));
      return -1;
    }
  }
}
