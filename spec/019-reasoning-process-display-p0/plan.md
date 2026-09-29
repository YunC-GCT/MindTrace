# Implementation Plan: 019 Reasoning Process Display P0 — #111 StreamEvent Protocol Vertical Slice

**Input**: Feature specification from `spec/019-reasoning-process-display-p0/spec.md`

## Summary

本计划按现有 MindTrace 五模块架构原地改造 #111：在 `common` 的 LLM 层定义结构化 `StreamEvent` 协议并替换 `(delta, kind)` 流式回调；在 `common/src/main/ets/llm/LlmClient.ets` SSE 适配中输出 `thinking`/`text` 事件并删除 reasoning→content 伪装重发；在 `entry` 的 ReplyService、ConversationWorkflow、AgentChatService、AgentFloatWindow 链路中完成双通道分发；在 `common/src/main/ets/llm/LlmConfig.ets` 默认开启 thinking；并以 TDD seam 锁定 SSE 解析与事件分发回归。

该切片遵循 ADR-0015 的 same-PR 硬约束：协议改造与 fallback 删除不可拆分。范围仅 #111，不纳入 spec 019 的其他 UI 动画、keyGen、历史会话 UI 完整验收或工具过程展示票。

## Technical Context

**Language/Version**: ArkTS 1.1 strict（MindTrace 当前 API 9，strict 规则由项目 lint 强制守门）
**Primary Dependencies**: HarmonyOS `@kit.NetworkKit` HTTP streaming、`@kit.ArkData.preferences`、Hypium 测试框架、项目自研 `scripts/arkts-lint`
**State Management**: 增量改造现有项目，保留当前 ArkUI State Management V1；不引入 V2 迁移
**Storage**: `common/src/main/ets/llm/LlmConfig.ets` 使用 preferences；ChatMsg 现有 JSON 会话持久化保持字段兼容，不新增持久化字段
**Testing**: Hypium tests under `common/src/test` and `entry/src/test`；ArkTS strict check via `arkts_check`；project lint via `node scripts/arkts-lint/index.mjs --quiet`；full lint tests via `npm --prefix scripts/arkts-lint test`；build via HarmonyOS project build
**Target Platform**: HarmonyOS mobile app，MindTrace `entry` HAP + `common`/`agents`/`skill`/`cardservice` HSP topology
**Project Type**: Existing HarmonyOS/ArkTS multi-module mobile app
**Performance Goals**: 流式 token 到达后保持逐增量分发，不引入额外网络轮询或 UI 阻塞；SSE 解析保持线性处理
**Constraints**: 不保留新旧双轨；不新增 UI 思考开关；不把思考文本复制到最终回答；不混入当前工作区既有无关调研/开关删除改动；最终 code-review 在工具链支持时使用 `GLM-5.3` + reasoning `max`
**Scale/Scope**: #111 单票纵切，涉及 `common` LLM 层、`entry` conversation/reply/floating-window adapter 层、2 个测试模块与 SDD 文档

## Project Structure

### Documentation (this feature)

```text
spec/019-reasoning-process-display-p0/
├── spec.md
├── plan.md
└── tasks.md
```

### Source Code (repository root)

```text
common/src/main/ets/
├── llm\
│   ├── LlmTypes.ets        # StreamEvent / stream callback / call request contract
│   ├── LlmClient.ets       # requestInStream adapter, SSE data-to-event conversion, fallback removal
│   └── LlmConfig.ets       # enableThinking default and reset/load fallback behavior
└── Index.ets               # public exports for StreamEvent-related types

entry/src/main/ets/
├── services\
│   ├── ReplyService.ets     # stream sink migration, thinking/text channel handling, explicit false override removal
│   └── AgentChatService.ets # adapter migration to structured stream events
├── workflows\conversation\
│   ├── ConversationTypes.ets    # workflow callback contract migration
│   └── ConversationWorkflow.ets # stream reply sink forwarding and interruption message handling
└── overlays\AgentFloatWindow\
    └── AgentFloatWindow.ets     # UI callback consumption: thinking -> reasoning, text -> content

common/src/test/
└── LlmStreamEvents.test.ets      # Seam A: SSE delta -> StreamEvent behavior tests

entry/src/test/
└── AgentChatStreamEvents.test.ets # Seam B: event -> ChatMsg field dispatch behavior tests, if adapter is testable
```

**Structure Decision**: 本计划跟随现有 MindTrace 架构和目录约定，不引入 MVVM 迁移或新目录层级。`common` 继续拥有 LLM 协议与 transport seam；`entry` 继续拥有浮窗 UI、conversation workflow 和 AgentChatService facade；测试分别落在对应模块的既有 `src/test` 目录。该切片是跨层协议纵切，但文件拆分保持最小化，以避免产生新旧流式协议双轨。

## Complexity Tracking

无计划中的架构违规。复杂性来自必须跨 `common` 与 `entry` 同步迁移同一流式协议；ADR-0015 已明确这是避免双发/空白中间态的必要复杂度。

## Research & Decisions

- **Decision**: 继续使用 HarmonyOS `requestInStream` 自研 SSE 适配，不引入 EventSource 三方库。
  - **Rationale**: 现有 `common/src/main/ets/llm/LlmClient.ets` 已基于 `requestInStream` 接入；官方文档说明 `requestInStream` 通过 `dataReceive` 接收 `ArrayBuffer` 流式数据，通过 `dataEnd` 结束并销毁请求对象，符合当前实现模型。spec 019 明确 EventSource 不采纳。
  - **Alternatives considered**: EventSource 三方库迁移；被 spec 019 排除，且会扩大 #111 范围。

- **Decision**: `StreamEvent` 协议定义在 `common/src/main/ets/llm/LlmTypes.ets`，并通过 `common/src/main/ets/Index.ets` 导出。
  - **Rationale**: `common` 是 LLM 协议、LlmClient、ToolLoop 的公共所有者；`entry` conversation 链路已通过 `common` 导入 LLM 类型。把事件类型放在 common 可避免 entry 与 common 各自定义协议造成漂移。
  - **Alternatives considered**: 在 `entry` 定义 UI 专用事件类型；会导致 LlmClient 与 UI 回调之间存在重复映射协议，不利于 P1 tool event 复用。

- **Decision**: P0 完整定义四类事件语义：`thinking`、`text`、`tool_call`、`tool_result`；P0 只实际 emit `thinking` 与 `text`。
  - **Rationale**: ADR-0015 要求一次性完成四值联合定义，避免 P1 工具事件再次改变回调签名。当前 #111 不实现工具事件 emit，以保持范围聚焦。
  - **Alternatives considered**: P0 只定义 `thinking`/`text`；会在 P1 扩展 union 时再次触发全链签名修复。

- **Decision**: 将 SSE delta 到 `StreamEvent` 的转换提取为可测试纯 seam，并保持 `common/src/main/ets/llm/LlmClient.ets` buffer/transport 逻辑只负责调用该 seam。
  - **Rationale**: #111 明确要求 Seam A 覆盖“思考非空/回答空”、“null delta”、“空 choices”、“思考先于回答”。纯 seam 可在 `common/src/test` 用 fixture 稳定验证，不依赖网络或设备流式响应时序。
  - **Alternatives considered**: 只测 `LlmClient` 私有方法或真机 SSE；会把网络、buffer 与协议转换耦合，回归定位困难。

- **Decision**: 删除 reasoning→content 伪装重发，只保留真实 `thinking` 与真实 `text` 通道。
  - **Rationale**: 这是 ADR-0015 same-PR 硬条款；保留伪装会继续把思考文本复制进最终回答，先删不改消费端会复现 UI 空白。
  - **Alternatives considered**: 保留兼容 fallback 到后续票再删；被 ADR-0015 明确拒绝。

- **Decision**: `entry/src/main/ets/services/ReplyService.ets` 的流式结果只把 `text` 事件计入最终回答正文；`thinking` 事件只向上游 sink 传递，不进入最终 answer content。
  - **Rationale**: Chat memory 与最终回答区应保存/展示真实回答，而不是思考链。该边界确保即使 UI 累积 reasoning，也不会污染 assistant content 的持久化。
  - **Alternatives considered**: 把所有事件 delta 都并入 `StreamReplyResult.content`；会重新引入思考文本污染最终回答的问题。

- **Decision**: `entry/src/main/ets/services/AgentChatService.ets`、`entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets` 与 `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets` 采用结构化事件通道分发：`thinking` 累积到 ChatMsg.reasoning，`text` 累积到 ChatMsg.content，保留未实现事件类型 default 兜底。
  - **Rationale**: ChatMsg 已有 `reasoning` 与 `content` 字段，P0 零新增字段即可满足功能；默认兜底保证 P1 之前保留事件不会破坏 P0 消费端。
  - **Alternatives considered**: 新增 ChatMsg 字段或分离 UI-only 状态；会引入旧会话兼容风险，不符合 #111 范围。

- **Decision**: `enableThinking` 默认值改为 true，并移除 `entry/src/main/ets/services/ReplyService.ets` 中三处显式 false 覆盖。
  - **Rationale**: issue #111 明确要求稳定开启思考供给；LlmClient 已有 request 未定义时回退 config 的链路。`common/src/main/ets/llm/LlmConfig.ets` 的 load/reset/default 三处需要一致，否则“恢复默认”或“无旧配置”仍会关闭 thinking。
  - **Alternatives considered**: 新增 UI 开关或只改流式路径；UI 开关被 spec 019 排除，只改流式路径会留下配置不一致。

- **Decision**: TDD 优先落在 Seam A 与 Seam B；若 AgentChatService adapter 无法直接单测，则在实施报告中说明降级并用集成/真机验收替代。
  - **Rationale**: 用户要求“/tdd where possible, at pre-agreed seams”；spec 019 已预先同意 Seam A/B。Seam A 必须单测；Seam B 以 service/adapter 可测性为先，不为测试强行重构 UI。
  - **Alternatives considered**: 只做手工验收；不足以锁定 parser 与通道串写回归。

- **Decision**: 最终 code-review 记录模型要求，但不把模型切换能力假定为可用。
  - **Rationale**: 当前主 agent 工具接口没有模型切换参数；用户要求“使用 GLM-5.3、推理强度 max”已纳入需求。若 code-review skill 或外部工具不支持选择模型/推理强度，交付报告必须记录限制并完成可用审查。
  - **Alternatives considered**: 声称已切换模型但无工具证据；不可验证，不符合交付约束。

## Data Model

### StreamEvent

| 字段 | 语义 | P0 行为 | 验证要求 |
|------|------|---------|----------|
| type | 事件类别：thinking/text/tool_call/tool_result | P0 emit thinking 与 text；tool_* 仅保留类型座位 | 编译期类型覆盖四值；消费端对未实现类型兜底 |
| delta/content payload | 增量文本或事件主体 | thinking 表示思考增量；text 表示最终回答增量 | 思考非空/回答空时仅 thinking；回答非空时 text |
| tool payload | 工具调用/结果相关数据 | P0 不 emit | P1 复用 spec 014 LlmToolCall/ToolResult 语义，不改回调签名 |

### SSE Delta Mapping

| 输入条件 | 输出事件 | 输出数量 | 备注 |
|----------|----------|----------|------|
| choices 为空 | 无事件 | 0 | 不报错 |
| delta 为 null 或不可用 | 无事件 | 0 | 不报错 |
| reasoning_content 非空且 content 空 | thinking | 1 | 禁止额外 text fallback |
| content 非空且 reasoning_content 空 | text | 1 | 正常最终回答 |
| reasoning_content 与 content 均非空 | thinking 后 text | 2 | 保持思考先于回答 |

### ChatMsg Compatibility

| 字段 | 本次用途 | 持久化兼容性 |
|------|----------|--------------|
| content | 只累积 `text` 事件 | 现有字段，旧会话继续可读 |
| reasoning | 只累积 `thinking` 事件 | 现有字段，旧会话缺省/空值按现状处理 |
| streaming | 流式状态保持 | 不改变语义 |
| reasoningExpanded | P0 不改变 | 非 #111 范围，key/动画票不在本次实现 |

### Thinking Supply Configuration

| 配置点 | 当前问题 | 目标状态 |
|--------|----------|----------|
| cachedEnableThinking 初始值 | false 导致默认关闭 | true |
| preferences load fallback | 缺省读取 false | 缺省读取 true |
| resetDefaults | 恢复为 false | 恢复为 true |
| ReplyService request override | 三处显式 false | 删除覆盖，使用 LlmClient config fallback |

## Contracts & Interfaces

### Common LLM Contract

| Contract | Location | Required Change |
|----------|----------|-----------------|
| Stream event type | `common/src/main/ets/llm/LlmTypes.ets` | 定义 `thinking/text/tool_call/tool_result` 四类事件语义；P0 只 emit 前两类 |
| LlmStreamCallback | `common/src/main/ets/llm/LlmTypes.ets` | 从 `(delta, kind)` 改为单个结构化 event 参数 |
| LlmCallRequest.onDelta | `common/src/main/ets/llm/LlmTypes.ets` | 跟随新 callback contract |
| Public exports | `common/src/main/ets/Index.ets` | 导出 StreamEvent 相关类型，供 entry 层引用 |

### SSE Parser Seam A

| Aspect | Contract |
|--------|----------|
| Input | 单条 SSE `data:` 后的 JSON payload 字符串 |
| Output | 零个或多个 `StreamEvent`，顺序与协议要求一致 |
| Throws | JSON 语法不完整/非法时可抛出，以保留现有 buffer 重试策略；有效 JSON 的空 choices/null delta 不抛 |
| Tests | `common/src/test/LlmStreamEvents.test.ets` 覆盖四个 #111 fixture |

### Entry Conversation Contract

| Contract | Location | Required Change |
|----------|----------|-----------------|
| ReplyEventSink | `entry/src/main/ets/services/ReplyService.ets` | 接收结构化 stream event；只把 text 事件计入最终回答内容 |
| Conversation callbacks | `entry/src/main/ets/workflows/conversation/ConversationTypes.ets` | append 回调接受结构化 event 或等价语义对象，不再使用旧 `kind` union |
| AgentChat callbacks | `entry/src/main/ets/services/AgentChatService.ets` | adapter 透传结构化事件，不过滤 thinking |
| FloatWindow append | `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets` | thinking -> reasoning；text -> content；tool_* default 兜底 |

### Verification & Delivery Contract

| Requirement | Contract |
|-------------|----------|
| Typechecking cadence | 修改 `.ets` 后用 `arkts_check` 覆盖变更文件；实现阶段定期运行相关单测 |
| Single-test cadence | 优先运行新建/受影响的 `common/src/test` 与 `entry/src/test` 单测文件 |
| Full suite | 最终运行 `npm --prefix scripts/arkts-lint test` 与 `node scripts/arkts-lint/index.mjs --quiet`；再执行 HarmonyOS build |
| Code review | 最终使用 code-review 能力；若可选模型/推理强度，则使用 `GLM-5.3` + `max`，否则报告限制 |
| Commit isolation | 提交前检查 branch、status、diff 与最近提交；只 stage #111 相关源码、测试与 SDD 产物，排除既有无关 dirty files |

### Risks, Mitigations, and Requirement Coverage

| Risk / Requirement | Coverage |
|--------------------|----------|
| 新旧 callback 迁移遗漏 | grep `LlmStreamCallback`、`onDelta`、`appendAiMsg`、`reasoning/content kind`，并运行 ArkTS check/build |
| fallback 删除早于消费端改造 | 同一任务切片内完成 common 与 entry 全链迁移，测试覆盖 parser 与分发 |
| thinking 被计入 final content | ReplyService text-only 内容累积；Seam B 验证 channel 不串 |
| enableThinking 默认不一致 | 同步修改初始值、load fallback、resetDefaults、ReplyService overrides |
| 当前工作区已有无关 dirty files | 提交前逐文件 stage；报告未纳入提交的无关文件 |
| FR-001 四类结构化事件 | Common LLM Contract、StreamEvent data model |
| FR-002 reasoning/content 映射 | SSE Delta Mapping、SSE Parser Seam A |
| FR-003 删除伪装 fallback | fallback 治理 decision、SSE parser tests |
| FR-004 双通道分发 | Entry Conversation Contract、ChatMsg Compatibility |
| FR-005 未实现类型兜底 | StreamEvent data model、FloatWindow append contract |
| FR-006 默认开启 thinking | Thinking Supply Configuration |
| FR-007 ChatMsg 兼容 | ChatMsg Compatibility |
| FR-008 parser 测试 | SSE Parser Seam A、Testing contract |
| FR-009 分发测试/验收 | Entry Conversation Contract、Testing contract |
| FR-010 typecheck/test/build | Verification & Delivery Contract |
| FR-011 code review + commit isolation | Verification & Delivery Contract |
| FR-012 GLM-5.3 max 审查偏好 | Verification & Delivery Contract |
