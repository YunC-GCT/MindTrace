// MindTrace - AgentTool 注册表 (spec 014 / ADR-0012)
// 位置: common/src/main/ets/tools/ToolRegistry.ets
// 职责: 统一工具面 — agents 管线 (ToolLoop) 与未来 skill/ IntentRouter (ADR-0011) 共享
// 约束: 只登记契约与容错执行, 不含具体业务工具 (P1 只读工具另落地); 禁止 import entry (拓扑红线)
//
// ArkTS 1.1 严格语法: 显式类型 / 无 spread / 无 untyped 对象字面量

import { LlmFunctionDefinition, LlmToolDefinition, LlmError } from '../llm/LlmTypes';

// 工具执行结果: content 以字符串回喂 LLM (ReAct 惯例), 失败时放错误说明而非抛异常
export interface ToolResult {
  ok: boolean;
  content: string;
}

// agent 可调用工具的最小契约: 名称 + 描述 + JSON Schema 参数 + 执行体
export interface AgentTool {
  name: string;
  description: string;
  parameters: Record<string, Object>;
  execute(args: Record<string, Object>): Promise<ToolResult>;
}

// 命名规则刻意严于 OpenAI wire 规则 ^[a-zA-Z0-9_-]{1,64}$ — 安全子集, 注册时拦截而非发送后被端点拒绝
const TOOL_NAME_PATTERN: RegExp = /^[a-z][a-z0-9_]{0,63}$/;

export class ToolRegistry {
  private toolMap: Map<string, AgentTool> = new Map<string, AgentTool>();
  private toolList: AgentTool[] = [];

  register(tool: AgentTool): void {
    if (this.toolMap.has(tool.name)) {
      throw new LlmError('duplicate tool registration: ' + tool.name, 'TOOL_REGISTRY_ERROR');
    }
    if (!TOOL_NAME_PATTERN.test(tool.name)) {
      throw new LlmError('invalid tool name: ' + tool.name, 'TOOL_REGISTRY_ERROR');
    }
    this.toolMap.set(tool.name, tool);
    this.toolList.push(tool);
  }

  has(name: string): boolean {
    return this.toolMap.has(name);
  }

  listDefinitions(): LlmToolDefinition[] {
    const defs: LlmToolDefinition[] = [];
    for (const tool of this.toolList) {
      const fn: LlmFunctionDefinition = { name: tool.name, description: tool.description, parameters: tool.parameters };
      const def: LlmToolDefinition = { type: 'function', function: fn };
      defs.push(def);
    }
    return defs;
  }

  // 容错执行: 未知工具 / 非法 JSON 参数都返回 ok:false (LLM 可能幻觉工具名), 不抛异常
  async execute(name: string, argsJson: string): Promise<ToolResult> {
    const tool: AgentTool | undefined = this.toolMap.get(name);
    if (tool === undefined) {
      const unknown: ToolResult = { ok: false, content: 'unknown tool: ' + name };
      return unknown;
    }
    let args: Record<string, Object>;
    try {
      const parsed: Object = JSON.parse(argsJson) as Object;
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        const nonObject: ToolResult = { ok: false, content: 'invalid tool arguments for ' + name + ': not a JSON object' };
        return nonObject;
      }
      args = parsed as Record<string, Object>;
    } catch (e) {
      const bad: ToolResult = { ok: false, content: 'invalid tool arguments for ' + name + ': ' + ((e as Error).message ?? String(e)) };
      return bad;
    }
    return await tool.execute(args);
  }
}
