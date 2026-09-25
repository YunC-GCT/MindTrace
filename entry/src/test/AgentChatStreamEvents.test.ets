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
import {
  applyStreamEventToChatMsg,
  ChatMsg,
  chatItemKey,
  chatMessageReasoning,
  chatMessageRunParts,
  finishChatMsg,
  replaceChatMsgContent,
} from '../main/ets/overlays/AgentFloatWindow/chat/ChatModels';
import {
  AgentRunPart,
  appendAgentRunError,
  appendAgentRunStatus,
} from '../main/ets/overlays/AgentFloatWindow/chat/AgentRunModels';

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

    it('should replace streamed raw content with the normalized final answer', 0, () => {
      const streamed: ChatMsg = applyStreamEventToChatMsg(
        message('', '思考'),
        { type: 'text', delta: '\\item 可加性' },
      );
      const replaced: ChatMsg = replaceChatMsgContent(streamed, '- 可加性');
      const parts: AgentRunPart[] = chatMessageRunParts(replaced);
      expect(replaced.content).assertEqual('- 可加性');
      expect(chatMessageReasoning(replaced)).assertEqual('思考');
      expect(replaced.streaming).assertTrue();
      expect(parts.length).assertEqual(2);
      expect(parts[1].kind).assertEqual('answer');
      expect(parts[1].content).assertEqual('- 可加性');
      expect(streamed.content).assertEqual('\\item 可加性');
    });

    it('should keep thinking and text channels separated in order', 0, () => {
      const thinking: StreamEvent = { type: 'thinking', delta: '先想' };
      const text: StreamEvent = { type: 'text', delta: '再答' };
      const afterThinking: ChatMsg = applyStreamEventToChatMsg(message('', ''), thinking);
      const afterText: ChatMsg = applyStreamEventToChatMsg(afterThinking, text);
      expect(chatMessageReasoning(afterText)).assertEqual('先想');
      expect(afterText.content).assertEqual('再答');
    });

    it('should preserve legacy text while recording a tool call part', 0, () => {
      const event: StreamEvent = {
        type: 'tool_call',
        delta: '',
        toolCallId: 'call-1',
        toolName: 'note_query',
        argumentsJson: '{"keyword":"极限"}',
      };
      const result: ChatMsg = applyStreamEventToChatMsg(message('正文', '思考'), event);
      const parts: AgentRunPart[] = chatMessageRunParts(result);
      expect(chatMessageReasoning(result)).assertEqual('思考');
      expect(result.content).assertEqual('正文');
      expect(parts.length).assertEqual(3);
      expect(parts[2].kind).assertEqual('tool');
      expect(parts[2].toolCallId).assertEqual('call-1');
      expect(parts[2].status).assertEqual('running');
    });

    it('should accumulate thinking when legacy message has no reasoning', 0, () => {
      const event: StreamEvent = { type: 'thinking', delta: '补充思考' };
      const result: ChatMsg = applyStreamEventToChatMsg(legacyMessage('正文'), event);
      expect(chatMessageReasoning(result)).assertEqual('补充思考');
      expect(result.content).assertEqual('正文');
    });

    it('should keep thinking tool result rethinking and answer in event order', 0, () => {
      const thinkingOne: StreamEvent = { type: 'thinking', delta: '先分析问题' };
      const toolCall: StreamEvent = {
        type: 'tool_call',
        delta: '',
        toolCallId: 'call-2',
        toolName: 'note_query',
        argumentsJson: '{"keyword":"导数"}',
      };
      const toolResult: StreamEvent = {
        type: 'tool_result',
        delta: '',
        toolCallId: 'call-2',
        toolName: 'note_query',
        result: '找到 3 条笔记',
        ok: true,
      };
      const thinkingTwo: StreamEvent = { type: 'thinking', delta: '结合笔记继续判断' };
      const text: StreamEvent = { type: 'text', delta: '最终答案' };
      const one: ChatMsg = applyStreamEventToChatMsg(message('', ''), thinkingOne);
      const two: ChatMsg = applyStreamEventToChatMsg(one, toolCall);
      const three: ChatMsg = applyStreamEventToChatMsg(two, toolResult);
      const four: ChatMsg = applyStreamEventToChatMsg(three, thinkingTwo);
      const five: ChatMsg = applyStreamEventToChatMsg(four, text);
      const parts: AgentRunPart[] = chatMessageRunParts(five);
      expect(parts.length).assertEqual(4);
      expect(parts[0].kind).assertEqual('thinking');
      expect(parts[1].kind).assertEqual('tool');
      expect(parts[1].content).assertEqual('找到 3 条笔记');
      expect(parts[1].status).assertEqual('success');
      expect(parts[2].kind).assertEqual('thinking');
      expect(parts[3].kind).assertEqual('answer');
      expect(parts[3].content).assertEqual('最终答案');
    });

    it('should merge tool call and failure result by toolCallId', 0, () => {
      const call: StreamEvent = {
        type: 'tool_call',
        delta: '{"id":',
        toolCallId: 'call-3',
        toolName: 'note_get',
      };
      const callTail: StreamEvent = {
        type: 'tool_call',
        delta: '"missing"}',
        toolCallId: 'call-3',
      };
      const result: StreamEvent = {
        type: 'tool_result',
        delta: '',
        toolCallId: 'call-3',
        result: '笔记不存在',
        ok: false,
      };
      const afterCall: ChatMsg = applyStreamEventToChatMsg(message('', ''), call);
      const afterTail: ChatMsg = applyStreamEventToChatMsg(afterCall, callTail);
      const afterResult: ChatMsg = applyStreamEventToChatMsg(afterTail, result);
      const parts: AgentRunPart[] = chatMessageRunParts(afterResult);
      expect(parts.length).assertEqual(1);
      expect(parts[0].detail).assertEqual('{"id":"missing"}');
      expect(parts[0].content).assertEqual('笔记不存在');
      expect(parts[0].status).assertEqual('failed');
    });

    it('should project legacy fields and close active parts on finish', 0, () => {
      const legacy: ChatMsg = message('历史答案', '历史思考');
      const projected: AgentRunPart[] = chatMessageRunParts(legacy);
      expect(projected.length).assertEqual(2);
      expect(projected[0].kind).assertEqual('thinking');
      expect(projected[1].kind).assertEqual('answer');
      const finished: ChatMsg = finishChatMsg(legacy);
      const finishedParts: AgentRunPart[] = chatMessageRunParts(finished);
      expect(finished.streaming).assertFalse();
      expect(finishedParts[0].status).assertEqual('success');
      expect(finishedParts[1].status).assertEqual('success');
    });

    it('should reserve status and error steps for workflow lifecycle adapters', 0, () => {
      const statusParts: AgentRunPart[] = appendAgentRunStatus([], 11, '正在读取学习记录', 'running');
      const errorParts: AgentRunPart[] = appendAgentRunError(statusParts, 11, '读取学习记录失败');
      expect(errorParts.length).assertEqual(2);
      expect(errorParts[0].kind).assertEqual('status');
      expect(errorParts[0].status).assertEqual('success');
      expect(errorParts[1].kind).assertEqual('error');
      expect(errorParts[1].status).assertEqual('failed');
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
