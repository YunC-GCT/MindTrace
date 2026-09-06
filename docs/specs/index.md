# Ticket specs index

This directory holds **implementation specs** for the P0/P1 tickets identified in the
2026-09-01 audit ([`docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md`](../legacy/mindtrace/architecture/audit-full-2026-09-01.md)). Each spec is derived from
an ADR (`docs/adr/`) and follows the same template.

## Coverage map

| Ticket | Spec | ADR | Status |
|--------|------|-----|--------|
| **#3** | [`003-knowledge-model-decomposition.md`](./003-knowledge-model-decomposition.md) | [`0006`](../adr/0006-knowledge-model-decomposition-plan.md) | **in progress** — 3 façades (`PromptBuilder` / `TruthCheckService` / `StructureService`) landed as forwarding shells; real split pending |
| **#4** | [`004-dispatcher-single-entry.md`](./004-dispatcher-single-entry.md) | [`0003`](../adr/0003-dispatcher-single-entry-design.md) | **implemented** (D2, 2026-09-05) |
| **#5** | [`005-llm-client-consolidation.md`](./005-llm-client-consolidation.md) | [`0004`](../adr/0004-llm-call-layer-consolidation.md) | **implemented** (2026-09-06) |
| **#7** | [`007-agent-chat-service-decomposition.md`](./007-agent-chat-service-decomposition.md) | (implicit) | spec ready, not implemented |
| **#9** | [`009-llm-config-throw-on-silent-override.md`](./009-llm-config-throw-on-silent-override.md) | (implicit, defensive coding principle) | **implemented** (TDD) |
| **#10** | [`010-mcp-to-tools-rename.md`](./010-mcp-to-tools-rename.md) | [`0005`](../adr/0005-mcp-to-tools-rename.md) | spec ready, not implemented |
| **#11 / D2** | [`011-capturegraph-arkts-refactor.md`](./011-capturegraph-arkts-refactor.md) | [`0008`](../adr/0008-capturegraph-self-built-runtime.md) | **implemented** (D2, 2026-09-05; see [teaching doc](../agents/d2-capturegraph-teaching-2026-09-05.md)) |
| **#12 / D3** | [`012-frontend-component-model.md`](./012-frontend-component-model.md) | (spec-driven) | **in progress** — `shared/components` split into atoms/molecules/organisms; overlay/service migration pending |
| **#13 / D4** | [`013-kit-adoption-boundary.md`](./013-kit-adoption-boundary.md) | [`0009`](../adr/0009-kit-facade-injection-boundary.md) | **contracts landed** (`common/src/main/ets/kit/`); 实际 Kit 资源接入延后 (2026-09-06) |

## P0 tickets without spec

| Ticket | Status |
|--------|--------|
| **#1** (doc expiry) | meta — not a refactor, just self-referential cleanup |

## Implementation status (2026-09-06)

Done:
- **#4** Dispatcher single-entry — landed with D2
- **#5** LlmClient consolidation — 单一 `call(request)`, 真 SSE 流式, 死路已删
- **#9** LlmConfig throw-on-silent-override — TDD
- **D2 / spec 011** end-to-end — CaptureGraph + 5 nodes + conditional persist edge, Dispatcher 旧 API 已删

Remaining (recommended order):
1. **#3** KnowledgeModel real decomposition — façades exist; move the logic out of KnowledgeModel
2. **#7** AgentChatService decomposition — 3 atomic PRs, 802-LOC class
3. **#10** mcp → tools rename — git mv, ~3 import lines

After all of these, the architecture matches ADR intent:
- ✅ Dispatcher has 1 public method
- ✅ LlmClient has 1 public method (call + adapters)
- 🟡 KnowledgeModel replaced by 3 services (façade stage done, real split pending)
- ⬜ AgentChatService is a thin facade
- ⬜ mcp/ directory doesn't exist

## How to read a spec

Each spec has these sections:

1. **Why this ticket** — context, the problem, the gap
2. **What we will build** — the new shape (types, classes, signatures)
3. **Public surface change** — what's breaking, what isn't
4. **Migration** — atomic PR sequence, file moves
5. **Test plan (TDD)** — what tests to write
6. **Reversibility** — how hard to undo
7. **Acceptance criteria** — explicit checklist
8. **Sequence** — concrete commit list
9. **Out of scope** — explicit non-goals

## Conventions in these specs

- **Atomic PRs only** — each commit is revertable
- **TDD red→green→refactor** — test first, then implementation
- **TDD at the AST level** — when feasible, write Node tests that parse the .ets file's AST and assert structure (sees tests run in the arkts-lint framework, not in DevEco)
- **No new ADRs** — every spec is derived from an existing ADR (or marked "implicit" when the ADR is the same philosophy applied to a sibling class)
- **No global renames** — each spec stays local to its ticket scope

## Cross-references

- [`docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md`](../legacy/mindtrace/architecture/audit-full-2026-09-01.md) — original audit (archived)
- [`docs/legacy/mindtrace/architecture/deep-dive-2026-09-01.md`](../legacy/mindtrace/architecture/deep-dive-2026-09-01.md) — 7 largest files analyzed (archived)
- [`docs/adr/`](../adr/) — Architecture Decision Records (the "why")
- [`docs/specs/`](./) — this directory (the "what" + "how")
- [`CONTEXT.md`](../../CONTEXT.md) — project glossary
- [`AGENTS.md`](../../AGENTS.md) — agent entry point
- [`.github/workflows/arkts-lint.yml`](../../.github/workflows/arkts-lint.yml) — CI guardrail
