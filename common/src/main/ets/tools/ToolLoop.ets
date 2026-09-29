// MindTrace - LLM 工具执行循环 (spec 014 / ADR-0012)
// 位置: common/src/main/ets/tools/ToolLoop.ets
// 职责: "模型请求工具 → registry 执行 → 结果回喂 → 继续对话" 的最小循环
//       (形状参考 Vercel AI SDK tool-loop / LangGraph ToolNode, 零依赖 — ADR-0008 设计不引运行时)
// seam: 构造注入 LlmCaller (复用 LlmGuard 模式 — 生产传 LlmClient, 测试传 mock)
// 约束: 仅 JSON 路径 (SSE 流式工具循环不在 spec 014); 禁止 import entry (拓扑红线)

import { LlmCaller } from '../llm/LlmGuard';
import { ChatMessage, LlmCallResult } from '../llm/LlmTypes';
import { ToolCallingWorkflow } from '../workflow/tool-calling/ToolCallingWorkflow';
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
}
