# Issue 98 — Light note generation and recovery artifacts

## Scope

Add a typed, persistence-disabled generation path for short or single-source material. The path selects the deterministic light route, asks `KnowledgeModel` to own Structure, validates the versioned draft contract locally, runs the existing final TruthCheck gate, and stores only resumable generation artifacts. It must not change conversation UI or confirmation behavior.

## Acceptance criteria

- `Dispatcher.dispatch` remains the only Capture entry and supports a typed `NoteGenerationRequest`.
- Ordered source fragments preserve stable IDs, origin IDs, fingerprints, sequence, and original text; the raw instruction is retained.
- Short/single-source material deterministically selects `light` with explicit budgets.
- `KnowledgeModel` owns light Structure and all model traffic goes through `LlmClient.call`.
- Draft output is checked against a versioned JSON Schema subset, domain rules, MM-MD-v1, and formulas.
- Strict `json_schema` is sent only to providers that explicitly declare support; custom providers default to local validation.
- `persist=false` returns a TruthChecked candidate and performs zero KnowledgeUnit DAO writes.
- Runs, ordered sources, and immutable checkpoints are additive and idempotent and can be restored after restart.
- Missing required facts return `needs-input` with explicit questions and never create a fallback KnowledgeUnit.
- Logs contain only run ID, route, counts, issue codes, and token information.

## Out of scope

Conversation UI switch (#99), confirmation restore/idempotency (#100), standard/deep routes (#101/#103), bounded repair (#102), and regenerate (#104).
