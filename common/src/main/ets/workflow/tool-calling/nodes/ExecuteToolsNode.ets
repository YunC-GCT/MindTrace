/**
 * ExecuteToolsNode.ets — 工具循环的执行节点
 *
 * 路径: common/src/main/ets/workflow/tool-calling/nodes/ExecuteToolsNode.ets
 * 职责: 执行模型返回的 tool_calls，把结果作为 role=tool 消息回喂；单个工具带超时与异常隔离，
 *       结果按预算裁剪（JSON 结构优先保留），避免坏工具/慢工具中断整轮或撑爆 prompt。
 * 依赖: ToolRegistry、LlmTypes、ToolCallingState、ToolExecutionGuard、ToolResultBudget、Logger。
 */
import { ChatMessage, LlmCallResult, LlmToolCall } from '../../../llm/LlmTypes';
import { ToolRegistry, ToolResult } from '../../../tools/ToolRegistry';
import { ToolCallingState } from '../ToolCallingState';
import { ToolExecutionGuard } from '../ToolExecutionGuard';
import { fitToolResult, ToolBudgetResult } from '../ToolResultBudget';
import { Logger } from '../../../utils/logger';

const TOOL_RESULT_MAX_CHARS: number = 4000;
const toolLog: Logger = new Logger('ToolLoop');

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
        const startedAt: number = Date.now();
        const toolResult: ToolResult = await ToolExecutionGuard.execute(
          this.registry, call.function.name, call.function.arguments);
        const fitted: ToolBudgetResult = fitToolResult(toolResult.content, TOOL_RESULT_MAX_CHARS);
        toolLog.info('tool name=' + call.function.name + ' ok=' + (toolResult.ok ? '1' : '0')
          + ' ms=' + (Date.now() - startedAt).toString()
          + ' chars=' + fitted.content.length.toString()
          + ' truncated=' + (fitted.truncated ? '1' : '0')
          + ' dropped=' + fitted.dropped.toString());
        const toolMessage: ChatMessage = {
          role: 'tool',
          content: fitted.content,
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
