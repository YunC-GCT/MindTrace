/**
 * ToolCallingStreamingWorkflow.ets — 流式工具循环（SSE + tool_calls）
 *
 * 路径: common/src/main/ets/workflow/tool-calling/ToolCallingStreamingWorkflow.ets
 * 职责: 与 ToolCallingWorkflow 同语义（call_model ↔ execute_tools，默认 4 轮），
 *       区别是每轮走 SSE 流式：文本增量经 onEvent 实时送出，tool_calls 增量在
 *       LlmClient 内拼好后返回；最终回答逐字到达 UI，而不是整包等待。
 * 依赖: LlmCaller、LlmTypes、ToolRegistry、ToolExecutionGuard、ToolResultBudget。
 *
 * 约束: 工具轮通常没有正文；若模型在工具轮输出了文本，也照常透传（作为进度文本）。
 */
import type { LlmCaller } from '../../llm/LlmGuard';
import { ChatMessage, LlmCallOptions, LlmCallRequest, LlmCallResult, LlmError,
  LlmStreamCallback, StreamEvent } from '../../llm/LlmTypes';
import { ToolRegistry } from '../../tools/ToolRegistry';
import { ToolLoopOptions } from './ToolCallingState';
import { ToolExecutionGuard } from './ToolExecutionGuard';
import { fitToolResult } from './ToolResultBudget';

const DEFAULT_MAX_STEPS: number = 4;
const TOOL_RESULT_MAX_CHARS: number = 4000;
const NOOP_SINK: LlmStreamCallback = (_event: StreamEvent): void => {};

export class ToolCallingStreamingWorkflow {
  private readonly llm: LlmCaller;
  private readonly registry: ToolRegistry;

  constructor(llm: LlmCaller, registry: ToolRegistry) {
    this.llm = llm;
    this.registry = registry;
  }

  async run(messages: ChatMessage[], options?: ToolLoopOptions,
    onEvent?: LlmStreamCallback): Promise<LlmCallResult> {
    const maxSteps: number = options !== undefined && options.maxSteps !== undefined
      ? options.maxSteps
      : DEFAULT_MAX_STEPS;
    if (maxSteps <= 0) {
      throw new LlmError('tool loop exceeded maxSteps=' + maxSteps.toString(), 'TOOL_LOOP_MAX_STEPS');
    }
    const sink: LlmStreamCallback = onEvent !== undefined ? onEvent : NOOP_SINK;
    const definitions = this.registry.listDefinitions();
    const current: ChatMessage[] = messages.slice(0);
    for (let step = 0; step < maxSteps; step += 1) {
      const request: LlmCallRequest = {
        messages: current,
        stream: true,
        onDelta: sink,
      };
      if (definitions.length > 0) {
        request.tools = definitions;
        request.tool_choice = 'auto';
      }
      if (options !== undefined && options.callOptions !== undefined) {
        ToolCallingStreamingWorkflow.copyCallOptions(request, options.callOptions);
      }
      const result: LlmCallResult = await this.llm.call(request);
      const toolCalls = result.toolCalls;
      if (toolCalls === undefined || toolCalls.length === 0) {
        return result;
      }
      const assistant: ChatMessage = {
        role: 'assistant',
        content: result.text !== undefined ? result.text : '',
        tool_calls: toolCalls,
      };
      current.push(assistant);
      for (let i = 0; i < toolCalls.length; i += 1) {
        const call = toolCalls[i];
        const callEvent: StreamEvent = {
          type: 'tool_call',
          delta: '',
          toolCallId: call.id,
          toolName: call.function.name,
          argumentsJson: call.function.arguments,
        };
        sink(callEvent);
        const startedAt: number = Date.now();
        const toolResult = await ToolExecutionGuard.execute(
          this.registry, call.function.name, call.function.arguments);
        const fitted = fitToolResult(toolResult.content, TOOL_RESULT_MAX_CHARS);
        console.info('[ToolLoop] tool name=' + call.function.name + ' ok=' + (toolResult.ok ? '1' : '0')
          + ' ms=' + (Date.now() - startedAt).toString()
          + ' chars=' + fitted.content.length.toString()
          + ' truncated=' + (fitted.truncated ? '1' : '0')
          + ' dropped=' + fitted.dropped.toString());
        const resultEvent: StreamEvent = {
          type: 'tool_result',
          delta: '',
          toolCallId: call.id,
          toolName: call.function.name,
          ok: toolResult.ok,
          result: fitted.content,
        };
        sink(resultEvent);
        const toolMessage: ChatMessage = {
          role: 'tool',
          content: fitted.content,
          tool_call_id: call.id,
        };
        current.push(toolMessage);
      }
    }
    throw new LlmError('tool loop exceeded maxSteps=' + maxSteps.toString(), 'TOOL_LOOP_MAX_STEPS');
  }

  private static copyCallOptions(request: LlmCallRequest, options: LlmCallOptions): void {
    if (options.temperature !== undefined) { request.temperature = options.temperature; }
    if (options.maxTokens !== undefined) { request.maxTokens = options.maxTokens; }
    if (options.model !== undefined) { request.model = options.model; }
    if (options.timeoutMs !== undefined) { request.timeoutMs = options.timeoutMs; }
    if (options.responseFormat !== undefined) { request.responseFormat = options.responseFormat; }
    if (options.enableThinking !== undefined) { request.enableThinking = options.enableThinking; }
    if (options.cancellationToken !== undefined) { request.cancellationToken = options.cancellationToken; }
  }
}
