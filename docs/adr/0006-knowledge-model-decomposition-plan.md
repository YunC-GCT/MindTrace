# 0006 — KnowledgeModel decomposition plan

`agents/src/main/ets/agents/KnowledgeModel.ets` is 870 LOC with 7+ responsibilities (per audit §4.2). It mixes structure building, AI call wrapping, JSON schema validation, and 4-check truth verification. We accept the audit's recommendation: split into 3 collaborators.

## Considered Options

1. **Three-class split: `StructureService` + `TruthCheckService` + `PromptBuilder`** *(chosen)*. Matches audit §5.1. Each class has one reason to change. Composition root is `Dispatcher`, which already orchestrates sub-agents.
2. **Four-class split** (add `LlmJsonValidator`). More granular but a 4th class for 30 lines of validation logic is over-decomposition.
3. **No split**. Add internal section comments and call it a day. Cost: zero. Risk: 870 LOC keeps growing.

## Consequences

- **Chosen (1)**: each class is ≤ 300 LOC, single responsibility. `Dispatcher` knows the order. Testing surface: can unit-test `TruthCheckService` independently (the math correctness checks) without mocking LLM.
- Reject (2): a class that does only JSON schema validation should be a function or a small module, not a sibling class. The 4th class adds DI complexity.
- Reject (3): 870 LOC is past the "I can hold it all in my head" threshold. Code review cost grows superlinearly.

## Reversibility

**Hard**. The class is consumed by `Dispatcher.dispatch` and `KnowledgeGalaxyViewModel`. Splitting changes the import graph. Migration is mechanical (one PR) but rollback is also mechanical (one revert). Once split, the parts don't have a strong reason to merge back.

## Migration plan

Phase 4 ticket #3 (already in audit). The 3 classes:

| Class | Lines | Public method |
|-------|-------|----------------|
| `StructureService` | ~300 | `structure(req: StructureRequest): Promise<KnowledgeUnit>` |
| `TruthCheckService` | ~250 | `check(text: string): TruthResult` |
| `PromptBuilder` | ~200 | `build(category: NoteType, text: string, hints?): ChatMessage[]` |

`Dispatcher` calls them in sequence:
```ts
const prompt = promptBuilder.build(req.category, text, req.hints);
const raw = await llmClient.call({ messages: [prompt] });
return truthCheckService.check(raw);  // → mutates response fields or null
```

`KnowledgeGalaxyViewModel` continues to call `dispatcher.dispatch(req)` and is unaware of the split.

## Related

- Audit §4.2 — original god-class finding
- Phase 4 ticket #3 — implementation ticket
- `CONTEXT.md` — defines `KnowledgeUnit`, `Capture`, `Structure`

## Amendment (2026-09-06)

Direction reaffirmed with a tool-calling addendum, per the [agent-tools inventory](../architecture/agent-tools-inventory-2026-09-06.md) cycle and user ruling:

- **The 3-way split stands.** User ruling: prompt constants and validation stay as code (this already endorses 2 of the 3 classes).
- **Tool-calling reservation**: after the split, `StructureService` confines its LLM interaction to a single private seam (today `LlmGuard.callJsonWithRetry`, same `LlmCaller` pattern), swappable by the `ToolLoop` from [ADR-0012](./0012-tool-calling-protocol.md) without interface change.
- **Schedule**: only the TruthCheck extraction lands in the competition window (zero-LLM-dependency segment, lowest regression risk); PromptBuilder/StructureService extraction is post-competition. The updated plan lives in [spec 015](../specs/015-knowledge-model-decomposition-v2.md), which supersedes [spec 003](../specs/003-knowledge-model-decomposition.md) (its PR sequence and test counts predate the D2 world: the 3 façade shells already exist, `Dispatcher` is single-entry).
