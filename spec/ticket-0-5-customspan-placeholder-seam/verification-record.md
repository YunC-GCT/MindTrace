# Verification Record: Ticket 0.5 CustomSpan Formula Placeholder Seam

**Ticket:** #123 / Ticket 0.5
**Feature directory:** `spec/ticket-0-5-customspan-placeholder-seam/`
**Verification scope:** `build+ui`
**Implementation date:** 2026-09-15
**Overall gate status:** PASS
**UI verification result marker:** `<!-- ui_verification_result: PASS -->`

## Phase 1 setup evidence

### Branch and pre-existing dirty inventory

- Current branch: `feature/spec-019-p0`.
- Pre-existing unrelated dirty work observed before #123 implementation (untouched by this ticket):

  ```text
  M CONTEXT.md
  M docs/adr/0015-structured-stream-events.md
  M docs/agents/qwen-deepseek-reasoning-handoff-2026-09-12.md
  M docs/research/index.md
  M docs/specs/019-reasoning-process-display-p0.md
  M docs/specs/index.md
  M spec/019-reasoning-process-display-p0/* (7 files)
  ?? agents/.preview/
  ?? common/.preview/
  ?? docs/research/arkweb-render-pipeline-stability-2026-09-11.md
  ?? docs/research/chat-markdown-latex-render-jank-2026-09-13.md
  ?? docs/specs/021-chat-streaming-incremental-rendering.md
  ?? entry/src/main/ets/shared/atoms/WebKeepAlive.ets
  ```

- #123 scoped files for this implementation pass:

  ```text
  spec/ticket-0-5-customspan-placeholder-seam/spec.md        (new)
  spec/ticket-0-5-customspan-placeholder-seam/plan.md        (new)
  spec/ticket-0-5-customspan-placeholder-seam/tasks.md       (new, checked off per phase)
  spec/ticket-0-5-customspan-placeholder-seam/verification-record.md (new)
  entry/src/main/ets/services/CustomSpanPlaceholderSeam.ets   (new)
  entry/src/test/CustomSpanPlaceholderSeam.test.ets           (new)
  entry/src/test/List.test.ets                                (register new test)
  ```

- Temporary artifacts created, observed, then removed with zero residual diff (not part of the final diff):

  ```text
  entry/src/main/ets/overlays/AgentFloatWindow/chat/CustomSpanSeamHarnessPage.ets  (created, observed, deleted)
  entry/src/main/resources/base/profile/main_pages.json        (temporarily registered, restored byte-identical)
  entry/src/main/ets/entryability/EntryAbility.ets             (temporarily switched entry, restored byte-identical)
  ```

### Reference reviews completed

- ArkTS strict rules reviewed in `docs/style/arkts-1.1.md`; applied constraints: no `any`/`unknown`, no destructuring, no inline object types, explicit typed object literals, explicit return types, no LaTeX imports.
- Spec 021 §5 (native Markdown + formula placeholders) and §12 (ticket-0 hard gate + CustomSpan failure branch) reviewed in `docs/specs/021-chat-streaming-incremental-rendering.md`.
- Official CustomSpan API verified with `devecocli docs` (`API参考/ArkUI_方舟UI框架/ArkTS组件/文本与输入/属性字符串/ts-universal-styled-string`):
  - `onMeasure(measureInfo: CustomSpanMeasureInfo): CustomSpanMetrics` — abstract; `CustomSpanMetrics { width (vp, 必填), height (vp, 可选;默认 Text fontSize) }`.
  - `onDraw(context: DrawContext, drawInfo: CustomSpanDrawInfo): void` — abstract; `CustomSpanDrawInfo { x, lineTop, lineBottom, baseline }` all px.
  - `invalidate(): void` — API 13+; documented as "主动刷新使用CustomSpan的Text组件".
  - `CustomSpanMeasureInfo { fontSize (fp) }`; `maxWidth`/`layoutPolicy` are API 26.0.0 additions — outside the API 24 baseline used here.
  - Official note: "最终的CustomSpan的高度是由当前Text组件的行高所决定的。当height大于当前行的其他子组件的高度时，此时height即为Text组件的行高。"
- Official example 6 (`StyledStringSetCustomspanDemo`) reviewed: same-instance `invalidate()` pattern; `gUIContext = this.getUIContext()` in `aboutToAppear`.

### Feature-pointer boundary

`spec/feature.json` still points to `spec/019-reasoning-process-display-p0`. It was not repointed to #123. This ticket owns only `spec/ticket-0-5-customspan-placeholder-seam/` and explicitly avoids hiding or taking ownership of the active #019/spec021 dirty work.

## Automated seam evidence

### TDD red-step record (Phase 2, 2026-09-15)

The initial focused test file (`entry/src/test/CustomSpanPlaceholderSeam.test.ets`) and its registration in `entry/src/test/List.test.ets` were created before the seam service existed, importing `../main/ets/services/CustomSpanPlaceholderSeam`.

Red evidence (true compile-time red, executed with the DevEco-bundled hvigor runner — see "Runner environment" below):

```text
hvigorw.js test -p module=entry -p coverage=false -p scope=CustomSpanPlaceholderSeam.issue123_width_estimate
```

Result: `FAIL` (compile) — `ERROR: 00305015 Rollup Error — Could not resolve "../main/ets/services/CustomSpanPlaceholderSeam"` + `10505001 ArkTS Compiler Error — Cannot find module`. Red by missing module, exactly as intended.

`arkts_check` on the red-step file passed ("No errors found in 2 file(s)"), consistent with the sibling records that the local check does not resolve cross-file module imports.

### Runner environment

- DevEco-bundled hvigor: `"D:\HarmoNova\DevEco Studio\tools\node\node.exe" "D:\HarmoNova\DevEco Studio\tools\hvigor\bin\hvigorw.js"` with `DEVECO_SDK_HOME = "D:\HarmoNova\DevEco Studio\sdk"`. (This resolves the `hvigorw not recognized` blocker recorded in the #120/#121 sibling records.)
- Device: `MatePad Pro 13` emulator, serial `127.0.0.1:5555`.

### Implemented focused seam

`entry/src/main/ets/services/CustomSpanPlaceholderSeam.ets` implements:

- `FORMULA_PLACEHOLDER_MAX_CHARS = 40` (frozen by this ticket, per clarified decision).
- Pure `estimatePlaceholderWidthVp(content, fontSizeFp)` = `16 + min(len, 40) × fontSizeFp × 0.62` — deterministic, bounded.
- Pure `InlineFormulaPlaceholderModel`: open phase freezes `openWidthVp` at construction; `appendDelta` never touches widths; `close()` recomputes `closedWidthVp` exactly once; open height = 1.4×fontSize, closed height = 2.2×fontSize; `displayText()` caps content and appends `…` when truncated.
- `CustomSpanVerificationReport`: measure/draw/invalidate counters, last metrics, last draw sample (`lineHeight = lineBottom - lineTop`), per-phase distinct-width sets with `openWidthStable()` / `closedWidthRecorded()` / `widthUpdatedOnClose()`.
- `InlineFormulaPlaceholderSpan extends CustomSpan`: `onMeasure` records + delegates to the model and hilogs (vp metrics + `measureInfo.fontSize` fp); `onDraw` records + hilogs the px draw offsets and paints a plain gray chip via `drawing.Brush`/`drawing.TextBlob` (no LaTeX); `invalidate()` records then `super.invalidate()`; `vp2px` injected at construction.
- `customSpanGateSemantics(status)` — PASS/FAIL/INCOMPLETE tri-state mapping.

### Focused and full automated results

Focused describe (`CustomSpanPlaceholderSeam.issue123_width_estimate`): `Tests run: 4, Failure: 0, Pass: 4`.

Full entry Hypium suite (`hvigorw.js test -p module=entry -p coverage=false`, run before the harness existed, again after harness removal, and once more after the post-review fixes):

```text
Tests run: 89, Failure: 0, Error: 0, Pass: 89, Ignore: 0   (final, after post-review fixes)
```

All 20 focused #123 assertions pass across six `CustomSpanPlaceholderSeam.issue123_*` describes:

- `width_estimate` 4/4 — minimum chip width, monotonic growth, cap frozen at 40, over-cap estimate equals at-cap estimate.
- `open_width_stability` 2/2 — measured width frozen across appended deltas; phase stays open.
- `close_transition` 3/3 — width recomputed exactly once on close; idempotent re-close; closed height taller than open height.
- `display_truncation` 2/2 — over-cap content truncated with `…`; within-cap content unchanged.
- `report_counters` 6/6 — counters increment; line height derived from offsets; single distinct open width; no vacuous stability with zero measures; close width update recorded; area-change recording stores the signed delta.
- `gate_status_template` 3/3 — PASS releases downstream design only; FAIL mandates contract redesign (never finish-only); INCOMPLETE blocks.

The other 69 entry tests show no regressions.

## On-device harness observation (Phase 7, 2026-09-15)

The temporary harness page `entry/src/main/ets/overlays/AgentFloatWindow/chat/CustomSpanSeamHarnessPage.ets` rendered one `Text` (TextController + `MutableStyledString` of prefix text + the span + suffix text) with `.onAreaChange`, three buttons, and a live counter panel. The app entry was temporarily switched to the harness route. A scripted sequence ran: 追加增量 ×3 (900ms apart) → 闭合公式 → reSetStyledString → 布局触发 (fontSize nudge).

Complete device evidence chain (`A0a001/CustomSpanSeam` hilog on `MatePad Pro 13`, cleaned buffer, fresh launch at 22:20:11):

```text
panel m=0 d=0 i=0 openStable=true closedRecorded=false widthUpdated=false
measure widthVp=125.12 heightVp=22.40 phase=open fontSizeFp=16.00
draw x=94.80 lineTop=14 lineBottom=59 baseline=50.99            (×2 initial draws)
areaChange h=36.50 delta=36.50
invalidate total=1 ... draw (no re-measure)                    (追加增量 1)
invalidate total=2 ... draw (no re-measure)                    (追加增量 2)
invalidate total=3 ... draw (no re-measure)                    (追加增量 3)
invalidate total=4 ... draw (no re-measure)                    (闭合公式 close + invalidate)
panel m=1 d=6 i=4 openStable=true closedRecorded=false widthUpdated=false
step reSetStyledString done phase=closed
measure widthVp=412.80 heightVp=35.20 phase=closed fontSizeFp=16.00
draw x=94.80 lineTop=14 lineBottom=84 baseline=76.59
areaChange h=49.00 delta=12.50
panel m=2 d=7 i=4 openStable=true closedRecorded=true widthUpdated=true
step nudgeLayout done nudge=true
measure widthVp=412.80 heightVp=35.20 phase=closed fontSizeFp=17.00
draw x=99.85 lineTop=14 lineBottom=84 baseline=76.10
```

A supplementary screenshot was captured from the device during observation (`snapshot_display`, 2880×1920, saved to the session temp area) showing the harness page mid-sequence; the log lines above are the authoritative evidence.

### Findings recorded (for ticket-2 and the GeometryChanged design)

1. **Measure fires only at Text layout, not per invalidate.** `onMeasure` ran once for the initial layout; all four `invalidate()` calls (open deltas + close) produced re-**draw** only — measure count stayed 1. Therefore the open-phase width is trivially stable on this SDK: open deltas never re-measure, and the frozen estimate `125.12vp` (`16 + 11 chars × 16fp × 0.62`, matching the pure estimate exactly) stays in force.
2. **`invalidate()` = repaint, not re-measure.** The official doc describes invalidate as "主动刷新使用CustomSpan的Text组件", and on this SDK (API 24 / 6.1.1(24)) the observed semantics are repaint-only. The close transition must therefore be driven by a **re-layout trigger**, not by invalidate alone.
3. **`TextController.setStyledString(same MutableStyledString instance)` is a working re-layout trigger.** Re-setting the *same* instance (the span identity preserved — no replacement, no new span) re-measured the span with closed metrics (`widthVp=412.80`, `heightVp=35.20`), re-drew it, and produced `areaChange h=49.00 delta=12.50` — a measurable signed Text height change. Any other re-layout trigger (e.g., a Text attribute change like the fontSize nudge, which re-measured with `fontSizeFp=17.00`) behaves the same way.
4. **Draw/layout callback units are now factually fixed**: `CustomSpanMetrics` in vp; `CustomSpanDrawInfo` (`x`/`lineTop`/`lineBottom`/`baseline`) in px; `onAreaChange` heights in vp. Observed open line height `lineBottom - lineTop = 45px` (line governed by the Text's line height, per the official note), closed line height `70px` after the taller closed height (2.2×fontSize) took effect.
5. **Height update behavior**: when the span's measured height grew (22.40 → 35.20 vp), the Text grew and `onAreaChange` reported the height delta (+12.50 vp). This is the callback the future `GeometryChanged` (`messageId`, signed `totalHeightDelta`, `ts`) design needs; the harness recorded it directly.

### Gate resolution against acceptance criteria

- "A minimal CustomSpan verification demonstrates measure/draw/invalidate behavior on the target SDK/device" — **demonstrated**: measure (layout), draw (paint, ×7), invalidate (×4) all observed on the emulator with recorded metrics.
- "Inline formula placeholder width remains stable while content is open and can update when the formula closes" — **verified**: width frozen at `125.12vp` across three open deltas; width updated to `412.80vp` on close via the recorded re-layout trigger, on the same span instance.
- "The verification records any height or layout callback behavior needed by later GeometryChanged work" — **recorded**: draw offsets (px) + `onAreaChange` height deltas (vp) above, with the invalidate-vs-layout trigger distinction.
- "The test does not require a LaTeX engine" — **satisfied**: no LaTeX/KaTeX/MathTextParser/ContentProtocol imports anywhere; the chip is plain `drawing` API paint.
- "No production chat path is switched to CustomSpan rendering yet" — **satisfied**: see Preservation checks.
- "ArkTS check, relevant tests, and debug build pass" — **satisfied**: see Polish checks.

### PASS/FAIL/INCOMPLETE semantics (template)

- **PASS**: all automated assertions pass and the required device evidence passes. Meaning: the three-state rendering contract is released for downstream design consideration only. This ticket still does not wire CustomSpan into any production chat path.
- **FAIL**: placeholder width instability, or measure/draw/invalidate misbehavior observed. Meaning: return to the rendering contract design (spec 021 §12); finish-only rendering is never adopted.
- **INCOMPLETE**: automated evidence passes but required device evidence is missing/inconclusive. Meaning: the rendering contract remains blocked; missing evidence is recorded as blocked tasks rather than done.

## Preservation checks

- Grep of the #123 scoped production diff for `ChatBubble`, `AgentMessageList`, `chatItemKey`, `MarkdownRenderer`, `FormulaSplitRenderer`, `StreamingReplyDocument`, and persistence paths: **no matches** — none of these files are in the diff (the only modified existing file is `entry/src/test/List.test.ets`; the two new files are the seam service and its test).
- No production chat path renders via CustomSpan; the seam service is unwired.
- Temporary harness page deleted; `main_pages.json` and `EntryAbility.ets` restored byte-identical to HEAD (verified `git diff` empty for both files).
- `spec/feature.json` untouched.

## Polish checks and final scoped diff

- `arkts_check` sweep over `entry/src/main/ets/services/CustomSpanPlaceholderSeam.ets`, `entry/src/test/CustomSpanPlaceholderSeam.test.ets`, `entry/src/test/List.test.ets`, `entry/src/main/ets/entryability/EntryAbility.ets`: `PASS` — no errors in 4 files. (The harness page and the temporarily switched EntryAbility each passed `arkts_check` during Phase 7 before removal.)
- Full entry Hypium suite (final sweep after harness removal): `PASS` — `Tests run: 89, Failure: 0, Error: 0, Pass: 89, Ignore: 0`.
- Repository Node lint suite: `npm --prefix scripts/arkts-lint test` → `PASS` — 103 passed, 0 failed.
- Naming lint: `node scripts/naming-lint/index.mjs` → `PASS` — 0 violations. (Coverage caveat: naming-lint roots cover `docs/` and `scripts/` only; the new `spec/ticket-0-5-customspan-placeholder-seam/`, `entry/src/main/ets/services/CustomSpanPlaceholderSeam.ets`, and `entry/src/test/CustomSpanPlaceholderSeam.test.ets` names were reviewed manually against `docs/style/naming-conventions.md` — kebab-case spec dir, `PascalCase` service file, `*.test.ets` test file — and follow repo conventions.)
- `git diff --check`: `PASS` — no whitespace errors.
- Debug build (whole project, production entry `pages/Index` restored): `PASS` — `hvigor BUILD SUCCESSFUL`, exitCode 0; only pre-existing out-of-scope deprecation warnings.

### Final scoped diff inventory

```text
entry/src/main/ets/services/CustomSpanPlaceholderSeam.ets   (new)
entry/src/test/CustomSpanPlaceholderSeam.test.ets           (new)
entry/src/test/List.test.ets                                (register new test)
spec/ticket-0-5-customspan-placeholder-seam/                (spec.md, plan.md, tasks.md, verification-record.md)
```

The broad working tree still contains the pre-existing unrelated #019/spec021 dirty and untracked files listed in Phase 1; they were not reverted, staged, or edited for #123.

## Final gate resolution

- Automated evidence: `PASS` (20/20 focused assertions; full entry suite 89/89; arkts_check PASS; Node lint 103/103; naming lint PASS; debug build PASS).
- Device evidence: `PASS` (the on-device observation above: measure/draw/invalidate lifecycle, frozen open width, closed width/height update, draw offsets and areaChange delta recorded).
- `ui_verification_result`: `PASS`; overall gate status: **`PASS`**.
- Downstream semantics: the three-state rendering contract is eligible for downstream design consideration **only**; no production chat path was switched in this ticket.
- Gate-justification note (per the two-axis review): PASS is not a silent reinterpretation. The ticket's acceptance criteria ("width remains stable while content is open and can update when the formula closes") are satisfied with a demonstrated mechanism; the one adjustment discovered on-device — `invalidate()` is repaint-only and the close-phase size update additionally needs a re-layout trigger (verified: `setStyledString` with the same `MutableStyledString` instance, span identity preserved) — is recorded as the design input for ticket-2, and spec 021 §12's failure branch ("CustomSpan 占位更新失败") did not trigger because the update demonstrably works. The spec artifact (US1-2, FR-004, FR-005, FR-006) was amended to state the verified mechanism rather than the overpromised `invalidate()`-only wording.

## Post-review fixes

Applied after the two-axis code review (Standards + Spec sub-agents, 2026-09-15):

1. **Spec wording reconciled with device reality** (`spec/ticket-0-5-customspan-placeholder-seam/spec.md`): US1 scenario 2 now states the verified repaint-only `invalidate()` semantics; FR-004 now mandates the verified close-update path (same span instance + `invalidate()` + re-layout trigger, verified trigger `setStyledString` with the same `MutableStyledString`); FR-005/FR-006 now include the durable area-change record surface; edge cases updated with observed line-height facts (45px → 70px).
2. **Durable area-change record surface** (`entry/src/main/ets/services/CustomSpanPlaceholderSeam.ets`): `CustomSpanVerificationReport` gained `recordAreaChange(heightVp, deltaVp)` with `areaChangeCount()`/`lastAreaHeightVp()`/`lastAreaDeltaVp()` getters, so FR-006 is satisfied by shipped code rather than harness-only prose. New test: `should record area height changes with the signed delta`.
3. **Non-vacuous width-stability verdict**: `openWidthStable()` now requires exactly one distinct open width (`openWidths_.length === 1`); zero open measures no longer report "stable". New test: `should not report open width stability without any open measure`.
4. **Gate semantics moved test-side** (speculative-generality cleanup): `CustomSpanGateStatus`/`CustomSpanGateSemantics`/`customSpanGateSemantics` removed from the production service and defined locally in `entry/src/test/CustomSpanPlaceholderSeam.test.ets`, mirroring the #120/#121 gate-template precedent. The unused `fallbackBranchReleased` field was dropped (the "finish-only" fallback is forbidden, not a branch to release). `plan.md` contracts updated accordingly.
5. **Duplication and cohesion cleanups** (`CustomSpanPlaceholderSeam.ets`): `onDraw` no longer pre-computes `lineHeight` (the report derives it in one place); `measureMetrics()` computes width/height once and returns a single literal; the file header now documents the `数据流` field and class-level separation wording.
6. **Test hygiene** (`CustomSpanPlaceholderSeam.test.ets`): `repeatChar` converted from a C-style `for` to a `while` loop; the repeated `fontSizeFp` literal hoisted to `TEST_FONT_SIZE_FP`.
7. **Evidence-number corrections** (`verification-record.md`): the focused count is 18 assertions pre-fix / 20 post-fix across six describes (not 21 across seven); the other entry tests number 69 (not 66); final suite 89/89.

Re-verification after the fixes:

- `arkts_check` on the two changed `.ets` files: `PASS` — no errors.
- Full entry Hypium suite: `PASS` — `Tests run: 89, Failure: 0, Error: 0, Pass: 89, Ignore: 0` (20/20 focused #123 assertions; no regressions in the other 69).
- `git diff --check`: `PASS`. Naming lint and Node lint unaffected by these files.
- The debug build after these fixes is re-run as the final build gate (see Polish checks).

The overall gate status remains **`PASS`** after these fixes.
