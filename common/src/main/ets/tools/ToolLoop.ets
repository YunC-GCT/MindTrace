// MindTrace - LLM 工具执行循环 (spec 014 / ADR-0012 + 041 流式)
// 位置: common/src/main/ets/tools/ToolLoop.ets
// 职责: "模型请求工具 → registry 执行 → 结果回喂 → 继续对话" 的最小循环
//       (形状参考 Vercel AI SDK tool-loop / LangGraph ToolNode, 零依赖 — ADR-0008 设计不引运行时)
// seam: 构造注入 LlmCaller (复用 LlmGuard 模式 — 生产传 LlmClient, 测试传 mock)
// 路径: run = JSON；runStreaming = SSE（tool_calls 增量在 LlmClient 拼好后回喂）
// 约束: 禁止 import entry (拓扑红线)

import { LlmCaller } from '../llm/LlmGuard';
import { ChatMessage, LlmCallResult, LlmStreamCallback } from '../llm/LlmTypes';
import { ToolCallingWorkflow } from '../workflow/tool-calling/ToolCallingWorkflow';
import { ToolCallingStreamingWorkflow } from '../workflow/tool-calling/ToolCallingStreamingWorkflow';
import { ToolLoopOptions } from '../workflow/tool-calling/ToolCallingState';
import { ToolRegistry } from './ToolRegistry';

export class ToolLoop {
  private llm: LlmCaller;

  constructor(llm: LlmCaller) {
    this.llm = llm;
  }

  async run(messages: ChatMessage[], registry: ToolRegistry, options?: ToolLoopOptions): Promise<LlmCallResult> {
    const workflow: ToolCallingWorkflow = new ToolCallingWorkflow(this.llm, registry);
    return await workflow.run(messages, options);
  }

  /** 流式工具循环：最终回答逐字经 onEvent 送出，工具轮不带正文。 */
  async runStreaming(messages: ChatMessage[], registry: ToolRegistry, options?: ToolLoopOptions,
    onEvent?: LlmStreamCallback): Promise<LlmCallResult> {
    const workflow: ToolCallingStreamingWorkflow = new ToolCallingStreamingWorkflow(this.llm, registry);
    return await workflow.run(messages, options, onEvent);
  }
}
