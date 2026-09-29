import { LlmCaller } from '../../../llm/LlmGuard';
import { LlmCallOptions, LlmCallRequest, LlmCallResult } from '../../../llm/LlmTypes';
import { ToolCallingState } from '../ToolCallingState';

export class CallModelNode {
  private readonly llm: LlmCaller;

  constructor(llm: LlmCaller) {
    this.llm = llm;
  }

  async run(input: ToolCallingState): Promise<ToolCallingState> {
    const request: LlmCallRequest = { messages: input.messages };
    if (input.definitions.length > 0) {
      request.tools = input.definitions;
      request.tool_choice = 'auto';
    }
    if (input.callOptions !== undefined) {
      CallModelNode.copyCallOptions(request, input.callOptions);
    }
    const result: LlmCallResult = await this.llm.call(request);
    const next: ToolCallingState = {
      messages: input.messages,
      definitions: input.definitions,
      maxSteps: input.maxSteps,
      stepCount: input.stepCount + 1,
      currentStep: 'call_model',
      lastResult: result,
      toolCalls: result.toolCalls ?? [],
    };
    if (input.callOptions !== undefined) {
      next.callOptions = input.callOptions;
    }
    return next;
  }

  private static copyCallOptions(request: LlmCallRequest, options: LlmCallOptions): void {
    if (options.temperature !== undefined) { request.temperature = options.temperature; }
    if (options.maxTokens !== undefined) { request.maxTokens = options.maxTokens; }
    if (options.model !== undefined) { request.model = options.model; }
    if (options.timeoutMs !== undefined) { request.timeoutMs = options.timeoutMs; }
    if (options.responseFormat !== undefined) { request.responseFormat = options.responseFormat; }
    if (options.enableThinking !== undefined) { request.enableThinking = options.enableThinking; }
  }
}
