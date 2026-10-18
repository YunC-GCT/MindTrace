# Issue 97 — KnowledgeUnit unified writes

## Scope

Unify manual KnowledgeUnit create/update and AI persistence behind one entry-side `KnowledgeUnitWriteService`. Keep `NoteDao` as the sole `knowledge_unit` RDB implementation, persist an immutable revision with every successful write, enforce optimistic version updates, and report post-commit side-effect failures as warnings.

## Acceptance criteria

- Manual create, manual update, and AI persistence delegate to the same write service.
- KnowledgeUnit and revision mutations commit or roll back together.
- Updates match note ID and expected version and return `VERSION_CONFLICT` when no row is affected.
- Revisions are queryable by note ID and version and preserve the full KnowledgeUnit plus optional generation metadata.
- Existing KnowledgeUnit rows are backfilled idempotently during migration.
- Post-commit cache, notes-version, or card failures do not turn a committed write into a failed write.
- Draft UI, generation routes, and write-capable AgentTools remain out of scope.
