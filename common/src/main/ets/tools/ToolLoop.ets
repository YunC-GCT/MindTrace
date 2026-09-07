// MindTrace - LLM 工具执行循环 (spec 014 / ADR-0012)
// 位置: common/src/main/ets/tools/ToolLoop.ets
// 职责: "模型请求工具 → registry 执行 → 结果回喂 → 继续对话" 的最小循环
//       (形状参考 Vercel AI SDK tool-loop / LangGraph ToolNode, 零依赖 — ADR-0008 设计不引运行时)
// seam: 构造注入 LlmCaller (复用 LlmGuard 模式 — 生产传 LlmClient, 测试传 mock)
// 约束: 仅 JSON 路径 (SSE 流式工具循环不在 spec 014); 禁止 import entry (拓扑红线)

import { LlmCaller } from '../llm/LlmGuard';
import {
  ChatMessage,
  LlmCallOptions,
  LlmCallRequest,
  LlmCallResult,
  LlmError,
  LlmToolDefinition,
} from '../llm/LlmTypes';
import { ToolRegistry, ToolResult } from './ToolRegistry';

export interface ToolLoopOptions {
  maxSteps?: number;                 // 循环步数上限, 默认 4 — 防失控循环
  callOptions?: LlmCallOptions;      // 模型/超时等, 透传每步 LLM 调用
}

const DEFAULT_MAX_STEPS: number = 4;

export class ToolLoop {
  private llm: LlmCaller;

  constructor(llm: LlmCaller) {
    this.llm = llm;
  }

  async run(messages: ChatMessage[], registry: ToolRegistry, options?: ToolLoopOptions): Promise<LlmCallResult> {
    const maxSteps: number = options !== undefined && options.maxSteps !== undefined ? options.maxSteps : DEFAULT_MAX_STEPS;
    const working: ChatMessage[] = messages.slice(0);
    const definitions: LlmToolDefinition[] = registry.listDefinitions();
    let step: number = 0;
    while (step < maxSteps) {
      step++;
      const request: LlmCallRequest = { messages: working };
      if (definitions.length > 0) {
        request.tools = definitions;
        request.tool_choice = 'auto';
      }
      if (options !== undefined && options.callOptions !== undefined) {
        this.copyCallOptions(request, options.callOptions);
      }
      const result: LlmCallResult = await this.llm.call(request);
      if (result.toolCalls === undefined || result.toolCalls.length === 0) {
        return result;
      }
      // 回喂 assistant(tool_calls) 消息 — content 固定 '' (OpenAI 兼容端点接受空串)
      const assistantMsg: ChatMessage = { role: 'assistant', content: result.text ?? '', tool_calls: result.toolCalls };
      working.push(assistantMsg);
      for (const call of result.toolCalls) {
        const toolResult: ToolResult = await registry.execute(call.function.name, call.function.arguments);
        const toolMsg: ChatMessage = { role: 'tool', content: toolResult.content, tool_call_id: call.id };
        working.push(toolMsg);
      }
    }
    throw new LlmError('tool loop exceeded maxSteps=' + maxSteps.toString(), 'TOOL_LOOP_MAX_STEPS');
  }

  private copyCallOptions(request: LlmCallRequest, callOptions: LlmCallOptions): void {
    if (callOptions.temperature !== undefined) { request.temperature = callOptions.temperature; }
    if (callOptions.maxTokens !== undefined) { request.maxTokens = callOptions.maxTokens; }
    if (callOptions.model !== undefined) { request.model = callOptions.model; }
    if (callOptions.timeoutMs !== undefined) { request.timeoutMs = callOptions.timeoutMs; }
    if (callOptions.responseFormat !== undefined) { request.responseFormat = callOptions.responseFormat; }
    if (callOptions.enableThinking !== undefined) { request.enableThinking = callOptions.enableThinking; }
  }
}
