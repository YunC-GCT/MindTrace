# 023 - Agent 运行时间线基础设施

> **Status**: foundation implemented, workflow emission pending (2026-09-21)
> **Related**: [ADR-0015](../adr/0015-structured-stream-events.md) · [spec 014](./014-tool-calling-protocol.md) · [spec 018](./018-agent-workflow-architecture.md) · [spec 019](./019-reasoning-process-display-p0.md)

## Problem

`ChatMsg` 原先只有 `reasoning` 与 `content` 两个字符串,只能表达“先思考、后回答”。真实 Agent 运行可能按以下顺序交错:

```text
thinking -> tool_call -> tool_result -> thinking -> text
```

继续增加并列区域会丢失顺序,也会让 UI 直接理解 ToolCallingWorkflow、工具注册表或节点状态。

## Implemented Foundation

### Ordered run model

`AgentRunModels.ets` 定义 `AgentRunPart[]`,Part 类型为:

- `thinking`: 一次连续思考阶段。
- `tool`: 一次工具调用及其结果,通过 `toolCallId` 原位更新。
- `answer`: 用户可见的真实回答。
- `status`: workflow 生命周期状态预留位。
- `error`: 结构化失败预留位。

Part 状态固定为 `pending | running | success | failed`。`applyStreamEventToAgentRun` 是 `StreamEvent` 到 UI 模型的唯一 reducer。

### Compatibility

`ChatMsg` 新增可选 `runParts`,旧字段 `content`、`reasoning`、`reasoningExpanded` 保留。历史会话缺失 `runParts` 时通过 `projectLegacyAgentRun` 即时投影,无需数据库或 Preferences 迁移。不存在运行过程总展开字段;每个展示模块自行管理局部交互状态。

流式写入继续同步旧字段:

- `thinking` 同时累积到 `reasoning` 和 thinking Part。
- `text` 同时累积到 `content` 和 answer Part。
- 工具事件只进入 Part,不得污染最终回答正文。

### Presentation

`AgentRunPanel` 按 Part 原始顺序分发。思考、工具、状态和错误放在带边框的过程视觉容器中,但容器没有标题按钮或总折叠开关;各步骤仍为独立模块,回答保持独立显示。

`AgentThinkingStep` 默认折叠:使用紧凑无框标题行,不显示前置图标或右侧展开箭头;运行中在思考标题右侧以小字号单行 Marquee 滚动最新片段,完成后在同一行显示开头摘要;点击整行后隐藏同行摘要,仅在下一行展开当前思考全文。`AgentToolStep` 独立显示工具生命周期,输入与结果默认不直接暴露,用户主动点“查看详情”后才显示。

展示文件不 import workflow、ToolRegistry、service、viewmodel、database 或 LlmClient。

## Event Semantics

- 连续 `thinking` delta 合并到当前 running thinking Part。
- 新种类事件到来时关闭先前 running 的非工具 Part。
- `tool_call.argumentsJson` 被视为完整参数并替换 detail;`tool_call.delta` 被视为参数片段并追加。
- `tool_result` 按 `toolCallId` 更新原工具 Part;找不到调用时创建可见的孤立工具结果,不静默丢弃。
- `tool_result.ok === false` 映射为 `failed`,其他结果映射为 `success`。
- `finishAgentRun` 将未关闭的思考/回答设为成功,未收到结果的工具设为失败。

## Workflow Seam

本切片不修改 `ToolCallingWorkflow` 的生产编排。后续 workflow 通过事件 sink 发出事件,UI adapter 再调用以下稳定入口:

- LLM 四类事件: `applyStreamEventToChatMsg`。
- workflow 阶段: `appendAgentRunStatus`。
- workflow 失败: `appendAgentRunError`。
- 运行结束: `finishChatMsg`。

State 中不得放 UI callback、ArkUI 引用或 `AgentRunPart`;event sink 是 workflow 构造依赖或运行依赖。

## Acceptance

- [x] thinking/tool/result/rethinking/answer 顺序可被模型保留。
- [x] 工具调用和结果按 `toolCallId` 合并。
- [x] 工具失败与缺失结果具有明确状态。
- [x] 旧会话无需迁移即可显示。
- [x] UI 展示模块与业务层隔离。
- [x] ArkTS lint、Node tests、naming-lint 和 entry HAP build 通过。
- [ ] 流式 key 更新后仍保留思考与工具组件的局部展开态。
- [ ] 回答与过程 Part 按原始事件顺序混排渲染,不再采用过程/回答两段式。
- [ ] 缺少 `toolCallId` 的工具事件被拒绝或隔离,不会覆盖相邻调用。
- [ ] ToolCallingWorkflow 发出真实 `tool_call/tool_result` 生命周期事件。
- [ ] ConversationWorkflow 把 workflow status/error 接入当前 AI 消息。
- [ ] 真机验证长工具结果、连续多工具和中断恢复。

## Out Of Scope

- 模拟工具事件或演示数据。
- 写类工具、HITL、Checkpoint、Subgraph 和并行 fan-out。
- 把原始工具 JSON 默认暴露给用户。
- 在 UI 内读取 ToolRegistry 或 workflow State。
