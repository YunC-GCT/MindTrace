# Implementation Plan: Restore ArkWeb Engine Warmup Gate

**Input**: Feature specification from `spec/restore-arkweb-warmup/spec.md`

## Summary

恢复 issue #119 要求的 EntryAbility 启动期 ArkWeb warmup/configuration gate，并把 spec 021/Q1 已冻结的 render process mode 固定为 `SINGLE`。技术方案是在现有 MindTrace entry 架构内增加一个小型、可测试的 ArkWeb warmup seam，维护可查询的 `BenchmarkBaselinePrecondition` 状态；#119 不新增 benchmark collection script，只为未来 spec 021 基准脚本提供 valid/invalid 前置状态。

## Technical Context

**Language/Version**: ArkTS in HarmonyOS Stage model；项目 target/compatible SDK 为 `6.1.1(24)`，来源 `build-profile.json5` 与官方 SDK 文档。
**Primary Dependencies**: `@kit.AbilityKit`、`@kit.ArkWeb`、`@kit.PerformanceAnalysisKit`、现有 `common` exports、现有 entry module services/kit facades。
**State Management**: 保留现有项目 State Management V1 约定；不引入 V2 迁移，不做 MVVM 重构。
**Storage**: #119 不改持久化；现有 Preferences chat history 路径必须保持 intact。`BenchmarkBaselinePrecondition` 是进程内可查询状态，不落库、不写 Preferences。
**Testing**: 现有 Node `.mjs` regression harness（`scripts/arkts-lint/tests/`）、Hypium ArkTS behavior test（`entry/src/test/ArkWebWarmupService.test.ets`）、changed `.ets` 文件的 `arkts_check`、targeted warmup/precondition test file、最终 full relevant Node suite、debug build、可用设备/模拟器下 launch smoke。
**Target Platform**: HarmonyOS mobile app，`entry` HAP + existing HSP modules。
**Project Type**: 既有多 module HarmonyOS application。
**Performance Goals**: 未来 chat rendering benchmark baseline 只能在 ArkWeb warmup 成功且 `BenchmarkBaselinePrecondition` 有效后采集；#119 不采集、不冻结 ticket-0 性能基线值。
**Constraints**: render process mode 必须固定为 `SINGLE`；只使用 SDK 24 可用 ArkWeb API；普通 app launch 不被可恢复 warmup failure 阻塞；不引入 StreamingReplyDocument、RendererScheduler、hidden Web keep-alive、benchmark script、chat persistence migration；在 `/code-review` 和 commit 前停止。
**Scale/Scope**: 窄范围 P0 restoration，预计触达 EntryAbility、一个 entry-owned warmup/precondition seam、一个 targeted Node regression test file；经用户明确批准，保留并校正 `docs/agents/api-version.md` 与 `docs/style/arkts-1.1.md` 的 API/SDK 兼容性文档维护，使其以 `build-profile.json5` 和官方文档为准，不再保留过时的 API 9/API 12+ 一刀切结论。

## Project Structure

### Documentation (this feature)

```text
spec/restore-arkweb-warmup/
├── spec.md
├── plan.md
└── tasks.md
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── entryability\
│   └── EntryAbility.ets                    # startup integration point；调用 warmup gate
└── services\
    └── ArkWebWarmupService.ets             # ArkWeb warmup adapter + BenchmarkBaselinePrecondition public seam

scripts/arkts-lint/tests/
└── arkweb-warmup-gate.test.mjs             # targeted TDD regression tests for agreed seams
```

**Structure Decision**: 本 plan 继续遵循 MindTrace 现有架构，不引入 MVVM migration 或新的目录层级。EntryAbility 保持 composition/startup owner；`entry/src/main/ets/services/ArkWebWarmupService.ets` 作为小型 entry-owned service seam 承担 ArkWeb static API adapter、`SINGLE` 决策封装与 `BenchmarkBaselinePrecondition` 状态查询，避免测试耦合 EntryAbility 私有实现。测试放入现有 `scripts/arkts-lint/tests/` Node harness，符合仓库已有 seam/regression test 约定。

## Complexity Tracking

无需要豁免的架构复杂度。新增 warmup/precondition seam 的复杂度来自用户已确认的 TDD seam 与未来 benchmark consumer 对 public precondition 状态的需求；相比把 ArkWeb static calls 和状态散落在 EntryAbility 中，该 seam 更小、更可测、更符合 hard-gate 可观测性要求。

## Research & Decisions

- **Decision**: warmup/configuration gate 必须显式设置 ArkWeb render process mode 为 `SINGLE`，然后执行 ArkWeb engine warmup。
  - **Rationale**: 官方 ArkWeb 进程文档说明 `RenderProcessMode.SINGLE` 表示多个 Web 复用一个渲染子进程，`MULTIPLE` 表示每个 Web 一个渲染子进程；spec 021/Q1 已冻结 SINGLE 决策，用于避免多 Web 组件引发 render process spawn 风暴。官方 WebviewController API 文档把 `initializeWebEngine()` 放在 Ability startup 示例中，并要求全局 Web 配置在 Web 组件绑定/加载前完成。
  - **Alternatives considered**: 配置化 render process mode 被拒绝，因为会违反 Q1 冻结决策；依赖默认模式被拒绝，因为不同设备形态默认策略可能不同且不可作为基线门禁；选择 `MULTIPLE` 被拒绝，因为它与 #119 的 warmup gate 目标冲突。

- **Decision**: `BenchmarkBaselinePrecondition` 作为 #119 的公共可查询状态，由 warmup seam 写入并暴露给未来 spec 021 benchmark script。
  - **Rationale**: 用户澄清 #119 不新增 benchmark collection script，但必须在 warmup failure 时把 precondition 标记为 invalid，并通过公共接口可查询。这样未来基准采集入口可以 fail fast，而 #119 只验证状态语义本身。
  - **Alternatives considered**: 在 #119 新增最小 benchmark script 被用户明确排除；只写日志不暴露状态被拒绝，因为未来 consumer 无法可靠判断 gate 是否有效；把状态写入 Preferences 被拒绝，因为 #119 明确不改 chat history/preferences persistence，且该状态是启动期 gate 状态而非用户数据。

- **Decision**: EntryAbility 在 `onCreate` 期间调用 warmup seam，位置必须早于 `onWindowStageCreate` 的 page content load 及任何 chat benchmark 使用。
  - **Rationale**: EntryAbility 是现有最早 composition root；官方示例也在 Ability startup 中调用 ArkWeb global initialization。若放到 chat UI、renderer 或 NoteDetail 中，调用时机过晚且会把全局 L2 warmup 能力泄漏到具体 UI 链路。
  - **Alternatives considered**: 从 chat component 懒调用被拒绝；从 NoteDetail/renderer 调用被拒绝；在 benchmark script 内才触发 warmup 被拒绝，因为 #119 不新增脚本且 baseline precondition 应由 app startup 提供。

- **Decision**: 可恢复 warmup/configuration failure 不阻塞普通 app launch，但必须使 `BenchmarkBaselinePrecondition` invalid。
  - **Rationale**: issue #119 同时要求 launch smoke 正常与 baseline 不错误产出；普通用户启动和性能基线门禁是两个不同结果。失败应产生 diagnostic + invalid precondition，而不是 crash 或静默 valid。
  - **Alternatives considered**: warmup 失败即 crash 被拒绝，因为违反 launch smoke；warmup 失败仍视作 valid 被拒绝，因为会污染 baseline；忽略异常只写 hilog 被拒绝，因为缺少 public status。

- **Decision**: Targeted TDD tests 覆盖三个公共 seam：ArkWeb API adapter seam、EntryAbility launch seam、BenchmarkBaselinePrecondition failure seam。
  - **Rationale**: `/tdd` 要求测试公共 seam，用户已确认 adapter 和 EntryAbility seam，并补充 precondition invalid public query。测试应验证外部行为而非 ArkWeb SDK 内部。
  - **Alternatives considered**: 只做 smoke verification 被拒绝；测试 private helper 被拒绝；测试未来 benchmark script failure 被拒绝，因为该脚本不在 #119 范围。

- **Decision**: Scope guard 以 test/diff 约束保证不启动 spec 021 downstream migration。
  - **Rationale**: #119 明确禁止切换 chat rendering 到 StreamingReplyDocument，并要求保留 MarkdownRenderer/FormulaSplitRenderer 与 Preferences chat history。
  - **Alternatives considered**: 同时落地 hidden Web keep-alive、RendererScheduler 或 persistence migration 均被拒绝，因为属于下游 ticket。

- **Decision**: `warmup()` 在成功后幂等；初次失败仍允许下一次 startup 相关路径重试。
  - **Rationale**: EntryAbility 生命周期可能重复进入启动相关路径。成功后再次调用必须返回稳定成功状态，不重复触发平台配置/初始化，也不因平台拒绝重复初始化而污染有效前置状态；失败后的重试保留恢复平台错误的机会。
  - **Transition**: `initial → valid` 或 `initial → invalid`；`invalid → valid` 允许重试；`valid → valid` 为幂等成功且不调用 adapter。

- **Decision**: `WarmupResult.recoverable` 只描述失败是否可恢复，不描述成功。
  - **Rationale**: 保留 spec 对 Warmup Result “是否可恢复”的观察字段，但消除成功结果恒为 `true` 的歧义；成功和成功后的幂等调用返回 `false`，可恢复失败返回 `true`。

- **Decision**: 诊断元数据仅保留经过字符白名单清洗的 `errorName` 和 `errorCode`。
  - **Rationale**: `errorType=recoverable-platform-error` 是硬编码标签，不是实际分类；删除它避免伪造错误分类。诊断不读取 `message`/`stack`，不序列化错误对象，也不包含 OCR、LLM、chat 或其他用户内容。

## Data Model

- **ArkWeb Warmup Gate**
  - Purpose: EntryAbility startup 阶段执行的 ArkWeb 初始化/配置门禁。
  - Required state transition: not attempted → attempted success 或 attempted failure。
  - Validation: render process mode decision 必须固定为 `SINGLE`；只使用 SDK 24 支持的 ArkWeb API。

- **Warmup Result**
  - Purpose: 表示 warmup/configuration 尝试的可观察结果。
  - Fields: success/failure 状态、失败是否可恢复、diagnostic summary、可选 platform error code。
  - `recoverable`: 成功（包括幂等成功）为 `false`；可恢复平台/API 失败为 `true`。
  - Validation: 不包含 chat content、OCR text、LLM reply body 或其他用户学习内容。

- **BenchmarkBaselinePrecondition**
  - Purpose: 面向未来 benchmark consumer 的 public query 状态。
  - States: initial/unknown、valid、invalid。
  - Transitions: warmup success → valid；recoverable warmup failure → invalid；startup 尚未尝试 → initial/unknown。
  - Failure semantics: invalid 只说明 baseline 不应采集，不阻塞普通 app launch。

- **Pre-agreed Test Seam**
  - Purpose: TDD 可观测边界。
  - Values: ArkWeb API adapter seam、EntryAbility launch seam、BenchmarkBaselinePrecondition failure/query seam。

## Contracts & Interfaces

### ArkWeb warmup service seam contract

- **Owner**: Entry module service seam：`entry/src/main/ets/services/ArkWebWarmupService.ets`。
- **Responsibility**: 统一执行 SDK-supported ArkWeb global configuration 和 engine warmup；写入 `BenchmarkBaselinePrecondition`。
- **Inputs**: 无用户数据；测试环境可通过 public seam 注入或替换 ArkWeb platform adapter。
- **Outputs**: `Warmup Result`；public query 返回当前 `BenchmarkBaselinePrecondition`。
- **Required behavior**: render process mode 具体值固定为 `SINGLE`；不得配置化或延迟选择。
- **Failure behavior**: 可恢复 platform/API failure 产生 diagnostic result，并把 `BenchmarkBaselinePrecondition` 标记为 invalid；普通 app launch 不被阻塞。
- **Traceability**: 覆盖 FR-001、FR-002、FR-003、FR-004、FR-005、FR-006、FR-007。

### EntryAbility launch seam contract

- **Owner**: `entry/src/main/ets/entryability/EntryAbility.ets`。
- **Responsibility**: 在 startup 期间调用 warmup service seam，早于 page content load 和任何 chat rendering benchmark 使用。
- **Inputs**: 标准 Ability startup 参数。
- **Outputs**: 正常 app launch 继续执行；warmup success/failure 通过 diagnostic logging 和 precondition query 可观察。
- **Side effects**: 现有 LLM/OCR/database/facade initialization 保持 intact；不引入 chat rendering/persistence migration。
- **Traceability**: 覆盖 FR-001、FR-009、FR-011、FR-012、FR-013。

### BenchmarkBaselinePrecondition public query contract

- **Owner**: Warmup service seam。
- **Responsibility**: 供未来 spec 021 benchmark script/consumer 判断 baseline 是否允许采集。
- **States**: initial/unknown、valid、invalid。
- **Invalid conditions**: ArkWeb render process mode configuration failure、engine warmup failure、unsupported/recoverable platform API failure。
- **Out of scope**: #119 不新增基准采集脚本，也不验证未来脚本在 invalid 时 fail fast。
- **Traceability**: 覆盖 FR-005、FR-006、FR-007、FR-008、FR-010。

### Regression verification contract

- **Targeted tests**: `scripts/arkts-lint/tests/arkweb-warmup-gate.test.mjs` 覆盖 SINGLE 固定值、warmup success valid、warmup failure invalid、EntryAbility startup ordering、幂等调用与 adapter call count、no-migration assertions；`entry/src/test/ArkWebWarmupService.test.ets` 行为执行 adapter 注入、reset、success/invalid precondition query、成功幂等和失败后重试。
- **ArkTS checks**: 每次 `.ets` 编辑后对 changed files 运行 `arkts_check`。
- **Targeted cadence**: 单测试文件在 RED、US1 GREEN、US2/precondition GREEN、最终 broader checks 前定期运行。
- **Full suite**: 最终运行 full relevant Node test suite 一次。
- **Build**: debug build。
- **Launch smoke**: 可用设备/模拟器上启动应用；无设备时记录环境阻塞。
- **Stop point**: Verification 完成后停止，不调用 `/code-review`，不 staging，不 commit。
- **Traceability**: 覆盖 FR-014、FR-015。

### Approved maintenance scope

本 ticket 有意保留两项与实现直接相关的文档维护，不视为无批准的 scope creep：

- `docs/agents/api-version.md`
- `docs/style/arkts-1.1.md`

两者统一说明当前项目基线为 `build-profile.json5` 的 `6.1.1(24)`，系统 API 必须同时通过当前 SDK 与官方文档核对；API 24 能力不再被旧的“当前不可用” blanket claim 否定，具体能力仍受应用配置、设备和模型约束。该维护范围已获用户明确批准（“API顺手改了”）。
