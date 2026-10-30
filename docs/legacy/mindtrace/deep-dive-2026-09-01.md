# MindTrace Deep-Dive Audit — Largest Unread Files

> Generated 2026-09-01 by subagent
> Companion to docs/architecture-audit-full-20260901.md

Scope: 7 largest files referenced in the main audit but not opened during
the first pass. Total ≈ 5,496 LOC analyzed in full. Findings use the
existing audit's `§F<n>.<m>` numbering so they can be cross-referenced.

---

## File 1: ReviewGraphView.ets (1880 LOC)

### Responsibility
Top-level Review tab page. Switches between two "galaxy" visualisations
(universe of subject systems vs. inside a single subject), manages local
camera/zoom/rotation state, dispatches planet taps into the
NoteDetailOverlay, and concentrates **all** the per-shape positioning
math (orbits, planets, stars, nebulas, links) inside its own component
tree.

### LOC by responsibility
- Module-level constants, palette/hash helpers: ≈120 LOC (L21-123)
- `ReviewGraphView` controller (state + lifecycle + animation orchestration): ≈300 LOC (L125-519)
- `SubjectUniverseView` (overview of subject systems): ≈650 LOC (L521-1175)
- `SubjectGalaxyView` (drill-down into one subject, incl. orbit/planet/link math): ≈800 LOC (L1177-1879)
- Three shared `@Builder` primitives (`SolarPlanet`, `SolarStar`, `ZoomControls`): ≈100 LOC

This file is **two UI sub-systems glued together** with their own
preview-vs-detail state models that share 7 helper functions at file scope.

### Findings
- **[P0] God file / unmaintainable scope — §F1.1.** One `.ets` file holds
  three `@Component` structs, two coordinate-systems, two camera models,
  and ~120 LOC of pure helpers. A change to "overview planet sizing" can
  silently affect "detail planet sizing" because `SolarPlanet` is duplicated
  verbatim across `SubjectUniverseView` (L885-919) and `SubjectGalaxyView`
  (L1541-1580). Suggested split:
  `ReviewGraphView.ets` (controller only) + `SubjectUniverseView.ets` +
  `SubjectGalaxyView.ets` + `galaxy/` (shared primitives & math).
- **[P0] Duplicated `SolarPlanet` body — §F1.2.** L885-919 and L1541-1580
  implement the same six-variant planet renderer with **different** accent
  choices (variant 2, 3, 4 in overview; variants 1-5 in detail) and **different**
  positioning math (`overviewPlanetX`/`Y` vs. `planetX`/`Y`). The duplication
  is invisible to the type system; a fix to one variant will be missed in
  the other. Move to a single `@Builder SolarPlanet(...)` in a shared module.
- **[P0] `GalaxyMath` pseudo-module lacks seams — §F1.3.** All camera/zoom
  math (`clamp` L48, `pctText` L44, `stableHash` L85, `paletteColor` L95,
  `planetVariant`/`planetLabel` L104-123, plus `universeColumns`/`Rows`/
  `WorldWidth/Height` L63-83) is free-floating at file scope. There is
  no `export` — testing requires instantiating the components and rendering
  them. Group into `galaxy/GalaxyMath.ets` so unit tests can hit the math
  without UI.
- **[P0] Leaky abstraction: `KnowledgeGalaxyViewModel` is recreated by
  `@State` then mutated via `load(...)` — §F1.4.** L128 `vm: KnowledgeGalaxyViewModel = new KnowledgeGalaxyViewModel()` is a private-by-class-field but `@State`-tracked object. ArkUI re-renders fire when `@State` vm
  references change, but `vm.load()` only mutates the inner `systems[]`
  — none of which are themselves `@State` or `@Observed`. The page
  *appears* responsive only because `build()` reads `this.vm.systems.length`
  directly each pass; a memoised build would freeze.
  See L380-413 (`if (this.vm.systems.length === 0) …`). Either mark the
  VM's mutable arrays `@Observed` or expose a `Tick` counter `@State` and
  bump it on `load()`.
- **[P1] `Science` of L1218-1229 — planet z-order depends on sine of
  rotation — §F1.5.** `PlanetLayer(isBackLayer)` (L1401-1418) toggles
  based on `isPlanetBehindStar` (L1836-1839), which returns `Math.sin(radians) < 0`. Combined with the orbiting `setInterval` (L218-220), the
  layer switch happens ~25 times per rotation. With ~30+ planets and a
  `ForEach` keyed by name + suffix (L1412), this triggers massive
  re-renders. Hoist the layer classification outside the build OR cap
  the rotation step to a coarser grid.
- **[P1] No contract for `KnowledgeGalaxyViewModel.deleteNote` —
  §F1.6.** L282-297 calls `vm.deleteNote(getContext(this), id)` and trusts
  its `Promise<boolean>`, but the VM also internally re-`load()`s the
  whole galaxy (ViewModel L271), causing a double refresh:
  `deleteNote → reload → reloadGalaxy(true)` → another `vm.load` is fired
  from the `@StorageProp("notesVersion")` watcher (L151-153). Two full
  re-renders for one delete. Add a "skip reload" flag or split API into
  `deleteNote` + `fireAndRecompute`.
- **[P1] Magic-number physics — §F1.7.** `GALAXY_SIZE = 360` (L21),
  `MIN_ZOOM/MAX_ZOOM` separate from `UNIVERSE_MIN_ZOOM/MAX_ZOOM` (L40-41
  vs L29-31), orbit tilt `tilts` array (L740), `slotX[]/slotY[]` ring
  layout (L706-707) — all are pulled from nowhere and depend on the
  world stage size `360×520` (L23-24). Changing one constant will
  silently break the others. Move to `galaxy/GalaxyConstants.ets`.
- **[P2] `aboutToDisappear` may race with `setInterval` callback
  — §F1.8.** L147-149 / L223-228: `stopRotation()` clears the timer, but
  `setInterval` callback (L218-220) mutates `this.orbitOffset` after the
  component is GC'd in theory. In practice the timerId check prevents it,
  but the pattern is non-obvious. Prefer an explicit `dispose()` chain.
- **[P2] Mixed comment quality — §F1.9.** Top-of-file comment block
  (L1-20 region) is empty; section headers appear inconsistently;
  hard-coded hex colours (`"#16FFFFFF"` L480, `"#A004070D"` L620,
  `"#01000000"` L589) appearing 30+ times should be tokens (see `common`'s
  `GLASS_*`).

### Deep-module opportunities
Currently this file has **shallow depth**: the outer component knows
every coordinate system and every shape variant. Suggested split:

| New module | Interface (small) | Implementation (deep) |
|---|---|---|
| `galaxy/GalaxyMath.ets` | `worldSize(count): {w,h}`, `hashPlanetColor(id)`, `tiltForOrbit(i)`, `planetVariant(id)` | hash, palette, layout, ring/slot math |
| `galaxy/GalaxyConstants.ets` | tokens | `GALAXY_SIZE`, zoom ranges, tilts, slot table |
| `galaxy/SolarPlanet.ets` | `SolarPlanet({planet,size,alpha})` `Builder` only | the 6-variant bodies + positioning |
| `pages/Review/ReviewController.ets` | `state`, `onPlanet`, `onCamera` | selects between overview and detail view |
| `pages/Review/SubjectUniverseView.ets` | `@Prop systems, totalCount, avgMastery, zoom, camera, callbacks` | overview visuals only |
| `pages/Review/SubjectGalaxyView.ets` | `@Prop system, zoom, camera, callbacks` | detail visuals + links |

Then `ReviewGraphView` becomes ~150 LOC and `<100` lines in the build
method — a deep module that *only* knows how to wire the two views to the
VM.

### Cross-file dependencies
- **Imports from**: `common` (`BG_*`, `MINT`, `TEXT_*`, `KnowledgeUnit`,
  `NoteItem`), `@kit.ArkUI` (`promptAction`),
  `shared/components/AppIcon`,
  `overlays/NoteDetailOverlay/NoteDetailOverlay`,
  `viewmodels/KnowledgeGalaxyViewModel` (`KnowledgeGalaxyViewModel`,
  `PlanetNode`, `ChapterOrbit`, `SubjectSystem`, `GalaxyLink`),
  `utils/NoteItemMapper` (`unitToNoteItem`).
- **Imported by**: likely `pages/Review/ReviewPage.ets` (per audit
  mention).
- **VM coupling**: this file owns ~80% of the VM's rendering contract;
  the VM's `SubjectSystem`/`ChapterOrbit`/`PlanetNode` types are shaped
  by this file's needs.

---

## File 2: KnowledgeGalaxyViewModel.ets (789 LOC)

### Responsibility
`@Observed` view model that loads `KnowledgeUnit`s from the DB plus a
hard-coded 12-unit "preview" fixture, then derives:
`SubjectSystem → ChapterOrbit[] → PlanetNode[]` along with layout,
mastery stats, and prerequisite/related link extraction. Also exposes
`loadNote`, `deleteNote`.

### LOC by responsibility
- Domain models (`GalaxyLink`, `PlanetNode`, `ChapterOrbit`, `SubjectSystem`,
  `UnitBundle`): L54-204 (~150 LOC)
- DB I/O (`load`, `loadPersistedUnits`, `loadNote`, `deleteNote`): L214-276 (~60 LOC)
- `unitsToNotes` + `withPreviewUnits` (merging fixture data): L278-322 (~45 LOC)
- `previewUnits()` fixture data (12 hard-coded units with hand-authored
  prerequisites/related edges): L324-465 (~140 LOC)
- `buildSystems` / `buildChapterOrbits` / `buildPlanets` / `buildLinks`
  (main graph build): L467-682 (~220 LOC)
- Universe layout (slot positions, ring fallback, sorting): L694-742 (~50 LOC)
- Helpers (mastery math, count, hash, tilt): L758-789 (~30 LOC)

### Findings
- **[P0] Fixture data lives in production code — §F2.1.** L324-465 is a
  hard-coded 12-node "示例" (preview) galaxy with hand-curated
  `prerequisites`/`related` arrays spanning the `KnowledgeUnit` model.
  This is **sample data** masquerading as content. Production users will
  see it surface in their galaxy (see L286-297 unconditionally merges it).
  The flag `ENABLE_GALAXY_PREVIEW_UNITS` (L12) is `true` and `previewSubjectRank`
  (L527) actively promotes "示例：*" subjects to the **top** of the sort
  order (L516-522). This is at best demo-grade data shipped to end users.
  Move to `entry/src/main/resources/rawfile/galaxy_preview.json` and
  load at debug build only.
- **[P0] `withPreviewUnits` pollutes user state — §F2.2.** L286-297
  prefixes fixture IDs with `PREVIEW_UNIT_PREFIX = "galaxy_preview_"`
  and concatenates them into the result. `loadNote()` then has special
  casing (L308-318) to return the fixture instead of hitting the DB.
  `deleteNote()` (L265-267) similarly special-cases the prefix to refuse
  deletion. **Three code paths know about one magic string.**
  Replace with a port (`GalaxyDataSource` adapter) and inject fixtures
  in tests only.
- **[P0] God-`@Observed` — §F2.3.** `KnowledgeGalaxyViewModel` exposes five
  mutable arrays (`systems`, `units`, `notes`, …) plus counters, plus
  provides DB-write side effects (`deleteNote`). The `@Observed`
  decorator on the class does not help consumers because the consumer
  (`ReviewGraphView`) reads field access but is itself `@Component`
  without `vm` being a `@ObjectLink` or `@Observed` tracked reference
  (see §F1.4). The class is doing data loading + graph build + DB I/O +
  fixture management in one type. Split:
  `KnowledgeGalaxyRepository` (DB + fixture merge) →
  `GalaxyGraphBuilder` (pure graph build) →
  `KnowledgeGalaxyViewModel` (state surface only).
- **[P1] `buildChapterOrbits` then `reapplyOrbitLayout` (L573-588) —
  §F2.4.** The first call computes radii/tilts/label positions
  (L552-557), then `reapplyOrbitLayout` runs identical math after sorting
  (L572-574). The first pass's layout values are immediately overwritten.
  Pure dead work. Delete `buildChapterOrbits`'s in-loop radius/label code
  or move it entirely to `reapplyOrbitLayout`.
- **[P1] Graph-builder allocates GC pressure per build — §F2.5.** Each
  `load()` (L214-232) creates `~6 arrays × N subjects` (subjectBundles,
  chapterNames, chapterBundles, orbits, planets, links). Subjects/pages
  with hundreds of notes will rebuild the entire graph on every DB miss.
  Combined with `reviewGraphView`'s `loadNote` always calling
  `vm.load(...)` indirectly via the watcher, this is O(n²) on snapshot
  misses. Consider memoising by `version` token.
- **[P1] `private async loadPersistedUnits` always returns `[]` on error
  — §F2.6.** L234-242 swallows exceptions and returns empty, so a real DB
  failure is indistinguishable from "no notes". The caller (`load`)
  treats both as success and proceeds to call `buildSystems([])`, which
  results in an empty galaxy and a toast of "知识星系加载失败" in the UI
  (ReviewGraphView L158). Helpful, but the controller has no way to
  distinguish "empty" from "DB down". Return a discriminated result.
- **[P2] `UnitBundle` could be a tuple — §F2.7.** L192-204 declares a
  four-field class only used inside `buildSystems`/`buildChapterOrbits`/
  `buildPlanets`. Prefer a `Map<id, {unit,note,subject,chapter}>` or simply
  parallel arrays. Minor.
- **[P2] `applyUniverseLayout` uses hard-coded magic `360 × 520` stage
  dimensions — §F2.8.** L699-700: stage width/height are duplicated from
  `ReviewGraphView` L23-24. Not synced:  if the View changes stage size,
  layout will go off-screen. Pass a `stage: {width,height}` parameter.
- **[P2] Numeric methods (`pickup`) — §F2.9.** L553: `radiusX: number = Math.min(164, 92 + index * 26)` — different from `radiusY` formula (L554) and from the overview sizing in `ReviewGraphView` L1138-1144. Same conceptual "size as orbit index" is computed in three places with different constants.

### Deep-module opportunities
The desired deep module is:

```ts
interface GalaxyRepository {
  loadUnits(ctx): Promise<KnowledgeUnit[]>
  loadNote(ctx, id): Promise<KnowledgeUnit | null>
  deleteNote(ctx, id): Promise<boolean>
}

interface GalaxyGraphBuilder {
  build(units: KnowledgeUnit[]): { systems: SubjectSystem[], total: number, avg: number }
}

class KnowledgeGalaxyViewModel implements @Observed {
  systems: SubjectSystem[]
  totalCount: number
  avgMastery: number
  // thin — just holds state and delegates
}
```

The repository should have **two adapters in the codebase already**:
`PersistedGalaxyAdapter` (production, hits `NoteDao`) and
`PreviewGalaxyAdapter` (fixture, debug-only). One interface, two seams.

### Cross-file dependencies
- **Imports from**: `common` (`DatabaseHelper`, `KnowledgeUnit`,
  `NoteItem`, `ReviewStatus`, `DifficultyLevel`, `subjectColor`, `typeColor`),
  `database/NoteDao`, `utils/NoteItemMapper`.
- **Imported by**: `pages/Review/ReviewGraphView.ets` and `ReviewPage.ets`
  (per audit).
- **Imports nothing else from `entry`**: this means the VM is the
  highest-level node in its slice — good for testability were it not for
  the embedded fixture.

---

## File 3: AgentMemoryService.ets (570 LOC)

### Responsibility
A gateway service that:
1. Persists chat messages, pending OCR/note material, session summaries,
   and a "learner profile" (beginner/novice/advanced) into the relational
   store.
2. Builds context snapshots for AI reply, note generation, and learner
   prompt injection.
3. Calls `LlmGuard`/`LlmClient` to refresh the profile and to compress
   long sessions into rolling summaries.

### LOC by responsibility
- Public API (save / get / update): L35-226 (~190 LOC)
- DB plumbing (`getStore`, message/memory DAO creation):
  L228-234, plus ad-hoc `new ChatMessageDao`/`AgentMemoryDao` per call
  (~inline)
- Static text-builders (`buildContextText`, `formatMessages`,
  `buildSummarySource`, `buildLearnerProfileMessages`,
  `formatLearnerProfileContext`): L236-361 (~125 LOC)
- Profile parsing/validation (`parseLearnerProfile`, `validate…`,
  `parseLearnerProfileJson`, `extractJsonObject`, `mergeLearnerProfile`):
  L363-544 (~180 LOC)
- Small utilities (`clip`, `newId`, `errorMessage`,
  `levelLabel`, `normalizeConfidence`, `parseLearnerLevel`):
  L500-569 (~70 LOC)

### Findings
- **[P0] Hard-coded JSON-grammar in `LlmGuard` schema — §F3.1.** The
  `LlmGuard.callJsonWithRetry` validator at L370-394 requires a fixed
  shape: `{globalLevel, sessionLevel, confidence, evidence}`. Any change
  to the learner model requires editing the schema here **and** the system
  prompt (L329) **and** the merge rule (L431-459) **and** the context
  formatter (L342-361). Four call sites coupled to one schema. Extract a
  `LearnerProfileSchema` module that owns these together.
- **[P0] `extractJsonObject` regex strips fenced blocks — §F3.2.** L532-544:
  `trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/)` works for ```json
  fences, but the second-stage `source.match(/\{[\s\S]*\}/)` (L539-542)
  will **truncate at the first `}`**, breaking any nested objects. Many
  LLM outputs include nested structure (escaped string in `evidence`,
  arrays). Use a brace-balance walker. This is also exercised by the
  LlmGuard in production with no test coverage.
- **[P0] Unbounded retry on `LlmConfig.getInstance().isConfigured()` —
  §F3.3.** L144 / L189: `await LlmConfig.getInstance().isConfigured()`
  is called on every `updateLearnerProfileIfNeeded` and
  `summarizeSessionIfNeeded`. If `LlmConfig` is itself backed by RDB,
  this is a sync point per chat message. At minimum cache the result for
  the service lifetime.
- **[P1] `extractJsonObject`'s "loose match" is too loose — §F3.4.** L539
  uses non-greedy `/{[\s\S]*}/`. Given an LLM reply that includes both
  preamble text and a JSON body, this captures from the **first** `{`
  to the **last** `}`. A reply like `Some words { "ok": true } tail
  {more here}` would be parsed as `{"ok": true } tail {more here}` —
  likely to throw at `JSON.parse`, leading to silent profile drop (L425-428
  `console.warn` then `return null`). Test with adversarial LLM output.
- **[P1] `countUserMessagesAfter` is O(n) per profile update — §F3.5.**
  L486-498: scans the entire message history to count users. This runs
  on every chat turn (L139) until threshold met. With `RECENT_REPLY_LIMIT`
  already capped at 100 but `queryAll(sessionId)` (L138) returning the
  full set, a heavy session is O(n). Use `messageDao.queryRecentAfter(...)`.
- **[P1] `withSessionLevel` mutates "global" record inconsistently —
  §F3.6.** L167-171 inserts a **global** record whose `globalLevel` is
  the LLM-updated `globalLevel`, but the **sessionLevel** is forced to
  `updated.globalLevel` (L168). The next call will then read this
  hybrid back via `queryLatestProfile` (L137-138) and treat `updated.globalLevel`
  as if it were a session-level signal. Merge algorithm (L431-459) doesn't
  account for the asymmetry. The semantics of `globalLevel` after one
  update are unclear.
- **[P1] `RECENT_NOTE_LIMIT = 100` then context joined inline — §F3.7.**
  L114 fetches 100 recent messages; L295-310 `formatMessages` walks them
  all and `clip`s to `NOTE_CONTEXT_LIMIT` (32 KB). The unused tail is
  fetched for nothing. Trim at the DAO.
- **[P1] `markPendingMaterialUsed` ignored by the rest of the file —
  §F3.8.** L223-226 marks records as used but no caller queries
  `used` status; it's write-only. Likely intended to feed
  `queryPendingNotes` filtering (L113) but the filter is absent. Either
  delete the field from the schema or wire the filter.
- **[P2] `errorMessage(e)` falls back to `JSON.stringify(e)` (L563-569),
  which on a non-serialisable object will throw — §F3.9.** Wrap in try/catch
  or only stringify if `typeof JSON.stringify(e) === 'string'`.
- **[P2] `effectiveLevel` accepts empty `sessionLevel` but `parseLearnerLevel`
  rejects it — §F3.10.** L500-505: returns `globalLevel` when
  `sessionLevel.length === 0`. But validation (L507-515) only accepts the
  three enum values. So `sessionLevel` is **never** empty at runtime,
  making the empty-branch dead code; the defensive check is a maintenance
  trap.
- **[P2] `newId` uses `Math.random()` with `Date.now()` — §F3.11.** L559-561:
  collisions possible in tight loops (same ms × same 1e6 modulus),
  but more importantly the prefix-based "id" (`msg_...`, `mem_...`) is
  brittle. `uuid()` exists in `common` (see `NoteDetailOverlay` L406).
  Use it.

### Deep-module opportunities
```
LearnerProfileRepository   — load/merge/persist profiles
ConversationMemoryRepository — load/save messages, pending notes, summaries
ConversationContextBuilder — read repos, emit context strings
LearnerProfileSummarizer   — calls LlmGuard + writes profile records
ChatSummarizer             — calls LlmClient + writes summary records
AgentMemoryService (thin)  — facade that wires them
```

Each gets a separate interface surface, which makes the
schema-vs-prompt-vs-merge coupling (Finding §F3.1) explicit and testable.

### Cross-file dependencies
- **Imports from**: `@kit.ArkData` (`relationalStore`),
  `@kit.AbilityKit` (`common.UIAbilityContext`),
  `common` (`ClassificationResult`, `ChatMessage`, `DatabaseHelper`,
  `LlmClient`, `LlmConfig`, `LlmGuard`, `LlmGuardValidationResult`),
  `database/AgentMemoryDao`, `database/ChatMessageDao`,
  `models/AgentMemoryModels` (`AgentMemoryRecord`, `ChatMessageRecord`,
  `ChatRole`, `LearnerLevel`, `LearnerProfile`).
- **Imported by**: likely AI/dispatcher service in `agents/` HSP and
  some `pages/AI/*` callers. Not imported by this audit's read set.

---

## File 4: NoteDetailOverlay.ets (562 LOC)

### Responsibility
Full-screen overlay that displays a note's details, supports an in-place
edit form, validates tags/title/summary/content, persists changes via
`NoteDao`, invalidates caches, and surfaces delete/share affordances.
Also the single source of "save flow" for both new notes (`isCreating=true`)
and updates.

### LOC by responsibility
- `build()` layout + `@Builder LoadingState`/`DiscardConfirm`: L64-271 (~210 LOC)
- Edit lifecycle (`startEdit`/`cancelEdit`/`closeOrCancel`/`saveEdit`):
  L300-402 (~100 LOC)
- Unit construction (`buildManualUnit`, `buildUpdatedUnit`, subject/category
  resolution): L404-499 (~95 LOC)
- Helpers (`parseTags`, `captureInitialSnapshot`, `hasUnsavedChanges`,
  `bumpNotesVersion`, `invalidateSavedRenderCaches`, `effectiveUnit`,
  `canRenderReadOnlyDetail`, etc.): L275-557 (~120 LOC)
- `mockShare` stub: L555-557 (~3 LOC)

### Findings
- **[P0] `mockShare` shipped in production — §F4.1.** L555-557:
  ```
  private mockShare = (): void => {
    promptAction.showToast({ message: '分享功能暂未开放', duration: 1500 })
  }
  ```
  Either implement or gate by `if (DEBUG)` and route to a real provider.
  Same stub appears as an `onShare` callback wiring at L166 — TODO debt
  that's easy to forget.
- **[P0] Save flow mixes read-modify-write with cache invalidation —
  §F4.2.** L359-402 `saveEdit`:
  1. Calls `DatabaseHelper.init(getContext(this))`
  2. Builds `KnowledgeUnit`
  3. Persists via DAO
  4. Invalidates three caches (`UiDataCacheService.invalidateNote`,
     `invalidateDetailRender`, `invalidateMarkdownText` × 2)
  5. Bumps `AppStorage("notesVersion")`
  6. Calls `onSaved(saved)` callback
  7. Sets `localUnit = saved` and clears `isEditing`

  Each step is correct in isolation, but the layering — VM-equivalent
  logic in a UI overlay — means future flows (e.g. save from a modal
  keyboard) will reimplement the same dance. Extract to a
  `NotesEditCoordinator` that owns the persistence + cache invalidation
  boundary.
- **[P1] All five `@Watch('onDetailInputChanged')` `note`/`unit`/`units`/
  `isCreating` props — §F4.3.** L35-38: any prop change fires the same
  watcher, which then has to inspect the actual relevant diff
  (`onDetailInputChanged` L284-288). With four `@State titleText/summary/...`
  fields (L42-45) only one of which is meaningful, every rebuild re-runs
  the watcher. Narrow the watches to the props each actually affects.
- **[P1] `parseTags` has six delimiter patterns but no fuzziness — §F4.4.**
  L501-518: separates on `[,\uFF0C\u3001;\uFF1B]` plus whitespace. Misses
  `、` (full-width comma) — wait, that IS covered. Misses `|` and `｜`.
  Also doesn't trim bracket wrapping (`[tag]`). Either document or
  consolidate into `common.normalizeTags`.
- **[P1] `resolveExistingCategory` then `resolveManualCategory` chain —
  §F4.5.** L493-499: the fallback chain is opaque. A user with a saved
  note whose category was migrated out of the `normalizeNoteType` enum
  falls into `resolveManualCategory` and re-derives from tags. Trace the
  call: `category: '概念'` stored as `category: ''` ⇒ re-derives ⇒ '概念'.
  Worth writing down somewhere — currently only inferred from code.
- **[P1] `parseTags` and `resolveCategory` both enumerate tags —
  §F4.6.** L501-518 and L470-483: tag parsing runs twice per save. Move
  to a shared util.
- **[P2] `@Builder DiscardConfirm` lives inside the overlay — §F4.7.**
  L208-271: 60+ LOC of nested layout. Reusable as a generic
  `ConfirmSheet` component if extracted.
- **[P2] `bumpNotesVersion()` reads/writes `AppStorage` directly — §F4.8.**
  L534-537: bypasses any wrapper. Combined with `ReviewGraphView`'s
  identical bump (L291-292), version state is **two writers**. Wrap
  behind `NotesVersionBump.bump()` in `common`.
- **[P2] `tag.text === SOURCE_CAMERA`-style constants live in
  `DetailRenderModel.ets` — §F4.9.** `SOURCE_CAMERA` is exported as a
  module-level string in a peer file (DetailRenderModel L46), then
  implicitly cross-referenced here. Friction: changing the constant
  cascades to two files. Move to `common/note.constants.ts`.

### Deep-module opportunities
```
NoteEditController          — owns edit lifecycle (start/cancel/save)
                               interface: {startEdit(unit), saveEdit(form)}
                                 returns Promise<KnowledgeUnit | Error>
NoteDetailOverlay           — pure UI shell (props + callbacks)
                               no @State for dirty tracking, no DAO calls
NoteActionBar / NoteEditForm / NoteDetailMeta — already extracted
```

The deep module is `NoteEditController` — its interface is "give me a
form snapshot, get a unit back (or an error); I'll handle the rest."
Covered by unit tests, the overlay becomes 200 LOC of layout only.

### Cross-file dependencies
- **Imports from**: `common`, `@kit.ArkUI` (`promptAction`),
  `database/NoteDao`, peer components
  (`./NoteCloseButton`, `./NoteDetailMeta`, `./NoteDetailBody`,
  `./NoteActionBar`, `./NoteIconButton`, `./NoteEditForm`),
  `services/UiDataCacheService`,
  `./model/DetailRenderCache` (`invalidateDetailRender`),
  `utils/MarkdownParseCache` (`invalidateMarkdownText`).
- **Imported by**: `pages/Review/ReviewGraphView.ets` (L420-427),
  likely `pages/Notes/*` list views.

---

## File 5: MathTextRenderer.ets (536 LOC)

### Responsibility
A wrapper around a WebView that loads a KaTeX-rendering HTML page and
calls its `renderForCache` / `renderFormula` JS to render LaTeX-bearing
markdown or display formulas. Owns the **render cache** (LRU with TTL),
estimate-height calc, deferred render queue for `note` profile, plain
text fallback, and two-stage fallback when bridge calls overflow.

### LOC by responsibility
- Module constants and pure cache functions (`cacheGet`, `cacheSet`,
  `cacheRemove`, `trim*`, `removeOldestCacheEntry`, `cacheTotalSize`,
  `contentHash`): L44-179 (~140 LOC)
- Component class declaration + `@State` fields: L181-204 (~25 LOC)
- `aboutToAppear` / `aboutToDisappear` / `onTextChanged` (entry points): L206-270 (~65 LOC)
- `renderContent` / `applyCachedRender` / `parseRenderedHeight` /
  `parseRenderPayload` / `unwrapJavaScriptString` (JS bridge): L272-403 (~130 LOC)
- `cacheKey` / `currentCacheKey` / `clampHeight` / `normalizeForRender` /
  `prepareMarkdownFromResult` / `plainFallbackText` /
  `shouldDeferWebRender` / `scheduleDeferredWebRender` /
  `estimateHeight`: L405-503 (~100 LOC)
- `build()`: L505-535 (~30 LOC)

### Findings
- **[P0] Module-scoped mutable cache shared across instances — §F5.1.**
  L44-56: `MATH_RENDER_CACHE: MathRenderCacheEntry[]` and
  `mathRenderCacheClock: number` are file-level globals. Every instance
  of `MathTextRenderer` (chat list rows + note body + formula card)
  shares one cache. In a list of 100 notes each rendering 5 formulas,
  one eviction displaces the other's. The shared eviction is fine but
  the TTL (10 min, L48) means a returned-to-after-30s cold render still
  stays — good — but the LRU clock (`mathRenderCacheClock`, L56, +1 per
  access, L60) **never resets**. After one hour it's at ~4000, still
  Number, fine. The real issue: the `MATH_RENDER_CACHE_KEY_VERSION = 'v2'`
  (L47) means a deploy that changes the KaTeX page contract forces a
  re-render of every entry, **but the code has no upgrade path** — old
  entries stay until TTL expires. Document or increment on init.
- **[P0] Render-cache and notes-page cache overlap — §F5.2.** L218-225
  vs `MathTextRenderer`'s own cache: the note page's renderer has its own
  dedupe (`MATH_RENDER_CACHE`) that's **separate** from the
  `NoteDetailOverlay`'s `invalidateMarkdownText` path
  (`utils/MarkdownParseCache` imported in `NoteDetailOverlay` L31). Two
  caches for markdown→HTML rendering. Merging is dangerous (different
  keys) but the existence of two implies the abstract contract — "render
  markdown to a fixed height" — has at least three adapters (one in
  `MathTextRenderer`, one in `MarkdownParseCache`, one in Detail body).
  Audit which is canonical and deprecate the others.
- **[P0] Two-stage fallback chain without timeout — §F5.3.** L288-333
  and L336-371: `renderContent` tries `renderForCache` first; on reject
  (bridge value too large) it falls back to `render()`. On reject
  of cached-apply, it retries `renderForCache` with **original text**
  (not key). Each call awaits a `Promise` from the controller. If the
  controller never resolves (webview hang), the user's await never
  settles and `webFailed` stays false. No timeout. Add `Promise.race`
  with a 5-second timeout that sets `webFailed = true`.
- **[P1] `renderSeq` ordering is correct but the contract is implicit
  — §F5.4.** L207-208, L237-239, L471-479: every entry point and every
  async callback captures `seq` to compare against `this.renderSeq`. If
  a `setTimeout` from `scheduleDeferredWebRender` fires after the user
  has moved on, the seq-mismatch returns early — fine. But the
  `applyCachedRender` chain (L336-371) uses `cacheKey` instead. Two
  concurrency tokens (`renderSeq` and `lastAppliedKey`) coexist. Pick
  one.
- **[P1] `shouldDeferWebRender` only checks `profile === 'note'` —
  §F5.5.** L465-467: all `note` profile renders go through the deferred
  queue. This means a single `note` instance steals the WebView slot
  from any subsequent renders for up to `DEFER_BASE_MS + DEFER_SLOTS *
  DEFER_STEP_MS` = 24 + 8×22 = 200 ms. There's no priority queue, so a
  chat message arriving during that 200 ms gets a `cache miss + fail`,
  forcing extra KaTeX work. Use a higher-priority pre-empt for `chat`.
- **[P1] Height estimation uses static line-width formulas — §F5.6.**
  L482-503 `estimateHeight`: assumes 24 chars/line for `note`,
  20 for chat; no actual width measurement. If the device is in 2×
  density or 1.5× font, the estimate drifts. Drift = scrollbar popping
  in late, then settling. Use `onAppear` measurement as a feedback
  signal.
- **[P1] `shouldDeferWebRender` returns boolean based on profile, but
  only `note` defers — §F5.7.** L465-467. Easy to extend to other
  profiles later; consider parameterising.
- **[P2] Hard-coded constants inside estimateHeight — §F5.8.** L494-496:
  `'\n$$'` and `'\\['` for display-formula counting double-counts `$$…$$`
  pairs (`split('$$').length - 1` is even ⇒ `/ 2`). Off-by-one risk if a
  stray `$$` in a paragraph appears; minor.
- **[P2] `@State private` modifier — §F5.9.** L200-203 declares all
  internal flags as `@State private`. The `private` keyword is not part
  of ArkTS Decorators in 1.1; consider `@State` alone for consistency
  with the rest of the codebase.
- **[P2] `cacheGet` uses `Date.now()` and `trimCacheIfNeeded`, but
  `MATH_RENDER_CACHE_TTL_MS` only enforced passively — §F5.10.** L118-123.
  `dropExpiredCacheEntries` is called inside `trimCacheIfNeeded` and
  inside `cacheSet`. A read-only stream (`cacheGet`) does **not**
  trigger expiry drop, so an idle cache can hold expired entries
  indefinitely (until next set). Less bad because reads are cheap,
  but write `dropExpiredCacheEntries` at the top of `cacheGet` too.

### Deep-module opportunities
```
MathRenderContract          — interface { render(text, profile): Promise<RenderResult> }
KaTeXWebRenderer            — current WebView impl + bridge fallback
MathRenderCache             — extract from L44-179 into its own file
RenderHeightEstimator       — extract from L482-503
MathTextRenderer            — @Component wrapping a contract; defensive UI only
```

The biggest depth win: hide the cache + bridge-fallback chain behind a
two-method contract (`render` + `heightFor`). Then 50 of today's 130 LOC
in this file become private to the cache module and can be unit-tested.

### Cross-file dependencies
- **Imports from**: `common` (`TEXT*`, `GLASS_10`, `BORDER`, `F_BASE`,
  `LatexRiskNormalizer`, `ContentProtocol`, `ContentValidationResult`,
  `LatexRiskResult`), `@ohos.web.webview` (controller + `Web`),
  `utils/UiCacheDebug` (`uiCacheLog`).
- **Imported by**: `overlays/NoteDetailOverlay/NoteDetailBody.ets` and
  chat UI rows (per audit's notes about KaTeX usage).

---

## File 6: UiDataCacheService.ets (511 LOC)

### Responsibility
A static, module-wide cache that memoises:
- the whole `KnowledgeUnit[]` list (notesSnapshot, keyed by `notesVersion`)
- per-subject groups (subjectGroupsSnapshot)
- per-note `KnowledgeUnit` details (detailEntries, keyed by id+version+updatedAt)
- study-plan snapshot (StudyPlanItem[])

Plus a `PreloadQueue` that drains tasks one-at-a-time with a 360 ms gap.

### LOC by responsibility
- Snapshot data classes (`NotesSnapshot`, `SubjectGroupsSnapshot`,
  `StudyPlanSnapshot`, `SubjectGroup`, `DetailCacheEntry`,
  `PreloadTask`, `DetailLoadingEntry`): L24-108 (~85 LOC)
- `UiDataCacheService` static state + accessors: L114-226 (~115 LOC)
- `buildSubjectGroups` (pure transform): L228-265 (~40 LOC)
- `loadNotesSnapshot` / `loadDetail` / `loadStudyPlanSnapshot` (loaders
  with promise-coalescing): L267-357 (~90 LOC)
- LRU + size-based eviction for `detailEntries`:
  L359-423 (~65 LOC)
- `PreloadQueueService` (single-worker queue): L445-497 (~50 LOC)
- `PreloadQueue` facade: L501-510 (~10 LOC)
- Pure helpers (`sortByDateDesc`, `sortGroups`, `resolveSubject`):
  L425-441 (~15 LOC)

### Findings
- **[P0] Static mutable state outside the class — §F6.1.** L115-124
  (`private static` fields) plus L499 `const UI_PRELOAD_QUEUE: PreloadQueueService`.
  Two distinct kinds of stateful singletons in one .ets file. Static
  fields in ArkUI persist across page lifetimes but are **not** reset
  on hot-reload → bugs found during DevEco HMR will go stale. There is
  no `_resetForTests()` hook. Add a `UiDataCacheService.resetForTests()`.
- **[P0] Promise-coalescing has subtle bugs — §F6.2.** L267-285
  (`loadNotesSnapshot`):
  ```
  if (UiDataCacheService.notesLoadingPromise !== null
      && UiDataCacheService.notesLoadingVersion === version) {
    return UiDataCacheService.notesLoadingPromise
  }
  UiDataCacheService.notesLoadingVersion = version
  const promise: Promise<NotesSnapshot> = UiDataCacheService.queryNotesSnapshot(...)
  UiDataCacheService.notesLoadingPromise = promise
  try {
    return await promise
  } finally {
    UiDataCacheService.notesLoadingPromise = null
    UiDataCacheService.notesLoadingVersion = -1
  }
  ```
  Pattern is correct in isolation. **Issue**: between line L278 and the
  actual `await DatabaseHelper.init`, two callers could synchronously
  call `loadNotesSnapshot(version)`, see `notesLoadingPromise === null`,
  start a second `queryNotesSnapshot`, and now two DB queries run.
  The check should set `notesLoadingPromise = promise` *before* any await.
  Same pattern in `loadDetail` (L293-310) and `loadStudyPlanSnapshot`
  (L335-351).
- **[P0] `setStudyPlanSnapshot` mints a new snapshot at the **same**
  version — §F6.3.** L215-220: stores at `UiDataCacheService.studyPlanVersion`,
  which is **not bumped** here. So `setStudyPlanSnapshot([...items])` is
  idempotent: subsequent `getStudyPlanSnapshot()` returns the new
  snapshot at the **same** version. If a caller calls
  `bumpStudyPlanVersion()` (L222-226) followed by `set…`, the version
  is current. But the order is essential and undocumented. Add a
  `setStudyPlanSnapshot(version, items)` signature and require callers
  to bump explicitly.
- **[P1] `detailKey` includes `updatedAt` and `version` — §F6.4.**
  L369-371. The cache therefore stores **distinct** entries for the
  same note across edits. The `getDetailById`/`setDetail` pair looks
  for `id + "|...|" + version` (L170-181), so by the time the client
  asks for `version=v+1`, the old `v` is still in cache. Effective
  behaviour OK, but `UI_DETAIL_LIMIT = 8` quickly cycles because each
  note edit knocks out the old `v`. Combine `updatedAt`-aware cache
  with explicit `invalidateNote(id)` (which is what we see in
  `NoteDetailOverlay.saveEdit` L541).
- **[P1] `invalidateNote(id)` also nukes `notesSnapshot` — §F6.5.**
  L200-203: invalidating a single note drops the entire list snapshot.
  For every save, the next `loadNotesSnapshot(version+1)` will miss
  the list cache. With CRUD-heavy sessions this is a guaranteed miss
  path. Consider invalidating the list only if the changed record
  affected subject grouping.
- **[P1] Preload queue keys are scoped incorrectly — §F6.6.** L450-458
  `enqueue`:
  ```
  if (this.queuedKeys.indexOf(key) >= 0) { return }
  this.queuedKeys.push(key)
  ...
  ```
  But a task's `key` is "notes\|version" (L504); two enqueues at the
  same version skip the second — good. However, the same key being
  enqueued right after `removeQueuedKey` (L478) is allowed back in,
  even if the underlying data hasn't changed. Risk: thrash between
  enqueue+enqueue+enqueue cycles when `notesVersion` bumps 5 times in
  a second. Consider a minimum re-enqueue interval.
- **[P1] `subjectColor()` re-evaluated per `buildSubjectGroups` call —
  §F6.7.** L256: deterministic by index, but called inside a loop and
  re-run on every miss. Memoise by `(subject, index)` for free if
  desired.
- **[P1] `NotesSnapshot`/`SubjectGroupsSnapshot` are version-keyed but
  `StudyPlanSnapshot` is not — §F6.8.** L62-70 vs L52-60: study plan
  exposes a separate `bumpStudyPlanVersion()` (L222). Inconsistency:
  notes use `AppStorage("notesVersion")` as the version, study plan
  uses a private static field. Pick one source of truth. (`AgentMemoryService`
  has a third — `now`-based timestamps in record IDs.)
- **[P2] Multiple `uiCacheLog("[UiDataCache] ...")` strings — §F6.9.**
  L136, L139, L146, L158, L161, L167, L175, L179, L208, L211, L218, L225,
  L273, L300, L341, L414, L452, L469, L472. ~20 hard-coded tags. Use
  a constant or a tagged logger to enable filtering per-build.
- **[P2] `sortByDateDesc` calls `new Date(b.date).getTime()` per
  comparison — §F6.10.** L432-434: `new Date(string)` parses a Date
  string each comparison. For 100s of notes in `sortByDateDesc`, that's
  hundreds of parses. Parse once and cache.

### Deep-module opportunities
```
UiCacheContract             — interface { get<T>(key), set<T>(key,val), invalidatePrefix(...) }
LruCacheAdapter             — current detailEntries machinery
VersionedCacheAdapter       — version-tagged snapshot machinery
PreloadQueueContract        — interface { enqueue(key, task), isBusy }
UiDataCacheService          — facade, key map, no eviction rules
```

The current class jams four concerns into one. Splitting the eviction
strategy (`LruCacheAdapter` vs `NotesSnapshot`-by-version) makes the
hot/miss behaviour testable in isolation.

### Cross-file dependencies
- **Imports from**: `common` (`DatabaseHelper`, `KnowledgeUnit`,
  `NoteItem`, `StudyPlanItem`, `subjectColor`), `database/NoteDao`,
  `database/StudyPlanDao`, `utils/NoteItemMapper` (`unitsToNoteItems`),
  `utils/UiCacheDebug`.
- **Imported by**: `NoteDetailOverlay.ets` (L29, L394, L541),
  most page-level VMs (per audit's `lazy-import` pattern).

---

## File 7: DetailRenderModel.ets (491 LOC)

### Responsibility
Pure transforms that turn `(NoteItem, KnowledgeUnit, [KnowledgeUnit])`
into a read-only `DetailRenderModel` for the six detail-page
sub-renderers. Includes a heavy section-title normaliser (Chinese +
English synonyms → stable English keys), category normaliser, and
section-text helpers (`findSection`, `sectionTextByKeys`,
`unmatchedSectionText`, etc.).

### LOC by responsibility
- Types (`DetailSectionData`, `DetailRenderModel`) + `EXTRA_SECTION_TITLE`
  const: L24-47 (~20 LOC)
- Public API (`buildDetailRenderModel`, `findSection`, `sectionText`,
  `sectionTextByKeys`, `hasAnySectionKey`, `unmatchedSectionText`,
  `originalSectionText`, `fallbackMainText`, `hasDetailMeta`,
  `splitReadableLines`, `firstAvailableSectionText`,
  `hasAnySectionText`): L49-187 (~140 LOC)
- `normalizeSectionKeys` / `appendUniqueText` (helpers): L189-205 (~15 LOC)
- `parseDetailSections` (markdown `## title` parser): L207-285 (~80 LOC)
- `normalizeSectionTitle` (the giant synonym table): L254-286 (~30 LOC)
- `normalizeKnownSectionTitle` (alias map with `containsAnyTitle`
  substring matches): L288-320 (~30 LOC)
- `trimSectionTitleDecorations` / `containsAnyTitle` (low-level helpers):
  L322-338 (~15 LOC)
- Field resolvers (`resolveBody`, `resolveCategory`, `resolveSubject`,
  `resolveTags`, `resolveKnowledgeRefs`, `resolveSource`,
  `resolveReviewLine`, `reviewStatusText`, `difficultyText`,
  `formatDate`): L340-480 (~140 LOC)
- `contentHash` (djb2): L482-491 (~10 LOC)

### Findings
- **[P0] Synonym list is duplicated — §F7.1.** L263-283 (in
  `normalizeSectionTitle`'s if/else chain) and L291-318 (in
  `normalizeKnownSectionTitle`, via `containsAnyTitle`). The first lists
  canonical aliases directly with `text === 'X' || text === 'Y'`.
  The second does substring matching on `text.indexOf(...)`. Result:
  a Chinese reader-friendly title `'## 推 导 过 程'` is treated
  differently by the two paths. L259-262 prefers the substring path
  first (`normalizeKnownSectionTitle`), so the if/else chain at L263+ is
  **dead code**. Delete L263-283 entirely.
- **[P0] `parseDetailSections` re-parses entire body on every render
  — §F7.2.** L207-233 is called once per `buildDetailRenderModel`,
  which happens on every prop change in the parent overlay (see §F4.3).
  For a 5 KB note body, that's a full regex + split per UI redraw. Wrap
  the parse in a memo with key = content hash (L482-491 already
  computes one — used only for the `key` field, not caching).
- **[P0] `containsAnyTitle` substring-matches are order-dependent —
  §F7.3.** L291-292 vs L296: `'parameters'` candidate appears in **both**
  sections of the if-chain. With substring matching (`text.indexOf('parameters') >= 0`),
  `"## parameters"` returns `'parameters'` on the first hit (good),
  but `"## parameter"` also returns `'parameters'` (also good). However,
  `"## rango"` (no such word) — fine. The issue is `containsAnyTitle`'s
  first-match-wins policy: changes to the alias table reshuffle
  priorities silently. Convert to a `Map<canonicalKey, predicates[]>`.
- **[P1] `cleanListPrefix` strips `1. `, `2. `, … but with ASCII `.` only —
  §F7.4.** L347-369: `dotIndex = text.indexOf('. ')` then `Number(prefix)`.
  Chinese numbered list `\uFF11\u3001` is not handled. Same omission as
  NoteDetailOverlay's `parseTags` (Finding §F4.4). Centralise.
- **[P1] `filterTags` silently drops `SOURCE_CAMERA` — §F7.5.** L390-406:
  ```
  if (tag.length === 0 || tag === SOURCE_CAMERA) { continue }
  ```
  `SOURCE_CAMERA = 'camera_capture'` (L46) is a hard-coded tag value.
  Anything else resembling an internal tag (`'ocr_text'`, `'src_internal'`)
  bleeds through. Centralise the internal-tag list in `common`.
- **[P1] `resolveKnowledgeRefs` is O(refs × units) — §F7.6.** L419-428:
  for each `prerequisites[i]`/`related[i]`, walk the entire `units[]` and
  `units.find(...)` (L435) walks linearly. For 10 refs × 200 units this
  is 2000 comparisons, every render. Pre-index `units` by `id` in a
  `Map<string, KnowledgeUnit>` before the merge.
- **[P1] `resolveReviewLine` mixes days/repetitions/date — §F7.7.**
  L444-458: concatenates `intervalDays`, `repetitions`, `nextReviewAt` into
  one human string. Hard to test because it embeds localisation. Consider
  returning `{interval: number, repetitions: number, nextReview: Date}`
  and let the UI format.
- **[P1] `formatDate` uses local `getMonth()`/`getDate()` — §F7.8.**
  L475-480: `d.getMonth() + 1` and `d.getDate()` return device-local
  values. Across timezones the displayed date can drift from the
  storage UTC. Either store in user's local TZ at write-time or
  format from `getUTC*`.
- **[P2] `normalizeDetailCategory` aliases `'概念'`, `'定理'`, `'公式'`,
  `'证明题'`, `'计算题'`, `'其它'` — §F7.9.** L408-417. This is **the**
  taxonomy for note types. Currently embedded in a renderer-side
  helper; move to `common/note.categories.ts` so the AI classifier,
  the storage layer, and the renderer all share it. The `normalizeNoteType`
  from `common` (L21) already implies this; consolidate.
- **[P2] `hasDetailMeta` returns `true` if only `originalSectionText()`
  has content — §F7.10.** L151-158: if the original OCR text exists but
  no tags/prereqs/source/review, `hasDetailMeta` is `true`. Not wrong,
  but the name promises "tags etc." → misleading. Split into `hasOriginal`
  and `hasTertiaryMeta`.
- **[P2] `containsAnyTitle` returns on `length > 0 && indexOf >= 0` —
  §F7.11.** L331-338: empty-string candidate trivially has
  `indexOf('') === 0` ⇒ returns true. Currently `normaliseKnownSectionTitle`
  filters empties at the call site, but the helper itself is unsafe;
  document or guard.

### Deep-module opportunities
```
SectionNormalizer           — synonym table + canonical keys
MarkdownSectionParser       — parseDetailSections
NoteCategoryNormalizer      — moved from this file to common
KnowledgeUnitResolver       — resolveKnowledgeRefs, resolveTags, resolveSource
ReviewStateFormatter        — resolveReviewLine, reviewStatusText, difficultyText
DetailRenderBuilder         — composes the above; pure function
```

Each of the five is a candidate for unit testing; today the entire
module is opaque (pure functions mixed with constant tables).

### Cross-file dependencies
- **Imports from**: `common` (`DifficultyLevel`, `KnowledgeUnit`,
  `NoteItem`, `ReviewStatus`, `normalizeNoteType`).
- **Imported by**: `overlays/NoteDetailOverlay/NoteDetailMeta.ets`,
  `overlays/NoteDetailOverlay/NoteDetailBody.ets`, and indirectly the
  other five `Note*` renderer files in the same directory.

---

## Cross-file patterns observed across all 7

| Pattern | Affected files | Severity |
|---|---|---|
| **AppStorage write/read scatters** | `ReviewGraphView` (`notesVersion` ++ L291-292), `NoteDetailOverlay` (`bumpNotesVersion` L534-537), `UiDataCacheService.currentNotesVersion` (L126-128) | P1 — three writers, no central bus |
| **Cache invalidation performed at UI layer** | `NoteDetailOverlay.saveEdit` invalidates 3 caches; `MathTextRenderer` has its own LRU; `UiDataCacheService` has another | P0 — three cache layers, no canonical contract |
| **`@State` mutable models accessed as @Component fields** | `ReviewGraphView.vm` (L128), local VMs that store arrays | P0 — silently not re-rendered under state mutations |
| **Production fixture data shipped** | `KnowledgeGalaxyViewModel.previewUnits` L324-465 (140 LOC) | P0 — users see "示例：数学分析" subjects |
| **Synonym/alias tables inline** | `DetailRenderModel.normalizeKnownSectionTitle` L288-320; `NoteDetailOverlay.parseTags` L501-518 | P1 — two normalisers overlap |
| **Magic numbers / constants without tokens** | `ReviewGraphView`'s stage sizes, `MathTextRenderer`'s profile-dependent line widths, `KnowledgeGalaxyViewModel`'s slot table | P1 — change one, break the others |
| **Hard-coded UI strings (CN)** | "暂未开放" (mockShare), "暂时未开放" pattern | P2 — i18n debt |

## Top 5 actionable items (ranked)

1. **Split `ReviewGraphView.ets`** into controller + 2 view modules + shared
   `galaxy/` primitives (§F1.1, §F1.2, §F1.3). Highest leverage — file is
   1880 LOC and the duplication is invisible to types.
2. **Move `KnowledgeGalaxyViewModel.previewUnits` (L324-465) out of the
   production bundle** (§F2.1, §F2.2). Either delete it or load it from
   `rawfile/galaxy_preview.json` only in `DEBUG`. Currently users see
   fake subjects promoted to the top.
3. **Extract a `LrnProfile`/`ConversationMemory` split from
   `AgentMemoryService`** (§F3.1, §F3.2). Single biggest fix:
   `extractJsonObject` non-greedy regex is a real correctness bug
   for nested JSON.
4. **Centralise cache invalidation** behind a `NotesVersionBus` (§F1.4,
   §F4.2, §F6.5). Today three writers for `AppStorage("notesVersion")`,
   two caches for markdown render, three eviction policies. One seam.
5. **Promote `@Observed` correctly on the VM** (§F1.4, §F2.3).
   `ReviewGraphView.vm.systems` mutations aren't seen by the build because
   the array isn't tracked. Either `vm = new …` per cycle (UI cost) or
   `@ObjectLink` on the inner arrays.

---

End of audit deep-dive.
