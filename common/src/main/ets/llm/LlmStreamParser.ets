/**
 * LlmStreamParser.ets — SSE chunk → 结构化流式事件（纯函数，无 Kit）
 *
 * 路径: common/src/main/ets/llm/LlmStreamParser.ets
 * 职责: 解析单条 `data: {...}` SSE payload，产出 thinking / text / tool_call 事件。
 *       tool_calls 在流式响应里按 index 分片到达，这里原样转成事件，由调用方拼接。
 * 依赖: ./LlmTypes、./LlmResponseParser（截断标记）。
 *
 * 约束: JSON 不完整时抛异常，交由 LlmClient 的行缓冲放回重试。
 */
import { LlmStreamChoice, LlmStreamChunk, LlmStreamDelta, LlmStreamToolCallDelta, StreamEvent,
  StreamToolCallEvent } from './LlmTypes';
import { TRUNCATION_MARKER } from './LlmResponseParser';

export function parseStreamEventsFromSseData(dataStr: string): StreamEvent[] {
  const chunk: LlmStreamChunk = JSON.parse(dataStr) as LlmStreamChunk;
  if (chunk.choices.length === 0) {
    return [];
  }
  const events: StreamEvent[] = [];
  const choice: LlmStreamChoice = chunk.choices[0];
  const delta: LlmStreamDelta | null = choice.delta;
  if (delta !== undefined && delta !== null) {
    const reasoning: string = delta.reasoning_content ?? '';
    if (reasoning.length > 0) {
      const thinkingEvent: StreamEvent = { type: 'thinking', delta: reasoning };
      events.push(thinkingEvent);
    }
    const content: string = delta.content ?? '';
    if (content.length > 0) {
      const textEvent: StreamEvent = { type: 'text', delta: content };
      events.push(textEvent);
    }
    const toolCalls: LlmStreamToolCallDelta[] | undefined = delta.tool_calls;
    if (toolCalls !== undefined) {
      for (let i = 0; i < toolCalls.length; i += 1) {
        const call: LlmStreamToolCallDelta = toolCalls[i];
        const fragment: string = call.function !== undefined && call.function.arguments !== undefined
          ? call.function.arguments
          : '';
        const toolEvent: StreamToolCallEvent = {
          type: 'tool_call',
          delta: fragment,
          argumentsJson: fragment,
          index: call.index !== undefined ? call.index : 0,
        };
        if (call.id !== undefined) {
          toolEvent.toolCallId = call.id;
        }
        if (call.function !== undefined && call.function.name !== undefined) {
          toolEvent.toolName = call.function.name;
        }
        events.push(toolEvent);
      }
    }
  }
  if (choice.finish_reason === 'length') {
    const truncationEvent: StreamEvent = { type: 'text', delta: '\n\n' + TRUNCATION_MARKER };
    events.push(truncationEvent);
  }
  return events;
}
