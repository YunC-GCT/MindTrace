/**
 * LlmStreamEvents.test.ets — #111 StreamEvent parser and config regressions
 *
 * 路径: common/src/test/LlmStreamEvents.test.ets
 * 职责: 锁定 SSE delta 到结构化 StreamEvent 的 Seam A 回归行为
 * 依赖: @ohos/hypium; common LlmClient/LlmConfig/StreamEvent exports
 *
 * 数据流:
 *   fixture SSE payload → LlmClient.parseStreamEventsFromSseData → StreamEvent assertions
 *
 * ArkTS 1.1 strict 适配:
 *   - 测试 fixture 使用显式 string 常量和具名 StreamEvent 数组
 */
import { describe, it, expect } from '@ohos/hypium';
import { LlmClient, LlmConfig, DEFAULT_ENABLE_THINKING } from '../main/ets/Index';
import type { StreamEvent } from '../main/ets/Index';

const reasoningOnlyPayload: string = '{"id":"s1","object":"chat.completion.chunk","created":1,"model":"m","choices":[{"index":0,"delta":{"reasoning_content":"思考一","content":""},"finish_reason":null}]}';
const textOnlyPayload: string = '{"id":"s2","object":"chat.completion.chunk","created":1,"model":"m","choices":[{"index":0,"delta":{"content":"答案一","reasoning_content":null},"finish_reason":null}]}';
const bothPayload: string = '{"id":"s3","object":"chat.completion.chunk","created":1,"model":"m","choices":[{"index":0,"delta":{"reasoning_content":"先想","content":"再答"},"finish_reason":null}]}';
const nullDeltaPayload: string = '{"id":"s4","object":"chat.completion.chunk","created":1,"model":"m","choices":[{"index":0,"delta":null,"finish_reason":null}]}';
const emptyChoicesPayload: string = '{"id":"s5","object":"chat.completion.chunk","created":1,"model":"m","choices":[]}';

export default function llmStreamEventsTest(): void {
  describe('LlmStreamEvents.issue111_test', () => {
    it('defines_four_forward_compatible_event_categories', 0, () => {
      const events: StreamEvent[] = [
        { type: 'thinking', delta: '思考' },
        { type: 'text', delta: '回答' },
        { type: 'tool_call', delta: '' },
        { type: 'tool_result', delta: '' },
      ];
      expect(events.length).assertEqual(4);
      expect(events[0].type).assertEqual('thinking');
      expect(events[1].type).assertEqual('text');
      expect(events[2].type).assertEqual('tool_call');
      expect(events[3].type).assertEqual('tool_result');
    });

    it('maps_reasoning_only_payload_to_one_thinking_event', 0, () => {
      const events: StreamEvent[] = LlmClient.parseStreamEventsFromSseData(reasoningOnlyPayload);
      expect(events.length).assertEqual(1);
      expect(events[0].type).assertEqual('thinking');
      expect(events[0].delta).assertEqual('思考一');
    });

    it('maps_text_only_payload_to_one_text_event', 0, () => {
      const events: StreamEvent[] = LlmClient.parseStreamEventsFromSseData(textOnlyPayload);
      expect(events.length).assertEqual(1);
      expect(events[0].type).assertEqual('text');
      expect(events[0].delta).assertEqual('答案一');
    });

    it('emits_thinking_before_text_when_both_fields_exist', 0, () => {
      const events: StreamEvent[] = LlmClient.parseStreamEventsFromSseData(bothPayload);
      expect(events.length).assertEqual(2);
      expect(events[0].type).assertEqual('thinking');
      expect(events[0].delta).assertEqual('先想');
      expect(events[1].type).assertEqual('text');
      expect(events[1].delta).assertEqual('再答');
    });

    it('does_not_emit_text_fallback_for_reasoning_only_payload', 0, () => {
      const events: StreamEvent[] = LlmClient.parseStreamEventsFromSseData(reasoningOnlyPayload);
      let textCount: number = 0;
      let thinkingCount: number = 0;
      for (const event of events) {
        if (event.type === 'text') {
          textCount += 1;
        }
        if (event.type === 'thinking') {
          thinkingCount += 1;
        }
      }
      expect(thinkingCount).assertEqual(1);
      expect(textCount).assertEqual(0);
    });

    it('returns_no_events_for_null_delta_and_empty_choices', 0, () => {
      const nullDeltaEvents: StreamEvent[] = LlmClient.parseStreamEventsFromSseData(nullDeltaPayload);
      const emptyChoiceEvents: StreamEvent[] = LlmClient.parseStreamEventsFromSseData(emptyChoicesPayload);
      expect(nullDeltaEvents.length).assertEqual(0);
      expect(emptyChoiceEvents.length).assertEqual(0);
    });

    it('defaults_thinking_supply_to_enabled', 0, () => {
      expect(DEFAULT_ENABLE_THINKING).assertTrue();
      expect(LlmConfig.getInstance().getEnableThinking()).assertTrue();
    });
  });
}
