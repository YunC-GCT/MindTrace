# Implementation Plan: Ticket 0.2 Stable Chat Key Prop Refresh Gate

**Input**: Feature specification from `spec/ticket-0-2-stable-chat-key-refresh/spec.md`

## Summary

#120 is a verification gate for the stable chat-row identity proposal. It will add a focused automated seam and a reproducible real-path UI procedure to determine whether a `LazyForEach` item can retain a message-ID-only identity while its `ChatBubble` receives answer-text, reasoning, and streaming-state changes. The production key and production chat rendering path remain unchanged by this ticket.

The gate result is tri-state: `PASS` releases the stable-key branch only for downstream design consideration, `FAIL` records the temporary `id + streaming` fallback and downstream impact, and `INCOMPLETE` keeps stable-key assumptions blocked until the real device/preview evidence is completed. The global `spec/feature.json` pointer is not owned by this ticket.

## Technical Context

**Language/Version**: ArkTS 1.1 strict, HarmonyOS project baseline from existing `build-profile.json5`  
**Primary Dependencies**: ArkUI `LazyForEach`, `IDataSource`, `DataChangeListener`, `@Prop`; existing entry chat model and bubble components  
**State Management**: Retain the existing incremental-project state-management style; no migration  
**Storage**: N/A for feature behavior; verification record is repository documentation only  
**Testing**: Existing Hypium-style `.ets` tests under `entry/src/test/`; `arkts_check`; project lint/test scripts; debug build; deployed UI verification  
**Target Platform**: MindTrace HarmonyOS entry-module chat floating window  
**Project Type**: Existing multi-module HarmonyOS mobile application  
**Performance Goals**: No new production rendering or persistence overhead; focused verification must isolate the identity/prop-refresh question  
**Constraints**: Do not change production `chatItemKey`; do not switch to `StreamingReplyDocument`; preserve `MarkdownRenderer`, `FormulaSplitRenderer`, chat history, and persistence; do not modify unrelated dirty work; do not claim UI PASS without real-path evidence  
**Scale/Scope**: One P0 gate ticket, three mutation cases, one focused automated seam, one real-path UI verification, one tri-state result

## Project Structure

### Documentation (this feature)

```text
spec/ticket-0-2-stable-chat-key-refresh/
|-- spec.md
|-- plan.md
|-- tasks.md
`-- verification-record.md
```

### Source Code (repository root)

```text
entry/src/main/ets/overlays/AgentFloatWindow/
|-- AgentMessageList.ets             # Production LazyForEach owner
`-- chat/
    |-- ChatModels.ets               # Production ChatMsg and current chatItemKey
    `-- ChatBubble.ets               # Production @Prop msg row

entry/src/test/
|-- List.test.ets                    # Existing test aggregator
|-- AgentChatStreamEvents.test.ets   # Existing reducer/key tests; not sufficient alone
`-- StableChatKeyRefresh.test.ets     # Focused #120 automated seam
```

**Structure Decision**: Follow the existing MindTrace entry module and test layout. This is incremental verification work, not a new application structure, MVVM migration, renderer migration, or storage redesign. A separate focused test harness is allowed only to model the stable-key/row-observation seam. If it is not structurally identical to production `AgentMessageList`/`ChatBubble`, the verification record must list the differences and require the real-path UI evidence to close that gap.

## Complexity Tracking

No planned architecture complexity violations. The focused test seam is justified because the issue requires a repeatable test of framework-sensitive identity and prop propagation while production migration is explicitly out of scope.

## Research & Decisions

- **Decision**: Verify, rather than immediately adopt, a message-ID-only key.
  **Rationale**: Official LazyForEach guidance states that the key generator identifies items and that unchanged keys preserve the existing child component. The issue asks whether changed data still reaches the existing row; changing production behavior before answering that question would invalidate the gate.
  **Alternatives considered**: Directly changing `chatItemKey` was rejected because it would be an unapproved production migration. Testing only the current key was rejected because it cannot answer the stable-key question.

- **Decision**: Use an isolated automated seam plus the real production UI path.
  **Rationale**: Automated evidence gives deterministic coverage of the three mutations; device/preview evidence validates actual `LazyForEach` and `@Prop` propagation. The automated seam may be smaller than the production tree, so the real path is required rather than optional.
  **Alternatives considered**: Automated-only evidence was rejected as insufficient for framework behavior. UI-only evidence was rejected as difficult to reproduce and weaker for regression protection.

- **Decision**: Execute the UI gate once in the final Verification phase.
  **Rationale**: US2 prepares the procedure and records harness differences; the final Verification phase performs the authoritative device/preview execution and resolves the UI result. This prevents duplicated or contradictory UI conclusions.
  **Alternatives considered**: Running UI verification both during US2 and final Verification was rejected because the same gate could receive conflicting outcomes.

- **Decision**: Use `PASS`, `FAIL`, and `INCOMPLETE` with fixed downstream semantics.
  **Rationale**: Missing UI evidence is not a pass. A stable-key failure warrants the temporary `id + streaming` branch; absent evidence does not. This keeps the downstream decision auditable.
  **Alternatives considered**: Treating unavailable UI evidence as a soft pass was rejected. Automatically releasing the fallback on missing evidence was rejected because it would conflate absence of proof with proof of failure.

- **Decision**: Preserve production chat and repository feature-pointer boundaries.
  **Rationale**: The ticket is a gate only. Existing renderer/history/persistence paths must remain intact, and the global `spec/feature.json` pointer belongs to the active repository workflow rather than this ticket.
  **Alternatives considered**: Pointing `spec/feature.json` at #120 was rejected because it hides the active 019 work from other tooling. Combining #120 with spec 021 renderer implementation was rejected because ticket-0 is a prerequisite gate.

## Data Model

### Chat Message

- **Fields**: message ID, role, answer content, timestamp, streaming state, optional reasoning content.
- **Validation rules**: One fixed message ID is used throughout each mutation sequence; answer, reasoning, and streaming state change independently.
- **State transitions**: initial streaming row → answer growth; initial streaming row → reasoning growth; initial streaming row → finished state.

### Stable Chat Item Identity

- **Fields**: message ID only.
- **Validation rules**: Identity remains equal when answer length, reasoning length, or streaming state changes.
- **Relationship**: Verification-only candidate contract; production `chatItemKey` is not changed by this ticket.

### Observed Chat Row

- **Fields**: stable identity marker, observed answer text, observed reasoning text, observed streaming/completion presentation.
- **Validation rules**: Each mutation must update the corresponding observed value while the identity marker remains unchanged.
- **Relationship**: Derived from automated seam or real UI observation; never persisted as application state.

### Verification Record

- **Fields**: scope, environment, procedures, automated results, UI results, harness/production differences, gate status, fallback decision, blocked-task status, preservation checks.
- **Validation rules**: `PASS` requires both automated and real UI evidence; `FAIL` requires an observed refresh failure and records `id + streaming`; `INCOMPLETE` records missing/inconclusive UI evidence and blocked downstream assumptions.

### Gate Status

- **Values**: `PASS`, `FAIL`, `INCOMPLETE`.
- **Semantics**:
  - `PASS`: both evidence layers pass; stable-key branch is released for downstream design consideration only.
  - `FAIL`: a required stable-key refresh assertion or UI observation fails; record the temporary `id + streaming` fallback and impact.
  - `INCOMPLETE`: required UI evidence is absent or inconclusive; stable-key gate remains unreleased and downstream assumptions remain blocked.

## Contracts & Interfaces

### Automated Verification Contract

- **Location**: `entry/src/test/StableChatKeyRefresh.test.ets`, registered by `entry/src/test/List.test.ets`.
- **Input**: typed chat message fixtures and a candidate stable identity derived only from message ID.
- **Required cases**: answer growth, reasoning growth, streaming-to-finished transition.
- **Assertions**: candidate identity is unchanged; the observed row data changes for each case; no assertion depends on a changed identity.
- **Harness boundary**: if the test harness is a minimal copy rather than the production tree, document the exact difference in `verification-record.md`.

### Production UI Verification Contract

- **Path**: `AgentMessageList.ets` → `LazyForEach` → `ChatBubble.ets` `@Prop msg` → displayed answer/reasoning/status.
- **Procedure**: final Verification phase executes the US2 procedure once on a device or Preview.
- **Required observations**: answer growth, reasoning growth, streaming-to-finished, each with unchanged message ID/row identity evidence.
- **Result**: `PASS`, `FAIL`, or `INCOMPLETE`; unavailable or inconclusive execution is `INCOMPLETE`.
- **Separation**: US2 documents the procedure and evidence gap; it does not independently resolve the final UI result.

### Preservation Contract

- No production `chatItemKey` migration.
- No `StreamingReplyDocument` integration.
- No removal/change of `MarkdownRenderer` or `FormulaSplitRenderer` usage.
- No chat history or persistence changes.
- No changes to unrelated pre-existing dirty files.

## Changelog

- **2026-09-14**: Reconciled after two-axis review. Removed workflow/code-review requirements from the product design, restored ownership boundary for `spec/feature.json`, clarified that US2 prepares the UI procedure while final Verification executes it once, and retained tri-state gate semantics plus harness-difference documentation.
