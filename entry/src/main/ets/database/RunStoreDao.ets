/**
 * RunStoreDao.ets — RunStoreStore 的生产实现（run_store / run_event 两表）
 *
 * 路径: entry/src/main/ets/database/RunStoreDao.ets
 * 职责: 把 RunStoreStore 的五个方法落到 RDB：记录读写 + 事件追加（事务内 MAX(sequence)+1）+ 事件分页；
 *       另提供观测用计数：countRecordsByRunPrefixAndStatus / countEventsByRunPrefix。
 * 依赖: @kit.ArkData（relationalStore）、common 的 RunRecord / RunEvent / RunStoreStore 契约、common uuid。
 *
 * 数据流:
 *   RunStoreAdapter → queryRecord / insert / update / appendEvent / listEvents → run_store / run_event
 *   scheduler 观测 → countRecordsByRunPrefixAndStatus / countEventsByRunPrefix → run_store / run_event
 *
 * schema（v16）:
 *   run_store(run_id PK, parent_run_id, status, checkpoint_id, committed_note_id, committed_version, created_at, updated_at)
 *   run_event(event_id PK, run_id, sequence, kind, payload_json, created_at) + idx(run_id, sequence)
 */
import { relationalStore } from '@kit.ArkData';
import { uuid } from 'common';
import type { RunEvent, RunRecord, RunStatus, RunStoreStore } from 'common';

const RECORD_COLUMNS: string = 'run_id, parent_run_id, status, checkpoint_id,'
  + ' committed_note_id, committed_version, created_at, updated_at';
const EVENT_COLUMNS: string = 'event_id, run_id, sequence, kind, payload_json, created_at';
const APPEND_ATTEMPTS: number = 3;
const RETRY_DELAY_MS: number = 50;

export class RunStoreDao implements RunStoreStore {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async queryRecord(runId: string): Promise<RunRecord | null> {
    const predicates = new relationalStore.RdbPredicates('run_store');
    predicates.equalTo('run_id', runId);
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates, ['*']);
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      return RunStoreDao.toRecord(resultSet);
    } finally {
      resultSet.close();
    }
  }

  async insertRecord(record: RunRecord): Promise<void> {
    const now: number = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'run_id': record.runId,
      'parent_run_id': record.parentRunId ?? '',
      'status': record.status,
      'checkpoint_id': record.checkpointId ?? '',
      'committed_note_id': record.committedNoteId ?? '',
      'committed_version': record.committedVersion ?? 0,
      'created_at': now,
      'updated_at': record.updatedAt > 0 ? record.updatedAt : now,
    };
    await this.store.insert('run_store', bucket);
  }

  async updateRecord(record: RunRecord): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('run_store');
    predicates.equalTo('run_id', record.runId);
    const bucket: relationalStore.ValuesBucket = {
      'parent_run_id': record.parentRunId ?? '',
      'status': record.status,
      'checkpoint_id': record.checkpointId ?? '',
      'committed_note_id': record.committedNoteId ?? '',
      'committed_version': record.committedVersion ?? 0,
      'updated_at': record.updatedAt > 0 ? record.updatedAt : Date.now(),
    };
    const rows: number = await this.store.update(bucket, predicates);
    if (rows === 0) {
      throw new Error('run_store row not found: ' + record.runId);
    }
  }

  async listEvents(runId: string, afterSequence: number, limit: number): Promise<RunEvent[]> {
    const sql: string = 'SELECT ' + EVENT_COLUMNS + ' FROM run_event'
      + ' WHERE run_id = ? AND sequence > ? ORDER BY sequence ASC LIMIT ?';
    const args: string[] = [runId, afterSequence.toString(), limit.toString()];
    const resultSet: relationalStore.ResultSet = await this.store.querySql(sql, args);
    try {
      const events: RunEvent[] = [];
      if (resultSet.goToFirstRow()) {
        do {
          events.push(RunStoreDao.toEvent(resultSet));
        } while (resultSet.goToNextRow());
      }
      return events;
    } finally {
      resultSet.close();
    }
  }

  /** 按 run_id 前缀统计事件数（观测脚本/自检用；schema 知识只留在此 DAO）。 */
  /** 按 run_id 前缀 + 终态统计 run_store 行数（S2：写任务终态验证）。 */
  async countRecordsByRunPrefixAndStatus(prefix: string, status: string): Promise<number> {
    const sql: string = 'SELECT COUNT(*) AS c FROM run_store WHERE run_id LIKE ? AND status = ?';
    const args: string[] = [prefix + '%', status];
    const resultSet: relationalStore.ResultSet = await this.store.querySql(sql, args);
    try {
      return resultSet.goToFirstRow() ? resultSet.getLong(resultSet.getColumnIndex('c')) : 0;
    } finally {
      resultSet.close();
    }
  }

  async countEventsByRunPrefix(prefix: string): Promise<number> {
    const sql: string = 'SELECT COUNT(*) AS c FROM run_event WHERE run_id LIKE ?';
    const args: string[] = [prefix + '%'];
    const resultSet: relationalStore.ResultSet = await this.store.querySql(sql, args);
    try {
      return resultSet.goToFirstRow() ? resultSet.getLong(resultSet.getColumnIndex('c')) : 0;
    } finally {
      resultSet.close();
    }
  }

  async appendEvent(runId: string, kind: string, payloadJson: string, createdAt: number): Promise<RunEvent> {
    let lastMessage: string = '';
    for (let attempt = 0; attempt < APPEND_ATTEMPTS; attempt += 1) {
      try {
        return await this.appendEventOnce(runId, kind, payloadJson, createdAt);
      } catch (e) {
        lastMessage = e instanceof Error ? e.message : String(e);
        if (!RunStoreDao.isRetryableWriteError(lastMessage)
          || attempt + 1 >= APPEND_ATTEMPTS) {
          break;
        }
        await RunStoreDao.delay(RETRY_DELAY_MS);
      }
    }
    throw new Error('RunStoreDao.appendEvent failed: ' + lastMessage);
  }

  /** 单次尝试：事务内 MAX(sequence)+1；跨进程 busy/唯一冲突由外层重试。 */
  private async appendEventOnce(runId: string, kind: string, payloadJson: string,
    createdAt: number): Promise<RunEvent> {
    const transaction: relationalStore.Transaction = await this.store.createTransaction();
    try {
      const maxSequence: number = await RunStoreDao.queryMaxSequence(transaction, runId);
      const sequence: number = maxSequence + 1;
      const eventId: string = uuid();
      const bucket: relationalStore.ValuesBucket = {
        'event_id': eventId,
        'run_id': runId,
        'sequence': sequence,
        'kind': kind,
        'payload_json': payloadJson,
        'created_at': createdAt,
      };
      await transaction.insert('run_event', bucket);
      await transaction.commit();
      const event: RunEvent = {
        eventId: eventId,
        runId: runId,
        sequence: sequence,
        kind: kind,
        payloadJson: payloadJson,
        createdAt: createdAt,
      };
      return event;
    } catch (e) {
      try {
        await transaction.rollback();
      } catch (rollbackError) {
        // 回滚失败不掩盖原始错误
      }
      const message: string = e instanceof Error ? e.message : String(e);
      throw new Error(message);
    }
  }

  private static isRetryableWriteError(message: string): boolean {
    const lower: string = message.toLowerCase();
    return lower.indexOf('busy') >= 0 || lower.indexOf('locked') >= 0
      || lower.indexOf('unique constraint') >= 0 || lower.indexOf('constraint failed') >= 0
      || lower.indexOf('14800015') >= 0;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout((): void => {
        resolve();
      }, ms);
    });
  }

  private static async queryMaxSequence(transaction: relationalStore.Transaction, runId: string): Promise<number> {
    const resultSet: relationalStore.ResultSet = await transaction.querySql(
      'SELECT COALESCE(MAX(sequence), 0) AS max_seq FROM run_event WHERE run_id = ?',
      [runId],
    );
    try {
      let maxSequence: number = 0;
      if (resultSet.goToFirstRow()) {
        maxSequence = resultSet.getLong(resultSet.getColumnIndex('max_seq'));
      }
      return maxSequence;
    } finally {
      resultSet.close();
    }
  }

  private static toRecord(rs: relationalStore.ResultSet): RunRecord {
    const record: RunRecord = {
      runId: RunStoreDao.readString(rs, 'run_id'),
      status: RunStoreDao.readString(rs, 'status') as RunStatus,
      updatedAt: RunStoreDao.readLong(rs, 'updated_at'),
    };
    const parentRunId: string = RunStoreDao.readString(rs, 'parent_run_id');
    if (parentRunId.length > 0) {
      record.parentRunId = parentRunId;
    }
    const checkpointId: string = RunStoreDao.readString(rs, 'checkpoint_id');
    if (checkpointId.length > 0) {
      record.checkpointId = checkpointId;
    }
    const committedNoteId: string = RunStoreDao.readString(rs, 'committed_note_id');
    if (committedNoteId.length > 0) {
      record.committedNoteId = committedNoteId;
      record.committedVersion = RunStoreDao.readLong(rs, 'committed_version');
    }
    return record;
  }

  private static toEvent(rs: relationalStore.ResultSet): RunEvent {
    const event: RunEvent = {
      eventId: RunStoreDao.readString(rs, 'event_id'),
      runId: RunStoreDao.readString(rs, 'run_id'),
      sequence: RunStoreDao.readLong(rs, 'sequence'),
      kind: RunStoreDao.readString(rs, 'kind'),
      payloadJson: RunStoreDao.readString(rs, 'payload_json'),
      createdAt: RunStoreDao.readLong(rs, 'created_at'),
    };
    return event;
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
