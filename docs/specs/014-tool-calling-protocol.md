# 014 — LLM Tool-calling 协议与 ToolRegistry(tools/ CRUD 工具层前置)

> **Status**: implemented (2026-09-06 — 协议字段 / ToolRegistry / ToolLoop + §4 P1 只读工具全部落地, 含 Hypium + Node 双层测试)

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
// ChatMessage 增 tool_calls?: LlmToolCall[]      — ToolLoop 回喂 assistant(tool_calls) 消息必需;
//                                                  该消息 content 固定传 ''(OpenAI 兼容端点接受空串)
// LlmResponseChoice.message 增 tool_calls?: LlmToolCall[];
// LlmCallRequest 增 tools? / tool_choice? 透传字段
// LlmCallResult 增 toolCalls?: LlmToolCall[]     — 由 extractToolCalls 填充, ToolLoop 经 LlmCaller seam 依赖它
```

`LlmClient`: `callJsonInternal` 组装 body 时透传新字段; 新增 `extractToolCalls(parsed): LlmToolCall[]`(以 `choices[0].message.tool_calls` 非空为准提取 — **不硬性依赖 `finish_reason`**, OpenAI 兼容端点在该字段上行为有差异, `finish_reason` 仅作日志参考), `LlmCallResult.toolCalls` 随之填充; `extractContent` 保持不变。

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
  register(tool: AgentTool): void;                      // 重名/命名非法抛 LlmError(kind=TOOL_REGISTRY_ERROR)
  has(name: string): boolean;
  listDefinitions(): LlmToolDefinition[];
  execute(name: string, argsJson: string): Promise<ToolResult>;  // JSON.parse 失败 → ok:false, 不抛
}
```

- `execute` 对**未知工具名**同样返回 `ok:false`(LLM 可能幻觉出未注册名), 不抛异常。
- 命名规则 `^[a-z][a-z0-9_]{0,63}$` **刻意严于** OpenAI wire 规则 `^[a-zA-Z0-9_-]{1,64}$`, 是安全子集 — 更严的约束在注册时拦截, 而不是发送后被端点拒绝。

### 3. 工具执行循环(common/src/main/ets/tools/ToolLoop.ets)

- **构造注入 `LlmCaller`**(复用 `LlmGuard` 既有 seam — 生产传 `LlmClient`, 测试传 mock; 测试计划据此成立): `run(messages, registry, options?)` 内部走 `llmCaller.call`(JSON 路径)。
- 响应 `toolCalls` 非空 → 逐个 `registry.execute` → 追加 assistant(`tool_calls` + `content:''`)消息 + `role:'tool'` 结果消息(`content = ToolResult.content`, `tool_call_id` 一一对应)→ 继续循环; 为空 → 返回最终 text。
- `ToolLoopOptions { maxSteps?: number(默认 4); callOptions?: LlmCallOptions(模型/超时等, 透传每步调用) }`; `maxSteps` 触顶**抛** `LlmError('tool loop exceeded maxSteps=N', 'TOOL_LOOP_MAX_STEPS')`(`LlmErrorKind` 增该值, additive — 既有调用方按 `indexOf(kind)` 匹配, 不受影响), 防失控循环。
- SSE 流式工具循环明确不在本 spec。

### 4. P1 首批工具(只读, 已落地: common/src/main/ets/tools/NoteQueryTools.ets)

`note_query`(按 subject / review_status / keyword 过滤, 返回条数上限 20)、`note_get`(按 id)、`review_due_query`(按 ReviewStatus 聚合计数)。全部基于 `common` 的 `DatabaseHelper` RDB store 直接查询, **禁止 import entry**(拓扑红线, ADR-0012)。

实现前提(写入验收):
- store 经 `DatabaseHelper.getStore()` 获取 — 未 init 时为 null, 工具返回 `ok:false, 'store not ready'`; **context 与 init 所有权仍在 entry 组合根**, common 不自建。
- **schema 归属警示**: `knowledge_unit` 等表结构目前由 `entry` 的 DAO 声明 — common 侧直查前, 要么把共享 schema 常量上移 common, 要么在工具文件头显式标注 NoteDao 为 schema source-of-truth, 防两端漂移。
- 不注册任何写工具 — 写路径统一(F2)是前置条件。

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

- **协议解析**: 带 `tool_calls` 的 LlmResponse fixture → `extractToolCalls` 取值正确; fixture 覆盖**两种端点形状**(`finish_reason='tool_calls'` 与 `finish_reason='stop'` 但 `message.tool_calls` 非空); 无 tool_calls → 空数组; `arguments` 非 JSON → registry 返回 `ok:false` 而非抛异常; 未知工具名 → `ok:false`。
- **向后兼容**: 不带 tools 的 `LlmRequestBody` JSON.stringify 输出与改动前逐字段一致。
- **ToolRegistry**: 注册成功 / 重名抛错 / 命名规则拒绝 / `listDefinitions()` 形状与 wire 协议一致。
- **ToolLoop**(mock `LlmCaller`, 复用 LlmGuard 既有 seam 模式): 无工具直接返回 / 单轮工具调用闭环 / `maxSteps` 触顶抛 `TOOL_LOOP_MAX_STEPS` / 工具错误作为 tool 消息回喂后模型自恢复。
- 测试分两层: `common/src/test/`(Hypium, 行为层 — 协议解析 / Registry / Loop 闭环)+ `scripts/arkts-lint/tests/`(Node AST/wire 形状守门, **进 CI** — 断言请求体逐字段兼容与新字段形状)。CI(arkts-lint)不回归。

## Reversibility

**Medium** — 协议字段可整体删除不留痕; registry/loop 是纯新增文件; 唯一粘滞点是 `ChatMessage.role` 扩宽, 但加宽对旧调用方无感。

## Acceptance criteria

- [ ] `LlmRequestBody` 含 `tools` 时, 请求体能被 OpenAI 兼容端点接受(fixture 单测断言 wire 形状)
- [ ] 不含 `tools` 时请求体与现状逐字段等价(单测)
- [ ] ToolLoop 在 mock LLM 回放下完成"提问→tool_calls→执行→回喂→最终回答"闭环(单测)
- [ ] ToolLoop 回喂消息形状正确: assistant 消息带 `tool_calls` 且 `content=''`, tool 消息带对应 `tool_call_id`(单测)
- [ ] `maxSteps` 触顶抛 `TOOL_LOOP_MAX_STEPS`(单测)
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
