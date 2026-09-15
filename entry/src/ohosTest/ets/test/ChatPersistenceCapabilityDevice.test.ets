/**
 * ChatPersistenceCapabilityDevice.test.ets — ticket #122 真机持久化能力门禁
 *
 * 路径: entry/src/ohosTest/ets/test/ChatPersistenceCapabilityDevice.test.ets
 * 职责: 在 Instrument Test 真机环境使用真实 app-private filesDir 验证 TaskPool、Worker、AtomicFile 成功路径。
 * 依赖: @ohos/hypium; @kit.TestKit; @ohos.file.fs; test/ChatPersistenceCapability; main/ets/services/ChatFilesDirSeam。
 *
 * 数据流:
 *   UIAbility.context.filesDir → ChatFilesDirSeam → ChatPersistenceCapability → Hypium assertions
 *
 * ArkTS 1.1 strict 适配:
 *   - 测试 fake 使用显式 class/interface,不使用 any/unknown 或解构。
 */

import fileIo from '@ohos.file.fs';
import UIAbility from '@ohos.app.ability.UIAbility';
import { afterAll, describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import {
  ChatFilesDirSeam,
  ChatFilesDirSeamStore,
  resetChatFilesDirSeamForTest,
  setChatFilesDirSeamStoreForTest,
} from '../../../main/ets/services/ChatFilesDirSeam';
import {
  ChatPersistenceCapability,
  PersistenceCapabilityResult,
  SnapshotTaskInput,
  SnapshotTaskResult,
} from '../../../test/ChatPersistenceCapability';

const SAMPLE_SNAPSHOT: SnapshotTaskInput = {
  schemaVersion: 1,
  sessionsJson: '[{"id":"s1","name":"数学","messages":[{"id":1,"role":"ai","content":"答案","ts":1,"streaming":false}]}]',
};

let deviceFilesDir: string = '';

class DeviceChatFilesDirSeamStore implements ChatFilesDirSeamStore {
  private current: ChatFilesDirSeam | null = null;

  read(): ChatFilesDirSeam | null {
    return this.current;
  }

  write(seam: ChatFilesDirSeam): void {
    this.current = seam;
  }
}

async function publishDeviceFilesDir(): Promise<void> {
  const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
  deviceFilesDir = ability.context.filesDir;
  resetChatFilesDirSeamForTest();
  const store: DeviceChatFilesDirSeamStore = new DeviceChatFilesDirSeamStore();
  setChatFilesDirSeamStoreForTest(store);
  store.write(ChatFilesDirSeam.fromFilesDir(deviceFilesDir));
}

function cleanupDeviceSnapshot(): void {
  if (deviceFilesDir.length === 0) {
    return;
  }
  const snapshotDir: string = ChatFilesDirSeam.snapshotDir(deviceFilesDir);
  const snapshotFile: string = snapshotDir + '/ticket-122-capability.json';
  try {
    fileIo.unlinkSync(snapshotFile);
  } catch (error) {
  }
  try {
    fileIo.rmdirSync(snapshotDir);
  } catch (error) {
  }
}

function assertContentSafeDiagnostic(diagnostic: string): void {
  expect(diagnostic.indexOf('答案') < 0).assertTrue();
  expect(diagnostic.indexOf('数学') < 0).assertTrue();
}

export default function chatPersistenceCapabilityDeviceTest(): void {
  describe('ChatPersistenceCapability.issue122_device_gate', () => {
    afterAll((): void => {
      cleanupDeviceSnapshot();
      resetChatFilesDirSeamForTest();
    });

    it('should serialize a representative snapshot through TaskPool on device', 0, async () => {
      const result: SnapshotTaskResult = await ChatPersistenceCapability.serializeSnapshot(SAMPLE_SNAPSHOT);
      expect(result.success).assertTrue();
      expect(result.stage).assertEqual('VERIFY');
      expect(result.transport).assertEqual('taskpool');
      expect(result.snapshotInputLength).assertEqual(SAMPLE_SNAPSHOT.sessionsJson.length);
      assertContentSafeDiagnostic(result.diagnostic);
    });

    it('should verify Worker fallback protocol on device', 0, async () => {
      const result: SnapshotTaskResult = await ChatPersistenceCapability.verifyWorkerFallback(SAMPLE_SNAPSHOT);
      expect(result.diagnostic).assertEqual('transport=worker; stage=VERIFY; schemaVersion=1');
      expect(result.success).assertTrue();
      expect(result.stage).assertEqual('VERIFY');
      expect(result.transport).assertEqual('worker');
      assertContentSafeDiagnostic(result.diagnostic);
    });

    it('should commit and roll back AtomicFile in app-private filesDir on device', 0, async () => {
      await publishDeviceFilesDir();
      const commit: PersistenceCapabilityResult = await ChatPersistenceCapability.writeAtomicSnapshot(SAMPLE_SNAPSHOT);
      expect(commit.success).assertTrue();
      expect(commit.stage).assertEqual('VERIFY');
      expect(commit.verified).assertTrue();
      assertContentSafeDiagnostic(commit.diagnostic);

      const rollback: PersistenceCapabilityResult = await ChatPersistenceCapability.writeAtomicSnapshotWithInjectedWriteFailure(
        SAMPLE_SNAPSHOT,
      );
      expect(rollback.success).assertFalse();
      expect(rollback.stage).assertEqual('WRITE');
      expect(rollback.rollbackCalled).assertTrue();
      expect(rollback.diagnostic.indexOf('rolled-back-preserved') >= 0).assertTrue();
      assertContentSafeDiagnostic(rollback.diagnostic);
    });
  });
}
