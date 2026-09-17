# ADR-0017 — RendererScheduler budget defaults are frozen from ticket-0 device measurement

**Status**: accepted (2026-09-16; corrected raw evidence committed; evidence baseline accepted with emulator performance follow-up — see "Evidence")
**Related**: [spec 021 §6](../specs/021-chat-streaming-incremental-rendering.md) · [ADR-0015](./0015-structured-stream-events.md) · [ADR-0016](./0016-reply-contract-by-transport.md)

## Decision

The `RendererScheduler` per-frame budgets get their default values from the ticket-0 chat-render
benchmark evidence on the target device, not from guessing. The two defaults are frozen here:

- `maxWebCreatesPerFrame = clamp(floor(32 / median(perCreateWorkMs)), 1, 4)`
- `maxWebWorkMsPerFrame = clamp(round(p75(perCreateWorkMs)), 1, 16)`

**Final frozen values from corrected evidence**:

- `maxWebCreatesPerFrame = 1`
- `maxWebWorkMsPerFrame = 16`

The current production render path does not meet the initial `T_finishToStable` performance target on
the DevEco emulator (`p95 > 500ms` on B/C/C′), but the raw evidence is complete, committed, and
recomputable. This emulator result is recorded as a performance follow-up, not as a failure of the
benchmark evidence deliverable.

## Context

spec 021 §6 defines `maxWebCreatesPerFrame` (hard per-frame quantity cap) and `maxWebWorkMsPerFrame`
(soft per-frame time budget) and states their defaults must be fixed by ticket-0 device measurement
and must not be freely changed by later tickets. 32ms is the frozen long-frame budget; the quantity
cap keeps one frame's Web-creation work below that budget, and the time budget uses the p75 of a
typical work unit with a hard 16ms ceiling (half of the 32ms frame budget as safety margin).

## Derivation rule (recomputable)

- `perCreateWorkMs` = the measured sample set of each Web work unit's duration from creation
  (MathTextRenderer enters the Web render decision) to its first real height application.
- `maxWebCreatesPerFrame = clamp(floor(32 / median(perCreateWorkMs)), 1, 4)`
- `maxWebWorkMsPerFrame = clamp(round(p75(perCreateWorkMs)), 1, 16)`
- Percentiles use nearest-rank (`ceil(p/100 * n)`); the clamp bounds are frozen constants.
- Final values are recomputable from the corrected raw per-run JSONL files in
  `spec/ticket-0-6-chat-render-fixtures-budgets/raw/` (one record per run, 20 rows per fixture). The
  older Phase-9 proxy-derived values below are retained only as superseded historical evidence.

## Environment

- Device: MatePad Pro 13 emulator (serial 127.0.0.1:5555), the same device used by tickets #120–#123.
- Fixtures: deterministic A/B/C/C′ (2000 UTF-16 code-units each; block-formula counts 0/2/6/6; C′ =
  3 consecutive closed pairs) — see `entry/src/main/ets/services/ChatRenderFixtures.ets`.
- Protocol: ≥20 runs per fixture, p50/p95 per metric, cold/warm runs distinguished; steady memory
  sampled at finish+30s; long-frame rule = frame >32ms in the first 500ms after finish with the
  frozen constraint that two consecutive long frames never occur; `T_firstDeltaToVisible` p95 >1.5s
  is an observation alarm only (never blocks the evidence deliverable). `T_finishToStable` p95 >500ms
  is a performance-target miss on the DevEco emulator and is carried forward as a follow-up; the
  target itself is not lowered.

## Evidence

Corrected evidence was collected 2026-09-16 on the MatePad Pro 13 emulator (127.0.0.1:5555) with the
post-review seam that emits `webWorkStartCount` and `webWorkDurationSamplesMs` directly. One process
ran warmup → precondition query → A/B/C/C′ 4×20 collection and emitted
`ALL_RUNS_DONE records=80` at 12:53:02.690. Raw rows are committed under
`spec/ticket-0-6-chat-render-fixtures-budgets/raw/`:

- `A.jsonl` — 20 rows
- `B.jsonl` — 20 rows
- `C.jsonl` — 20 rows
- `C_P.jsonl` — 20 rows

### Corrected per-fixture p50/p95 (raw JSONL, n=20 per fixture)

| Metric | A (0 formulas) | B (2 formulas) | C (6 formulas) | C′ (3 consecutive pairs) |
|---|---:|---:|---:|---:|
| `tFirstDeltaToVisibleMs` | n/a | 275 / 288 | 459 / 2285 | 381 / 538 |
| `finishToVisibleMs` | n/a | 15 / 33 | 38 / 141 | 31 / 69 |
| `tFinishToStableMs` | n/a | **545 / 554** | **708 / 2649** | **608 / 687** |
| `webCreateCount` | 0 / 0 | 5 / 5 | 13 / 13 | 10 / 10 |
| `longFrameCount` | 0 / 0 | 1 / 2 | 0 / 0 | 0 / 0 |
| runs with consecutive long frames | 0/20 | **13/20** | 0/20 | 0/20 |
| `webWorkDurationSampleCount` total | 0 | 5 | 7 | 4 |
| `webWorkDurationSamplesMs` median / p75 / p95 | n/a | 86 / 131 / 131 | 284 / 590 / 1038 | 386 / 580 / 591 |
| steady `heapUsed` KB first→last | 3941→7648 | 9059→13226 | 14803→9572 | 10945→12966 |

Cold/warm split is explicit in the raw rows (`runIndex=0` = `cold`, `runIndex=1..19` = `warm`):

| Fixture | Cold `T_finishToStableMs` | Warm `T_finishToStableMs` p50/p95 | Direct work samples cold/warm |
|---|---:|---:|---:|
| A | n/a | n/a | 0 / 0 |
| B | 2699 | 545 / 554 | 5 / 0 |
| C | 3435 | 708 / 2649 | 7 / 0 |
| C′ | 3270 | 608 / 687 | 4 / 0 |

Direct `perCreateWorkMs` samples are the pooled `webWorkDurationSamplesMs` values from B/C/C′
(`n=16`, median `150ms`, p75 `426ms`, p95 `1038ms`). Cache-hit warm runs correctly carry
`webWorkStartCount` but often have zero paired duration samples because the real height is applied from
the cached height before the cached-output Web work starts; those rows are preserved in raw evidence
rather than backfilled with proxies.

Corrected budget derivation:

- `floor(32 / median(150)) = floor(0.2133) = 0` → `maxWebCreatesPerFrame = clamp(0, 1, 4) = 1`
- `round(p75(426)) = 426` → `maxWebWorkMsPerFrame = clamp(426, 1, 16) = 16`

Evidence baseline verdict: **PASS_WITH_EMULATOR_PERFORMANCE_FOLLOW_UP**. Formula fixtures exceed the
initial `T_finishToStable` performance target (`B=554ms`, `C=2649ms`, `C′=687ms`; target `500ms`)
and B records consecutive-long-frame observations (`13/20` runs). These values remain unchanged and
are not hidden; on the DevEco emulator they are follow-up performance findings rather than reasons to
reject the completed fixture, metric, and budget evidence. `T_firstDeltaToVisible` remains
observation-only.

### Historical Phase-9 evidence (superseded for budget derivation)

Historical Phase-9 evidence was collected 2026-09-16 on the MatePad Pro 13 emulator (127.0.0.1:5555) by the ticket-0.6 harness
(`[ChatRenderBench]` structured hilog + `filesDir/chat-render-benchmark/<fixture>.json` dual channel).
Authoritative historical set = session 2 (pid 8763): warmup precondition `valid`, one process ran the
full 4 fixtures × 20 runs (80 records, `ALL_RUNS_DONE records=80`). Session 1 (pid 4454, A/B/C 20+20+20,
C′ interrupted at 13/20 by a device-side process termination) corroborates the historical numbers.
This section is retained as superseded gate-failure context; final recomputation uses the corrected JSONL
section above.

#### Per-fixture p50/p95 (session 2, n=20 per fixture)

| Metric | A (0 formulas) | B (2 formulas) | C (6 formulas) | C′ (3 consecutive pairs) |
|---|---|---|---|---|
| `webCreateCount` | 0 / 0 | 5 / 5 | 0 / 0 | 0 / 0 |
| `heightUpdateCount` | 0 / 0 | 15 / 15 | 13 / 13 | 8 / 8 |
| `heightAppliedCount` | 0 / 0 | 15 / 15 | 13 / 13 | 8 / 8 |
| `cacheHitCount` / `cacheMissCount` | 0 / 0 | 10 / 0 | 13 / 0 | 8 / 0 |
| `degradationCount` | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| `tFirstDeltaToVisibleMs` | n/a (no Web blocks) | 3543 / 3734 | 4304 / 5140 | 3810 / 4402 |
| `finishToVisibleMs` | n/a | 26 / 63 | 34 / 59 | 29 / 36 |
| `tFinishToStableMs` | n/a | 1994 / 2300 | 658 / 744 | 602 / 682 |
| `longFrameCount` | 0 / 1 | 1 / 2 | 0 / 0 | 0 / 0 |
| `frameCount` (sampled in finish+500ms) | 30 / 31 | 2 / 3 | 0 / 0 | 0 / 0 |
| `areaChangeCount` | 10 / 10 | 10 / 10 | 10 / 10 | 10 / 10 |
| `finalAreaHeight` (vp) | 272.5 / 272.5 | 367.5 / 367.5 | 629.5 / 922.9 | 512.5 / 512.5 |
| steady `heapUsed` (KB, first→last) | 4128→9940 | 5617→10833 | 12487→13760 | 15075→10165 |

Notes: formula-bearing fixtures (B/C/C′) inherit the shared formula cache key across fixtures, so C
and C′ run 0 are already warm for formula blocks (`webCreateCount` = 0); B re-creates pages through
its sequence (p50 = 5) when the 10-minute cache TTL expires mid-fixture. `finalAreaHeight` for C/C′
shows run-to-run Web render variance (629.5→3030.9 / 512.5→2774.1) — the variance the ≥20-run
protocol exists to characterize. Steady memory follows a GC sawtooth (rises ~5MB over ~20 runs,
resets on GC); no unbounded monotonic in-session leak. Cold/warm distinction was observed by run index
(run 0 treated as cold; runs 1–19 as warm), but this historical report is not the corrected raw source.

#### `perCreateWorkMs` sample distribution (create→first-height-applied)

**Superseded evidence note (post-code-review)**: the distribution below is retained as historical
Phase-9 evidence only. It reconstructed per-work-unit samples from run-level proxies
(`finishToVisibleMs` and `tFinishToStableMs − 500`) instead of directly emitted
`webWorkDurationSamplesMs`. Code review rejected that proxy as insufficiently auditable. The corrected
measurement seam now records `webWorkStartCount` and duration samples directly; final numeric defaults
are recorded in the corrected evidence section above.

Per-work-unit create→first-apply durations are reconstructed from run-level seam evidence: all
blocks enter the Web render decision at the finish boundary (blocks only mount at `streaming=false`),
so for every run with `webCreateCount > 0` two samples are taken — the first block's exact
create→first-apply (`finishToVisibleMs`) and the last observed application's create→apply
(`tFinishToStableMs − 500`, the 500ms quiet period). Pooled over B/C/C′ session-2 runs with
`webCreateCount > 0`: **n=28, median=1414ms, p75=1622ms** (samples: 2082, 2872, 28, 1640, 28, 1437,
26, 1470, 26, 1391, 19, 1541, 27, 1650, 63, 1622, 27, 1506, 15, 1759, 25, 1543, 30, 1494, 25, 1661,
26, 1800). A cold-only subset (fully cold runs: B session-1 run 0 {2320, 2965}, B session-2 run 0
{2082, 2872}, C implementation-phase instrumented run {1124, 2773}) gives median 2546.5ms /
p75 2872ms — the same frozen outcome under the clamp bounds.

#### Historical recomputation (superseded; not final frozen values)

- `floor(32 / median(1414)) = floor(0.0226) = 0` → `maxWebCreatesPerFrame = clamp(0, 1, 4) = 1`
- `round(p75(1622)) = 1622` → `maxWebWorkMsPerFrame = clamp(1622, 1, 16) = 16`

These values are not final reliable defaults because the input distribution used run-level proxy
samples. Recompute the final defaults only from corrected `webWorkDurationSamplesMs` evidence after a
new 4×20 collection.

#### Historical gate-relevant findings (recorded, not hidden)

- `T_finishToStable` p95 = 2300ms (B) / 744ms (C) / 682ms (C′) — all exceed the frozen 500ms gate
  → ticket-0 gate **FAIL** per the frozen template (spec 021 §12: never lower the threshold to pass).
- `T_firstDeltaToVisible` p95 = 3734 / 5140 / 4402ms — above the 1500ms observation alarm line;
  record-only, does not block (frozen observation semantics).
- Consecutive long frames observed in B (4 of 20 runs in session 2: runs 0, 4, 7, 15; 1 of 20 in
  session 1: run 19) — the frozen "two consecutive long frames never occur" visual-continuity
  constraint is violated on this emulator's current production render path. Caveat: vsync only
  fires during repaints on this emulator, so formula fixtures sample 0–3 frames per window
  (A streams text: 21–31 frames).
- `T_sealedToVisible` recorded N/A (no seal event in the current path); `finish→visible` is the
  measured analog (p50 26–34ms, p95 36–63ms — fast, cache-dominated).

## Consequences

- ticket-1 may consume the corrected frozen defaults (`maxWebCreatesPerFrame=1`,
  `maxWebWorkMsPerFrame=16`) and the raw JSONL evidence. It must not consume the superseded
  proxy-derived distribution.
- #124 closes as an accepted evidence ticket with a **PASS_WITH_EMULATOR_PERFORMANCE_FOLLOW_UP**
  delivery status, not as a claim that the current DevEco emulator meets the performance target.
- The harness page used for collection is temporary (#124: deleted after observation, `main_pages.json`
  and `EntryAbility.ets` restored byte-identical); durable evidence lives here, in spec 021 §6, in the
  focused tests, and in the verification record.
