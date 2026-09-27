import { relationalStore } from '@kit.ArkData';
import { AgentMemoryRecord, AgentMemoryType } from '../models/AgentMemoryModels';
import { ProfileScopePolicy, SessionIdPolicy } from '../services/ConversationIdentity';

export class AgentMemoryDao {
  private store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async insert(record: AgentMemoryRecord): Promise<number> {
    if (record.type === 'profile') {
      ProfileScopePolicy.requireValid(record.sessionId);
    } else {
      SessionIdPolicy.requireValid(record.sessionId);
    }
    const bucket: relationalStore.ValuesBucket = AgentMemoryDao.toBucket(record);
    return new Promise<number>((resolve, reject) => {
      this.store.insert('agent_memory', bucket, (err: Error, rowId: number) => {
        if (err) {
          reject(new Error('AgentMemoryDao.insert failed: ' + err.message));
          return;
        }
        resolve(rowId);
      });
    });
  }

  async queryPendingNotes(sessionId: string): Promise<AgentMemoryRecord[]> {
    SessionIdPolicy.requireValid(sessionId);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('agent_memory');
    predicates.equalTo('session_id', sessionId);
    predicates.equalTo('type', 'pending_note');
    predicates.equalTo('used', 0);
    predicates.orderByAsc('created_at');

    return new Promise<AgentMemoryRecord[]>((resolve, reject) => {
      this.store.query(predicates, ['*'], (err: Error, rs: relationalStore.ResultSet) => {
        if (err) {
          reject(new Error('AgentMemoryDao.queryPendingNotes failed: ' + err.message));
          return;
        }
        const records: AgentMemoryRecord[] = [];
        if (rs.goToFirstRow()) {
          do {
            records.push(AgentMemoryDao.rowToRecord(rs));
          } while (rs.goToNextRow());
        }
        rs.close();
        resolve(records);
      });
    });
  }

  async queryLatestSummary(sessionId: string): Promise<AgentMemoryRecord | null> {
    SessionIdPolicy.requireValid(sessionId);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('agent_memory');
    predicates.equalTo('session_id', sessionId);
    predicates.equalTo('type', 'summary');
    predicates.orderByDesc('created_at');

    return new Promise<AgentMemoryRecord | null>((resolve, reject) => {
      this.store.query(predicates, ['*'], (err: Error, rs: relationalStore.ResultSet) => {
        if (err) {
          reject(new Error('AgentMemoryDao.queryLatestSummary failed: ' + err.message));
          return;
        }
        if (rs.goToFirstRow()) {
          const record: AgentMemoryRecord = AgentMemoryDao.rowToRecord(rs);
          rs.close();
          resolve(record);
          return;
        }
        rs.close();
        resolve(null);
      });
    });
  }

  async queryLatestProfile(sessionId: string, source: string): Promise<AgentMemoryRecord | null> {
    ProfileScopePolicy.requireValid(sessionId);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('agent_memory');
    predicates.equalTo('session_id', sessionId);
    predicates.equalTo('type', 'profile');
    predicates.equalTo('source', source);
    predicates.orderByDesc('created_at');

    return new Promise<AgentMemoryRecord | null>((resolve, reject) => {
      this.store.query(predicates, ['*'], (err: Error, rs: relationalStore.ResultSet) => {
        if (err) {
          reject(new Error('AgentMemoryDao.queryLatestProfile failed: ' + err.message));
          return;
        }
        if (rs.goToFirstRow()) {
          const record: AgentMemoryRecord = AgentMemoryDao.rowToRecord(rs);
          rs.close();
          resolve(record);
          return;
        }
        rs.close();
        resolve(null);
      });
    });
  }

  async markPendingUsedByIds(sourceIds: string[]): Promise<void> {
    if (sourceIds.length === 0) {
      return;
    }
    const bucket: relationalStore.ValuesBucket = {
      'used': 1,
      'updated_at': Date.now(),
    };
    for (const sourceId of sourceIds) {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('agent_memory');
      predicates.equalTo('id', sourceId);
      predicates.equalTo('type', 'pending_note');
      predicates.equalTo('used', 0);
      await new Promise<void>((resolve, reject) => {
        this.store.update(bucket, predicates, (err: Error, _rows: number): void => {
          if (err) {
            reject(new Error('AgentMemoryDao.markPendingUsedByIds failed: ' + err.message));
            return;
          }
          resolve();
        });
      });
    }
  }

  async deleteBySession(sessionId: string): Promise<void> {
    SessionIdPolicy.requireValid(sessionId);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('agent_memory');
    predicates.equalTo('session_id', sessionId);

    return new Promise<void>((resolve, reject) => {
      this.store.delete(predicates, (err: Error, _rows: number) => {
        if (err) {
          reject(new Error('AgentMemoryDao.deleteBySession failed: ' + err.message));
          return;
        }
        resolve();
      });
    });
  }

  static rowToRecord(rs: relationalStore.ResultSet): AgentMemoryRecord {
    return {
      id: rs.getString(rs.getColumnIndex('id')),
      sessionId: rs.getString(rs.getColumnIndex('session_id')),
      type: AgentMemoryDao.parseType(rs.getString(rs.getColumnIndex('type'))),
      content: rs.getString(rs.getColumnIndex('content')),
      source: rs.getString(rs.getColumnIndex('source')),
      used: rs.getLong(rs.getColumnIndex('used')),
      createdAt: rs.getLong(rs.getColumnIndex('created_at')),
      updatedAt: rs.getLong(rs.getColumnIndex('updated_at')),
    };
  }

  private static toBucket(record: AgentMemoryRecord): relationalStore.ValuesBucket {
    return {
      'id': record.id,
      'session_id': record.sessionId,
      'type': record.type,
      'content': record.content,
      'source': record.source,
      'used': record.used,
      'created_at': record.createdAt,
      'updated_at': record.updatedAt,
    };
  }

  private static parseType(value: string): AgentMemoryType {
    if (value === 'summary') { return 'summary'; }
    if (value === 'ocr_result') { return 'ocr_result'; }
    if (value === 'profile') { return 'profile'; }
    return 'pending_note';
  }
}
