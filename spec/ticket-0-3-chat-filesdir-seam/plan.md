# Implementation Plan: Ticket 0.3 Chat filesDir Context Seam

**Input**: Feature specification from `spec/ticket-0-3-chat-filesdir-seam/spec.md`

## Summary

#121 is a hard verification gate for the storage branch of spec 021. It verifies that `AgentFloatWindow` and its non-UI collaborator `ChatSessionManager` can obtain the correct application-level app-private filesDir for the future AtomicFile chat snapshot path, and adds the minimal missing seam: the entry ability resolves the filesDir once at creation, publishes a plain-string seam through AppStorage (the repo's composition-root injection convention), and the floating window hands the resolved value to the collaborator on each initialization. Storage is not migrated: the collaborator retains and exposes the resolved snapshot shape but continues to use Preferences for all reads and writes.

The gate is tri-state: `PASS` releases the storage branch for downstream design consideration only, `FAIL` blocks the storage branch with no Preferences fallback for the new design, and `INCOMPLETE` keeps the storage branch blocked until device/preview evidence is completed. The global `spec/feature.json` pointer is not owned by this ticket.

## Technical Context

**Language/Version**: ArkTS 1.1 strict, HarmonyOS project baseline from existing `build-profile.json5`
**Primary Dependencies**: `@kit.AbilityKit` (`common` Context/ApplicationContext), `@kit.ArkUI` (AppStorage), `@kit.ArkData` (preferences, unchanged), `@kit.PerformanceAnalysisKit` (hilog), `@ohos/hypium` (tests)
**State Management**: Retain the existing incremental-project state-management style; no migration. AppStorage is already the repo's composition-root injection vehicle (`reminderFacade`, `backgroundTaskFacade`, `formCardFacade`, `statusBarHeight`)
**Storage**: Preferences chat history unchanged (`chat_history`/`sessions`). The resolved filesDir is retained as plain data only; no file I/O in this ticket
**Testing**: Existing Hypium-style `.ets` tests under `entry/src/test/` registered in `List.test.ets`; `arkts_check`; focused tests; one full suite run at the end; debug build
**Target Platform**: MindTrace HarmonyOS entry-module chat floating window
**Project Type**: Existing multi-module HarmonyOS mobile application (1 HAP + 4 HSP)
**Performance Goals**: No new production persistence or rendering overhead; seam resolution is a one-time string read at ability creation and a per-window string hand-off at initialization
**Constraints**: Do not import or invoke AtomicFile/TaskPool in production; do not change the Preferences load/save path; do not hold a UI context in the seam or the collaborator; do not log chat content or secrets; do not modify unrelated dirty work; do not repoint `spec/feature.json`
**Scale/Scope**: One P0 gate ticket; one new seam service file, one new focused test file, three small production edits, one verification record

## Project Structure

### Documentation (this feature)

```text
spec/ticket-0-3-chat-filesdir-seam/
|-- spec.md
|-- plan.md
|-- tasks.md
`-- verification-record.md
```

### Source Code (repository root)

```text
entry/src/main/ets/
|-- entryability/
|   `-- EntryAbility.ets                 # Modified: publish seam at onCreate
|-- services/
|   `-- ChatFilesDirSeam.ets             # New: seam model, pure shape helpers, injectable store
`-- overlays/AgentFloatWindow/
    |-- AgentFloatWindow.ets             # Modified: read seam, hand filesDir to collaborator
    `-- chat/
        `-- ChatSession.ets              # Modified: retain filesDir + snapshot shape

entry/src/test/
|-- List.test.ets                        # Modified: register the focused seam test
`-- ChatFilesDirSeam.test.ets            # New: focused #121 automated seam
```

**Structure Decision**: Follow the existing MindTrace entry architecture and conventions — services live in `entry/src/main/ets/services/`, chat overlay code stays under `overlays/AgentFloatWindow/`, the composition root is `EntryAbility.onCreate`, and Hypium tests live in `entry/src/test/`. No MVVM migration and no state-management migration is introduced; this is incremental gate work within the existing architecture. The new file count (one service, one test) is the smallest set that keeps the seam model, the injection vehicle, and the collaborator retention boundary separate and testable.

## Complexity Tracking

No planned architecture complexity violations. The injectable seam store (a read/write abstraction over AppStorage with a test fake) is justified because AppStorage behavior is not hermetic inside Hypium unit tests, and the lifecycle re-read semantics required by FR-005 need deterministic automated coverage. This mirrors the existing `ArkWebWarmupService` platform-adapter test seam precedent.

## Research & Decisions

- **Decision**: Use AppStorage as the sanctioned injection vehicle, following the EntryAbility composition-root pattern.
  **Rationale**: Spec 021 §10 sanctions `EntryAbility → AppStorage/单例 → AgentFloatWindow`; the official FAQ (工具类中获取Context) recommends saving the app context into AppStorage and reading it from AppStorage in tool classes; the repo already injects `reminderFacade`, `backgroundTaskFacade`, `formCardFacade`, and `statusBarHeight` this way in `EntryAbility.onCreate`.
  **Alternatives considered**: A module-level singleton was rejected because it bypasses the composition-root convention and complicates deterministic test seams. Passing the `UIAbilityContext` itself was rejected because Context cannot be passed into TaskPool (official FAQ on multi-thread Context passing) and would retain a UI reference in app state.

- **Decision**: Resolve the application-level filesDir (`getApplicationContext().filesDir`) as the seam payload, stored as a plain string.
  **Rationale**: User-confirmed decision; the official FAQ distinguishes application context (`/data/storage/el2/base/files`) from ability context (`/data/storage/el2/base/haps/entry/files`), and "app-private filesDir" matches the application-level path. A plain string is TaskPool-ready for the future storage ticket and keeps UI context out of the seam and the non-UI collaborator.
  **Alternatives considered**: Ability-level filesDir was rejected by the clarified decision. Retaining a context holder was rejected because it retains UI references and cannot cross into TaskPool later.

- **Decision**: When filesDir cannot be resolved, record a `blocked` state with the intended relative shape and no fallback.
  **Rationale**: Spec 021 §10 mandates blocking the storage ticket and forbids falling back to Preferences for the new storage design. The floating window must still initialize normally on its unchanged Preferences path.
  **Alternatives considered**: Fabricating a directory or falling back to Preferences for the new design was rejected per the spec's hard-gate rule.

- **Decision**: Split the seam into a pure `fromFilesDir(filesDir)` factory plus a thin `fromApplicationContext(ctx)` adapter.
  **Rationale**: The pure factory is fully testable in Hypium without constructing a real `ApplicationContext`; the adapter is a one-line context read exercised on device/preview. This mirrors the `ArkWebWarmupService` test-adapter precedent.
  **Alternatives considered**: Testing through a mocked `ApplicationContext` object was rejected because ArkTS strict typing makes faking the large Context interface brittle.

- **Decision**: Add a `recordFilesDir(filesDir)` method on `ChatSessionManager` instead of changing the `init(ctx)` signature.
  **Rationale**: Keeps the Preferences load/save path byte-for-byte intact, reduces risk, and makes the per-window lifecycle hand-off explicit: each window initialization re-reads the seam and re-records the value.
  **Alternatives considered**: Widening `init` to take a second parameter was rejected because it entangles the unchanged Preferences path with the new seam. Storing the seam on the floating window only (not the collaborator) was rejected because the acceptance criterion requires the non-UI collaborator to obtain the filesDir.

- **Decision**: Introduce a small injectable seam store (`read`/`write`) with an AppStorage-backed production implementation and an in-memory test fake.
  **Rationale**: Gives deterministic automated coverage of publish → read roundtrip, absent-seam → null, and republish overwrite (ability re-creation) semantics without depending on AppStorage behavior inside unit tests.
  **Alternatives considered**: Direct AppStorage calls everywhere was rejected as untestable in Hypium and weaker for lifecycle coverage.

- **Decision**: Runtime diagnostics contain only seam state and the resolved directory shape.
  **Rationale**: The diagnostic is built exclusively from the system-provided filesDir and fixed path literals, so chat content, session names, reasoning text, and API keys cannot appear by construction; automated adversarial tests enforce this.
  **Alternatives considered**: Logging nothing was rejected because the gate requires recorded evidence of the resolved shape. Logging chat metadata was rejected per the acceptance criteria.

- **Decision**: Preserve the repository feature-pointer boundary; do not repoint `spec/feature.json`.
  **Rationale**: The pointer belongs to the active repository workflow (currently the 019 work). Repointing it to this ticket would hide the active work from other tooling, following the reconciled #120 precedent.
  **Alternatives considered**: Overwriting `spec/feature.json` was rejected for the same reason recorded in the #120 plan.

- **Decision**: No AtomicFile or TaskPool import or invocation anywhere in production; the resolved filesDir is retained and exposed but never written.
  **Rationale**: The ticket is verification-only. Enabling migration here would violate the ticket's hard gate and spec 021's ticket-0 gate rules.
  **Alternatives considered**: A partial write path was rejected as out of scope and gate-violating.

## Data Model

### Chat FilesDir Seam

- **Fields**: `filesDir` (string, the resolved application-level app-private filesDir), `state` (`'resolved' | 'blocked'`), `diagnostic` (string, state + shape metadata only).
- **Validation rules**: `resolved` requires a non-empty `filesDir`; `blocked` must carry an empty `filesDir` and a diagnostic naming the intended relative shape; the diagnostic must never contain chat message content, session names, reasoning text, or API keys.
- **State transitions**: none at runtime — the seam is an immutable resolved value; ability re-creation produces a fresh seam and republishing overwrites the store entry.

### Resolved Directory Shape

- **Fields**: snapshot directory = `<filesDir>/chat-history`; snapshot file = `<snapshot directory>/sessions.json`; relative shape constant = `chat-history/sessions.json`.
- **Validation rules**: derived only from the filesDir plus the two fixed path literals fixed by spec 021 §10; never derived from session or message data.
- **Relationship**: future AtomicFile target; in this ticket it is recorded and tested but not created and not written.

### Chat Storage Collaborator Additions

- **Fields**: retained `filesDir` (string, default empty), derived resolved snapshot path (computed from the retained value), a `hasFilesDir` query.
- **Validation rules**: empty retained value means blocked/absent seam; re-recording replaces the previous value per window initialization; no persistence method reads or writes these fields.
- **State transitions**: empty → resolved value on `recordFilesDir`; re-record on each window initialization; save/load behavior unchanged and independent of these fields.

### Seam Store

- **Fields**: single seam slot.
- **Validation rules**: `read` returns the current seam or null when nothing is published; `write` replaces the previous value.
- **Relationship**: production implementation is backed by AppStorage under one fixed key; test implementation is an in-memory fake.

### Verification Record

- **Fields**: scope, environment, procedures, automated results, device/preview results, diagnostic-safety checks, gate status, blocked-task notes, preservation checks, scoped file inventory.
- **Validation rules**: `PASS` requires both automated and device/preview evidence; `FAIL` requires an observed seam failure and records the storage branch as blocked; `INCOMPLETE` records missing device/preview evidence and keeps the storage branch blocked.

## Contracts & Interfaces

### ChatFilesDirSeam (new service, `entry/src/main/ets/services/ChatFilesDirSeam.ets`)

- `ChatFilesDirSeam` class: read-only fields `filesDir: string`, `state: 'resolved' | 'blocked'`, `diagnostic: string`.
- `ChatFilesDirSeam.fromApplicationContext(context: common.ApplicationContext): ChatFilesDirSeam` — thin adapter reading the application-level filesDir; any empty value or thrown error yields the blocked state.
- `ChatFilesDirSeam.fromFilesDir(filesDir: string): ChatFilesDirSeam` — pure factory: non-empty string resolves; empty string blocks.
- `ChatFilesDirSeam.snapshotDir(filesDir: string): string` — pure: `<filesDir>/chat-history`.
- `ChatFilesDirSeam.snapshotFile(filesDir: string): string` — pure: `<snapshotDir>/sessions.json`.
- `ChatFilesDirSeam.RELATIVE_SHAPE: string` — constant `chat-history/sessions.json`.
- `interface ChatFilesDirSeamStore { read(): ChatFilesDirSeam | null; write(seam: ChatFilesDirSeam): void }`.
- `publishChatFilesDirSeam(seam: ChatFilesDirSeam): void` — production write via the store.
- `getChatFilesDirSeam(): ChatFilesDirSeam | null` — production read via the store; null when nothing is published.
- `setChatFilesDirSeamStoreForTest(store: ChatFilesDirSeamStore): void` / `resetChatFilesDirSeamForTest(): void` — test seam control, mirroring the `ArkWebWarmupService` adapter pattern.

### ChatSessionManager (modified, `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets`)

- `recordFilesDir(filesDir: string): void` — retains the resolved value and recomputes the derived snapshot path; empty value records the blocked/absent state.
- `getResolvedSnapshotPath(): string` — returns the derived `<filesDir>/chat-history/sessions.json` or empty when blocked/absent.
- `hasFilesDir(): boolean` — true only when a resolved filesDir is retained.
- Unchanged contracts: `sid()`, `init(ctx)` Preferences load, `save(sessions)` Preferences save; neither reads nor writes the seam fields.

### AgentFloatWindow (modified, `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets`)

- During `loadHistory()`, read the seam once via `getChatFilesDirSeam()` and hand `seam.filesDir` (or empty string when null) to `ChatSessionManager.recordFilesDir` before `init`. No other behavioral change; no logging of chat content.

### EntryAbility (modified, `entry/src/main/ets/entryability/EntryAbility.ets`)

- In `onCreate`, after the existing facade injections: build the seam from `this.context.getApplicationContext()`, publish it via `publishChatFilesDirSeam`, and log the seam diagnostic via hilog using the existing `%{public}s` format. The diagnostic contains only state and shape metadata.

### Automated Verification Contract (`entry/src/test/ChatFilesDirSeam.test.ets`)

- Pure shape composition: snapshot directory and snapshot file for a sample filesDir; relative shape constant.
- Resolution semantics: non-empty filesDir resolves; empty filesDir blocks; diagnostics carry state and shape.
- Diagnostic safety: adversarial chat content, session name, reasoning, and API-key strings never appear in any diagnostic.
- Store lifecycle semantics: publish → read roundtrip; absent store → null; republish overwrites (ability re-creation).
- Collaborator retention: `recordFilesDir` + `getResolvedSnapshotPath` + `hasFilesDir` transitions; `save()` without initialization neither throws nor touches the retained filesDir.

### Preservation Contract

- No AtomicFile import or invocation; no TaskPool import or invocation in production.
- Preferences chat history load/save path unchanged.
- No production path switched to the snapshot location; the directory/file is not created.
- No changes to unrelated pre-existing dirty files.
- `spec/feature.json` remains untouched.

## Changelog

- **2026-09-15**: Initial plan for #121, reconciled with the clarified decisions (application-level filesDir, resolved plain-string seam payload, feature directory `spec/ticket-0-3-chat-filesdir-seam/`).
