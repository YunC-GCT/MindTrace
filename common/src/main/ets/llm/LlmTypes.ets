// MindTrace - LLM 共享类型定义
// 位置: common/src/main/ets/llm/LlmTypes.ets
// 责任: Z (Mavis)
// 创建: 2026-07-14 — 主 Agent 业务 LLM 调用基础设施
// 用途: LlmConfig + LlmClient 共享的类型,以及后续所有 agent 调 LLM 时的入参/出参
//
// 约束: ArkTS 1.1 严格语法
//   - 无 any / unknown
//   - 无 C 风格 for 循环
//   - 无 Record<string, T> 类型断言

// ==================== ChatMessage (单轮对话消息)====================
export interface ChatMessage {
  role: 'system' | 'user' | 'assistant' | 'tool';  // 'tool': 工具回喂消息 (spec 014)
  content: string;
  reasoning_content?: string;  // 推理模型
  tool_call_id?: string;       // role='tool' 时必填 (OpenAI 语义)
  tool_calls?: LlmToolCall[];  // assistant 消息携带的模型工具调用 (ToolLoop 回喂必需)
}

// ==================== LlmRequestBody (OpenAI 兼容请求体)====================
export interface LlmRequestBody {
  model: string;
  messages: ChatMessage[];
  temperature: number;
  max_tokens: number;
  stream: boolean;
  response_format?: LlmResponseFormat;
  thinking?: LlmThinkingConfig;   // DeepSeek 思考模式配置
  reasoning_effort?: string;      // 思考强度: "high" | "max"
  tools?: LlmToolDefinition[];    // OpenAI 兼容 function-calling (spec 014, 可选 → 向后兼容)
  tool_choice?: string;           // Phase 1 仅 'auto' | 'none'
}

export interface LlmThinkingConfig {
  type: 'enabled' | 'disabled';
}

export interface LlmResponseFormat {
  type: 'json_object';
}

// ==================== LlmResponse (OpenAI 兼容响应,只取常用字段)====================
export interface LlmResponseChoice {
  index: number;
  message: ChatMessage;
  finish_reason: string;
}

export interface LlmResponseUsage {
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
}

export interface LlmResponse {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: LlmResponseChoice[];
  usage?: LlmResponseUsage;
}

// ==================== LlmError (统一错误)====================
export type LlmErrorKind =
  | 'NO_API_KEY'        // 未配置 API key
  | 'NOT_INITIALIZED'   // LlmConfig 未 init
  | 'NETWORK_ERROR'     // 网络/HTTP 层失败
  | 'API_ERROR'         // API 返回非 2xx
  | 'PARSE_ERROR'       // 响应 JSON 解析失败
  | 'EMPTY_RESPONSE'    // 响应内容为空
  | 'TIMEOUT'           // 超时
  | 'STREAM_FAILED'     // 流式传输中断
  | 'PERSIST_ERROR'     // preferences 读写失败
  | 'NORMALIZE_KEYWORD_REJECTED' // LlmConfig 拒绝保留关键词
  | 'TOOL_LOOP_MAX_STEPS'       // ToolLoop 超过 maxSteps (spec 014)
  | 'TOOL_REGISTRY_ERROR';      // ToolRegistry 重名/命名非法注册 (spec 014)

export class LlmError extends Error {
  public kind: LlmErrorKind;

  constructor(message: string, kind: LlmErrorKind) {
    super(message);
    this.kind = kind;
    this.name = 'LlmError';
  }
}

// ==================== LlmConfigInitResult (init 返回)====================
export interface LlmConfigInitResult {
  ok: boolean;
  message: string;
}

// ==================== LlmStreamChunk (SSE 流式响应增量)====================
// DeepSeek / OpenAI 兼容的 SSE chunk 格式
// 流式响应中每个 chunk 的 delta 字段是增量文本,而非完整消息
export interface LlmStreamDelta {
  role?: 'assistant';
  content?: string;            // 正式回答的增量文本
  reasoning_content?: string;  // 思考模式的思维链增量文本
}

export interface LlmStreamChoice {
  index: number;
  delta: LlmStreamDelta;
  finish_reason: string | null;
}

export interface LlmStreamChunk {
  id: string;
  object: string;              // "chat.completion.chunk"
  created: number;
  model: string;
  choices: LlmStreamChoice[];
  usage?: LlmResponseUsage;    // 仅 stream_options.include_usage 时在最后 chunk 有值
}

// 流式回调: delta 为本次增量文本, kind 区分思考内容 / 正式回答
export type LlmStreamCallback = (delta: string, kind: 'reasoning' | 'content') => void;

// ==================== LlmCallOptions (单次调用可选参数)====================
export interface LlmCallOptions {
  // 不指定则用 LlmConfig 的默认配置
  temperature?: number;
  maxTokens?: number;
  model?: string;
  timeoutMs?: number;
  responseFormat?: LlmResponseFormat;
  // 流式专用
  enableThinking?: boolean;    // 是否启用思考模式 (DeepSeek thinking: {type: "enabled"})
}

// ==================== OpenAI 兼容 tool-calling wire 类型 (spec 014 / ADR-0012)====================
export interface LlmFunctionDefinition {
  name: string;                                   // ^[a-z][a-z0-9_]{0,63}$ (ToolRegistry 注册时校验)
  description: string;
  parameters: Record<string, Object>;             // JSON Schema 对象 (ArkTS 惯例, 同 LlmGuard)
}

export interface LlmToolDefinition {
  type: 'function';
  function: LlmFunctionDefinition;
}

// 响应侧: 模型发起的一次工具调用
export interface LlmFunctionCallNameArgs {
  name: string;
  arguments: string;                              // JSON 字符串
}

export interface LlmToolCall {
  id: string;
  type: 'function';
  function: LlmFunctionCallNameArgs;
}

// ==================== LlmCallRequest (统一调用入参, spec 005 / ADR-0004)====================
export interface LlmCallRequest {
  messages: ChatMessage[];
  // 流式开关: true 走 requestInStream SSE 适配路径, false (默认) 走 JSON request 适配路径
  stream?: boolean;
  // 流式回调 (stream=true 时必填), 每个 token 触发一次
  onDelta?: LlmStreamCallback;
  // 以下不指定则用 LlmConfig 的默认配置
  temperature?: number;
  maxTokens?: number;
  model?: string;
  timeoutMs?: number;
  responseFormat?: LlmResponseFormat;
  enableThinking?: boolean;
  tools?: LlmToolDefinition[];    // 透传 (spec 014)
  tool_choice?: string;           // 透传, Phase 1 仅 'auto' | 'none'
}

// ==================== LlmCallResult (统一调用出参, spec 005 / ADR-0004)====================
export interface LlmCallResult {
  // stream=false 时为完整回复文本; stream=true 时为 undefined (内容经 onDelta 交付)
  text?: string;
  // 本次调用是否为流式
  streamed: boolean;
  // JSON 路径: 响应携带的模型工具调用 (extractToolCalls 填充; 无工具调用时缺省)
  toolCalls?: LlmToolCall[];
}
