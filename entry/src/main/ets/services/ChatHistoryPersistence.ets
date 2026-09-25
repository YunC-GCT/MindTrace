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
 * - 新文件存在但损坏时不回退 Preferences,只返回空内存会话与可恢复诊断。
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
  ChatMessageOrigin,
  ChatMessageOutcome,
  copyChatSessionsForPersistence,
  normalizeDecodedChatMessage,
} from '../overlays/AgentFloatWindow/chat/ChatModels';
import { ChatFilesDirSeam } from './ChatFilesDirSeam';
import {
  CHAT_HISTORY_SCHEMA_VERSION,
  CHAT_HISTORY_V1_SCHEMA_VERSION,
} from './ChatHistorySchema';
import { ConversationRunIdPolicy, SessionIdPolicy } from './ConversationIdentity';
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

export interface ChatHistoryMessageWire {
  id: number;
  role: string;
  content: string;
  ts: number;
  streaming: boolean;
  reasoning?: string;
  reasoningExpanded?: boolean;
  origin?: string;
  outcome?: string;
  runId?: string;
  sequence?: number;
  messageKey?: string;
}

export interface ChatHistorySessionWire {
  id: string;
  name: string;
  messages: ChatHistoryMessageWire[];
}

export interface ChatHistorySnapshotWire {
  schemaVersion: number;
  sessions: ChatHistorySessionWire[];
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
const MAX_SNAPSHOT_BYTES: number = 16 * 1024 * 1024;
const MAX_SESSION_COUNT: number = 200;
const MAX_MESSAGES_PER_SESSION: number = 5000;
const MAX_SESSION_NAME_LENGTH: number = 80;
const MAX_MESSAGE_TEXT_LENGTH: number = 262144;
const MAX_MESSAGE_KEY_LENGTH: number = 256;

function defaultSessions(): ChatSession[] { return []; }

function decodeDiagnostic(stage: string, code: string, path: string): string {
  return 'stage=' + stage + ';code=' + code + ';path=' + path;
}

function corrupt(code: string, path: string, stage: string = 'validate'): ChatHistoryDecodeResult {
  return { error: 'corrupt', diagnostic: decodeDiagnostic(stage, code, path) };
}

function hasForbiddenIdentityControl(value: string): boolean {
  let index: number = 0;
  while (index < value.length) {
    const code: number = value.charCodeAt(index);
    if (code < 32 || code === 127) { return true; }
    index += 1;
  }
  return false;
}

function hasForbiddenMessageControl(value: string): boolean {
  let index: number = 0;
  while (index < value.length) {
    const code: number = value.charCodeAt(index);
    if ((code < 32 && code !== 9 && code !== 10 && code !== 13) || code === 127) { return true; }
    index += 1;
  }
  return false;
}

function utf8ByteLengthAtMost(value: string, limit: number): number {
  let bytes: number = 0;
  let index: number = 0;
  while (index < value.length && bytes <= limit) {
    const code: number = value.charCodeAt(index);
    if (code < 128) { bytes += 1; }
    else if (code < 2048) { bytes += 2; }
    else if (code >= 55296 && code <= 56319 && index + 1 < value.length
      && value.charCodeAt(index + 1) >= 56320 && value.charCodeAt(index + 1) <= 57343) {
      bytes += 4;
      index += 1;
    } else { bytes += 3; }
    index += 1;
  }
  return bytes;
}

function isOrigin(value: string): boolean {
  return value === 'chat' || value === 'image' || value === 'note-regeneration'
    || value === 'system' || value === 'legacy';
}

function isOutcome(value: string): boolean {
  return value === 'completed' || value === 'interrupted' || value === 'cancelled' || value === 'failed';
}

interface SessionValidationResult {
  sessions?: ChatSession[];
  diagnostic: string;
}

interface LegacyParseResult {
  sessions?: ChatSession[];
  diagnostic: string;
}

interface MessageValidationResult {
  message?: ChatMsg;
  diagnostic: string;
}

function validateMessage(
  message: ChatHistoryMessageWire,
  path: string,
  legacyInput: boolean,
): MessageValidationResult {
  if (message === null || typeof message !== 'object') {
    return { diagnostic: decodeDiagnostic('validate', 'MESSAGE_NOT_OBJECT', path) };
  }
  if (typeof message.id !== 'number' || !Number.isSafeInteger(message.id) || message.id <= 0) {
    return { diagnostic: decodeDiagnostic('validate', 'INVALID_MESSAGE_ID', path + '.id') };
  }
  if (message.role !== 'user' && message.role !== 'ai') {
    return { diagnostic: decodeDiagnostic('validate', 'INVALID_ROLE', path + '.role') };
  }
  if (typeof message.content !== 'string' || message.content.length > MAX_MESSAGE_TEXT_LENGTH) {
    return { diagnostic: decodeDiagnostic('validate', 'INVALID_CONTENT', path + '.content') };
  }
  if (hasForbiddenMessageControl(message.content)) {
    return { diagnostic: decodeDiagnostic('validate', 'INVALID_MESSAGE_CONTROL', path + '.content') };
  }
  if (typeof message.ts !== 'number' || !Number.isFinite(message.ts) || message.ts < 0) {
    return { diagnostic: decodeDiagnostic('validate', 'INVALID_TIMESTAMP', path + '.ts') };
  }
  if (typeof message.streaming !== 'boolean') {
    return { diagnostic: decodeDiagnostic('validate', 'INVALID_STREAMING', path + '.streaming') };
  }
  if (message.reasoning !== undefined && (typeof message.reasoning !== 'string'
    || message.reasoning.length > MAX_MESSAGE_TEXT_LENGTH
    || hasForbiddenMessageControl(message.reasoning))) {
    return { diagnostic: decodeDiagnostic('validate', 'INVALID_REASONING', path + '.reasoning') };
  }
  if (!legacyInput && message.reasoningExpanded !== undefined) {
    return { diagnostic: decodeDiagnostic('validate', 'UI_STATE_IN_SNAPSHOT', path + '.reasoningExpanded') };
  }
  if (message.origin !== undefined && !isOrigin(message.origin)) {
    return { diagnostic: decodeDiagnostic('validate', 'INVALID_ORIGIN', path + '.origin') };
  }
  if (message.outcome !== undefined && !isOutcome(message.outcome)) {
    return { diagnostic: decodeDiagnostic('validate', 'INVALID_OUTCOME', path + '.outcome') };
  }
  if (message.runId !== undefined && (typeof message.runId !== 'string'
    || !ConversationRunIdPolicy.isValid(message.runId) || hasForbiddenIdentityControl(message.runId))) {
    return { diagnostic: decodeDiagnostic('validate', 'INVALID_RUN_ID', path + '.runId') };
  }
  if (message.sequence !== undefined && (typeof message.sequence !== 'number'
    || !Number.isSafeInteger(message.sequence) || message.sequence <= 0)) {
    return { diagnostic: decodeDiagnostic('validate', 'INVALID_SEQUENCE', path + '.sequence') };
  }
  if (message.messageKey !== undefined && (typeof message.messageKey !== 'string'
    || message.messageKey.length === 0 || message.messageKey.length > MAX_MESSAGE_KEY_LENGTH
    || hasForbiddenIdentityControl(message.messageKey))) {
    return { diagnostic: decodeDiagnostic('validate', 'INVALID_MESSAGE_KEY', path + '.messageKey') };
  }
  if (message.streaming && message.outcome !== undefined) {
    return { diagnostic: decodeDiagnostic('validate', 'STREAMING_WITH_TERMINAL_OUTCOME', path + '.outcome') };
  }
  if (message.role === 'ai' && message.origin !== undefined && message.origin !== 'legacy') {
    if (message.runId === undefined) {
      return { diagnostic: decodeDiagnostic('validate', 'AI_MESSAGE_RUN_ID_REQUIRED', path + '.runId') };
    }
    if (!message.streaming && message.outcome === undefined) {
      return { diagnostic: decodeDiagnostic('validate', 'AI_MESSAGE_OUTCOME_REQUIRED', path + '.outcome') };
    }
  }
  const trusted: ChatMsg = {
    id: message.id,
    role: message.role,
    content: message.content,
    ts: message.ts,
    streaming: message.streaming,
  };
  if (message.reasoning !== undefined) { trusted.reasoning = message.reasoning; }
  if (legacyInput && message.reasoningExpanded !== undefined) {
    trusted.reasoningExpanded = message.reasoningExpanded;
  }
  if (message.origin !== undefined) { trusted.origin = message.origin as ChatMessageOrigin; }
  if (message.outcome !== undefined) { trusted.outcome = message.outcome as ChatMessageOutcome; }
  if (message.runId !== undefined) { trusted.runId = message.runId; }
  if (message.sequence !== undefined) { trusted.sequence = message.sequence; }
  if (message.messageKey !== undefined) { trusted.messageKey = message.messageKey; }
  return { message: normalizeDecodedChatMessage(trusted), diagnostic: '' };
}

function validateSessions(input: ChatHistorySessionWire[], legacyInput: boolean): SessionValidationResult {
  if (!Array.isArray(input)) {
    return { diagnostic: decodeDiagnostic('validate', 'SESSIONS_NOT_ARRAY', 'sessions') };
  }
  if (input.length > MAX_SESSION_COUNT) {
    return { diagnostic: decodeDiagnostic('validate', 'SESSION_LIMIT_EXCEEDED', 'sessions') };
  }
  const sessionIds: Set<string> = new Set<string>();
  const sessions: ChatSession[] = [];
  let sessionIndex: number = 0;
  for (const session of input) {
    const sessionPath: string = 'sessions[' + sessionIndex.toString() + ']';
    if (session === null || typeof session !== 'object') {
      return { diagnostic: decodeDiagnostic('validate', 'SESSION_NOT_OBJECT', sessionPath) };
    }
    if (typeof session.id !== 'string' || !SessionIdPolicy.isValid(session.id)
      || hasForbiddenIdentityControl(session.id)) {
      return { diagnostic: decodeDiagnostic('validate', 'INVALID_SESSION_ID', sessionPath + '.id') };
    }
    if (sessionIds.has(session.id)) {
      return { diagnostic: decodeDiagnostic('validate', 'DUPLICATE_SESSION_ID', sessionPath + '.id') };
    }
    sessionIds.add(session.id);
    if (typeof session.name !== 'string' || session.name.length > MAX_SESSION_NAME_LENGTH
      || hasForbiddenIdentityControl(session.name)) {
      return { diagnostic: decodeDiagnostic('validate', 'INVALID_SESSION_NAME', sessionPath + '.name') };
    }
    if (!Array.isArray(session.messages) || session.messages.length > MAX_MESSAGES_PER_SESSION) {
      return { diagnostic: decodeDiagnostic('validate', 'MESSAGE_LIMIT_EXCEEDED', sessionPath + '.messages') };
    }
    const messageIds: Set<number> = new Set<number>();
    const messageKeys: Set<string> = new Set<string>();
    const unfinishedRuns: Set<string> = new Set<string>();
    const messages: ChatMsg[] = [];
    let messageIndex: number = 0;
    for (const message of session.messages) {
      const messagePath: string = sessionPath + '.messages[' + messageIndex.toString() + ']';
      const messageResult: MessageValidationResult = validateMessage(message, messagePath, legacyInput);
      if (messageResult.message === undefined) { return { diagnostic: messageResult.diagnostic }; }
      const validatedMessage: ChatMsg = messageResult.message;
      if (messageIds.has(message.id)) {
        return { diagnostic: decodeDiagnostic('validate', 'DUPLICATE_MESSAGE_ID', messagePath + '.id') };
      }
      messageIds.add(message.id);
      if (validatedMessage.messageKey !== undefined) {
        if (messageKeys.has(validatedMessage.messageKey)) {
          return { diagnostic: decodeDiagnostic('validate', 'DUPLICATE_MESSAGE_KEY', messagePath + '.messageKey') };
        }
        messageKeys.add(validatedMessage.messageKey);
      }
      if (message.role === 'ai' && message.streaming && message.runId !== undefined) {
        if (unfinishedRuns.has(message.runId)) {
          return { diagnostic: decodeDiagnostic('validate', 'DUPLICATE_UNFINISHED_RUN', messagePath + '.runId') };
        }
        unfinishedRuns.add(message.runId);
      }
      if (legacyInput) { validatedMessage.reasoningExpanded = undefined; }
      messages.push(validatedMessage);
      messageIndex += 1;
    }
    sessions.push({ id: session.id, name: session.name, messages: messages });
    sessionIndex += 1;
  }
  return { sessions: sessions, diagnostic: '' };
}

function parseSessions(raw: string): LegacyParseResult {
  if (raw.length > MAX_SNAPSHOT_BYTES || utf8ByteLengthAtMost(raw, MAX_SNAPSHOT_BYTES) > MAX_SNAPSHOT_BYTES) {
    return { diagnostic: decodeDiagnostic('parse', 'SNAPSHOT_SIZE_EXCEEDED', '$') };
  }
  try {
    const sessions: ChatHistorySessionWire[] = JSON.parse(raw) as ChatHistorySessionWire[];
    const validation: SessionValidationResult = validateSessions(sessions, true);
    return { sessions: validation.sessions, diagnostic: validation.diagnostic };
  } catch (error) {
    return { diagnostic: decodeDiagnostic('parse', 'MALFORMED_JSON', '$') };
  }
}

export interface ChatHistoryDecodeResult {
  snapshot?: ChatHistorySnapshot;
  error: 'none' | 'corrupt' | 'unsupported-version';
  version?: number;
  diagnostic: string;
}

export type ChatHistorySnapshotDecoder = (snapshot: ChatHistorySnapshotWire) => ChatHistoryDecodeResult;

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
    if (raw.length > MAX_SNAPSHOT_BYTES || utf8ByteLengthAtMost(raw, MAX_SNAPSHOT_BYTES) > MAX_SNAPSHOT_BYTES) {
      return corrupt('SNAPSHOT_SIZE_EXCEEDED', '$', 'parse');
    }
    try {
      const snapshot: ChatHistorySnapshotWire = JSON.parse(raw) as ChatHistorySnapshotWire;
      if (snapshot === null || typeof snapshot !== 'object') {
        return corrupt('SNAPSHOT_NOT_OBJECT', '$', 'parse');
      }
      if (typeof snapshot.schemaVersion !== 'number' || !Number.isInteger(snapshot.schemaVersion)
        || snapshot.schemaVersion <= 0) {
        return corrupt('INVALID_SCHEMA_VERSION', 'schemaVersion', 'dispatch');
      }
      const decoder: ChatHistorySnapshotDecoder | undefined =
        this.decoders.get(snapshot.schemaVersion);
      if (decoder === undefined) {
        return {
          error: 'unsupported-version',
          version: snapshot.schemaVersion,
          diagnostic: decodeDiagnostic('dispatch', 'UNSUPPORTED_SCHEMA_VERSION', 'schemaVersion'),
        };
      }
      return decoder(snapshot);
    } catch (error) {
      return corrupt('MALFORMED_JSON', '$', 'parse');
    }
  }
}

function decodeChatHistorySnapshotV1(snapshot: ChatHistorySnapshotWire): ChatHistoryDecodeResult {
  if (!Array.isArray(snapshot.sessions)) {
    return corrupt('SESSIONS_NOT_ARRAY', 'sessions');
  }
  const validation: SessionValidationResult = validateSessions(snapshot.sessions, false);
  if (validation.sessions === undefined) { return { error: 'corrupt', diagnostic: validation.diagnostic }; }
  if (snapshot.migratedFrom !== undefined && snapshot.migratedFrom !== 'preferences') {
    return corrupt('INVALID_MIGRATION_SOURCE', 'migratedFrom');
  }
  const validated: ChatHistorySnapshot = {
    schemaVersion: CHAT_HISTORY_V1_SCHEMA_VERSION,
    sessions: copyChatSessionsForPersistence(validation.sessions),
  };
  if (snapshot.migratedFrom === 'preferences') {
    validated.migratedFrom = 'preferences';
  }
  return { error: 'none', snapshot: validated, diagnostic: '' };
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

interface DiagnosticErrorShape {
  name?: string;
  code?: number;
  message?: string;
}

function sanitizeDiagnosticValue(value: string): string {
  const normalized: string = value.replace(/[\r\n;]/g, '_');
  return normalized.length > 160 ? normalized.substring(0, 160) : normalized;
}

function errorToken(error: Object): string {
  if (!(error instanceof Error)) {
    return 'errorType=unknown';
  }
  const detail: DiagnosticErrorShape = error as DiagnosticErrorShape;
  const name: string = sanitizeDiagnosticValue(detail.name ?? 'Error');
  const code: string = typeof detail.code === 'number' ? detail.code.toString() : 'none';
  const message: string = sanitizeDiagnosticValue(detail.message ?? '');
  return 'errorType=' + name + '; errorCode=' + code + '; errorMessage=' + message;
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
    if (!fileIo.accessSync(directory)) {
      try {
        fileIo.mkdirSync(directory, true);
      } catch (error) {
        if (!fileIo.accessSync(directory)) {
          const errorType: string = error instanceof Error
            ? error.name.replace(/[\r\n;]/g, '_').substring(0, 160) : 'unknown';
          const errorCode: string = error instanceof Error && typeof (error as DiagnosticErrorShape).code === 'number'
            ? (error as DiagnosticErrorShape).code?.toString() ?? 'none' : 'none';
          const errorMessage: string = error instanceof Error
            ? error.message.replace(/[\r\n;]/g, '_').substring(0, 160) : '';
          throw new Error('directory-create-failed; originalErrorType=' + errorType
            + '; originalErrorCode=' + errorCode + '; originalErrorMessage=' + errorMessage);
        }
      }
    }
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
        + '; error=atomic-write-failed; errorType='
        + (error instanceof Error ? error.name.replace(/[\r\n;]/g, '_').substring(0, 160) : 'unknown')
        + '; errorCode=' + (error instanceof Error && typeof (error as DiagnosticErrorShape).code === 'number'
          ? (error as DiagnosticErrorShape).code?.toString() ?? 'none' : 'none')
        + '; errorMessage='
        + (error instanceof Error ? error.message.replace(/[\r\n;]/g, '_').substring(0, 160) : '')
        + '; schemaVersion=' + CHAT_HISTORY_SCHEMA_VERSION.toString() + '; ts='
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
      return combineFallbackResult(taskpoolResult, await runWorkerWrite(path, sessions, migratedFrom));
    } catch (error) {
      const taskpoolFailure: ChatHistorySaveResult = {
        success: false,
        state: 'failed',
        stage: 'PREPARE',
        transport: 'taskpool',
        retryable: true,
        diagnostic: 'transport=taskpool; ' + diagnostic('PREPARE', 'error=taskpool-exception; ' + errorToken(error)),
      };
      return combineFallbackResult(taskpoolFailure, await runWorkerWrite(path, sessions, migratedFrom));
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
            diagnostic: 'state=corrupt; source=file; fallback=memory; ' + decoded.diagnostic,
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
