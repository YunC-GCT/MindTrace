# 041 — Chat 工具回复（ToolLoop 接入 conversation workflow）

> **Status**: implemented (2026-11-02, default off) — 默认关闭，无用户可见行为变更
> **Related**: [spec 014](./014-tool-calling-protocol.md) · [spec 039](./039-agent-workflow-first.md) · [ADR-0012](../adr/0012-tool-calling-protocol.md)
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
