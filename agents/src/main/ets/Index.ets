// agents HSP - public API 入口
// W1 块 3 逐步展开真实 export(HMAFManager + 5 子 Agent)

// 当前版本
//   v0.0.1 (2026-07-13 骨架)
//   v0.0.2 (2026-07-14 LLM 共享基础设施 LlmConfig/LlmClient)
//   v0.0.3 (2026-07-14 DispatchRequest.payload 升级 DispatchPayload discriminated union)
export const AGENTS_VERSION = 'v0.0.3';

// 主 Agent 调度中枢(Z)
export { Dispatcher } from './core/Dispatcher';
export { CaptureGraph } from './graph/CaptureGraph';
export type {
  AgentState,
  CaptureGraphError,
  CaptureNode,
  CaptureNodeResult,
  CaptureStep,
} from './graph/AgentState';
export type { CaptureGraphOptions } from './graph/CaptureGraph';

// 子 Agent(D 责任 - 写真实现,L 责任 - 写真实现)
//   当前为 stub,接 DispatchPayload discriminated union
//   D 接手: 替换 TypeClassifier.classify body
//   spec 015: KnowledgeModel 重构为轻量编排 agent, 常量/提示词/真值检查拆分为协作服务
export { TypeClassifier } from './agents/TypeClassifier';
export type { TypeClassifierTextResult } from './agents/TypeClassifier';
export { KnowledgeModel } from './agents/KnowledgeModel';
export { PromptBuilder } from './agents/PromptBuilder';
export { TruthCheckService } from './agents/TruthCheckService';
export { OcrTool } from './mcp/tools/OcrTool';
export type { OcrRecognitionResult } from './mcp/tools/OcrTool';

// 模型与扩展类型
export type { KnowledgeUnitExt, StructuredField, AiRawResponse } from './models/KnowledgeUnitExt';

// 持久化接口 (D2 Ticket #5: entry 通过该接口注入 NoteDao 实现)
export type { NoteDaoInterface } from './models/NoteDaoInterface';

// 重新导出 DispatchPayload 类型(定义在 common/models/CaptureChain.ets)
//   UI 端 (entry/) 可以 `import type { DispatchPayload } from 'agents'`
//   也可以从 'common' 拿,两种都行
export type { DispatchPayload } from 'common';
