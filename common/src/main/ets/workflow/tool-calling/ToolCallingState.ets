import { ChatMessage, LlmCallOptions, LlmCallResult, LlmToolCall, LlmToolDefinition } from '../../llm/LlmTypes';

export type ToolCallingStep = 'START' | 'call_model' | 'execute_tools' | 'max_steps_error' | 'END';

export interface ToolLoopOptions {
  maxSteps?: number;
  callOptions?: LlmCallOptions;
}

export interface ToolCallingState {
  messages: ChatMessage[];
  definitions: LlmToolDefinition[];
  callOptions?: LlmCallOptions;
  maxSteps: number;
  stepCount: number;
  currentStep: ToolCallingStep;
  lastResult?: LlmCallResult;
  toolCalls?: LlmToolCall[];
}
