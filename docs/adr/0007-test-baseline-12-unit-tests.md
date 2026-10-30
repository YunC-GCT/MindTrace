# 0007 — Test baseline: 12 unit tests for the agent pipeline

MindTrace currently has only 2 Hypium test files in `agents/src/test/`. The audit (2026-09-01) flagged 12 tests as the minimum bar for a healthy pipeline (per ticket #13). We adopt that bar.

## Considered Options

1. **Adopt 12-test baseline now** *(chosen)*. The audit already specified what the 12 tests should cover (StructureService × 4, TruthCheckService × 4, PromptBuilder × 2, dispatcher integration × 2). The bar is set, the path to meet it is clear.
2. **Adopt 6 tests** (one per concern). Lower bar, less coverage, less confidence.
3. **Adopt 0 tests + aim for 100% coverage target**. Aspirational, but the team is small and 100% is a long way from 0 — the gap makes the goal feel unreachable and people stop trying.

## Consequences

- **Chosen (1)**: 12 is the audit's number. Each test maps to a class and a method. Writing them is mechanical once the class exists (post-ADR-0006 split). Coverage goes from 2 → 14, with the new 12 each tied to a discrete responsibility.
- Reject (2): too low. The risk is that a future regression in `TruthCheckService` (e.g. dropping the four math checks) ships without anyone noticing. 4 tests for TruthCheckService is a 4-eye check.
- Reject (3): aspirational targets become demoralizing. 12 is a 6× improvement on 2 — meaningful but not infinite.

## What the 12 tests cover

| Class | Tests | What each verifies |
|-------|-------|-------------------|
| `StructureService` | 4 | (1) builds from valid JSON; (2) rejects malformed JSON; (3) preserves type from `noteType`; (4) emits a stable schema version |
| `TruthCheckService` | 4 | (1) brace pairing; (2) division-by-zero; (3) equation consistency; (4) LaTeX syntax |
| `PromptBuilder` | 2 | (1) emits system + user pair; (2) reuses JSON output rules + LLM type |
| `Dispatcher` (integration) | 2 | (1) `dispatch()` with `persist: false` returns the analysis without writing; (2) `persist: true` writes to `NoteDao` and returns a `KnowledgeUnit` |

All 12 are unit tests (mock external dependencies). They do not require a real DB or real LLM API.

## 现状（2026-10-30 回填）

12 条是**下限**，不是总量，而且早已被超过：`*.test.mjs` **145 个**（`find . -name "*.test.mjs" -not -path "*/node_modules/*" -not -path "*/build/*" | wc -l`），`agent-gate --all` 报 `pass=953 fail=0`（425 个 `.ets`）。本 ADR 里「2 → 14」那组数字是 2026-09 的历史，不要当成当前覆盖率读；「4+4+2+2 分四个单元」的分法也已被 `scripts/arkts-lint/tests/` 下按能力组织的用例取代。

## Reversibility

**Easy**. The 12 tests are additive; deleting one or more is a separate commit. Adopting a higher bar (e.g. 20) is also additive.

## When to adopt

Phase 4 ticket #13 (per audit). Triggered after ADR-0006 (KnowledgeModel split) lands, because `StructureService` / `TruthCheckService` / `PromptBuilder` are the units under test. `Dispatcher` integration tests are independent of the split and can be written any time after ADR-0003.

## Related

- `CONTEXT.md` — defines `Dispatcher`, `StructureService` (implicitly via `Structure`), `KnowledgeUnit`
- Audit §4.18, §8 Q8 — original 12-test proposal
- ADR-0006 — KnowledgeModel split (creates the units that the tests cover)
- ADR-0003 — Dispatcher single-entry (pre-condition for the 2 integration tests)
