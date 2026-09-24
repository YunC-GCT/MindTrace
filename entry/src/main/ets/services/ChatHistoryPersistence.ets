/**
 * ChatHistoryPersistence.ets — 聊天历史文件快照持久化服务(spec 021 ticket-5, #141)
 *
 * 路径: entry/src/main/ets/services/ChatHistoryPersistence.ets
 * 职责: 通过应用私有文件、TaskPool/Worker 与 AtomicFile 保存 ChatSession 快照,并迁移旧 Preferences 历史。
 * 依赖: @ohos.file.fs; @kit.ArkTS(taskpool/worker); @kit.ArkData(preferences); ChatFilesDirSeam。
 *
 * 数据流:
 *   ChatSessionManager → ChatHistoryPersistence → ChatHistoryStorePort
 *   → TaskPool writeChatHistorySnapshotTask → AtomicFile
 *   → Worker fallback(ChatPersistenceWorker) → AtomicFile
 *
 * 边界:
 * - messages 是唯一持久化真源;不保存 reasoningExpanded 等 UI 状态。
 * - 新文件存在但损坏时不回退 Preferences,只返回内存默认会话与可恢复诊断。
 * - filesDir 缺失时阻塞文件持久化,不回退 Preferences 写入。
 * - Production save ownership is this private-file service. Preferences is a
 *   migration read source only; ChatPersistenceCapability is test-side evidence.
 * - AtomicWriteStage describes actual AtomicFile work only. flush() returns
 *   state=idle with no stage when no pending/in-flight write exists.
 * - 诊断只含阶段、错误码、schemaVersion 与时间戳,不含聊天正文/会话名/推理内容/密钥。
 *
 * ArkTS 1.1 strict 适配: 显式 interface/type;无 any/unknown;对象字面量均有类型上下文。
 */

import fileIo from '@ohos.file.fs';
import { MessageEvents, taskpool, worker } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import {
  ChatMsg,
  ChatSession,
  copyChatSessionsForPersistence,
} from '../overlays/AgentFloatWindow/chat/ChatModels';
import { ChatFilesDirSeam } from './ChatFilesDirSeam';
import {
  CHAT_HISTORY_SCHEMA_VERSION,
  CHAT_HISTORY_V1_SCHEMA_VERSION,
} from './ChatHistorySchema';
import { SessionIdPolicy } from './ConversationIdentity';
export { CHAT_HISTORY_SCHEMA_VERSION } from './ChatHistorySchema';

export const STREAM_SAVE_THROTTLE_MS: number = 500;

export type AtomicWriteStage = 'PREPARE' | 'WRITE' | 'COMMIT' | 'VERIFY';
export type PersistenceTransport = 'taskpool' | 'worker';
export type ChatHistoryLoadState = 'default' | 'migrated' | 'migrationFailed' | 'loaded' | 'corrupt' | 'unsupported-version' | 'blocked';
export type ChatHistorySaveState = 'idle' | 'completed' | 'failed' | 'blocked' | 'not-initialized';

export interface ChatHistorySnapshot {
  schemaVersion: number;
  sessions: ChatSession[];
  migratedFrom?: string;
}

export interface ChatHistoryLoadResult {
  sessions: ChatSession[];
  state: ChatHistoryLoadState;
  diagnostic: string;
}

export interface ChatHistorySaveResult {
  success: boolean;
  state: ChatHistorySaveState;
  stage: AtomicWriteStage | undefined;
  transport: PersistenceTransport;
  retryable: boolean;
  diagnostic: string;
}

export interface IdleSaveResult extends ChatHistorySaveResult {
  success: true;
  state: 'idle';
  stage: undefined;
  retryable: false;
}

export interface ChatHistoryStorePort {
  readSnapshot(path: string): Promise<string>;
  writeSnapshot(path: string, sessions: ChatSession[], migratedFrom: string | undefined): Promise<ChatHistorySaveResult>;
  fileExists(path: string): Promise<boolean>;
}

export interface ChatHistoryPreferencesPort {
  readSessions(): string;
}

interface SaveWaiter {
  resolve: (result: ChatHistorySaveResult) => void;
}

interface AtomicWriteTaskResult {
  success: boolean;
  stage: AtomicWriteStage;
  schemaVersion: number;
  diagnostic: string;
}

interface WorkerWriteResponse {
  kind: string;
  success: boolean;
  stage: AtomicWriteStage;
  schemaVersion: number;
  diagnostic: string;
}

interface WorkerWriteRequest {
  kind: string;
  path: string;
  sessions: ChatSession[];
  migratedFrom?: string;
}

const WORKER_SCRIPT: string = 'entry/ets/workers/ChatPersistenceWorker.ets';
const WORKER_WRITE_TIMEOUT_MS: number = 5000;
const MAX_CONSECUTIVE_FAILURES: number = 3;

function defaultSessions(): ChatSession[] {
  const session: ChatSession = {
    id: 's1',
    name: '对话 1',
    messages: [],
  };
  return [session];
}

function isChatMsg(candidate: ChatMsg): boolean {
  const reasoningValid: boolean = candidate.reasoning === undefined || typeof candidate.reasoning === 'string';
  const expansionValid: boolean = candidate.reasoningExpanded === undefined
    || typeof candidate.reasoningExpanded === 'boolean';
  return typeof candidate.id === 'number'
    && (candidate.role === 'user' || candidate.role === 'ai')
    && typeof candidate.content === 'string'
    && typeof candidate.ts === 'number'
    && typeof candidate.streaming === 'boolean'
    && reasoningValid
    && expansionValid;
}

function isChatSession(candidate: ChatSession): boolean {
  if (typeof candidate.id !== 'string' || !SessionIdPolicy.isValid(candidate.id)
    || typeof candidate.name !== 'string') {
    return false;
  }
  if (!Array.isArray(candidate.messages)) {
    return false;
  }
  for (const message of candidate.messages) {
    if (!isChatMsg(message)) {
      return false;
    }
  }
  return true;
}

function parseSessions(raw: string): ChatSession[] | undefined {
  try {
    const sessions: ChatSession[] = JSON.parse(raw);
    if (!Array.isArray(sessions)) {
      return undefined;
    }
    for (const session of sessions) {
      if (!isChatSession(session)) {
        return undefined;
      }
    }
    return sessions.length > 0 ? copyChatSessionsForPersistence(sessions) : undefined;
  } catch (error) {
    return undefined;
  }
}

export interface ChatHistoryDecodeResult {
  snapshot?: ChatHistorySnapshot;
  error: 'none' | 'corrupt' | 'unsupported-version';
  version?: number;
}

export type ChatHistorySnapshotDecoder = (snapshot: ChatHistorySnapshot) => ChatHistoryDecodeResult;

export interface ChatHistoryDecoderRegistration {
  readonly version: number;
  readonly decode: ChatHistorySnapshotDecoder;
}

export class ChatHistoryDecoderCatalog {
  private readonly decoders: Map<number, ChatHistorySnapshotDecoder> =
    new Map<number, ChatHistorySnapshotDecoder>();

  constructor(registrations: ChatHistoryDecoderRegistration[]) {
    for (const registration of registrations) {
      if (!Number.isInteger(registration.version) || registration.version <= 0
        || this.decoders.has(registration.version)) {
        throw new Error('INVALID_CHAT_HISTORY_DECODER_REGISTRATION');
      }
      this.decoders.set(registration.version, registration.decode);
    }
  }

  decode(raw: string): ChatHistoryDecodeResult {
    try {
      const snapshot: ChatHistorySnapshot = JSON.parse(raw);
      if (typeof snapshot.schemaVersion !== 'number' || !Number.isInteger(snapshot.schemaVersion)
        || snapshot.schemaVersion <= 0) {
        return { error: 'corrupt' };
      }
      const decoder: ChatHistorySnapshotDecoder | undefined =
        this.decoders.get(snapshot.schemaVersion);
      if (decoder === undefined) {
        return { error: 'unsupported-version', version: snapshot.schemaVersion };
      }
      return decoder(snapshot);
    } catch (error) {
      return { error: 'corrupt' };
    }
  }
}

function decodeChatHistorySnapshotV1(snapshot: ChatHistorySnapshot): ChatHistoryDecodeResult {
  if (!Array.isArray(snapshot.sessions)) {
    return { error: 'corrupt' };
  }
  const sessions: ChatSession[] = [];
  for (const session of snapshot.sessions) {
    if (!isChatSession(session)) {
      return { error: 'corrupt' };
    }
    sessions.push(session);
  }
  const validated: ChatHistorySnapshot = {
    schemaVersion: CHAT_HISTORY_V1_SCHEMA_VERSION,
    sessions: copyChatSessionsForPersistence(sessions),
  };
  if (snapshot.migratedFrom === 'preferences') {
    validated.migratedFrom = 'preferences';
  }
  return { error: 'none', snapshot: validated };
}

export function createChatHistoryDecoderCatalog(
  additionalRegistrations: ChatHistoryDecoderRegistration[] = [],
): ChatHistoryDecoderCatalog {
  const v1Registration: ChatHistoryDecoderRegistration = {
    version: CHAT_HISTORY_V1_SCHEMA_VERSION,
    decode: decodeChatHistorySnapshotV1,
  };
  const registrations: ChatHistoryDecoderRegistration[] = [v1Registration];
  for (const registration of additionalRegistrations) {
    registrations.push(registration);
  }
  return new ChatHistoryDecoderCatalog(registrations);
}

const CHAT_HISTORY_DECODER_CATALOG: ChatHistoryDecoderCatalog = createChatHistoryDecoderCatalog();

export function decodeChatHistorySnapshot(raw: string): ChatHistoryDecodeResult {
  return CHAT_HISTORY_DECODER_CATALOG.decode(raw);
}

function errorToken(error: Object): string {
  return error instanceof Error ? error.name : 'unknown';
}

function diagnostic(stage: AtomicWriteStage, token: string): string {
  return 'stage=' + stage
    + '; ' + token
    + '; schemaVersion=' + CHAT_HISTORY_SCHEMA_VERSION.toString()
    + '; ts=' + Date.now().toString();
}

@Concurrent
export async function writeChatHistorySnapshotTask(
  path: string,
  sessions: ChatSession[],
  migratedFrom: string,
): Promise<AtomicWriteTaskResult> {
  let stage: AtomicWriteStage = 'PREPARE';
  const schemaVersion: number = CHAT_HISTORY_SCHEMA_VERSION;
  let tmpPath: string = '';
  try {
    const snapshot: ChatHistorySnapshot = {
      schemaVersion: schemaVersion,
      sessions: sessions,
    };
    if (migratedFrom.length > 0) {
      snapshot.migratedFrom = migratedFrom;
    }
    const json: string = JSON.stringify(snapshot);
    const lastSlash: number = path.lastIndexOf('/');
    const directory: string = lastSlash >= 0 ? path.substring(0, lastSlash) : path;
    fileIo.mkdirSync(directory, true);
    tmpPath = path + '.tmp';
    stage = 'WRITE';
    const file: fileIo.File = fileIo.openSync(
      tmpPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    );
    fileIo.writeSync(file.fd, json);
    fileIo.closeSync(file.fd);
    stage = 'COMMIT';
    fileIo.renameSync(tmpPath, path);
    stage = 'VERIFY';
    const formal: string = fileIo.readTextSync(path);
    if (formal !== json) {
      return {
        success: false,
        stage: 'VERIFY',
        schemaVersion: schemaVersion,
        diagnostic: 'stage=VERIFY; error=content-mismatch; schemaVersion='
          + schemaVersion.toString()
          + '; ts=' + Date.now().toString(),
      };
    }
    return {
      success: true,
      stage: 'VERIFY',
      schemaVersion: schemaVersion,
      diagnostic: 'stage=VERIFY; verified=true; schemaVersion='
        + schemaVersion.toString()
        + '; ts=' + Date.now().toString(),
    };
  } catch (error) {
    if (tmpPath.length > 0) {
      try {
        fileIo.unlinkSync(tmpPath);
      } catch (cleanupError) {
      }
    }
    const result: AtomicWriteTaskResult = {
      success: false,
      stage: stage,
      schemaVersion: schemaVersion,
      diagnostic: 'stage=' + stage
        + '; error=atomic-write-failed; schemaVersion=' + CHAT_HISTORY_SCHEMA_VERSION.toString() + '; ts='
        + Date.now().toString(),
    };
    return result;
  }
}

class FileChatHistoryStore implements ChatHistoryStorePort {
  async readSnapshot(path: string): Promise<string> {
    return await fileIo.readText(path);
  }

  async writeSnapshot(
    path: string,
    sessions: ChatSession[],
    migratedFrom: string | undefined,
  ): Promise<ChatHistorySaveResult> {
    try {
      const metadata: string = migratedFrom ?? '';
      const task: taskpool.GenericsTask<[string, ChatSession[], string], AtomicWriteTaskResult> =
        new taskpool.GenericsTask<[string, ChatSession[], string], AtomicWriteTaskResult>(
          writeChatHistorySnapshotTask,
          path,
          sessions,
          metadata,
        );
      const result: AtomicWriteTaskResult = await taskpool.execute<
        [string, ChatSession[], string],
        AtomicWriteTaskResult
      >(task);
      return {
        success: result.success,
        stage: result.stage,
        transport: 'taskpool',
        retryable: !result.success,
        state: result.success ? 'completed' : 'failed',
        diagnostic: 'transport=taskpool; ' + result.diagnostic,
      };
    } catch (error) {
      return await runWorkerWrite(path, sessions, migratedFrom);
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

async function runWorkerWrite(
  path: string,
  sessions: ChatSession[],
  migratedFrom: string | undefined,
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
  private writeInFlight: boolean = false;
  private forcePending: boolean = false;
  private timerId: number | undefined;
  private consecutiveFailures: number = 0;
  private lastFailure: string = '';
  private lastFailedSessions: ChatSession[] | undefined;
  private lastFailedMigratedFrom: string | undefined;
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
            diagnostic: 'state=corrupt; source=file; fallback=memory',
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
    const legacy: ChatSession[] | undefined = parseSessions(this.preferences.readSessions());
    if (legacy === undefined) {
      return {
        sessions: defaultSessions(),
        state: 'default',
        diagnostic: 'state=default; source=empty',
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
    const currentWaiters: SaveWaiter[] = this.waiters;
    this.pending = undefined;
    this.pendingMigratedFrom = undefined;
    this.waiters = [];
    this.writeInFlight = true;
    const force: boolean = this.forcePending;
    this.forcePending = false;
    this.store.writeSnapshot(this.snapshotPath, sessions, metadata).then(
      (result: ChatHistorySaveResult): void => {
        this.writeInFlight = false;
        const reported: ChatHistorySaveResult = this.recordResult(result, sessions, metadata);
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
      const reported: ChatHistorySaveResult = this.recordResult(failed, sessions, metadata);
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
  ): ChatHistorySaveResult {
    if (result.success) {
      this.consecutiveFailures = 0;
      this.lastFailure = '';
      this.lastFailedSessions = undefined;
      this.lastFailedMigratedFrom = undefined;
      if (metadata !== undefined && metadata === this.pendingMigrationFrom) {
        this.pendingMigrationFrom = undefined;
      }
      return result;
    }
    this.consecutiveFailures += 1;
    this.lastFailedSessions = sessions;
    this.lastFailedMigratedFrom = metadata;
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
