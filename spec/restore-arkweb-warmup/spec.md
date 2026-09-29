# Feature Specification: Restore ArkWeb Engine Warmup Gate

**Created**: 2026-09-13
**Status**: Draft
**Input**: User description: "Implement issue #119. Use TDD where possible at pre-agreed seams; run typechecking, tests, full suite; stop before `/code-review` because the user will perform review. Reopened Phase 1 requirements: render process mode must be SINGLE; warmup failure must mark BenchmarkBaselinePrecondition invalid and expose that status through a public interface; #119 does not add benchmark collection scripts."

## Overview

恢复 EntryAbility 级 ArkWeb 引擎预热/配置门禁，确保 spec 021 ticket-0 的 chat 渲染性能基线不会把一次性的 ArkWeb 引擎、动态库或渲染进程启动成本计入稳定态渲染成本。

本 ticket 必须保持范围窄：只恢复当前 SDK 支持的 ArkWeb warmup/configuration 与可查询的基线前置状态，不启动 spec 021 下游渲染迁移、基准采集脚本、RendererScheduler、StreamingReplyDocument 或聊天历史持久化迁移。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 预热先于基线采集 (Priority: P1)

作为准备执行 spec 021 ticket-0 性能基线的维护者，我需要应用在 EntryAbility 启动阶段执行已冻结的 ArkWeb 预热/配置，使后续 chat 渲染基线排除一次性 ArkWeb 启动成本。

**Why this priority**: 这是 issue #119 的硬门禁。ticket-1 到 ticket-5 不得在 ticket-0.x 门禁失败时继续创建或实施。

**Independent Test**: 通过 ArkWeb API adapter seam 与 EntryAbility launch seam 验证 warmup/configuration 在 chat benchmark 入口可用前已被调用。

**Acceptance Scenarios**:

1. **Given** 应用冷启动，**When** EntryAbility startup 执行，**Then** 系统在任何 chat rendering benchmark 入口可用前尝试 ArkWeb warmup/configuration。
2. **Given** 当前 SDK 与项目配置，**When** warmup/configuration 编译和运行，**Then** 只使用当前 SDK 支持的 ArkWeb API，不要求 SDK 升级。
3. **Given** Q1 决策已冻结，**When** warmup/configuration 设置 ArkWeb 渲染进程模式，**Then** 具体模式必须是 `SINGLE`，不得以“配置化”或默认值为由留空、延后选择或选择其他模式。

---

### User Story 2 - 预热失败不产出有效基线前置状态 (Priority: P1)

作为维护性能基线门禁的维护者，我需要预热失败时有明确可查询的 invalid 前置状态，供未来 spec 021 基准采集脚本拒绝错误基线。

**Why this priority**: “基线必须在预热完成后采集”是 spec 021 的执行约束；#119 负责暴露正确状态，但不新增基准采集脚本。

**Independent Test**: 通过 warmup seam 的 recoverable failure 测试，验证失败会把 BenchmarkBaselinePrecondition 标记为 invalid，并可通过公共接口查询。

**Acceptance Scenarios**:

1. **Given** ArkWeb warmup/configuration 成功，**When** 外部消费者查询 BenchmarkBaselinePrecondition，**Then** 状态可表明基线前置条件有效。
2. **Given** ArkWeb warmup/configuration 出现可恢复失败，**When** 外部消费者查询 BenchmarkBaselinePrecondition，**Then** 状态必须是 invalid，并包含不暴露用户内容的诊断信息。
3. **Given** BenchmarkBaselinePrecondition 为 invalid，**When** 未来 spec 021 的基准采集脚本消费该状态，**Then** 该脚本应失败而不是产出错误基线；但该脚本消费行为不在 #119 内实现或验证。

---

### User Story 3 - 预热不破坏正常启动 (Priority: P1)

作为打开 MindTrace 的用户，我需要应用在恢复 ArkWeb warmup 后仍能正常启动，不因门禁修复导致启动崩溃或白屏阻塞。

**Why this priority**: issue #119 明确要求 warmup 恢复后进行启动 smoke verification。

**Independent Test**: 通过 build 后启动 smoke verification 验证；如无设备/模拟器，则记录环境阻塞。

**Acceptance Scenarios**:

1. **Given** warmup gate 已恢复，**When** debug build 后启动应用，**Then** EntryAbility startup 不发生 launch-blocking crash。
2. **Given** warmup 出现可恢复平台错误，**When** 应用继续启动，**Then** 错误可诊断、BenchmarkBaselinePrecondition 为 invalid，且正常应用启动不被阻塞。

---

### User Story 4 - 现有 chat 渲染与持久化保持不变 (Priority: P2)

作为当前 chat 体验维护者，我需要 #119 不切换渲染和持久化路径，避免把 spec 021 下游迁移混入 hard-gate 修复。

**Why this priority**: issue #119 明确禁止在本 ticket 中切换 chat rendering 到 StreamingReplyDocument，并要求保留现有 MarkdownRenderer/FormulaSplitRenderer 与 Preferences chat history 路径。

**Independent Test**: 通过 diff review 与 targeted regression assertions 验证没有引入渲染/持久化迁移。

**Acceptance Scenarios**:

1. **Given** #119 实施完成，**When** 检查改动，**Then** 没有任何 chat rendering path 切换到 StreamingReplyDocument。
2. **Given** #119 实施完成，**When** 检查现有渲染与历史路径，**Then** MarkdownRenderer/FormulaSplitRenderer 和 Preferences chat history 保持可用且行为不变。

---

### User Story 5 - 在已确认 seam 上执行 TDD (Priority: P2)

作为接受此改动的维护者，我需要测试落在已确认的公共 seam 上，避免测试耦合私有实现细节。

**Why this priority**: 用户要求尽可能使用 `/tdd`，且已确认 ArkWeb API adapter seam 与 EntryAbility launch seam。

**Independent Test**: 通过 targeted test file 的 RED→GREEN 证据验证 adapter seam、EntryAbility launch seam、recoverable failure/precondition seam。

**Acceptance Scenarios**:

1. **Given** ArkWeb API adapter seam 被测试，**When** warmup path 执行，**Then** 测试验证支持 API 的调用、`SINGLE` 模式约束、成功/失败结果。
2. **Given** EntryAbility launch seam 被测试或 smoke-verified，**When** EntryAbility startup 运行，**Then** 测试或 smoke evidence 证明 warmup 是 startup ordering 的一部分。
3. **Given** recoverable failure seam 被测试，**When** warmup 失败，**Then** BenchmarkBaselinePrecondition invalid 状态可通过公共接口查询。

### Edge Cases

- ArkWeb warmup/configuration API 在部分设备上可能可编译但运行时不支持或抛出错误；此类失败必须生成 diagnostic + invalid precondition，而不是静默视为有效基线前置条件。
- EntryAbility 生命周期可能重复进入 startup 相关路径；成功后的 `warmup()` 必须幂等，第二次调用返回成功和稳定的 valid precondition，不得再次调用 `setRenderProcessMode`/`initializeWebEngine`；初次 invalid 仍允许下一次调用重试并恢复为 valid。
- #119 不新增 benchmark collection script；未来“invalid 时基准采集失败”属于 spec 021 下游脚本消费点。
- #119 不创建 ticket-1~5 行为，不实施 StreamingReplyDocument、RendererScheduler、隐藏 Web keep-alive、fixture baseline collection、TaskPool/AtomicFile 聊天历史迁移或 NoteDetail 切换。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 系统 MUST 在 chat rendering benchmark baseline 可采集前，于 EntryAbility startup 阶段执行当前 SDK 支持的 ArkWeb engine warmup/configuration。
- **FR-002**: 系统 MUST 将 ArkWeb render process mode 的具体值设置为 `SINGLE`，并且不得以配置化、默认值或未来选择为由省略该决策。
- **FR-003**: 系统 MUST 调用当前项目 SDK 与 build 配置可用的 ArkWeb API，不得引入超出 SDK 24 的 API 依赖。
- **FR-004**: 系统 MUST 暴露或保留可测试的 ArkWeb warmup public seam，用于验证 supported API invocation、`SINGLE` 约束、成功结果与 recoverable failure reporting。
- **FR-005**: 系统 MUST 暴露可查询的 BenchmarkBaselinePrecondition 状态。
- **FR-006**: 系统 MUST 在 ArkWeb warmup/configuration 成功时将 BenchmarkBaselinePrecondition 标记为 valid 或等价可用状态。
- **FR-007**: 系统 MUST 在 ArkWeb warmup/configuration 可恢复失败时将 BenchmarkBaselinePrecondition 标记为 invalid，并提供不含用户内容的诊断信息。
- **FR-008**: 系统 MUST NOT 在 #119 内新增 benchmark collection script；未来基准脚本消费 invalid 状态并失败属于 spec 021 下游范围。
- **FR-009**: 系统 MUST 在 warmup 恢复后保持正常 app launch，不因可恢复 warmup 失败阻塞普通用户启动。
- **FR-010**: 系统 MUST 提供 pre-agreed TDD seam 验证：ArkWeb API adapter seam、EntryAbility launch seam、BenchmarkBaselinePrecondition failure seam。
- **FR-011**: 系统 MUST NOT 在本 ticket 中将任何 chat rendering path 切换到 StreamingReplyDocument。
- **FR-012**: 系统 MUST 保持现有 MarkdownRenderer/FormulaSplitRenderer 路径 intact。
- **FR-013**: 系统 MUST 保持现有 Preferences chat history 路径 intact。
- **FR-014**: 系统 MUST 通过 changed ArkTS files 的 ArkTS check 或等价 typecheck、targeted tests、full relevant test suite、debug build 与可用环境下 launch smoke。
- **FR-015**: 工作流 MUST 在 `/code-review` 与 commit 前停止，因为用户明确表示将自行执行 `/code-review`。

### Key Entities

- **ArkWeb Warmup Gate**: EntryAbility startup 阶段执行的 ArkWeb 初始化/配置门禁，用于排除基线中的一次性 ArkWeb 启动成本。
- **Warmup Result**: warmup 尝试的可观察结果，包含成功/失败、诊断摘要与失败是否可恢复，不包含用户 chat 内容；成功（包括幂等成功）`recoverable=false`，可恢复失败 `recoverable=true`。失败诊断只允许经过清洗的 `errorName`/`errorCode` 及固定摘要，不得加入 `message`、`stack`、序列化错误对象或硬编码的伪 `errorType`。
- **BenchmarkBaselinePrecondition**: 面向未来 benchmark consumer 的可查询前置状态；warmup 成功时有效，warmup 失败时 invalid。
- **Pre-agreed Test Seam**: 用户确认的测试边界，包括 ArkWeb API adapter seam、EntryAbility launch seam、BenchmarkBaselinePrecondition failure seam。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Targeted tests 能证明 ArkWeb render process mode 被固定为 `SINGLE`。
- **SC-002**: Targeted tests 能证明 warmup 成功后 BenchmarkBaselinePrecondition 可查询为有效状态。
- **SC-003**: Targeted tests 能证明 warmup 可恢复失败后 BenchmarkBaselinePrecondition 可查询为 invalid。
- **SC-004**: Changed ArkTS files 通过 ArkTS syntax/type check 或项目可用的等价检查。
- **SC-005**: Targeted warmup/precondition test file 通过。
- **SC-006**: Full relevant Node test suite 在最终阶段运行一次并通过，或记录非 #119 范围的既有失败。
- **SC-007**: Debug build 通过。
- **SC-008**: Launch smoke verification 证明 app 启动正常，或在无设备/模拟器时记录明确环境阻塞。
- **SC-009**: Diff review 证明没有 StreamingReplyDocument migration、没有移除 MarkdownRenderer/FormulaSplitRenderer、没有迁移 Preferences chat history。

## Assumptions

- Issue #119、parent issue #118、spec 021/Q1/Q4 决策是本 ticket 的权威范围来源。
- 当前 SDK 兼容边界是 `6.1.1(24)`；API 26 或未来能力不在 #119 范围内。
- “invalid 时基准采集失败”是未来 spec 021 benchmark script 的消费责任；#119 只暴露可查询状态并测试状态本身。
- 用户对“commit your work”的原始要求已被后续澄清覆盖：本 workflow 到 `/code-review` 前停止，不 staging、不 commit。
- 如果没有可用设备/模拟器，launch smoke 可以记录环境阻塞，但 build/test/typecheck 仍需完成。

## Open Questions

- None.
