/**
 * ChatFilesDirSeam.test.ets — #121 chat filesDir context seam gate
 *
 * 路径: entry/src/test/ChatFilesDirSeam.test.ets
 * 职责: 验证应用级 filesDir 解析 seam、快照目录形状、blocked 语义、store 生命周期、
 *       collaborator 保留语义、诊断安全性以及 PASS/FAIL/INCOMPLETE gate 语义。
 * 数据流: ChatFilesDirSeam factories → shape helpers → seam store → ChatSessionManager retention
 * 依赖: @ohos/hypium; services/ChatFilesDirSeam; AgentFloatWindow chat/ChatSession + ChatModels
 *
 * ArkTS 1.1 strict 适配:
 *   - 无 any/unknown;对象字面量一律带显式类型;无解构;catch 变量不标注类型。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  ChatFilesDirSeam,
  ChatFilesDirSeamStore,
  publishChatFilesDirSeam,
  getChatFilesDirSeam,
  setChatFilesDirSeamStoreForTest,
  resetChatFilesDirSeamForTest,
} from '../main/ets/services/ChatFilesDirSeam';
import { ChatSessionManager } from '../main/ets/overlays/AgentFloatWindow/chat/ChatSession';
import { ChatSession } from '../main/ets/overlays/AgentFloatWindow/chat/ChatModels';

const SAMPLE_FILES_DIR: string = '/data/storage/el2/base/files';

type GateStatus = 'PASS' | 'FAIL' | 'INCOMPLETE';

interface GateSemantics {
  status: GateStatus;
  storageBranchEligible: boolean;
  preferencesFallbackAdopted: boolean;
  storageBranchBlocked: boolean;
  requiredText: string;
}

function gateSemantics(status: GateStatus): GateSemantics {
  if (status === 'PASS') {
    const semantics: GateSemantics = {
      status: status,
      storageBranchEligible: true,
      preferencesFallbackAdopted: false,
      storageBranchBlocked: false,
      requiredText: 'storage branch eligible for downstream design consideration only',
    };
    return semantics;
  }
  if (status === 'FAIL') {
    const semantics: GateSemantics = {
      status: status,
      storageBranchEligible: false,
      preferencesFallbackAdopted: false,
      storageBranchBlocked: true,
      requiredText: 'storage branch blocked; no Preferences fallback for the new storage design',
    };
    return semantics;
  }
  const semantics: GateSemantics = {
    status: status,
    storageBranchEligible: false,
    preferencesFallbackAdopted: false,
    storageBranchBlocked: true,
    requiredText: 'storage branch blocked until missing device/preview evidence is completed',
  };
  return semantics;
}

// 测试内存 fake: 单槽位 seam,模拟 AppStorage 的 publish/read 生命周期
class InMemorySeamStore implements ChatFilesDirSeamStore {
  private current: ChatFilesDirSeam | null = null;

  read(): ChatFilesDirSeam | null {
    return this.current;
  }

  write(seam: ChatFilesDirSeam): void {
    this.current = seam;
  }
}

export default function chatFilesDirSeamTest(): void {
  describe('ChatFilesDirSeam.issue121_shape_composition', () => {
    it('should compose the snapshot directory shape from the resolved filesDir', 0, () => {
      expect(ChatFilesDirSeam.snapshotDir(SAMPLE_FILES_DIR)).assertEqual(SAMPLE_FILES_DIR + '/chat-history');
    });

    it('should compose the snapshot file shape from the resolved filesDir', 0, () => {
      expect(ChatFilesDirSeam.snapshotFile(SAMPLE_FILES_DIR)).assertEqual(SAMPLE_FILES_DIR + '/chat-history/sessions.json');
    });

    it('should expose the fixed relative shape constant', 0, () => {
      expect(ChatFilesDirSeam.RELATIVE_SHAPE).assertEqual('chat-history/sessions.json');
    });

    it('should compose the snapshot file shape for a second sample filesDir', 0, () => {
      const other: string = '/data/app/el2/100/base/com.example.mathmind/haps/entry/files';
      expect(ChatFilesDirSeam.snapshotFile(other)).assertEqual(other + '/chat-history/sessions.json');
    });
  });

  describe('ChatFilesDirSeam.issue121_resolution_semantics', () => {
    it('should resolve a non-empty filesDir into the resolved state', 0, () => {
      const seam: ChatFilesDirSeam = ChatFilesDirSeam.fromFilesDir(SAMPLE_FILES_DIR);
      expect(seam.state).assertEqual('resolved');
      expect(seam.filesDir).assertEqual(SAMPLE_FILES_DIR);
    });

    it('should block an empty filesDir without fabricating a directory', 0, () => {
      const seam: ChatFilesDirSeam = ChatFilesDirSeam.fromFilesDir('');
      expect(seam.state).assertEqual('blocked');
      expect(seam.filesDir).assertEqual('');
    });

    it('should carry state and shape in the resolved diagnostic', 0, () => {
      const seam: ChatFilesDirSeam = ChatFilesDirSeam.fromFilesDir(SAMPLE_FILES_DIR);
      expect(seam.diagnostic).assertContain('resolved');
      expect(seam.diagnostic).assertContain(ChatFilesDirSeam.RELATIVE_SHAPE);
    });

    it('should carry state and intended relative shape in the blocked diagnostic', 0, () => {
      const seam: ChatFilesDirSeam = ChatFilesDirSeam.fromFilesDir('');
      expect(seam.diagnostic).assertContain('blocked');
      expect(seam.diagnostic).assertContain(ChatFilesDirSeam.RELATIVE_SHAPE);
    });
  });

  describe('ChatFilesDirSeam.issue121_store_lifecycle', () => {
    it('should roundtrip a published seam through read', 0, () => {
      resetChatFilesDirSeamForTest();
      setChatFilesDirSeamStoreForTest(new InMemorySeamStore());
      const seam: ChatFilesDirSeam = ChatFilesDirSeam.fromFilesDir(SAMPLE_FILES_DIR);
      publishChatFilesDirSeam(seam);
      const read: ChatFilesDirSeam | null = getChatFilesDirSeam();
      expect(read !== null).assertTrue();
      if (read !== null) {
        expect(read.state).assertEqual('resolved');
        expect(read.filesDir).assertEqual(SAMPLE_FILES_DIR);
        expect(read.diagnostic).assertEqual(seam.diagnostic);
      }
    });

    it('should return null when no seam has been published', 0, () => {
      resetChatFilesDirSeamForTest();
      setChatFilesDirSeamStoreForTest(new InMemorySeamStore());
      expect(getChatFilesDirSeam()).assertNull();
    });

    it('should overwrite the previous seam on republish', 0, () => {
      resetChatFilesDirSeamForTest();
      setChatFilesDirSeamStoreForTest(new InMemorySeamStore());
      const first: ChatFilesDirSeam = ChatFilesDirSeam.fromFilesDir(SAMPLE_FILES_DIR);
      const second: ChatFilesDirSeam = ChatFilesDirSeam.fromFilesDir('/data/storage/el2/base/recreated');
      publishChatFilesDirSeam(first);
      publishChatFilesDirSeam(second);
      const read: ChatFilesDirSeam | null = getChatFilesDirSeam();
      expect(read !== null).assertTrue();
      if (read !== null) {
        expect(read.filesDir).assertEqual('/data/storage/el2/base/recreated');
      }
    });
  });

  describe('ChatFilesDirSeam.issue121_collaborator_retention', () => {
    it('should start with no retained filesDir before recording', 0, () => {
      const manager: ChatSessionManager = new ChatSessionManager();
      expect(manager.hasFilesDir()).assertFalse();
      expect(manager.getResolvedSnapshotPath()).assertEqual('');
    });

    it('should retain the recorded filesDir and derive the snapshot path', 0, () => {
      const manager: ChatSessionManager = new ChatSessionManager();
      manager.recordFilesDir(SAMPLE_FILES_DIR);
      expect(manager.hasFilesDir()).assertTrue();
      expect(manager.getResolvedSnapshotPath()).assertEqual(ChatFilesDirSeam.snapshotFile(SAMPLE_FILES_DIR));
    });

    it('should replace the retained filesDir on re-record', 0, () => {
      const manager: ChatSessionManager = new ChatSessionManager();
      const other: string = '/data/storage/el2/base/recreated';
      manager.recordFilesDir(SAMPLE_FILES_DIR);
      manager.recordFilesDir(other);
      expect(manager.hasFilesDir()).assertTrue();
      expect(manager.getResolvedSnapshotPath()).assertEqual(ChatFilesDirSeam.snapshotFile(other));
    });

    it('should fall back to blocked when an empty filesDir is recorded', 0, () => {
      const manager: ChatSessionManager = new ChatSessionManager();
      manager.recordFilesDir(SAMPLE_FILES_DIR);
      manager.recordFilesDir('');
      expect(manager.hasFilesDir()).assertFalse();
      expect(manager.getResolvedSnapshotPath()).assertEqual('');
    });

    it('should neither throw nor touch the retained filesDir when save runs without init', 0, () => {
      const manager: ChatSessionManager = new ChatSessionManager();
      manager.recordFilesDir(SAMPLE_FILES_DIR);
      const sessions: ChatSession[] = [{ id: 's1', name: '会话 1', messages: [] }];
      manager.save(sessions);
      expect(manager.hasFilesDir()).assertTrue();
      expect(manager.getResolvedSnapshotPath()).assertEqual(ChatFilesDirSeam.snapshotFile(SAMPLE_FILES_DIR));
    });
  });

  describe('ChatFilesDirSeam.issue121_diagnostic_safety', () => {
    it('should never embed chat content, session names, reasoning, or API keys in the resolved diagnostic', 0, () => {
      const seam: ChatFilesDirSeam = ChatFilesDirSeam.fromFilesDir(SAMPLE_FILES_DIR);
      const adversarial: string[] = [
        '请帮我解这道二次函数的题',
        '高三数学复习计划',
        '首先分析已知条件，然后代入公式',
        'sk-abcdef1234567890',
      ];
      for (const candidate of adversarial) {
        expect(seam.diagnostic.indexOf(candidate) < 0).assertTrue();
      }
    });

    it('should never embed chat content, session names, reasoning, or API keys in the blocked diagnostic', 0, () => {
      const seam: ChatFilesDirSeam = ChatFilesDirSeam.fromFilesDir('');
      const adversarial: string[] = [
        '请帮我解这道二次函数的题',
        '高三数学复习计划',
        '首先分析已知条件，然后代入公式',
        'sk-abcdef1234567890',
      ];
      for (const candidate of adversarial) {
        expect(seam.diagnostic.indexOf(candidate) < 0).assertTrue();
      }
    });

    it('should build diagnostics from state and shape metadata only', 0, () => {
      const resolved: ChatFilesDirSeam = ChatFilesDirSeam.fromFilesDir(SAMPLE_FILES_DIR);
      const blocked: ChatFilesDirSeam = ChatFilesDirSeam.fromFilesDir('');
      expect(resolved.diagnostic).assertContain('seam=resolved');
      expect(resolved.diagnostic).assertContain('shape=' + ChatFilesDirSeam.RELATIVE_SHAPE);
      expect(blocked.diagnostic).assertContain('seam=blocked');
      expect(blocked.diagnostic).assertContain('shape=' + ChatFilesDirSeam.RELATIVE_SHAPE);
      expect(blocked.diagnostic).assertContain('unavailable');
    });

    it('should never leak adversarial content placed inside the filesDir path', 0, () => {
      const adversarialPath: string = '/data/请帮我解这道二次函数的题/sk-abcdef1234567890/高三数学复习计划/files';
      const seam: ChatFilesDirSeam = ChatFilesDirSeam.fromFilesDir(adversarialPath);
      expect(seam.state).assertEqual('resolved');
      expect(seam.diagnostic.indexOf('请帮我解这道二次函数的题') < 0).assertTrue();
      expect(seam.diagnostic.indexOf('sk-abcdef1234567890') < 0).assertTrue();
      expect(seam.diagnostic.indexOf('高三数学复习计划') < 0).assertTrue();
      expect(seam.diagnostic).assertEqual('seam=resolved; shape=' + ChatFilesDirSeam.RELATIVE_SHAPE);
    });
  });

  describe('ChatFilesDirSeam.issue121_gate_status_template', () => {
    it('should encode PASS semantics as eligible without Preferences fallback', 0, () => {
      const semantics: GateSemantics = gateSemantics('PASS');
      expect(semantics.storageBranchEligible).assertTrue();
      expect(semantics.preferencesFallbackAdopted).assertFalse();
      expect(semantics.storageBranchBlocked).assertFalse();
      expect(semantics.requiredText).assertContain('downstream design consideration only');
    });

    it('should encode FAIL semantics as blocked without Preferences fallback', 0, () => {
      const semantics: GateSemantics = gateSemantics('FAIL');
      expect(semantics.storageBranchEligible).assertFalse();
      expect(semantics.preferencesFallbackAdopted).assertFalse();
      expect(semantics.storageBranchBlocked).assertTrue();
      expect(semantics.requiredText).assertContain('no Preferences fallback');
    });

    it('should encode INCOMPLETE semantics as blocked pending device/preview evidence', 0, () => {
      const semantics: GateSemantics = gateSemantics('INCOMPLETE');
      expect(semantics.storageBranchEligible).assertFalse();
      expect(semantics.preferencesFallbackAdopted).assertFalse();
      expect(semantics.storageBranchBlocked).assertTrue();
      expect(semantics.requiredText).assertContain('missing device/preview evidence');
    });
  });
}
