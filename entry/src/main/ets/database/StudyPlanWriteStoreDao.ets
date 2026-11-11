/**
 * StudyPlanWriteStoreDao.ets — StudyPlanWriteStore 的生产实现（study_plan + study_plan_op）
 *
 * 路径: entry/src/main/ets/database/StudyPlanWriteStoreDao.ets
 * 职责: 待办的 insert / update / setDone，每个写操作都在**同一事务**里写业务行 + 操作记录，
 *       保证 operationId 幂等与版本号推进原子化。
 * 依赖: @kit.ArkData（relationalStore）、common 的契约类型与 uuid。
 *
 * 数据流:
 *   StudyPlanWritePortAdapter → insertRecord / updateRecord / setDone → study_plan + study_plan_op
 *
 * schema（v17）:
 *   study_plan 新增 version 列（CAS）；study_plan_op(operation_id PK, plan_id, kind, version, committed_at)
 */
import { relationalStore } from '@kit.ArkData';
import { uuid } from 'common';
import type {
  StudyPlanOperationRecord,
  StudyPlanRecord,
  StudyPlanWriteCommand,
  StudyPlanWriteRecord,
  StudyPlanWriteStore,
} from 'common';

const PLAN_COLUMNS: string = 'id, title, is_done, priority, linked_note_id, created_at, due_date, version';

export class StudyPlanWriteStoreDao implements StudyPlanWriteStore {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async queryOperation(operationId: string): Promise<StudyPlanOperationRecord | null> {
    const predicates = new relationalStore.RdbPredicates('study_plan_op');
    predicates.equalTo('operation_id', operationId);
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates, ['*']);
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      const operation: StudyPlanOperationRecord = {
        operationId: StudyPlanWriteStoreDao.readString(resultSet, 'operation_id'),
        planId: StudyPlanWriteStoreDao.readString(resultSet, 'plan_id'),
        kind: StudyPlanWriteStoreDao.readString(resultSet, 'kind'),
        version: StudyPlanWriteStoreDao.readLong(resultSet, 'version'),
        committedAt: StudyPlanWriteStoreDao.readLong(resultSet, 'committed_at'),
      };
      return operation;
    } finally {
      resultSet.close();
    }
  }

  async queryRecord(id: string): Promise<StudyPlanWriteRecord | null> {
    const predicates = new relationalStore.RdbPredicates('study_plan');
    predicates.equalTo('id', id);
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates, ['*']);
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      return StudyPlanWriteStoreDao.toRecord(resultSet);
    } finally {
      resultSet.close();
    }
  }

  async insertRecord(item: StudyPlanRecord, command: StudyPlanWriteCommand): Promise<StudyPlanWriteRecord> {
    const id: string = item.id.length > 0 ? item.id : uuid();
    const now: number = Date.now();
    const transaction: relationalStore.Transaction = await this.store.createTransaction();
    try {
      const bucket: relationalStore.ValuesBucket = {
        'id': id,
        'title': item.title,
        'is_done': item.isDone ? 1 : 0,
        'priority': item.priority,
        'linked_note_id': item.linkedNoteId,
        'created_at': item.createdAt > 0 ? item.createdAt : now,
        'due_date': item.dueDate,
        'version': 1,
      };
      await transaction.insert('study_plan', bucket);
      await StudyPlanWriteStoreDao.insertOperation(transaction, command.operationId, id, 'create', 1, now);
      await transaction.commit();
      const written: StudyPlanWriteRecord = {
        id: id,
        title: item.title,
        isDone: item.isDone,
        priority: item.priority,
        linkedNoteId: item.linkedNoteId,
        createdAt: item.createdAt > 0 ? item.createdAt : now,
        dueDate: item.dueDate,
        version: 1,
      };
      return written;
    } catch (e) {
      await StudyPlanWriteStoreDao.rollbackQuietly(transaction);
      const message: string = e instanceof Error ? e.message : String(e);
      throw new Error('StudyPlanWriteStoreDao.insertRecord failed: ' + message);
    }
  }

  async updateRecord(item: StudyPlanRecord, command: StudyPlanWriteCommand): Promise<StudyPlanWriteRecord> {
    if (item.id.length === 0) {
      throw new Error('StudyPlanWriteStoreDao.updateRecord: id is required');
    }
    const now: number = Date.now();
    const transaction: relationalStore.Transaction = await this.store.createTransaction();
    try {
      const current: StudyPlanWriteRecord | null = await StudyPlanWriteStoreDao.queryInTransaction(transaction, item.id);
      if (current === null) {
        throw new Error('study_plan row not found: ' + item.id);
      }
      StudyPlanWriteStoreDao.assertVersion(current, command);
      const nextVersion: number = current.version + 1;
      const bucket: relationalStore.ValuesBucket = {
        'title': item.title,
        'is_done': item.isDone ? 1 : 0,
        'priority': item.priority,
        'linked_note_id': item.linkedNoteId,
        'due_date': item.dueDate,
        'version': nextVersion,
      };
      const predicates = new relationalStore.RdbPredicates('study_plan');
      predicates.equalTo('id', item.id);
      predicates.equalTo('version', current.version);
      const rows: number = await transaction.update(bucket, predicates);
      if (rows === 0) {
        throw new Error('study_plan version race: ' + item.id);
      }
      await StudyPlanWriteStoreDao.insertOperation(transaction, command.operationId, item.id, 'update', nextVersion, now);
      await transaction.commit();
      const written: StudyPlanWriteRecord = {
        id: item.id,
        title: item.title,
        isDone: item.isDone,
        priority: item.priority,
        linkedNoteId: item.linkedNoteId,
        createdAt: current.createdAt,
        dueDate: item.dueDate,
        version: nextVersion,
      };
      return written;
    } catch (e) {
      await StudyPlanWriteStoreDao.rollbackQuietly(transaction);
      const message: string = e instanceof Error ? e.message : String(e);
      throw new Error('StudyPlanWriteStoreDao.updateRecord failed: ' + message);
    }
  }

  async setDone(id: string, done: boolean, command: StudyPlanWriteCommand): Promise<StudyPlanWriteRecord> {
    const now: number = Date.now();
    const transaction: relationalStore.Transaction = await this.store.createTransaction();
    try {
      const current: StudyPlanWriteRecord | null = await StudyPlanWriteStoreDao.queryInTransaction(transaction, id);
      if (current === null) {
        throw new Error('study_plan row not found: ' + id);
      }
      StudyPlanWriteStoreDao.assertVersion(current, command);
      const nextVersion: number = current.version + 1;
      const bucket: relationalStore.ValuesBucket = {
        'is_done': done ? 1 : 0,
        'version': nextVersion,
      };
      const predicates = new relationalStore.RdbPredicates('study_plan');
      predicates.equalTo('id', id);
      predicates.equalTo('version', current.version);
      const rows: number = await transaction.update(bucket, predicates);
      if (rows === 0) {
        throw new Error('study_plan version race: ' + id);
      }
      await StudyPlanWriteStoreDao.insertOperation(transaction, command.operationId, id, done ? 'complete' : 'reopen',
        nextVersion, now);
      await transaction.commit();
      const written: StudyPlanWriteRecord = {
        id: current.id,
        title: current.title,
        isDone: done,
        priority: current.priority,
        linkedNoteId: current.linkedNoteId,
        createdAt: current.createdAt,
        dueDate: current.dueDate,
        version: nextVersion,
      };
      return written;
    } catch (e) {
      await StudyPlanWriteStoreDao.rollbackQuietly(transaction);
      const message: string = e instanceof Error ? e.message : String(e);
      throw new Error('StudyPlanWriteStoreDao.setDone failed: ' + message);
    }
  }

  private static async queryInTransaction(transaction: relationalStore.Transaction,
    id: string): Promise<StudyPlanWriteRecord | null> {
    const sql: string = 'SELECT ' + PLAN_COLUMNS + ' FROM study_plan WHERE id = ? LIMIT 1';
    return new Promise<StudyPlanWriteRecord | null>((resolve, reject) => {
      transaction.querySql(sql, [id], (err, resultSet) => {
        if (err) {
          reject(new Error('StudyPlanWriteStoreDao.queryInTransaction failed: ' + err.message));
          return;
        }
        let found: StudyPlanWriteRecord | null = null;
        if (resultSet.goToFirstRow()) {
          found = StudyPlanWriteStoreDao.toRecord(resultSet);
        }
        resultSet.close();
        resolve(found);
      });
    });
  }

  private static async insertOperation(transaction: relationalStore.Transaction, operationId: string,
    planId: string, kind: string, version: number, committedAt: number): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'operation_id': operationId,
      'plan_id': planId,
      'kind': kind,
      'version': version,
      'committed_at': committedAt,
    };
    await transaction.insert('study_plan_op', bucket);
  }

  private static assertVersion(record: StudyPlanWriteRecord, command: StudyPlanWriteCommand): void {
    const expected: number | undefined = command.expectedVersion;
    if (expected !== undefined && record.version !== expected) {
      throw new Error('study_plan version conflict: expected ' + expected.toString()
        + ', actual ' + record.version.toString());
    }
  }

  private static async rollbackQuietly(transaction: relationalStore.Transaction): Promise<void> {
    try {
      await transaction.rollback();
    } catch (e) {
      // 回滚失败不掩盖原始错误
    }
  }

  private static toRecord(rs: relationalStore.ResultSet): StudyPlanWriteRecord {
    const record: StudyPlanWriteRecord = {
      id: StudyPlanWriteStoreDao.readString(rs, 'id'),
      title: StudyPlanWriteStoreDao.readString(rs, 'title'),
      isDone: StudyPlanWriteStoreDao.readLong(rs, 'is_done') === 1,
      priority: StudyPlanWriteStoreDao.readLong(rs, 'priority'),
      linkedNoteId: StudyPlanWriteStoreDao.readString(rs, 'linked_note_id'),
      createdAt: StudyPlanWriteStoreDao.readLong(rs, 'created_at'),
      dueDate: StudyPlanWriteStoreDao.readLong(rs, 'due_date'),
      version: StudyPlanWriteStoreDao.readLong(rs, 'version'),
    };
    return record;
  }

  private static readString(rs: relationalStore.ResultSet, column: string): string {
    try {
      return rs.getString(rs.getColumnIndex(column));
    } catch (e) {
      return '';
    }
  }

  private static readLong(rs: relationalStore.ResultSet, column: string): number {
    try {
      return rs.getLong(rs.getColumnIndex(column));
    } catch (e) {
      return 0;
    }
  }
}
