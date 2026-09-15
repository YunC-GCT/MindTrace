# Verification Record: Ticket 0.3 Chat filesDir Context Seam

**Ticket:** #121 / Ticket 0.3
**Feature directory:** `spec/ticket-0-3-chat-filesdir-seam/`
**Verification scope:** `build+ui`
**Implementation date:** 2026-09-15
**Overall gate status:** PASS
**UI verification result marker:** `<!-- ui_verification_result: PASS -->`

## Phase 1 setup evidence

### Branch and pre-existing dirty inventory

- Current branch: `feature/spec-019-p0`.
- Pre-existing unrelated dirty work observed before #121 implementation (untouched by this ticket):

  ```text
  M CONTEXT.md
  M docs/adr/0015-structured-stream-events.md
  M docs/agents/qwen-deepseek-reasoning-handoff-2026-09-12.md
  M docs/research/index.md
  M docs/specs/019-reasoning-process-display-p0.md
  M docs/specs/index.md
  M spec/019-reasoning-process-display-p0/delivery-checklist.md
  M spec/019-reasoning-process-display-p0/plan.md
  M spec/019-reasoning-process-display-p0/review-report.md
  M spec/019-reasoning-process-display-p0/spec.md
  M spec/019-reasoning-process-display-p0/tasks.md
  M spec/019-reasoning-process-display-p0/verification-report.md
  ?? agents/.preview/
  ?? common/.preview/
  ?? docs/research/arkweb-render-pipeline-stability-2026-09-11.md
  ?? docs/research/chat-markdown-latex-render-jank-2026-09-13.md
  ?? docs/specs/021-chat-streaming-incremental-rendering.md
  ?? entry/src/main/ets/shared/atoms/WebKeepAlive.ets
  ```

- #121 scoped files for this implementation pass:

  ```text
  spec/ticket-0-3-chat-filesdir-seam/spec.md               (read-only)
  spec/ticket-0-3-chat-filesdir-seam/plan.md               (read-only)
  spec/ticket-0-3-chat-filesdir-seam/tasks.md              (checked off per phase)
  spec/ticket-0-3-chat-filesdir-seam/verification-record.md (new)
  entry/src/main/ets/services/ChatFilesDirSeam.ets          (new)
  entry/src/test/ChatFilesDirSeam.test.ets                  (new)
  entry/src/test/List.test.ets                              (register new test)
  entry/src/main/ets/entryability/EntryAbility.ets          (publish seam at onCreate)
  entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets (read seam in loadHistory)
  entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets  (retain filesDir + shape)
  ```

### Reference reviews completed

- ArkTS strict rules reviewed in `docs/style/arkts-1.1.md`; key applied constraints include no `any`/`unknown`, no inline object types, no destructuring, explicit typed object literals, explicit return types, `catch` without type annotation, no object literals as types, and no production ArkUI struct-method changes.
- `arkts-grammar-standards` skill loaded before `.ets` edits.
- Spec 021 storage decisions reviewed in `docs/specs/021-chat-streaming-incremental-rendering.md` (§10 storage / ticket-0 gate): the future snapshot baseline file is app-private `filesDir/chat-history/sessions.json`; `filesDir` acquisition failure blocks the storage ticket; the sanctioned context injection path is `EntryAbility → AppStorage/单例 → AgentFloatWindow`; falling back to Preferences for the new storage design is forbidden; logs must not record snapshot content.
- Official API knowledge verified with `devecocli docs`:
  - FAQ `faqs-ability-15` confirms the application-level files path is obtained via `this.context.getApplicationContext().filesDir`.
  - `ApplicationContext` inherits from `Context` and is obtainable from a `UIAbility` via `getApplicationContext()` (`@kit.AbilityKit`).
  - `AppStorage.SetOrCreate<T>(propName: string, newValue: T): void` confirmed; FAQ `faqs-arkui-49` confirms AppStorage is a UI-thread-only global state store — consistent with the decision to store a plain resolved string, never a UI context.
- Current seam gap reviewed (before implementation):
  - `entry/src/main/ets/entryability/EntryAbility.ets`: injects `reminderFacade` / `backgroundTaskFacade` / `formCardFacade` / `statusBarHeight` into AppStorage in `onCreate`; no filesDir seam exists.
  - `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets`: `loadHistory()` constructs `ChatSessionManager` and calls `this.sm.init(getContext(this))`; no filesDir is obtained anywhere.
  - `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets`: `ChatSessionManager` only wraps `@kit.ArkData.preferences` (`chat_history` / `sessions`); it retains no filesDir and derives no snapshot shape.

### Feature-pointer boundary

`spec/feature.json` still points to `spec/019-reasoning-process-display-p0`. It was not repointed to #121. This ticket owns only `spec/ticket-0-3-chat-filesdir-seam/` and explicitly avoids hiding or taking ownership of the active #019/spec021 dirty work.

## Automated seam evidence

### TDD red-step record (Phase 2, 2026-09-15)

The initial focused #121 test file (`entry/src/test/ChatFilesDirSeam.test.ets`) and its registration in `entry/src/test/List.test.ets` were created before the seam service exists. The initial file contains red assertions for shape composition (`snapshotFile(<filesDir>) === <filesDir>/chat-history/sessions.json`) and resolution semantics (`fromFilesDir(non-empty).state === 'resolved'`), importing the not-yet-created production module `../main/ets/services/ChatFilesDirSeam`.

Red evidence:

- The imported production module `entry/src/main/ets/services/ChatFilesDirSeam.ets` does not exist at this step, so the focused test cannot compile or run — red by construction.
- Focused Hypium execution was attempted with the repository-documented CLI shape:

  ```text
  hvigor test -p module=entry -p coverage=false -p scope=ChatFilesDirSeam.issue121_shape_composition
  ```

  Result: `BLOCKED`, because PowerShell reported `hvigor` is not recognized as a cmdlet; no repository `hvigorw` wrapper exists and `hvigor`/`hvigorw` are not available on `PATH` in this environment (same limitation recorded in the sibling ticket-0.2 record). This is an environment/test-runner blocker, not a passing automated result.

- `arkts_check entry/src/test/ChatFilesDirSeam.test.ets entry/src/test/List.test.ets` returned "No errors found in 2 file(s)"; the local check does not resolve cross-file module imports, so the syntactic validity of the seam file is confirmed but the missing-module red state persists until the service file is created (T011).

### US1 seam resolution + shape (Phase 3, 2026-09-15)

Implemented seam service `entry/src/main/ets/services/ChatFilesDirSeam.ets`:

- `ChatFilesDirSeam` class with readonly `filesDir` / `state` (`'resolved' | 'blocked'`) / `diagnostic`.
- Pure shape helpers `snapshotDir(filesDir)` → `<filesDir>/chat-history` and `snapshotFile(filesDir)` → `<filesDir>/chat-history/sessions.json`; static constant `RELATIVE_SHAPE = 'chat-history/sessions.json'`.
- Pure factory `fromFilesDir(filesDir)`: non-empty resolves, empty blocks, no fabricated directory.
- Thin adapter `fromApplicationContext(ctx: common.ApplicationContext)`: reads `ctx.filesDir`; empty value or thrown error → blocked.
- Diagnostics built only from state + filesDir-derived shape (`seam=resolved; filesDir=...; shape=...` / `seam=blocked; filesDir unavailable; shape=...`).

US1 focused assertions added in `entry/src/test/ChatFilesDirSeam.test.ets`:

- `snapshotDir` / `snapshotFile` composition for a sample filesDir (plus a second sample filesDir).
- `RELATIVE_SHAPE` equals exactly `chat-history/sessions.json`.
- Non-empty filesDir → `resolved` with filesDir preserved; empty filesDir → `blocked` with empty filesDir.
- Resolved diagnostic carries `resolved` + the relative shape; blocked diagnostic carries `blocked` + the intended relative shape.

ArkTS check result after US1 implementation:

```text
arkts_check entry/src/main/ets/services/ChatFilesDirSeam.ets entry/src/test/ChatFilesDirSeam.test.ets entry/src/test/List.test.ets
```

Result: `PASS` — no errors found in 3 files.

Focused seam test execution after US1 implementation:

```text
hvigor test -p module=entry -p coverage=false -p scope=ChatFilesDirSeam.issue121_shape_composition
```

Result: `BLOCKED` — `hvigor` is not available on `PATH` and no repository wrapper exists. The focused Hypium seam is written, registered, and the production module now exists (the red-by-missing-module state is resolved), but runtime PASS/FAIL evidence could not be produced in this environment. This keeps the US1 focused evidence pending a Hypium-capable environment (recorded, not inferred as pass).

### US2 lifecycle wiring (Phase 4, 2026-09-15)

Store interface and production implementation (part of `entry/src/main/ets/services/ChatFilesDirSeam.ets`):

- `ChatFilesDirSeamStore` interface with `read(): ChatFilesDirSeam | null` and `write(seam)`.
- AppStorage-backed production store under key `chatFilesDirSeam`; `read` returns `null` when nothing is published; `write` replaces the previous value.
- `publishChatFilesDirSeam(seam)` / `getChatFilesDirSeam()` production functions plus `setChatFilesDirSeamStoreForTest(store)` / `resetChatFilesDirSeamForTest()` test hooks, mirroring the `ArkWebWarmupService` adapter pattern.
- Note: the store functions were implemented together with the seam model in T011 (single-file contract, per plan §Contracts); T014's store lifecycle assertions were then added in the test file to verify them. TDD red-first granularity at the store slice was therefore partial — recorded here transparently.

End-to-end wiring:

- `entry/src/main/ets/entryability/EntryAbility.ets`: in `onCreate`, after the existing facade injections, the seam is built via `ChatFilesDirSeam.fromApplicationContext(this.context.getApplicationContext())`, published via `publishChatFilesDirSeam`, and its diagnostic is logged via hilog `%{public}s` (info for `resolved`, warn for `blocked` — existing hilog style).
- `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets`: `loadHistory()` re-reads the seam once via `getChatFilesDirSeam()` and hands `seam.filesDir` (or `''` when the seam is null) to `this.sm.recordFilesDir(...)` before `this.sm.init(getContext(this))`. No chat content is logged.
- `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets`: added `recordFilesDir(filesDir)`, `getResolvedSnapshotPath()`, and `hasFilesDir()` to `ChatSessionManager`; the retained value is a plain string (no UI reference); `init(ctx)` / `save(sessions)` bodies remain byte-for-byte unchanged (Preferences `chat_history`/`sessions` still the only persistence path).

US2 focused assertions added in `entry/src/test/ChatFilesDirSeam.test.ets`:

- Store lifecycle: publish → read roundtrip (state/filesDir/diagnostic); absent store → `null`; republish overwrites (ability re-creation).
- Collaborator retention: fresh manager starts blocked/absent (`hasFilesDir` false, path `''`); `recordFilesDir` → path/`hasFilesDir` transitions; re-record replaces; empty record falls back to blocked; `save()` without `init` neither throws nor touches the retained filesDir.

ArkTS check result after US2 wiring:

```text
arkts_check entry/src/main/ets/services/ChatFilesDirSeam.ets entry/src/main/ets/entryability/EntryAbility.ets entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets entry/src/test/ChatFilesDirSeam.test.ets entry/src/test/List.test.ets
```

Result: `PASS` — no errors found in 6 files.

Focused seam test execution after US2 wiring:

```text
hvigor test -p module=entry -p coverage=false -p scope=ChatFilesDirSeam.issue121_store_lifecycle
```

Result: `BLOCKED` — `hvigor` unavailable on `PATH` (same environment limitation). US2 runtime evidence remains pending a Hypium-capable environment; structural evidence (seam read before init, collaborator holds no UI reference — only the imported pure shape helper and a plain string) is recorded here.

### US3 diagnostic safety (Phase 5, 2026-09-15)

Construction guarantee (recorded per T023): `ChatFilesDirSeam` diagnostics are produced exclusively by the two private static builders `buildResolvedDiagnostic()` and `buildBlockedDiagnostic()` in `entry/src/main/ets/services/ChatFilesDirSeam.ets`. Both concatenate only the seam state literal (`resolved`/`blocked`), the fixed `RELATIVE_SHAPE` literal, and (for blocked) the fixed `filesDir unavailable` literal. The raw filesDir string is never embedded in a runtime diagnostic (post-review hardening, see "Post-review fixes"), so no path content — adversarial or otherwise — can leak by construction. No session/message/reasoning/API-key data is an input to diagnostic construction.

US3 focused assertions added in `entry/src/test/ChatFilesDirSeam.test.ets`:

- Adversarial chat content (`请帮我解这道二次函数的题`), session name (`高三数学复习计划`), reasoning text (`首先分析已知条件，然后代入公式`), and API-key string (`sk-abcdef1234567890`) never appear in the resolved diagnostic.
- The same adversarial strings never appear in the blocked diagnostic.
- Diagnostics contain only state (`seam=resolved` / `seam=blocked`), the `shape=` metadata, and (for blocked) the `unavailable` marker — no fabricated directory.
- (Post-review, 2026-09-15) An additional assertion verifies adversarial content placed **inside the filesDir path itself** never reaches the resolved diagnostic; the diagnostic is asserted exactly equal to `seam=resolved; shape=chat-history/sessions.json` regardless of path content.

ArkTS check result after US3 assertions:

```text
arkts_check entry/src/test/ChatFilesDirSeam.test.ets
```

Result: `PASS` — no errors found in 1 file.

Focused seam test execution after US3 assertions:

```text
hvigor test -p module=entry -p coverage=false -p scope=ChatFilesDirSeam.issue121_diagnostic_safety
```

Result: `BLOCKED` — `hvigor` unavailable on `PATH` (same environment limitation). US3 runtime evidence remains pending a Hypium-capable environment; the construction guarantee above is recorded as the by-construction proof.

## Gate status semantics template

The status semantics are covered in two places: human-readable template text below and executable repository-artifact checks in `entry/src/test/ChatFilesDirSeam.test.ets` (`ChatFilesDirSeam.issue121_gate_status_template`). The `.ets` tests are suitable here because the tri-state mapping is pure data and does not need to parse markdown text; the markdown template remains the authoritative record humans will fill during final verification.

### PASS

Use `PASS` only when all automated seam assertions pass and the required device/preview evidence passes. Meaning: the storage branch is released for downstream design consideration only. This ticket still does not migrate storage: no AtomicFile write path, no TaskPool persistence, no snapshot directory/file creation, and no change to the Preferences chat history path (`chat_history`/`sessions`).

### FAIL

Use `FAIL` when the filesDir seam cannot be provided or any required assertion/observation fails. Meaning: the storage branch is blocked and must not adopt a Preferences fallback for the new storage design; the downstream impact is recorded and later storage tickets cannot proceed under an ambiguous assumption.

### INCOMPLETE

Use `INCOMPLETE` when automated evidence passes but required device/preview evidence is missing or inconclusive. Meaning: the storage branch remains blocked; the missing evidence is recorded as blocked tasks rather than done; absence of evidence is never recorded as a pass.

## Production boundary checks (Phase 6, 2026-09-15)

### AtomicFile / TaskPool absence (T026)

Grep of the #121 production diff for `AtomicFile`, `TaskPool`, `worker`, `@ohos.file`, `@kit.ArkTS`:

- `git diff -- entry/src/main/ets` (the four modified production files: `EntryAbility.ets`, `AgentFloatWindow.ets`, `chat/ChatSession.ets`, plus `entry/src/test/List.test.ets`): no matches.
- New file `entry/src/main/ets/services/ChatFilesDirSeam.ets`: the only occurrences of `AtomicFile`/`TaskPool` are in the header comment stating that they must NOT be imported or invoked. No import, no invocation, no `@ohos.file.fs`, no worker usage.
- The only `@ohos.file.fs` import in `entry/src/main/ets` belongs to the pre-existing, untouched `services/ImageUriResolver.ets` — outside the #121 diff.

Result: `PASS` — no AtomicFile import/invocation and no TaskPool import/invocation anywhere in the #121 production change. The resolved filesDir is retained and recorded but never written; no snapshot directory or file is created.

### Preferences path unchanged (T027)

`git diff -- entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets` review:

- The diff adds only: the file-header interface/boundary comments, the `ChatFilesDirSeam` import, one private field (`resolvedFilesDir`), and three new methods (`recordFilesDir`, `getResolvedSnapshotPath`, `hasFilesDir`).
- The `init(ctx)` body and the `save(sessions)` body are byte-for-byte unchanged: `preferences.getPreferences(ctx, "chat_history")`, `getSync("sessions", "")`, `putSync("sessions", ...)`, and `flush()` all remain exactly as before.
- `init`/`save` neither read nor write the new seam field; the retained filesDir is used only for path derivation.

Result: `PASS` — Preferences chat history (`chat_history`/`sessions`) remains the only persistence path, unchanged.

## Polish checks and final scoped diff

### UI result marker (Phase 7)

The `ui_verification_result` marker stays unresolved through implementation:

```text
<!-- ui_verification_result: PENDING -->
```

Phase 8 Verification (T034-T036) owns the build/deploy/UI observation and resolves the marker exactly once. It was resolved to `PASS` in "Final gate resolution" below.

### ArkTS check sweep (T029)

```text
arkts_check entry/src/main/ets/services/ChatFilesDirSeam.ets entry/src/main/ets/entryability/EntryAbility.ets entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets entry/src/test/ChatFilesDirSeam.test.ets entry/src/test/List.test.ets
```

Result: `PASS` — no errors found in 6 files.

### Focused seam test (T030)

```text
hvigor test -p module=entry -p coverage=false -p scope=ChatFilesDirSeam.issue121_shape_composition
```

Result: `BLOCKED` — `hvigor` is not recognized as a cmdlet on this machine; no repository `hvigorw` wrapper exists and `hvigor`/`hvigorw` are not on `PATH`. The focused Hypium test remains queued for a DevEco/Hvigor-capable environment (Phase 8 or user-run).

### Full entry test suite (T031)

```text
hvigor test -p module=entry -p coverage=false
```

Result: `BLOCKED` for the same local `hvigor` availability reason. Honest limitation recorded per execution constraint 7.

Runnable local fallback (full relevant suite):

```text
npm --prefix scripts/arkts-lint test
```

Result: `PASS` — 103 tests passed, 0 failed.

### Naming lint (T032)

```text
node scripts/naming-lint/index.mjs
```

Result: `PASS` — 0 violations across docs and scripts.

Coverage caveat: the naming-lint configured roots cover `docs/` and `scripts/` only; the new #121 files under `spec/ticket-0-3-chat-filesdir-seam/`, `entry/src/main/ets/services/`, and `entry/src/test/` are not linted by this tool. Their names were reviewed manually against `docs/style/naming-conventions.md` (`PascalCase` service class file, `*.test.ets` test file, `kebab-case` spec directory) and follow existing repo conventions.

### Final diff and scoped inventory review (T033)

`git diff --check` produced no whitespace errors. The #121 scoped changed files are:

```text
entry/src/main/ets/services/ChatFilesDirSeam.ets          (new)
entry/src/test/ChatFilesDirSeam.test.ets                  (new)
entry/src/test/List.test.ets                              (register new test)
entry/src/main/ets/entryability/EntryAbility.ets          (publish seam + hilog)
entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets (read seam in loadHistory)
entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets  (retain filesDir + shape)
spec/ticket-0-3-chat-filesdir-seam/tasks.md               (checkboxes)
spec/ticket-0-3-chat-filesdir-seam/verification-record.md (new)
```

`git status --porcelain` after implementation shows exactly the four modified scoped files plus the two new scoped files and `spec/ticket-0-3-chat-filesdir-seam/`; the pre-existing unrelated #019/spec021 dirty and untracked files listed in Phase 1 remain untouched (including `docs/agents/qwen-deepseek-reasoning-handoff-2026-09-12.md`, whose modification belongs to the parallel session's work). Nothing was staged or committed. No AtomicFile/TaskPool code and no Preferences-path change is present in the scoped diff (see "Production boundary checks").

## Final gate resolution

*(Resolved by the Verification phase (Phase 8), 2026-09-15.)*

### Phase 8 evidence (T034-T036)

**T034 — Build.** `build_project` (debug, default product, whole project): `PASS` on the first attempt (`hvigor BUILD SUCCESSFUL in 1 min 2 s 409 ms`, `build_fix_attempts = 1/10`). Only pre-existing ArkTS deprecation/"function may throw" warnings in files outside the #121 scope; no compilation errors. The `Will skip sign 'hos_hap'` warning is the repo's normal unsigned-debug path; deployment succeeded through the devecocli run pipeline regardless.

**T035 — Deploy.** Device: `MatePad Pro 13` emulator (running, serial `127.0.0.1:5555`). `devecocli run --skip-build --device "MatePad Pro 13" --module entry`: app installed and `com.example.mathmind/EntryAbility` started successfully. `PASS`.

**T036 — UI verification and gate resolution.** One `verify_ui` invocation per user story with `freshStart=true`; device logs collected via the returned verification IDs.

- **US1 (resolved filesDir seam):** fresh-start launch → main UI loaded with bottom navigation (central AI button), no crash. Note: the `verify_ui` tool itself is screenshot/UI-operation based and cannot execute log collection, so its step-3 was not runnable by the tool; the required log evidence was collected from that session's device logs instead. Device hilog observed on every fresh start:
  `A00000/testTag: seam=resolved; filesDir=/data/storage/el2/base/files; shape=chat-history/sessions.json`
  This proves the seam resolves the **application-level** app-private filesDir (`/data/storage/el2/base/files`, not the ability-level `.../haps/entry/files`) and derives the exact `<filesDir>/chat-history/sessions.json` shape. `PASS` (attempt 1/3).
  *(Post-review, 2026-09-15: the raw path was subsequently removed from the runtime diagnostic — see "Post-review fixes". A fresh on-device relaunch after the fix re-confirmed the seam: `09-15 11:01:10.749 I A00000/testTag: seam=resolved; shape=chat-history/sessions.json`.)*
- **US2 (floating window lifecycle):** open float via central AI button → close via header close button → re-open. Both opens displayed the Preferences-backed session history/content; no crash, no white screen, no error dialogs. `PASS` (attempt 1/3).
- **US3 (diagnostic safety):** launch + open/close float window (which loads real session history) succeeded. Inspection of that session's full device log: the only seam diagnostics present are the shape-metadata lines above; a grep of the entire captured log for adversarial chat-content/session-name/reasoning/API-key patterns (`二次函数`, `复习计划`, `sk-`, `推理`, `MindTrace AI`, etc.) returned zero matches. `PASS` (attempt 1/3). Diagnostics contain only seam state and directory-shape metadata.
- **US4 (session read/write behavior and production boundary):** open float → type and send `你好,seam验证` → user message rendered → close → re-open → message still present (Preferences persistence intact). Device log inspection: no `chat-history` file creation or filesystem write activity (the only `chat-history` occurrence is the shape string inside the seam diagnostic); no AtomicFile/TaskPool/worker/fileIo activity from the app; `PreferencesJsKit` active. Combined with the static T026/T027 checks (no AtomicFile/TaskPool in the diff; Preferences path byte-for-byte unchanged): `PASS` (attempt 1/3).

**Focused test + full suite (resolves the Phase 7 `BLOCKED` records).** A Hypium-capable runner was located in this environment: the DevEco Studio bundled hvigor (`tools\hvigor\bin\hvigorw.js` executed via `tools\node\node.exe`, with `DEVECO_SDK_HOME` set to the bundled SDK). Phase 7's `BLOCKED` was an environment gap, not a missing runner — resolved here:

```text
hvigorw.js test -p module=entry -p coverage=false -p scope=ChatFilesDirSeam.issue121_shape_composition
```

Result: `PASS` — 4/4 assertions for the shape-composition scope.

```text
hvigorw.js test -p module=entry -p coverage=false
```

Result: `PASS` — `Tests run: 59, Failure: 0, Error: 0, Pass: 59, Ignore: 0`. All 22 focused #121 assertions pass across the six `ChatFilesDirSeam.issue121_*` describes (shape composition 4/4, resolution semantics 4/4, store lifecycle 3/3, collaborator retention 5/5, diagnostic safety 3/3, gate status template 3/3); the other 37 entry tests show no regressions.

**ArkTS check sweep (fresh, Phase 8).** `arkts_check` over the 6 changed `.ets` files: `PASS` — no errors found in 6 file(s).

### Gate resolution

- Automated evidence: `PASS` (22/22 focused assertions on-device; full entry suite 59/59; arkts_check PASS; debug build PASS).
- Device/preview evidence: `PASS` (US1-US4 device observations above).
- `ui_verification_result`: `PASS`; overall gate status: **`PASS`**.
- Downstream semantics (US4): the storage branch is eligible for downstream design consideration **only**; this ticket still performs no storage migration — no AtomicFile, no TaskPool, no snapshot directory/file creation, and Preferences `chat_history`/`sessions` remains the only persistence path.
- Per-story attempt audit: all four stories passed on their first verification attempt; no per-story code fixes were applied (`code_modified=false`), so the final verification pass was skipped per the verification workflow and the per-story verification loop results are authoritative.

## Post-review fixes (2026-09-15)

After the two-axis code review, the following spec-faithful fixes were applied and re-verified:

1. **Shape-only resolved diagnostic** (`entry/src/main/ets/services/ChatFilesDirSeam.ets`): `buildResolvedDiagnostic()` no longer embeds the raw filesDir path; it emits only `seam=resolved; shape=chat-history/sessions.json`. This makes FR-007 ("diagnostics MUST contain only seam state and directory-shape metadata") hold by construction and closes the spec edge case about adversarial content placed inside the path.
2. **Adversarial-path test** (`entry/src/test/ChatFilesDirSeam.test.ets`): added an assertion that an adversarial path (`/data/请帮我解这道二次函数的题/sk-abcdef1234567890/高三数学复习计划/files`) never leaks into the diagnostic, which is asserted exactly equal to the shape-only format.
3. **Header `路径:` field** added to `ChatFilesDirSeam.ets` per `docs/agents/file-header-template.md`.
4. **Doc touch-ups**: `spec.md` status reconciled; this record's stale `PENDING` marker note, the "unblocked" wording, the "Phase 1 authoritative" phrasing, and the US1 quoted log line were corrected.

Re-verification after the fixes:

- `arkts_check` on the two changed `.ets` files: `PASS` — no errors found in 2 file(s).
- `build_project` (debug, whole project): `PASS` (`hvigor BUILD SUCCESSFUL in 1 min 30 s 171 ms`, exitCode 0; only pre-existing out-of-scope deprecation warnings).
- Re-deploy + relaunch on emulator `MatePad Pro 13` (`127.0.0.1:5555`): app installed and launched successfully.
- Device log re-observation (fresh onCreate): `09-15 11:01:10.749 14026 14026 I A00000/testTag: seam=resolved; shape=chat-history/sessions.json` — seam still resolves on-device with the shape-only diagnostic.
- Hypium re-run: the full entry Hypium suite re-ran cleanly after the fixes (user-run in the DevEco environment on 2026-09-15) — `Tests run: 60, Failure: 0, Error: 0, Pass: 60, Ignore: 0`, all 23 focused `#121` assertions pass (shape 4/4, resolution 4/4, store 3/3, collaborator 5/5, diagnostic safety 4/4 incl. the new adversarial-path assertion, gate 3/3); the other 37 entry tests show no regressions; total +1 over the pre-fix 59/59 baseline = exactly the new adversarial-path assertion.
- Pre-fix quirk surfaced during the re-run: `entry/src/test/IncrementalRegeneration.test.ets` used an invalid describe id (`'Issue 104 incremental regeneration'` — spaces + digit-leading) which previously crashed "run all tests" with `00521002`; this is a pre-existing bug, unrelated to #121, but a one-line id fix was required to unblock the full-suite re-run (`IncrementalRegeneration.issue104_incremental_regeneration`); the fix was folded into the #121 commit at user direction (amended on top of `81b6ffb`).

The overall gate status remains **`PASS`** after these fixes.
