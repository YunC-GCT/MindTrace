/**
 * AgentChatStreamEvents.test.ets — #111 StreamEvent -> ChatMsg dispatch regressions
 *
 * 路径: entry/src/test/AgentChatStreamEvents.test.ets
 * 职责: 锁定结构化流事件到 ChatMsg.reasoning/content 的 Seam B 分发行为
 * 依赖: @ohos/hypium; common StreamEvent; AgentFloatWindow chat models
 *
 * 数据流:
 *   StreamEvent fixture → applyStreamEventToChatMsg → ChatMsg assertions
 *
 * ArkTS 1.1 strict 适配:
 *   - ChatMsg fixture 使用显式返回类型和具名对象字面量上下文
 */
import { describe, it, expect } from '@ohos/hypium';
import type { StreamEvent } from 'common';
import { applyStreamEventToChatMsg, ChatMsg, chatItemKey, chatMessageReasoning } from '../main/ets/overlays/AgentFloatWindow/chat/ChatModels';

function message(content: string, reasoning: string): ChatMsg {
  const msg: ChatMsg = {
    id: 11,
    role: 'ai',
    content: content,
    ts: 100,
    streaming: true,
    reasoning: reasoning,
  };
  return msg;
}

function legacyMessage(content: string): ChatMsg {
  const msg: ChatMsg = {
    id: 11,
    role: 'ai',
    content: content,
    ts: 100,
    streaming: true,
  };
  return msg;
}

function collapsedMessage(content: string, reasoning: string): ChatMsg {
  const msg: ChatMsg = message(content, reasoning);
  msg.reasoningExpanded = false;
  return msg;
}

function expandedMessage(content: string, reasoning: string): ChatMsg {
  const msg: ChatMsg = message(content, reasoning);
  msg.reasoningExpanded = true;
  return msg;
}

function finishedMessage(content: string, reasoning: string): ChatMsg {
  const msg: ChatMsg = collapsedMessage(content, reasoning);
  msg.streaming = false;
  return msg;
}

export default function agentChatStreamEventsTest(): void {
  describe('AgentChatStreamEvents.issue111_test', () => {
    it('should accumulate thinking events into reasoning only', 0, () => {
      const event: StreamEvent = { type: 'thinking', delta: '推理' };
      const result: ChatMsg = applyStreamEventToChatMsg(message('', ''), event);
      expect(chatMessageReasoning(result)).assertEqual('推理');
      expect(result.content).assertEqual('');
    });

    it('should accumulate text events into content only', 0, () => {
      const event: StreamEvent = { type: 'text', delta: '答案' };
      const result: ChatMsg = applyStreamEventToChatMsg(message('', '已有思考'), event);
      expect(chatMessageReasoning(result)).assertEqual('已有思考');
      expect(result.content).assertEqual('答案');
    });

    it('should keep thinking and text channels separated in order', 0, () => {
      const thinking: StreamEvent = { type: 'thinking', delta: '先想' };
      const text: StreamEvent = { type: 'text', delta: '再答' };
      const afterThinking: ChatMsg = applyStreamEventToChatMsg(message('', ''), thinking);
      const afterText: ChatMsg = applyStreamEventToChatMsg(afterThinking, text);
      expect(chatMessageReasoning(afterText)).assertEqual('先想');
      expect(afterText.content).assertEqual('再答');
    });

    it('should ignore reserved tool events without mutating message text', 0, () => {
      const event: StreamEvent = { type: 'tool_call', delta: '' };
      const result: ChatMsg = applyStreamEventToChatMsg(message('正文', '思考'), event);
      expect(chatMessageReasoning(result)).assertEqual('思考');
      expect(result.content).assertEqual('正文');
    });

    it('should accumulate thinking when legacy message has no reasoning', 0, () => {
      const event: StreamEvent = { type: 'thinking', delta: '补充思考' };
      const result: ChatMsg = applyStreamEventToChatMsg(legacyMessage('正文'), event);
      expect(chatMessageReasoning(result)).assertEqual('补充思考');
      expect(result.content).assertEqual('正文');
    });
  });

  describe('AgentChatStreamEvents.issue112_key_test', () => {
    it('should change key when reasoning grows', 0, () => {
      const before: string = chatItemKey(collapsedMessage('', '思'));
      const after: string = chatItemKey(collapsedMessage('', '思考中'));
      expect(before !== after).assertTrue();
    });

    it('should keep key when reasoning expanded changes', 0, () => {
      const before: string = chatItemKey(collapsedMessage('', '思考'));
      const after: string = chatItemKey(expandedMessage('', '思考'));
      expect(before).assertEqual(after);
    });

    it('should change key when content or streaming changes', 0, () => {
      const base: string = chatItemKey(collapsedMessage('答', '思考'));
      const contentChanged: string = chatItemKey(collapsedMessage('答案', '思考'));
      const streamingChanged: string = chatItemKey(finishedMessage('答', '思考'));
      expect(base !== contentChanged).assertTrue();
      expect(base !== streamingChanged).assertTrue();
    });

    it('should treat missing legacy reasoning as empty for keys', 0, () => {
      const legacyKey: string = chatItemKey(legacyMessage('答'));
      const currentKey: string = chatItemKey(message('答', ''));
      expect(legacyKey).assertEqual(currentKey);
    });
  });
}
