# 041 — Chat 工具回复（ToolLoop 接入 conversation workflow）

> **Status**: enabled (2026-11-05) — 默认开启，仅笔记检索意图触发；普通问答保持流式
> **Related**: [spec 014](./014-tool-calling-protocol.md) · [spec 039](./039-agent-workflow-first.md) · [ADR-0012](../adr/0012-tool-calling-protocol.md) · [spec 044](./044-rag-recall-and-evidence-quality.md)
> **Code**: `agents/src/main/ets/conversation/ConversationWorkflow.ets` · `ConversationWorkflowPorts.ets` · `ConversationToolReplyFlags.ets` · `common/src/main/ets/tools/ToolLoop.ets`
> **Verified by**: `node scripts/agent-gate/index.mjs`；默认关闭，无真机行为变更

## 1. 目标

把已有的 `ToolLoop`（`ToolCallingWorkflow`）接入 conversation workflow，为后续「聊天中查询本机笔记」留出唯一入口；先默认关闭，保证现有 `ReplyService` 行为不变。

## 2. 接线

- `ConversationToolReplyFlags.CHAT_TOOL_REPLY_ENABLED = false`。
- 开启时：`save_reply_input` 的 text 请求进入 `tool_reply` 节点；该节点用 `ToolLoop + ToolCatalog.createReadOnlyRegistry()` 走 JSON 工具循环，非流式。
- 关闭时：图里不添加 `tool_reply`，`complete_reply` / `stream_reply` 路径与原来一致。
- `ConversationToolReplyAdapter` 复用 `IntentClassifier.buildReplyMessages`，与 `ReplyService` 共用同一套系统提示和消息形状。

## 3. 非目标

- 不做流式工具循环（`ToolLoop` 只支持 JSON 路径）。
- 不加写工具；只读目录来自 `ToolCatalog.createReadOnlyRegistry()`。
- 不改变默认 UX、不改变 A2A、不改变 `ReplyService` 的既有路径。

## 4. 开启前验收

- 真机聊天能触发 `note_query` / `note_query_rag` 并正确展示结果；
- 工具循环不突破首字 / 总时延预算；
- golden 与现有 conversation 测试不回归；
- 工具失败时回退到 `ReplyService` 或明确报错，不静默吞错；
- 需要单独 ADR 决定「默认开启 + 工具结果如何呈现」。

## 5. 开启策略（2026-11-05）

`CHAT_TOOL_REPLY_ENABLED = true`，但**不是所有文本都走工具链**：`save_reply_input` 增加意图闸门
`ConversationToolReplyFlags.shouldUseTools(userContent)`，只有命中「笔记 / 知识库 / 错题 / 复习 /
我保存过 / 我记得 / 查一下我」这类关键词才进 `tool_reply`。

理由：普通知识问答不需要工具，闸门避免多一轮模型调用 + 工具执行的额外开销；笔记检索类请求才付出这个代价。
工具链本身已支持流式（见 §6），所以闸门是为了「省一次工具轮」，不再是为了「避免丢流式」。

工具结果呈现：模型最终回答直接包含工具检索结论，来源块沿用 `applyEvidenceToAnswer` 的证据脚注，
不额外展示原始工具 JSON。

工具结果预算：超过 4000 字时按 JSON 结构裁剪——对象按数组字段丢尾部条目、顶层数组按条丢弃、
无数组时缩短超长字符串；不再做会破坏 JSON 的字符截断。

## 6. 流式工具循环（2026-11-05）

- `LlmStreamParser`：解析 SSE 里的 `tool_calls` 增量（按 `index` 分片）。
- `LlmClient.callStreamInternal`：按 index 拼接 `id/name/arguments`，流结束后返回 `LlmCallResult.toolCalls`。
- `ToolCallingStreamingWorkflow`：每轮走 SSE；有 `toolCalls` 就执行并回喂，否则返回最终回答（已逐字送出）。
- `ToolExecutionGuard` / `ToolResultBudget` 抽成共享模块，JSON 与流式两条路径共用。
- `tool_reply` 节点改走 `handleStream(..., true)`；证据脚注、引用校验、重连回退保持不变。

真机对比（2026-11-05，设备 `3XTYD24C16203663`）：

| 指标 | 非流式（旧） | 流式（新） |
|---|---|---|
| 首字 | 约 20s（整包） | 3.4–3.8s |
| 总耗时 | 约 20–21s | 7.7–7.9s |
| 工具结果 | `note_query` 被字符截断 | `truncated=1 dropped=2`，仍是合法 JSON |
