# MindTrace Tool Layer & Per-Agent Patterns

> **Date**: 2026-09-16
> **Scope**: ① 工具调用面 (ToolRegistry / ToolLoop / LLM wire / MCP) 的完整拓扑;② 10 个核心 agent/workflow 的设计模式判定 (ReAct / Reflexion / Plan-Execute / Router / Pipeline …)。
> **方法**: 仅引用代码 + 已存 docs/ADR/spec, 全部论断 `path:LINE`。
> **关系**: 与 [`capturegraph-architecture-evolution-2026-09-16.md`](./capturegraph-architecture-evolution-2026-09-16.md) §5 (CaptureGraph) / §6 (兄弟 workflow) 互补 — 那是 "图运行机制", 本文档是 "工具面 + 模式标签"。
> **作者备注**: 6 类候选模式标签见 §0.1; §4 列出 doc 与 code 的 drift (含 ToolLoop 零生产消费方)。

---

## 0. 前置约定

### 0.1 模式标签词典 (8 种, 用于 §2-§3)

| 标签 | 核心特征 | MindTrace 中典型代表 |
|---|---|---|
| **ReAct** | 思考↔工具交错循环, 终止条件由 LLM 决策 + 上限共同决定 | ToolCallingWorkflow |
| **Reflexion** | 校验失败→修复→重试, 自我批评驱动 | KnowledgeModel.repair* |
| **Plan-and-Execute** | 计划→子任务→执行 | KnowledgeModel.structureStandardDraft (含 outline/evidence/draft 三阶段) |
| **Router / Classifier** | 输入路由到固定分支 | SkillIntentWorkflow; ConversationWorkflow (kind/intent 分流) |
| **Single-shot LLM call** | 一次 LLM 调用, 无循环, 无记忆 | TypeClassifier.classifyText |
| **Multi-turn chat with state** | 记忆 + 流式 + 意图切换 | ConversationWorkflow |
| **Pure function** | 无 LLM, 无状态机 | TruthCheckService; PromptBuilder |
| **Pipeline / DAG orchestration** | 静态节点 + 条件边 + haltWhen | CaptureGraph (Capture pipeline) |

### 0.2 阅读路径

接后端新人 (15 分钟): §1.3 (一张图看完整工具面) → §2 速读 (§2 表格) → §3 (矩阵) → §4 (drift)。

---

## 1. Tool layer architecture

### 1.1 全景图 (一张图看完整工具面)

```
                                          ┌───────────────────────────────┐
                                          │       LLM provider            │
                                          │  (DeepSeek / Qwen via OpenAI) │
                                          └──────────────┬────────────────┘
                                                         │ wire:
                                                         │ - tools: LlmToolDefinition[]
                                                         │ - tool_choice: 'auto'|'none'
                                                         │ - tool_calls: LlmToolCall[]
                                                         ▼
                          ┌──────────────────────────────────────────────────┐
                          │ common/src/main/ets/llm/                        │
                          │   LlmClient.call (60-70)  ◄── 唯一入口          │
                          │     ├─ callJsonInternal (74-167)               │
                          │     │     └─ body.tools (106-108)              │
                          │     │     └─ LlmResponseParser.buildCallResult │
                          │     │           └─ extractToolCalls (46-55)    │
                          │     └─ callStreamInternal (216-402)            │
                          │           └─ parseStreamEventsFromSseData (497)│
                          │              ⚠️ 暂未 emit tool_call/tool_result │
                          │              (StreamEvent 4 类型已定义)        │
                          └──────────────┬───────────────────────────────────┘
                                         │ LlmCallResult { text, toolCalls?, streamed }
                                         ▼
   ┌─────────────────────────────────────────────────────────────────────────┐
   │ Tool-calling workflow (spec 014 / 018)                                 │
   │ common/src/main/ets/workflow/tool-calling/                             │
   │                                                                         │
   │  ToolLoop.run (ToolLoop.ets:21-24)                                     │
   │     └─► ToolCallingWorkflow.run (ToolCallingWorkflow.ets:22-45)        │
   │           └─► StateGraph.run (maxSteps*3+4 默认)                      │
   │                ├─ call_model (CallModelNode.ets:12-35)                 │
   │                │     request.tools=defs, request.tool_choice='auto'    │
   │                ├─ execute_tools (ExecuteToolsNode.ets:12-50)           │
   │                │     registry.execute(name, argsJson) → ToolResult    │
   │                └─ max_steps_error 抛 LlmError 'TOOL_LOOP_MAX_STEPS'   │
   └─────────────────────────────────┬───────────────────────────────────────┘
                                         │
                                         ▼
                          ┌──────────────────────────────┐
                          │ common/src/main/ets/tools/   │
                          │   ToolRegistry               │
                          │   ToolCatalog (factory)      │
                          │   NoteQueryTools (P1)        │
                          │     • NoteQueryTool          │
                          │     • NoteGetTool            │
                          │     • ReviewDueQueryTool     │
                          └──────────────────────────────┘

  ┌─────────────────────────┐                ┌─────────────────────────────────┐
  │ agents/src/main/ets/mcp/ │                │ skill/  小艺意图               │
  │   tools/OcrTool.ets      │  direct call   │  SkillAbility.handleWant       │
  │   (MCP 语义, ADR-0010)   │  from          │   → ToolCatalog                │
  │   不实现 AgentTool       │  TypeClassifier│     .createReadOnlyRegistry()   │
  │   不注册进 ToolRegistry  │  .extractText  │   → SkillIntentWorkflow.run    │
  └─────────────────────────┘  (140-148)     │     → registry.execute         │
                                              │       ('note_query', ...)      │
                                              └─────────────────────────────────┘
```

### 1.2 ToolRegistry — 注册中心 (spec 014 / ADR-0012)

**位置**: `common/src/main/ets/tools/ToolRegistry.ets:1-77` (77 LOC)

**公共表面**:

```ts
// ToolRegistry.ets:11-14  — ToolResult: 回喂 LLM 的字符串 (ReAct 惯例)
export interface ToolResult { ok: boolean; content: string; }

// ToolRegistry.ets:17-22  — AgentTool 最小契约
export interface AgentTool {
  name: string;                                // ^[a-z][a-z0-9_]{0,63}$ 注册时校验
  description: string;
  parameters: Record<string, Object>;          // JSON Schema 对象
  execute(args: Record<string, Object>): Promise<ToolResult>;
}

// ToolRegistry.ets:25      — 命名规则严于 OpenAI wire (安全子集)
const TOOL_NAME_PATTERN: RegExp = /^[a-z][a-z0-9_]{0,63}$/;

// ToolRegistry.ets:27-76  — 4 公开方法
export class ToolRegistry {
  register(tool: AgentTool): void;             // :31 重名 / 非法名 → LlmError('TOOL_REGISTRY_ERROR')
  has(name: string): boolean;                  // :42
  listDefinitions(): LlmToolDefinition[];      // :46-54 → 转 {type:'function', function:{name,description,parameters}}
  execute(name: string, argsJson: string): Promise<ToolResult>;  // :57-76 容错: 未知工具/坏 JSON → ok:false, 不抛
}
```

**关键设计**:
- **容错执行** (`:57-76`): 未知工具名 → `{ok:false, content:'unknown tool: '+name}`; JSON.parse 失败 → `{ok:false, content:'invalid tool arguments...'}`; 不抛异常 — 因为 LLM 可能幻觉出未注册名。
- **注册时校验命名** (`:35-37`): 不合法 `^[a-z][a-z0-9_]{0,63}$` 抛 `LlmError(kind='TOOL_REGISTRY_ERROR')`, 防发送后被 OpenAI 端点拒绝。

**生产消费方** (4 处):
| 调用方 | file:line | 用途 |
|---|---|---|
| `ToolCallingWorkflow` | `common/src/main/ets/workflow/tool-calling/ToolCallingWorkflow.ets:3, 12, 16-20` | 构造时注入, 由 `buildGraph` 初始化 `definitions` (`:31`) |
| `ExecuteToolsNode` | `common/src/main/ets/workflow/tool-calling/nodes/ExecuteToolsNode.ets:2, 6, 8, 24` | 构造时注入, `run` 中按 `call.function.name` 执行 |
| `SkillAbility` | `skill/src/main/ets/skillability/SkillAbility.ets:2, 27` | 通过 `ToolCatalog.createReadOnlyRegistry()` 取得, 转发给 SkillIntentWorkflow |
| `SkillIntentWorkflow` | `skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets:1, 5, 7, 38` | 注入后**只**对 `'note_query'` 直接 `registry.execute` (`:38`), 不走 LLM |

> **DRIFT 提示**: spec 018 §1 ([`docs/specs/018-agent-workflow-architecture.md:44`](../specs/018-agent-workflow-architecture.md)) 列 Tool-calling 入口 = `ToolLoop.run`; **全仓生产代码无 ToolLoop 调用** (grep `new ToolLoop` 仅命中测试 `common/src/test/LlmToolCalling.test.ets:128,148,164,185` 与构建缓存)。**唯一真实工具消费方是 skill/ 的 SearchNote**, 详见 §4。

### 1.3 ToolCatalog — 只读工具目录工厂

**位置**: `common/src/main/ets/tools/ToolCatalog.ets:1-27` (27 LOC)

```ts
// ToolCatalog.ets:18-26
export class ToolCatalog {
  static createReadOnlyRegistry(): ToolRegistry {  // :19
    const registry: ToolRegistry = new ToolRegistry();
    const tools: AgentTool[] = createReadOnlyNoteTools();  // 来自 NoteQueryTools.ets:250
    for (const tool of tools) {
      registry.register(tool);
    }
    return registry;
  }
}
```

- **静态工厂**而非构造器 (`:19` 注释明示 "便于 ArkTS Hypium seam 测试注入", `docs/specs/014-tool-calling-protocol.md:11-13`)。
- **唯一调用方**: `SkillAbility.ets:27` (生产)。ToolCallingWorkflow 的设计意图 ("common 工具面两消费方") 当前只对 skill 落地。

### 1.4 ToolLoop — 工具循环外壳

**位置**: `common/src/main/ets/tools/ToolLoop.ets:1-25` (25 LOC)

```ts
// ToolLoop.ets:14-24
export class ToolLoop {
  private llm: LlmCaller;
  constructor(llm: LlmCaller) { this.llm = llm; }
  async run(messages: ChatMessage[], registry: ToolRegistry, options?: ToolLoopOptions): Promise<LlmCallResult> {
    const workflow: ToolCallingWorkflow = new ToolCallingWorkflow(this.llm, registry);  // :22
    return await workflow.run(messages, options);  // :23
  }
}
```

- **25 行薄壳**, 内部完全委托给 `ToolCallingWorkflow`。
- **公开稳定入口** (spec 018 §3 "ToolLoop 是 workflow, 不是 Tool, 也不是单个 Node") — 但**生产消费方为零** (见 §1.2 末尾)。这是 §4 的核心 drift 之一。
- 注释 `ToolLoop.ets:6` 明说 "仅 JSON 路径 (SSE 流式工具循环不在 spec 014)"。

### 1.5 ToolCallingWorkflow — StateGraph 风格显式 workflow

**位置**: `common/src/main/ets/workflow/tool-calling/ToolCallingWorkflow.ets:1-69` (69 LOC)

#### 1.5.1 State shape

`common/src/main/ets/workflow/tool-calling/ToolCallingState.ets:10-19`:

```ts
export interface ToolCallingState {
  messages: ChatMessage[];
  definitions: LlmToolDefinition[];
  callOptions?: LlmCallOptions;
  maxSteps: number;
  stepCount: number;
  currentStep: ToolCallingStep;     // :3 = 'START' | 'call_model' | 'execute_tools' | 'max_steps_error' | 'END'
  lastResult?: LlmCallResult;
  toolCalls?: LlmToolCall[];
}
```

对齐 spec 018 §3 "至少包含 messages、step count、max steps、last result 和 tool calls" ([`docs/specs/018-agent-workflow-architecture.md:61`](../specs/018-agent-workflow-architecture.md))。

#### 1.5.2 `run` 与终止条件

```ts
// ToolCallingWorkflow.ets:9      — 默认上限
const DEFAULT_MAX_STEPS: number = 4;

// ToolCallingWorkflow.ets:22-45
async run(messages: ChatMessage[], options?: ToolLoopOptions): Promise<LlmCallResult> {
  const maxSteps = options?.maxSteps ?? DEFAULT_MAX_STEPS;
  if (maxSteps <= 0) {
    throw new LlmError('tool loop exceeded maxSteps=' + maxSteps, 'TOOL_LOOP_MAX_STEPS');  // :27
  }
  const initial: ToolCallingState = {
    messages: messages.slice(0),
    definitions: this.registry.listDefinitions(),  // :31
    maxSteps, stepCount: 0, currentStep: 'START',
  };
  // 关键: graph.run 上限是 maxSteps*3+4, 给底层 StateGraph 充足余地
  const finalState = await this.buildGraph().run(initial, maxSteps * 3 + 4);  // :40
  if (finalState.lastResult === undefined) {
    throw new LlmError('tool workflow produced no result', 'EMPTY_RESPONSE');  // :42
  }
  return finalState.lastResult;  // :44
}
```

#### 1.5.3 图拓扑 (3 节点 + 4 边)

`ToolCallingWorkflow.ets:47-68`:

| 节点 / 边 | file:line | 行为 |
|---|---|---|
| `START → call_model` | `:56` | 必走 |
| `call_model` | `:50` | 调 LLM, 把 `result.toolCalls` 写入 state |
| `call_model → execute_tools` (cond) | `:57-62` | `state.toolCalls` 非空 → `execute_tools`; 空 → `END` |
| `execute_tools` | `:51-52` | 追加 `assistant(tool_calls, content:'')` + 逐 call `registry.execute` + `tool(tool_call_id, content)` 消息 |
| `execute_tools → call_model` 或 `max_steps_error` (cond) | `:63-65` | `stepCount >= maxSteps` → `max_steps_error`; 否则回 `call_model` |
| `max_steps_error` | `:53-55` | 抛 `LlmError(kind='TOOL_LOOP_MAX_STEPS')` |
| `max_steps_error → END` | `:66` | 直接终结 |

**关键 `stopWhen` 语义**: 终止由两个谓词 + 上限组成 — ① `toolCalls` 为空 (LLM 决策 "无需工具") → 自然 END; ② `stepCount >= maxSteps` → 抛错 (ReAct 失控防护)。

#### 1.5.4 节点实现

**CallModelNode** `common/src/main/ets/workflow/tool-calling/nodes/CallModelNode.ets:1-45`:

```ts
// CallModelNode.ets:12-35
async run(input: ToolCallingState): Promise<ToolCallingState> {
  const request: LlmCallRequest = { messages: input.messages };
  if (input.definitions.length > 0) {
    request.tools = input.definitions;             // :15
    request.tool_choice = 'auto';                  // :16
  }
  if (input.callOptions !== undefined) {
    CallModelNode.copyCallOptions(request, input.callOptions);  // :19
  }
  const result: LlmCallResult = await this.llm.call(request);  // :21 — 走 LlmGuard 同款 LlmCaller seam
  const next: ToolCallingState = { ...input, currentStep: 'call_model',
    stepCount: input.stepCount + 1,                // :26 — 每次 +1
    lastResult: result,
    toolCalls: result.toolCalls ?? [],             // :29
  };
  return next;
}
```

**ExecuteToolsNode** `common/src/main/ets/workflow/tool-calling/nodes/ExecuteToolsNode.ets:1-51`:

```ts
// ExecuteToolsNode.ets:12-50
async run(input: ToolCallingState): Promise<ToolCallingState> {
  const messages = input.messages.slice(0);
  const result = input.lastResult;
  const toolCalls = input.toolCalls;
  if (result !== undefined && toolCalls !== undefined && toolCalls.length > 0) {
    messages.push({ role: 'assistant', content: '', tool_calls: toolCalls });  // :17-22
    for (const call of toolCalls) {
      const toolResult: ToolResult = await this.registry.execute(call.function.name, call.function.arguments);  // :24
      messages.push({ role: 'tool', content: toolResult.content, tool_call_id: call.id });  // :25-30
    }
  }
  // 注意: ExecuteToolsNode 不增 stepCount (CallModelNode 已增), :37 直接复制
  const next = { ...input, messages, currentStep: 'execute_tools' };
  return next;
}
```

### 1.6 Tool-calling wire 协议 (spec 014 / ADR-0012)

**位置**: `common/src/main/ets/llm/LlmTypes.ets`

#### 1.6.1 请求侧 (5 字段增量, 全可选, 向后兼容)

```ts
// LlmTypes.ets:13-19 — ChatMessage
export interface ChatMessage {
  role: 'system' | 'user' | 'assistant' | 'tool';   // :14 加 'tool'
  content: string;
  reasoning_content?: string;
  tool_call_id?: string;                            // :17 role='tool' 必填
  tool_calls?: LlmToolCall[];                       // :18 assistant 携带工具调用 (ToolLoop 回喂必需)
}

// LlmTypes.ets:22-34 — LlmRequestBody (OpenAI 兼容)
export interface LlmRequestBody {
  model: string; messages: ChatMessage[];
  temperature?: number; max_tokens: number; stream: boolean;
  response_format?: LlmResponseFormat;
  enable_thinking?: boolean;
  thinking?: LlmThinkingConfig;
  reasoning_effort?: string;
  tools?: LlmToolDefinition[];                      // :32 spec 014 可选 → 向后兼容
  tool_choice?: string;                             // :33 Phase 1 仅 'auto' | 'none'
}

// LlmTypes.ets:175-185 — 工具定义形状
export interface LlmFunctionDefinition {            // :176
  name: string;                                     // ^[a-z][a-z0-9_]{0,63}$
  description: string;
  parameters: Record<string, Object>;               // JSON Schema
}
export interface LlmToolDefinition {                // :182
  type: 'function';
  function: LlmFunctionDefinition;
}

// LlmTypes.ets:200-215 — 统一调用入参 (透传)
export interface LlmCallRequest {
  messages: ChatMessage[]; stream?: boolean; onDelta?: LlmStreamCallback;
  temperature?: number; maxTokens?: number; model?: string; timeoutMs?: number;
  responseFormat?: LlmResponseFormat; enableThinking?: boolean;
  tools?: LlmToolDefinition[];                      // :213 透传 (spec 014)
  tool_choice?: string;                             // :214 透传
}

// LlmTypes.ets:218-225 — 统一调用出参
export interface LlmCallResult {
  text?: string;
  streamed: boolean;
  toolCalls?: LlmToolCall[];                        // :224 由 extractToolCalls 填充; 无调用时缺省
  usage?: LlmResponseUsage;
}

// LlmTypes.ets:85-86 — 新增错误种类
| 'TOOL_LOOP_MAX_STEPS'       // spec 014
| 'TOOL_REGISTRY_ERROR';      // spec 014
```

#### 1.6.2 响应侧 — `extractToolCalls`

**位置**: `common/src/main/ets/llm/LlmResponseParser.ets:46-55`

```ts
// LlmResponseParser.ets:46-55
private static extractToolCalls(parsed: LlmResponse): LlmToolCall[] {
  if (parsed.choices.length === 0) { return []; }
  const message: ChatMessage | null = parsed.choices[0].message;
  if (message === undefined || message === null
      || message.tool_calls === undefined || message.tool_calls === null) {
    return [];
  }
  return message.tool_calls;
}
```

**关键设计**: **不依赖 `finish_reason`** (spec 014 §1.51 行注释)。OpenAI 兼容端点在该字段上行为有差异 (有些填 `'tool_calls'`, 有些填 `'stop'` 但 `message.tool_calls` 非空), 一律以 `message.tool_calls` 非空为准。

### 1.7 工具面 → LlmClient → LLM provider 的接线

**位置**: `common/src/main/ets/llm/LlmClient.ets:60-167` (JSON 路径)

#### 1.7.1 唯一公共入口 `call`

```ts
// LlmClient.ets:60-70
public async call(request: LlmCallRequest): Promise<LlmCallResult> {
  if (request.stream === true) {
    if (request.onDelta === undefined) {
      throw new LlmError('call: stream=true requires onDelta callback', 'STREAM_FAILED');  // :63
    }
    await this.callStreamInternal(request, request.onDelta);  // :65
    return { streamed: true };                                // :66
  }
  return await this.callJsonInternal(request);               // :69
}
```

#### 1.7.2 JSON 路径透传 `tools` / `tool_choice`

```ts
// LlmClient.ets:106-111
if (request.tools !== undefined) {
  body.tools = request.tools;                    // :107
}
if (request.tool_choice !== undefined) {
  body.tool_choice = request.tool_choice;        // :110
}
```

调用方最终解析走 `LlmResponseParser.buildCallResult` (`LlmResponseParser.ets:26-44`):

```ts
// LlmResponseParser.ets:26-44
public static buildCallResult(parsed: LlmResponse): LlmCallResult {
  const toolCalls: LlmToolCall[] = LlmResponseParser.extractToolCalls(parsed);  // :29
  const result: LlmCallResult = { text: '', streamed: false };
  if (toolCalls.length > 0) {
    if (first.message.content !== undefined && first.message.content !== null) {
      result.text = first.message.content;        // :37 — tool_calls 与 content 可共存
    }
    result.toolCalls = toolCalls;                // :39
  } else {
    result.text = LlmResponseParser.extractContent(parsed, isTruncated);
  }
  return result;
}
```

#### 1.7.3 SSE 流式路径 — tool_call/tool_result 事件占位但未 emit

`LlmClient.ets:216-402` (`callStreamInternal`) 走 `requestInStream` + 行缓冲。事件类型 `StreamEvent` (`LlmTypes.ets:129-158`) 已**定义** 4 种:

```ts
// LlmTypes.ets:129
export type StreamEventType = 'thinking' | 'text' | 'tool_call' | 'tool_result';
```

但 `parseStreamEventsFromSseData` (`LlmClient.ets:497-522`) **当前只 emit `thinking` 与 `text`**, tool_call / tool_result 路径未实现:

```ts
// LlmClient.ets:506-515
const reasoning: string = delta.reasoning_content ?? '';
if (reasoning.length > 0) { /* emit thinking */ }
const content: string = delta.content ?? '';
if (content.length > 0) { /* emit text */ }
// tool_calls / tool_result 不在当前 emit 范围 — spec 014 §"Out of scope" 明确
//   "流式 (SSE) 工具循环" 不在 scope
```

→ 结论: **SSE + 工具循环 = 空白**, 当前 ToolLoop 仅走 JSON 路径 (`ToolLoop.ets:6` 注释 + `CallModelNode.ets:21` 走 `LlmCaller.call` 非流式分支)。

### 1.8 P1 只读工具实现 (NoteQueryTools)

**位置**: `common/src/main/ets/tools/NoteQueryTools.ets:1-253` (253 LOC, 3 工具)

| 工具类 | file:line | name | 描述 | 关键 SQL/查询 |
|---|---|---|---|---|
| `NoteQueryTool` | `:50-126` | `note_query` | 按 subject / review_status / keyword 过滤, 上限 20 条 | `relationalStore.RdbPredicates` + `contains('title', kw) or contains('content', kw)` (`:89-94`) |
| `NoteGetTool` | `:129-193` | `note_get` | 按 id 取单条 + 完整 content | `equalTo('id', id)` + 全字段 SELECT (`:157`) |
| `ReviewDueQueryTool` | `:196-247` | `review_due_query` | 按 ReviewStatus 聚合计数 | `SELECT review_status, COUNT(*) GROUP BY review_status` (`:232`) |

**注册工厂**: `NoteQueryTools.ets:250-253`

```ts
export function createReadOnlyNoteTools(): AgentTool[] {
  const tools: AgentTool[] = [new NoteQueryTool(), new NoteGetTool(), new ReviewDueQueryTool()];
  return tools;
}
```

**Schema 归属警示** (文件头 `:5-6`): `knowledge_unit` 表结构由 `entry/src/main/ets/database/NoteDao.ets` 声明, 本文件**只读直查**; 两端漂移时以 NoteDao 为准修这里。这是 ADR-0012 §Consequences 提到的 schema 上移前提。

**错误处理统一形状**: 所有工具 `ok:false, content:'store not ready'` 当 `DatabaseHelper.getStore() === null` (`:72-76, 149-153, 218-222`); 写入由 `entry` 组合根负责 init。

### 1.9 MCP 工具 (OcrTool) vs ToolRegistry — ADR-0010 双工具面

**位置**: `agents/src/main/ets/mcp/tools/OcrTool.ets:1-427`

**关键差异**:

| 维度 | ToolRegistry tools | OcrTool (MCP) |
|---|---|---|
| 实现 AgentTool | ✅ 4 件套 name/desc/params/execute (`ToolRegistry.ets:17-22`) | ❌ 无 name/desc/params/execute, 直接 `class OcrTool` (`OcrTool.ets:52`) |
| 注册进 ToolRegistry | ✅ `ToolCatalog.createReadOnlyRegistry()` | ❌ 不注册 |
| 调用方 | LLM 通过 tool_calls JSON 走 ReAct 循环 | TypeClassifier 同步 `new OcrTool().recognize(imageUri)` (`TypeClassifier.ets:140, 146`) |
| 命名空间 | `common/src/main/ets/tools/` | `agents/src/main/ets/mcp/tools/` |
| ADR 依据 | ADR-0012 | ADR-0010 |

**OcrTool 接口** (`OcrTool.ets:52-109`):

```ts
// OcrTool.ets:52
export class OcrTool {
  // 公开: :60-62 识别字节 (ArrayBuffer)
  async recognizeBytes(imageBytes: ArrayBuffer, fileName?: string): Promise<OcrRecognitionResult>
  // 公开: :64-96 字节 + endpoint (测试 seam)
  async recognizeBytesWithEndpoint(imageBytes, endpoint, fileName?, mode?): Promise<OcrRecognitionResult>
  // 公开: :98-109 给 Capture 流水线的高层接口, 抛错而非返回 ok:false
  async recognize(imageUri: string): Promise<string>  // 返回 promptText
  // 公开: :111-174 完整 OCR 流程
  async recognizeImage(imageUri: string): Promise<OcrRecognitionResult>
}
```

**为什么单独存在** (ADR-0010 §Consequences 行 17 + CONTEXT.md:111):
- "按 MCP 语义封装的 agent 工具" — 不论将来是否真以 MCP 协议 (JSON-RPC server) 对外暴露, 目录语义就是 MCP 风格。
- 与 ToolRegistry 的"agent 工具能力面"区分: ToolRegistry 给 LLM 当工具调, OcrTool 给 Capture 流水线当"流水线工具"调, **不是 LLM 选择的工具**。

### 1.10 skill 侧复用 (唯一生产消费方)

**位置**: `skill/src/main/ets/skillability/SkillAbility.ets:1-48`

```ts
// SkillAbility.ets:20-46
private async handleWant(want: Want): Promise<void> {
  const request: SkillIntentRequest = new IntentRouter().fromWant(want);  // :21
  let result: SkillIntentResult;
  try {
    if (request.target === 'search_note') {
      await DatabaseHelper.init(this.context);  // :25 — skill 必须自 init
    }
    const registry: ToolRegistry = ToolCatalog.createReadOnlyRegistry();  // :27
    result = await new SkillIntentWorkflow(registry).run(request);          // :28
  } catch (e) { /* 错误路径 */ }
  // 包成 Want + abilityResult 回 platform (小艺): :36-46
}
```

**Tool → LLM 路径**:
`SkillAbility.handleWant → IntentRouter.fromWant (Want → typed request) → ToolCatalog.createReadOnlyRegistry → SkillIntentWorkflow.run → execute_search 节点直接 registry.execute('note_query', argsJson) → terminateSelfWithResult`

**注意**: skill 路径**不走 LLM** (无 tool_call 决策), 是平台 Want 直连单工具执行 (复用 research ⑤ §2.3 结论)。这与 ToolCallingWorkflow 的 ReAct 循环是两个**完全独立**的通路。

### 1.11 工具面拓扑总结表

| 工具 / 工作流类 | 模块 | file:line | 公开方法 | 谁调用 |
|---|---|---|---|---|
| `ToolRegistry` | common | `tools/ToolRegistry.ets:27-76` | `register`/`has`/`listDefinitions`/`execute` | ToolCallingWorkflow, ExecuteToolsNode, SkillAbility |
| `ToolCatalog` | common | `tools/ToolCatalog.ets:18-26` | `static createReadOnlyRegistry()` | SkillAbility.handleWant (`:27`) |
| `ToolLoop` | common | `tools/ToolLoop.ets:14-24` | `run(messages, registry, options?)` | **零生产调用** (仅测试) |
| `NoteQueryTool` | common | `tools/NoteQueryTools.ets:50-126` | `execute(args)` | ToolCatalog.createReadOnlyRegistry (`:21`) |
| `NoteGetTool` | common | `tools/NoteQueryTools.ets:129-193` | `execute(args)` | 同上 |
| `ReviewDueQueryTool` | common | `tools/NoteQueryTools.ets:196-247` | `execute(args)` | 同上 |
| `OcrTool` (MCP) | agents | `mcp/tools/OcrTool.ets:52-426` | `recognize`/`recognizeBytes`/`recognizeImage` | TypeClassifier.extractText (`:140-148`) |
| `CallModelNode` | common | `workflow/tool-calling/nodes/CallModelNode.ets:5-44` | `run(state)` | ToolCallingWorkflow.buildGraph (`:50`) |
| `ExecuteToolsNode` | common | `workflow/tool-calling/nodes/ExecuteToolsNode.ets:5-50` | `run(state)` | ToolCallingWorkflow.buildGraph (`:51`) |
| `ToolCallingWorkflow` | common | `workflow/tool-calling/ToolCallingWorkflow.ets:11-68` | `run(messages, options?)` | ToolLoop.run (`:22`), **零生产** |
| `SkillIntentWorkflow` | skill | `workflows/intent/SkillIntentWorkflow.ets:4-85` | `run(request)` | SkillAbility.handleWant (`:28`) |

---

## 2. Per-agent design patterns

每节格式: **Pattern name / Justification / State transitions / Loop semantics / Tool usage**。证据统一给 `path:LINE`。

### 2.1 TypeClassifier — Single-shot LLM + Tool call (mixed)

**Pattern**: **Single-shot LLM call** (主路径 `classifyText`) + **Pure function fallback** (rule-based)。
**位置**: `agents/src/main/ets/agents/TypeClassifier.ets:1-363`

**Justification**:
- 公开 3 入口 (`classify`/`recognizeText`/`classifyText`), 内部统一走 `callClassifier` (`:212-231`) 单次 LLM 调用, 不循环。
- LLM 失败显式 catch (`:123-133`) 落到 `ruleFallback` (`:292-299`) — 5 类题 + 6 学科的关键词匹配 (`CATEGORY_RULES`/`SUBJECT_RULES` `:41-56`), 不调 LLM。
- **`recognizeText` 是工具调用而非 LLM 调用**: image/file payload 走 `OcrTool.recognize` (`TypeClassifier.ets:140-148`), 不是 LLM 的 tool_call。

**State transitions**: 无 — 纯函数式 (每次调用传 `payload, context` 即可)。

**Loop semantics**: 无循环。LlmGuard 的 `callJsonWithRetry` (`LlmGuard.ets:37-66`) 是 JSON 校验重试, 不是 ReAct 循环 (最多 `DEFAULT_MAX_RETRIES=2` 次)。

**Tool usage**:
- 同步调 `OcrTool.recognize(imageUri)` (`TypeClassifier.ets:140, 146`), 不走 LLM tool_call。
- 通过 `LlmGuard.callJsonWithRetry` 调 LLM (`:224-229`), 预算 `maxTokens=800, timeoutMs=120000, temperature=0.1` (`:18-20`)。

### 2.2 KnowledgeModel — Plan-and-Execute + Reflexion

**Pattern**: **Plan-and-Execute** (outline→evidence→draft 三阶段, `structureStandardDraft`) + **Reflexion** (修复循环 `repairStandardDraft`/`repairDeepDraft`/`repairIncrementalSections`)。
**位置**: `agents/src/main/ets/agents/KnowledgeModel.ets:1-1252` (split 后 ~554 LOC per spec 015)

**Justification**:
- `structureStandardDraft` (`:235-258`) 三阶段: ① `callStandardArtifacts` 生成 outline+evidence+draft (`:691-720`); ② `normalizeStandardResult` 归一化 (`:785-844`); ③ `callIndependentVerifier` 独立验证 (`:722-783`) → ④ `applyVerification` (`:846-869`) → 这是典型的 **Plan-and-Execute** (Planner 生成 3 份产物 + Executor 验证)。
- `repairStandardDraft` (`:260-287`) 是 **Reflexion**: `current.verification` 失败 → `callEvidenceRepair` 修复 → 重 verify → `mergeVerifiedEvidence` (`:871-941`) 保留 `supported` 证据冻结, 只替换 contradicted。形成"验证-修复-再验证"循环, 但循环在 Dispatcher 编排层 (`Dispatcher.dispatchStandardGeneration`, `Dispatcher.ets:585-751`), 修到 `best.hardIssueCount === 0` (`:666-669`)。
- `repairDeepDraft` (`:375-451`): 同样 Reflexion 风格, 但限定 `targets = issue.sectionId`, 不重做整个 draft。
- `structureDeepDraft` (`:289-373`): 顺次 `callDeepSectionDraft` 每个 outlineSection, 维护共享 `ledger` (`formulas`/`terminology`/`conclusions` `:306, 559-581`), 这是 Plan-and-Execute 的变种 (sequential deep route)。

**State transitions**: 由 Dispatcher 持有 `current: NoteGenerationStandardResult` / `current: NoteGenerationDeepResult`, 每次 repair 替换; KnowledgeModel 自身无状态。

**Loop semantics**:
- `Dispatcher.dispatchStandardGeneration` 是真正的 Reflexion 循环 (max 几轮, 见 `Dispatcher.ets:585-751`)。
- KnowledgeModel 的 repair 方法**无内循环** — 它是被循环调用的纯转换。
- `callJsonWithRetry` 是 JSON 校验重试 (`:144-150`), 不是 Reflexion。

**Tool usage**:
- **不调 AgentTool**; 通过 `LlmCaller` (`LlmClient` via `LlmGuard`) 多次调 LLM (`callStandardArtifacts`/`callIndependentVerifier`/`callDeepSectionDraft`/`callEvidenceRepair`/`callAi`)。
- `PromptBuilder.buildPrompt` 是 prompt 构造 (`:114-155`), 不调 LLM。
- 预算: `KNOWLEDGE_MAX_TOKENS=12000`, `KNOWLEDGE_TIMEOUT_MS=300000` (`PromptBuilder.ets:10-11`)。

### 2.3 TruthCheckService — Pure function

**Pattern**: **Pure function** (4 项数学校验, 纯文本 → 文本+`truthFlag`)。
**位置**: `agents/src/main/ets/agents/TruthCheckService.ets:1-283`

**Justification**:
- 公开面 `check(input) → MvpTruthCheckResult` (`:32-34`); 内部 4 检查全字符串处理, 无 LLM, 无状态。
- 4 check: `checkBracePairing` (`:115-154`) + `checkDivisionByZero` (`:156-165`) + `checkEquation` (`:166-188`) + `checkLatexInternal` (`:189-231` 调 bracePairing + left/right parity + typo fix + `patchIntegralDx`)。
- 是 **CaptureGraph `truth_check` 节点的唯一实现** (`TruthCheckNode.ets:13`: `service.check(truthInput)`), **spec 015 后所有权已从 KnowledgeModel 移到 Capture pipeline** (CONTEXT.md 词汇 + spec 015 §3)。
- 返回值 `{truthFlag, details, correctedText}` (`:108-112`), `TruthCheckNode` 映射成 `{passed, flags, message}` (`TruthCheckNode.ets:20-24`)。

**State transitions**: 无 — 纯函数。

**Loop semantics**: 无循环 (单 pass over text)。

**Tool usage**: 无 LLM, 无 AgentTool。

### 2.4 PromptBuilder — Pure function (Builder 不算 GoF 模式)

**Pattern**: **Pure function** (类只封装常量 + 单方法, 命名上像 Builder 但行为是函数)。
**位置**: `agents/src/main/ets/agents/PromptBuilder.ets:1-58`

**Justification**:
- 公开 `build(input)` (`:19-21`) 与 `buildPrompt(ocrText)` (`:23-57`), 后者返回**模板字符串** (类别枚举 + 字段规范 + 渲染要求)。
- 持有 7 个常量 (`KNOWLEDGE_INPUT_LIMIT` 等 `:9-15`), 全部 `export const`, KnowledgeModel `KnowledgeModel.ets:88-96` import 当 budget 源。
- "**PromptBuilder is 系统 prompt 文本的唯一所有者**" (capturegraph-architecture-evolution §5.5 行 297, 文件头注释 `:5`: "工具化预留位 — 结构化若改走 ToolLoop, 提示词组装仍归本类")。
- 与 GoF Builder 模式差异: 它**不**分步构造复杂对象 (无 setter 链 / 无 Director), 而是一次性返回字符串 — 命名为 Builder 是惯用语, 行为是函数。

**State transitions**: 无 — 类实例可重入。

**Loop semantics**: 无循环。

**Tool usage**: 无 (prompt 文本生成器)。

### 2.5 OcrTool — Pure function (HTTP / SDK call wrapper)

**Pattern**: **Pure function** (无状态工具类, 单一职责 = 把图片 → 文本)。
**位置**: `agents/src/main/ets/mcp/tools/OcrTool.ets:1-427`

**Justification**:
- 公开 3 入口 (`recognizeBytes`/`recognizeBytesWithEndpoint`/`recognize`/`recognizeImage` `:60-174`), 内部混合 CoreVisionKit 本地文本 (`textRecognition.recognizeText`, `:191-197`) + 本地 OCR 服务 fallback (`:267-278`)。
- 单实例可复用 (无内部计数器 / 无 LRU / 无状态), `formulaEndpoint` 是构造时唯一字段 (`:53-58`)。
- `recognize` (`:98-109`) 抛错 (非 `ok:false`), 因为它是 TypeClassifier 的**同步依赖**而非 AgentTool。

**State transitions**: 无 — `OcrConfig.getInstance()` 是配置单例, 不是 OcrTool 的状态。

**Loop semantics**:
- `recognizeBytesWithEndpoint` 重试 2 次 (`:74-88`), `requestFormulaWithRetry` 重试 2 次 (`:256-263`), `requestCombinedWithRetry` 重试 2 次 (`:268-276`) — 都是**传输层重试**, 不是 ReAct/Reflexion。
- `recognizeImage` 本地→server fallback 是**条件降级**, 不是循环。

**Tool usage**: **无 LLM**, 无 AgentTool 注册 (ADR-0010)。

### 2.6 CaptureGraph — Pipeline / DAG orchestration

**Pattern**: **Pipeline / DAG orchestration** (StateGraph 风格, 条件路由 + haltWhen)。
**位置**: `agents/src/main/ets/graph/CaptureGraph.ets:1-99`

**Justification**:
- `CaptureGraph extends StateGraph<AgentState, CaptureStep>` 薄包装 (`:17-25`); `haltWhen` = `state.error !== undefined` (`:23`)。
- 5 节点 (`capture`/`classify`/`structure`/`truth_check`/`persist`), 装配由 `Dispatcher.buildGraph` 完成 (`Dispatcher.ets:1497-1531`), 拓扑见 capturegraph-architecture-evolution §5.2。
- `addNode` 包 try/catch (`:30-36`) 异常 → `CaptureGraphError{kind:'NODE_ERROR'}`; `run` 终态化 `currentStep='END'` (`:58`)。
- **不是** ReAct: 节点不基于 LLM 决策递归, 是**线性 + 条件分支**的静态图; 终止条件由 `haltWhen` 和 `addConditionalEdge` 路由函数 (`Dispatcher.ets:1524-1528`) 静态决定。

**State transitions**: `AgentState` (`:33-51` capturegraph-architecture-evolution §5.3 引) 字段逐步填: `payload → captureText → classification → knowledgeUnit → truthCheck → error?(短路) → commitResult`。

**Loop semantics**: **无内循环** — CaptureGraph 的 StateGraph 是单 pass DAG; 但外层 `dispatchStandardGeneration` (`Dispatcher.ets:585-751`) 在 repair 循环时反复 invoke `buildGenerationGraph`, 这是 §2.2 的 Reflexion 循环, 不是 CaptureGraph 自身。

**Tool usage**: **不直接调 AgentTool**; 节点通过注入 `TypeClassifier`/`KnowledgeModel`/`TruthCheckService`/`NoteDaoInterface` 调 LLM 和 DB。

### 2.7 ToolCallingWorkflow — **ReAct**

**Pattern**: **ReAct** (Reasoning + Acting 交错, `CallModelNode` ↔ `ExecuteToolsNode` 循环, LLM 决策 `toolCalls` 是否终止)。
**位置**: `common/src/main/ets/workflow/tool-calling/ToolCallingWorkflow.ets:1-69`

**Justification**:
- 循环结构: `START → call_model → (toolCalls 空? END : execute_tools) → (stepCount>=maxSteps ? max_steps_error : call_model) → END` (`ToolCallingWorkflow.ets:56-66`)。
- LLM 决策循环终止 (`:57-62` `toolCalls.length === 0` → END); 失控防护 `stepCount >= maxSteps` (`:63-65`) 抛 `TOOL_LOOP_MAX_STEPS`。
- 每轮: `CallModelNode.run` 调 LLM with `tools=[...], tool_choice='auto'` (`CallModelNode.ets:14-17`); `ExecuteToolsNode.run` 逐个 `registry.execute` + 回喂 OpenAI 格式 (`ExecuteToolsNode.ets:17-31`) → 这是教科书 ReAct 形状。
- **与 Plan-and-Execute 区别**: 无独立 plan 阶段 (无 outline/draft 拆分); LLM 在每轮 inline 决策。

**State transitions**: `messages/definitions/maxSteps/stepCount/currentStep/lastResult/toolCalls` (`ToolCallingState.ets:10-19`) 每步演化。

**Loop semantics**:
- 默认 `maxSteps=4` (`ToolCallingWorkflow.ets:9`), `maxSteps*3+4` 给 StateGraph 余地 (`:40`)。
- 终止: ① `toolCalls` 空 → END (LLM 决策 "no more tools"); ② `maxSteps` 触顶 → 抛 `LlmError('TOOL_LOOP_MAX_STEPS')` (`ToolCallingWorkflow.ets:54`); ③ 未知工具/坏 JSON → `ok:false` 回喂, **不**终止 (`ToolRegistry.ets:57-76` 容错) — 让模型自恢复 (`LlmToolCalling.test.ets:175-191` "loop_feeds_tool_error_back_and_model_recovers")。
- **零生产消费方** (见 §1.2 末尾 + §4)。

**Tool usage**:
- LLM: `LlmCaller.call` via CallModelNode (`CallModelNode.ets:21`), 走 `LlmGuard` 同款 seam。
- AgentTool: `ToolRegistry.execute` via ExecuteToolsNode (`ExecuteToolsNode.ets:24`)。
- 协议: OpenAI 兼容, JSON 路径 (`ToolLoop.ets:6` 注释: SSE 工具循环不在 spec 014)。

### 2.8 ConversationWorkflow — Multi-turn chat with state + Router

**Pattern**: **Multi-turn chat with state** (记忆 + 流式 + 意图路由) + **Router / Classifier** (kind/intent 分流)。
**位置**: `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets:1-664`

**Justification**:
- `ConversationState` (`ConversationState.ets:49-60`) 含 `sessionId/memoryContext/learnerProfileContext/draftRunId/draftStatus` 等多轮状态字段, **无** UIAbilityContext/ArkUI/callback/DAO/LlmClient/ToolRegistry (符合 spec 018 §4)。
- 9 节点 + 6 条件边 (`ConversationWorkflow.ets:124-232`):
  - `START → (image?image_reply : regenerate?regenerate_reply : classify_intent)`
  - `classify_intent → (note_generation?note_reply : load_reply_context)`
  - `load_reply_context → save_reply_input → (stream?stream_reply : complete_reply)`
- 三类入口 (image/text/regenerate) + intent (note_generation vs text reply) + response mode (complete vs stream) **三层 Router** 叠加。
- 多轮: `AgentMemoryService.saveMessage`/`getContextForReply`/`getContextForNoteGeneration` (`ConversationWorkflow.ets:524-578`) + `learnerProfileContext` + `summarizeSessionIfNeeded` (`:588-594`) — 这是 chat-with-state 的核心证据。
- **不是** ReAct: 节点执行**确定** (每个节点调什么服务是写死的, 非 LLM 决策); 没有 tool_call 决策循环。

**State transitions**: 见 §capturegraph-architecture-evolution §6.3 详细分析 + spec 018 §4。

**Loop semantics**: **无内循环**; conversation 是多轮 (外部多次 run), 单次 run 是单 pass DAG。

**Tool usage**:
- **不直接调 AgentTool / ToolRegistry** (`ConversationWorkflow.ets:1-22` 无 import ToolRegistry/ToolLoop)。
- 通过 `ReplyService` (`ReplyService.ets:41-227`) 调 LLM (SSE 流式 + JSON fallback); `AiService` (`:9, 59`) 调 CaptureGraph 生成笔记 (`AiService.confirmDraft`/`regenerateNoteDraft`/`generateNoteDraftWithSources`)。

### 2.9 SkillIntentWorkflow — Router / Classifier

**Pattern**: **Router / Classifier** (单层 action 路由, 不调 LLM)。
**位置**: `skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets:1-86`

**Justification**:
- 4 节点 + 3 边 (`SkillIntentWorkflow.ets:29-74`):
  - `START → route_action → (target==='search_note' ? execute_search : unsupported) → END`
- 单层 Router: `state.request.target` 决定 execute_search 或 unsupported (`:68-70`)。
- **execute_search 不是 LLM tool_call**: 是直接 `registry.execute('note_query', argsJson)` (`:38`), 把结果一次性包成 SkillIntentResult 返回。
- **unsupported** 返回 `{ok:false, content:'Unsupported skill intent: '+action, errorKind:'UNSUPPORTED_INTENT'}` (`:58-62`), 对应 ADR-0011 "其余 6 个 action 明确 unsupported"。

**State transitions**: `request → route_action → result?` (`SkillIntentState.ets:16-19`)。

**Loop semantics**: **无循环**。

**Tool usage**:
- **直接调 AgentTool** (`:38`); 不调 LLM。
- 仅 `'note_query'` 接通 (`:38` + spec 018 §"skill 仅 SearchNote 接通" + ADR-0011 2026-09-10 实施)。

### 2.10 ReplyService — Adapter (Stream + JSON fallback)

**Pattern**: **Adapter pattern** (封装 LLM 调用的 transport 选择: SSE 优先 + JSON 回退)。
**位置**: `entry/src/main/ets/services/ReplyService.ets:1-227`

**Justification**:
- 公开 2 入口: `complete(context)` (`:49-51` 走 `guardedComplete` JSON) + `stream(context, sink)` (`:68-146` 走 SSE + JSON fallback)。
- `stream` 内部 retry 1 次 (`:81-113` while loop, `streamAttempts < 2`), 首字节超时或 NETWORK_ERROR 才重试; 仍失败 → `fallback()` (`:153-164`) 走 `guardedComplete`。
- 这是 **transport-level retry + fallback**, 不是 Reflexion (无自我批评 / 无修复规划)。
- 不实现 `StreamEvent` 的 `tool_call`/`tool_result` emit (与 §1.7.3 一致 — 当前 SSE 不传工具循环)。

**State transitions**: 流式累积 `content` (`:73, 94`) + 计数 `thinkingChars`/`textChars` (`:75-78`) — 局部状态, 不跨调用。

**Loop semantics**:
- `stream` 内 retry loop: `streamAttempts < 2` (`:81`), 不超过 2 次尝试。
- `fallback` 仅当 `shouldUseFallback(content)` = `content.trim().length === 0` (`:114, 166-168`) 或 catch 内 transport error (`:138-145`)。

**Tool usage**: 不调 AgentTool; 调 `LlmClient.call({stream:true, onDelta})` (`ReplyService.ets:83-100`) + `LlmGuard.callJsonWithRetry` (`:54-62`)。预算 `CHAT_REPLY_MAX_TOKENS=12000` (`:31`)。

---

## 3. Cross-agent pattern matrix

| # | Agent / Workflow | Pattern | Has loop? | Max iter | Tool seam | State channels |
|---|---|---|---|---|---|---|
| 1 | `TypeClassifier` ([`agents/src/main/ets/agents/TypeClassifier.ets`](../agents/src/main/ets/agents/TypeClassifier.ets)) | Single-shot LLM + Pure function fallback | 内无 (外 LlmGuard JSON 重试 ≤2) | n/a | 同步调 `OcrTool.recognize` (`:140, 146`), LLM 走 `LlmGuard.callJsonWithRetry` (`:224-229`) | 无 (函数式) |
| 2 | `KnowledgeModel` ([`agents/src/main/ets/agents/KnowledgeModel.ets`](../agents/src/main/ets/agents/KnowledgeModel.ets)) | Plan-and-Execute + Reflexion (外层 Dispatcher 循环) | 内无 (外 Dispatcher 标准/深度 repair 循环) | n/a (Dispatcher 编排) | `LlmCaller.call` + `LlmGuard.callJsonWithRetry` (`:144-150`); 不调 AgentTool | 无 (函数式, 持有 PromptBuilder/ContentProtocol) |
| 3 | `TruthCheckService` ([`agents/src/main/ets/agents/TruthCheckService.ets`](../agents/src/main/ets/agents/TruthCheckService.ets)) | Pure function | 无 | n/a | 无 | 无 |
| 4 | `PromptBuilder` ([`agents/src/main/ets/agents/PromptBuilder.ets`](../agents/src/main/ets/agents/PromptBuilder.ets)) | Pure function (类惯用语) | 无 | n/a | 无 | 无 (常量类) |
| 5 | `OcrTool` ([`agents/src/main/ets/mcp/tools/OcrTool.ets`](../agents/src/main/ets/mcp/tools/OcrTool.ets)) | Pure function (HTTP/SDK wrapper) | 传输层重试 ≤2 (`:74, 256, 268`) | 2 | 无 (不实现 AgentTool) | 无 |
| 6 | `CaptureGraph` ([`agents/src/main/ets/graph/CaptureGraph.ets`](../agents/src/main/ets/graph/CaptureGraph.ets)) | Pipeline / DAG orchestration | 无 (单 pass DAG; haltWhen 短路) | n/a | 不直调; 节点调 LLM/DB/OCR | `AgentState` 13 字段 (`AgentState.ets:33-51`) |
| 7 | `ToolCallingWorkflow` ([`common/src/main/ets/workflow/tool-calling/ToolCallingWorkflow.ets`](../common/src/main/ets/workflow/tool-calling/ToolCallingWorkflow.ets)) | **ReAct** | ✅ 显式循环 | `DEFAULT_MAX_STEPS=4` (`:9`) | `ToolRegistry.execute` via ExecuteToolsNode (`:24`) + `LlmCaller.call` via CallModelNode (`:21`) | `ToolCallingState` 8 字段 (`ToolCallingState.ets:10-19`) |
| 8 | `ConversationWorkflow` ([`entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets`](../entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets)) | Multi-turn chat with state + Router | 内无 (外多轮) | n/a | 不调 AgentTool (无 ToolRegistry import); LLM 走 ReplyService (`:297, 337`) | `ConversationState` 9 字段 (`ConversationState.ets:49-60`) |
| 9 | `SkillIntentWorkflow` ([`skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets`](../skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets)) | Router / Classifier | 无 | n/a | `ToolRegistry.execute('note_query', ...)` (`:38`); 不调 LLM | `SkillIntentState` 3 字段 (`SkillIntentState.ets:16-19`) |
| 10 | `ReplyService` ([`entry/src/main/ets/services/ReplyService.ets`](../entry/src/main/ets/services/ReplyService.ets)) | Adapter (Stream + JSON fallback) | retry ≤2 (`:81`) | 2 | 不调 AgentTool; 调 `LlmClient.call` + `LlmGuard.callJsonWithRetry` | 局部流式累积 (`:73, 94`) |

**模式分布**: 4 Pure function (TruthCheckService / PromptBuilder / OcrTool) + 2 Single-shot (TypeClassifier / ReplyService) + 1 ReAct (ToolCallingWorkflow) + 1 Plan-and-Execute+Reflexion (KnowledgeModel) + 1 Pipeline (CaptureGraph) + 1 Router (SkillIntentWorkflow) + 1 Multi-turn chat + Router (ConversationWorkflow)。

**Loop 分布**: 仅 3 个有显式循环 (ToolCallingWorkflow=4 iter; ReplyService=2 iter; OcrTool=2 iter 传输重试), 其余 7 个无内循环。

**Tool 调用分布**: 5 个不调 AgentTool (TypeClassifier 调 OcrTool MCP / KnowledgeModel 调 LlmCaller / CaptureGraph 节点调 sub-services / ConversationWorkflow 调 AiService+ReplyService / ReplyService 调 LlmClient); 2 个直接调 (SkillIntentWorkflow → `note_query`; ToolCallingWorkflow → 通用 ToolRegistry); 1 个同步工具 (TypeClassifier → OcrTool MCP)。

---

## 4. Drift between docs and code (tool layer / patterns)

按 §1-§2 当前实现对照 spec 014 / 018 / ADR-0010 / 0011 / 0012 列出。

### 4.1 硬 drift (与 §7 决策矩阵潜在冲突, 需处置)

| # | drift | 引用 | 修复方向 |
|---|---|---|---|
| 1 | **ToolLoop / ToolCallingWorkflow 零生产消费方**。spec 018:44 列 ToolLoop 为 Tool-calling 稳定入口, 但全仓 `new ToolLoop` 仅命中 `common/src/test/LlmToolCalling.test.ets:128,148,164,185` + 构建缓存; **没有任何生产代码调它**。`ConversationWorkflow` 不接 (spec 018:74 "工具循环只调用 ToolLoop" 未落地) | spec 018:44, 74; 实测 grep 见 §1.2 末 | 接 ToolCallingWorkflow 到 ConversationWorkflow (答复/笔记生成); 或改 spec 018 §1 表格降级 ToolLoop 为 "infrastructure, not yet wired" |
| 2 | **ConversationWorkflow 不接 ToolLoop**。`ConversationWorkflow.ets:1-22` import 列表无 `ToolRegistry`/`ToolLoop`, spec 018:74 写 "工具循环只调用 ToolLoop; 不得复制两者逻辑", 当前 reply_service 仍是 `LlmClient.call` 直调 | spec 018:74; `ConversationWorkflow.ets:1-22` | 接 ToolLoop 进 ConversationWorkflow.handleCompleteReply/handleStreamReply; ToolCall 决策由 LLM 在对话内 inline 做 |

### 4.2 软 drift (非红线, 但建议修)

| # | drift | 引用 | 修复 |
|---|---|---|---|
| 3 | **SSE + 工具循环 = 空白**。`StreamEvent` 类型已 4 值全定义 (`LlmTypes.ets:129`), 但 `parseStreamEventsFromSseData` (`LlmClient.ets:497-522`) 仅 emit `thinking`/`text`, 不 emit `tool_call`/`tool_result`; `ToolLoop.ets:6` 注释明说 "SSE 流式工具循环不在 spec 014" | `LlmTypes.ets:129`, `LlmClient.ets:497-522`, `ToolLoop.ets:6` | 加 spec 014 extension / 新 spec; 改 `parseStreamEventsFromSseData` 在 delta 含 `tool_calls` 时 emit `tool_call` 事件 |
| 4 | **ToolLoop 零事件出口**。`run()` 只返回最终 `LlmCallResult` (`ToolCallingWorkflow.ets:41-44`), 中间 tool_call/tool_result 不对外发事件, 无法驱动 UI 过程展示 | `ToolCallingWorkflow.ets:22-45`; 实测 grep | 加 `ToolLoopOptions.sink?: (event: StreamEvent) => void`, ExecuteToolsNode.emit tool_call/tool_result |
| 5 | **P1 只读工具未在 entry/agents 注入**。`SkillAbility.ets:27` 唯一生产消费方; `entry/src/main/ets/` 全文 grep `ToolRegistry\|ToolLoop\|ToolCatalog` 无任何 match (见 §1.2 末). spec 014 §"P1 首批工具" 明确 "已落地" 但应用方只在 skill | `agents/src/main/ets/Index.ets` + `entry/src/main/ets` grep | spec 014 后增加 "应用方 wiring" 章节; 或在 EntryAbility 启动时 `ToolCatalog.createReadOnlyRegistry()` 缓存 (供未来 app 内 LLM 工具循环用) |
| 6 | **ToolRegistry schema 漂移风险未消除**。`NoteQueryTools.ets:5-6` 文件头注释说 "以 NoteDao 为准修这里", 但无 CI 守门; `knowledge_unit` 17 列在 NoteQueryTools (`:97, 157`) 与 entry NoteDao 同时声明 | `NoteQueryTools.ets:5-6` | spec 014 后增加命名-lint 或 AST 测试比对两文件列名集合 |

### 4.3 已核实 / 不可改

| # | 项 | 来源 |
|---|---|---|
| A | OcrTool 不进 ToolRegistry (符合 ADR-0010 + CONTEXT.md:111) | `OcrTool.ets:52` 无 AgentTool 4 件套; `ToolCatalog.createReadOnlyRegistry` (`ToolCatalog.ets:19-26`) 不 import OcrTool |
| B | ToolRegistry 落 `common/` (符合 ADR-0012 §Chosen 1) | `common/src/main/ets/tools/ToolRegistry.ets:1`; `common/Index.ets:210` export |
| C | P1 只读工具先于写工具 (符合 ADR-0012 §Chosen 3 "写工具赛后") | spec 014 §4 + ADR-0012; `ToolCatalog.createReadOnlyRegistry` 命名明示 |
| D | spec 014 §3 "SSE 流式工具循环明确不在本 spec" | `ToolLoop.ets:6` 注释明示 |
| E | ToolRegistry 容错执行 (未知工具/坏 JSON → ok:false) 符合 spec 014 §2 | `ToolRegistry.ets:57-76` + `LlmToolCalling.test.ets:110-119` 测试 |
| F | skill 仅 SearchNote 接通, 其余 UNSUPPORTED_INTENT | `SkillIntentWorkflow.ets:57-66` + ADR-0011 (2026-09-10 follow-up 行 21) |

### 4.4 仍未核实

| # | 项 | 来源 |
|---|---|---|
| α | spec 018 §"验收" Hypium + 真机验收 (1 项未勾) | spec 018:137-139 |
| β | 7 个 skill intent action 语义, 队员确认状态 | ADR-0011 §Open item + CONTEXT.md:119 |
| γ | spec 015 §"P3" `CaptureGraphError.cause?: Object` 收紧 `unknown` | spec 015 §3 + capturegraph-architecture-evolution §8.1 drift #4 |

---

## 5. Source citations count

### 5.1 引用路径分布 (top 15)

| # | 路径 | 引用次数 |
|---|---|---|
| 1 | `common/src/main/ets/llm/LlmTypes.ets` | 12 |
| 2 | `common/src/main/ets/tools/ToolRegistry.ets` | 10 |
| 3 | `common/src/main/ets/workflow/tool-calling/ToolCallingWorkflow.ets` | 10 |
| 4 | `common/src/main/ets/llm/LlmClient.ets` | 8 |
| 5 | `agents/src/main/ets/mcp/tools/OcrTool.ets` | 7 |
| 6 | `common/src/main/ets/workflow/tool-calling/ToolCallingState.ets` | 7 |
| 7 | `agents/src/main/ets/agents/KnowledgeModel.ets` | 7 |
| 8 | `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets` | 7 |
| 9 | `common/src/main/ets/tools/NoteQueryTools.ets` | 6 |
| 10 | `agents/src/main/ets/agents/TypeClassifier.ets` | 6 |
| 11 | `common/src/main/ets/llm/LlmResponseParser.ets` | 5 |
| 12 | `common/src/main/ets/workflow/tool-calling/nodes/ExecuteToolsNode.ets` | 5 |
| 13 | `skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets` | 5 |
| 14 | `common/src/main/ets/llm/LlmGuard.ets` | 4 |
| 15 | `common/src/main/ets/tools/ToolCatalog.ets` | 4 |

(其余被引 1-3 次: `ToolLoop.ets`, `CallModelNode.ets`, `LlmConfig.ets`, `CaptureGraph.ets`, `AgentState.ets`, `DispatchPayload.ets`, `Dispatcher.ets`, `OcrNode.ets`, `TruthCheckService.ets`, `PromptBuilder.ets`, `AiService.ets`, `IntentRouter.ets`, `SkillAbility.ets`, `ReplyService.ets`, `ConversationState.ets`, `ConversationTypes.ets`, `SkillIntentState.ets`, `LlmToolCalling.test.ets`, `Index.ets` × 2)

### 5.2 docs/ 引用

| 文档 | 引用次数 | 章节 |
|---|---|---|
| `docs/specs/018-agent-workflow-architecture.md` | 5 | §1, §3, §4, §7 |
| `docs/specs/014-tool-calling-protocol.md` | 4 | §1, §2, §3, §4 |
| `docs/adr/0012-tool-calling-protocol.md` | 3 | §1, §1.6, §1.8 |
| `docs/adr/0010-mcp-tools-semantics.md` | 2 | §1.9 |
| `docs/adr/0011-skill-xiaoyi-reservation.md` | 2 | §1.10, §2.9 |
| `docs/research/capturegraph-architecture-evolution-2026-09-16.md` | 3 | §0, §2.6, §2.8 |
| `docs/research/agent-toolkit-and-skill-dispatch-2026-09-06.md` | 1 | §1.10 |
| `docs/research/agent-reasoning-process-display-research-2026-09-11.md` | 1 | §4.1 |

**总引用数**: ~120 个 `path:LINE` 引用 + 7 个 ADR/spec 章节引用 + 8 个 docs/research 引用 (合计 ~135 个唯一引用)。

---

## 6. Maintenance

- **本文档**是 Tool layer + Per-agent patterns 的**唯一权威研究**; 与 `capturegraph-architecture-evolution-2026-09-16.md` 互补 (后者 "图运行机制", 本文 "工具面 + 模式标签")。
- **更新触发**:
  - `common/src/main/ets/tools/*` 任一文件重大变更 → 在 `docs/research/` 开新 dated 调研, 把本文档标 "see also"
  - spec 014 / 018 / ADR-0010 / 0011 / 0012 修订 → 先看 §3 模式矩阵 + §4 drift 是否仍成立
  - 新 agent/workflow 加入 → §2 加一节, §3 加一行, §4.1 #1 (ToolLoop 零生产) 重新评估
- **drift 推进**: §4.1 #1-2 各开一个 ticket; #3-6 待优先级排序
- **本文档不重复** capturegraph-architecture-evolution §5/§6 的图节点细节, 直接引用之

---

## 7. Related

- [`docs/research/capturegraph-architecture-evolution-2026-09-16.md`](./capturegraph-architecture-evolution-2026-09-16.md) — CaptureGraph 唯一权威 (图运行机制, 4 workflow 节点表, 决策一致性)
- [`docs/research/agent-toolkit-and-skill-dispatch-2026-09-06.md`](./agent-toolkit-and-skill-dispatch-2026-09-06.md) — 工具层 / skill 调度调研基线
- [`docs/research/agent-reasoning-process-display-research-2026-09-11.md`](./agent-reasoning-process-display-research-2026-09-11.md) — ToolCallingWorkflow 零生产消费方 最早记录 (与 §4.1 #1 同源)
- [`docs/specs/014-tool-calling-protocol.md`](../specs/014-tool-calling-protocol.md) — 协议/ToolRegistry/ToolLoop 实现 spec
- [`docs/specs/018-agent-workflow-architecture.md`](../specs/018-agent-workflow-architecture.md) — 4 workflow 共享 StateGraph 内核 spec
- [`docs/adr/0010-mcp-tools-semantics.md`](../adr/0010-mcp-tools-semantics.md) — `mcp/` vs `tools/` 语义
- [`docs/adr/0011-skill-xiaoyi-reservation.md`](../adr/0011-skill-xiaoyi-reservation.md) — skill/ 模块是 SearchNote 第一行动作
- [`docs/adr/0012-tool-calling-protocol.md`](../adr/0012-tool-calling-protocol.md) — OpenAI 兼容工具调用协议 + ToolRegistry 落位
- [`docs/adr/0008-capturegraph-self-built-runtime.md`](../adr/0008-capturegraph-self-built-runtime.md) — LangGraph 是设计模型不是运行时
