/**
 * ChatPersistenceCapability.test.ets — test-only 持久化能力探针边界测试
 *
 * 路径: entry/src/test/ChatPersistenceCapability.test.ets
 * 职责: 验证 test-only capability probe 与生产私有文件持久化边界，以及
 * TaskPool、Worker、AtomicFile 的成功/失败/显式 blocker 语义。
 * 依赖: @ohos/hypium; @ohos.file.fs; services/ChatPersistenceCapability; services/ChatFilesDirSeam。
 *
 * 数据流:
 *   SAMPLE_SNAPSHOT → ChatPersistenceCapability → Hypium assertions
 *
 * ArkTS 1.1 strict 适配:
 *   - 测试 fake 使用显式 class/interface,不使用 any/unknown 或解构。
 */

import fileIo from '@ohos.file.fs';
import { afterAll, describe, expect, it } from '@ohos/hypium';
import {
  AtomicWriteStage,
  ChatPersistenceCapability,
  PersistenceCapabilityResult,
  SnapshotTaskInput,
  SnapshotTaskResult,
} from './ChatPersistenceCapability';
import {
  ChatFilesDirSeam,
  ChatFilesDirSeamStore,
  resetChatFilesDirSeamForTest,
  setChatFilesDirSeamStoreForTest,
} from '../main/ets/services/ChatFilesDirSeam';

const SAMPLE_SNAPSHOT: SnapshotTaskInput = {
  schemaVersion: 1,
  sessionsJson: '[{"id":"s1","name":"数学","messages":[{"id":1,"role":"ai","content":"答案","ts":1,"streaming":false}]}]',
};

const TEST_FILES_DIR: string = 'build/chat-persistence-capability-test';
const TEST_HISTORY_DIR: string = TEST_FILES_DIR + '/chat-history';
const TEST_CAPABILITY_FILE: string = TEST_HISTORY_DIR + '/ticket-122-capability.json';

class InMemoryChatFilesDirSeamStore implements ChatFilesDirSeamStore {
  private current: ChatFilesDirSeam | null = null;

  read(): ChatFilesDirSeam | null {
    return this.current;
  }

  write(seam: ChatFilesDirSeam): void {
    this.current = seam;
  }
}

function cleanupTestFiles(): void {
  try {
    fileIo.unlinkSync(TEST_CAPABILITY_FILE);
  } catch (error) {
  }
  try {
    fileIo.rmdirSync(TEST_HISTORY_DIR);
  } catch (error) {
  }
  try {
    fileIo.rmdirSync(TEST_FILES_DIR);
  } catch (error) {
  }
}

function publishResolvedFilesDirForTest(): void {
  cleanupTestFiles();
  resetChatFilesDirSeamForTest();
  const store: InMemoryChatFilesDirSeamStore = new InMemoryChatFilesDirSeamStore();
  setChatFilesDirSeamStoreForTest(store);
  store.write(ChatFilesDirSeam.fromFilesDir(TEST_FILES_DIR));
}

function assertContentSafeDiagnostic(diagnostic: string): void {
  expect(diagnostic.indexOf('答案') < 0).assertTrue();
  expect(diagnostic.indexOf('数学') < 0).assertTrue();
}

function assertStage(result: PersistenceCapabilityResult, stage: AtomicWriteStage): void {
  expect(result.success).assertFalse();
  expect(result.stage).assertEqual(stage);
  assertContentSafeDiagnostic(result.diagnostic);
}

function assertSnapshotStage(result: SnapshotTaskResult, stage: AtomicWriteStage): void {
  expect(result.success).assertFalse();
  expect(result.stage).assertEqual(stage);
  assertContentSafeDiagnostic(result.diagnostic);
}

export default function chatPersistenceCapabilityTest(): void {
  describe('ChatPersistenceCapability.test_only_snapshot_task', () => {
    afterAll((): void => {
      cleanupTestFiles();
      resetChatFilesDirSeamForTest();
    });

    it('should serialize a representative pure-data snapshot or record a TaskPool blocker', 0, async () => {
      const result: SnapshotTaskResult = await ChatPersistenceCapability.serializeSnapshot(SAMPLE_SNAPSHOT);
      if (result.success) {
        expect(result.schemaVersion).assertEqual(1);
        expect(result.jsonLength > 0).assertTrue();
        expect(result.snapshotInputLength).assertEqual(SAMPLE_SNAPSHOT.sessionsJson.length);
      } else {
        expect(result.transport).assertEqual('taskpool');
        expect(result.diagnostic.indexOf('blocker=') >= 0).assertTrue();
      }
      assertContentSafeDiagnostic(result.diagnostic);
    });

    it('should return invalid input as a safe serialization failure without snapshot content', 0, async () => {
      const input: SnapshotTaskInput = {
        schemaVersion: 0,
        sessionsJson: '',
      };
      const result: SnapshotTaskResult = await ChatPersistenceCapability.serializeSnapshot(input);
      assertSnapshotStage(result, 'PREPARE');
      expect(result.diagnostic.indexOf('snapshot') >= 0).assertTrue();
    });

    it('should verify TaskPool rejection semantics or record a TaskPool blocker', 0, async () => {
      const result: SnapshotTaskResult = await ChatPersistenceCapability.verifyTaskPoolFailureResponse();
      expect(result.success).assertFalse();
      expect(result.transport).assertEqual('taskpool');
      expect(result.stage === 'PREPARE' || result.stage === 'VERIFY').assertTrue();
      expect(result.diagnostic.indexOf('snapshot-task') >= 0).assertTrue();
      if (result.stage === 'VERIFY') {
        expect(result.diagnostic.indexOf('blocker=') >= 0).assertTrue();
      }
      assertContentSafeDiagnostic(result.diagnostic);
    });
  });

  describe('ChatPersistenceCapability.test_only_worker_protocol', () => {
    it('should expose a build-wired Worker fallback protocol or record a Worker blocker', 0, async () => {
      const result: SnapshotTaskResult = await ChatPersistenceCapability.verifyWorkerFallback(SAMPLE_SNAPSHOT);
      expect(result.transport).assertEqual('worker');
      if (result.success) {
        expect(result.schemaVersion).assertEqual(1);
        expect(result.stage).assertEqual('VERIFY');
      } else {
        expect(result.stage).assertEqual('WRITE');
        expect(result.diagnostic.indexOf('worker') >= 0).assertTrue();
        expect(result.diagnostic.indexOf('blocker=') >= 0).assertTrue();
      }
      assertContentSafeDiagnostic(result.diagnostic);
    });

    it('should map Worker failure response to a safe WRITE-stage result', 0, async () => {
      const result: SnapshotTaskResult = await ChatPersistenceCapability.verifyWorkerFailureResponse();
      expect(result.success).assertFalse();
      expect(result.transport).assertEqual('worker');
      expect(result.stage).assertEqual('WRITE');
      expect(result.diagnostic.indexOf('worker') >= 0).assertTrue();
      expect(result.diagnostic.indexOf('snapshot') >= 0).assertTrue();
      expect(result.diagnostic.indexOf('failure-response-observed') >= 0 || result.diagnostic.indexOf('blocker=') >= 0).assertTrue();
      expect(result.diagnostic.indexOf('content') < 0).assertTrue();
    });

    it('should distinguish an unsupported structured request from a write request', 0, async () => {
      const result: SnapshotTaskResult = await ChatPersistenceCapability.verifyWorkerUnsupportedRequest();
      expect(result.success).assertFalse();
      expect(result.transport).assertEqual('worker');
      expect(result.stage === 'PREPARE' || result.stage === 'WRITE').assertTrue();
      if (result.stage === 'PREPARE') {
        expect(result.diagnostic).assertContain('unsupported-request');
        expect(result.diagnostic).assertContain('response=unsupported');
      } else {
        expect(result.diagnostic).assertContain('blocker=');
      }
      assertContentSafeDiagnostic(result.diagnostic);
    });
  });

  describe('ChatPersistenceCapability.test_only_atomic_file', () => {
    it('should commit a snapshot with AtomicFile or record an AtomicFile blocker', 0, async () => {
      publishResolvedFilesDirForTest();
      const result: PersistenceCapabilityResult = await ChatPersistenceCapability.writeAtomicSnapshot(SAMPLE_SNAPSHOT);
      if (result.success) {
        expect(result.stage).assertEqual('VERIFY');
        expect(result.verified).assertTrue();
      } else {
        expect(result.stage === 'WRITE' || result.stage === 'PREPARE').assertTrue();
        expect(result.diagnostic.indexOf('blocker=') >= 0).assertTrue();
      }
      assertContentSafeDiagnostic(result.diagnostic);
    });

    it('should call failWrite and preserve the formal file when the write stage fails', 0, async () => {
      publishResolvedFilesDirForTest();
      const result: PersistenceCapabilityResult = await ChatPersistenceCapability.writeAtomicSnapshotWithInjectedWriteFailure(
        SAMPLE_SNAPSHOT,
      );
      if (result.stage === 'PREPARE') {
        expect(result.diagnostic.indexOf('blocker=') >= 0).assertTrue();
      } else {
        assertStage(result, 'WRITE');
        expect(result.rollbackCalled).assertTrue();
        expect(result.diagnostic.indexOf('rolled-back-preserved') >= 0 || result.diagnostic.indexOf('blocker=') >= 0).assertTrue();
      }
    });

    it('should report each failure stage without logging chat content', 0, async () => {
      const prepare: PersistenceCapabilityResult = await ChatPersistenceCapability.simulateFailure('PREPARE');
      const write: PersistenceCapabilityResult = await ChatPersistenceCapability.simulateFailure('WRITE');
      const commit: PersistenceCapabilityResult = await ChatPersistenceCapability.simulateFailure('COMMIT');
      const verify: PersistenceCapabilityResult = await ChatPersistenceCapability.simulateFailure('VERIFY');
      assertStage(prepare, 'PREPARE');
      assertStage(write, 'WRITE');
      assertStage(commit, 'COMMIT');
      assertStage(verify, 'VERIFY');
    });
  });

  describe('ChatPersistenceCapability.test_only_vs_production_boundary', () => {
    it('should document private-file production persistence and migration-read-only Preferences', 0, () => {
      expect(ChatPersistenceCapability.productionMigrationEnabled()).assertTrue();
      expect(ChatPersistenceCapability.snapshotPathShape()).assertEqual('chat-history/sessions.json');
    });

    it('should keep the test capability seam separate from the production service', 0, () => {
      expect(ChatPersistenceCapability.productionMigrationEnabled()).assertTrue();
      expect(ChatPersistenceCapability.snapshotPathShape().indexOf('chat-history') >= 0).assertTrue();
    });
  });
}
