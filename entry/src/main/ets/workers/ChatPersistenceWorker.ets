/**
 * ChatPersistenceWorker.ets — 聊天持久化 Worker fallback 写入协议
 *
 * 路径: entry/src/main/ets/workers/ChatPersistenceWorker.ets
 * 职责: 区分 string capability probe 与 kind=write structured request，并返回可诊断的
 * unsupported、AtomicFile stage 和 content-safe failure response。
 * 依赖: @kit.ArkTS(worker)。
 *
 * 数据流:
 *   ThreadWorker.postMessage → workerPort.onmessage → workerPort.postMessage
 *
 * ArkTS 1.1 strict 适配:
 *   - Worker 消息协议使用固定 string 常量,不使用 any/unknown 或动态对象访问。
 */

import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import fileIo from '@ohos.file.fs';
import { ChatSession, copyChatSessionsForPersistence } from '../overlays/AgentFloatWindow/chat/ChatModels';
import { CHAT_HISTORY_SCHEMA_VERSION } from '../services/ChatHistorySchema';

const WORKER_SUCCESS_REQUEST: string = 'worker-capability-success';
const WORKER_SUCCESS_RESPONSE: string = 'worker-capability-ok';
const WORKER_FAILURE_RESPONSE: string = 'worker-capability-error';

type AtomicWriteStage = 'PREPARE' | 'WRITE' | 'COMMIT' | 'VERIFY';

interface ChatWorkerRequest {
  kind: string;
  path: string;
  sessions: ChatSession[];
  migratedFrom?: string;
}

interface ChatWorkerResponse {
  // write-result is a completed write protocol response; unsupported-request
  // is never interpreted as a write by the caller.
  kind: 'write-result' | 'unsupported-request';
  success: boolean;
  stage: AtomicWriteStage;
  schemaVersion: number;
  diagnostic: string;
}

interface ChatWorkerSnapshot {
  schemaVersion: number;
  sessions: ChatSession[];
  migratedFrom?: string;
}

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;
function diagnostic(stage: AtomicWriteStage, token: string): string {
  return 'stage=' + stage
    + '; ' + token
    + '; schemaVersion=' + CHAT_HISTORY_SCHEMA_VERSION.toString()
    + '; ts=' + Date.now().toString();
}

workerPort.onmessage = async (event: MessageEvents): Promise<void> => {
  // Capability probes are fixed string messages and only verify Worker wiring.
  if (typeof event.data === 'string') {
    const request: string = event.data;
    const response: string = request === WORKER_SUCCESS_REQUEST
      ? WORKER_SUCCESS_RESPONSE
      : WORKER_FAILURE_RESPONSE;
    workerPort.postMessage(response);
    return;
  }
  const request: ChatWorkerRequest = event.data;
  if (request.kind !== 'write') {
    const unsupported: ChatWorkerResponse = {
      kind: 'unsupported-request',
      success: false,
      stage: 'PREPARE',
      schemaVersion: CHAT_HISTORY_SCHEMA_VERSION,
      diagnostic: diagnostic('PREPARE', 'error=unsupported-request; response=unsupported'),
    };
    workerPort.postMessage(unsupported);
    return;
  }
  let tmpPath: string = '';
  let json: string = '';
  try {
    const snapshot: ChatWorkerSnapshot = {
      schemaVersion: CHAT_HISTORY_SCHEMA_VERSION,
      // The production service sends a persistence snapshot. Copy again at
      // this boundary so UI-only reasoningExpanded can never reach disk.
      sessions: copyChatSessionsForPersistence(request.sessions),
    };
    if (request.migratedFrom !== undefined && request.migratedFrom.length > 0) {
      snapshot.migratedFrom = request.migratedFrom;
    }
    json = JSON.stringify(snapshot);
  } catch (error) {
    const result: ChatWorkerResponse = {
      kind: 'write-result',
      success: false,
      stage: 'PREPARE',
      schemaVersion: CHAT_HISTORY_SCHEMA_VERSION,
      diagnostic: diagnostic('PREPARE', 'error=serialization-failed'),
    };
    workerPort.postMessage(result);
    return;
  }
  try {
    const directory: string = request.path.substring(0, request.path.lastIndexOf('/'));
    fileIo.mkdirSync(directory, true);
    tmpPath = request.path + '.tmp';
  } catch (error) {
    const result: ChatWorkerResponse = {
      kind: 'write-result',
      success: false,
      stage: 'PREPARE',
      schemaVersion: CHAT_HISTORY_SCHEMA_VERSION,
      diagnostic: diagnostic('PREPARE', 'error=worker-prepare-failed'),
    };
    workerPort.postMessage(result);
    return;
  }
  try {
    const file: fileIo.File = fileIo.openSync(
      tmpPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    );
    fileIo.writeSync(file.fd, json);
    fileIo.closeSync(file.fd);
  } catch (error) {
    try {
      fileIo.unlinkSync(tmpPath);
    } catch (rollbackError) {
    }
    const result: ChatWorkerResponse = {
      kind: 'write-result',
      success: false,
      stage: 'WRITE',
      schemaVersion: CHAT_HISTORY_SCHEMA_VERSION,
      diagnostic: diagnostic('WRITE', 'error=worker-write-failed'),
    };
    workerPort.postMessage(result);
    return;
  }
  try {
    fileIo.renameSync(tmpPath, request.path);
  } catch (error) {
    try {
      fileIo.unlinkSync(tmpPath);
    } catch (rollbackError) {
    }
    const result: ChatWorkerResponse = {
      kind: 'write-result',
      success: false,
      stage: 'COMMIT',
      schemaVersion: CHAT_HISTORY_SCHEMA_VERSION,
      diagnostic: diagnostic('COMMIT', 'error=worker-commit-failed'),
    };
    workerPort.postMessage(result);
    return;
  }
  try {
    const formal: string = fileIo.readTextSync(request.path);
    const result: ChatWorkerResponse = {
      kind: 'write-result',
      success: formal === json,
      stage: 'VERIFY',
      schemaVersion: CHAT_HISTORY_SCHEMA_VERSION,
      diagnostic: formal === json ? diagnostic('VERIFY', 'verified=true') : diagnostic('VERIFY', 'error=content-mismatch'),
    };
    workerPort.postMessage(result);
  } catch (error) {
    const result: ChatWorkerResponse = {
      kind: 'write-result',
      success: false,
      stage: 'VERIFY',
      schemaVersion: CHAT_HISTORY_SCHEMA_VERSION,
      diagnostic: diagnostic('VERIFY', 'error=worker-verify-failed'),
    };
    workerPort.postMessage(result);
  }
};
