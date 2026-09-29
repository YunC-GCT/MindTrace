# Tasks: Issue 97

## Phase 1: Setup

- [X] T001 Read Issue #97, project context, ArkTS rules, workflow architecture, current write paths, and official RDB transaction documentation.
- [X] T002 Establish the `KnowledgeUnitWriteService` seam and strict #97 scope.

## Phase 2: Foundational

- [X] T003 Add a red-capable focused behavior/source guard for unified writes, revisions, conflicts, rollback, and warning semantics.
- [X] T004 Run the focused guard and record the expected red result before production implementation.

## Phase 3: User Story 1 — Unified transactional writes

- [X] T005 Add write/revision contracts and seam-level ArkTS behavior tests.
- [X] T006 Add idempotent `note_revision` schema creation and existing-row backfill.
- [X] T007 Implement transactional NoteDao create/update plus revision and revision queries.
- [X] T008 Implement KnowledgeUnitWriteService result, conflict, and post-commit warning behavior.
- [X] T009 Route manual NoteEditService and AI NoteDaoAdapter writes through KnowledgeUnitWriteService.
- [X] T010 Move cache, notesVersion, and card refresh to post-commit side effects without false save failures.
- [X] T011 Run ArkTS checks after each ArkTS edit and keep the focused guard green.

## Phase 4: Polish

- [X] T012 Update source guards and implementation documentation for the final ownership boundary.
- [X] T013 Review the scoped diff without modifying unrelated session work.

## Phase 5: Verification

<!-- verification_scope: Run relevant tests, strict lint, naming checks, diff check, and full default debug build. -->

- [ ] T014 Run all verification commands and record results.
