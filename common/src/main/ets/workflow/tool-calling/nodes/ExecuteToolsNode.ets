import { ChatMessage, LlmCallResult, LlmToolCall } from '../../../llm/LlmTypes';
import { ToolRegistry, ToolResult } from '../../../tools/ToolRegistry';
import { ToolCallingState } from '../ToolCallingState';

export class ExecuteToolsNode {
  private readonly registry: ToolRegistry;

  constructor(registry: ToolRegistry) {
    this.registry = registry;
  }

  async run(input: ToolCallingState): Promise<ToolCallingState> {
    const messages: ChatMessage[] = input.messages.slice(0);
    const result: LlmCallResult | undefined = input.lastResult;
    const toolCalls: LlmToolCall[] | undefined = input.toolCalls;
    if (result !== undefined && toolCalls !== undefined && toolCalls.length > 0) {
      const assistantMessage: ChatMessage = {
        role: 'assistant',
        content: '',
        tool_calls: toolCalls,
      };
      messages.push(assistantMessage);
      for (const call of toolCalls) {
        const toolResult: ToolResult = await this.registry.execute(call.function.name, call.function.arguments);
        const toolMessage: ChatMessage = {
          role: 'tool',
          content: toolResult.content,
          tool_call_id: call.id,
        };
        messages.push(toolMessage);
      }
    }
    const next: ToolCallingState = {
      messages: messages,
      definitions: input.definitions,
      maxSteps: input.maxSteps,
      stepCount: input.stepCount,
      currentStep: 'execute_tools',
    };
    if (input.callOptions !== undefined) {
      next.callOptions = input.callOptions;
    }
    if (result !== undefined) {
      next.lastResult = result;
    }
    if (toolCalls !== undefined) {
      next.toolCalls = toolCalls;
    }
    return next;
  }
}
