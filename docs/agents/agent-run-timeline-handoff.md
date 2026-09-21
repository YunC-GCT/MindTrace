# Agent 运行时间线接入交接

> 面向后续 Agent workflow 接入者。当前 UI 与 reducer 基础设施已落地,真实工具生命周期事件尚未从 ToolCallingWorkflow 发出。

## 当前状态

已完成:

- `StreamEvent` 的 `thinking/text/tool_call/tool_result` 均可进入有序 `AgentRunPart[]`。
- `tool_call` 与 `tool_result` 通过 `toolCallId` 合并为一个工具步骤。
- 思考、工具、状态、错误和回答已有独立展示模块。
- 过程 Part 在一个无总开关的带边框视觉容器中按顺序出现,每个步骤仍是独立模块。
- 每个思考模块默认折叠;紧凑无框标题行不显示前置图标或右侧展开图标,运行中标题右侧小字滚动最新片段,完成后同一位置显示开头摘要;整行可点击,展开后同行摘要隐藏。
- 历史 `reasoning/content` 会话即时投影,Preferences 无迁移要求。

尚未完成:

- `LlmClient` SSE 路径目前只稳定 emit `thinking/text`。
- `ToolCallingWorkflow` 当前走非流式模型调用,没有事件 sink。
- Conversation workflow 的 `onProgress` 仍只进入 `ChatStatusMachine`;浮窗的 `setStatusMeta` 当前为空实现。
- `appendAgentRunStatus` 与 `appendAgentRunError` 已提供,但尚未接生产 workflow。

## 代码导航

| 责任 | 文件 |
|---|---|
| 有序 Part、reducer、兼容投影 | `entry/src/main/ets/overlays/AgentFloatWindow/chat/AgentRunModels.ets` |
| 消息兼容字段与 StreamEvent 入口 | `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets` |
| 过程视觉容器与无状态顺序路由 | `entry/src/main/ets/overlays/AgentFloatWindow/chat/AgentRunPanel.ets` |
| 独立思考步骤与局部折叠 | `entry/src/main/ets/overlays/AgentFloatWindow/chat/AgentThinkingStep.ets` |
| 工具步骤 | `entry/src/main/ets/overlays/AgentFloatWindow/chat/AgentToolStep.ets` |
| 状态/错误步骤 | `entry/src/main/ets/overlays/AgentFloatWindow/chat/AgentStatusStep.ets` |
| 回答步骤 | `entry/src/main/ets/overlays/AgentFloatWindow/chat/AgentAnswerStep.ets` |
| UI 消息写入回调 | `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets` |
| Conversation 编排 | `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets` |
| Tool workflow | `common/src/main/ets/workflow/tool-calling/ToolCallingWorkflow.ets` |
| 模型/工具节点 | `common/src/main/ets/workflow/tool-calling/nodes/` |

## 必须保持的事件契约

### Thinking 与回答

连续相同种类的 delta 合并;工具或另一轮思考出现后必须新建 Part,不能把多轮思考重新拼成一个字符串。

```text
thinking(A) -> tool(call-1) -> tool_result(call-1) -> thinking(B) -> text(C)
```

必须得到五个阶段中的四个 Part:`thinking(A), tool(call-1), thinking(B), answer(C)`。

### 工具调用

每次调用必须提供稳定且非空的 `toolCallId`。一次调用的所有参数片段和结果都使用同一个 ID。

- `argumentsJson`: 完整参数快照,每次覆盖。
- `delta`: 参数或结果增量,每次追加。
- `result`: 完整结果快照,覆盖当前结果。
- `ok: false`: 明确失败;不要把失败文本包装成成功结果。

并发工具调用将来可按 ID 正确更新,但当前 UI 仍按事件到达顺序展示,没有并行分组视觉。

### Status 与错误

workflow 生命周期不得伪装成 `thinking` 或 `text`。entry adapter 应使用:

```ts
appendAgentRunStatus(parts, messageId, userFacingStatus, status)
appendAgentRunError(parts, messageId, userFacingError)
```

传入 UI 的文字必须是面向用户的摘要,不能直接传异常堆栈、prompt、API Key、原始数据库行或完整工具协议 JSON。

## 推荐接线顺序

1. 在 `common` 定义最小只读 observer interface,覆盖 model start/end、tool start/end 和 workflow error。
2. 通过构造注入或 `run` options 把 observer 交给 `ToolCallingWorkflow`;不要把 callback 放入 `ToolCallingState`。
3. `CallModelNode` 在拿到 tool calls 后发 `tool_call`;`ExecuteToolsNode` 在每个工具结束后发 `tool_result`。
4. entry 的 Conversation adapter 把 observer 事件转成现有 `StreamEvent`,再调用 `appendAiMsg(messageId, event)`。
5. 将 Conversation `onProgress` 映射为少量用户可理解的 status Part;不要把每个内部 Node 名称逐字显示。
6. fatal error 追加 error Part,随后调用 `finishAiMsg`;可恢复工具错误只关闭对应工具 Part,允许模型继续运行。
7. 完成 SSE 工具循环后复用同一事件契约,不要建立第二套 UI reducer。

## 不要这样接

- 不要让 `AgentRunPanel` import ToolRegistry、ToolCallingState 或任何 Node。
- 不要给过程视觉容器增加总折叠开关;新增 Part 必须拥有独立展示模块或映射到既有模块。
- 不要把工具过程拼进 `ChatMsg.content`;该字段仍是 Reply Body 与会话上下文的唯一答案正文。
- 不要根据工具名称猜测 `toolCallId`。
- 不要同时保留过程式 ToolLoop 和新 workflow 两条生产路径。
- 不要为了演示在 UI 注入假工具步骤。
- 不要把 `runParts` 作为 workflow State;它是 entry UI 的展示模型。

## 持久化与兼容

`ChatSessionManager` 对整个 `ChatSession` 做 JSON 序列化,因此新增可选字段会随会话自然保存。读取旧 JSON 时字段缺失合法。移除 `content/reasoning` 需要独立迁移 spec,当前禁止提前删除。

工具结果可能很大。正式接线前必须确定持久化裁剪策略:建议 Part 只保存用户摘要和受限详情,完整结果仍由工具/领域数据所有者保存。不要无限增长 Preferences。

## 当前已知限制与范围例外

以下限制已在 2026-09-21 PR 前审查中确认。当前 UI 效果可提交,但后续接入真实 Agent workflow 前必须重新处理,不得把它们视为已完成能力:

- `chatItemKey` 与 `agentRunPartKey` 当前包含内容长度或状态。流式 token 与完成状态会改变 key,可能重建 `AgentThinkingStep` / `AgentToolStep` 并把组件内部 `detailOpen` 恢复为默认折叠。后续需要在保持增量刷新的同时提供稳定的步骤身份与可恢复的局部展开态。
- `AgentRunPanel` 当前先渲染过程 Part、再渲染回答 Part,因此展示仍是过程/回答两段式。正式支持 `text -> tool -> thinking -> text` 前,必须改为按 `AgentRunPart[]` 的原始顺序逐项分发,同时保持过程项的共享视觉容器语义。
- reducer 在事件缺少 `toolCallId` 时可能复用最后一个运行中工具 ID。生产 workflow 必须为每次调用提供稳定非空 ID;UI reducer 也应拒绝或隔离无 ID 调用,不得让相邻工具互相覆盖。
- 会话历史面板、长按删除和头部关闭入口调整并非 Agent 时间线协议的一部分。本次作为用户确认的 UI 范围例外一并提交;后续修改时应与时间线/工作流接线分别评审,不得据此扩大 Agent 展示模块职责。

## 验证清单

- `thinking -> tool -> result -> thinking -> answer` 顺序正确。
- 两个连续工具各自按 ID 更新,不互相覆盖。
- 工具失败后模型继续回答时,失败步骤保留且回答正常显示。
- thinking/tool/status/error 在过程视觉容器内作为独立模块顺序出现,任一模块交互不隐藏其他模块或回答。
- 运行中思考在标题右侧持续滚动最新片段,完成后同一行固定为开头摘要。
- 展开一个思考或工具详情时不改变其他 Part 的局部展开状态,回答正文始终可见。
- 历史会话、无思考回答、纯思考中断均可显示。
- 运行 ArkTS lint、Node tests、Hypium、naming-lint、diff check 和 entry HAP build。

## 关联资料

- [`../specs/023-agent-run-timeline-foundation.md`](../specs/023-agent-run-timeline-foundation.md)
- [`../specs/018-agent-workflow-architecture.md`](../specs/018-agent-workflow-architecture.md)
- [`../specs/014-tool-calling-protocol.md`](../specs/014-tool-calling-protocol.md)
- [`../adr/0015-structured-stream-events.md`](../adr/0015-structured-stream-events.md)
