# 分层可折叠思考与执行过程展示 — 前后端改良深度调研 — 2026-09-11

> **Date:** 2026-09-11
> **Scope:** AI 浮窗对话「过程区块 + 最终回答区块」改良的事实基础 — 思考模式链路 (LlmConfig→LlmClient→ConversationWorkflow→AgentChatService→ChatBubble) / 工具调用架构现状与缺口 / UI 旧组件动刀档案 / 鸿蒙官方能力对接 / React 生态对照 — 只读调研, 不改任何代码
> **Project:** MindTrace (`entry` HAP + `common`/`agents`/`skill`/`cardservice` HSP)
> **Author:** 研究后台 agent (只读代码 + `devecocli docs` 本地官方文档库检索 + 生态文档 fetch)
> **上游调研:** [agent-float-window-component-research-2026-09-11.md](./agent-float-window-component-research-2026-09-11.md) (本调研是它的延伸; 该文档已裁决 "深度思考"开关 → **删除**)

---

**TL;DR:** 当前系统的"思考展示"是一条**单向硬编码链**: 流式事件枚举只有 `'reasoning' | 'content'` 两种 kind (LlmTypes.ets:133), `enableThinking` 在 ReplyService 三处硬编码 `false` (ReplyService.ets:54,81,123), 但 deepseek-v4-pro 服务端默认思考模式仍会回 `reasoning_content` (LlmClient.ets:495 注释), 所以 ChatBubble 的 reasoning 折叠面板**数据源活但默认收不到** — 除非模型服务端自发返回。"推理力度"概念**半存在**: wire 字段 `reasoning_effort` 已定义 (LlmTypes.ets:30) 但在 LlmClient.ets:284 **硬编码 `'high'`**, LlmConfig 只存 boolean (LlmConfig.ets:320-326) 且 `setEnableThinking` **全仓无调用方**。工具调用方面: 工具面 (ToolRegistry/AgentTool/ToolCatalog + 3 个只读工具) 完备, ToolCallingWorkflow 已 StateGraph 化, 但 **ToolLoop 生产代码零调用** (仅测试), Conversation workflow 的 `stream_reply` 是单次 LLM 调用**无工具循环**, 流式事件**无 tool_call/tool_result 类型** — 即任务简报的 4 类 SSE 事件中 `thinking`/`text` 可直接映射现有 kind, `tool_call`/`tool_result` **全缺**。UI 侧 ChatBubble 现有 reasoning 面板 (ChatBubble.ets:64-92) 无展开动画、无二级折叠、思考内容纯 Text; 改造成双区块的切口在 ai 分支 :63-92 (过程) 与 :94-120 (最终回答) 之间。鸿蒙官方: 无 Markdown/公式组件 (`faqs-arkweb-97` 仍有效), 无手风琴/打字机预置组件 (需 animateTo + if 自绘, `faqs-arkui-348`/`faqs-arkui-1414`), 工具图标可用 SymbolGlyph (`ts-basic-components-symbolglyph`)。**最大架构缺口: SSE 流式 + 工具循环的组合是空白** (ToolLoop.ets:6 注释明说 "SSE 流式工具循环不在 spec 014"), 需要新 spec。

## Question

1. Q1 思考模式/推理力度从 UI 到 LLM 请求的完整业务逻辑链是什么? "推理力度"是否存在于系统中? 接通 UI→请求参数需要动哪些文件?
2. Q2 工具调用 (Tool Calls) 的架构现状如何? 若对话气泡要展示 tool_call/tool_result 过程, 哪些可复用、哪些缺失?
3. Q3 UI 旧组件 (ChatBubble/ChatModels/AgentMessageList/MarkdownRenderer/ChatStatusMachine) 的动刀档案 — 改造为双区块结构的最小切口、ChatMsg 新字段、keyGen 调整、摘要计数来源?
4. Q4 鸿蒙官方能力: SSE/流式方案、折叠面板组件、打字机效果、SymbolGlyph 图标、Markdown 渲染、@Reusable — 各有什么官方支持 (documentId)?
5. Q5 React/业界生态 (Vercel AI SDK / assistant-ui / Claude 产品) 的 reasoning + tool call 流式协议与展示模式是什么 (生态参照)?

## Method

- 通读思考链路全部文件: `common/src/main/ets/llm/` (LlmTypes/LlmClient/LlmConfig/LlmGuard) + `entry/src/main/ets/services/` (ReplyService/AgentChatService/ChatStatusMachine) + `entry/src/main/ets/workflows/conversation/` (ConversationState/ConversationTypes/ConversationWorkflow) + `entry/src/main/ets/overlays/AgentFloatWindow/` (AgentFloatWindow/ChatBubble/ChatModels/AgentMessageList/ChatSession)。
- 全仓 grep: `enableThinking|reasoning_content|getEnableThinking|setEnableThinking` (思考链)、`ToolRegistry|ToolCatalog|AgentTool|ToolLoop|note_query|createReadOnlyRegistry` (工具链), 建立生产调用 vs 测试调用映射。
- 通读工具链: `common/src/main/ets/tools/` (ToolRegistry/ToolLoop/ToolCatalog/NoteQueryTools) + `common/src/main/ets/workflow/tool-calling/` (Workflow/State/2 Node) + `skill/src/main/ets/` (SkillAbility/SkillIntentWorkflow/State) + `agents/src/main/ets/mcp/tools/OcrTool.ets`。
- 读渲染分子: `entry/src/main/ets/shared/molecules/MarkdownRenderer.ets` (417 行全文) / `FormulaSplitRenderer.ets` (拆分算法与块上限) + `common/src/main/ets/render/ContentProtocol.ets`。
- 权威 spec 核对: `docs/specs/018-agent-workflow-architecture.md` (§3 Tool-calling / §4 Conversation 的硬约束) + `docs/specs/014-tool-calling-protocol.md` (grep 摘录)。
- 鸿蒙官方文档: `devecocli docs catalog` 后按关键词检索 (SSE / requestInStream / 折叠 / 打字机 / SymbolGlyph / Markdown / Reusable), 只采信命中文档, 记录 documentId。
- 生态对照: webfetch Vercel AI SDK v7 `streamText` 参考文档 (2026-09-11 实拉, 拿到 TextStreamPart 全枚举与 reasoning effort 枚举); assistant-ui / Claude 产品模式标注"生态参照"。
- 行数口径: 文件物理行数 (与编辑器一致)。

## Findings

### Q1 思考模式/推理力度业务逻辑链 (UI → LLM 请求)

#### 1.1 LlmTypes.ets (198 行) — 类型全景

| 类型 | 行 | 内容 |
|---|---|---|
| `ChatMessage` | :13-19 | `role: 'system'\|'user'\|'assistant'\|'tool'` (:14, 'tool' 为 spec 014 工具回喂), `reasoning_content?` (:16), `tool_call_id?` (:17), `tool_calls?: LlmToolCall[]` (:18) |
| `LlmRequestBody` | :22-34 | `thinking?: LlmThinkingConfig` (:29, DeepSeek 思考配置), `reasoning_effort?: string` (:30, 注释 "思考强度: high \| max"), `tools?`/`tool_choice?` (:31-32), `chat_template_kwargs?` (:33, qwen 专用) |
| `LlmThinkingConfig` | :36-38 | `{type: 'enabled' \| 'disabled'}` — 只有开关, 无力度分级 |
| `LlmChatTemplateKwargs` | :40-42 | `{enable_thinking: boolean}` |
| `LlmStreamDelta` | :111-115 | `content?` (:113) + `reasoning_content?` (:114) — SSE chunk 的 delta 字段 |
| **`LlmStreamCallback`** | :133 | `(delta: string, kind: 'reasoning' \| 'content') => void` — **流式事件 kind 枚举仅 2 种**, 无 tool_call/tool_result |
| `LlmCallOptions.enableThinking` | :144 | 单次调用可选思考开关 |
| `LlmCallRequest` | :172-187 | 统一入参: `stream?` (:175), `onDelta?` (:177), `enableThinking?` (:184), `tools?`/`tool_choice?` (:185-186) |
| `LlmCallResult` | :190-198 | `text?`/`streamed`/`toolCalls?` (:196, extractToolCalls 填充)/`usage?` |

#### 1.2 LlmClient.ets (532 行) — 双路径与 SSE 架构

- **唯一公共入口 `call()`** (:60-70): `stream===true` 走 `callStreamInternal` (SSE), 否则 `callJsonInternal` (JSON)。
- **enableThinking 缺省回退 config**: JSON 路径 :86-88 / SSE 路径 :262-264, 均为 `request.enableThinking !== undefined ? request.enableThinking : this.config.getEnableThinking()`。
- **thinking 配置注入 (SSE 路径)** :281-285: `enableThinking=true` 时 `bodyObj['thinking'] = {type:'enabled'}` + **`bodyObj['reasoning_effort'] = 'high'` (硬编码)**; 同时 :277-279 思考模式不设 temperature ("DeepSeek 思考模式不支持 temperature")。qwen 模型走 `chat_template_kwargs` (:287-290; JSON 路径 :108-111)。
- **SSE 传输架构**: `http.requestInStream` (:370) + `on('dataReceive')` (:333) + `on('dataEnd')` (:349); 行缓冲解析 `processSseBuffer` (:416-463, 单 `\n` 分隔 + `data:` 前缀 + `[DONE]` 哨兵, :423 注释记录 2026-09-07 PR1k 修复 "OpenAI/DeepSeek 实际 SSE 格式是 data: {...}\n 每个 event 一行"); 双超时保护: 2 分钟总超时 (:311-318) + 30 秒首字节降级 (:322-330, :320-321 注释 "deepseek-v4-pro 思考模式 thinking_content 阶段可能 10-20 秒才发出第一个 chunk")。
- **reasoning 解析与 emit** `tryEmitSseDelta` (:501-522): `delta.reasoning_content != null && length>0` → `onDelta(delta, 'reasoning')` (:512-513); content 优先 `onDelta(delta.content, 'content')` (:517-518), **content 为空时 fallback 用 reasoning_content 再 emit 一次 'content'** (:519-521, :495-499 P1 bug fix 注释: 防止 deepseek-v4-pro 思考模式导致 UI 空白) — 注意这意味着思考模式下同一段文本可能**双发** (先 'reasoning' 后 'content')。
- **非流式 call() 路径的 reasoning 处理**: `extractContent` (:189-205) — content 为空时 fallback 返回 `reasoning_content` (:199-201); tool_calls 响应不走空内容抛错 (:164-170); `extractToolCalls` 以 `message.tool_calls` 非空为准 (:178-187, 不看 finish_reason)。

#### 1.3 LlmConfig.ets (590 行) — thinking 配置存储

- 持久化键 `KEY_ENABLE_THINKING = 'enable_thinking'` (:18), 运行时缓存 `cachedEnableThinking: boolean = false` (:50), 读写方法 `getEnableThinking()`/`setEnableThinking()` (:320-326), `resetDefaults()` 重置 false (:466, :482)。
- **`setEnableThinking` 全仓无调用方** (grep 仅定义处 + LlmClient 两处 `getEnableThinking` 调用 :88/:264) — 即设置页没有任何思考开关 UI, config 值永远停留在默认 `false`。
- **"推理力度/reasoning effort/thinking budget" 判定**: 系统中只有 wire 字段 `reasoning_effort` (LlmTypes.ets:30, 取值注释 "high \| max") 且被 LlmClient.ets:284 硬编码 `'high'`; LlmConfig 不存 effort; 无任何 UI/配置入口。**结论: 力度概念半存在 (wire 层有、配置层无、UI 层无)。**

#### 1.4 LlmGuard.ets (132 行)

`LlmCaller` seam (:5-7, `call(request): Promise<LlmCallResult>`, ToolLoop/测试复用同一 mock 模式); `callJsonWithRetry` (:37-66) 做 JSON 提取 + 校验重试; `enableThinking` 经 `toCallRequest` 透传 (:128)。ReplyService.complete 走这条路。

#### 1.5 ReplyService.ets (177 行) — 三处硬编码的定位

| 硬编码位置 | 所在方法 | 服务的场景 | 为什么硬编码 |
|---|---|---|---|
| :54 | `complete()` (:47-61) | `handleCompleteReply` (ConversationWorkflow.ets:280-308) — `responseMode:'complete'` 非流式回答路径 (AgentChatService.realReply, **无 UI 调用方**) | 代码与注释均未说明; LlmGuard JSON 路径要求结构化 `{answer}` 输出 (:134-153 校验器), 思考模式会先产出思维链、干扰 JSON 稳定性, 推测为输出可靠性考虑 |
| :81 | `stream()` (:63-106) | `handleStreamReply` (ConversationWorkflow.ets:314-364) — **浮窗主路径** `realReplyStream` 的 SSE 流式回答 | 同上推测; 但 LlmClient SSE 路径 `enableThinking=false` 时**不发送 thinking 字段** (:281), 服务端模型默认行为仍可能返回 reasoning_content (:495 注释佐证) — 即关闭开关≠收不到思考内容 |
| :123 | `fallback()` (:113-132) | stream 失败/空内容时的非流式降级 (:83-86, :104) | 与 complete 同理 |

**关键事实**: 三处硬编码只控制**请求体是否带 thinking 字段**, 不控制 reasoning 展示链路 — 展示链路 (kind='reasoning' → ChatMsg.reasoning → 折叠面板) 对服务端自发返回的思考内容是**被动全兼容**的。

#### 1.6 AgentChatService.ets (101 行) — UI facade 全貌

- **`AgentChatCallbacks` 接口 10 项** (:9-20): `addAiMsg` / `addAiMsgEmpty` / `appendAiMsg(id, delta, kind?)` / `finishAiMsg` / `setBusy` / `setStatusMeta` / `getContext` / `getConversationText` / `getSessionId` / `onDraftReady`。(`ConversationWorkflowCallbacks` 11 项, ConversationTypes.ets:5-16, 多 `onStart`/`onProgress`/`onFinish`; 上游调研称 "12 项" 略有漂移, 以代码为准。)
- **`appendAiMsg` 的 kind 二分流**: 实现在 AgentFloatWindow.ets:112-118 — `kind==='reasoning'` 时 append 到 `m.reasoning` (:114), 否则 append 到 `m.content` (:116), 均 map+spread 不可变更新。
- **两条路径**: `captureReply(imageUri, userText)` (:65-72, ImageConversationRequest → image_reply 节点, 图片识别链, 非流式) vs `realReplyStream(userContent)` (:82-89, TextConversationRequest + responseMode:'stream' → stream_reply 节点, SSE 流式)。`send()` 分流在 AgentFloatWindow.ets:175-185 (有图 captureReply / 纯文本 realReplyStream), **不传任何思考参数**。
- **6 个无调用方 facade 方法**: `realReply` (:74) / `restoreDraft` (:95) / `retryDraft` (:96) / `regenerateNote` (:98) / `requestRegeneration` (:99) / `listRecoverableDrafts` (:100) — 与上游调研一致。
- `ConversationWorkflowAdapter` (:22-58): 包一层 ChatStatusMachine (:24) 做 `onProgress → statusMachine.advance → setStatusMeta` (:38-40), activeRuns 计数守卫 busy (:34-51)。

#### 1.7 ConversationState.ets (60 行)

- `ConversationStep` 10 值 (:3-13): START/classify_intent/load_reply_context/save_reply_input/image_reply/complete_reply/stream_reply/note_reply/regenerate_reply/END。
- `ConversationProgressStep` 12 值 (:15-27) — ChatStatusMachine 文案表的 key (ChatStatusMachine.ets:20-34)。
- **三种 request 形态均无思考字段** (:29-47): `ImageConversationRequest{kind,imageUri,userContent}` / `TextConversationRequest{kind,userContent,responseMode}` / `RegenerateConversationRequest{kind,noteId,userContent}`。
- `ConversationState` (:49-60): request/sessionId/currentStep + 可选 intent/memoryContext/learnerProfileContext/draft 四件套。

#### 1.8 ConversationWorkflow.ets (607 行) — 流式链路与图结构

- **流式链路** `handleStreamReply` (:314-364): LlmConfig.isConfigured 检查 (:321) → `addAiMsgEmpty()` 占位拿 msgId (:329) → `setStep('reply_model_call')` (:330) → `replyService.stream(..., sink)` (:331-336), **sink 即 `(delta, kind) => this.cbs.appendAiMsg(msgId, delta, kind)`** (:335) — reasoning 透传方式是裸字符串 kind 逐 delta 回调, 无事件对象封装。结果三分支: usedFallback → finishAiMsg + addAiMessage (:337-341); interrupted → appendAiMsg('\n\n⚠️ *AI 回复中断，请重试*') (:342-343); 正常 → setStep('completed') (:345)。收尾: finishAiMsg (:347) → safeSaveAssistantMessage (:348, **只存最终 content, reasoning 不入会话记忆**) → learnerProfile/summarize (:352-353)。
- **节点 8 个** (:125-202): classify_intent / image_reply / load_reply_context / save_reply_input / complete_reply / stream_reply / note_reply / regenerate_reply; **边**: START 条件边 (image→image_reply / regenerate→regenerate_reply / else classify_intent, :203-211) + classify_intent 条件边 (note_generation→note_reply / else load_reply_context, :212-217) + save_reply_input 条件边 (stream→stream_reply / else complete_reply, :219-224) + 5 个 END 边 (:225-229)。
- **无工具调用节点**: 全文件无 ToolLoop/ToolRegistry import; `stream_reply`/`complete_reply` 都是单次 LLM 调用 (经 ReplyService)。
- **无 progress 事件对象**: `setStep(step)` (:473-475) 只推 ConversationProgressStep → statusMeta (busy 行文案), 与流式 delta 是两条平行通道。

#### 1.9 当前"思考模式"完整数据流 (结论)

```
LlmConfig.enable_thinking (boolean, 默认 false, 无 UI 写入 — setEnableThinking 零调用方)
  ↓ (LlmClient :86-88 / :262-264 缺省回退)
LlmClient.call({enableThinking}) — ReplyService 三处均显式传 false (:54/:81/:123)
  ↓ enableThinking=true 时: body.thinking={type:'enabled'} + body.reasoning_effort='high' (硬编码 :281-285)
SSE requestInStream → dataReceive → processSseBuffer → tryEmitSseDelta
  ↓ onDelta(delta, 'reasoning' | 'content')  [kind 枚举仅 2 种, :133]
ReplyService.stream sink (ReplyService.ets:75-78)
  ↓
ConversationWorkflow.handleStreamReply → cbs.appendAiMsg(msgId, delta, kind) (:335)
  ↓
AgentChatService adapter (:30-32) → AgentFloatWindow.appendAiMsg kind 二分流 (:112-118)
  ↓
ChatMsg.reasoning / ChatMsg.content (ChatModels.ets:30/21)
  ↓
ChatBubble: reasoning 非空 → 折叠面板 (:64-92); content → 三态渲染 (:95-117)
```

**判断**: "推理力度"不存在可配置入口; UI→请求参数的思考控制链**完全断开** (上游调研已裁决删除装饰性 deepThink 开关, 本调研确认删除不伤展示链 — 展示链依赖服务端自发 reasoning_content, 与请求开关正交)。

**若要接通 UI→请求参数, 需动的文件清单** (8 个):
1. `chat/ChatHeader.ets` — 新控件 (原装饰开关已裁决删除)
2. `AgentFloatWindow.ets` — state + send() 传参 (:175-185)
3. `workflows/conversation/ConversationState.ets` — TextConversationRequest 加思考字段 (:35-39)
4. `services/AgentChatService.ets` — realReplyStream/realReply 透传 (:74-89)
5. `services/ReplyService.ets` — 三处 `enableThinking: false` 参数化 (:54/:81/:123)
6. `common/src/main/ets/llm/LlmClient.ets` — reasoning_effort 可配置化 (:284, 可选)
7. `common/src/main/ets/llm/LlmConfig.ets` — effort 持久化 (:320-326, 可选)
8. `ConversationWorkflow.ets` — handleStreamReply/handleCompleteReply 透传 (:294/:331-336)

### Q2 工具调用 (Tool Calls) 现状与缺口

#### 2.1 工具面 (可复用, 完备)

- **`ToolRegistry`** (common/src/main/ets/tools/ToolRegistry.ets, 77 行): `AgentTool` 接口 `{name, description, parameters: Record<string,Object>, execute(args): Promise<ToolResult>}` (:17-22); `ToolResult {ok: boolean, content: string}` (:11-14); 命名规则 `^[a-z][a-z0-9_]{0,63}$` 注册时拦截 (:25, :35-37); `listDefinitions()` 转 OpenAI wire `LlmToolDefinition[]` (:46-54); `execute(name, argsJson)` 容错执行 — 未知工具/非法 JSON 返回 `ok:false` 不抛异常 (:57-76)。
- **`ToolCatalog`** (27 行): `createReadOnlyRegistry()` 静态工厂 (:19-26), 注册 3 个只读工具。
- **已注册工具清单** (NoteQueryTools.ets, 253 行): `note_query` (:50-127, 按 subject/review_status/keyword 检索, 上限 20 条) / `note_get` (:129) / `review_due_query` (:196) — **全部是笔记查询类, 无终端/文件系统/命令类工具**。
- **`OcrTool`** (agents/src/main/ets/mcp/tools/OcrTool.ets, 427 行): **不实现 AgentTool 接口** (无 name/description/parameters/execute 四件套), **不注册进 ToolRegistry** — MCP 语义预留位 (CONTEXT.md:110-112, ADR-0010), 由 AiService→Dispatcher 的 Capture 链直接实例化调用; 混合识别 CoreVisionKit 本地文本 + 本地 OCR 服务 fallback (:46-51 注释)。

#### 2.2 ToolCalling workflow (spec 018 四领域之一)

- **位置**: `common/src/main/ets/workflow/tool-calling/` (Workflow 69 行 + State 19 行 + nodes/ 2 文件)。
- **入口**: `ToolLoop.run(messages, registry, options?)` (common/src/main/ets/tools/ToolLoop.ets:21-24) → `ToolCallingWorkflow.run` (:22-45)。
- **图结构** (:47-68): 3 节点 `call_model`/`execute_tools`/`max_steps_error`; 条件边: call_model → (toolCalls 空 ? END : execute_tools) (:57-62); execute_tools → (stepCount>=maxSteps ? max_steps_error : call_model) (:63-65); maxSteps 默认 4 (:9), 触顶抛 `LlmError('TOOL_LOOP_MAX_STEPS')`。
- **State** (ToolCallingState.ets:10-19): `messages/definitions/callOptions?/maxSteps/stepCount/currentStep/lastResult?/toolCalls?`。
- **CallModelNode** (:12-35): 构造 LlmCallRequest + `tools` + `tool_choice='auto'` (:14-17); `copyCallOptions` 含 enableThinking 透传 (:43)。
- **ExecuteToolsNode** (:12-50): assistant(tool_calls, content='') + 逐 call 执行 + role:'tool' 消息带 tool_call_id 回喂 (:17-31) — OpenAI 语义完整。
- **事件出口: 无** — `run()` 只返回最终 `LlmCallResult` (:41-44), 中间每步的 tool_calls/结果**不对外发事件**, 无法驱动 UI 过程展示。
- **⚠️ 生产消费: 零**。grep 全仓: `new ToolLoop` 仅出现在 `common/src/test/LlmToolCalling.test.ets:128/148/164/185`; **没有任何生产代码调用 ToolLoop/ToolCallingWorkflow**。spec 018:44 把它列为 Tool-calling 领域稳定入口, 但 Conversation workflow 没接 (ConversationWorkflow.ets 无相关 import)。
- **⚠️ 仅 JSON 路径**: ToolLoop.ets:6 注释明说 "仅 JSON 路径 (SSE 流式工具循环不在 spec 014)" — CallModelNode 走 `LlmCaller.call` 的非流式分支。

#### 2.3 skill 模块的 note_query 消费 (唯一生产工具消费方)

- 链路: `SkillAbility.handleWant` (:20-47) → `IntentRouter.fromWant` → `ToolCatalog.createReadOnlyRegistry()` (:27) → `SkillIntentWorkflow.run` (:28) → `execute_search` 节点直接 `registry.execute('note_query', argsJson)` (SkillIntentWorkflow.ets:38) → 结果一次性 `terminateSelfWithResult` 返回 (:46)。
- **事件流: 无** — 不是 LLM 驱动的工具循环 (无 tool_call 决策), 是平台 Want 直连单工具执行; 与对话气泡的工具过程展示无直接关系, 但证明 registry 在 UIAbility 上下文可初始化 (DatabaseHelper.init :25)。

#### 2.4 可复用 vs 缺失 (结论)

| 能力 | 现状 | 判定 |
|---|---|---|
| 工具契约与注册 (AgentTool/ToolRegistry/ToolCatalog) | 完备 (ToolRegistry.ets:17-76, ToolCatalog.ets:19-26) | **直接复用** |
| OpenAI tool-calling wire 类型 (LlmToolCall 等) | 完备 (LlmTypes.ets:148-169) | **直接复用** |
| 工具循环图骨架 (ToolCallingWorkflow StateGraph) | 完备但无事件出口 (ToolCallingWorkflow.ets:47-68) | **复用 + 加事件 sink** |
| SSE 传输层 (requestInStream + 行缓冲) | 完备 (LlmClient.ets:303-409) | **直接复用** |
| **流式事件枚举 tool_call/tool_result 类型** | **缺失** — kind 只有 'reasoning'\|'content' (LlmTypes.ets:133) | **需新增** |
| **Conversation workflow 工具循环** | **缺失** — stream_reply 单次调用 (ConversationWorkflow.ets:158-166, :314-364) | **需接入** (spec 018:74 "工具循环只调用 ToolLoop" 已有原则) |
| **SSE + 工具循环组合** | **空白** — ToolLoop 仅 JSON 路径 (ToolLoop.ets:6) | **需新 spec** |
| **ToolCallingWorkflow 的 onToolCall/onToolResult 回调** | **缺失** (run 只返回最终 result) | **需新增** |
| **ChatMsg 的工具调用字段** | **缺失** (ChatModels.ets:13-34) | **需新增** |
| **工具调用入会话记忆** | **缺失** — safeSaveAssistantMessage 只存 content (ConversationWorkflow.ets:503-509) | **需决策** |
| 语义为"终端/文件/命令"的工具本体 | **缺失** — 现有 3 工具全是笔记查询 (NoteQueryTools.ets:250-252) | **需决策** (演示文案映射或新工具) |

### Q3 UI 旧组件现状 (动刀对象档案)

#### 3.1 ChatBubble.ets (139 行)

- **reasoning 折叠面板** (:64-92): 进入条件 `(this.msg.reasoning ?? '').length > 0` (:64); 折叠头 = ▾/▸ 箭头 + "思考过程" 文本胶囊 (:65-80, `.onClick(onToggleReasoning)` :80); 展开体 = `Text(this.msg.reasoning)` 斜体 F_SM (:82-91)。**展开动画: 无** — 纯 if 条件渲染直接切换 (:82); **二级折叠: 无**; **思考内容渲染: 纯 Text**, 不走 Markdown。
- **三态渲染** (:95-117): ① `streaming===true` → 轻量 `Text(content)` (:96-103, :97 注释 "避免每 token 做 Markdown 重解析") — **打字机效果即 delta append 的天然节奏, 无额外逐字动画**; ② 非 streaming 且 `containsFormulaSyntax` → `FormulaSplitRenderer({text, profile:'chat'})` (:104-109); ③ 其余 → `MarkdownRenderer({text, progressive:false, profile:'chat'})` (:110-116)。即流式结束后发生一次性"渲染升级" (Text → Markdown/公式)。
- **长文处理** (:124-125): `content.length > 240` 时底色从 PURPLE_LIGHT 换 `rgba(255,255,255,0.035)` + maxWidth 88%→94%。
- `containsFormulaSyntax` (:136-138) 委托 ContentProtocol.hasFormulaSyntax。

#### 3.2 ChatModels.ets (53 行)

- **`ChatMsg` 6 字段** (:13-34): `id` / `role: 'user'|'ai'` / `content` / `ts` / `streaming` (:27) / `reasoning` (:30) / `reasoningExpanded?` (:33, 默认收起)。
- `ChatStatusStep = ConversationProgressStep` 别名 (:36) — 浮窗类型反向锚定 workflow 层的唯一接缝; `ChatStatusMeta {step, title, detail}` (:38-42); `ChatSession {id, name, messages}` (:44-53)。
- 会话持久化: ChatSessionManager 把整个 sessions 数组 JSON 序列化进 preferences (ChatSession.ets:52-61), **reasoning 字段随 ChatMsg 一起持久化** (:55, JSON.stringify(sessions)); 新字段需考虑旧数据反序列化兼容 (init 的 JSON.parse as ChatSession[] :39, 多出的字段自动 undefined)。

#### 3.3 AgentMessageList.ets (133 行)

- `ChatMessageDataSource implements IDataSource` (:18-56): `setMessages` slice 拷贝 + `onDataReloaded` **全量 reload** (:46-49, :51-55) — 每个流式 delta 触发整列表 reload, 非行级 onDataUpdate。
- **LazyForEach keyGen** (:98): `msg.id + '_c' + msg.content.length + '_s' + streaming + '_r' + reasoningExpanded` — content.length 每 token 变 → 该行 key 变 → 行级重建; 展开态变化也触发重建 (r 位)。**reasoning.length 不在 key 里**: 流式思考期间 reasoning 增长但 key 不变 — 展开体 Text 因 @Prop msg 引用变化仍会刷新, 但 LazyForEach 缓存判断依赖 key, 存在刷新粒度隐患。
- 滚动行为 (:71-77): `onMessagesChanged` 时最后一条 streaming → 50ms 后 `scrollEdge(Edge.Bottom)`; `initialIndex` 滚到底 (:127-132)。
- busy 行 (:101-115): LoadingProgress + statusMeta.title/detail — **ChatStatusMachine 12 步文案的展示位**。

#### 3.4 MarkdownRenderer.ets (417 行) + FormulaSplitRenderer.ets (276 行)

- **MarkdownRenderer 接口**: `@Prop @Watch('onTextChanged') text` (:33) / `@Prop progressive` 默认 true (:34) / `@Prop profile: 'note'|'chat'` (:35)。**支持 text 动态变化 (增量喂入可行)**: `resetVisibleBlocks` (:326-342) 在每次 text 变化时重新 parse (≤280 字符立即解析 :28, :337-339; 更长走 16ms 延迟 :344-351), textSignature djb2 hash 防重复解析 (:402-412)。
- **性能特征**: 渐进披露 — 初始 3 块 + "继续阅读" 批次展开 (:25-26, :363-367, :370-375); 但**每次 text 变化都会重置 visibleBlockCount** (:336) — 流式中高频喂入会导致 parseReady 抖动 + 块列表闪动, 这正是 ChatBubble 流式态绕过它用纯 Text 的原因 (:97 注释)。
- **FormulaSplitRenderer**: `splitByFormulas('$$')` 拆分 (:53-80), 合并相邻文本块减 ~40% WebView (:16-17), 块硬上限 30 (:30), LazyForEach 按需建毁 (:18), 文本块 ≤1500 字符 (:31)。
- **思考步骤 Markdown 怎么渲染的答案**: 思考内容通常无公式; 流式期间用纯 Text (现状策略平移), 流结束后可切 MarkdownRenderer progressive=true (或保持纯 Text + maxLines 截断 — 深度思考文本常超长)。

#### 3.5 ContentProtocol (common/src/main/ets/render/ContentProtocol.ets, 611 行)

MM-MD-v1 归一化/校验协议 (:33-64 normalizeNoteMarkdown; :77-79 validateNoteMarkdown); `hasFormulaSyntax(text)` (:81-86) = 未转义 $ / `\(` / `\[` / 数学命令 — ChatBubble/MarkdownRenderer 共用它决定公式分流; 全部 AI 正文走它归一化 (ConversationWorkflow.addAiMessage :489-493)。

#### 3.6 ChatStatusMachine.ets (42 行) 与未来"过程区块"摘要的关系

- 12 步固定 title/detail 文案表 (:20-34): intent_check/reply_context_load/reply_model_call/image_*/note_*/completed — 是**流水线步骤**语义 (classify → load → call), 不是**工具调用**语义。
- **判定: 可复用且不被替代** — statusMeta 驱动 busy 行 (AgentMessageList.ets:101-115), 与消息内过程区块是两个正交展示位: 前者回答"AI 正在哪个阶段", 后者回答"AI 想了什么/用了什么工具"。图片链 (image_recognize 等) 无流式 reasoning, statusMeta 是其唯一过程展示。融合是 P2 议题 (如完成后把最后 statusMeta 归档进过程区块)。

#### 3.7 双区块改造最小切口 (结论)

- **切口定位**: ChatBubble ai 分支 (:54-132) — 现有 reasoning 面板 (:63-92) 升级为"过程区块"容器 (折叠头 + 摘要行 + 展开体[思考 Markdown + 工具列表]); 现有 content Column (:94-120) 保持为"最终回答区块"。**不需要动 user 分支** (:23-53) 与 AgentMessageList 的 LazyForEach 骨架。
- **ChatMsg 需要的新字段** (ChatModels.ets): `toolCalls?: ChatToolCallView[]` (每项 {toolName, argsSummary, result, resultExpanded?}) + `processExpanded?` (过程区块总开关, 替代/包含 reasoningExpanded) + 派生计数字段或渲染时计算 (`thinkingCount`/`toolCount`)。若要多轮 thinking 交错保序, 需 `processBlocks?: ProcessBlock[]` 结构化数组 (Vercel UIMessage parts 式) — 更彻底但动持久化格式。
- **keyGen 是否需要改** (AgentMessageList.ets:98): **需要** — 现有 key 不含 reasoning.length 与 toolCalls 状态, 新区块的流式刷新 (reasoning 增长/工具项加入/二级展开) 不会触发 LazyForEach 行更新判定; 建议加 `'_rl' + reasoning.length + '_t' + toolCalls.length + '_pe' + processExpanded` (注意: 展开态进 key 会保留"展开触发行重建"的现有行为, 若要去抖需配合 @Reusable 或行内 state)。
- **摘要 "思考 X 次，查看 Y 个文件，执行 Z 条命令" 的计数来源**: ① X (thinking 次数) = 收到的 thinking 事件**分段数** — 当前单轮 LLM 只有一段 reasoning, **恒为 1**; 只有接入 ToolLoop 多步循环 (每步模型可再思考) 后 X 才 >1; ② Y/Z = tool_call 事件的分类计数 (按 toolName 映射图标/文案) — **数据源是尚不存在的 tool_call 事件** (Q2 缺口); ③ 计数实现位置建议: AgentFloatWindow.appendAiMsg 侧累计 (与现有 kind 二分流同位, AgentFloatWindow.ets:112-118) 或 ChatMsg 派生 getter — 前者改动小。
- **UI 状态一致性 (流式中手动展开不被后续 delta 折叠)**: 现有机制已给出模式 — `reasoningExpanded` 是独立于 content/reasoning 的字段, appendAiMsg 的 map+spread 更新**原样保留它** (AgentFloatWindow.ets:114/:116 均未触碰 reasoningExpanded); 新增 processExpanded/toolExpanded 沿用同一纪律即可, 风险点在 map+spread 手写展开处**漏复制新字段** (现为逐字段手写, 非自动 spread — 新增字段必须同步 5 处字面量: :114/:116/:120/:161-162/:178)。

### Q4 鸿蒙官方能力对接 (devecocli docs, documentId 均为本地官方文档库命中项)

#### 4.1 SSE / 流式请求

| 文档 | documentId | 结论 |
|---|---|---|
| SSE 请求大模型流式数据 | `faqs-network-80` | 官方对 "POST + SSE 请求大模型" 的回答: **用官方提供的 EventSource 三方库** — 不用自研; 但 MindTrace 现有 requestInStream 自研解析已稳定运行 (LlmClient.ets:416-463), 迁移非必需 |
| request vs requestInStream 边界 | `faqs-network-52` | request 适用 ≤5MB; requestInStream 适用 >5MB / 流式 — LlmClient 选择正确 |
| requestInStream 用法 | `faqs-network-81` | dataReceive 逐块接收 — 与 LlmClient 实现一致 |
| 大数据量 maxLimit | `faqs-network-64` | 5M 默认上限可调 maxLimit 至 100M; 思考链长文本场景余量充足 |

**多类型混合事件流**: 官方**无专门方案** — dataReceive 只给原始 ArrayBuffer, 事件分型 (thinking/tool_call/tool_result/text) 需应用层自定协议 (现状的 `data: {json}` 行协议 + type 字段是标准做法, 只需扩展 type 枚举)。

#### 4.2 折叠面板 / 展开动画

| 需求 | 官方答案 | documentId |
|---|---|---|
| 可折叠容器组件 (手风琴) | **无预置组件** — 检索 "折叠面板 collapse 展开" 无 Accordion 类组件命中; 官方推荐模式 = **animateTo + if 条件渲染** 控制展开收起 | `faqs-arkui-348` (List 折叠动画, 原文 "可以使用显式动画animateTo结合条件渲染if控制ListItem内容区域的展开和收起") |
| 文本展开收起 (长文截断) | measureTextSize 测量 + 展开按钮 | `faqs-arkui-267` |
| Flex 子项折叠 | Flex wrap 折叠行数 | `faqs-arkui-1213` |
| 展开动画推荐 | **animateTo 显式动画** (ChatBubble 现状 :82 缺这一步, 加 `animateTo` 包裹展开态切换即可获得高度过渡) | `faqs-arkui-348`; transition 组件转场见 `faqs-performance-26` (transition 用于插入/删除) |

#### 4.3 打字机效果

官方**无预置打字机组件**; `faqs-arkui-1414` (文本动态播报) 给出自绘范式: **双重 ForEach 逐字符分割 + animateTo 逐字着色** — 适用于"逐字高亮"类动效。MindTrace 现状打字机 = SSE delta 天然逐字 append (ChatBubble.ets:96-103 纯 Text), **无需额外动画**; 若要平滑补间可参考该 FAQ 或生态 smoothStream 思路 (见 Q5)。

#### 4.4 图标 (工具调用: 终端/文件/搜索)

- **`ts-basic-components-symbolglyph`** (API 参考): SymbolGlyph 显示系统预置图标小符号, 支持颜色/大小/粗细/渲染策略/动效, "相比使用图片资源，SymbolGlyph具有体积小、可动态着色、支持动效等优势" — **工具图标首选方案**。
- **`arkts-common-components-symbol`** (开发指南): `$r` 引用系统预置 Symbol 资源名。
- **`ui-design-symbolregister`** / `ui-design-custom-symbol-res-register`: 自定义 Symbol 图标注册 (TTF + JSON 动效参数, 5.1.1(19)+) — 系统图标库找不到"终端"等图标时的兜底。
- 具体资源名 (终端/搜索/文件) 需查系统图标库 (`harmonyos-symbol` 资源页), 本次未逐一确认 — Open question。

#### 4.5 Markdown 渲染

**官方无 Markdown/公式渲染组件** — `faqs-arkweb-97` 结论仍有效 (原文 "HarmonyOS目前没有提供专门的数学公式渲染组件，可以使用WebView组件来加载支持数学公式渲染的网页"); `faqs-arkui-112` (RichText 底层即 WebView)。MindTrace 自研 MarkdownRenderer + FormulaSplitRenderer (KaTeX WebView) 就是官方推荐路线, **无替换必要** — 与 2026-09-06 审计及上游调研结论一致。

#### 4.6 @Reusable 组件复用

- `ts-custom-component-decorator-reusable` (API 参考): @Reusable + reuseId 区分类型 + aboutToReuse 收参; 官方点名 "列表滚动、频繁切换组件显示与隐藏" 场景。
- `arkts-reusable` (V1 复用指南) / `arkts-component_reuse` (开发实践) / `arkts-global-reuse-pool` (全局复用池, 跨父组件共享)。
- `bpta-best-practices-long-list`: 长列表最佳实践, 官方点名聊天应用场景。
- **对本次改造的适用性: 高** — 双区块后 ChatBubble 更重 (折叠面板 + 工具列表 + Markdown), 滚动回收收益增大; 注意事项: ① @Prop msg 深拷贝模式与 aboutToReuse 参数更新需对齐; ② `faqs-arkui-1433` (复用时 animation 不停止) 提醒展开动画状态要在 aboutToReuse 重置; ③ reuseId 需区分 user/ai 气泡。

### Q5 React / 业界生态对照 (概念参照, 均非鸿蒙 API)

#### 5.1 Vercel AI SDK v7 (2026-09-11 实拉 sdk.vercel.ai/docs/reference/ai-sdk-core/stream-text)

- **流式 part 类型枚举** (TextStreamPart): `text-delta` / `reasoning-delta` / `source` / `custom` / `tool-call` / `tool-input-start` / `tool-input-delta` / `tool-result` — 即任务简报的 4 类事件在业界是**单一 type 枚举的 8 种 part**, 走同一条流; 工具入参还有增量流 (tool-input-start/delta)。
- **消息 part 模型** (UIMessage/AssistantModelMessage content): `text` / `reasoning` / `reasoning-file` / `file` / `tool-call` / `tool-result` — **消息级也是 parts 数组**, 与 delta 级一一对应, 这就是"过程区块"的数据模型参照。
- **推理力度**: `reasoning?: 'provider-default' | 'none' | 'minimal' | 'low' | 'medium' | 'high' | 'xhigh'` — 7 级枚举, 与 DeepSeek 的 reasoning_effort "high|max" 同概念不同分级粒度。
- **reasoning detail**: `{type:'text', signature?}` / `{type:'redacted'}` (Anthropic 式签名/遮蔽); **step 划分**: `StepResult.stepType: 'initial'|'continue'|'tool-result'` + onStepStart/onStepEnd — "思考 X 次" 的 X 在业界即 **step 计数**。
- **smoothStream** (reference 工具列表): 官方提供 chunk 平滑中间件 — 打字机补间的生态参照。

#### 5.2 assistant-ui / CopilotKit chat UI 库 (生态参照, 公开文档知识)

- **assistant-ui**: message parts 模型中 `ReasoningPart` 默认折叠 + 显示 duration ("Thought for Xs"); `ToolCallPart` 带 toolName / state (running/complete) / 自定义 avatar 与渲染组件 — 与任务简报的"图标 + 二级折叠"形态一致; 其分块思想: reasoning 与 text 是同级 part, 由 UI 决定折叠分组。
- **CopilotKit**: `useCopilotAction` 的 render prop 让每个工具自定义过程渲染 (loading/result 两态), 工具状态与消息流解耦 — 参照点: 工具渲染组件注册制 (toolName → renderer) 可平移为 ChatBubble 内的 toolName → 图标/文案映射表。

#### 5.3 Claude / ChatGPT 产品交互模式 (生态参照)

- **Claude (thinking block)**: 默认折叠; 折叠头是一句话摘要带计量 "Thought for X seconds"; 流式时折叠头实时滚动思考文本 (peek), 点击展开全文; **用户展开后流式继续写入不会收起** (与任务简报的 UI 状态一致性要求同源); 多段 thinking (工具间) 各自成块按时序排列。
- **ChatGPT (o 系模型)**: "Thinking" 折叠块, 完成后摘要化; 工具调用 (web search 等) 显示为独立图标行 + 展开看引用来源 — "查看 Y 个文件" 式摘要计数的产品先例。
- **共性抽象**: ① 默认折叠 + 计量摘要; ② 展开态是用户所有权, 流式不夺回; ③ thinking 与 tool call 是时序 parts, 展示层分区渲染但数据层保序; ④ 最终回答独立区块, 渲染升级 (流式 Text → 富文本) 在流结束时一次性发生。

## Conclusion

MindTrace 的思考展示链路**骨架全通但两端哑火**: 传输层 (requestInStream SSE + 行解析) 与 UI 层 (reasoning 折叠面板) 都在, 但流式事件枚举只有 `'reasoning'|'content'` 两种裸字符串 kind (LlmTypes.ets:133), `enableThinking` 三处硬编码 false 使请求侧主动关闭思考, 展示全靠 deepseek-v4-pro 服务端默认思考模式的"漏回" (LlmClient.ets:495 注释)。"推理力度"是 wire 层幽灵字段 (LlmTypes.ets:30 定义, LlmClient.ets:284 硬编码 'high', LlmConfig 只存 boolean 且 setEnableThinking 零调用方)。工具调用的**能力面** (ToolRegistry/AgentTool/3 只读工具/wire 类型) 与**循环骨架** (ToolCallingWorkflow StateGraph 化) 已按 spec 014/018 建成, 但**消费面为零** — ToolLoop 生产代码无调用, Conversation 的 stream_reply 是单次 LLM 调用, ToolCallingWorkflow 无事件出口, SSE+工具循环被 spec 014 明确排除在范围外。因此任务简报的 4 类事件中 thinking/text 有直接对应物, tool_call/tool_result 从事件类型、workflow 循环、UI 字段三个层面全缺。UI 改造切口清晰: ChatBubble ai 分支 :63-92 (过程) 与 :94-120 (最终回答) 双区块化, ChatMsg 加 toolCalls/processExpanded 字段, keyGen 补 reasoning.length 与工具状态因子; 摘要计数的"思考 X 次"在单轮调用下恒 1, 有意义化依赖工具循环接入。鸿蒙官方对齐: 无 Markdown/手风琴/打字机预置组件 (自绘 + animateTo + SymbolGlyph 是官方路线), SSE 用 requestInStream 自研解析或 EventSource 三方库 (faqs-network-80) 均可。

## Implications

### ① 改良计划需要拍板的决策点清单

**前端:**

| # | 决策点 | 选项与影响 |
|---|---|---|
| F1 | ChatMsg 数据模型: 平铺扩展 vs 结构化 parts 数组 | 平铺 (toolCalls? + processExpanded?) 改动小、持久化兼容; parts 数组 (Vercel UIMessage 式) 保序彻底、支持多轮 thinking 交错, 但动 ChatSession JSON 格式与全部 map+spread 字面量 (AgentFloatWindow.ets 5 处) |
| F2 | 过程区块展示结构: 分区 (上思考 Markdown + 下工具列表) vs 时序混排 | 任务简报是分区; 时序混排信息保真但组件复杂 — 若 P1 只做单轮 thinking, 分区无信息损失; 多轮时再议 |
| F3 | keyGen 策略 (AgentMessageList.ets:98) | 补 `reasoning.length + toolCalls.length + 展开态摘要`; 展开态是否留在 key (现状 reasoningExpanded 在 — 展开即行重建) 需与 @Reusable/行内 state 方案二选一 |
| F4 | 摘要计数实现位置 | AgentFloatWindow.appendAiMsg 侧累计 (与 kind 二分流同位) vs ChatMsg 派生 getter; "思考 X 次"恒 1 的问题: 摘要文案是否降级为 "思考中…" / "已深度思考" 直到工具循环落地 |
| F5 | 思考步骤的渲染 | 流式纯 Text (现状平移) vs progressive Markdown (MarkdownRenderer 已支持 text 动态喂入但每 delta 重置 visibleBlockCount, 有抖动风险) |
| F6 | @Reusable 是否本次一并做 | 双区块加重组件, 收益增大; 但需处理 aboutToReuse 参数与展开态重置 (faqs-arkui-1433) |
| F7 | 工具图标方案 | SymbolGlyph 系统图标 (ts-basic-components-symbolglyph, 需选资源名) vs 自定义 Symbol 注册 (ui-design-symbolregister) vs 资源图片 |
| F8 | 旧会话 JSON 兼容 | ChatMsg 新字段全部 optional + init 时 JSON.parse 容错 (ChatSession.ets:39-45 已有 try-catch), 但 map+spread 手写字面量漏复制新字段 = 静默丢数据, 需列入 checklist |

**后端:**

| # | 决策点 | 选项与影响 |
|---|---|---|
| B1 | 事件协议形状: 保留 `(delta, kind)` 加 kind 枚举值 vs 结构化事件对象 `{type, ...}` | 加枚举值向后兼容 (kind 联合类型扩到 4-5 个); 结构化对象 (简报的 `{"type":"thinking","content":...}`) 是 breaking change, LlmTypes/LlmClient/ReplyService/ConversationWorkflow/AgentChatService/AgentFloatWindow 全链同步改; 结构化是终态, 建议一步到位 |
| B2 | Conversation 工具循环接入方式 | stream_reply 节点内部接 ToolLoop (spec 018:74 "工具循环只调用 ToolLoop") vs conversation 自建节点 — 前者符合 spec 但 ToolLoop 需先加事件出口; **SSE+工具循环是新 spec 范围** (spec 014 明确排除) |
| B3 | enableThinking 是否随本次参数化 | 展示链路不依赖开关 (服务端漏回即可工作); 但要**稳定保证** thinking 事件供给, 需把 ReplyService.ets:81 改为 true 或可配置 — 与上游调研"删除 deepThink 开关"裁决的关系需澄清: 删除的是 UI 装饰开关, 请求侧开关是另一件事 |
| B4 | reasoning→content fallback 双发行为 (LlmClient.ets:519-521) | 新 thinking 事件后此 fallback 是否保留 (P1 bug fix 的历史包袱: 同段文本双发); 建议: content 空且 thinking 已独立emit 时不再 fallback, 或显式标记 fallback 来源 |
| B5 | reasoning_effort 可配置化 (LlmClient.ets:284) | 硬编码 'high' → LlmCallRequest 字段; P2 议题 |
| B6 | 工具面语义缺口 | "查看 Y 个文件/执行 Z 条命令"的终端/文件工具不存在 (只有笔记查询三件套); 演示场景需拍板: note_query 映射为"搜索笔记"图标+文案, 还是先造 1-2 个演示工具 (受 ADR-0010 语义约束: 查询类进 tools/) |
| B7 | ToolCallingWorkflow 事件出口形状 | onToolCall/onToolResult 回调注入 (spec 018:73 "流式 delta 和 progress 通过注入的 event sink 交付" 已有原则) vs State 加 event log channel |
| B8 | 工具调用是否入会话记忆 (AgentMemoryService) | 现状只存最终 content (ConversationWorkflow.ets:503-509); 多轮上下文回喂是否需要 tool 消息 (影响后续轮次质量) |

### ② 初步分层建议 (P0/P1/P2)

- **P0 (事件协议 + 双区块骨架, 不依赖工具循环)**: ① LlmStreamCallback 事件结构化 (B1) + thinking/text 两类先落; ② ReplyService.ets:81 enableThinking 参数化并默认开启 (B3); ③ ChatBubble 双区块化 (过程区块 = 现有 reasoning 面板升级: 摘要行 + animateTo 展开动画 faqs-arkui-348; 最终回答区块 = 现有 content 列) + ChatMsg 平铺扩展 (F1 取平铺) + keyGen 调整 (F3); ④ 展开态保护: processExpanded 沿用 reasoningExpanded 的"append 不触碰"纪律。
- **P1 (工具循环 + 工具过程展示)**: ① ToolCallingWorkflow 加事件出口 (B7) + SSE 工具循环新 spec (B2); ② Conversation stream_reply 接 ToolLoop; ③ tool_call/tool_result 事件 + UI 工具列表 (二级折叠 + SymbolGlyph 图标 F7 + 摘要计数 F4); ④ fallback 双发治理 (B4)。
- **P2 (打磨)**: reasoning_effort 可配置 (B5) + @Reusable (F6) + ChatStatusMachine 与过程区块融合 + 工具调用入记忆 (B8) + 思考步骤 progressive Markdown (F5) + EventSource 三方库评估迁移。

### ③ 用户给的 4 类 SSE 事件 vs 现有事件枚举的映射表

| 目标事件 (任务简报) | 现有系统对应物 | 映射结论 |
|---|---|---|
| `{"type":"thinking","content":"..."}` | `LlmStreamCallback kind='reasoning'` (LlmTypes.ets:133; LlmClient.ets:512-513 emit) | **语义等价, 直接映射** — 但需从裸字符串 kind 升级为结构化事件对象; 供给前提是 enableThinking 开启或服务端漏回 (B3/B4) |
| `{"type":"tool_call","tool":"terminal","content":"..."}` | **缺失** — kind 枚举无此类型; `LlmToolCall` wire 类型存在 (LlmTypes.ets:165-169) 但只在 JSON 路径 LlmCallResult.toolCalls (LlmClient.ets:159-170) 一次性返回, 无流式事件 | **需新增** — 事件类型 + ToolCallingWorkflow 事件出口 + Conversation 工具循环 (三层全缺) |
| `{"type":"tool_result","content":"..."}` | **缺失** — `ToolResult {ok, content}` (ToolRegistry.ets:11-14) 存在但只在循环内部回喂 LLM (ExecuteToolsNode.ets:24-31), 不出 UI | **需新增** — 同上; 另需决策 ok:false 的展示形态 |
| `{"type":"text","content":"..."}` | `kind='content'` (LlmClient.ets:517-518) | **语义等价, 直接映射** — 注意与 thinking 的 fallback 双发行为 (LlmClient.ets:519-521) 需一并治理 (B4), 否则思考模式下 content 会包含 thinking 副本 |

**额外现状行为 (映射表之外)**: 现有 `ChatStatusMachine` 12 步 progress 事件 (ConversationWorkflow setStep → statusMeta) 是第三条平行通道, 官方生态无直接对应 (类似 Vercel 的 onStepStart/onStepEnd 粗粒度版), 建议保留为独立通道不并入 4 类事件。

## Open questions

1. **deepseek-v4-pro `enableThinking:false` 时服务端是否仍返回 reasoning_content?** LlmClient.ets:495 注释 ("deepseek-v4-pro 默认思考模式") 暗示是, 但未实测; 这决定 P0 阶段 thinking 事件的供给是否稳定, 建议改造前用真机 + hilog 实测一轮。
2. **SSE 工具循环的产品形态**: 工具执行期间 (note_query 本地查询快, 未来终端类工具可能数秒) 过程区块显示什么 — spinner? ChatStatusMachine 文案? 是否需要 tool_input 流式展示 (Vercel 的 tool-input-start/delta 模式)?
3. **摘要文案的工具语义映射**: note_query/note_get/review_due_query 三个真实工具在 "查看 Y 个文件，执行 Z 条命令" 句式下如何措辞 (如 "检索 Y 条笔记")? 演示是否需要新增工具本体 (受 ADR-0010 与只读安全边界约束)?
4. **EventSource 三方库 vs 现有 requestInStream**: faqs-network-80 推荐三方库; 现有自研解析已稳定且刚修过 SSE 边界 bug (PR1k), 迁移收益不明 — 建议维持现状, 记录为已评估不采纳。
5. **多轮 thinking 的区块合并**: ToolLoop 接入后每步模型都可能产生 reasoning, 分区展示 (F2) 会丢失轮次信息 — 届时是否引入 step 分隔 (Vercel stepType 参照)?
6. **reasoning 的会话持久化膨胀**: reasoning 已随 ChatSession JSON 持久化 (ChatSession.ets:55), 思考链普遍数千 token, preferences 单键容量与加载性能需评估 (现 36 进制会话无限累积)。
7. **旧会话兼容验证**: 新字段 optional + JSON.parse 容错理论上兼容, 但 map+spread 手写字面量 (AgentFloatWindow.ets 5 处) 漏字段 = 静默丢数据, 需要测试锁定。
8. **系统 Symbol 图标资源名**: 终端/文件/搜索类图标在系统图标库的具体资源名未逐一确认 (Q4), 实施前需查 harmonyos-symbol 资源页。

---

## Primary source citations

- `common/src/main/ets/llm/LlmTypes.ets:13-19,22-42,108-133,135-145,147-169,171-198` — 类型全景 (enableThinking :144/:184, reasoning_effort :30, LlmStreamCallback :133)
- `common/src/main/ets/llm/LlmClient.ets:60-70,74-175,189-205,247-330,333-409,416-463,501-522` — 双路径/SSE 架构/emit (enableThinking 回退 :86-88/:262-264, thinking 注入 :281-285, reasoning emit :512-521)
- `common/src/main/ets/llm/LlmConfig.ets:18,50,320-326,459-490` — enable_thinking 持久化 (setEnableThinking 零调用方)
- `common/src/main/ets/llm/LlmGuard.ets:5-7,37-66,120-131` — LlmCaller seam
- `entry/src/main/ets/services/ReplyService.ets:47-61,63-106,113-132` — 三处 enableThinking:false (:54/:81/:123)
- `entry/src/main/ets/services/AgentChatService.ets:9-20,22-58,60-101` — 回调接口/adapter/facade
- `entry/src/main/ets/services/ChatStatusMachine.ets:20-41` — 12 步文案表
- `entry/src/main/ets/workflows/conversation/ConversationState.ets:3-60` — Step/Progress/Request 三形态/State
- `entry/src/main/ets/workflows/conversation/ConversationTypes.ets:5-16` — ConversationWorkflowCallbacks 11 项
- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets:39-54,122-231,280-364,489-565` — 图结构/流式链路/记忆
- `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets:104-185` — 回调装配/appendAiMsg 二分流/send 分流
- `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatBubble.ets:15-139` — reasoning 面板 :64-92, 三态 :95-117, 长文 :124-125
- `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets:13-53` — ChatMsg 6 字段
- `entry/src/main/ets/overlays/AgentFloatWindow/AgentMessageList.ets:18-56,71-77,87-99,101-115` — DataSource/keyGen/busy 行
- `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets:34-61` — preferences 持久化
- `entry/src/main/ets/shared/molecules/MarkdownRenderer.ets:25-53,326-412` — progressive 机制与增量喂入特征
- `entry/src/main/ets/shared/molecules/FormulaSplitRenderer.ets:30-80` — 拆分算法/块上限
- `common/src/main/ets/render/ContentProtocol.ets:32-86` — MM-MD-v1/hasFormulaSyntax
- `common/src/main/ets/tools/ToolRegistry.ets:11-76` / `ToolCatalog.ets:18-27` / `NoteQueryTools.ets:50-60,249-253` / `ToolLoop.ets:6,14-25` — 工具面 (SSE 工具循环排除声明 :6)
- `common/src/main/ets/workflow/tool-calling/ToolCallingWorkflow.ets:9,22-68` / `ToolCallingState.ets:3-19` / `nodes/CallModelNode.ets:12-44` / `nodes/ExecuteToolsNode.ets:12-50` — 循环骨架
- `skill/src/main/ets/skillability/SkillAbility.ets:20-47` / `skill/src/main/ets/workflows/intent/SkillIntentWorkflow.ets:29-74` / `SkillIntentState.ets:1-20` — note_query 生产消费链
- `agents/src/main/ets/mcp/tools/OcrTool.ets:46-58,111-174` — MCP 语义 (不实现 AgentTool)
- `docs/specs/018-agent-workflow-architecture.md:40-47,58-75,85-98` — 四领域定位/单后端硬约束
- `docs/specs/014-tool-calling-protocol.md:3,77-126` (grep 摘录) — ToolLoop 实现状态
- 全仓 grep: `enableThinking|reasoning_content|getEnableThinking|setEnableThinking` / `ToolLoop|note_query|createReadOnlyRegistry` / `new ToolLoop` — 生产 vs 测试调用映射
- 鸿蒙官方文档 (devecocli docs, documentId): `faqs-network-80` (SSE/EventSource), `faqs-network-52`, `faqs-network-81`, `faqs-network-64` (requestInStream); `faqs-arkui-348` (animateTo+if 折叠动画), `faqs-arkui-267` (measureTextSize 展开收起), `faqs-arkui-1213` (Flex 折叠); `faqs-arkui-1414` (逐字播报); `ts-basic-components-symbolglyph`, `arkts-common-components-symbol`, `ui-design-symbolregister`, `ui-design-custom-symbol-res-register` (图标); `faqs-arkweb-97` (无公式组件), `faqs-arkui-112` (RichText=WebView); `ts-custom-component-decorator-reusable`, `arkts-reusable`, `arkts-component_reuse`, `arkts-global-reuse-pool`, `bpta-best-practices-long-list`, `faqs-arkui-1433` (@Reusable)
- 生态参照 (非鸿蒙 API): Vercel AI SDK v7 `streamText` 参考 (sdk.vercel.ai/docs/reference/ai-sdk-core/stream-text, 2026-09-11 实拉) — TextStreamPart 8 种 part / UIMessage parts / reasoning 7 级枚举 / StepResult.stepType / smoothStream; assistant-ui ReasoningPart/ToolCallPart 与 CopilotKit useCopilotAction render prop (公开文档知识); Claude thinking block 与 ChatGPT Thinking 折叠交互 (产品观察)

## Last updated

2026-09-11

---

## Update — 2026-09-13 (post-#111 implementation reconciliation)

> **Scope**: amend this research doc so it stops contradicting the implementation & the
> accepted spec decisions reached on 2026-09-13. The original 2026-09-11 analysis is
> preserved above for traceability; this section only reconciles.

### Reconciliations (none of which override this document's architectural findings)

| Original claim (line) | Original wording | Reconciled statement (2026-09-13) | Source of truth |
|---|---|---|---|
| L45 / L330 / L352 | `LlmStreamCallback :133 (delta: string, kind: 'reasoning' \| 'content')` | The 2-value `(delta, kind)` type has been **replaced** by a 4-value `StreamEvent` family `{type, ...payload}` with `type ∈ 'thinking' \| 'text' \| 'tool_call' \| 'tool_result'`. P0 emits only `thinking` / `text`; `tool_call` / `tool_result` are reserved seats per [ADR-0015](../../adr/0015-structured-stream-events.md). The seam `LlmStreamCallback` no longer exists in `common/src/main/ets/llm/LlmTypes.ets`. | ADR-0015; `common/src/main/ets/llm/LlmTypes.ets:128-160`; `common/src/test/LlmStreamEvents.test.ets` |
| L128 | `ReplyService.ets:54/:81/:123 enableThinking: false` | The three explicit `enableThinking: false` overrides were **removed** in the same #111 slice. `ReplyService` was rewritten as a fresh module (`entry/src/main/ets/services/ReplyService.ets`, 227 LOC, header block dated 2026-09-13); the old 54/81/123 line numbers no longer exist. `DEFAULT_ENABLE_THINKING = true` now lives in `common/src/main/ets/llm/LlmConfig.ets`.` and is the sole supply. | `LlmConfig.ets:38`; `ReplyService.ets`; commit `2990579` |
| L186 | `ChatMsg 6 字段 reasoningExpanded? 默认收起` | `reasoningExpanded` exists but the **default is "expanded"**, not "collapsed". Implementation: `reasoningExpanded !== undefined ? msg.reasoningExpanded : true` in both `AgentFloatWindow.ets:177` and `ChatBubble.ets:25`. Legacy messages without explicit value render expanded. | `ChatBubble.ets:24-25`; `AgentFloatWindow.ets:177-178` |
| L193 / L300 / L322 | `chatItemKey` 含 `reasoningExpanded` (行级重建) | **`reasoningExpanded` is NOT in `chatItemKey`**. Final key shape: `id + content.length + reasoning.length + streaming`. Fold state lives in `ChatBubble` as an internal `@State` (`aboutToAppear` initialized from `msg.reasoningExpanded`); the parent array is updated via `onToggleReasoning` only for persistence, and `copyChatMsg` preserves `reasoningExpanded` so a content-driven rebuild does not lose the expanded state. Rationale (commit `2e27083`): key-flip would destroy the row and kill the `animateTo` fold animation. | `ChatModels.ets:41-47`; `ChatBubble.ets:24-25`; commit `2e27083`; ADR-0015 § "Accepted UI Amendment — 2026-09-13" |
| L219 | "`reasoningExpanded` 是独立于 content/reasoning 的字段,append 不触碰" | Still true at the **persistence / ChatMsg shape** layer. But at the **list-row layer**, the "no touch" discipline now applies through `copyChatMsg`'s field-by-field copy (not map+spread) in `ChatModels.ets:55-64`; any future P1 field (e.g. `toolCalls`, `processExpanded`) must be added there and to `applyStreamEventToChatMsg` (`:73-83`). The 5 hand-rolled literal sites this line warned about have shifted to one reducer location. |

### Out-of-scope but worth flagging

- The reconciliation above targets the **2026-09-13 accepted UI Amendment** position.
  A separate design conversation in [`docs/specs/021-chat-streaming-incremental-rendering.md`](../../specs/021-chat-streaming-incremental-rendering.md) and [`docs/research/chat-markdown-latex-render-jank-2026-09-13.md`](../chat-markdown-latex-render-jank-2026-09-13.md) proposes a **third position** (`chatItemKey` = `id` or `id + streaming`, removing length-based keys entirely) to fix finish-time row churn. That proposal is parallel to #111 and is **not part of the #111 slice**; it should be tracked under spec 021 / ticket-0 separately and is intentionally not adopted here.
- The 2026-09-13 UI Amendment also chose **not** to bring tool-call/tool-result event types into the P0 consumer (default branch in `applyStreamEventToChatMsg` returns the message unchanged). That is consistent with ADR-0015's "reserved seats for P1" wording, not with this document's earlier "P0 emits no tool events" framing which implied consumers might break.

### Cross-references after reconciliation
- Spec source of truth: [`docs/specs/019-reasoning-process-display-p0.md`](../../specs/019-reasoning-process-display-p0.md) § "Accepted UI Amendment — 2026-09-13"
- ADR source of truth: [`docs/adr/0015-structured-stream-events.md`](../../adr/0015-structured-stream-events.md)
- Implementation: [`entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets`](../../../entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets), [`entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatBubble.ets`](../../../entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatBubble.ets), [`entry/src/main/ets/services/ReplyService.ets`](../../../entry/src/main/ets/services/ReplyService.ets)

> 2026-09-13 reconciliation note appended by two-axis code review (no overwrite of the original 2026-09-11 findings, per AGENTS.md red line 3).
