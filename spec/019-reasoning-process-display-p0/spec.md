# Feature Specification: 019 Reasoning Process Display P0 — #111 StreamEvent Protocol Vertical Slice

**Created**: 2026-09-12
**Status**: Draft
**Input**: User description: "Implement the work described by the user in the spec or tickets... #111, 在新分支 feature/spec-019-p0 上做 — spec 019 四票一个 PR, 与之前开关删除/调研的 commit 分开 review"; clarified scope: only issue #111; additional constraint: code review should use `GLM-5.3` with reasoning strength `max` where the environment supports model and reasoning-strength selection.

## Overview

本功能将浮窗 AI 对话的流式输出从裸文本回调升级为结构化事件供给，使“思考过程”和“最终回答”稳定分离。完成后，思考内容进入思考通道，最终回答只展示真实回答文本，不再依赖服务端偶发漏回，也不再把思考文本复制进最终回答。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 稳定展示 AI 思考通道 (Priority: P1)

作为学生用户，我希望 AI 浮窗回答在有思考内容时稳定进入思考区块，而不是有时显示、有时空白，以便理解 AI 正在如何推理。

**Why this priority**: 这是 #111 的主要用户价值，也是后续 UI 分层票的协议前置。

**Independent Test**: 可通过一次产生思考内容的流式回答验证：思考文本持续进入思考区块，最终回答区不混入思考文本。

**Acceptance Scenarios**:

1. **Given** AI 服务返回思考内容但最终回答片段为空，**When** 流式事件被消费，**Then** 系统只产生思考通道更新，不产生最终回答文本副本。
2. **Given** AI 服务先返回思考内容再返回最终回答内容，**When** 流式事件按顺序到达，**Then** 思考区先更新，最终回答区随后更新，两个通道互不串写。

---

### User Story 2 - 最终回答不重复思考文本 (Priority: P1)

作为学生用户，我希望最终回答区只包含 AI 给我的结论或解答，不包含思考过程副本，以便阅读不被重复内容干扰。

**Why this priority**: 删除思考到回答的伪装 fallback 是 ADR-0015 和 #111 的硬条款；若保留会导致双发和重复显示。

**Independent Test**: 可用仅包含思考内容的流式输入验证最终回答区保持为空，同时思考区正常累积。

**Acceptance Scenarios**:

1. **Given** 流式片段只包含思考内容，**When** 系统处理该片段，**Then** 最终回答内容不增加。
2. **Given** 流式片段同时或连续包含思考内容与回答内容，**When** 系统处理这些片段，**Then** 思考内容只进入思考通道，回答内容只进入回答通道。

---

### User Story 3 - 结构化事件协议支持当前与后续过程类型 (Priority: P1)

作为开发者，我希望流式回调统一使用结构化事件对象，并完整定义当前和后续过程类型，以便 P0 支持思考/回答分流，后续工具调用展示不再改变回调形态。

**Why this priority**: #111 是 spec 019 P0 的协议纵切；协议一旦落地，后续 UI 和工具事件票可以复用同一事件模型。

**Independent Test**: 可通过单元测试验证流式输入被转换成明确类型的事件集合，未实现的事件类型不会破坏现有消费端。

**Acceptance Scenarios**:

1. **Given** 流式响应包含思考字段，**When** 系统转换响应，**Then** 输出思考类型事件。
2. **Given** 流式响应包含回答字段，**When** 系统转换响应，**Then** 输出回答类型事件。
3. **Given** 后续保留类型尚未在 P0 发出，**When** 消费端遇到未实现类型，**Then** 通过默认兜底安全忽略或保持现状，不影响思考/回答通道。

---

### User Story 4 - 默认开启思考供给 (Priority: P1)

作为学生用户，我希望 AI 思考模式默认开启，以便思考区块有稳定内容供给，而不是依赖服务端在关闭状态下偶发返回。

**Why this priority**: 稳定供给是用户可见思考区块的基础；#111 明确要求删除显式关闭覆盖并将默认值改为开启。

**Independent Test**: 可通过配置与请求行为验证：未显式设置时，系统默认请求思考内容；已有调用不会再强制关闭思考。

**Acceptance Scenarios**:

1. **Given** 用户未配置思考开关，**When** AI 对话发起请求，**Then** 系统默认请求思考内容。
2. **Given** 现有对话链路发起 AI 请求，**When** 请求参数生成，**Then** 不应出现强制关闭思考供给的覆盖行为。

---

### User Story 5 - 回归风险被测试锁定 (Priority: P2)

作为维护者，我希望 SSE 片段解析和事件分发具备可重复自动化测试，以便 null delta、空 choices、双通道顺序、思考/回答串写等回归能被及时发现。

**Why this priority**: 该功能改动跨公共 LLM 层与浮窗对话链路；没有测试锁定会增加复发 2026-09-07 空白或双发问题的风险。

**Independent Test**: 可运行针对解析 seam 和分发 seam 的单测，验证每个边界输入产生预期事件或消息字段变化。

**Acceptance Scenarios**:

1. **Given** null 或空响应片段，**When** 系统解析，**Then** 不崩溃且不产生错误事件。
2. **Given** 同一响应中思考内容先于回答内容，**When** 系统解析并分发，**Then** 事件顺序和消息字段累积均保持正确。
3. **Given** 测试套件运行，**When** 本功能相关测试执行，**Then** 解析和分发行为被覆盖且通过。

---

### User Story 6 - 使用指定模型完成代码审查 (Priority: P2)

作为维护者，我希望最终代码审查在环境支持时使用 `GLM-5.3` 且推理强度为 `max`，以便本次提交按用户指定审查偏好完成独立复核。

**Why this priority**: 这是用户对交付流程的明确约束，不改变 #111 功能范围，但影响最终验收与交付报告。

**Independent Test**: 可在交付报告中检查代码审查步骤是否记录使用了 `GLM-5.3` 与 `max` 推理强度，或明确说明当前工具链不支持模型/推理强度切换时采用的替代审查方式。

**Acceptance Scenarios**:

1. **Given** code-review 工具链支持模型与推理强度选择，**When** 执行最终代码审查，**Then** 审查使用 `GLM-5.3` 且推理强度为 `max`。
2. **Given** 当前 agent 环境不支持直接切换模型或推理强度，**When** 执行最终代码审查，**Then** 报告必须明确记录该限制，并仍完成可用的 code-review 审查。

---

### Edge Cases

- 流式响应片段缺少可用 choice 时，应不产生事件且不影响后续片段处理。
- 流式响应片段包含 null delta 时，应容错处理，不应崩溃或误写最终回答。
- 响应片段只有思考内容、没有最终回答内容时，应只更新思考通道。
- 响应片段同时覆盖思考与回答内容时，应保持思考先于回答的可观察顺序。
- 消费端收到 P0 未发出的保留事件类型时，应安全兜底，不影响已支持通道。
- 旧会话模型不应因本次协议纵切引入不兼容字段要求。
- 若 code-review 模型或推理强度切换能力不可用，应记录限制，不应阻断功能验证与提交。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 系统 MUST 将流式回调表达为结构化事件对象，事件类型集合 MUST 覆盖 `thinking`、`text`、`tool_call`、`tool_result` 四类语义，其中 P0 只需要实际发出 `thinking` 与 `text`。
- **FR-002**: 系统 MUST 将服务端思考字段转换为思考类型事件，并将回答字段转换为回答类型事件。
- **FR-003**: 系统 MUST 删除“当回答内容为空时把思考内容伪装为回答内容”的行为，且该删除 MUST 与结构化事件消费能力同一实施切片完成。
- **FR-004**: 系统 MUST 在浮窗 AI 对话链路中将思考类型事件累积到消息的思考通道，将回答类型事件累积到消息的回答通道。
- **FR-005**: 系统 MUST 为 P0 未实际发出的保留事件类型提供安全兜底，避免消费端因未知或暂未处理事件破坏现有对话。
- **FR-006**: 系统 MUST 默认开启思考供给，并移除现有 AI 对话调用中强制关闭思考供给的覆盖行为。
- **FR-007**: 系统 MUST 保持 P0 对现有聊天消息持久化模型的兼容，不要求旧会话新增字段后才能正常读取。
- **FR-008**: 系统 MUST 提供可重复测试来覆盖流式片段到事件的转换行为，包括“思考非空/回答空”、“null delta”、“空 choices”、“思考先于回答”的场景。
- **FR-009**: 系统 MUST 提供可重复测试或明确验收说明来覆盖事件到聊天消息字段的分发行为，确保思考与回答不串写。
- **FR-010**: 系统 MUST 通过项目要求的类型检查、相关单测、最终全量测试和构建验证。
- **FR-011**: 系统 MUST 在提交前进行代码审查，并将本次 #111 改动提交到 `feature/spec-019-p0` 分支；提交内容不得混入与 #111 无关的既有开关删除/调研改动。
- **FR-012**: 最终代码审查 SHOULD 在工具链支持时使用 `GLM-5.3` 且推理强度为 `max`；若当前 agent 环境无法切换模型或推理强度，交付报告 MUST 明确记录该限制并说明已执行的替代 code-review 路径。

### Key Entities *(include if feature involves data)*

- **StreamEvent**: 流式输出的结构化事件，表达思考、回答以及为后续工具过程预留的事件类型。
- **Thinking Event**: 表示 AI 思考内容增量的事件；用户可见为“思考”通道内容。
- **Text Event**: 表示最终回答内容增量的事件；用户可见为回答正文。
- **AI Chat Message**: 浮窗对话中的 AI 消息，承载思考通道和回答通道的累积内容。
- **Thinking Supply Configuration**: 控制 AI 请求是否请求思考内容的配置；P0 默认开启且不新增用户开关。
- **Code Review Execution Context**: 最终代码审查所使用的工具、参考点、模型与推理强度能力记录，用于证明审查步骤已按交付约束执行。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 对“思考非空、回答为空”的流式片段，100% 只产生思考通道更新，不产生回答通道更新。
- **SC-002**: 对 null delta 与空 choices 输入，相关解析测试 100% 通过且无崩溃。
- **SC-003**: 对思考与回答连续到达的流式输入，相关测试 100% 验证思考先于回答且两个通道不串写。
- **SC-004**: 默认配置下，AI 对话请求 100% 不再被本链路强制关闭思考供给。
- **SC-005**: 本次变更通过相关单测、项目类型检查、最终全量测试与构建验证。
- **SC-006**: 本次提交只包含 #111 范围内改动及其 SDD 产物，不包含无关调研或开关删除工作。
- **SC-007**: 交付报告 100% 记录最终 code-review 的执行方式；若可切换模型与推理强度，则记录使用 `GLM-5.3` 与 `max`，否则记录无法切换的环境限制与替代审查结果。

## Assumptions

- 本次范围仅包含 issue #111，不包含 spec 019 的其他三个票，也不包含双区块 UI 动画、key 纯函数或历史会话 UI 完整验收票。
- P0 完整定义四类事件类型是为了协议前向兼容，但本次只需要实际产生思考与回答两类事件。
- 现有聊天消息模型已经具备承载思考与回答文本的字段，本次不新增持久化字段。
- 项目现有 LLM 请求配置链路支持“请求未显式设置时回退到默认配置”的行为。
- 若 AgentChatService 的结构不适合直接单测，事件分发验收可以降级为真机/集成验收，但需要在实施报告中说明原因与证据。
- 当前主 agent 没有直接更换底层模型或推理强度的工具接口；如果 code-review skill 或外部工具不支持模型/推理强度选择，则按 FR-012 记录限制并完成可用审查。

## Open Questions

- 无。实施范围已澄清为仅 #111，SDD 产物路径已确认，code-review 模型与推理强度偏好已纳入交付约束。
