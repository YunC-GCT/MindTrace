# Feature Specification: Ticket 0.3 Chat filesDir Context Seam

**Created**: 2026-09-15
**Status**: Draft, reconciled after review; implementation and verification recorded as `PASS` (2026-09-15); post-review hardening applied (shape-only runtime diagnostic + adversarial-path test)
**Input**: User description: "Implement the work described by the user in the spec or tickets. #121"; clarified decisions: feature directory `spec/ticket-0-3-chat-filesdir-seam/`, application-level app-private filesDir, resolved filesDir string as the injected seam payload.

## Overview

This ticket is a hard verification gate for the chat history persistence branch of spec 021. It verifies that `AgentFloatWindow` and its non-UI chat storage collaborator (`ChatSessionManager`) can obtain the correct app-private `filesDir` needed for the future AtomicFile chat snapshot path, and — because the seam does not exist yet — adds the minimal context injection seam. Storage is **not** migrated: the resolved directory is retained and recorded, but all chat history reads and writes continue through the existing Preferences path.

The gate result is tri-state: `PASS`, `FAIL`, or `INCOMPLETE`. `PASS` releases the storage branch only for downstream design consideration; `FAIL` blocks the storage branch and must not fall back to Preferences for the new storage design; `INCOMPLETE` keeps the storage branch blocked until the missing device/preview evidence is completed.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Resolved filesDir seam without UI references (Priority: P1)

As a maintainer, I want the chat floating window and its non-UI storage collaborator to obtain the correct app-private filesDir through an injected seam, so that the future AtomicFile snapshot path has a verified, UI-free source of truth.

**Why this priority**: This is the blocking precondition for the storage branch of spec 021. Without a verified seam, ticket-0.4 (TaskPool/Worker/AtomicFile capability) and the later snapshot migration cannot be planned.

**Independent Test**: Run the focused automated verification and confirm that the seam resolves the application-level filesDir into the fixed snapshot directory shape, without any global UI reference in the collaborator.

**Acceptance Scenarios**:

1. **Given** the application entry composes the seam at ability creation, **When** the seam is resolved, **Then** it carries the application-level app-private filesDir as a plain string and records a resolved state.
2. **Given** the seam holds the resolved filesDir, **When** the snapshot directory shape is derived, **Then** the shape is exactly `<filesDir>/chat-history/sessions.json`.
3. **Given** the chat floating window initializes its storage collaborator, **When** the seam is read, **Then** the collaborator receives the resolved filesDir as a plain value and does not obtain it through any global UI reference.
4. **Given** the filesDir cannot be resolved (empty or unavailable), **When** the seam is recorded, **Then** the state is blocked and the resolved value is not fabricated or replaced with a Preferences fallback.

---

### User Story 2 - Lifecycle-safe seam for floating window creation/destruction (Priority: P1)

As a maintainer, I want the seam to be safe across floating window creation and destruction, so that re-opening the window never leaks UI references, crashes, or corrupts the current Preferences history path.

**Why this priority**: The floating window is created and destroyed repeatedly during normal use; a seam that breaks on the second lifecycle would invalidate the gate.

**Independent Test**: Exercise window re-creation semantics at the seam level: re-reading the seam on each initialization, re-resolving state, and confirming the collaborator holds no reference to any UI component.

**Acceptance Scenarios**:

1. **Given** a floating window instance is created, **When** the storage collaborator initializes, **Then** the seam is read fresh for that window instance and the resolved filesDir is recorded on the per-window collaborator.
2. **Given** a floating window instance is destroyed and a new one created, **When** the new instance initializes, **Then** the seam is read again without referencing the destroyed instance.
3. **Given** the seam is absent from app state, **When** the floating window initializes, **Then** initialization completes with a blocked seam state, the Preferences history path still works, and no exception is thrown.
4. **Given** the floating window is destroyed, **When** destruction handlers run, **Then** no UI reference owned by the seam outlives the window and the existing Preferences save behavior is unchanged.

---

### User Story 3 - Verification records the directory shape without chat content (Priority: P1)

As a maintainer, I want the verification to record the resolved directory shape while guaranteeing that no chat content or secrets appear in any runtime diagnostic or the verification record.

**Why this priority**: The gate's evidence must be auditable without creating a sensitive-data leak in logs.

**Independent Test**: Run the automated diagnostic-safety verification with adversarial strings and confirm that diagnostics contain only seam state and shape metadata.

**Acceptance Scenarios**:

1. **Given** a resolved filesDir, **When** the shape diagnostic is produced, **Then** it contains the seam state and the snapshot directory shape, and never the chat message content, session names, reasoning text, or API keys.
2. **Given** the verification record is finalized, **When** it documents the resolved directory shape, **Then** it records only directory structure, not chat content or secrets.
3. **Given** a blocked seam, **When** the diagnostic is produced, **Then** it records the blocked state and the intended relative shape without pretending a directory exists.

---

### User Story 4 - Gate status and production boundary are explicit (Priority: P1)

As a maintainer, I want the gate result to have fixed downstream semantics and the production storage boundary to stay untouched, so later storage tickets cannot proceed under an ambiguous assumption.

**Why this priority**: The result controls whether the storage branch may proceed, stays blocked, or remains unproven; and the ticket must not accidentally enable the future migration.

**Independent Test**: Review the verification record after automated and device/preview evidence is complete and confirm each gate status maps to the required downstream action, and that no AtomicFile/TaskPool persistence or Preferences change was introduced.

**Acceptance Scenarios**:

1. **Given** all required automated and device/preview observations pass, **When** the verification completes, **Then** the result is `PASS` and the storage branch is eligible for downstream design consideration without any production migration in this ticket.
2. **Given** the filesDir seam cannot be provided, **When** the verification completes, **Then** the result is `FAIL`, the storage branch is blocked, and no Preferences fallback is adopted for the new storage design.
3. **Given** automated evidence passes but required device/preview evidence is missing, **When** the verification completes, **Then** the result is `INCOMPLETE`, the storage branch remains blocked, and the missing evidence is recorded as blocked tasks rather than done.
4. **Given** any gate result, **When** the changed code is reviewed, **Then** no AtomicFile migration, TaskPool persistence, or change to the Preferences chat history path is present in production.

---

### Edge Cases

- The application context filesDir resolves to an empty string; the seam must record blocked and the floating window must still initialize its Preferences-backed history.
- The seam is not present in app state (for example a preview without the normal ability entry); initialization must not throw and must mark the seam blocked.
- The floating window is created twice in sequence; the second creation must not reference the first window's state.
- The same filesDir value is resolved again on a later ability creation; the seam must re-resolve rather than rely on a stale global.
- Diagnostics are built from the filesDir path; tests must verify adversarial content placed in the path cannot leak chat text, session names, or secrets.
- The existing Preferences chat history load/save path must behave exactly as before the ticket.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The application entry MUST resolve the application-level app-private filesDir at ability creation and publish a resolved plain-string seam through the sanctioned injection vehicle, without retaining a UI context inside the seam.
- **FR-002**: `AgentFloatWindow` MUST read the seam when the chat storage collaborator initializes and hand the resolved filesDir to the non-UI collaborator; the collaborator MUST NOT obtain filesDir through any global UI reference.
- **FR-003**: The non-UI chat storage collaborator MUST retain the resolved filesDir and the derived snapshot directory shape for the future AtomicFile path, without using them for persistence in this ticket.
- **FR-004**: The derived snapshot directory shape MUST be exactly `<application-filesDir>/chat-history/sessions.json`.
- **FR-005**: The seam MUST be lifecycle-safe: it is re-read per floating window initialization, each window owns its collaborator state, no UI component reference is retained by the seam or collaborator, and window destruction MUST NOT crash or change the existing save behavior.
- **FR-006**: If the filesDir cannot be resolved at ability creation, the seam MUST record a blocked state and MUST NOT fabricate a directory or fall back to Preferences for the new storage design.
- **FR-007**: The verification MUST record the resolved directory shape without logging chat content or secrets; runtime diagnostics MUST contain only seam state and directory-shape metadata.
- **FR-008**: The ticket MUST NOT enable AtomicFile migration or TaskPool persistence in production; the resolved filesDir is retained and recorded but never written to.
- **FR-009**: The existing Preferences chat history load/save path MUST remain intact and remain the only persistence path.
- **FR-010**: If required evidence is missing or fails, the verification record MUST mark the gate `FAIL` or `INCOMPLETE` with the storage branch blocked; it MUST NOT mark `PASS` without both automated and device/preview evidence.
- **FR-011**: Changed `.ets` and test artifacts MUST pass ArkTS strict checks, relevant focused tests, the full test suite, and the project debug build; failures MUST be recorded rather than hidden.

### Key Entities *(include if feature involves data)*

- **Chat FilesDir Seam**: A resolved plain-string filesDir plus seam state and shape diagnostic, published by the application entry and read by the floating window.
- **Resolved Directory Shape**: The fixed future snapshot layout `<filesDir>/chat-history/sessions.json`, derived from the application-level filesDir.
- **Chat Storage Collaborator**: The non-UI session persistence manager that retains the resolved filesDir and shape while continuing to use Preferences for all reads and writes.
- **Verification Record**: The durable evidence containing procedures, results, tri-state gate status, diagnostic-safety checks, and the scoped file inventory.
- **Gate Status**: One of `PASS`, `FAIL`, or `INCOMPLETE`, with fixed downstream semantics for the storage branch.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: One focused automated verification covers seam resolution, the snapshot directory shape, blocked-state semantics, and lifecycle re-read semantics, with 100% of assertions passing before the gate can be marked `PASS`.
- **SC-002**: The collaborator's filesDir source contains no global UI reference; the code review records this structural check explicitly.
- **SC-003**: The derived snapshot shape equals `<application-filesDir>/chat-history/sessions.json` for every seam state in the verification.
- **SC-004**: Diagnostic-safety tests prove runtime diagnostics never contain chat content, session names, reasoning text, or API keys, including adversarial inputs.
- **SC-005**: The production diff contains no AtomicFile migration, no TaskPool persistence, and no change to the Preferences chat history path.
- **SC-006**: Relevant ArkTS checks, focused tests, the full test suite, and the debug build all pass with no unreported failures; missing device/preview evidence is recorded as `INCOMPLETE`, not `PASS`.
- **SC-007**: The verification record resolves the gate status unambiguously with the storage branch blocked on `FAIL` or `INCOMPLETE`.

## Assumptions

- The current repository is the project root and the feature artifacts live under `spec/ticket-0-3-chat-filesdir-seam/`.
- The correct app-private filesDir is the application-level one (resolved via the application context), per the clarified decision; its device shape is the `/data/storage/el2/base/files` family.
- The injected seam payload is the resolved filesDir string, not a retained context holder, per the clarified decision.
- The global `spec/feature.json` pointer belongs to the active repository workflow (currently the 019 work) and is not repointed by this ticket, following the #120 precedent.
- The future snapshot layout `chat-history/sessions.json` is fixed by spec 021 §10; this ticket only records the shape and does not create the directory or file.
- Only one `AgentFloatWindow` instance exists at a time (spec 021 assumption); multi-window seam sharing is out of scope.
- Device or preview access may be unavailable in a run; unavailable evidence is a documented `INCOMPLETE` result, not an inferred pass.
- Existing repository changes unrelated to #121 are outside this ticket and must not be overwritten or included in the scoped implementation.
- Repository code-review, staging, and commit rules are delivery-process constraints, not product requirements; they are tracked in the task list and verification record.

## Open Questions

- None. The feature directory, filesDir level, seam payload, and evidence scope were explicitly clarified before implementation.
