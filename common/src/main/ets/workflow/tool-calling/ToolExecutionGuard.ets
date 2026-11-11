/**
 * ToolExecutionGuard.ets — 工具执行的统一护栏（纯逻辑，无 Kit）
 *
 * 路径: common/src/main/ets/workflow/tool-calling/ToolExecutionGuard.ets
 * 职责: 单个工具执行带超时与异常隔离：超时/抛错都转成 ok:false 的 ToolResult，
 *       由调用方回喂模型，避免一个慢工具或坏工具中断整轮对话。
 * 依赖: ../../tools/ToolRegistry。
 */
import { ToolRegistry, ToolResult } from '../../tools/ToolRegistry';

export const TOOL_EXEC_TIMEOUT_MS: number = 8000;

export class ToolExecutionGuard {
  static async execute(registry: ToolRegistry, name: string, argsJson: string,
    timeoutMs: number = TOOL_EXEC_TIMEOUT_MS): Promise<ToolResult> {
    let timer: number = 0;
    const timeout: Promise<ToolResult> = new Promise<ToolResult>((resolve: (value: ToolResult) => void): void => {
      timer = setTimeout((): void => {
        const timedOut: ToolResult = {
          ok: false,
          content: 'tool timeout after ' + timeoutMs.toString() + 'ms',
        };
        resolve(timedOut);
      }, timeoutMs);
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
}
