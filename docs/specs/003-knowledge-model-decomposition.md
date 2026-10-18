# Ticket #3 — KnowledgeModel decomposition into 3 services

> **Status**: superseded by [spec 015](./015-knowledge-model-decomposition-v2.md) (2026-09-06; ADR-0006 amended)
> **Source ADR**: [`../adr/0006-knowledge-model-decomposition-plan.md`](../adr/0006-knowledge-model-decomposition-plan.md)
> **Files affected**: `agents/src/main/ets/agents/KnowledgeModel.ets` (split into 3 files); `agents/src/main/ets/agents/TypeClassifier.ets` (consumer, unchanged interface); `agents/src/main/ets/core/Dispatcher.ets` (orchestrator, calls the 3 services)
> **Test files**: new `agents/src/test/StructureService.test.ets` (Hypium), `agents/src/test/TruthCheckService.test.ets` (Hypium), `agents/src/test/PromptBuilder.test.ets` (Hypium)

## Why this ticket

`agents/src/main/ets/agents/KnowledgeModel.ets` is **870 LOC** with 7+ responsibilities per the audit (§4.2):
1. `structure()` — pipeline orchestration
2. `buildPrompt()` — prompt construction
3. AI call (LlmClient + LlmGuard wrapping)
4. JSON parse + validate
5. KnowledgeUnit construction
6. `truthCheck()` — 4 math checks
7. `fixLatex()` — LaTeX auto-fix

Per the audit, this violates the "deep module" principle: too many seams in one class, too many reasons to change. ADR-0006 chose 3 services (over 4) as the right granularity: each ≤ 300 LOC, single responsibility, `Dispatcher` orchestrates.

## What we will build

Three new classes in `agents/src/main/ets/agents/`:

```ts
// 1. Prompt construction (~200 LOC)
class PromptBuilder {
  build(req: StructureRequest): ChatMessage[];  // [system, user] pair
  // internal: reuses JSON output rules, model type
}

// 2. Pipeline orchestration (~300 LOC)
class StructureService {
  constructor(
    private llmClient: LlmClient,
    private truthCheckService: TruthCheckService,
  ) {}
  async structure(req: StructureRequest): Promise<KnowledgeUnit>;
  // delegates: prompt → LLM → truth-check → fix → assemble
}

// 3. Math validation (~250 LOC)
class TruthCheckService {
  check(text: string): TruthResult;  // { ok, issues, fixedText }
  // 4 sub-checks: brace pairing, div-by-zero, equation consistency, LaTeX syntax
  // private: fixLatex() helper
}
```

`Dispatcher` is updated to wire these 3 services together:

```ts
class Dispatcher {
  private promptBuilder = new PromptBuilder();
  private truthCheck = new TruthCheckService();
  private structureService = new StructureService(this.llmClient, this.truthCheck);
  // ... existing fields
  async dispatch(req): Promise<DispatchResult> {
    return this.structureService.structure(req);
  }
}
```

`KnowledgeModel` is **deleted**. All 870 LOC of its logic is now in 3 classes, each ≤ 300 LOC with one reason to change.

## Public surface change

`TypeClassifier` and any caller of `KnowledgeModel` (`agents/src/main/ets/agents/TypeClassifier.ets`, etc.) currently call `structureService.structure(req)` after ADR-0006 migration. The interface is preserved; only the class name changes (`KnowledgeModel` → `StructureService`).

`Dispatcher` has a new internal seam — `promptBuilder` and `truthCheck` — but its public `dispatch(req)` is unchanged.

## Migration (mechanical, multi-step)

This is a non-trivial refactor. **Three atomic PRs** for reviewability:

### PR 1: extract `PromptBuilder`

```bash
git mv agents/src/main/ets/agents/KnowledgeModel.ets \
       agents/src/main/ets/agents/_KnowledgeModel.ets.legacy
# extract PromptBuilder into a new file
# new file: agents/src/main/ets/agents/PromptBuilder.ets
# update KnowledgeModel to call PromptBuilder.build() (1 line change)
# existing tests pass (behavior preserved)
```

After PR 1: 2 files, no behavior change.

### PR 2: extract `TruthCheckService`

```bash
# new file: agents/src/main/ets/agents/TruthCheckService.ets
# update KnowledgeModel to call truthCheck.check() (1 line change)
# add agents/src/test/TruthCheckService.test.ets (4 math tests)
```

After PR 2: 3 files, 1 new test file. The truthCheck logic is now in 1 file.

### PR 3: extract `StructureService`, delete `KnowledgeModel`

```bash
# new file: agents/src/main/ets/agents/StructureService.ets
# StructureService contains the orchestration logic (the rest of
# KnowledgeModel minus PromptBuilder and TruthCheckService)
# Dispatcher updated to wire the 3 services
# delete _KnowledgeModel.ets.legacy
# add agents/src/test/StructureService.test.ets (4 happy-path tests)
# add agents/src/test/PromptBuilder.test.ets (2 tests)
```

After PR 3: 3 new files, 2 test files. `KnowledgeModel` no longer exists. Dispatcher orchestrates 3 services.

## Test plan (TDD)

Per ADR-0007 (12-test baseline) and the test distribution in that ADR:

| Class | New tests (Hypium) | What each verifies |
|-------|---------------------|---------------------|
| `PromptBuilder` | 2 | (1) emits system + user pair; (2) reuses JSON output rules + LLM type |
| `TruthCheckService` | 4 | (1) brace pairing; (2) div-by-zero; (3) equation consistency; (4) LaTeX syntax |
| `StructureService` | 4 | (1) builds from valid JSON; (2) rejects malformed JSON; (3) preserves type from `noteType`; (4) emits a stable schema version |
| `Dispatcher` (integration) | 2 | (1) `dispatch()` with `persist: false` returns the analysis without writing; (2) `persist: true` writes to `NoteDao` and returns a `KnowledgeUnit` |

12 new tests total. Adds to the existing 2 tests, total 14. Lint baseline will move from `0/253` to `0/164` (89 fewer struct-method warnings).

## Reversibility

**Hard** (the rename is fine; the structural split is hard to undo because the call sites grow). Each PR is independently revertable.

## Acceptance criteria

- [ ] `KnowledgeModel.ets` does not exist (renamed to `_legacy` then deleted in PR 3)
- [ ] 3 new files: `PromptBuilder.ets`, `TruthCheckService.ets`, `StructureService.ets`
- [ ] `Dispatcher.ets` instantiates all 3 services in its constructor
- [ ] 12 new tests in `agents/src/test/` (4+4+2+2)
- [ ] `node scripts/arkts-lint/index.mjs --quiet` shows warnings count ≤ 165 (currently 253, target 89 fewer for the moved-to-PromptBuilder methods)
- [ ] `node --test scripts/arkts-lint/tests/*.test.mjs` all 65+ pass
- [ ] No change in observable behavior: same response shape, same DB writes, same error semantics

## Sequence (3 atomic PRs)

As above. Each is revertable; each is testable in isolation.

## Out of scope (intentionally)

- LlmClient consolidation (ticket #5, separate)
- Dispatcher single-entry (ticket #4, separate, should land BEFORE this ticket)
- 4-class variant (with separate `LlmJsonValidator`); the 3-class split is enough
- Renaming `agents/mcp/tools/` (ticket #10, separate)
- Adopting actual MCP server (per ADR-0005, future consideration)
