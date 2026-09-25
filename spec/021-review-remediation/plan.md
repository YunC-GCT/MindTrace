# Implementation Plan: 021 合并结果 Review Remediation

**Input**: Feature specification from `spec/021-review-remediation/spec.md`

## Summary

本计划在现有 MindTrace entry ArkTS 架构内，针对 #140/#141 合并结果的五类 review finding 做最小范围收敛：将 RenderTick 单实例策略统一为明确失败；将会话内存副本与持久化快照复制契约集中到共享 ChatModels；为保存结果引入准确的 idle 状态；补充能力探针和 Worker 协议边界说明；在不改变 ADR-0017 冻结预算的情况下保留并显式记录 DevEco 模拟器性能 follow-up。

本计划不实施 #142/#143/#144，不引入 StreamingReplyDocument，不切换 chat 的 Markdown/LaTeX 渲染入口，也不改变生产持久化的异步 TaskPool/Worker + AtomicFile 路径。

## Technical Context

**Language/Version**: ArkTS 1.1 strict, project SDK baseline API 24
**Primary Dependencies**: ArkUI existing V1 state model, `@ohos/hypium`, HarmonyOS `TaskPool`/Worker and `AtomicFile` seams already present in entry
**State Management**: Incremental change; retain the existing project State Management V1 and current service/test seams
**Storage**: Application-private chat-history snapshot; Preferences remains migration read source only
**Testing**: Hypium `.test.ets`, repository ArkTS static check, ArkTS lint, Node contract tests, naming lint, diff check, full project build
**Target Platform**: Existing MindTrace HarmonyOS entry module, API 24 baseline and supported DevEco target device/emulator
**Project Type**: HarmonyOS mobile application with entry HAP and supporting HSP modules
**Performance Goals**: Preserve ADR-0017 frozen budgets of one Web creation per frame and 16ms Web work budget; do not claim emulator `T_finishToStable` target success
**Constraints**: No UI-thread synchronous persistence fallback; no fallback from corrupt new snapshot to Preferences; no budget changes; no changes to the #142/#143/#144 scope
**Scale/Scope**: One AgentFloatWindow/RenderTick instance; current ChatSession/ChatMsg model; review remediation only

### Structure Decision

This is an incremental change to an existing HarmonyOS project. The plan follows the current entry architecture and does not introduce MVVM directories or restructure the application. Service lifecycle policy remains in `entry/src/main/ets/services/`; chat models and pure copy functions remain in `entry/src/main/ets/overlays/AgentFloatWindow/chat/`; Worker protocol remains in `entry/src/main/ets/workers/`; capability probes and behavioral tests remain in `entry/src/test/`.

## Project Structure

### Documentation (this feature)

```text
D:\HMgent\MindTrace\spec\021-review-remediation\
├── spec.md              # Approved requirements and boundaries
├── plan.md              # This architecture and contract plan
└── tasks.md             # Phase 3 execution and verification tasks
```

### Source Code (repository root)

```text
D:\HMgent\MindTrace\entry\src\main\ets\
├── services\
│   ├── RenderTick.ets                 # Unified single-instance lifecycle policy
│   └── ChatHistoryPersistence.ets     # Idle save result and persistence copy seam
├── overlays\AgentFloatWindow\chat\
│   ├── ChatModels.ets                 # Central in-memory/persistence copy contracts
│   └── ChatSession.ets                # Manager uses central copy contracts
└── workers\
    └── ChatPersistenceWorker.ets      # Worker message protocol documentation

D:\HMgent\MindTrace\entry\src\test\
├── RenderTick.test.ets                # Release/development-independent single-instance tests
├── ChatHistoryPersistence.test.ets    # Idle stage and copy behavior tests
├── ChatPersistenceCapability.ets      # Capability probe boundary documentation
└── ChatPersistenceCapability.test.ets # Probe naming and boundary assertions
```

The existing `scripts/arkts-lint/tests/renderer-scheduler-contract.test.mjs` remains the structural guard for ticket-1. No new module, resource directory, global Document, or global RenderTick is introduced.

## Complexity Tracking

No constitution or architecture violation is introduced. The remediation centralizes already duplicated pure data copying in the existing ChatModels seam, rather than adding a repository or a new persistence abstraction. The idle result is a distinct external status, not a fake AtomicFile failure stage.

## Research & Decisions

### Decision 1: Always fail a second RenderTick instance

- **Decision**: Make the single-instance policy independent of build mode. A second live instance fails explicitly; it is never created as a disabled no-op. The first live instance and post-dispose replacement behavior remain unchanged.
- **Rationale**: spec 021 §6 explicitly treats the product as single-instance and requires a development assertion. A release-only no-op hides a lifecycle defect and produces an apparently valid but non-functional instance.
- **Alternatives considered**: Retaining `developmentGuard=false` release no-op was rejected because it is the review finding. Creating a global RenderTick was rejected by spec 021 lifecycle boundaries.

### Decision 2: Centralize copy semantics in ChatModels

- **Decision**: Keep the existing `ChatModels.ets` as the shared pure-model seam and expose distinct, semantically named copy operations for an in-memory working copy and a persistence snapshot. `ChatSessionManager` and `ChatHistoryPersistence` consume those operations instead of maintaining local duplicate implementations.
- **Rationale**: The existing two implementations differ intentionally on `reasoningExpanded`; naming the two contracts makes that difference explicit while preventing future drift.
- **Alternatives considered**: Copying every field into the persistence snapshot was rejected because `reasoningExpanded` is UI-only. Keeping two private functions was rejected because it preserves the maintenance risk identified in review. A new utility module was rejected as unnecessary file expansion.

### Decision 3: Represent idle flush separately from AtomicFile stages

- **Decision**: Preserve the four actual AtomicFile write stages (`PREPARE`, `WRITE`, `COMMIT`, `VERIFY`) and add a separate externally visible idle/no-write result state for `flush` when no write exists.
- **Rationale**: The spec's failure-stage vocabulary remains intact, while an idle call no longer claims to have entered `PREPARE`.
- **Alternatives considered**: Returning `VERIFY` for idle was rejected because no verification occurred. Reusing `PREPARE` was rejected because it is the current finding.

### Decision 4: Document, do not duplicate, the Worker protocol

- **Decision**: Add explicit protocol documentation at the Worker and capability-probe seams and align test names/headers with the production boundary. Keep the existing string capability probe and structured write request behavior because the remediation does not require a wire-format migration.
- **Rationale**: The current behavior is functional; the finding is contract discoverability, not a demonstrated protocol failure. Minimal documentation avoids a new compatibility surface.
- **Alternatives considered**: Introducing a new shared protocol module was rejected as disproportionate to the finding and could create cross-test/Worker import coupling.

### Decision 5: Preserve ADR-0017 and record performance as follow-up

- **Decision**: Do not edit frozen budget values or lower the 500ms target. The remediation artifacts and verification report explicitly preserve the DevEco emulator follow-up and #139 true-device evidence requirement.
- **Rationale**: ADR-0017 already records `PASS_WITH_EMULATOR_PERFORMANCE_FOLLOW_UP` and the raw evidence. Rewriting the decision would obscure rather than improve traceability.
- **Alternatives considered**: Re-running or re-deriving budgets in this remediation was rejected because no new true-device evidence was requested or available. Claiming emulator performance pass was rejected by the user-confirmed scope.

## Data Model

### RenderTick instance state

- `live instance`: owns the process-level single-instance reservation and may schedule pending work.
- `disposed instance`: releases the reservation and ignores later requests.
- `rejected construction`: produces an explicit single-instance failure and owns no timer, subscription, or reservation.
- `pending/shown`: existing lifecycle state remains unchanged; phase order remains data notification → geometry notification → scroll handling.

### Chat copy contracts

- `ChatMsg` remains the source model with message identity, role, reply body, timestamp, streaming status, optional reasoning, and optional UI-only reasoning expansion state.
- `InMemoryChatSessionCopy` retains fields required for active UI interaction, including optional reasoning expansion state.
- `PersistenceChatSessionSnapshot` retains pure persisted history fields and excludes UI-only expansion state.
- Both copy contracts preserve message/session identity and do not mutate the source arrays or objects.

### Persistence result state

- `AtomicWriteStage`: actual file operation stages `PREPARE`, `WRITE`, `COMMIT`, `VERIFY`.
- `IdleSaveResult`: successful no-write `flush` result, with a diagnostic stating that no pending snapshot existed.
- `ChatHistorySaveResult`: external result carrying success, stage/state, transport, retryability, and content-safe diagnostic.
- Existing blocked, not-initialized, failed, retry, migrated, loaded, and corrupt states remain distinguishable.

### Worker protocol entities

- `CapabilityProbe`: fixed string request/response used only to verify Worker wiring.
- `WriteRequest`: structured request with `kind=write`, snapshot path, pure session data, and optional migration metadata.
- `WriteResponse`: structured write result with success, actual AtomicFile stage, schema version, and content-safe diagnostic.
- `UnsupportedRequest`: structured failure for non-write structured requests; it is not treated as a write.

## Contracts & Interfaces

### RenderTick construction contract

- A second live `RenderTick` construction attempt MUST fail explicitly regardless of build mode or options.
- A failed construction MUST NOT increment the active instance count, start a timer, connect a subscription, or change the first instance.
- `dispose()` MUST release the single-instance reservation exactly once.
- After disposal, a replacement instance MUST be constructible and functional.

### Chat copy contract

- The shared ChatModels seam owns the two named copy semantics: active in-memory copy and persistence snapshot copy.
- `ChatSessionManager` uses the active in-memory contract for static active-session handoff.
- `ChatHistoryPersistence` uses the persistence snapshot contract before TaskPool/Worker transfer.
- Persistence copy output is plain data and excludes `reasoningExpanded`; active copy output preserves it when present.

### Flush result contract

- `flush()` with no pending snapshot and no in-flight write returns a successful idle/no-write result.
- `flush()` with pending or in-flight work returns the result of the actual asynchronous write sequence.
- Actual write failures continue to use only the four AtomicFile stages and preserve retry/recovery diagnostics.
- `filesDir` blocked and manager-not-initialized results remain failures and are not reclassified as idle success.

### Worker protocol contract

- String capability requests are limited to the documented success/failure probe values.
- Structured write requests use `kind=write`; any other structured kind returns a content-safe unsupported-request response.
- Worker write failures report a stage, retryable outcome, schema version, and diagnostic without chat body, session name, reasoning, or key material.
- Production persistence continues to be owned by `ChatHistoryPersistence`; the capability probe remains test-side evidence and does not become the production save path.

### Performance follow-up contract

- ADR-0017 values remain `maxWebCreatesPerFrame=1` and `maxWebWorkMsPerFrame=16`.
- The DevEco emulator `T_finishToStable` miss remains recorded as follow-up; the initial 500ms goal is not lowered.
- #139 remains responsible for true-device evidence, recomputation, and any separately approved performance work.
