# Feature Specification: Ticket 0.2 Stable Chat Key Prop Refresh Gate

**Created**: 2026-09-14  
**Status**: Draft, reconciled after review; implementation and verification recorded as `INCOMPLETE` (2026-09-14)  
**Input**: User description: "Implement the work described by the user in the spec or tickets. #120"; clarified verification scope: automated seam evidence and device/preview evidence; clarified tri-state gate semantics and harness/production difference recording.

## Overview

This ticket establishes a hard verification gate for the proposed stable chat-row identity contract. It determines whether a chat row managed by `LazyForEach` continues to deliver changing message data to `ChatBubble` and its text-rendering children when the item identity depends only on the message ID. The ticket produces both repeatable automated seam evidence and a real device or preview observation, without changing the production chat path or adopting `StreamingReplyDocument`.

The gate result is tri-state: `PASS`, `FAIL`, or `INCOMPLETE`. `INCOMPLETE` means the stable-key gate is not released and downstream stable-key assumptions remain blocked until real device/preview evidence is completed. The three-state result is a verification outcome, not a product feature state.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Stable key refresh is proven (Priority: P1)

As a maintainer, I want a focused verification to prove that a chat item whose identity remains tied to one message ID can still reflect changing message data, so that downstream incremental-rendering work has a reliable go/no-go gate.

**Why this priority**: This is the blocking decision for the stable-key branch of the incremental chat rendering work.

**Independent Test**: Run the focused automated verification and confirm that one message identity remains stable while each required message mutation is observable in the row content/state.

**Acceptance Scenarios**:

1. **Given** a streaming AI message with a fixed message ID and initial empty answer text, **When** answer text grows while the item identity remains unchanged, **Then** the row's observed answer text reflects the new value.
2. **Given** a streaming AI message with a fixed message ID and initial reasoning text, **When** reasoning text grows while the item identity remains unchanged, **Then** the row's observed reasoning text reflects the new value.
3. **Given** a fixed message ID and a message marked streaming, **When** the message transitions to finished while the item identity remains unchanged, **Then** the row's observed streaming state and completion presentation reflect the new value.
4. **Given** the automated harness uses a structure that differs from production `ChatBubble` or the production `LazyForEach` owner, **When** the verification record is finalized, **Then** the record explicitly lists those differences and states that User Story 2 is required to cover the production-path gap.

---

### User Story 2 - Real rendering path confirms the seam (Priority: P1)

As a maintainer, I want the actual chat list and bubble rendering path exercised in a device or preview environment, so that automated seam evidence is checked against the framework behavior used by the product.

**Why this priority**: A pure model test cannot by itself prove framework-level propagation through `LazyForEach` and `@Prop`.

**Independent Test**: Run the recorded device or preview scenario with a stable item identity and observe answer growth, reasoning growth, and the streaming-to-finished transition in the rendered chat row.

**Acceptance Scenarios**:

1. **Given** the real chat list displays one streaming AI row, **When** answer content is appended without changing the message ID, **Then** the visible answer text updates in the same row rather than requiring a new item identity.
2. **Given** the same row displays reasoning, **When** reasoning content is appended without changing the message ID, **Then** the visible reasoning area updates in the same row.
3. **Given** the same row is streaming, **When** streaming changes to finished without changing the message ID, **Then** the visible status changes to the finished state without replacing the row identity.
4. **Given** User Story 2 cannot be completed because the device/preview environment is unavailable or the production path cannot be exercised, **When** the gate result is recorded, **Then** the overall gate status is `INCOMPLETE`, not `PASS`.

---

### User Story 3 - Gate result and fallback branch are explicit (Priority: P1)

As a maintainer, I want each possible gate result to have fixed downstream semantics, so later tickets cannot proceed under an ambiguous assumption.

**Why this priority**: The result controls whether downstream work may use the stable-key contract, must use a temporary fallback, or remains blocked.

**Independent Test**: Review the verification record after automated and UI evidence is complete and confirm that `PASS`, `FAIL`, and `INCOMPLETE` each map to the required downstream action.

**Acceptance Scenarios**:

1. **Given** all automated and real device/preview required observations pass, **When** the verification is completed, **Then** the result is `PASS` and the stable-key gate is released for downstream design consideration, without implementing production migration in this ticket.
2. **Given** any required stable-key refresh assertion or UI observation fails, **When** the verification is completed, **Then** the result is `FAIL`, the gate is released only through the temporary `id + streaming` fallback branch, and the downstream impact is documented before downstream tickets proceed.
3. **Given** automated evidence passes but required real device/preview evidence is missing or inconclusive, **When** the verification is completed, **Then** the result is `INCOMPLETE`, the gate is not released, downstream stable-key assumptions remain blocked, and the relevant tasks are marked blocked rather than done.
4. **Given** the stable-key verification fails or is incomplete, **When** downstream ticket planning is reviewed, **Then** no production chat path is switched to the stable-key contract based on this ticket.

---

### Edge Cases

- The message starts without a reasoning field, and reasoning is later introduced; the observed reasoning value must still update correctly.
- The message has empty answer text while reasoning grows; reasoning updates must not be mistaken for answer updates.
- Answer text, reasoning text, and streaming state change in separate updates and in the stated order.
- The message ID changes; this is a new item identity and must not be used as evidence for stable-key refresh.
- The same content value is supplied twice; the verification must distinguish identity stability from a no-op value update.
- The automated harness uses a minimal structure that differs from production `ChatBubble`/`LazyForEach`; the verification record must identify the differences.
- The device or preview environment cannot reproduce the real rendering path; the record must mark the gate as `INCOMPLETE` and must not claim the device/preview criterion passed.
- Existing `MarkdownRenderer` and `FormulaSplitRenderer` behavior, chat history reads, and persistence behavior are not changed by this ticket.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The verification MUST define a stable chat item identity based only on the message ID for the tested contract; content length, reasoning length, and streaming state MUST NOT be used as identity inputs in the stable-key scenario.
- **FR-002**: The automated verification MUST cover answer text growth while the message ID remains fixed.
- **FR-003**: The automated verification MUST cover reasoning text growth while the message ID remains fixed.
- **FR-004**: The automated verification MUST cover a streaming-to-finished transition while the message ID remains fixed.
- **FR-005**: The automated verification MUST demonstrate that the observed row data changes for all three mutations without relying on a changed item identity.
- **FR-006**: If the automated harness differs from the production `ChatBubble` or production `LazyForEach` owner structure, the verification record MUST explicitly document those differences and state why User Story 2 is required to close the evidence gap.
- **FR-007**: A device or preview verification MUST exercise the real `LazyForEach` chat list and `ChatBubble` rendering path, or explicitly record why that path could not be exercised.
- **FR-008**: The device or preview verification MUST record separate observations for answer growth, reasoning growth, and streaming-to-finished transition.
- **FR-009**: The ticket MUST NOT switch any production chat path to `StreamingReplyDocument` or otherwise remove the existing chat rendering path.
- **FR-010**: The ticket MUST preserve existing `MarkdownRenderer` and `FormulaSplitRenderer` usage, chat history reads, and persistence behavior.
- **FR-011**: If any required stable-key refresh assertion or UI observation fails, the verification record MUST mark the gate as `FAIL` and explicitly document the temporary `id + streaming` fallback branch and its impact on downstream tickets.
- **FR-012**: If all automated and UI observations pass, the verification record MUST mark the gate as `PASS` and document that the stable-key branch is eligible for downstream design consideration but is not adopted in production by this ticket.
- **FR-013**: If automated evidence passes but required UI evidence is unavailable or inconclusive, the verification record MUST mark the gate as `INCOMPLETE`; `INCOMPLETE` MUST mean the stable-key gate is not released and downstream stable-key assumptions remain blocked until device/preview verification is completed.
- **FR-014**: The verification MUST include a reproducible test procedure, observed results, environment details, and evidence sufficient for a maintainer to distinguish a stable identity from a row replacement.
- **FR-015**: The changed test and verification artifacts MUST pass ArkTS strict checks, relevant focused tests, and the project debug build; failures MUST be recorded rather than hidden.

### Key Entities *(include if feature involves data)*

- **Chat Message**: The AI chat row input carrying message ID, answer content, reasoning content, and streaming state.
- **Stable Chat Item Identity**: The identity used by the tested list item, derived only from the chat message ID for this gate.
- **Observed Chat Row**: The rendered row and child text/state values used to determine whether changed message data reached the existing item.
- **Verification Record**: The durable evidence containing procedures, results, tri-state gate status, harness/production differences, fallback branch decision, blocked-task notes, and scoped file inventory.
- **Gate Status**: One of `PASS`, `FAIL`, or `INCOMPLETE`, with fixed downstream semantics.
- **Fallback Branch**: The temporary `id + streaming` identity strategy recorded only when stable-key refresh fails.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: One focused automated verification covers all three required mutations: answer growth, reasoning growth, and streaming-to-finished transition, with 100% of assertions passing for a stable message ID before the gate can be marked `PASS`.
- **SC-002**: The real device or preview verification records a distinct result for all three required mutations and identifies the observed row identity for each result before the gate can be marked `PASS`.
- **SC-003**: A passing gate provides both automated and device/preview evidence; missing or inconclusive device/preview evidence is recorded as `INCOMPLETE`, not `PASS`.
- **SC-004**: A failed stable-key assertion or UI observation produces an explicit `id + streaming` fallback record and prevents an undocumented stable-key production migration.
- **SC-005**: An `INCOMPLETE` result records the gate as not released, downstream stable-key assumptions as blocked, and incomplete UI tasks as blocked rather than done.
- **SC-006**: If the automated harness differs from production structure, the verification record lists those differences and ties the remaining risk to the US2 real-path evidence.
- **SC-007**: No production chat path, existing renderer call, history read, or persistence behavior is changed by this ticket.
- **SC-008**: Relevant ArkTS checks, focused tests, full test suite, debug build, deploy, and UI verification results are recorded with no unreported failures.

## Assumptions

- The current repository is the project root and the feature artifacts live under `spec/ticket-0-2-stable-chat-key-refresh/`.
- The ticket is a verification gate for #120, not the implementation of the broader incremental chat rendering spec.
- The existing chat message model already carries answer content, optional reasoning, streaming state, and a numeric message ID.
- Device or preview access may be unavailable in a particular run; unavailable evidence is a documented `INCOMPLETE` result, not an inferred pass.
- The temporary fallback branch is a decision record for downstream work only; it is not a request to modify the production item key in this ticket.
- Existing repository changes unrelated to #120 are outside this ticket and must not be overwritten or included as part of the scoped implementation.
- Repository code-review, staging, and commit rules are delivery-process constraints, not product requirements, and are tracked separately in the task list and verification record.

## Open Questions

- None. The evidence scope, feature directory, tri-state gate semantics, harness difference record, and production-preservation boundary were explicitly clarified before implementation.
