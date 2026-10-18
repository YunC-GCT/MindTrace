# Implementation plan

1. Add shared typed generation contracts, schema constants, deterministic light policy, and local validators.
2. Add an entry-side `NoteGenerationRepository` over additive RDB tables with idempotent run/source/checkpoint upserts and recovery queries.
3. Extend `KnowledgeModel` with a light Structure method using the existing `LlmClient.call` seam and provider capability negotiation.
4. Extend `Dispatcher.dispatch` with generation mode, artifact persistence, TruthChecked candidate output, and zero-DAO behavior for `persist=false`.
5. Cover behavior through `Dispatcher.dispatch` and `NoteGenerationRepository` tests; retain existing Capture and write ownership.

## Ownership boundary

`Dispatcher.dispatch` is the only Capture entry. Light generation uses the
existing CaptureGraph TruthCheckNode as its final gate, while KnowledgeModel
owns the new Structure operation. `NoteGenerationRepository` stores only run,
source, and immutable checkpoint artifacts; it never writes `knowledge_unit`.
Conversation UI confirmation and the #97 KnowledgeUnitWriteService remain
unchanged and are intentionally outside this slice.
