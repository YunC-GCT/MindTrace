# Feature Specification: Ticket 0.5 CustomSpan Formula Placeholder Seam

**Created**: 2026-09-15
**Status**: Draft, reconciled before implementation
**Input**: User description: "Implement the work described by the user in the spec or tickets. #123"; clarified decisions: feature directory `spec/ticket-0-5-customspan-placeholder-seam/`, temporary harness page (observed on emulator then deleted, #120 precedent), `FORMULA_PLACEHOLDER_MAX_CHARS = 40`.

## Overview

This ticket is a hard verification gate for the inline-formula rendering branch of spec 021. It verifies that the `CustomSpan` seam needed for inline formula placeholders behaves as the three-state rendering contract requires: an initial width estimate, a stable placeholder width while the formula is open, an invalidate-driven width/height update when the formula closes, and recorded draw/layout callback behavior for the later `GeometryChanged` work.

The verification is seam-only. It does **not** require a LaTeX engine, does **not** switch any production chat path to CustomSpan rendering, and does **not** touch the existing `MarkdownRenderer`/`FormulaSplitRenderer` or Preferences chat history paths.

The gate result is tri-state: `PASS`, `FAIL`, or `INCOMPLETE`. `PASS` releases the three-state rendering contract for downstream design consideration only; `FAIL` returns to the rendering contract design (spec 021 §12) and must never degrade to finish-only rendering; `INCOMPLETE` keeps the contract blocked until the missing device/preview evidence is completed.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Minimal CustomSpan verification demonstrates measure/draw/invalidate on device (Priority: P1)

As a maintainer, I want a minimal `CustomSpan` subclass to demonstrate the official measure/draw/invalidate lifecycle on the target SDK/device, so that ticket-2 can rely on the seam instead of re-verifying the framework behavior.

**Why this priority**: This is the blocking precondition for the `InlineFormulaBlock → CustomSpan` backend decision in spec 021 §5. Without a verified on-device measure/draw/invalidate cycle, the three-state rendering contract cannot be released.

**Independent Test**: Render one `Text` containing the placeholder span on the emulator, drive append/invalidate/close, and confirm via device log + counters that `onMeasure`, `onDraw`, and `invalidate()` each fired with the expected order.

**Acceptance Scenarios**:

1. **Given** a Text renders a styled string containing the placeholder span, **When** the Text first lays out, **Then** the span's `onMeasure` and `onDraw` are invoked and their invocations are recorded.
2. **Given** the span instance is retained, **When** `invalidate()` is called on the same instance, **Then** the framework re-draws the same span instance without replacing the Text component or the styled string. *(Verified finding: `invalidate()` is repaint-only on the API 24 baseline — it does not re-measure. Re-measure happens on a re-layout trigger; see FR-004 for the verified update path.)*
3. **Given** the verification runs on the target SDK/device, **When** each callback fires, **Then** the callback records its metrics (measured width/height, draw offsets) in a durable report.

---

### User Story 2 - Placeholder width stays stable while open and updates on close (Priority: P1)

As a maintainer, I want the inline formula placeholder to keep one estimated width while its content is open and to update its width exactly once when the formula closes, so that each streaming delta does not reflow the whole line.

**Why this priority**: Spec 021 §5 freezes this contract ("一次估算宽度、闭合替换"); user story 4 of spec 021 depends on it. If the width cannot stay stable across deltas, the contract must be redesigned.

**Independent Test**: Append several deltas to an open formula and assert the measured width is unchanged; close the formula and assert the measured width updates exactly once and the span instance identity is preserved.

**Acceptance Scenarios**:

1. **Given** a placeholder span enters the open phase with initial content, **When** its width is estimated once, **Then** the estimate is computed from the content known at entry and is bounded by `FORMULA_PLACEHOLDER_MAX_CHARS`.
2. **Given** the span is open, **When** deltas are appended (with or without re-measure), **Then** the measured width stays exactly the first estimated width.
3. **Given** the formula closes, **When** the close transition happens, **Then** the width is recomputed once from the final content and the same span instance (not a replacement) reports the new width.
4. **Given** the open-phase display content is capped, **When** content exceeds `FORMULA_PLACEHOLDER_MAX_CHARS`, **Then** the displayed placeholder text is truncated to the cap and the width stays the capped estimate.

---

### User Story 3 - Verification records height and layout callback behavior for GeometryChanged (Priority: P1)

As a maintainer, I want the verification to record every height/layout callback the seam exposes (line metrics from draw, Text area height deltas), so that ticket-2's `GeometryChanged` design has measured facts instead of guesses.

**Why this priority**: Spec 021 §6–7 design `GeometryChanged` (`messageId`, signed `totalHeightDelta`, `ts`) around measured height-change behavior. Without a record of what CustomSpan exposes, the design assumptions are unverified.

**Independent Test**: Inspect the durable report and verification record after device observation and confirm measured width/height, `x`/`lineTop`/`lineBottom`/`baseline` draw samples, and Text `onAreaChange` height deltas are recorded.

**Acceptance Scenarios**:

1. **Given** the span draws, **When** `onDraw` fires, **Then** the draw offsets (`x`, `lineTop`, `lineBottom`, `baseline`, derived line height) are recorded in the report.
2. **Given** the span's measured height changes after close, **When** the Text re-lays out, **Then** the Text-level `onAreaChange` height delta is observed and recorded.
3. **Given** the verification record is finalized, **When** it documents the observed behavior, **Then** it lists which callbacks exist and what units they report (vp for `CustomSpanMetrics`, px for `CustomSpanDrawInfo`), so the later `GeometryChanged` work can reference them.

---

### User Story 4 - Gate status and production boundary are explicit (Priority: P1)

As a maintainer, I want the gate result to have fixed downstream semantics and the production chat boundary to stay untouched, so later tickets cannot proceed under an ambiguous assumption.

**Why this priority**: The result controls whether the three-state rendering contract may proceed, returns to redesign, or stays unproven; and the ticket must not accidentally switch production rendering.

**Independent Test**: Review the verification record after automated and device evidence is complete and confirm each gate status maps to the required downstream action, and that no production chat path, renderer, or persistence path was changed.

**Acceptance Scenarios**:

1. **Given** all required automated and device observations pass, **When** the verification completes, **Then** the result is `PASS` and the three-state rendering contract is released for downstream design consideration only.
2. **Given** the placeholder width cannot stay stable or measure/draw/invalidate misbehaves, **When** the verification completes, **Then** the result is `FAIL` and the rendering contract must be redesigned; finish-only rendering is not adopted.
3. **Given** automated evidence passes but required device evidence is missing, **When** the verification completes, **Then** the result is `INCOMPLETE`, the contract remains blocked, and the missing evidence is recorded as blocked tasks rather than done.
4. **Given** any gate result, **When** the changed code is reviewed, **Then** no production chat path (`ChatBubble`, `AgentMessageList`, `chatItemKey`, `MarkdownRenderer`, `FormulaSplitRenderer`) and no persistence path is changed.

---

### Edge Cases

- The span's display content exceeds `FORMULA_PLACEHOLDER_MAX_CHARS`; the displayed text is truncated but the frozen width estimate stays.
- `invalidate()` is called while the formula is open; the framework re-draws (repaint-only, verified) and the measured width stays the frozen estimate.
- The close transition runs twice (idempotence); the width is recomputed once and repeated close calls do not change it again.
- The span is drawn on a line whose other components are taller; the official doc states the span height becomes the Text line height — the verification records the observed behavior rather than assuming it (observed: open line height 45px → closed line height 70px on the target device).
- The re-layout trigger after close is applied without replacing the span instance or the styled string; the verification records the verified trigger (`setStyledString` with the same instance).
- The verification must not import or invoke any LaTeX/KaTeX/MathTextParser logic.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The seam MUST provide a `CustomSpan` subclass implementing the official `onMeasure(measureInfo: CustomSpanMeasureInfo): CustomSpanMetrics` and `onDraw(context: DrawContext, drawInfo: CustomSpanDrawInfo): void` contracts, restricted to the API 24 baseline (no `maxWidth`/`layoutPolicy`, which are API 26 additions).
- **FR-002**: The placeholder width MUST be estimated exactly once when the span first enters the open phase, from the content known at entry, bounded by `FORMULA_PLACEHOLDER_MAX_CHARS = 40`.
- **FR-003**: While the formula is open, appending deltas MUST NOT change the measured width; `invalidate()` may re-draw but the width stays the frozen estimate.
- **FR-004**: When the formula closes, the width MUST be recomputed exactly once from the final content; the update MUST go through the same span instance and `invalidate()`, followed by a re-layout trigger — never through a Text component replacement or a styled-string replacement. *(Verified trigger: re-setting the same `MutableStyledString` instance via `TextController.setStyledString` re-measures the same span with the closed metrics.)*
- **FR-005**: The seam MUST record every measure, draw, invalidate, and area-change invocation with its metrics in a durable report: measure count, draw count, invalidate count, area-change count, last measured width/height (vp), last draw sample (`x`, `lineTop`, `lineBottom`, `baseline`, derived line height in px), last area height and signed area delta (vp), and a width-stability verdict.
- **FR-006**: The verification MUST record Text-level layout behavior (area height/width changes) produced when the span's measured height changes after close — both as a durable report surface (`recordAreaChange`) and as observed device evidence — as the measured input for the later `GeometryChanged` design.
- **FR-007**: The seam MUST NOT depend on a LaTeX engine; the placeholder draws only a plain chip (background + truncated placeholder text) and never imports or invokes KaTeX/`MathTextParser`/`ContentProtocol` rendering.
- **FR-008**: No production chat path MUST be switched to CustomSpan rendering: `ChatBubble`, `AgentMessageList`, `ChatModels.chatItemKey`, `MarkdownRenderer`, and `FormulaSplitRenderer` MUST remain byte-for-byte unchanged; no `StreamingReplyDocument` is introduced.
- **FR-009**: The gate result MUST be one of `PASS`/`FAIL`/`INCOMPLETE` with the fixed downstream semantics; `PASS` requires both automated and device evidence; a CustomSpan failure MUST return to the rendering contract design and MUST NOT degrade to finish-only rendering.
- **FR-010**: Changed `.ets` and test artifacts MUST pass ArkTS strict checks, relevant focused tests, the full test suite, and the project debug build; failures MUST be recorded rather than hidden.

### Key Entities *(include if feature involves data)*

- **Inline Formula Placeholder Span**: The `CustomSpan` subclass whose measure/draw/invalidate lifecycle implements the placeholder contract and feeds the durable report.
- **Placeholder Phase**: `open` (content streaming, width frozen) or `closed` (formula complete, width recomputed once).
- **Placeholder Model**: The pure, UI-free state machine holding phase, capped content, frozen open width, recomputed closed width, and open/closed heights.
- **Placeholder Metrics**: `{ widthVp, heightVp }` — the measure result in vp units.
- **Draw Sample**: `{ x, lineTop, lineBottom, baseline, lineHeight }` — one recorded draw callback in px units.
- **Verification Report**: Counters and last-values for measure/draw/invalidate plus the width-stability verdict; the durable automated evidence surface.
- **Gate Status**: One of `PASS`, `FAIL`, or `INCOMPLETE`, with fixed downstream semantics for the rendering contract.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: One focused automated verification covers width estimation, open-phase width stability, close-phase single recomputation, display truncation, report counters, and gate semantics, with 100% of assertions passing before the gate can be marked `PASS`.
- **SC-002**: On the target emulator, `onMeasure`, `onDraw`, and `invalidate()` are observed firing with the recorded metrics, and the open-phase measures share exactly one width while the closed-phase measure reports the updated width.
- **SC-003**: The verification record documents the observed draw offsets and the Text-level height delta behavior in explicit units (vp for metrics, px for draw info), ready for the `GeometryChanged` design.
- **SC-004**: The production diff contains no change to `ChatBubble`, `AgentMessageList`, `chatItemKey`, `MarkdownRenderer`, `FormulaSplitRenderer`, or any persistence path; the temporary harness page is deleted after observation with zero residual diff.
- **SC-005**: Relevant ArkTS checks, focused tests, the full entry test suite, naming lint, `git diff --check`, and the debug build all pass with no unreported failures; missing device evidence is recorded as `INCOMPLETE`, not `PASS`.
- **SC-006**: The verification record resolves the gate status unambiguously; `FAIL` maps to contract redesign (never finish-only), `INCOMPLETE` blocks downstream tickets.

## Assumptions

- The current repository is the project root and the feature artifacts live under `spec/ticket-0-5-customspan-placeholder-seam/`.
- The target SDK baseline is API 24; `CustomSpanMeasureInfo.maxWidth`/`layoutPolicy` (API 26) are out of scope.
- The placeholder width estimate is a deterministic char-width heuristic (no `MeasureUtils`/UIContext dependency in the pure model); precision is not required because the placeholder is a visual chip, not a typeset formula.
- The on-device demonstration uses the temporary harness page on the `MatePad Pro 13` emulator, which is deleted after observation (user-confirmed, #120 precedent); the durable evidence lives in the seam tests and this record.
- `spec/feature.json` is not repointed to this ticket; it keeps pointing at the active 019 work.
- Existing repository changes unrelated to #123 are outside this ticket and must not be overwritten or included in the scoped implementation.
- Repository code-review, staging, and commit rules are delivery-process constraints; the user has instructed a local commit to the current branch after code review.

## Open Questions

- None. The feature directory, harness strategy, and `FORMULA_PLACEHOLDER_MAX_CHARS` value were explicitly clarified before implementation.
