import { relationalStore } from '@kit.ArkData';
import { ChatMessageRecord, ChatRole } from '../models/AgentMemoryModels';
import { SessionIdPolicy } from '../services/ConversationIdentity';

export class ChatMessageDao {
  private store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async upsert(record: ChatMessageRecord): Promise<number> {
    SessionIdPolicy.requireValid(record.sessionId);
    const bucket: relationalStore.ValuesBucket = ChatMessageDao.toBucket(record);
    return new Promise<number>((resolve, reject) => {
      this.store.insert(
        'chat_message',
        bucket,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE,
        (err: Error, rowId: number): void => {
          if (err) {
            reject(new Error('ChatMessageDao.upsert failed: ' + err.message));
            return;
          }
          resolve(rowId);
        },
      );
    });
  }

  async queryRecent(sessionId: string, limit: number): Promise<ChatMessageRecord[]> {
    SessionIdPolicy.requireValid(sessionId);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chat_message');
    predicates.equalTo('session_id', sessionId);
    predicates.orderByDesc('sequence');
    predicates.orderByDesc('created_at');
    predicates.orderByDesc('id');

    return new Promise<ChatMessageRecord[]>((resolve, reject) => {
      this.store.query(predicates, ['*'], (err: Error, rs: relationalStore.ResultSet) => {
        if (err) {
          reject(new Error('ChatMessageDao.queryRecent failed: ' + err.message));
          return;
        }
        const records: ChatMessageRecord[] = [];
        let count: number = 0;
        if (rs.goToFirstRow()) {
          do {
            if (count < limit) {
              records.unshift(ChatMessageDao.rowToRecord(rs));
              count += 1;
            }
          } while (count < limit && rs.goToNextRow());
        }
        rs.close();
        resolve(records);
      });
    });
  }

  async queryAll(sessionId: string): Promise<ChatMessageRecord[]> {
    SessionIdPolicy.requireValid(sessionId);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chat_message');
    predicates.equalTo('session_id', sessionId);
    predicates.orderByAsc('sequence');
    predicates.orderByAsc('created_at');
    predicates.orderByAsc('id');

    return new Promise<ChatMessageRecord[]>((resolve, reject) => {
      this.store.query(predicates, ['*'], (err: Error, rs: relationalStore.ResultSet) => {
        if (err) {
          reject(new Error('ChatMessageDao.queryAll failed: ' + err.message));
          return;
        }
        const records: ChatMessageRecord[] = [];
        if (rs.goToFirstRow()) {
          do {
            records.push(ChatMessageDao.rowToRecord(rs));
          } while (rs.goToNextRow());
        }
        rs.close();
        resolve(records);
      });
    });
  }

  async deleteBySession(sessionId: string): Promise<void> {
    SessionIdPolicy.requireValid(sessionId);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chat_message');
    predicates.equalTo('session_id', sessionId);

    return new Promise<void>((resolve, reject) => {
      this.store.delete(predicates, (err: Error, _rows: number) => {
        if (err) {
          reject(new Error('ChatMessageDao.deleteBySession failed: ' + err.message));
          return;
        }
        resolve();
      });
    });
  }

  static rowToRecord(rs: relationalStore.ResultSet): ChatMessageRecord {
    return {
      id: rs.getString(rs.getColumnIndex('id')),
      messageKey: ChatMessageDao.readOptionalString(rs, 'message_key')
        || rs.getString(rs.getColumnIndex('id')),
      sessionId: rs.getString(rs.getColumnIndex('session_id')),
      role: ChatMessageDao.parseRole(rs.getString(rs.getColumnIndex('role'))),
      content: rs.getString(rs.getColumnIndex('content')),
      runId: ChatMessageDao.readOptionalString(rs, 'run_id') || undefined,
      sequence: ChatMessageDao.readOptionalNumber(rs, 'sequence'),
      origin: ChatMessageDao.readOptionalString(rs, 'origin') || 'legacy',
      outcome: ChatMessageDao.readOptionalString(rs, 'outcome') || 'completed',
      createdAt: rs.getLong(rs.getColumnIndex('created_at')),
    };
  }

  private static toBucket(record: ChatMessageRecord): relationalStore.ValuesBucket {
    return {
      'id': record.id,
      'message_key': record.messageKey,
      'session_id': record.sessionId,
      'role': record.role,
      'content': record.content,
      'run_id': record.runId ?? '',
      'sequence': record.sequence,
      'origin': record.origin,
      'outcome': record.outcome,
      'created_at': record.createdAt,
    };
  }

  private static readOptionalString(rs: relationalStore.ResultSet, column: string): string {
    try {
      const index: number = rs.getColumnIndex(column);
      return index >= 0 ? rs.getString(index) : '';
    } catch (error) {
      return '';
    }
  }

  private static readOptionalNumber(rs: relationalStore.ResultSet, column: string): number {
    try {
      const index: number = rs.getColumnIndex(column);
      return index >= 0 ? rs.getLong(index) : 0;
    } catch (error) {
      return 0;
    }
  }

  private static parseRole(value: string): ChatRole {
    if (value === 'system') { return 'system'; }
    if (value === 'assistant') { return 'assistant'; }
    return 'user';
  }
}
