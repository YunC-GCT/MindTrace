/**
 * ChatHistoryWire.ets — 聊天历史的线上格式、校验与解码
 *
 * 路径: entry/src/main/ets/services/ChatHistoryWire.ets
 * 职责: wire DTO / 端口、容量上限、结构校验与按版本解码
 * 依赖: common、@kit.ArkData（仅类型）
 *
 * 数据流:
 *   preferences/文件原始字符串 → decodeChatHistorySnapshot → ChatHistoryDecodeResult
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

export { CHAT_HISTORY_SCHEMA_VERSION } from './ChatHistorySchema';

export const STREAM_SAVE_THROTTLE_MS: number = 500;
export const CHAT_CLEAR_LOG_DOMAIN: number = 0xA2A0;
export const CHAT_CLEAR_LOG_TAG: string = 'ChatHistoryClear';

export type AtomicWriteStage = 'PREPARE' | 'WRITE' | 'COMMIT' | 'VERIFY';
export type PersistenceTransport = 'taskpool' | 'worker';
export type ChatHistoryLoadState = 'default' | 'migrated' | 'migrationFailed' | 'loaded' | 'corrupt' | 'unsupported-version' | 'blocked';
export type ChatHistorySaveState = 'idle' | 'completed' | 'failed' | 'blocked' | 'not-initialized';

export interface ChatHistorySnapshot {
  schemaVersion: number;
  sessions: ChatSession[];
  migratedFrom?: string;
  historyEpoch?: number;
}

export interface ChatHistoryMessageWire {
  id: number;
  role: string;
  content: string;
  ts: number;
  streaming: boolean;
  reasoning?: string;
  reasoningExpanded?: boolean;
  runParts?: ChatHistoryAgentRunPartWire[];
  origin?: string;
  outcome?: string;
  runId?: string;
  sequence?: number;
  messageKey?: string;
  noteContextClarification?: NoteContextClarification;
}

export interface ChatHistoryAgentRunPartWire {
  id: string;
  sequence: number;
  kind: string;
  status: string;
  content: string;
  toolCallId?: string;
  toolName?: string;
  detail?: string;
  progressKey?: string;
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
  historyEpoch?: number;
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
  writeSnapshot(
    path: string,
    sessions: ChatSession[],
    migratedFrom: string | undefined,
    historyEpoch?: number,
  ): Promise<ChatHistorySaveResult>;
  fileExists(path: string): Promise<boolean>;
}

export interface ChatHistoryPreferencesPort {
  readSessions(): string;
}

export interface SaveWaiter {
  resolve: (result: ChatHistorySaveResult) => void;
}

export interface AtomicWriteTaskResult {
  success: boolean;
  stage: AtomicWriteStage;
  schemaVersion: number;
  diagnostic: string;
}

export interface WorkerWriteResponse {
  kind: string;
  success: boolean;
  stage: AtomicWriteStage;
  schemaVersion: number;
  diagnostic: string;
}

export interface WorkerWriteRequest {
  kind: string;
  path: string;
  sessions: ChatSession[];
  migratedFrom?: string;
  // Worker 协议当前不消费该字段；TaskPool 路径用它写入快照 historyEpoch。
  historyEpoch?: number;
}

export const WORKER_SCRIPT: string = 'entry/ets/workers/ChatPersistenceWorker.ets';
export const WORKER_WRITE_TIMEOUT_MS: number = 5000;
export const MAX_CONSECUTIVE_FAILURES: number = 3;
const MAX_SNAPSHOT_BYTES: number = 16 * 1024 * 1024;
const MAX_SESSION_COUNT: number = 200;
const MAX_MESSAGES_PER_SESSION: number = 5000;
const MAX_SESSION_NAME_LENGTH: number = 80;
const MAX_MESSAGE_TEXT_LENGTH: number = 262144;
const MAX_MESSAGE_KEY_LENGTH: number = 256;
const MAX_RUN_PART_COUNT: number = 5000;
const MAX_RUN_PART_IDENTITY_LENGTH: number = 256;

export function defaultSessions(): ChatSession[] { return []; }

export function normalizeHistoryEpoch(value: number | undefined): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    return 0;
  }
  return value;
}

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

function isAgentRunPartKind(value: string): boolean {
  return value === 'thinking' || value === 'tool' || value === 'answer'
    || value === 'status' || value === 'error';
}

function isAgentRunPartStatus(value: string): boolean {
  return value === 'pending' || value === 'running' || value === 'success' || value === 'failed';
}

interface SessionValidationResult {
  sessions?: ChatSession[];
  diagnostic: string;
}

export interface LegacyParseResult {
  sessions?: ChatSession[];
  diagnostic: string;
}

interface MessageValidationResult {
  message?: ChatMsg;
  diagnostic: string;
}

interface AgentRunPartsValidationResult {
  parts?: AgentRunPart[];
  diagnostic: string;
}

function invalidRunPartIdentity(value: string): boolean {
  return value.length === 0 || value.length > MAX_RUN_PART_IDENTITY_LENGTH
    || hasForbiddenIdentityControl(value);
}

function validateAgentRunParts(
  input: ChatHistoryAgentRunPartWire[],
  path: string,
): AgentRunPartsValidationResult {
  if (!Array.isArray(input) || input.length > MAX_RUN_PART_COUNT) {
    return { diagnostic: decodeDiagnostic('validate', 'INVALID_RUN_PARTS', path) };
  }
  const parts: AgentRunPart[] = [];
  let partIndex: number = 0;
  for (const part of input) {
    const partPath: string = path + '[' + partIndex.toString() + ']';
    if (part === null || typeof part !== 'object') {
      return { diagnostic: decodeDiagnostic('validate', 'RUN_PART_NOT_OBJECT', partPath) };
    }
    if (typeof part.id !== 'string' || invalidRunPartIdentity(part.id)) {
      return { diagnostic: decodeDiagnostic('validate', 'INVALID_RUN_PART_ID', partPath + '.id') };
    }
    if (typeof part.sequence !== 'number' || !Number.isSafeInteger(part.sequence) || part.sequence < 0) {
      return { diagnostic: decodeDiagnostic('validate', 'INVALID_RUN_PART_SEQUENCE', partPath + '.sequence') };
    }
    if (typeof part.kind !== 'string' || !isAgentRunPartKind(part.kind)) {
      return { diagnostic: decodeDiagnostic('validate', 'INVALID_RUN_PART_KIND', partPath + '.kind') };
    }
    if (typeof part.status !== 'string' || !isAgentRunPartStatus(part.status)) {
      return { diagnostic: decodeDiagnostic('validate', 'INVALID_RUN_PART_STATUS', partPath + '.status') };
    }
    if (typeof part.content !== 'string' || part.content.length > MAX_MESSAGE_TEXT_LENGTH
      || hasForbiddenMessageControl(part.content)) {
      return { diagnostic: decodeDiagnostic('validate', 'INVALID_RUN_PART_CONTENT', partPath + '.content') };
    }
    if (part.toolCallId !== undefined && (typeof part.toolCallId !== 'string'
      || invalidRunPartIdentity(part.toolCallId))) {
      return { diagnostic: decodeDiagnostic('validate', 'INVALID_RUN_PART_TOOL_CALL_ID', partPath + '.toolCallId') };
    }
    if (part.toolName !== undefined && (typeof part.toolName !== 'string'
      || part.toolName.length > MAX_RUN_PART_IDENTITY_LENGTH || hasForbiddenIdentityControl(part.toolName))) {
      return { diagnostic: decodeDiagnostic('validate', 'INVALID_RUN_PART_TOOL_NAME', partPath + '.toolName') };
    }
    if (part.detail !== undefined && (typeof part.detail !== 'string'
      || part.detail.length > MAX_MESSAGE_TEXT_LENGTH || hasForbiddenMessageControl(part.detail))) {
      return { diagnostic: decodeDiagnostic('validate', 'INVALID_RUN_PART_DETAIL', partPath + '.detail') };
    }
    if (part.progressKey !== undefined && (typeof part.progressKey !== 'string'
      || invalidRunPartIdentity(part.progressKey))) {
      return { diagnostic: decodeDiagnostic('validate', 'INVALID_RUN_PART_PROGRESS_KEY', partPath + '.progressKey') };
    }
    const trusted: AgentRunPart = {
      id: part.id,
      sequence: part.sequence,
      kind: part.kind as AgentRunPartKind,
      status: part.status as AgentRunPartStatus,
      content: part.content,
    };
    if (part.toolCallId !== undefined) { trusted.toolCallId = part.toolCallId; }
    if (part.toolName !== undefined) { trusted.toolName = part.toolName; }
    if (part.detail !== undefined) { trusted.detail = part.detail; }
    if (part.progressKey !== undefined) { trusted.progressKey = part.progressKey; }
    parts.push(trusted);
    partIndex += 1;
  }
  return { parts: parts, diagnostic: '' };
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
  let runParts: AgentRunPart[] | undefined = undefined;
  if (message.runParts !== undefined) {
    const runPartsResult: AgentRunPartsValidationResult =
      validateAgentRunParts(message.runParts, path + '.runParts');
    if (runPartsResult.parts === undefined) {
      return { diagnostic: runPartsResult.diagnostic };
    }
    runParts = runPartsResult.parts;
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
  const clarification: NoteContextClarification | undefined =
    sanitizeNoteContextClarification(message.noteContextClarification);
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
  if (runParts !== undefined) { trusted.runParts = runParts; }
  if (legacyInput && message.reasoningExpanded !== undefined) {
    trusted.reasoningExpanded = message.reasoningExpanded;
  }
  if (message.origin !== undefined) { trusted.origin = message.origin as ChatMessageOrigin; }
  if (message.outcome !== undefined) { trusted.outcome = message.outcome as ChatMessageOutcome; }
  if (message.runId !== undefined) { trusted.runId = message.runId; }
  if (message.sequence !== undefined) { trusted.sequence = message.sequence; }
  if (message.messageKey !== undefined) { trusted.messageKey = message.messageKey; }
  if (clarification !== undefined) { trusted.noteContextClarification = clarification; }
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

export function parseSessions(raw: string): LegacyParseResult {
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
    // 旧快照没有 historyEpoch：按 0 处理，不视为损坏。
    historyEpoch: normalizeHistoryEpoch(snapshot.historyEpoch),
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

export function errorToken(error: Object): string {
  if (!(error instanceof Error)) {
    return 'errorType=unknown';
  }
  const detail: DiagnosticErrorShape = error as DiagnosticErrorShape;
  const name: string = sanitizeDiagnosticValue(detail.name ?? 'Error');
  const code: string = typeof detail.code === 'number' ? detail.code.toString() : 'none';
  const message: string = sanitizeDiagnosticValue(detail.message ?? '');
  return 'errorType=' + name + '; errorCode=' + code + '; errorMessage=' + message;
}

export function diagnostic(stage: AtomicWriteStage, token: string): string {
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
  historyEpoch: number,
): Promise<AtomicWriteTaskResult> {
  let stage: AtomicWriteStage = 'PREPARE';
  const schemaVersion: number = CHAT_HISTORY_SCHEMA_VERSION;
  let tmpPath: string = '';
  try {
    const snapshot: ChatHistorySnapshot = {
      schemaVersion: schemaVersion,
      sessions: sessions,
      historyEpoch: (typeof historyEpoch === 'number' && Number.isSafeInteger(historyEpoch) && historyEpoch >= 0)
        ? historyEpoch : 0,
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
