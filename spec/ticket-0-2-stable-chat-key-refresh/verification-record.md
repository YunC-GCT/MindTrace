# Verification Record: Ticket 0.2 Stable Chat Key Prop Refresh Gate

**Ticket:** #120 / Ticket 0.2  
**Feature directory:** `spec/ticket-0-2-stable-chat-key-refresh/`  
**Verification scope:** `build+ui`  
**Implementation date:** 2026-09-14  
**Overall gate status:** `PASS` — manual emulator observation of the verification-only harness confirmed message-ID-only key propagation through the real `ChatBubble` `@Prop` path; stable-key branch released for downstream design consideration only  
**UI verification result:** `PASS`  
**Authoritative implementation source:** this Phase 1-6 implementation pass. The earlier verification-only record was superseded because the focused seam is now being added.

## Phase 1 setup evidence

### Branch and pre-existing dirty inventory

- Current branch: `feature/spec-019-p0`.
- Pre-existing unrelated dirty work observed before #120 implementation:
  - `CONTEXT.md`
  - `docs/adr/0015-structured-stream-events.md`
  - `docs/agents/qwen-deepseek-reasoning-handoff-2026-09-12.md`
  - `docs/research/index.md`
  - `docs/specs/019-reasoning-process-display-p0.md`
  - `docs/specs/index.md`
  - `docs/specs/021-chat-streaming-incremental-rendering.md` (pre-existing untracked spec context; read-only for #120)
  - `entry/src/main/ets/shared/atoms/WebKeepAlive.ets`
  - `spec/019-reasoning-process-display-p0/delivery-checklist.md`
  - `spec/019-reasoning-process-display-p0/plan.md`
  - `spec/019-reasoning-process-display-p0/review-report.md`
  - `spec/019-reasoning-process-display-p0/spec.md`
  - `spec/019-reasoning-process-display-p0/tasks.md`
  - `spec/019-reasoning-process-display-p0/verification-report.md`
  - `docs/research/arkweb-render-pipeline-stability-2026-09-11.md`
  - `docs/research/chat-markdown-latex-render-jank-2026-09-13.md`
- #120 scoped files for this implementation pass:
  - `spec/ticket-0-2-stable-chat-key-refresh/spec.md` (read-only)
  - `spec/ticket-0-2-stable-chat-key-refresh/plan.md` (read-only)
  - `spec/ticket-0-2-stable-chat-key-refresh/tasks.md`
  - `spec/ticket-0-2-stable-chat-key-refresh/verification-record.md`
  - `entry/src/test/StableChatKeyRefresh.test.ets`
  - `entry/src/test/List.test.ets`
  - `entry/src/main/ets/overlays/AgentFloatWindow/AgentMessageList.ets` (read-only unless a UI harness becomes unavoidable)
  - `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets` (read-only unless a pure helper becomes unavoidable)
  - `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatBubble.ets` (read-only preservation check)

### Reference reviews completed

- ArkTS strict rules reviewed in `docs/style/arkts-1.1.md`; key applied constraints include no `any`, no inline object types, no destructuring, explicit typed object literals, and no production ArkUI struct-method changes.
- `arkts-grammar-standards` skill loaded before `.ets` edits; `references/recipes-core.md` was also reviewed before writing the new test file.
- Stable-key gate context reviewed in `docs/specs/021-chat-streaming-incremental-rendering.md`, especially section 8 and ticket-0 hard gate semantics.
- Official API knowledge check executed with `devecocli docs` for `LazyForEach`, `IDataSource`, `DataChangeListener.onDataChange`, and key generator behavior. The documentation states that changing data without changing the key does not rebuild the child component and that `onDataChange(index)` is the row-change notification; therefore real UI evidence is still required for the production `@Prop` path.
- Production path inventory reviewed:
  - `AgentMessageList.ets` uses `LazyForEach(this.dataSource, itemGenerator, keyGenerator)`.
  - The item generator creates `ListItem -> ChatBubble({ msg })`.
  - `ChatBubble.ets` receives `@Prop msg: ChatMsg`.
  - Production key generator remains `chatItemKey(msg)`.
  - Current `chatItemKey` in `ChatModels.ets` uses `id`, content length, reasoning length, and streaming state.

### Feature-pointer boundary

`spec/feature.json` still points to `spec/019-reasoning-process-display-p0`. It was not repointed to #120. This ticket owns only `spec/ticket-0-2-stable-chat-key-refresh/` and explicitly avoids hiding or taking ownership of the active #019/spec021 dirty work.

## Automated seam evidence

### TDD red-step record

The initial focused #120 test file and test-suite registration were created before implementing the stable-row fixture. The initial file intentionally asserted that a changed answer with the same message ID would already be visible in the observed row while the row fixture still returned its original data. This produced an intended red assertion if executed by Hypium.

Focused Hypium execution was attempted using the repository-documented CLI shape:

```text
hvigorw test -p module=entry -p coverage=false -p scope=StableChatKeyRefresh.issue120_red
```

Result: `BLOCKED`, because PowerShell reported `hvigorw` is not recognized as a cmdlet, function, script file, or executable program; no repository `hvigorw` wrapper exists and `hvigor`/`hvigorw` are not available on `PATH` in this API session. `arkts_check` on the new red-step file and `List.test.ets` passed, so the initial seam was syntactically valid. This is an environment/test-runner blocker, not a passing automated result. The red-step intent is still preserved in the initial failing assertion before the fixture was implemented.

### Harness-vs-production differences

The automated seam is a pure Hypium fixture, not a full ArkUI render tree. Differences from production are intentional and must be closed by Phase 7 UI verification:

1. The fixture models the row's stable identity and observed row data in plain typed classes; it does not instantiate `AgentMessageList`, `LazyForEach`, or `ChatBubble`.
2. The fixture calls `update(message)` directly to model the row receiving a changed `ChatMsg`; production propagation depends on `IDataSource` notifications, `LazyForEach`, and `@Prop` delivery.
3. The fixture observes `answerText`, `reasoningText`, and `streaming` fields directly; production observes visible Text/renderer/status output.
4. The fixture proves the contract shape needed by #120 but cannot alone prove framework-level reuse/refresh. User Story 2 and Phase 7 remain required.

### Implemented focused seam

`entry/src/test/StableChatKeyRefresh.test.ets` now defines the candidate stable identity as message ID only through `candidateStableKey(message)`. The test-only `StableObservedRow` fixture models a row whose identity remains stable while its observed message fields are replaced from the next `ChatMsg`. No production helper was required, so `ChatModels.ets` was left unchanged.

Automated assertion coverage added:

1. candidate key is exactly `message.id.toString()`;
2. answer growth leaves the stable key unchanged;
3. reasoning growth leaves the stable key unchanged;
4. streaming-to-finished leaves the stable key unchanged;
5. observed answer text updates on the same row identity;
6. observed reasoning text updates on the same row identity, including the legacy missing-reasoning edge case;
7. observed streaming/status changes to finished on the same row identity;
8. PASS/FAIL/INCOMPLETE semantics are encoded as focused repository-artifact checks.

### ArkTS check result after US1 implementation

```text
arkts_check entry/src/test/StableChatKeyRefresh.test.ets entry/src/test/List.test.ets
```

Result: `PASS` — no errors found in 2 files.

### Focused stable-key test execution after US1 implementation

```text
hvigorw test -p module=entry -p coverage=false -p scope=StableChatKeyRefresh.issue120_stable_key_contract
```

Result: `BLOCKED`, because PowerShell reported `hvigorw` is not recognized. The focused Hypium seam is written and registered, but runtime PASS/FAIL evidence could not be produced in this API environment. This keeps `automated_seam_result` unresolved for a build/test-capable phase; it is not recorded as a pass.

## Real UI procedure for Phase 7

Phase 7 must execute this procedure once on a device or Preview. It must use the production path `AgentMessageList.ets -> LazyForEach -> ChatBubble(@Prop msg)` and must not substitute the pure test fixture.

1. Prepare or drive one visible AI `ChatMsg` row with a fixed `message.id`, `streaming=true`, initial answer text, and initial reasoning text. Record the message ID and row-identifying evidence visible or logged for the same row.
2. Answer growth: append answer text without changing `message.id`. Trigger the row data update through the normal message-list path. Expected observation: the same row shows the appended answer text without requiring a new message ID or a production key migration.
3. Reasoning growth: append reasoning text without changing `message.id`. Expected observation: the same row's reasoning area shows the appended reasoning text.
4. Streaming-to-finished: set `streaming=false` without changing `message.id`. Expected observation: the row status changes from generating to finished presentation in the same row.
5. Record each case separately as `PASS`, `FAIL`, or `INCOMPLETE`, including device/Preview environment and any logs/screenshots available to the parent verification phase.
6. Resolve `ui_verification_result` only in Phase 7. If any required UI observation is unavailable or inconclusive, the overall gate remains `INCOMPLETE` even when automated syntax and seam checks pass.

At Phase 4 implementation time no harness was added, because that implementation phase was not allowed to run the production UI verification and adding a production control would itself alter the path under test. After the two-axis review, a separate verification-only UI harness (方案 A) was approved and added on 2026-09-14 as its own page — see "Verification-only UI harness (方案 A)" below. `AgentMessageList.ets` remains unchanged; the harness imports the production `ChatBubble` and `ChatModels` instead of altering the production list path.

The final Verification phase is the only phase that may resolve `ui_verification_result`. If the final UI execution is `INCOMPLETE`, then the overall #120 gate remains `INCOMPLETE` even if the focused seam is syntactically valid and later passes under Hypium.

## Verification-only UI harness (方案 A)

Added 2026-09-14 after the two-axis review determined that existing app controls cannot drive the message-ID-only scenario without touching the production path. This harness is a separate, explicitly-scoped verification page; it does not modify production chat behavior.

### File and registration

- Harness file: `entry/src/main/ets/overlays/AgentFloatWindow/chat/StableChatKeyHarnessPage.ets`
- Page registered in `entry/src/main/resources/base/profile/main_pages.json` as `overlays/AgentFloatWindow/chat/StableChatKeyHarnessPage` (existing entries preserved).

### How to open/run it

- Route name: `overlays/AgentFloatWindow/chat/StableChatKeyHarnessPage`.
- Open via DevEco Studio Preview with the harness file active, or on device/emulator via router pushUrl using the registered route name (e.g. `this.getUIContext().getRouter().pushUrl({ url: 'overlays/AgentFloatWindow/chat/StableChatKeyHarnessPage' })` from a dev-only entry), or through the final Verification phase's UI driver.
- This page renders one AI ChatMsg with fixed `id = 120`, `streaming = true`, plain-text answer and plain-text reasoning (no formula syntax), so Markdown/WebView render paths are not part of the observation.

### The three mutations (same fixed id)

1. **追加回答 (answer growth)**: `content += '·追加回答'` — a NEW `ChatMsg` object with the same id replaces the row item; `listener.onDataChange(0)`.
2. **追加思考 (reasoning growth)**: `reasoning += '·追加思考'` via the production `chatMessageReasoning` helper for legacy-safe reads — new object, same id; `onDataChange(0)`.
3. **结束流式 (streaming-to-finished)**: `streaming = false` — new object, same id; `onDataChange(0)`.

### What to observe

- The fixed display line shows `行 key: 120` and must NOT change across any mutation.
- After 追加回答: the answer text inside the same ChatBubble row grows in place.
- After 追加思考: the reasoning panel text inside the same row grows in place.
- After 结束流式: the row status changes from 正在生成/生成中 to 已完成 in the same row.
- If a mutation leaves the bubble visually unchanged while the key label stays `120`, that is a FAIL observation for the message-ID-only hypothesis (consistent with official FAQ faqs-arkui-828 场景二, which documents that unchanged keys can leave rows unrefreshed).

### Harness-vs-production differences (explicit)

- (a) The harness uses its own minimal in-file `SingleMessageDataSource` (one ChatMsg, private, not exported) with message-ID-only keyGenerator `(msg: ChatMsg): string => msg.id.toString()` and `onDataChange(0)` notifications; production `AgentMessageList` uses `ChatMessageDataSource` with `setMessages`/`onDataReloaded` and the content/reasoning/streaming-sensitive `chatItemKey`.
- (b) Shared real surfaces: `ChatBubble` with `@Prop msg` (imported production component, not a copy), `LazyForEach` keyGenerator semantics, and `List` row rendering. `ChatMsg` and the `chatMessageReasoning`/`copyChatMsg` helpers are the production ones from `ChatModels.ets`.

### ArkTS check result

```text
arkts_check entry/src/main/ets/overlays/AgentFloatWindow/chat/StableChatKeyHarnessPage.ets
```

Result: `PASS` — no errors found in 1 file. File verified UTF-8 without BOM (first bytes `0x2F 0x2A 0x2A`).

Official API knowledge was re-verified with `devecocli docs`: `DataChangeListener.onDataChange(index)` (API 8+, the non-deprecated row-change notification) and the `IDataSource` contract (`totalCount`/`getData`/`registerDataChangeListener`/`unregisterDataChangeListener`).

### Preservation

`AgentMessageList.ets`, `chat/ChatModels.ets`, `chat/ChatBubble.ets`, and all renderer/history/persistence files remain unchanged by this harness. `spec/feature.json` was not changed and still points to `spec/019-reasoning-process-display-p0`.

## Gate status semantics template

The status semantics are covered in two places: human-readable template text below and executable repository-artifact checks in `entry/src/test/StableChatKeyRefresh.test.ets` (`StableChatKeyRefresh.issue120_gate_status_template`). `.ets` tests are suitable here because the tri-state mapping is pure data and does not need to parse markdown text; the markdown template remains the authoritative record humans will fill during final verification.

### PASS

Use `PASS` only when all automated stable-key seam assertions pass and all real UI observations pass. Meaning: the stable-key branch is released for downstream design consideration only. This ticket still does not migrate production `chatItemKey`, does not switch to `StreamingReplyDocument`, and does not remove existing renderers/history/persistence.

### FAIL

Use `FAIL` when any required automated assertion or real UI observation proves that message-ID-only identity does not refresh the required row data. Meaning: record the temporary `id + streaming` fallback branch, document the downstream impact, and prevent downstream tickets from assuming the stable-key contract. The fallback is a downstream decision record, not a production change in this ticket.

### INCOMPLETE

Use `INCOMPLETE` when automated evidence, UI evidence, environment details, or observations are missing/inconclusive. Meaning: the stable-key gate is not released; downstream stable-key assumptions remain blocked; missing UI tasks remain blocked rather than done; the `id + streaming` fallback is not released merely because evidence is absent.

## Preservation checks

- Production `chatItemKey` remains unchanged and still includes `id`, content length, reasoning length, and streaming state.
- `StreamingReplyDocument` was not introduced or connected to production chat.
- `MarkdownRenderer` usage in `ChatBubble.ets` remains unchanged.
- `FormulaSplitRenderer` usage in `ChatBubble.ets` remains unchanged.
- Chat history and persistence paths were not modified.
- `AgentMessageList.ets`, `ChatModels.ets`, `ChatBubble.ets`, renderer files, history files, and persistence files are intentionally outside the implementation diff unless later Phase 7 verification explicitly requests a separate harness.

Specific production files inspected/preserved:

- `entry/src/main/ets/overlays/AgentFloatWindow/AgentMessageList.ets`
- `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets`
- `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatBubble.ets`

No renderer, chat-history, or persistence file was edited by #120.

## Removed stale UI attempt concepts

Earlier repository-only concepts that attempted to treat gate-semantics text or workflow/code-review pause contracts as in-app UI stories have been removed from the active procedure. User Story 3 is a repository artifact check and template, not an app screen. Code review, staging, commit, and push remain outside this implementation pass.

## Polish checks and final scoped diff

### UI result marker

`tasks.md` marker history:

- After the failed `verify_ui` attempt (tool error `Internal error: fetch failed`), the marker was temporarily resolved to `INCOMPLETE`.
- After the manual harness observation on the emulator produced PASS evidence, the marker was updated to its final value:

```text
<!-- ui_verification_result: PASS -->
```

Phase 4/Polish left the marker unresolved; Phase 7 Verification owns and applied both updates. The final value is `PASS`, matching the final gate resolution section at the end of this record.

### Focused entry test after final `.ets` changes

```text
hvigorw test -p module=entry -p coverage=false -p scope=StableChatKeyRefresh.issue120_stable_key_contract
```

Result: `BLOCKED`, because `hvigorw` is not available on `PATH` and no repository wrapper exists. The focused Hypium test remains queued for a DevEco/Hvigor-capable verification environment.

### Full relevant test suite

Two relevant suites were considered:

- Entry Hypium suite attempt:

  ```text
  hvigorw test -p module=entry -p coverage=false
  ```

  Result: `BLOCKED` for the same local `hvigorw` availability reason.

- Repository Node lint/test suite:

  ```text
  npm --prefix scripts/arkts-lint test
  ```

  Result: `PASS` — 103 tests passed, 0 failed.

### Naming lint

```text
node scripts/naming-lint/index.mjs
```

Result: `PASS` — 0 violations across docs and scripts.

Coverage caveat: the naming-lint configured roots cover `docs/` and `scripts/` only; the new #120 files under `spec/ticket-0-2-stable-chat-key-refresh/` and `entry/src/test/` are not linted by this tool. Their names were reviewed manually against `docs/style/naming-conventions.md` (kebab-case, `*.test.ets`) and follow the existing repo conventions.

### Diff and scope review

`git diff --check` produced no whitespace errors. The final #120 scoped changed files (after removing the verification-only harness page by user decision) are:

```text
entry/src/test/List.test.ets
entry/src/test/StableChatKeyRefresh.test.ets
spec/ticket-0-2-stable-chat-key-refresh/spec.md
spec/ticket-0-2-stable-chat-key-refresh/plan.md
spec/ticket-0-2-stable-chat-key-refresh/tasks.md
spec/ticket-0-2-stable-chat-key-refresh/verification-record.md
```

Temporary and now-reverted/removed artifacts (not part of the final diff):
- `entry/src/main/ets/overlays/AgentFloatWindow/chat/StableChatKeyHarnessPage.ets` — verification-only harness; created, observed, then deleted by user decision so it does not ship in production builds.
- `entry/src/main/resources/base/profile/main_pages.json` — temporarily registered the harness route, then restored byte-identical to HEAD.
- `entry/src/main/ets/entryability/EntryAbility.ets` — temporarily switched the app entry to the harness page, then restored byte-identical to HEAD (zero diff).

The broad working tree still contains pre-existing unrelated #019/spec021 dirty and untracked files listed in Phase 1. They were not reverted, staged, committed, or edited for #120. `docs/specs/021-chat-streaming-incremental-rendering.md` was read for context only and remains an unrelated pre-existing untracked file.

Final #120 delivery state before Phase 7: implementation artifacts are present, `arkts_check` and repository Node/naming checks pass, but Hypium runtime and real UI evidence remain unresolved because the local runner is unavailable and UI verification is explicitly out of scope for this subagent.

## Final implementation-phase status

*(Superseded by the final gate resolution section at the end of this record.)* Phase 1 through Polish tasks were completed within implementation scope, with production paths preserved. At that interim point the gate was `INCOMPLETE` because the focused entry test had not yet been executed and UI evidence had not yet been produced. Both were later completed: the focused seam ran green in DevEco Studio (user-run) and the verification-only harness was observed on the emulator (user-run). The authoritative final status is `PASS`.

## Phase 7 final verification result (2026-09-14)

### Environment and scope

- Verification scope confirmed from `tasks.md`: `build+ui` via `<!-- verification_scope: build+ui -->`.
- Device/emulator used for deploy: `MatePad Pro 13` (`127.0.0.1:5555` reported by DevEco run tooling).
- Package launched: `com.example.mathmind/EntryAbility`.
- Per-story fix loop source modifications: none. `code_modified=false`; final Phase 2 no-fix pass was skipped by the verification workflow because no per-story code fix was applied.

### Static/test checks run during verification

```text
arkts_check entry/src/test/StableChatKeyRefresh.test.ets entry/src/test/List.test.ets
```

Result: `PASS` — no errors found in 2 files.

```text
npm --prefix scripts/arkts-lint test
```

Result: `PASS` — 103 tests passed, 0 failed.

```text
node scripts/naming-lint/index.mjs
```

Result: `PASS` — 0 naming violations.

Official documentation check was performed with `devecocli docs` for LazyForEach/Hypium-related topics. The LazyForEach documentation reiterates that the key generator identifies items and key changes cause replacement/recreation, while same keys do not by themselves prove child refresh; therefore the production `@Prop` path still requires real UI evidence.

### Focused automated seam runtime status

Earlier automation attempts:

```text
& .\hvigorw test -p module=entry -p coverage=false -p scope=StableChatKeyRefresh.issue120_stable_key_contract
hvigor test -p module=entry -p coverage=false -p scope=StableChatKeyRefresh.issue120_stable_key_contract
```

Result: `BLOCKED` in this API session (PowerShell did not recognize `hvigorw`/`hvigor`).

User-run DevEco Studio execution (2026-09-14):

- File run by the user in DevEco Studio: `entry/src/test/StableChatKeyRefresh.test.ets` (right-click → Run Local Test).
- User-reported result: **all test cases passed** (focused seam green).

Automated seam status: `PASS` (user-run). This proves the pure-data contract: candidate stable key is message-ID only and the observed-row fixture updates answer/reasoning/streaming state on the same identity. It does not by itself prove framework-level `@Prop` propagation through the real `LazyForEach`/`ChatBubble` tree.

### Build and deploy

```text
build_project(product=default, build_mode=debug)
```

Result: `PASS` — hvigor build completed successfully in 1 min 2 s. Warnings were limited to missing signing configuration and local dependency packaging warnings; no #120 compilation fix was required.

```text
start_app(module=entry, target=default, ability=EntryAbility, hvd=MatePad Pro 13)
```

Result: `PASS` — app installed and `com.example.mathmind/EntryAbility` started successfully.

### UI verification results

*(Superseded by the manual harness observation in the final gate resolution section. Kept as the historical record of the automated `verify_ui` attempts.)*

The automated `verify_ui` tooling attempt produced no usable result:

- US1 automated/equivalent-entry UI verification: `INCOMPLETE`. The provided story describes a focused seam/data-state mutation rather than a concrete application UI operation. The `verify_ui` plan validator rejected it as lacking an executable UI object/action. (The focused seam itself later ran green in DevEco Studio, user-run.)
- US2 production path UI verification: `INCOMPLETE`. `verify_ui` was invoked against the deployed app with an executable plan to locate the chat/AgentFloatWindow path and observe answer growth, reasoning growth, and streaming-to-finished on the same row. The tool returned `Internal error: fetch failed`, so no real UI observation was produced by the tooling.
- US3 verification-record check: satisfied as a repository artifact review — US3 is verified by reviewing `verification-record.md` itself, not by in-app UI evidence. The earlier attempt to treat US3 as an in-app verification-record display was withdrawn as out of scope for #120 and removed from the UI verification procedure. US3 does not produce a UI result and does not affect the tri-state UI evidence outcome.

The automated tooling result was later superseded by the user-run manual harness observation, which produced the authoritative PASS UI evidence recorded in the final gate resolution section.

### Manual production-path observation (user-reported, 2026-09-14)

The user manually exercised the real app streaming path (方案 B) and reported normal behavior: during a streamed AI reply, the answer text grows in the same visible row, the reasoning area grows, and the status changes to 已完成 when the stream ends.

Contrast-evidence caveat: this observation runs under the current production `chatItemKey`, which still includes content length, reasoning length, and streaming state. Because every streaming delta changes that key, the production rows rebuild rather than persist a message-ID-only identity. The manual observation therefore confirms normal production streaming UX but does not prove the #120 hypothesis (message-ID-only key + `@Prop` propagation through `LazyForEach`/`ChatBubble`). That hypothesis was subsequently proven by the verification-only harness with a message-ID-only keyGenerator, observed in the final gate resolution section.

### Resolved placeholders

```text
automated_red_run_result: BLOCKED_HVIGORW_NOT_AVAILABLE (intended red-step recorded; final green run user-reported)
automated_seam_result: PASS_USER_RUN_DEVECO (all focused seam cases green)
arkts_check_result: PASS_NO_ERRORS_IN_2_FILES
focused_entry_test_result: PASS_USER_RUN_DEVECO
full_relevant_suite_result: NODE_ARKTS_LINT_PASS_103_ENTRY_HYPIUM_PASS_USER_RUN_FOCUSED
naming_lint_result: PASS_0_VIOLATIONS
build_result: PASS
deploy_result: PASS
manual_production_observation: NORMAL_CONTRAST_EVIDENCE_ONLY (production key still content/reasoning/streaming-sensitive)
harness_observation: PASS_USER_RUN_EMULATOR (all three mutations updated in place; key stayed 120; no rebuild/blank/flicker)
ui_verification_result: PASS
overall_gate_status: PASS
```

## Post code-review fixes (2026-09-14)

Applied after the two-axis code review of the #120 working tree:

1. `tasks.md` T040 changed from done to blocked at that interim point: UI verification was `INCOMPLETE` because `verify_ui` returned `Internal error: fetch failed`, so the task read as blocked rather than completed. *(Later superseded: after the user-run harness observation produced PASS evidence, T040 was completed and marked `[X]` with the PASS note.)* T038 build and T039 deploy stay complete.
2. `verification-record.md` US3 reclassified as a repository artifact check only; the in-app verification-record display attempt was withdrawn as out of scope for #120 and removed from the UI verification procedure.

Applied after the second review round:

3. `tasks.md` T032 wording fixed: removed the dangling `US4` label (spec defines only US1-US3) and called it a repository-only workflow concept.
4. `verification-record.md` US3 bullet wording fixed to avoid the "INCOMPLETE yet satisfied" contradiction: US3 is a repository artifact review and produces no UI result.
5. `verification-record.md` Polish "UI result marker" section updated to match the then-resolved `<!-- ui_verification_result: INCOMPLETE -->` value; the stale unresolved-marker quote was removed. *(Later superseded: the marker's final value is `PASS`, recorded in the final gate resolution section.)*
6. `verification-record.md` removed the duplicated "Status placeholders for later phases" block superseded by "Resolved placeholders".
7. `verification-record.md` naming-lint section now records the coverage caveat that naming-lint roots exclude `spec/` and `entry/src/test/`.

*(Superseded by the final gate resolution section.)* The focused seam has since executed green in DevEco Studio (user-run), manual production streaming was observed normal under the current production key, and the verification-only harness was observed on the emulator with a message-ID-only keyGenerator. The authoritative final status is `overall_gate_status: PASS`, `ui_verification_result: PASS`. The `id + streaming` fallback was not released because no stable-key refresh failure was ever observed.

## Temporary app-entry switch for manual harness observation (2026-09-14, verification-only)

The user cannot use DevEco Previewer, so the app entry was temporarily pointed at the verification harness page to allow manual observation on the emulator.

- **Change applied:** in `entry/src/main/ets/entryability/EntryAbility.ets`, the single line in `onWindowStageCreate` was changed from
  `windowStage.loadContent('pages/Index', (err) => {`
  to
  `windowStage.loadContent('overlays/AgentFloatWindow/chat/StableChatKeyHarnessPage', (err) => {`.
  Nothing else in the file was touched.
- **Purpose:** manual observation only. This is NOT a production change and must not be shipped.
- **REVERT REQUIRED:** after the user finishes observing the harness on the emulator, `EntryAbility.ets` MUST be changed back to `windowStage.loadContent('pages/Index', (err) => {`. This revert is mandatory before any staging/commit of the working tree or any production build intended for release.
- **arkts_check result after this edit:**
  ```text
  arkts_check entry/src/main/ets/entryability/EntryAbility.ets
  ```
  Result: `PASS` — no errors found in 1 file.

## Final gate resolution: manual harness observation (2026-09-14)

### Manual harness observation evidence (user-reported, emulator MatePad Pro 13, 2026-09-14)

The user manually observed the verification-only harness page (`StableChatKeyHarnessPage`) on the emulator (`MatePad Pro 13`). Evidence per mutation:

1. **追加回答 (answer growth)**: in-place update observed — the answer text inside the same ChatBubble row grew in place; the row key display stayed `120` (unchanged).
2. **追加思考 (reasoning growth)**: in-place update observed — the reasoning panel text inside the same row grew in place; the row key display stayed `120` (unchanged).
3. **结束流式 (streaming-to-finished)**: status changed to 已完成 in the same row; the row key display stayed `120` (unchanged).

No rebuild, blank, or flicker was observed across any of the three mutations. This is PASS evidence for the #120 stable-key gate: under a message-ID-only `LazyForEach` keyGenerator, `@Prop` updates reach the real production `ChatBubble` and all three required mutations update in place with a stable key.

This observation closes the remaining gap: the harness shares the real `ChatBubble` with `@Prop msg`, real `LazyForEach` keyGenerator semantics, and real `List` row rendering, so the `@Prop` propagation question is now answered with real ArkUI evidence.

### Contrast note (kept)

The earlier manual production-path observation (方案 B) remains contrast evidence only: production `chatItemKey` still includes content length, reasoning length, and streaming state, so production rows rebuild rather than persist a message-ID-only identity. The harness observation above is the authoritative message-ID-only evidence because its key generator is `msg.id.toString()`.

### Resolved final status

- `automated_seam_result`: `PASS_USER_RUN_DEVECO` (focused seam green in DevEco Studio, user-run).
- `harness_observation`: `PASS_USER_RUN_EMULATOR` (all three mutations updated in place; key stayed `120`; no rebuild/blank/flicker).
- `ui_verification_result`: `PASS`.
- `overall_gate_status`: `PASS`.

Approved PASS semantics (recorded per the PASS template): the stable-key branch is released for downstream design consideration only. This ticket still does not migrate production `chatItemKey`, does not switch to `StreamingReplyDocument`, and does not remove existing renderers/history/persistence.

### EntryAbility revert confirmation (2026-09-14)

The temporary app-entry switch described above has been reverted. In `entry/src/main/ets/entryability/EntryAbility.ets`, the single line in `onWindowStageCreate` is back to:

```text
windowStage.loadContent('pages/Index', (err) => {
```

Nothing else in the file was changed by the revert (verified via `git diff` — only that one line differs from the harness-switched state).

`arkts_check` after the revert:

```text
arkts_check entry/src/main/ets/entryability/EntryAbility.ets
```

Result: `PASS` — no errors found in 1 file.

## Authoritative final status (supersedes all earlier interim statuses)

**Final gate status: `PASS`** — resolved 2026-09-14. Any earlier section of this record that states `INCOMPLETE` or `PARTIAL` describes an interim state and is superseded by this section.

Evidence chain:

1. `automated_seam_result: PASS` — `entry/src/test/StableChatKeyRefresh.test.ets` executed green in DevEco Studio (user-run).
2. `harness_observation: PASS` — verification-only harness (real `ChatBubble` + `LazyForEach`, message-ID-only keyGenerator `msg.id.toString()`, `onDataChange(0)` notifications) observed by the user on the `MatePad Pro 13` emulator: 追加回答, 追加思考, and 结束流式 all updated in place with the row key constant at `120`; no rebuild/blank/flicker.
3. `ui_verification_result: PASS`.
4. `build_result: PASS`, `deploy_result: PASS`.
5. Static checks: `arkts_check` PASS, arkts-lint node tests PASS (103), naming lint PASS.

Approved PASS semantics: the stable-key branch is released for downstream design consideration only. This ticket does not migrate production `chatItemKey`, does not switch to `StreamingReplyDocument`, and does not remove existing renderers/history/persistence. The `id + streaming` fallback is not released because no stable-key refresh failure was observed.

Harness disposal (user decision): `StableChatKeyHarnessPage.ets` was removed and its `main_pages.json` registration reverted so no verification page ships in production builds. `EntryAbility.ets` was restored to `pages/Index` (zero diff vs HEAD). The durable automated evidence is the focused seam test.

Commit boundary: no staging or commit has been performed. Staging/commit requires explicit user confirmation after code review. Unrelated pre-existing dirty files (#019/spec021) remain excluded.
