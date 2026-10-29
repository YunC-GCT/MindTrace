# Tasks: Issue 98

## Phase 1: Setup

- [X] T001 Read Issue #98/#96, current #97 work, project context, ArkTS rules, spec 018, and official API documentation.
- [X] T002 Establish the typed light-generation and repository seams without changing conversation UI or confirmation behavior.

## Phase 2: Foundational

- [X] T003 Add a red-capable focused Dispatcher/repository behavior test for light routing, zero writes, recovery, and needs-input.
- [X] T004 Run the focused test/check and record the expected red result before production implementation.

## Phase 3: User Story 1 — Light draft generation and recovery

- [X] T005 Add typed request/source/draft/checkpoint/result models, schema contract, policy, and local validators.
- [X] T006 Add additive generation artifact schema and idempotent NoteGenerationRepository storage/recovery.
- [X] T007 Add KnowledgeModel light Structure ownership and provider-aware strict structured output.
- [X] T008 Extend Dispatcher.dispatch for generation, final TruthCheck, needs-input, safe metadata logs, and persist=false zero DAO writes.
- [X] T009 Keep focused seams green and run ArkTS checks after each ETS batch.

## Phase 4: Polish

- [X] T010 Update exports/source guards and document the ownership boundary.
- [X] T011 Review the scoped diff without modifying unrelated session work.

## Phase 5: Verification

<!-- verification_scope: Run relevant tests, strict lint, naming checks, diff check, and full default debug build. -->

- [ ] T012 Run all verification commands and record results.
