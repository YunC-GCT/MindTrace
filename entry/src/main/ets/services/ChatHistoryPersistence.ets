/**
 * ChatHistoryPersistence.ets — 聊天历史的文件存储与保存生命周期
 *
 * 路径: entry/src/main/ets/services/ChatHistoryPersistence.ets
 * 职责: 文件/偏好端口实现、原子写入、节流保存、失败重试与加载状态
 * 依赖: ./ChatHistoryWire、@kit.CoreFileKit、@kit.ArkData、@kit.ArkTS
 *
 * 数据流:
 *   ChatSession[] → save() → 节流 drain → FileChatHistoryStore → 快照文件
 */
import fileIo from '@ohos.file.fs';
import { MessageEvents, taskpool, worker } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ChatMsg,
  ChatSession,
  ChatMessageOrigin,
  ChatMessageOutcome,
  copyChatSessionsForPersistence,
  normalizeDecodedChatMessage,
  sanitizeNoteContextClarification,
} from '../overlays/AgentFloatWindow/chat/ChatModels';
import type { NoteContextClarification } from 'common';
import {
  AgentRunPart,
  AgentRunPartKind,
  AgentRunPartStatus,
} from '../overlays/AgentFloatWindow/chat/AgentRunModels';
import { ChatFilesDirSeam } from './ChatFilesDirSeam';
import {
  CHAT_HISTORY_SCHEMA_VERSION,
  CHAT_HISTORY_V1_SCHEMA_VERSION,
} from './ChatHistorySchema';
import { ConversationRunIdPolicy, SessionIdPolicy } from 'common';
import type { ChatHistoryClearControl } from './ChatHistoryClearControl';
import { getChatHistoryClearControl } from './ChatHistoryClearControl';
import {
  AtomicWriteTaskResult,
  CHAT_CLEAR_LOG_DOMAIN,
  CHAT_CLEAR_LOG_TAG,
  ChatHistoryDecodeResult,
  ChatHistoryLoadResult,
  ChatHistoryPreferencesPort,
  ChatHistorySaveResult,
  ChatHistoryStorePort,
  IdleSaveResult,
  LegacyParseResult,
  MAX_CONSECUTIVE_FAILURES,
  STREAM_SAVE_THROTTLE_MS,
  SaveWaiter,
  WORKER_SCRIPT,
  WORKER_WRITE_TIMEOUT_MS,
  WorkerWriteRequest,
  WorkerWriteResponse,
  decodeChatHistorySnapshot,
  defaultSessions,
  diagnostic,
  errorToken,
  normalizeHistoryEpoch,
  parseSessions,
  writeChatHistorySnapshotTask,
} from './ChatHistoryWire';

// 对外仍以本模块为入口：wire 的公共类型与工厂在这里转发
export {
  CHAT_CLEAR_LOG_DOMAIN,
  CHAT_CLEAR_LOG_TAG,
  ChatHistoryDecoderCatalog,
  MAX_CONSECUTIVE_FAILURES,
  STREAM_SAVE_THROTTLE_MS,
  WORKER_SCRIPT,
  WORKER_WRITE_TIMEOUT_MS,
  createChatHistoryDecoderCatalog,
  decodeChatHistorySnapshot,
  defaultSessions,
  diagnostic,
  errorToken,
  normalizeHistoryEpoch,
  parseSessions,
  writeChatHistorySnapshotTask,
} from './ChatHistoryWire';
export type {
  AtomicWriteStage,
  AtomicWriteTaskResult,
  ChatHistoryAgentRunPartWire,
  ChatHistoryDecodeResult,
  ChatHistoryDecoderRegistration,
  ChatHistoryLoadResult,
  ChatHistoryLoadState,
  ChatHistoryMessageWire,
  ChatHistoryPreferencesPort,
  ChatHistorySaveResult,
  ChatHistorySaveState,
  ChatHistorySessionWire,
  ChatHistorySnapshot,
  ChatHistorySnapshotDecoder,
  ChatHistorySnapshotWire,
  ChatHistoryStorePort,
  IdleSaveResult,
  LegacyParseResult,
  PersistenceTransport,
  SaveWaiter,
  WorkerWriteRequest,
  WorkerWriteResponse,
} from './ChatHistoryWire';

class FileChatHistoryStore implements ChatHistoryStorePort {
  async readSnapshot(path: string): Promise<string> {
    return await fileIo.readText(path);
  }

  async writeSnapshot(
    path: string,
    sessions: ChatSession[],
    migratedFrom: string | undefined,
    historyEpoch: number = 0,
  ): Promise<ChatHistorySaveResult> {
    try {
      const metadata: string = migratedFrom ?? '';
      const task: taskpool.GenericsTask<[string, ChatSession[], string, number], AtomicWriteTaskResult> =
        new taskpool.GenericsTask<[string, ChatSession[], string, number], AtomicWriteTaskResult>(
          writeChatHistorySnapshotTask,
          path,
          sessions,
          metadata,
          historyEpoch,
        );
      const result: AtomicWriteTaskResult = await taskpool.execute<
        [string, ChatSession[], string, number],
        AtomicWriteTaskResult
      >(task);
      const taskpoolResult: ChatHistorySaveResult = {
        success: result.success,
        stage: result.stage,
        transport: 'taskpool',
        retryable: !result.success,
        state: result.success ? 'completed' : 'failed',
        diagnostic: 'transport=taskpool; ' + result.diagnostic,
      };
      if (taskpoolResult.success) {
        return taskpoolResult;
      }
      return combineFallbackResult(
        taskpoolResult,
        await runWorkerWrite(path, sessions, migratedFrom, historyEpoch),
      );
    } catch (error) {
      const taskpoolFailure: ChatHistorySaveResult = {
        success: false,
        state: 'failed',
        stage: 'PREPARE',
        transport: 'taskpool',
        retryable: true,
        diagnostic: 'transport=taskpool; ' + diagnostic('PREPARE', 'error=taskpool-exception; ' + errorToken(error)),
      };
      return combineFallbackResult(
        taskpoolFailure,
        await runWorkerWrite(path, sessions, migratedFrom, historyEpoch),
      );
    }
  }

  async fileExists(path: string): Promise<boolean> {
    try {
      return await fileIo.access(path);
    } catch (error) {
      return false;
    }
  }
}

export function combineFallbackResult(
  primary: ChatHistorySaveResult,
  fallback: ChatHistorySaveResult,
): ChatHistorySaveResult {
  return {
    success: fallback.success,
    state: fallback.state,
    stage: fallback.stage,
    transport: fallback.transport,
    retryable: primary.retryable || fallback.retryable,
    diagnostic: 'fallback=worker; primary={' + primary.diagnostic + '}; result={' + fallback.diagnostic + '}',
  };
}

async function runWorkerWrite(
  path: string,
  sessions: ChatSession[],
  migratedFrom: string | undefined,
  historyEpoch: number,
): Promise<ChatHistorySaveResult> {
  return await new Promise<ChatHistorySaveResult>((resolve: (value: ChatHistorySaveResult) => void): void => {
    let workerInstance: worker.ThreadWorker | undefined;
    let settled: boolean = false;
    const timeoutId: number = setTimeout((): void => {
      if (settled) {
        return;
      }
      settled = true;
      if (workerInstance !== undefined) {
        workerInstance.terminate();
      }
      resolve({
        success: false,
        state: 'failed',
        stage: 'PREPARE',
        transport: 'worker',
        retryable: true,
        diagnostic: 'transport=worker; ' + diagnostic('PREPARE', 'error=worker-unavailable'),
      });
    }, WORKER_WRITE_TIMEOUT_MS);
    const finish = (result: ChatHistorySaveResult): void => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timeoutId);
      if (workerInstance !== undefined) {
        workerInstance.terminate();
      }
      resolve(result);
    };
    try {
      workerInstance = new worker.ThreadWorker(WORKER_SCRIPT);
      workerInstance.onmessage = (event: MessageEvents): void => {
        const response: WorkerWriteResponse = event.data;
        if (response.kind !== 'write-result') {
          finish({
            success: false,
            state: 'failed',
            stage: 'PREPARE',
            transport: 'worker',
            retryable: false,
            diagnostic: 'transport=worker; ' + diagnostic('PREPARE', 'error=unsupported-response'),
          });
          return;
        }
        finish({
          success: response.success,
          state: response.success ? 'completed' : 'failed',
          stage: response.stage,
          transport: 'worker',
          retryable: !response.success,
          diagnostic: 'transport=worker; ' + response.diagnostic,
        });
      };
      workerInstance.onAllErrors = (): void => {
        finish({
          success: false,
          state: 'failed',
          stage: 'WRITE',
          transport: 'worker',
          retryable: true,
          diagnostic: 'transport=worker; ' + diagnostic('WRITE', 'error=worker-error'),
        });
      };
      const request: WorkerWriteRequest = {
        kind: 'write',
        path: path,
        sessions: sessions,
        historyEpoch: historyEpoch,
      };
      if (migratedFrom !== undefined) {
        request.migratedFrom = migratedFrom;
      }
      workerInstance.postMessage(request);
    } catch (error) {
      finish({
        success: false,
        state: 'failed',
        stage: 'PREPARE',
        transport: 'worker',
        retryable: true,
        diagnostic: 'transport=worker; ' + diagnostic('PREPARE', 'error=worker-unavailable'),
      });
    }
  });
}

export class ChatHistoryPersistence {
  private readonly store: ChatHistoryStorePort;
  private readonly preferences: ChatHistoryPreferencesPort;
  private readonly snapshotPath: string;
  private pending: ChatSession[] | undefined;
  private pendingMigratedFrom: string | undefined;
  private pendingHistoryEpoch: number = 0;
  private writeInFlight: boolean = false;
  private forcePending: boolean = false;
  private timerId: number | undefined;
  private consecutiveFailures: number = 0;
  private lastFailure: string = '';
  private lastFailedSessions: ChatSession[] | undefined;
  private lastFailedMigratedFrom: string | undefined;
  private lastFailedHistoryEpoch: number = 0;
  private pendingMigrationFrom: string | undefined;
  private waiters: SaveWaiter[] = [];
  private flushWaiters: SaveWaiter[] = [];

  constructor(store: ChatHistoryStorePort, preferencesPort: ChatHistoryPreferencesPort, snapshotPath: string) {
    this.store = store;
    this.preferences = preferencesPort;
    this.snapshotPath = snapshotPath;
  }

  async load(): Promise<ChatHistoryLoadResult> {
    if (this.snapshotPath.length === 0) {
      return {
        sessions: defaultSessions(),
        state: 'blocked',
        diagnostic: 'state=blocked; reason=filesDir-unavailable',
      };
    }
    if (await this.store.fileExists(this.snapshotPath)) {
      try {
        const raw: string = await this.store.readSnapshot(this.snapshotPath);
        const decoded: ChatHistoryDecodeResult = decodeChatHistorySnapshot(raw);
        if (decoded.error === 'unsupported-version') {
          return {
            sessions: defaultSessions(),
            state: 'unsupported-version',
            diagnostic: 'state=unsupported-version; source=file; version=' + (decoded.version ?? 0).toString(),
          };
        }
        if (decoded.snapshot === undefined) {
          return {
            sessions: defaultSessions(),
            state: 'corrupt',
            diagnostic: 'state=corrupt; source=file; fallback=memory; ' + decoded.diagnostic,
          };
        }
        const snapshotEpoch: number = normalizeHistoryEpoch(decoded.snapshot.historyEpoch);
        const clearControl: ChatHistoryClearControl | undefined = getChatHistoryClearControl();
        if (clearControl !== undefined && clearControl.isSnapshotBlocked(snapshotEpoch)) {
          hilog.debug(CHAT_CLEAR_LOG_DOMAIN, CHAT_CLEAR_LOG_TAG,
            'code=CHAT_HISTORY_SNAPSHOT_BLOCKED epoch=%{public}d', snapshotEpoch);
          return {
            sessions: defaultSessions(),
            state: 'blocked',
            diagnostic: 'state=blocked; source=file; code=CHAT_HISTORY_SNAPSHOT_BLOCKED; epoch='
              + snapshotEpoch.toString(),
          };
        }
        return {
          sessions: decoded.snapshot.sessions,
          state: 'loaded',
          diagnostic: 'state=loaded; source=file; schemaVersion=' + decoded.snapshot.schemaVersion.toString(),
        };
      } catch (error) {
        return {
          sessions: defaultSessions(),
          state: 'corrupt',
          diagnostic: 'state=corrupt; source=file; fallback=memory; error=' + errorToken(error),
        };
      }
    }
    const legacyResult: LegacyParseResult = parseSessions(this.preferences.readSessions());
    const legacy: ChatSession[] | undefined = legacyResult.sessions;
    if (legacy === undefined) {
      return {
        sessions: defaultSessions(),
        state: 'corrupt',
        diagnostic: 'state=corrupt; source=preferences; ' + legacyResult.diagnostic,
      };
    }
    const writeResult: ChatHistorySaveResult = await this.store.writeSnapshot(this.snapshotPath, legacy, 'preferences');
    if (!writeResult.success) {
      this.consecutiveFailures += 1;
      this.lastFailure = writeResult.diagnostic;
      this.lastFailedSessions = copyChatSessionsForPersistence(legacy);
      this.lastFailedMigratedFrom = 'preferences';
      this.pendingMigrationFrom = 'preferences';
      return {
        sessions: legacy,
        state: 'migrationFailed',
        diagnostic: 'state=migrationFailed; retry=true; ' + writeResult.diagnostic,
      };
    }
    return {
      sessions: legacy,
      state: 'migrated',
      diagnostic: 'state=migrated; migratedFrom=preferences; schemaVersion=' + CHAT_HISTORY_SCHEMA_VERSION.toString(),
    };
  }

  save(sessions: ChatSession[], force: boolean = false): Promise<ChatHistorySaveResult> {
    if (this.snapshotPath.length === 0) {
      return Promise.resolve(ChatHistoryPersistence.blockedSaveResult());
    }
    this.pending = copyChatSessionsForPersistence(sessions);
    this.pendingMigratedFrom = this.pendingMigrationFrom;
    this.pendingHistoryEpoch = ChatHistoryPersistence.currentHistoryEpoch();
    if (force) {
      this.forcePending = true;
      this.clearTimer();
    } else if (this.timerId === undefined) {
      this.timerId = setTimeout((): void => {
        this.timerId = undefined;
        this.drain();
      }, STREAM_SAVE_THROTTLE_MS);
    }
    const result: Promise<ChatHistorySaveResult> = new Promise<ChatHistorySaveResult>(
      (resolve: (value: ChatHistorySaveResult) => void): void => {
        this.waiters.push({ resolve: resolve });
      },
    );
    if (force) {
      this.drain();
    }
    return result;
  }

  flush(): Promise<ChatHistorySaveResult> {
    if (this.snapshotPath.length === 0) {
      return Promise.resolve(ChatHistoryPersistence.blockedSaveResult());
    }
    this.forcePending = true;
    this.clearTimer();
    if (!this.writeInFlight && this.pending === undefined) {
      this.forcePending = false;
      const idle: IdleSaveResult = {
        success: true,
        state: 'idle',
        stage: undefined,
        transport: 'taskpool',
        retryable: false,
        diagnostic: 'state=idle; schemaVersion=' + CHAT_HISTORY_SCHEMA_VERSION.toString()
          + '; ts=' + Date.now().toString(),
      };
      return Promise.resolve(idle);
    }
    if (this.writeInFlight) {
      return new Promise<ChatHistorySaveResult>((resolve: (value: ChatHistorySaveResult) => void): void => {
        this.flushWaiters.push({ resolve: resolve });
      });
    }
    const result: Promise<ChatHistorySaveResult> = new Promise<ChatHistorySaveResult>(
      (resolve: (value: ChatHistorySaveResult) => void): void => {
        this.flushWaiters.push({ resolve: resolve });
      },
    );
    this.drain();
    return result;
  }

  retry(): Promise<ChatHistorySaveResult> {
    if (this.lastFailedSessions !== undefined && this.pending === undefined) {
      this.pending = copyChatSessionsForPersistence(this.lastFailedSessions);
      this.pendingMigratedFrom = this.lastFailedMigratedFrom;
      this.pendingHistoryEpoch = this.lastFailedHistoryEpoch;
    }
    this.forcePending = true;
    this.clearTimer();
    return this.flush();
  }

  failureCount(): number {
    return this.consecutiveFailures;
  }

  lastFailureDiagnostic(): string {
    return this.lastFailure;
  }

  private drain(): void {
    if (this.writeInFlight || this.pending === undefined) {
      return;
    }
    const sessions: ChatSession[] = this.pending;
    const metadata: string | undefined = this.pendingMigratedFrom;
    const historyEpoch: number = this.pendingHistoryEpoch;
    const currentWaiters: SaveWaiter[] = this.waiters;
    this.pending = undefined;
    this.pendingMigratedFrom = undefined;
    this.pendingHistoryEpoch = 0;
    this.waiters = [];
    this.writeInFlight = true;
    const force: boolean = this.forcePending;
    this.forcePending = false;
    this.store.writeSnapshot(this.snapshotPath, sessions, metadata, historyEpoch).then(
      (result: ChatHistorySaveResult): void => {
        this.writeInFlight = false;
        const reported: ChatHistorySaveResult = this.recordResult(result, sessions, metadata, historyEpoch);
        for (const waiter of currentWaiters) {
          waiter.resolve(reported);
        }
        if (this.pending === undefined) {
          const completedFlushWaiters: SaveWaiter[] = this.flushWaiters;
          this.flushWaiters = [];
          for (const waiter of completedFlushWaiters) {
            waiter.resolve(reported);
          }
        }
        this.afterDrain(force);
      },
    ).catch((error: Error): void => {
      const failed: ChatHistorySaveResult = {
        success: false,
        state: 'failed',
        stage: 'WRITE',
        transport: 'taskpool',
        retryable: true,
        diagnostic: diagnostic('WRITE', 'error=' + errorToken(error)),
      };
      this.writeInFlight = false;
      const reported: ChatHistorySaveResult = this.recordResult(failed, sessions, metadata, historyEpoch);
      for (const waiter of currentWaiters) {
        waiter.resolve(reported);
      }
      if (this.pending === undefined) {
        const completedFlushWaiters: SaveWaiter[] = this.flushWaiters;
        this.flushWaiters = [];
        for (const waiter of completedFlushWaiters) {
          waiter.resolve(reported);
        }
      }
      this.afterDrain(force);
    });
  }

  private afterDrain(force: boolean): void {
    if (this.pending !== undefined) {
      if (this.forcePending || force) {
        this.drain();
      } else if (this.timerId === undefined) {
        this.timerId = setTimeout((): void => {
          this.timerId = undefined;
          this.drain();
        }, STREAM_SAVE_THROTTLE_MS);
      }
      return;
    }
    this.forcePending = false;
  }

  private recordResult(
    result: ChatHistorySaveResult,
    sessions: ChatSession[],
    metadata: string | undefined,
    historyEpoch: number,
  ): ChatHistorySaveResult {
    if (result.success) {
      this.consecutiveFailures = 0;
      this.lastFailure = '';
      this.lastFailedSessions = undefined;
      this.lastFailedMigratedFrom = undefined;
      this.lastFailedHistoryEpoch = 0;
      if (metadata !== undefined && metadata === this.pendingMigrationFrom) {
        this.pendingMigrationFrom = undefined;
      }
      return result;
    }
    this.consecutiveFailures += 1;
    this.lastFailedSessions = sessions;
    this.lastFailedMigratedFrom = metadata;
    this.lastFailedHistoryEpoch = historyEpoch;
    const recovery: string = this.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES ? '; recovery=required' : '';
    this.lastFailure = result.diagnostic + recovery;
    return {
      success: false,
      state: 'failed',
      stage: result.stage,
      transport: result.transport,
      retryable: result.retryable,
      diagnostic: this.lastFailure,
    };
  }

  private clearTimer(): void {
    if (this.timerId !== undefined) {
      clearTimeout(this.timerId);
      this.timerId = undefined;
    }
  }

  private static currentHistoryEpoch(): number {
    const control: ChatHistoryClearControl | undefined = getChatHistoryClearControl();
    if (control === undefined) {
      return 0;
    }
    try {
      return normalizeHistoryEpoch(control.getState().historyEpoch);
    } catch (error) {
      return 0;
    }
  }

  private static blockedSaveResult(): ChatHistorySaveResult {
    const result: ChatHistorySaveResult = {
      success: false,
      state: 'blocked',
      stage: 'PREPARE',
      transport: 'taskpool',
      retryable: true,
      diagnostic: diagnostic('PREPARE', 'reason=filesDir-unavailable'),
    };
    return result;
  }
}

export class PreferencesChatHistoryPort implements ChatHistoryPreferencesPort {
  private readonly preferences: preferences.Preferences;

  constructor(preferencesValue: preferences.Preferences) {
    this.preferences = preferencesValue;
  }

  readSessions(): string {
    const value: preferences.ValueType = this.preferences.getSync('sessions', '');
    return typeof value === 'string' ? value : '';
  }
}

export function createFileChatHistoryStore(): ChatHistoryStorePort {
  return new FileChatHistoryStore();
}

export function chatSnapshotPath(filesDir: string): string {
  return filesDir.length === 0 ? '' : ChatFilesDirSeam.snapshotFile(filesDir);
}
