// AgentChatStreamEvents.test.ets — #111 StreamEvent -> ChatMsg dispatch regressions
// Seam B: structured stream events update ChatMsg.reasoning and ChatMsg.content separately.
import { describe, it, expect } from '@ohos/hypium';
import type { StreamEvent } from 'common';
import { applyStreamEventToChatMsg } from '../main/ets/services/AgentChatService';
import { ChatMsg } from '../main/ets/overlays/AgentFloatWindow/chat/ChatModels';

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

export default function agentChatStreamEventsTest(): void {
  describe('AgentChatStreamEvents.issue111_test', () => {
    it('accumulates_thinking_events_into_reasoning_only', 0, () => {
      const event: StreamEvent = { type: 'thinking', delta: '推理' };
      const result: ChatMsg = applyStreamEventToChatMsg(message('', ''), event);
      expect(result.reasoning).assertEqual('推理');
      expect(result.content).assertEqual('');
    });

    it('accumulates_text_events_into_content_only', 0, () => {
      const event: StreamEvent = { type: 'text', delta: '答案' };
      const result: ChatMsg = applyStreamEventToChatMsg(message('', '已有思考'), event);
      expect(result.reasoning).assertEqual('已有思考');
      expect(result.content).assertEqual('答案');
    });

    it('keeps_thinking_and_text_channels_separated_in_order', 0, () => {
      const thinking: StreamEvent = { type: 'thinking', delta: '先想' };
      const text: StreamEvent = { type: 'text', delta: '再答' };
      const afterThinking: ChatMsg = applyStreamEventToChatMsg(message('', ''), thinking);
      const afterText: ChatMsg = applyStreamEventToChatMsg(afterThinking, text);
      expect(afterText.reasoning).assertEqual('先想');
      expect(afterText.content).assertEqual('再答');
    });

    it('ignores_reserved_tool_events_without_mutating_message_text', 0, () => {
      const event: StreamEvent = { type: 'tool_call', delta: '' };
      const result: ChatMsg = applyStreamEventToChatMsg(message('正文', '思考'), event);
      expect(result.reasoning).assertEqual('思考');
      expect(result.content).assertEqual('正文');
    });
  });
}
