/**
 * LlmResponseParser.ets — OpenAI compatible JSON response parser
 *
 * 路径: common/src/main/ets/llm/LlmResponseParser.ets
 * 职责: 将非流式 LLM JSON 响应转换为 LlmCallResult
 * 依赖: ./LlmTypes
 *
 * 数据流:
 *   LlmClient HTTP response → LlmResponseParser.buildCallResult → LlmCallResult
 *
 * ArkTS 1.1 strict 适配:
 *   - 响应对象与数组均使用显式类型
 */
import {
  ChatMessage,
  LlmResponse,
  LlmResponseChoice,
  LlmCallResult,
  LlmToolCall,
  LlmError,
} from './LlmTypes';

export const TRUNCATION_MARKER: string = '*(回复因长度限制被截断)*';

export class LlmResponseParser {
  public static buildCallResult(parsed: LlmResponse): LlmCallResult {
    const firstChoice: LlmResponseChoice | undefined = parsed.choices.length > 0 ? parsed.choices[0] : undefined;
    const isTruncated: boolean = firstChoice !== undefined && firstChoice.finish_reason === 'length';
    const toolCalls: LlmToolCall[] = LlmResponseParser.extractToolCalls(parsed);
    const result: LlmCallResult = { text: '', streamed: false };
    if (parsed.usage !== undefined) {
      result.usage = parsed.usage;
    }
    if (toolCalls.length > 0) {
      const first: LlmResponseChoice = parsed.choices[0];
      if (first.message !== undefined && first.message !== null && first.message.content !== undefined && first.message.content !== null) {
        result.text = first.message.content;
      }
      result.toolCalls = toolCalls;
    } else {
      result.text = LlmResponseParser.extractContent(parsed, isTruncated);
    }
    return result;
  }

  private static extractToolCalls(parsed: LlmResponse): LlmToolCall[] {
    if (parsed.choices.length === 0) {
      return [];
    }
    const message: ChatMessage | null = parsed.choices[0].message;
    if (message === undefined || message === null || message.tool_calls === undefined || message.tool_calls === null) {
      return [];
    }
    return message.tool_calls;
  }

  private static extractContent(parsed: LlmResponse, isTruncated: boolean): string {
    if (parsed.choices.length === 0) {
      throw new LlmError('LLM returned empty choices', 'EMPTY_RESPONSE');
    }
    const first: LlmResponseChoice = parsed.choices[0];
    if (first.message === undefined || first.message === null) {
      throw new LlmError('LLM returned empty message', 'EMPTY_RESPONSE');
    }
    const content: string = first.message.content;
    if (content === undefined || content === null || content.length === 0) {
      throw new LlmError('LLM returned empty content', 'EMPTY_RESPONSE');
    }
    return LlmResponseParser.formatTextResponse(content, isTruncated ? 'length' : first.finish_reason);
  }

  private static formatTextResponse(content: string, finishReason: string): string {
    if (finishReason !== 'length') {
      return content;
    }
    if (content.endsWith(TRUNCATION_MARKER)) {
      return content;
    }
    if (content.length === 0) {
      return TRUNCATION_MARKER;
    }
    return content + '\n\n' + TRUNCATION_MARKER;
  }
}
