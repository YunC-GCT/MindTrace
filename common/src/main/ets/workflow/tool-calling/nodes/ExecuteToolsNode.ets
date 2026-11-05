/**
 * ExecuteToolsNode.ets — 工具循环的执行节点
 *
 * 路径: common/src/main/ets/workflow/tool-calling/nodes/ExecuteToolsNode.ets
 * 职责: 执行模型返回的 tool_calls，把结果作为 role=tool 消息回喂；单个工具带超时与异常隔离，
 *       结果超出上限时截断，避免坏工具/慢工具中断整轮。
 * 依赖: ToolRegistry、LlmTypes、ToolCallingState、Logger。
 */
import { ChatMessage, LlmCallResult, LlmToolCall } from '../../../llm/LlmTypes';
import { ToolRegistry, ToolResult } from '../../../tools/ToolRegistry';
import { ToolCallingState } from '../ToolCallingState';
import { Logger } from '../../../utils/logger';

const TOOL_TIMEOUT_MS: number = 8000;
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
        const toolResult: ToolResult = await ExecuteToolsNode.executeGuarded(
          this.registry, call.function.name, call.function.arguments);
        const content: string = ExecuteToolsNode.truncate(toolResult.content);
        toolLog.info('tool name=' + call.function.name + ' ok=' + (toolResult.ok ? '1' : '0')
          + ' ms=' + (Date.now() - startedAt).toString() + ' chars=' + content.length.toString());
        const toolMessage: ChatMessage = {
          role: 'tool',
          content: content,
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

  /**
   * 工具执行护栏：单个工具超时或抛错都转成 ok:false 的 ToolResult 回喂模型，
   * 不让一个慢工具/坏工具中断整轮对话。
   */
  private static async executeGuarded(registry: ToolRegistry, name: string,
    argsJson: string): Promise<ToolResult> {
    let timer: number = 0;
    const timeout: Promise<ToolResult> = new Promise<ToolResult>((resolve: (value: ToolResult) => void): void => {
      timer = setTimeout((): void => {
        const timedOut: ToolResult = {
          ok: false,
          content: 'tool timeout after ' + TOOL_TIMEOUT_MS.toString() + 'ms',
        };
        resolve(timedOut);
      }, TOOL_TIMEOUT_MS);
    });
    try {
      return await Promise.race([registry.execute(name, argsJson), timeout]);
    } catch (e) {
      const failed: ToolResult = {
        ok: false,
        content: 'tool error: ' + ((e as Error).message ?? String(e)),
      };
      return failed;
    } finally {
      clearTimeout(timer);
    }
  }

  /** 工具结果截断：避免多轮工具调用把 prompt 撑爆。 */
  private static truncate(content: string): string {
    if (content.length <= TOOL_RESULT_MAX_CHARS) {
      return content;
    }
    return content.substring(0, TOOL_RESULT_MAX_CHARS) + '…[truncated]';
  }
}
