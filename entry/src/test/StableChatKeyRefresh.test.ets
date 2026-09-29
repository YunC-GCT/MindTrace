/**
 * StableChatKeyRefresh.test.ets — #120 stable chat key refresh gate
 *
 * 路径: entry/src/test/StableChatKeyRefresh.test.ets
 * 职责: 验证 message-ID-only 候选身份下的 chat row 数据刷新契约与 gate 语义。
 * 数据流: ChatMsg fixture → candidateStableKey/StableObservedRow → gate status semantics
 * 依赖: @ohos/hypium; AgentFloatWindow ChatModels
 */
import { describe, it, expect } from '@ohos/hypium';
import { ChatMsg, chatMessageReasoning } from '../main/ets/overlays/AgentFloatWindow/chat/ChatModels';

class StableObservedRow {
  readonly stableKey: string;
  readonly answerText: string;
  readonly reasoningText: string;
  readonly streaming: boolean;
  readonly statusText: string;

  constructor(stableKey: string, message: ChatMsg) {
    this.stableKey = stableKey;
    this.answerText = message.content;
    this.reasoningText = chatMessageReasoning(message);
    this.streaming = message.streaming;
    this.statusText = message.streaming ? '生成中' : '已完成';
  }

  update(message: ChatMsg): StableObservedRow {
    return new StableObservedRow(this.stableKey, message);
  }
}

type GateStatus = 'PASS' | 'FAIL' | 'INCOMPLETE';

interface GateSemantics {
  status: GateStatus;
  stableKeyReleased: boolean;
  fallbackBranchReleased: boolean;
  downstreamBlocked: boolean;
  requiredText: string;
}

function candidateStableKey(message: ChatMsg): string {
  return message.id.toString();
}

function observeStableRow(message: ChatMsg): StableObservedRow {
  return new StableObservedRow(candidateStableKey(message), message);
}

function streamingMessage(content: string, reasoning: string): ChatMsg {
  const msg: ChatMsg = {
    id: 120,
    role: 'ai',
    content: content,
    ts: 1200,
    streaming: true,
    reasoning: reasoning,
  };
  return msg;
}

function legacyStreamingMessage(content: string): ChatMsg {
  const msg: ChatMsg = {
    id: 120,
    role: 'ai',
    content: content,
    ts: 1200,
    streaming: true,
  };
  return msg;
}

function finishedMessage(content: string, reasoning: string): ChatMsg {
  const msg: ChatMsg = streamingMessage(content, reasoning);
  msg.streaming = false;
  return msg;
}

function gateSemantics(status: GateStatus): GateSemantics {
  if (status === 'PASS') {
    const semantics: GateSemantics = {
      status: status,
      stableKeyReleased: true,
      fallbackBranchReleased: false,
      downstreamBlocked: false,
      requiredText: 'stable-key branch released for downstream design consideration only',
    };
    return semantics;
  }
  if (status === 'FAIL') {
    const semantics: GateSemantics = {
      status: status,
      stableKeyReleased: false,
      fallbackBranchReleased: true,
      downstreamBlocked: false,
      requiredText: 'temporary id + streaming fallback branch and downstream impact recorded',
    };
    return semantics;
  }
  const semantics: GateSemantics = {
    status: status,
    stableKeyReleased: false,
    fallbackBranchReleased: false,
    downstreamBlocked: true,
    requiredText: 'stable-key gate not released and downstream assumptions blocked',
  };
  return semantics;
}

export default function stableChatKeyRefreshTest(): void {
  describe('StableChatKeyRefresh.issue120_stable_key_contract', () => {
    it('should define candidate stable key as message ID only', 0, () => {
      const before: ChatMsg = streamingMessage('', '');
      const after: ChatMsg = streamingMessage('答案增长', '');
      expect(candidateStableKey(before)).assertEqual('120');
      expect(candidateStableKey(before)).assertEqual(candidateStableKey(after));
    });

    it('should keep stable key unchanged when answer grows', 0, () => {
      const before: ChatMsg = streamingMessage('', '已有思考');
      const after: ChatMsg = streamingMessage('答案增长', '已有思考');
      expect(candidateStableKey(before)).assertEqual(candidateStableKey(after));
    });

    it('should keep stable key unchanged when reasoning grows', 0, () => {
      const before: ChatMsg = streamingMessage('', '思');
      const after: ChatMsg = streamingMessage('', '思考增长');
      expect(candidateStableKey(before)).assertEqual(candidateStableKey(after));
    });

    it('should keep stable key unchanged when streaming finishes', 0, () => {
      const before: ChatMsg = streamingMessage('答案', '思考');
      const after: ChatMsg = finishedMessage('答案', '思考');
      expect(candidateStableKey(before)).assertEqual(candidateStableKey(after));
    });
  });

  describe('StableChatKeyRefresh.issue120_observed_row_contract', () => {
    it('should observe answer text growth on the same stable row identity', 0, () => {
      const before: ChatMsg = streamingMessage('', '已有思考');
      const after: ChatMsg = streamingMessage('答案增长', '已有思考');
      const beforeRow: StableObservedRow = observeStableRow(before);
      const afterRow: StableObservedRow = beforeRow.update(after);
      expect(beforeRow.stableKey).assertEqual(afterRow.stableKey);
      expect(afterRow.answerText).assertEqual('答案增长');
      expect(afterRow.reasoningText).assertEqual('已有思考');
    });

    it('should observe reasoning text growth on the same stable row identity', 0, () => {
      const before: ChatMsg = legacyStreamingMessage('答案');
      const after: ChatMsg = streamingMessage('答案', '新增思考');
      const beforeRow: StableObservedRow = observeStableRow(before);
      const afterRow: StableObservedRow = beforeRow.update(after);
      expect(beforeRow.stableKey).assertEqual(afterRow.stableKey);
      expect(beforeRow.reasoningText).assertEqual('');
      expect(afterRow.reasoningText).assertEqual('新增思考');
      expect(afterRow.answerText).assertEqual('答案');
    });

    it('should observe streaming-to-finished status on the same stable row identity', 0, () => {
      const before: ChatMsg = streamingMessage('答案', '思考');
      const after: ChatMsg = finishedMessage('答案', '思考');
      const beforeRow: StableObservedRow = observeStableRow(before);
      const afterRow: StableObservedRow = beforeRow.update(after);
      expect(beforeRow.stableKey).assertEqual(afterRow.stableKey);
      expect(beforeRow.streaming).assertTrue();
      expect(afterRow.streaming).assertFalse();
      expect(afterRow.statusText).assertEqual('已完成');
    });
  });

  describe('StableChatKeyRefresh.issue120_gate_status_template', () => {
    it('should encode PASS semantics without changing production key', 0, () => {
      const semantics: GateSemantics = gateSemantics('PASS');
      expect(semantics.stableKeyReleased).assertTrue();
      expect(semantics.fallbackBranchReleased).assertFalse();
      expect(semantics.downstreamBlocked).assertFalse();
      expect(semantics.requiredText).assertContain('downstream design consideration only');
    });

    it('should encode FAIL semantics with id + streaming fallback', 0, () => {
      const semantics: GateSemantics = gateSemantics('FAIL');
      expect(semantics.stableKeyReleased).assertFalse();
      expect(semantics.fallbackBranchReleased).assertTrue();
      expect(semantics.downstreamBlocked).assertFalse();
      expect(semantics.requiredText).assertContain('id + streaming fallback');
    });

    it('should encode INCOMPLETE semantics as blocked without fallback release', 0, () => {
      const semantics: GateSemantics = gateSemantics('INCOMPLETE');
      expect(semantics.stableKeyReleased).assertFalse();
      expect(semantics.fallbackBranchReleased).assertFalse();
      expect(semantics.downstreamBlocked).assertTrue();
      expect(semantics.requiredText).assertContain('downstream assumptions blocked');
    });
  });
}
