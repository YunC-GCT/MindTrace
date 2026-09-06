# Architecture Decision Records

This directory holds ADRs that capture **why** the project is shaped a certain way, not just what
it does. Every ADR documents one decision: the context, the alternatives considered, the
choice made, and the reversibility.

## Index

| # | Decision | Status |
|---|-----------|--------|
| [0001](./0001-layer-boundaries-in-5-module-arkts-app.md) | Allow direct cross-layer imports (`entry/services/` → `agents/`) for now; add interface layer when 5+ services import `agents/` | accepted |
| [0002](./0002-agent-terminology-disambiguation.md) | Keep code names `Agent*`; migrate user-facing copy to "AI 助手"; document disambiguation in CONTEXT.md | accepted |
| [0003](./0003-dispatcher-single-entry-design.md) | Collapse 3 public methods (`analyze` + `dispatch` + `routeDispatch`) to one `dispatch(req, opts?)`; `analyze` becomes a private step | accepted |
| [0004](./0004-llm-call-layer-consolidation.md) | Collapse 3 call methods to one `call(opts)` with adapter selection via `opts.stream`; remove `callSseTokens` (dead path) | accepted |
| [0005](./0005-mcp-to-tools-rename.md) | Rename `agents/mcp/tools/` to `agents/tools/`; `mcp` is misleading (no MCP server runs) | accepted |
| [0006](./0006-knowledge-model-decomposition-plan.md) | Split 870-LOC god class into 3 services (PromptBuilder + TruthCheckService + StructureService); Dispatcher orchestrates | accepted |
| [0007](./0007-test-baseline-12-unit-tests.md) | Adopt audit's 12-test baseline (4+4+2+2 across 4 units) as the test floor | accepted |
| [0008](./0008-capturegraph-self-built-runtime.md) | Adopt the LangGraph model as the canonical design root, implemented natively in ArkTS (`CaptureGraph`) — no Python sidecar / langgraphjs runtime dependency; AI failure throws, no fallback KnowledgeUnit | accepted |
| [0009](./0009-kit-facade-injection-boundary.md) | Kit capability seam: pipeline consumes kits via `common/kit/` facade contracts, implementations injected at composition root — a seam, not an import ban (DevEco template modules import kits directly); kit integration deferred | accepted |

## How to write a new ADR

Per `~/.agents/skills/domain-modeling/ADR-FORMAT.md`, ADRs are minimal:

```md
# {Short title of the decision}

{1-3 sentences: what's the context, what did we decide, and why.}
```

Optional sections (only when they add value):
- **Status** frontmatter (`proposed | accepted | deprecated | superseded by ADR-NNNN`)
- **Considered Options** — only when rejected alternatives are worth remembering
- **Consequences** — only when non-obvious downstream effects need to be called out

## When to create an ADR

**All three must be true**:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If a decision is easy to reverse, skip the ADR — you'll just reverse it. If it's not surprising, nobody will wonder why. If there was no real alternative, there's nothing to record beyond "we did the obvious thing."

## What qualifies

- **Architectural shape.** "We're using a monorepo." "The pipeline is orchestrated, the helpers are pure."
- **Integration patterns between layers.** "Services communicate via direct method calls, not events."
- **Technology choices that carry lock-in.** Database, message bus, auth provider, deployment target.
- **Boundary and scope decisions.** "Fixture data is debug-only; production never sees preview content."
- **Deliberate deviations from the obvious path.** "We use V1 lint even though V0.3 is the recommendation, because V1 is what was in place when CI was wired."
- **Constraints not visible in the code.** "We can't use async here because DevEco Studio's ArkTS runtime doesn't support top-level await."
- **Rejected alternatives when the rejection is non-obvious.** If you considered GraphQL and picked REST for subtle reasons, record it.

## Relationship to other docs

- **`docs/specs/`** — implementation specs derived from ADRs (the "what" + "how")
- **`docs/style/arkts-1.1.md`** — ArkTS rules (technical, not architectural decisions)
- **[`docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md`](../legacy/mindtrace/architecture/audit-full-2026-09-01.md)** — original audit (2026-09-01, archived) that surfaced the design issues these ADRs resolve
- **`CONTEXT.md`** — project glossary; ADRs reference terms defined there

## Numbering

ADRs use 4-digit sequential numbering: `0001-slug.md`, `0002-slug.md`, etc. New ADRs get
the next available number. Slugs are kebab-case short descriptions.

## When ADRs are wrong

ADRs that turn out to be wrong are not deleted; they are marked `superseded by ADR-NNNN` and
the new ADR links to the old one. The git history preserves the original reasoning.
