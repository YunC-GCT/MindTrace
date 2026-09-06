# 014 — LLM Tool-calling 协议与 ToolRegistry(tools/ CRUD 工具层前置)

Derived from [ADR-0012](../adr/0012-tool-calling-protocol.md). Scope label: F1(2026-09-06 体检)/ 复赛冲刺序 3(spec-only, 见 [inventory §6.1](../architecture/agent-tools-inventory-2026-09-06.md)).

## Why this ticket

- 复核确认(2026-09-06): `LlmRequestBody` 无 `tools`/`tool_choice`, `LlmClient.extractContent` 不解析 `tool_calls` — LLM 无法"选择"任何工具, ADR-0010 预留的 `tools/` 位没有调用协议支撑。
- 调研事实([agent-toolkit-and-skill-dispatch-2026-09-06](../research/agent-toolkit-and-skill-dispatch-2026-09-06.md)): 手机端 API 24 无系统级 LLM API(且官方无 "AI Kit"), 云端 OpenAI 兼容 function-calling 是唯一工具调用通道; `skill/` 的 7 个意图中 6 个被拓扑卡住([ADR-0011](../adr/0011-skill-xiaoyi-reservation.md)) — 需要一个两个调用方共享的工具面。
- 本 spec 只立协议与骨架,**不写业务工具实现**(复赛阶段零回归风险; 首批只读工具实现为 P1, 可赛后落地)。

## What we will build

全部改动在 `common/src/main/ets/llm/` 与新增 `common/src/main/ets/tools/`; 不触碰 `entry`、`agents` 既有代码。

### 1. 协议字段(LlmTypes.ets, 全部可选 — 向后兼容)

```ts
// ChatMessage 扩展
role: 'system' | 'user' | 'assistant' | 'tool';  // 增 'tool'
tool_call_id?: string;                            // role='tool' 时必填(OpenAI 语义)

// 请求侧
tools?: LlmToolDefinition[];
tool_choice?: string;                             // Phase 1 仅 'auto' | 'none'

export interface LlmFunctionDefinition {
  name: string;                                   // ^[a-z][a-z0-9_]{0,63}$
  description: string;
  parameters: Record<string, Object>;             // JSON Schema 对象(ArkTS 惯例, 同 LlmGuard)
}
export interface LlmToolDefinition {
  type: 'function';
  function: LlmFunctionDefinition;
}

// 响应侧
export interface LlmToolCall {
  id: string;
  type: 'function';
  function: LlmFunctionCallNameArgs;              // { name: string; arguments: string }
}
// LlmResponseChoice.message 增 tool_calls?: LlmToolCall[];
// LlmCallRequest 增 tools? / tool_choice? 透传字段
```

`LlmClient`: `callJsonInternal` 组装 body 时透传新字段; 新增 `extractToolCalls(parsed): LlmToolCall[]`(`finish_reason === 'tool_calls'` 时取 `choices[0].message.tool_calls`, 其余返回空数组); `extractContent` 保持不变。

### 2. ToolRegistry(common/src/main/ets/tools/ToolRegistry.ets)

```ts
export interface ToolResult {
  ok: boolean;
  content: string;        // 回喂 LLM 的字符串(ReAct 惯例), 失败时放错误说明
}
export interface AgentTool {
  name: string;
  description: string;
  parameters: Record<string, Object>;
  execute(args: Record<string, Object>): Promise<ToolResult>;
}
export class ToolRegistry {
  register(tool: AgentTool): void;                      // 重名/命名非法抛 LlmError
  has(name: string): boolean;
  listDefinitions(): LlmToolDefinition[];
  execute(name: string, argsJson: string): Promise<ToolResult>;  // JSON.parse 失败 → ok:false, 不抛
}
```

### 3. 工具执行循环(common/src/main/ets/tools/ToolLoop.ets)

`run(messages: ChatMessage[], registry: ToolRegistry, options?: ToolLoopOptions): Promise<LlmCallResult>` — 内部走 `LlmClient.call`(JSON 路径): 响应含 `tool_calls` → 逐个 `registry.execute` → 追加 assistant(tool_calls) 消息 + `role:'tool'` 结果消息 → 继续循环; 无 `tool_calls` → 返回最终 text。`ToolLoopOptions.maxSteps`(默认 4)触顶即停并返回错误说明, 防失控循环。SSE 流式工具循环明确不在本 spec。

### 4. P1 首批工具(只读; 本 spec 只定接口形状, 实现可赛后)

`note_query`(按 subject / review_status / keyword 过滤, 返回条数上限 20)、`note_get`(按 id)、`review_due_query`(按 ReviewStatus 聚合计数)。全部基于 `common` 的 `DatabaseHelper` RDB store 直接查询, **禁止 import entry**(拓扑红线, ADR-0012)。不注册任何写工具 — 写路径统一(F2)是前置条件。

### 5. skill 侧复用(仅契约, 不实装)

未来 `skill/` 的 IntentRouter 从同一 `ToolRegistry` 取 `listDefinitions()` / `execute()`(见 [ADR-0011](../adr/0011-skill-xiaoyi-reservation.md) 实装路径)。本 spec 不创建 skill 侧代码。

## Public surface change

- **不破坏**: 新字段全部可选; 不传 `tools` 的请求体与现状等价(验收项见下)。`ChatMessage.role` 联合类型扩宽是加宽不是收窄, 现有字面量全部仍合法。
- **新增导出**(common/Index.ets): `AgentTool` / `ToolResult` / `ToolRegistry` / `ToolLoop` 及相关类型。`LlmToolCall` 等类型同步导出。

## Migration

单 PR 可回滚, 建议序列:
1. `feat(common): llm tool-calling protocol fields + extractToolCalls`(TDD: 先写解析测试)
2. `feat(common): ToolRegistry + ToolLoop`(TDD: mock LlmCaller)
3. `docs(specs): mark 014 implemented`(P1 工具实现落地时)

## Test plan (TDD)

- **协议解析**: 带 `tool_calls` 的 LlmResponse fixture → `extractToolCalls` 取值正确; `finish_reason='stop'` → 空数组; `arguments` 非 JSON → registry 返回 `ok:false` 而非抛异常。
- **向后兼容**: 不带 tools 的 `LlmRequestBody` JSON.stringify 输出与改动前逐字段一致。
- **ToolRegistry**: 注册成功 / 重名抛错 / 命名规则拒绝 / `listDefinitions()` 形状与 wire 协议一致。
- **ToolLoop**(mock `LlmCaller`, 复用 LlmGuard 既有 seam 模式): 无工具直接返回 / 单轮工具调用闭环 / `maxSteps` 触顶 / 工具错误作为 tool 消息回喂后模型自恢复。
- 全部走 `common/src/test/` 现有框架; CI(arkts-lint)不回归。

## Reversibility

**Medium** — 协议字段可整体删除不留痕; registry/loop 是纯新增文件; 唯一粘滞点是 `ChatMessage.role` 扩宽, 但加宽对旧调用方无感。

## Acceptance criteria

- [ ] `LlmRequestBody` 含 `tools` 时, 请求体能被 OpenAI 兼容端点接受(fixture 单测断言 wire 形状)
- [ ] 不含 `tools` 时请求体与现状逐字段等价(单测)
- [ ] ToolLoop 在 mock LLM 回放下完成"提问→tool_calls→执行→回喂→最终回答"闭环(单测)
- [ ] `node scripts/arkts-lint/index.mjs --quiet` 0 errors; `npm --prefix scripts/arkts-lint test` 全绿
- [ ] naming-lint / link-check 通过
- [ ] 无任何 `entry` import 出现在 `common/src/main/ets/tools/`

## Out of scope

- 写类工具(Note insert/update/delete)— 与 F2 写库路径统一绑定, 赛后另立 spec
- `OcrTool` 注册为 AgentTool(保持 `mcp/` 语义不动, [ADR-0010](../adr/0010-mcp-tools-semantics.md); 可能的后续单独决策)
- MCP Server 化与小艺开放平台上架(ADR-0010 开放注记)
- skill/ IntentRouter 实装(另立 spec, 前置: 7 个 intent action 语义经队员确认)
- A2A / FunctionComponent 集成(API 26 / 平台侧, roadmap)
- 流式(SSE)工具循环
