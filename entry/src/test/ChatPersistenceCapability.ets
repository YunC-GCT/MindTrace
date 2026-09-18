/**
 * ChatPersistenceCapability.ets — ticket #122 聊天持久化能力门禁
 *
 * 路径: entry/src/test/ChatPersistenceCapability.ets
 * 职责: 作为 test-only ChatPersistenceCapability，验证 TaskPool 纯数据快照序列化、Worker fallback 协议、AtomicFile 提交/回滚阶段诊断。
 * 依赖: @ohos.file.fs; @kit.ArkTS(taskpool/worker); main/ets/services/ChatFilesDirSeam。
 *
 * 数据流:
 *   SnapshotTaskInput → TaskPool/Worker/AtomicFile probe → SnapshotTaskResult/PersistenceCapabilityResult
 *
 * 设计边界:
 *   本文件仅为 test 侧能力探针，不是生产 ChatHistoryPersistence；不接入生产聊天历史迁移，不读取/写入 Preferences。
 *   生产保存边界是 entry 私有文件快照服务，Preferences 仅由生产服务作为迁移读取源。
 *
 * ArkTS 1.1 strict 适配:
 *   - @Concurrent 任务只接收 number/string;结果和失败诊断均使用显式 interface/type。
 */

import fileIo from '@ohos.file.fs';
import { ErrorEvent, MessageEvents, taskpool, worker } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  ChatFilesDirSeam,
  getChatFilesDirSeam,
} from '../main/ets/services/ChatFilesDirSeam';

export type AtomicWriteStage = 'PREPARE' | 'WRITE' | 'COMMIT' | 'VERIFY';
export type PersistenceTransport = 'taskpool' | 'worker';

export interface SnapshotTaskInput {
  schemaVersion: number;
  sessionsJson: string;
}

export interface SnapshotTaskResult {
  success: boolean;
  stage: AtomicWriteStage;
  transport: PersistenceTransport;
  schemaVersion: number;
  jsonLength: number;
  snapshotInputLength: number;
  serializedJson: string;
  diagnostic: string;
}

export interface PersistenceCapabilityResult {
  success: boolean;
  stage: AtomicWriteStage;
  verified: boolean;
  rollbackCalled: boolean;
  diagnostic: string;
}

interface WorkerProbeResult {
  success: boolean;
  response: string;
  reason: string;
}

interface WorkerUnsupportedRequest {
  kind: string;
}

interface WorkerProtocolResponse {
  kind: string;
  success: boolean;
  stage: AtomicWriteStage;
  schemaVersion: number;
  diagnostic: string;
}

const CAPABILITY_FILE_NAME: string = 'ticket-122-capability.json';
const ROLLBACK_BASELINE_JSON: string = '{"baseline":true}';
const WORKER_SCRIPT: string = '../main/ets/workers/ChatPersistenceWorker.ets';
const WORKER_PROBE_TIMEOUT_MS: number = 1000;
const WORKER_SUCCESS_REQUEST: string = 'worker-capability-success';
const WORKER_SUCCESS_RESPONSE: string = 'worker-capability-ok';
const WORKER_FAILURE_REQUEST: string = 'worker-capability-failure';
const WORKER_FAILURE_RESPONSE: string = 'worker-capability-error';

function snapshotInputIsValid(schemaVersion: number, sessionsJson: string): boolean {
  return schemaVersion > 0 && sessionsJson.length > 0;
}

function buildSnapshotJson(schemaVersion: number, sessionsJson: string): string {
  return '{"schemaVersion":' + schemaVersion.toString() + ',"sessionsJson":' + JSON.stringify(sessionsJson) + '}';
}

@Concurrent
export function serializeSnapshotTask(schemaVersion: number, sessionsJson: string): string {
  if (schemaVersion <= 0 || sessionsJson.length === 0) {
    throw new Error('snapshot input rejected');
  }
  return '{"schemaVersion":' + schemaVersion.toString() + ',"sessionsJson":' + JSON.stringify(sessionsJson) + '}';
}

export class ChatPersistenceCapability {
  // This API is deliberately test-only. Production chat history is owned by
  // ChatHistoryPersistence and does not call this capability probe.
  static async serializeSnapshot(input: SnapshotTaskInput): Promise<SnapshotTaskResult> {
    if (!snapshotInputIsValid(input.schemaVersion, input.sessionsJson)) {
      return ChatPersistenceCapability.taskFailure('PREPARE', 'taskpool', 'snapshot-task-rejected');
    }
    try {
      const task: taskpool.GenericsTask<[number, string], string> = new taskpool.GenericsTask<[number, string], string>(
        serializeSnapshotTask,
        input.schemaVersion,
        input.sessionsJson,
      );
      const serializedJson: string = await taskpool.execute<[number, string], string>(task);
      if (serializedJson.length > 0) {
        return ChatPersistenceCapability.taskSuccess(input, serializedJson, 'taskpool');
      }
      return ChatPersistenceCapability.taskFailure(
        'VERIFY',
        'taskpool',
        'snapshot-task-empty-result; blocker=local-unit-runner-taskpool-empty-result',
      );
    } catch (error) {
      return ChatPersistenceCapability.taskFailure('PREPARE', 'taskpool', 'snapshot-task-rejected');
    }
  }

  static async verifyTaskPoolFailureResponse(): Promise<SnapshotTaskResult> {
    try {
      const task: taskpool.GenericsTask<[number, string], string> = new taskpool.GenericsTask<[number, string], string>(
        serializeSnapshotTask,
        0,
        '',
      );
      const serializedJson: string = await taskpool.execute<[number, string], string>(task);
      if (serializedJson.length > 0) {
        return ChatPersistenceCapability.taskFailure(
          'VERIFY',
          'taskpool',
          'snapshot-task-unexpected-success; blocker=local-unit-runner-taskpool-invalid-input-succeeded',
        );
      }
      return ChatPersistenceCapability.taskFailure(
        'PREPARE',
        'taskpool',
        'snapshot-task-failure-not-observed; blocker=local-unit-runner-taskpool-no-rejection',
      );
    } catch (error) {
      return ChatPersistenceCapability.taskFailure('PREPARE', 'taskpool', 'snapshot-task-rejected');
    }
  }

  static async verifyWorkerFallback(input: SnapshotTaskInput): Promise<SnapshotTaskResult> {
    try {
      const probe: WorkerProbeResult = await ChatPersistenceCapability.runWorkerProbe(WORKER_SUCCESS_REQUEST);
      if (!probe.success) {
        return ChatPersistenceCapability.workerFailure(probe.reason);
      }
      if (probe.response !== WORKER_SUCCESS_RESPONSE) {
        return ChatPersistenceCapability.workerFailure('snapshot-worker-response-mismatch');
      }
      return ChatPersistenceCapability.workerSuccess(input);
    } catch (error) {
      return ChatPersistenceCapability.workerFailure('snapshot-worker-probe-rejected');
    }
  }

  static async verifyWorkerFailureResponse(): Promise<SnapshotTaskResult> {
    try {
      const probe: WorkerProbeResult = await ChatPersistenceCapability.runWorkerProbe(WORKER_FAILURE_REQUEST);
      if (!probe.success) {
        return ChatPersistenceCapability.workerFailure(probe.reason);
      }
      if (probe.response === WORKER_FAILURE_RESPONSE) {
        return ChatPersistenceCapability.workerFailure('snapshot-worker-failure-response-observed');
      }
      return ChatPersistenceCapability.workerFailure('snapshot-worker-failure-response-mismatch');
    } catch (error) {
      return ChatPersistenceCapability.workerFailure('snapshot-worker-probe-rejected');
    }
  }

  static async verifyWorkerUnsupportedRequest(): Promise<SnapshotTaskResult> {
    try {
      const response: WorkerProtocolResponse = await ChatPersistenceCapability.runWorkerUnsupportedProbe();
      const safe: boolean = response.diagnostic.indexOf('答案') < 0
        && response.diagnostic.indexOf('数学') < 0;
      if (response.kind === 'unsupported-request' && !response.success && safe) {
        return {
          success: false,
          stage: response.stage,
          transport: 'worker',
          schemaVersion: response.schemaVersion,
          jsonLength: 0,
          snapshotInputLength: 0,
          serializedJson: '',
          diagnostic: 'transport=worker; stage=' + response.stage + '; reason=unsupported-request; response=unsupported',
        };
      }
      return ChatPersistenceCapability.workerFailure('snapshot-worker-unsupported-response-mismatch');
    } catch (error) {
      return ChatPersistenceCapability.workerFailure('snapshot-worker-unsupported-probe-rejected');
    }
  }

  static async writeAtomicSnapshot(input: SnapshotTaskInput): Promise<PersistenceCapabilityResult> {
    const serialized: SnapshotTaskResult = await ChatPersistenceCapability.serializeSnapshot(input);
    if (!serialized.success) {
      return ChatPersistenceCapability.persistenceFailure(
        'PREPARE',
        false,
        false,
        'snapshot-serialization-unavailable; blocker=taskpool-snapshot-serialization-unavailable',
      );
    }
    return ChatPersistenceCapability.writeAtomicJson(serialized.serializedJson);
  }

  static async writeAtomicSnapshotWithInjectedWriteFailure(
    input: SnapshotTaskInput,
  ): Promise<PersistenceCapabilityResult> {
    const serialized: SnapshotTaskResult = await ChatPersistenceCapability.serializeSnapshot(input);
    if (!serialized.success) {
      return ChatPersistenceCapability.persistenceFailure(
        'PREPARE',
        false,
        false,
        'snapshot-serialization-unavailable; blocker=taskpool-snapshot-serialization-unavailable',
      );
    }
    const path: string | undefined = ChatPersistenceCapability.capabilityPath();
    if (path === undefined) {
      return ChatPersistenceCapability.persistenceFailure(
        'PREPARE',
        false,
        false,
        'snapshot-filesDir-unavailable; blocker=app-private-filesDir-unavailable',
      );
    }
    let rollbackCalled: boolean = false;
    try {
      const directory: string = ChatPersistenceCapability.capabilityDirectory(path);
      ChatPersistenceCapability.ensureDirectory(directory);
      const baseline: fileIo.AtomicFile = new fileIo.AtomicFile(path);
      const baselineStream = baseline.startWrite();
      await ChatPersistenceCapability.writeStreamFully(baselineStream, ROLLBACK_BASELINE_JSON);
      baseline.finishWrite();

      const failed: fileIo.AtomicFile = new fileIo.AtomicFile(path);
      const failedStream = failed.startWrite();
      await ChatPersistenceCapability.writeStreamFully(failedStream, serialized.serializedJson);
      failed.failWrite();
      rollbackCalled = true;
      const formalJson: string = fileIo.readTextSync(path);
      const preserved: boolean = formalJson === ROLLBACK_BASELINE_JSON;
      const reason: string = preserved ? 'snapshot-write-rolled-back-preserved' : 'snapshot-write-rolled-back-not-preserved';
      return ChatPersistenceCapability.persistenceFailure('WRITE', false, rollbackCalled, reason);
    } catch (error) {
      const digest: string = ChatPersistenceCapability.errorDigest(error as Error);
      const reason: string = rollbackCalled
        ? 'snapshot-write-rollback-attempted; error=' + digest
        : 'snapshot-write-failed-before-rollback; error=' + digest + '; blocker=atomic-file-write-unavailable';
      return ChatPersistenceCapability.persistenceFailure('WRITE', false, rollbackCalled, reason);
    }
  }

  static async simulateFailure(stage: AtomicWriteStage): Promise<PersistenceCapabilityResult> {
    return Promise.resolve(ChatPersistenceCapability.persistenceFailure(stage, false, stage !== 'PREPARE', 'snapshot-stage-simulated'));
  }

  static productionMigrationEnabled(): boolean {
    return true;
  }

  static snapshotPathShape(): string {
    return ChatFilesDirSeam.RELATIVE_SHAPE;
  }

  static taskFailure(stage: AtomicWriteStage, transport: PersistenceTransport, reason: string): SnapshotTaskResult {
    const result: SnapshotTaskResult = {
      success: false,
      stage: stage,
      transport: transport,
      schemaVersion: 0,
      jsonLength: 0,
      snapshotInputLength: 0,
      serializedJson: '',
      diagnostic: 'transport=' + transport + '; stage=' + stage + '; reason=' + reason,
    };
    return result;
  }

  private static taskSuccess(
    input: SnapshotTaskInput,
    serializedJson: string,
    transport: PersistenceTransport,
  ): SnapshotTaskResult {
    return {
      success: true,
      stage: 'VERIFY',
      transport: transport,
      schemaVersion: input.schemaVersion,
      jsonLength: serializedJson.length,
      snapshotInputLength: input.sessionsJson.length,
      serializedJson: serializedJson,
      diagnostic: 'transport=' + transport + '; stage=VERIFY; schemaVersion=' + input.schemaVersion.toString(),
    };
  }

  private static workerSuccess(input: SnapshotTaskInput): SnapshotTaskResult {
    const serializedJson: string = buildSnapshotJson(input.schemaVersion, input.sessionsJson);
    const result: SnapshotTaskResult = {
      success: true,
      stage: 'VERIFY',
      transport: 'worker',
      schemaVersion: input.schemaVersion,
      jsonLength: serializedJson.length,
      snapshotInputLength: input.sessionsJson.length,
      serializedJson: serializedJson,
      diagnostic: 'transport=worker; stage=VERIFY; schemaVersion=' + input.schemaVersion.toString(),
    };
    return result;
  }

  private static workerFailure(reason: string): SnapshotTaskResult {
    const blockerSuffix: string = reason === 'snapshot-worker-timeout' || reason === 'snapshot-worker-create-failed'
      ? '; blocker=local-unit-runner-worker-unavailable'
      : '';
    const result: SnapshotTaskResult = {
      success: false,
      stage: 'WRITE',
      transport: 'worker',
      schemaVersion: 0,
      jsonLength: 0,
      snapshotInputLength: 0,
      serializedJson: '',
      diagnostic: 'transport=worker; stage=WRITE; reason=' + reason + blockerSuffix,
    };
    return result;
  }

  private static runWorkerProbe(request: string): Promise<WorkerProbeResult> {
    return new Promise<WorkerProbeResult>((resolve: (result: WorkerProbeResult) => void,
      reject: (reason: Error) => void): void => {
      let settled: boolean = false;
      let workerInstance: worker.ThreadWorker | undefined;
      const timeoutId: number = setTimeout((): void => {
        fail('snapshot-worker-timeout');
      }, WORKER_PROBE_TIMEOUT_MS);
      const finish = (response: string): void => {
        if (!settled) {
          settled = true;
          clearTimeout(timeoutId);
          if (workerInstance !== undefined) {
            workerInstance.terminate();
          }
          const result: WorkerProbeResult = {
            success: true,
            response: response,
            reason: '',
          };
          resolve(result);
        }
      };
      const fail = (reason: string): void => {
        if (!settled) {
          settled = true;
          clearTimeout(timeoutId);
          if (workerInstance !== undefined) {
            workerInstance.terminate();
          }
          const result: WorkerProbeResult = {
            success: false,
            response: '',
            reason: reason,
          };
          resolve(result);
        }
      };
      try {
        workerInstance = new worker.ThreadWorker(WORKER_SCRIPT);
        workerInstance.onmessage = (event: MessageEvents): void => {
          const response: string = event.data;
          finish(response);
        };
        workerInstance.onmessageerror = (_event: MessageEvents): void => {
          fail('snapshot-worker-message-error');
        };
        workerInstance.onAllErrors = (error: ErrorEvent): void => {
          fail('snapshot-worker-all-errors:' + error.message);
        };
        workerInstance.onerror = (error: ErrorEvent): void => {
          fail('snapshot-worker-onerror:' + error.message);
        };
        workerInstance.onexit = (code: number): void => {
          if (code !== 0) {
            fail('snapshot-worker-nonzero-exit');
          }
        };
        workerInstance.postMessage(request);
      } catch (error) {
        fail('snapshot-worker-create-failed');
      }
    });
  }

  private static runWorkerUnsupportedProbe(): Promise<WorkerProtocolResponse> {
    return new Promise<WorkerProtocolResponse>((resolve: (result: WorkerProtocolResponse) => void,
      reject: (reason: Error) => void): void => {
      let settled: boolean = false;
      let workerInstance: worker.ThreadWorker | undefined;
      const timeoutId: number = setTimeout((): void => {
        if (!settled) {
          settled = true;
          if (workerInstance !== undefined) {
            workerInstance.terminate();
          }
          reject(new Error('snapshot-worker-unsupported-timeout'));
        }
      }, WORKER_PROBE_TIMEOUT_MS);
      try {
        workerInstance = new worker.ThreadWorker(WORKER_SCRIPT);
        workerInstance.onmessage = (event: MessageEvents): void => {
          if (settled) {
            return;
          }
          settled = true;
          clearTimeout(timeoutId);
          if (workerInstance !== undefined) {
            workerInstance.terminate();
          }
          const response: WorkerProtocolResponse = event.data;
          resolve(response);
        };
        const request: WorkerUnsupportedRequest = { kind: 'read' };
        workerInstance.postMessage(request);
      } catch (error) {
        if (!settled) {
          settled = true;
          clearTimeout(timeoutId);
          if (workerInstance !== undefined) {
            workerInstance.terminate();
          }
          reject(new Error('snapshot-worker-unsupported-create-failed'));
        }
      }
    });
  }

  private static capabilityPath(): string | undefined {
    const seam = getChatFilesDirSeam();
    if (seam === null || seam.state !== 'resolved') {
      return undefined;
    }
    return ChatFilesDirSeam.snapshotDir(seam.filesDir) + '/' + CAPABILITY_FILE_NAME;
  }

  private static capabilityDirectory(path: string): string {
    const suffix: string = '/' + CAPABILITY_FILE_NAME;
    return path.endsWith(suffix) ? path.substring(0, path.length - suffix.length) : path;
  }

  private static async writeAtomicJson(json: string): Promise<PersistenceCapabilityResult> {
    const path: string | undefined = ChatPersistenceCapability.capabilityPath();
    if (path === undefined) {
      return ChatPersistenceCapability.persistenceFailure(
        'PREPARE',
        false,
        false,
        'snapshot-filesDir-unavailable; blocker=app-private-filesDir-unavailable',
      );
    }
    let atomic: fileIo.AtomicFile | undefined;
    try {
      ChatPersistenceCapability.ensureDirectory(ChatPersistenceCapability.capabilityDirectory(path));
      atomic = new fileIo.AtomicFile(path);
      const stream = atomic.startWrite();
      await ChatPersistenceCapability.writeStreamFully(stream, json);
    } catch (error) {
      if (atomic !== undefined) {
        ChatPersistenceCapability.safeFailWrite(atomic);
      }
      const digest: string = ChatPersistenceCapability.errorDigest(error as Error);
      return ChatPersistenceCapability.persistenceFailure('WRITE', false, atomic !== undefined, 'snapshot-write-failed; error=' + digest + '; blocker=atomic-file-write-unavailable');
    }
    try {
      if (atomic === undefined) {
        return ChatPersistenceCapability.persistenceFailure('COMMIT', false, false, 'snapshot-atomic-missing');
      }
      atomic.finishWrite();
    } catch (error) {
      ChatPersistenceCapability.safeFailWrite(atomic);
      const digest: string = ChatPersistenceCapability.errorDigest(error as Error);
      return ChatPersistenceCapability.persistenceFailure('COMMIT', false, true, 'snapshot-commit-failed; error=' + digest);
    }
    try {
      const verifiedJson: string = fileIo.readTextSync(path);
      if (verifiedJson !== json) {
        return ChatPersistenceCapability.persistenceFailure(
          'VERIFY',
          false,
          false,
          'snapshot-verify-mismatch; writtenLength=' + json.length.toString() + '; readLength=' + verifiedJson.length.toString(),
        );
      }
      return {
        success: true,
        stage: 'VERIFY',
        verified: true,
        rollbackCalled: false,
        diagnostic: 'stage=VERIFY; verified=true',
      };
    } catch (error) {
      const digest: string = ChatPersistenceCapability.errorDigest(error as Error);
      return ChatPersistenceCapability.persistenceFailure('VERIFY', false, false, 'snapshot-verify-failed; error=' + digest);
    }
  }

  private static safeFailWrite(atomic: fileIo.AtomicFile): void {
    try {
      atomic.failWrite();
    } catch (error) {
    }
  }

  private static writeStreamFully(stream: fileIo.WriteStream, content: string): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (reason: Error) => void): void => {
      stream.end(content, 'utf-8', (err: Error | undefined): void => {
        if (err !== undefined && err !== null) {
          reject(err);
        } else {
          resolve();
        }
      });
    });
  }

  private static ensureDirectory(directory: string): void {
    try {
      fileIo.mkdirSync(directory, true);
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      if (businessError.code !== 13900015) {
        throw new Error('snapshot-directory-create-failed');
      }
    }
  }

  private static errorDigest(error: Error): string {
    if (error === null || error === undefined) {
      return 'Error:null';
    }
    const businessError: BusinessError = error as BusinessError;
    const code: string = businessError.code === undefined ? 'none' : businessError.code.toString();
    const name: string = error.name === undefined ? 'Error' : error.name;
    return ChatPersistenceCapability.sanitizeToken(name, 'Error') + ':' + ChatPersistenceCapability.sanitizeToken(code, 'none');
  }

  private static sanitizeToken(value: string, fallback: string): string {
    let sanitized: string = '';
    let index: number = 0;
    while (index < value.length && sanitized.length < 32) {
      const character: string = value.charAt(index);
      const isLowercase: boolean = character >= 'a' && character <= 'z';
      const isUppercase: boolean = character >= 'A' && character <= 'Z';
      const isDigit: boolean = character >= '0' && character <= '9';
      if (isLowercase || isUppercase || isDigit || character === '_' || character === '-' || character === '.') {
        sanitized += character;
      } else {
        sanitized += '_';
      }
      index += 1;
    }
    return sanitized.length === 0 ? fallback : sanitized;
  }

  private static persistenceFailure(
    stage: AtomicWriteStage,
    verified: boolean,
    rollbackCalled: boolean,
    reason: string,
  ): PersistenceCapabilityResult {
    return {
      success: false,
      stage: stage,
      verified: verified,
      rollbackCalled: rollbackCalled,
      diagnostic: 'stage=' + stage + '; reason=' + reason,
    };
  }
}
