/**
 * SessionDeletionCoordinator.ets - Idempotent cross-store conversation session deletion.
 *
 * Path: entry/src/main/ets/services/SessionDeletionCoordinator.ets
 * Responsibility: Persist delete tombstones, commit file history first, then clean session-owned RDB data.
 * Dependencies: @ohos.file.fs, common DatabaseHelper, ChatMessage/AgentMemory/NoteGeneration repositories.
 *
 * Data flow:
 *   AgentFloatWindow -> delete/replay -> file snapshot + tombstone -> one RDB transaction.
 *
 * ArkTS 1.1 strict adaptation:
 *   - Explicit result and callback types; no structural object indexing or untyped literals.
 */
import fileIo from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper } from 'common';
import { ConversationSessionSnapshot } from '../models/ConversationSnapshotModels';
import { ChatHistorySaveResult } from './ChatHistoryPersistence';
import { SessionIdPolicy } from './ConversationIdentity';
import { NoteGenerationRepository } from '../database/NoteGenerationRepository';

export type SessionDeletionState = 'completed' | 'cleanup-pending' | 'failed-before-commit';

export interface SessionDeletionResult {
  state: SessionDeletionState;
  diagnostic: string;
}

export type SessionSnapshotCommit = (sessions: ConversationSessionSnapshot[]) => Promise<ChatHistorySaveResult>;
export type SessionQuiesce = (sessionId: string) => Promise<void>;

export interface SessionDeletionOperations {
  readTombstones(): Promise<string[]>;
  writeTombstones(sessionIds: string[]): Promise<void>;
  cleanupRdb(sessionId: string): Promise<void>;
}

export class SessionDeletionCoordinator {
  private readonly context: common.UIAbilityContext | null;
  private readonly tombstonePath: string;
  private readonly commitSnapshot: SessionSnapshotCommit;
  private readonly quiesce: SessionQuiesce;
  private readonly operations: SessionDeletionOperations | null;

  constructor(
    context: common.UIAbilityContext | null,
    tombstonePath: string,
    commitSnapshot: SessionSnapshotCommit,
    quiesce: SessionQuiesce,
    operations?: SessionDeletionOperations,
  ) {
    this.context = context;
    this.tombstonePath = tombstonePath;
    this.commitSnapshot = commitSnapshot;
    this.quiesce = quiesce;
    this.operations = operations ?? null;
  }

  async deleteSession(sessionId: string, remainingSessions: ConversationSessionSnapshot[]): Promise<SessionDeletionResult> {
    SessionIdPolicy.requireValid(sessionId);
    try {
      await this.quiesce(sessionId);
      const pending: string[] = await this.readTombstones();
      if (!pending.includes(sessionId)) { pending.push(sessionId); }
      await this.writeTombstones(pending);
    } catch (error) {
      return { state: 'failed-before-commit', diagnostic: 'code=SESSION_DELETE_PREPARE_FAILED' };
    }
    let saved: ChatHistorySaveResult;
    try {
      saved = await this.commitSnapshot(remainingSessions);
    } catch (error) {
      await this.bestEffortRemoveTombstone(sessionId);
      return { state: 'failed-before-commit', diagnostic: 'code=SESSION_SNAPSHOT_COMMIT_FAILED' };
    }
    if (!saved.success) {
      await this.bestEffortRemoveTombstone(sessionId);
      return { state: 'failed-before-commit', diagnostic: 'code=SESSION_SNAPSHOT_COMMIT_FAILED' };
    }
    try {
      await this.cleanupRdb(sessionId);
      await this.removeTombstone(sessionId);
      return { state: 'completed', diagnostic: 'code=SESSION_DELETE_COMPLETED' };
    } catch (error) {
      return { state: 'cleanup-pending', diagnostic: 'code=SESSION_RDB_CLEANUP_PENDING' };
    }
  }

  async replay(currentSessions: ConversationSessionSnapshot[]): Promise<string[]> {
    const pending: string[] = await this.readTombstones();
    const stillPending: string[] = [];
    for (const sessionId of pending) {
      const visible: boolean = currentSessions.some((session: ConversationSessionSnapshot): boolean => session.id === sessionId);
      // A visible target means the file snapshot commit did not complete.
      // Keep the tombstone as the recovery credential; deleting it here would
      // strand the session-owned RDB rows permanently.
      if (visible) {
        stillPending.push(sessionId);
        continue;
      }
      try {
        await this.quiesce(sessionId);
        await this.cleanupRdb(sessionId);
      } catch (error) {
        stillPending.push(sessionId);
      }
    }
    try { await this.writeTombstones(stillPending); } catch (error) { return pending; }
    return stillPending;
  }

  private async cleanupRdb(sessionId: string): Promise<void> {
    if (this.operations !== null) { return await this.operations.cleanupRdb(sessionId); }
    if (this.context === null) { throw new Error('SESSION_DELETE_CONTEXT_REQUIRED'); }
    let store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) { store = await DatabaseHelper.init(this.context); }
    const generationRepository: NoteGenerationRepository = new NoteGenerationRepository(store);
    const runs = await generationRepository.listIncompleteByOriginSession(sessionId);
    const transaction: relationalStore.Transaction = await store.createTransaction();
    try {
      const chat = new relationalStore.RdbPredicates('chat_message');
      chat.equalTo('session_id', sessionId);
      await transaction.delete(chat);
      const memory = new relationalStore.RdbPredicates('agent_memory');
      memory.equalTo('session_id', sessionId);
      await transaction.delete(memory);
      for (const run of runs) {
        await this.deleteGenerationRun(transaction, run.id);
      }
      await transaction.commit();
    } catch (error) {
      try { await transaction.rollback(); } catch (rollbackError) {}
      throw new Error('SESSION_RDB_CLEANUP_FAILED');
    }
  }

  private async deleteGenerationRun(transaction: relationalStore.Transaction, runId: string): Promise<void> {
    const source = new relationalStore.RdbPredicates('note_generation_source');
    source.equalTo('run_id', runId);
    await transaction.delete(source);
    const checkpoint = new relationalStore.RdbPredicates('note_generation_checkpoint');
    checkpoint.equalTo('run_id', runId);
    await transaction.delete(checkpoint);
    const log = new relationalStore.RdbPredicates('note_generation_log');
    log.equalTo('run_id', runId);
    await transaction.delete(log);
    const run = new relationalStore.RdbPredicates('note_generation_run');
    run.equalTo('id', runId);
    await transaction.delete(run);
  }

  private async readTombstones(): Promise<string[]> {
    if (this.operations !== null) { return await this.operations.readTombstones(); }
    if (this.tombstonePath.length === 0) { return []; }
    try {
      if (!(await fileIo.access(this.tombstonePath))) { return []; }
      const parsed: string[] = JSON.parse(await fileIo.readText(this.tombstonePath)) as string[];
      if (!Array.isArray(parsed)) { return []; }
      const result: string[] = [];
      for (const sessionId of parsed) {
        if (typeof sessionId === 'string' && SessionIdPolicy.isValid(sessionId) && !result.includes(sessionId)) {
          result.push(sessionId);
        }
      }
      return result;
    } catch (error) {
      return [];
    }
  }

  private async removeTombstone(sessionId: string): Promise<void> {
    const pending: string[] = await this.readTombstones();
    await this.writeTombstones(pending.filter((candidate: string): boolean => candidate !== sessionId));
  }

  private async bestEffortRemoveTombstone(sessionId: string): Promise<void> {
    try { await this.removeTombstone(sessionId); } catch (error) {}
  }

  private async writeTombstones(sessionIds: string[]): Promise<void> {
    if (this.operations !== null) { return await this.operations.writeTombstones(sessionIds); }
    if (this.tombstonePath.length === 0) { throw new Error('SESSION_TOMBSTONE_PATH_UNAVAILABLE'); }
    const slash: number = this.tombstonePath.lastIndexOf('/');
    const directory: string = slash >= 0 ? this.tombstonePath.substring(0, slash) : this.tombstonePath;
    fileIo.mkdirSync(directory, true);
    const temporary: string = this.tombstonePath + '.tmp';
    const file: fileIo.File = fileIo.openSync(
      temporary,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    );
    fileIo.writeSync(file.fd, JSON.stringify(sessionIds));
    fileIo.closeSync(file.fd);
    fileIo.renameSync(temporary, this.tombstonePath);
  }
}
