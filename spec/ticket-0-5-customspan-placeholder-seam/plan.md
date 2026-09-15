# Implementation Plan: Ticket 0.5 CustomSpan Formula Placeholder Seam

**Input**: Feature specification from `spec/ticket-0-5-customspan-placeholder-seam/spec.md`

## Summary

#123 is a hard verification gate for the inline-formula branch of spec 021. It verifies that the `CustomSpan` seam needed for inline formula placeholders behaves as the three-state rendering contract requires: an initial width estimate, a stable placeholder width while the formula is open, an invalidate-driven width/height update when the formula closes, and recorded draw/layout callback behavior for the later `GeometryChanged` work.

The seam is a single service file with three cooperating pieces: a pure, UI-free `InlineFormulaPlaceholderModel` (phase, capped content, frozen open width, recomputed closed width), a `CustomSpan` subclass `InlineFormulaPlaceholderSpan` that delegates measure/draw to the model and feeds every callback into a `CustomSpanVerificationReport`, and the report itself. Unit tests exercise the pure model and report; a temporary harness page renders the span on the emulator and proves the framework-level measure/draw/invalidate cycle on device, then is deleted so nothing ships.

The gate is tri-state: `PASS` releases the three-state rendering contract for downstream design consideration only, `FAIL` returns to the rendering contract design (never finish-only), and `INCOMPLETE` blocks downstream tickets until device evidence is completed. The global `spec/feature.json` pointer is not owned by this ticket.

## Technical Context

**Language/Version**: ArkTS 1.1 strict, HarmonyOS project baseline from existing `build-profile.json5`
**Primary Dependencies**: `@kit.ArkUI` (ambient `CustomSpan`/`StyledString`/`MutableStyledString`/`TextController`; `DrawContext`), `@kit.ArkGraphics2D` (`drawing.Brush`/`drawing.Font`/`drawing.TextBlob` for the plain chip), `@kit.PerformanceAnalysisKit` (hilog), `@ohos/hypium` (tests)
**State Management**: The span is a plain retained instance; the framework re-measures/re-draws it via `invalidate()`; no `@State` migration, no component replacement
**Storage**: None in this ticket; chat history Preferences path untouched
**Testing**: Existing Hypium-style `.ets` tests under `entry/src/test/` registered in `List.test.ets`; `arkts_check`; focused tests; one full suite run at the end; debug build
**Target Platform**: MindTrace HarmonyOS entry-module chat floating window (production path read-only); emulator `MatePad Pro 13` for the harness observation
**Project Type**: Existing multi-module HarmonyOS mobile application (1 HAP + 4 HSP)
**Performance Goals**: Zero production overhead — the seam is an unwired service and the harness is deleted after observation
**Constraints**: API 24 baseline only (no `maxWidth`/`layoutPolicy`); no LaTeX/KaTeX/`MathTextParser`/`ContentProtocol` rendering; no production chat/renderer/persistence changes; do not repoint `spec/feature.json`; do not modify unrelated dirty work; harness must be deleted with zero residual diff
**Scale/Scope**: One P0 gate ticket; one new service file, one new focused test file, one temporary harness page (deleted), one verification record

## Project Structure

### Documentation (this feature)

```text
spec/ticket-0-5-customspan-placeholder-seam/
|-- spec.md
|-- plan.md
|-- tasks.md
`-- verification-record.md
```

### Source Code (repository root)

```text
entry/src/main/ets/
|-- services/
|   `-- CustomSpanPlaceholderSeam.ets      # New: model + span + report + gate semantics
`-- overlays/AgentFloatWindow/chat/
    `-- CustomSpanSeamHarnessPage.ets      # Temporary: on-device demonstration (deleted after observation)

entry/src/test/
|-- List.test.ets                          # Modified: register the focused seam test
`-- CustomSpanPlaceholderSeam.test.ets     # New: focused #123 automated seam

entry/src/main/resources/base/profile/
`-- main_pages.json                        # Temporary: register harness route (restored to zero diff)

entry/src/main/ets/entryability/
`-- EntryAbility.ets                       # Temporary: point loadContent at harness (restored to zero diff)
```

**Structure Decision**: Follow the existing MindTrace entry architecture — services live in `entry/src/main/ets/services/` (the #121 precedent for a production-side, not-yet-wired seam). The seam is placed in `main` (not `test`) because the temporary harness page in the main source set must import the span, and `src/test` imports of main-side files are the repo's normal test direction. The durable automated tests live in `entry/src/test/` like every sibling ticket-0.x. The harness page mirrors the #120 verification-only harness precedent: created, observed, then deleted with `main_pages.json` and `EntryAbility.ets` restored byte-identical.

## Complexity Tracking

No planned architecture complexity violations. One deliberate split is recorded: the pure model is separated from the `CustomSpan` subclass so the width-stability contract and the report are fully testable in Hypium without instantiating an ArkUI class in a non-UI test environment. The span subclass is a thin delegating adapter whose framework-level behavior is proven once on the emulator via the temporary harness.

## Research & Decisions

- **Decision**: Seam lives in `entry/src/main/ets/services/CustomSpanPlaceholderSeam.ets` as a production-side, not-yet-wired service.
  **Rationale**: The harness page (main source set) must import the span; main-side service placement follows the #121 seam precedent and keeps the ticket-2 `InlineFormulaBlock → CustomSpan` backend one import away. It ships unused until ticket-2 wires it.
  **Alternatives considered**: Test-side placement (`entry/src/test/`) was rejected because main cannot import test sources and the harness needs the real span class.

- **Decision**: Pure placeholder model + thin `CustomSpan` adapter, with the width estimate as a deterministic char-width heuristic.
  **Rationale**: The model is 100% unit-testable without ArkUI runtime; the estimate only needs to be a stable, bounded placeholder width (`16vp` chip padding + `min(len, 40) × fontSizeFp × 0.62`), not a typeset width. Spec 021 §5 explicitly says "估算一次" (estimate once), not "measure precisely".
  **Alternatives considered**: `MeasureUtils.measureTextSize` was rejected for the pure model because it needs a UIContext and would push the width contract out of Hypium coverage.

- **Decision**: Open-phase height = 1.4 × fontSize (single line); closed-phase height = 2.2 × fontSize (taller, models a real rendered formula). The close transition therefore produces a measurable Text height change.
  **Rationale**: Acceptance criterion 3 requires recording height/layout callback behavior. A close-phase height change drives both the span re-measure and the Text `onAreaChange` delta, producing the exact facts the `GeometryChanged` design needs.
  **Alternatives considered**: Keeping height constant was rejected because it would not exercise the height-update behavior the ticket must record.

- **Decision**: The span records every callback into a `CustomSpanVerificationReport` and mirrors the same metrics into hilog under a fixed tag.
  **Rationale**: The report is the durable, assertable evidence surface (unit-tested); hilog gives the on-device observation channel for the harness (collected via device log during observation). Both are needed because `onMeasure`/`onDraw` only fire inside a real Text layout.
  **Alternatives considered**: Report-only was rejected (no device observation channel); log-only was rejected (not assertable in Hypium).

- **Decision**: The span's `invalidate()` override records the call and then delegates to `super.invalidate()`.
  **Rationale**: The official pattern mutates span state then calls `invalidate()`; overriding to record keeps the caller API identical while producing the invalidate-count evidence.
  **Alternatives considered**: A separate `refresh()` wrapper was rejected because spec 021 §5 mandates the official `invalidate()` seam itself.

- **Decision**: The span receives a `vp2px` converter at construction (injected by the harness from `getUIContext().vp2px`).
  **Rationale**: `onDraw` only receives px offsets and no UIContext; the chip rectangle width needs px. Injection keeps the span environment-free and the harness provides the converter in `aboutToAppear`.
  **Alternatives considered**: Hard-coding a density was rejected (device-dependent); storing px from `onMeasure` was rejected because API 24 `CustomSpanMeasureInfo` exposes only `fontSize` in fp.

- **Decision**: Temporary harness page (created → observed → deleted), per the user-confirmed #120 precedent.
  **Rationale**: measure/draw/invalidate only fire inside a rendered Text, and the repo has no other UI-driving route that does not touch production. A separate page keeps production untouched and is removed after observation.
  **Alternatives considered**: A permanently shipped debug page was rejected by the user decision; instrument-test window mounting was rejected as unproven in this repo and riskier than the #120 precedent.

- **Decision**: No LaTeX engine anywhere in the seam; `onDraw` paints a plain gray chip with the truncated placeholder text via `drawing.Brush`/`drawing.TextBlob`.
  **Rationale**: Acceptance criterion 4 forbids LaTeX dependency; the placeholder is a visual chip by spec 021 §5.
  **Alternatives considered**: Any KaTeX/`MathTextParser`/WebView involvement was rejected as gate-violating.

- **Decision**: Preserve the repository feature-pointer boundary; do not repoint `spec/feature.json`.
  **Rationale**: Same as the #120/#121 records — the pointer belongs to the active 019 work.

## Data Model

### Placeholder Phase

- **Values**: `'open'` (content streaming; width frozen) | `'closed'` (formula complete; width recomputed once).
- **Transitions**: `open → closed` only, once; repeated close calls are idempotent.

### Inline Formula Placeholder Model (pure)

- **Fields**: `phase`, `content` (capped at `FORMULA_PLACEHOLDER_MAX_CHARS = 40`), `fontSizeFp`, `openWidthVp` (frozen at construction from the entry content), `closedWidthVp` (recomputed on close), `openHeightVp` (1.4 × fontSize), `closedHeightVp` (2.2 × fontSize).
- **Validation rules**: `appendDelta` grows content (capped) and never touches widths; `close` recomputes `closedWidthVp` exactly once and sets `phase`; `measureMetrics()` returns `{ widthVp, heightVp }` for the current phase; `displayText()` returns the capped content with a trailing ellipsis when truncated.
- **Pure helpers**: `estimatePlaceholderWidthVp(content, fontSizeFp)` = `16 + min(len, 40) × fontSizeFp × 0.62`, deterministic and bounded.

### CustomSpan Verification Report

- **Fields**: `measureCount`, `drawCount`, `invalidateCount`, `lastMetrics` (`PlaceholderMetrics`), `lastDrawSample` (`DrawSample`: `x`/`lineTop`/`lineBottom`/`baseline`/`lineHeight` in px), distinct open-phase width set, distinct closed-phase width set.
- **Validation rules**: `recordMeasure(metrics, phase)` appends a width to the per-phase set only when it differs from the previous one; `openWidthStable()` = the open set has ≤ 1 distinct width; `closedWidthRecorded()` = the closed set has ≥ 1 width; `widthUpdatedOnClose()` = closed width differs from the open width.
- **Draw Sample derivation**: `lineHeight = lineBottom - lineTop`.

### Gate Status

- **Values**: `PASS` | `FAIL` | `INCOMPLETE`, each mapping to fixed downstream semantics (`customSpanGateSemantics(status)`).
- **Validation rules**: `PASS` releases the rendering contract for downstream design consideration only; `FAIL` blocks the contract and mandates redesign (never finish-only); `INCOMPLETE` blocks downstream tickets and records missing evidence.

## Contracts & Interfaces

### CustomSpanPlaceholderSeam (new service, `entry/src/main/ets/services/CustomSpanPlaceholderSeam.ets`)

- `FORMULA_PLACEHOLDER_MAX_CHARS: number` — constant `40` (frozen by this ticket).
- `type PlaceholderPhase = 'open' | 'closed'`.
- `interface PlaceholderMetrics { widthVp: number; heightVp: number }`.
- `interface DrawSample { x: number; lineTop: number; lineBottom: number; baseline: number; lineHeight: number }`.
- `function estimatePlaceholderWidthVp(content: string, fontSizeFp: number): number` — pure, deterministic, bounded.
- `class InlineFormulaPlaceholderModel` — constructor `(initialContent: string, fontSizeFp: number)`; methods `appendDelta(delta: string): void`, `close(): void`, `measureMetrics(): PlaceholderMetrics`, `displayText(): string`, `phase(): PlaceholderPhase`, `contentLength(): number`, `isClosed(): boolean`.
- `class CustomSpanVerificationReport` — `recordMeasure(metrics: PlaceholderMetrics, phase: PlaceholderPhase): void`, `recordDraw(sample: DrawSample): void`, `recordInvalidate(): void`, `recordAreaChange(heightVp: number, deltaVp: number): void`; getters `measureCount()`, `drawCount()`, `invalidateCount()`, `areaChangeCount()`, `lastMetrics()`, `lastDrawSample()`, `lastAreaHeightVp()`, `lastAreaDeltaVp()`, `openWidthStable()`, `closedWidthRecorded()`, `widthUpdatedOnClose()`. `openWidthStable()` is true only when exactly one distinct open width was observed (never vacuously true with zero measures).
- `class InlineFormulaPlaceholderSpan extends CustomSpan` — constructor `(model, report, vp2px: (vp: number) => number)`; overrides `onMeasure` (records + delegates to model), `onDraw` (records + draws gray chip with `drawing` APIs), `invalidate` (records + `super.invalidate()`); convenience `appendDelta(delta)` and `close()` delegating to the model.

### Automated Verification Contract (`entry/src/test/CustomSpanPlaceholderSeam.test.ets`)

- Width estimate: deterministic bounds, growth monotonicity, cap enforcement at 40.
- Open-phase stability: multiple `appendDelta` calls never change `measureMetrics().widthVp`.
- Close transition: width recomputed once, phase flips, idempotent re-close.
- Display truncation: content over the cap shows ellipsis and capped length.
- Report: counters increment; open width set stays single-valued (and is never vacuously stable with zero measures); closed width recorded and differs from open; area-change recording stores the signed delta.
- Gate semantics: PASS/FAIL/INCOMPLETE text and flags (test-side `customSpanGateSemantics`, mirroring the #120/#121 gate-template precedent).

### Harness Contract (temporary, `entry/src/main/ets/overlays/AgentFloatWindow/chat/CustomSpanSeamHarnessPage.ets`)

- One `Text` (TextController + `MutableStyledString` of prefix text + the span + suffix text) with `.onAreaChange` recording height/width deltas into state and hilog.
- Three buttons: 追加增量 (append delta + invalidate), 闭合公式 (close + invalidate), 刷新计数 (refresh the counter panel).
- Panel shows measure/draw/invalidate counts, last metrics, last draw sample, phase, and the width-stability verdict.
- hilog tag `CustomSpanSeam` on every callback with metrics (collected via device log during observation).

### Preservation Contract

- `ChatBubble.ets`, `AgentMessageList.ets`, `ChatModels.ets` (including `chatItemKey`), `MarkdownRenderer.ets`, `FormulaSplitRenderer.ets`, and all persistence paths remain unchanged.
- No `StreamingReplyDocument` introduced; no CustomSpan wired into any production chat path.
- Harness page, `main_pages.json` registration, and `EntryAbility.ets` entry switch are restored to zero diff after observation.
- `spec/feature.json` remains untouched.

## Changelog

- **2026-09-15**: Initial plan for #123, reconciled with the clarified decisions (temporary harness then delete, `FORMULA_PLACEHOLDER_MAX_CHARS = 40`, feature directory `spec/ticket-0-5-customspan-placeholder-seam/`).
