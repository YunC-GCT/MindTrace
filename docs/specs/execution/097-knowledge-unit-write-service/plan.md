# Implementation plan

## Architecture

- Add typed write request/result, revision, repository, and side-effect contracts in entry.
- Implement transaction-aware create/update/revision operations in the existing `NoteDao`.
- Add `KnowledgeUnitWriteService` as the stable behavior seam and an entry-side post-commit side-effect implementation.
- Delegate `NoteEditService` and `NoteDaoAdapter` to the service.
- Add an additive `note_revision` schema and idempotent backfill migration.

The API 24 product target supports the API 14+ `RdbStore.createTransaction()` and `Transaction` CRUD/commit/rollback APIs. Official documentation prefers this transaction-object API over legacy `beginTransaction`, so the DAO uses one transaction object for both mutations.

## Testing

- Add a red-capable focused behavior/source guard before production code.
- Add seam-level ArkTS behavior tests with fakes for success, conflict, persistence failure, and side-effect warning behavior.
- Leave full build and repository-wide verification to the verification phase.
