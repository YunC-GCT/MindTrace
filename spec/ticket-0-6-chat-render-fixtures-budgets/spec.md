# Feature Specification: Ticket 0.6 Chat Render Fixtures and Budgets

**Created**: 2026-09-15
**Status**: Draft, reconciled before implementation
**Input**: User description: "Implement the work described by the user in the spec or tickets. #124"; clarified decisions: feature directory `spec/ticket-0-6-chat-render-fixtures-budgets/`, temporary harness page (observed on emulator then deleted, #120/#123 precedent), deterministic simulated SSE (real LLM excluded from reproducible runs), `T_sealedToVisible` recorded as N/A with `finish→visible` as the measured analog, minimal non-behavioral measurement seam allowed in production renderers, budget defaults frozen in a new ADR + backfilled into spec 021 §6, target device = MatePad Pro 13 emulator.

## Overview

This ticket is the last hard gate of spec 021 ticket-0: it establishes the reproducible chat rendering benchmark harness for fixtures A/B/C/C′ and freezes the first set of `RendererScheduler` budget defaults from measured evidence. The measured object is the **current production render path** (`ChatBubble → FormulaSplitRenderer → MathTextRenderer` with ArkWeb/KaTeX), not the future `StreamingReplyDocument` — no production chat path is switched in this ticket.

The baseline must be collected only after the ticket-0.1 EntryAbility warmup is restored and its precondition is valid, so the numbers do not include one-time ArkWeb engine startup cost. Every fixture runs at least 20 times on the target device with p50/p95 reporting. If the metrics are not reproducible, the fixture/measurement setup must be fixed first — subjective smoothness is never accepted as evidence. A DevEco emulator miss against the initial `T_finishToStable` target is recorded as a performance follow-up; it does not invalidate an otherwise complete evidence delivery.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deterministic A/B/C/C′ fixtures with controlled text size and formula density (Priority: P1)

As a test maintainer, I want four fixed fixtures whose plain-text character counts are comparable and whose block-formula counts are controlled (A=0, B=few, C=many, C′=consecutive closed pairs), so that any downstream ticket can re-run the exact same workload and compare against this baseline.

**Why this priority**: Spec 021 §12 freezes "性能 fixture、计时起点、可见定义、p50/p95 样本量和长帧规则固定且可复现". Without deterministic fixtures, p50/p95 runs are not comparable and the budget defaults cannot be derived from evidence.

**Independent Test**: Pure fixture definitions (no UI, no network) asserted by focused unit tests: char counts comparable, formula counts exact, block counts expected, deterministic string content.

**Acceptance Scenarios**:

1. **Given** the four fixture definitions, **When** each is parsed, **Then** A/B/C/C′ have the same plain-text character count (±0) and formula counts of exactly 0 / 2 / 6 / 6 respectively.
2. **Given** fixture C′, **When** its formula layout is inspected, **Then** its 6 block formulas are arranged as 3 consecutive closed pairs (same scheduling window pressure) and the text between pairs is minimal.
3. **Given** any fixture, **When** it is serialized for the report, **Then** its content is deterministic (no randomness, no network, no LLM) and can be reproduced byte-for-byte from the recorded definition.

---

### User Story 2 - Frozen metric definitions and percentile reporting (Priority: P1)

As a test maintainer, I want one frozen definition of `visible`, the timing metrics (`T_firstDeltaToVisible`, `finish→visible`, `T_finishToStable`), the long-frame rule, steady memory, Web create count, and height update count — plus a pure p50/p95 computation — so that every run reports the same units and the same statistics.

**Why this priority**: The metrics are the deliverable. Spec 021 §12 requires the `visible` definition, the p50/p95 sample size, and the long-frame rule to be fixed and reproducible before any budget value is frozen.

**Independent Test**: Pure metric-definition and statistics functions asserted by focused unit tests (percentile computation, long-frame classification, visible-condition evaluation on recorded samples).

**Acceptance Scenarios**:

1. **Given** recorded per-block samples, **When** the visible condition is evaluated, **Then** a block is `visible` only when it has completed rendering, is inside the viewport, and its height callback has been applied (`renderedHeight > 0`).
2. **Given** a run's timestamps, **When** metrics are computed, **Then** `T_firstDeltaToVisible` = first visible formula time − first delta arrival time, `finish→visible` = first visible formula time − finish event time, and `T_finishToStable` = stable time − finish event time (stable = all viewport-and-one-screen blocks in final state and 500ms without height change).
3. **Given** frame duration samples in the first 500ms window, **When** the long-frame rule is applied, **Then** a frame >32ms is a long frame, and the frozen visual-continuity constraint is that two consecutive long frames never occur.
4. **Given** ≥20 samples per fixture per metric, **When** the report is generated, **Then** p50 and p95 are reported per metric and the sample size is recorded.

---

### User Story 3 - Benchmark runs drive the production render path on the target device (Priority: P1)

As a test maintainer, I want a temporary harness page that reuses the production `ChatBubble`/`FormulaSplitRenderer`/`MathTextRenderer` read-only, drives a deterministic simulated SSE stream, and automatically runs each fixture at least 20 times on the target device, recording all metrics per run — so the baseline reflects the real production render behavior, not a synthetic stand-in.

**Why this priority**: The budget defaults must be derived from the production render path's real behavior. A simulated stand-in would invalidate the evidence.

**Independent Test**: On the emulator, run the harness for all four fixtures and confirm ≥20 runs each with complete metric samples and a machine-readable report.

**Acceptance Scenarios**:

1. **Given** the harness page is loaded, **When** a fixture starts, **Then** its text is injected as deltas at a fixed chunk size and tick rhythm into one AI message rendered by the production components, followed by a fixed finish boundary.
2. **Given** one fixture run, **When** it completes, **Then** the run records visible events, timing metrics, Web create count, height update count, long-frame samples, and the warmup precondition state.
3. **Given** all four fixtures, **When** the harness finishes, **Then** each fixture has ≥20 runs and the report contains per-metric p50/p95 for every recorded metric.
4. **Given** a run hits a render degradation (plain fallback, web failure, bridge-limit fallback), **When** the report is generated, **Then** the run is still counted and the degradation count is recorded, not silently dropped.

---

### User Story 4 - RendererScheduler budget defaults frozen from evidence (Priority: P1)

As a maintainer, I want `maxWebCreatesPerFrame` and `maxWebWorkMsPerFrame` proposed from the measured evidence with a reproducible derivation, frozen in a new ADR and backfilled into spec 021 §6, so ticket-1's scheduler implements fixed numbers instead of guessing.

**Why this priority**: Spec 021 §6 states the two budget defaults must be frozen from ticket-0 device measurement and must not be freely changed by later tickets.

**Independent Test**: The ADR's proposed values can be recomputed from the recorded evidence (Web create count distribution, per-Web work duration, long-frame occurrence) using the documented derivation rule.

**Acceptance Scenarios**:

1. **Given** the measured evidence, **When** the budget proposal is derived, **Then** `maxWebCreatesPerFrame` is justified by the finish-frame Web create count distribution and long-frame occurrence, and `maxWebWorkMsPerFrame` is justified by the per-Web work unit duration distribution.
2. **Given** the proposal, **When** it is frozen, **Then** a new ADR records the values, the derivation rule, the device model, and the evidence summary; `docs/specs/021-chat-streaming-incremental-rendering.md` §6 is backfilled with the frozen values.
3. **Given** the frozen values, **When** a reviewer recomputes them from the evidence, **Then** they reach the same values through the documented derivation (no unexplained magic numbers).

---

### User Story 5 - Gate status, warmup precondition, and production boundary (Priority: P1)

As a maintainer, I want the benchmark to refuse collection when the ticket-0.1 warmup precondition is invalid, to leave the production chat path untouched, and to leave zero residual diff after the temporary harness is deleted — so the ticket result is trustworthy and cannot pollute production.

**Why this priority**: #124 explicitly requires the baseline to record that the EntryAbility warmup is present, and forbids switching any production chat path to `StreamingReplyDocument`. A polluted baseline or a leaked harness would invalidate the whole ticket-0 gate.

**Independent Test**: Review the verification record and the scoped diff: precondition recorded as valid, no production render path change, harness deleted with byte-identical restoration of the temporarily touched files.

**Acceptance Scenarios**:

1. **Given** the harness starts, **When** it queries `ArkWebWarmupService.getBenchmarkBaselinePrecondition()`, **Then** the state is recorded in the report; if it is not `valid`, collection fails fast and no baseline numbers are produced.
2. **Given** the ticket completes, **When** the scoped diff is reviewed, **Then** no `StreamingReplyDocument` is introduced, no chat path switches renderer, and the only production changes are the agreed minimal measurement seam (counters/timestamps with zero rendering-logic change).
3. **Given** the harness observation is done, **When** the temporary page and its registrations are removed, **Then** `main_pages.json` and `EntryAbility.ets` are restored byte-identical with zero residual diff.
4. **Given** all evidence, **When** the gate is resolved, **Then** the result is one of `PASS_WITH_EMULATOR_PERFORMANCE_FOLLOW_UP` (all automated checks pass, ≥20 runs per fixture recorded with p50/p95, budget frozen, boundary intact, and DevEco emulator performance misses are recorded for follow-up), `FAIL` (metrics not reproducible or boundary violated — fix fixtures/measurement first, never pass on subjective smoothness), or `INCOMPLETE` (required device evidence missing).

---

### Edge Cases

- The warmup precondition is invalid → fail fast, record the state, collect nothing, do not mark the gate PASS.
- The first run of a fixture differs from later runs (cold cache / first Web creation) → runs are indexed and the report distinguishes cold vs warm runs; the statistical basis is stated in the ADR rather than silently pooled.
- A run hits the bridge return-limit fallback (formula-heavy C/C′) → degradation count recorded; the run still counts toward ≥20.
- A block render fails (`webFailed`) or falls back to plain text → the run is counted and the failure is recorded; height updates that never arrive are recorded as missing, not as zero.
- The harness list geometry makes a block out of viewport → the fixture texts are sized to fit one screen, and viewport membership is recorded via the harness's own area-change evidence; a block not in the viewport cannot satisfy `visible`.
- The 20th+ runs drift (e.g., memory pressure) → steady memory is sampled at finish+30s per run and any monotonic drift is reported, not averaged away.
- p95 of `T_firstDeltaToVisible` exceeds the 1.5s observation alarm line → reported as an observation (spec 021 explicitly does not block ticket acceptance on it); `T_finishToStable` p95 above the 500ms initial target on the DevEco emulator is recorded as a performance follow-up and does not invalidate the completed evidence baseline. The target itself is not lowered.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide four deterministic fixtures A/B/C/C′ with comparable plain-text character counts and controlled block-formula counts (A=0, B=2, C=6, C′=6 as 3 consecutive closed pairs); fixture content MUST be byte-reproducible with no randomness, network, or LLM dependency.
- **FR-002**: The system MUST freeze one `visible` definition (block rendered + in viewport + height callback applied with `renderedHeight > 0`) and one definition for each timing metric: `T_firstDeltaToVisible`, `finish→visible` (the measured analog for the N/A `T_sealedToVisible`), and `T_finishToStable` (stable = viewport-and-one-screen blocks final + 500ms without height change).
- **FR-003**: The system MUST apply the long-frame rule (frame >32ms in the first 500ms window) with the frozen constraint that two consecutive long frames never occur.
- **FR-004**: The system MUST record, per run: `visible` events, `T_firstDeltaToVisible`, `finish→visible`, `T_finishToStable`, long-frame samples, steady memory (sampled at finish+30s, not instantaneous peak), Web create count, and height update count.
- **FR-005**: The system MUST report p50 and p95 per metric per fixture with ≥20 runs each on the target device, MUST record the sample size and the cold/warm run distinction, and MUST retain the raw per-run samples (persisted, not only the percentile summary) so the reported p50/p95 can be recomputed.
- **FR-006**: The system MUST provide a minimal, non-behavioral measurement seam in the production renderers (`MathTextRenderer` / `FormulaSplitRenderer` scope): Web create count, height update count, and cache hit/miss counting only — it MUST NOT change any rendering decision, height, cache, or scheduling logic, and the render behavior MUST remain equivalent except for the added counting.
- **FR-007**: The system MUST drive the benchmark through a temporary harness page that reuses production `ChatBubble`/`FormulaSplitRenderer`/`MathTextRenderer` read-only, injects deltas at a fixed chunk size and tick rhythm (deterministic simulated SSE), and applies a fixed finish boundary; real LLM SSE MUST NOT participate in reproducible runs.
- **FR-008**: The system MUST query `ArkWebWarmupService.getBenchmarkBaselinePrecondition()` before collection and record its state in the report; when it is not `valid`, the system MUST fail fast and produce no baseline numbers.
- **FR-009**: The system MUST derive `RendererScheduler.maxWebCreatesPerFrame` and `maxWebWorkMsPerFrame` defaults from the measured evidence through a documented, recomputable derivation rule, freeze them in a new ADR, and backfill the frozen values into `docs/specs/021-chat-streaming-incremental-rendering.md` §6.
- **FR-010**: The system MUST NOT introduce `StreamingReplyDocument`, `RendererScheduler`, `RenderTick`, or any chat path switch in this ticket; existing `MarkdownRenderer`/`FormulaSplitRenderer` and Preferences chat history paths MUST remain intact.
- **FR-011**: The system MUST delete the temporary harness page after observation with `main_pages.json` and `EntryAbility.ets` restored byte-identical, leaving zero residual diff from the harness itself.
- **FR-012**: Changed `.ets` and test artifacts MUST pass ArkTS strict checks, relevant focused tests, the full test suite, naming check, diff check, and the project debug build; failures MUST be recorded rather than hidden, and a missing device run MUST be recorded as `INCOMPLETE`, never `PASS`.

### Key Entities *(include if feature involves data)*

- **ChatRenderFixture**: `{ id, bodyText, formulaCount, layout }` — one deterministic benchmark workload; A/B/C/C′ are the four instances.
- **FixtureRunSample**: one run's raw samples — visible events (block, timestamp), delta-arrival timestamp, finish timestamp, stable timestamp, frame durations, Web create count, height update count, degradation count, cache hit/miss counts, steady memory.
- **PercentileReport**: `{ fixtureId, runCount, per-metric p50/p95, cold/warm split }` — the machine-readable report surface.
- **RendererBudgetProposal**: `{ maxWebCreatesPerFrame, maxWebWorkMsPerFrame, derivation rule, evidence summary }` — frozen in the new ADR and backfilled into spec 021 §6.
- **BenchmarkBaselinePrecondition**: `valid`/`invalid`/unknown state from `ArkWebWarmupService` — collection gate; baseline is only collected when `valid`.
- **Gate Status**: one of `PASS_WITH_EMULATOR_PERFORMANCE_FOLLOW_UP`, `FAIL`, or `INCOMPLETE` with fixed downstream semantics.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The four fixtures are deterministic, their plain-text character counts are identical, and their formula counts are exactly A=0 / B=2 / C=6 / C′=6 (3 consecutive pairs); focused unit tests assert all of this with 100% passing.
- **SC-002**: Every fixture completes ≥20 runs on the MatePad Pro 13 emulator with per-metric p50/p95 reported and the sample size recorded.
- **SC-003**: The report records all required metrics — `visible`, `T_firstDeltaToVisible`, `finish→visible`, `T_finishToStable`, long-frame samples, steady memory, Web create count, height update count — plus degradation counts.
- **SC-004**: The report records the ticket-0.1 warmup precondition as `valid`; an invalid precondition produces fail-fast with zero baseline numbers.
- **SC-005**: The RendererScheduler budget defaults are frozen in a new ADR and backfilled into spec 021 §6, and the derivation is recomputable from the recorded evidence.
- **SC-006**: The scoped production diff contains no `StreamingReplyDocument` introduction and no chat render path switch; the only production changes are the agreed measurement seam; the temporary harness is deleted with byte-identical restoration and zero residual diff.
- **SC-007**: ArkTS checks, focused tests, the full entry test suite, naming lint, `git diff --check`, and the debug build all pass with no unreported failures.
- **SC-008**: If the metrics are not reproducible across runs, the ticket does not pass — the fixture/measurement setup is fixed first and subjective smoothness is never used as evidence.

## Assumptions

- The feature artifacts live under `spec/ticket-0-6-chat-render-fixtures-budgets/`; `spec/feature.json` is not repointed to this ticket (keeps pointing at the active 019 work, #123 precedent).
- The target device is the `MatePad Pro 13` emulator (127.0.0.1:5555), the same device used by #120–#123; the device model is recorded as part of the baseline environment.
- The harness page is temporary (#120/#123 precedent): created, observed, then deleted; durable evidence lives in the ADR, the backfilled spec 021 §6, the focused tests, and the verification record.
- Concrete fixture numbers (plain-text char count = 2000 UTF-16 code-units per fixture, character-identical across fixtures except formula count and formula close timing — the same unit as the Q19 offset decision; simulated-SSE chunk size and tick rhythm; steady-memory sampling point) are fixed defaults chosen for this baseline and recorded in the ADR.
- The measurement seam's counting is always-on but zero-logic; it does not gate, drop, or reorder any rendering work.
- Frame durations for the long-frame rule are sampled on the UI thread during the measurement window; the exact sampling mechanism is a Phase 2 decision constrained to SDK 24 APIs.
- `T_sealedToVisible` is out of the current path's vocabulary (no seal event exists before `StreamingReplyDocument`); the baseline records it as N/A and measures `finish→visible` instead (clarified decision).
- KaTeX output mode is unchanged in this ticket (`htmlAndMathml` default stays; the output-flag experiment is not part of ticket-0).

## Open Questions

- None. The feature directory, harness durability, simulated-SSE approach, seal mapping, measurement seam allowance, budget freeze destination, and target device were explicitly clarified before implementation.
