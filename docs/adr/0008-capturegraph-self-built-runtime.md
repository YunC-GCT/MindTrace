# 0008 — Self-built CaptureGraph runtime instead of LangGraph / Python sidecar

The Dispatcher pipeline (Capture → Classify → Structure → TruthCheck → Persist) needed explicit graph orchestration (D1 research: [agent framework comparison](../research/agent-framework-comparison-2026-09-02.md)). We decided to build a lightweight LangGraph-style runtime in ArkTS — `agents/src/main/ets/graph/CaptureGraph.ets` (`addNode` / `addEdge` / `addConditionalEdge` / `run`, `START`/`END` sentinels, conditional persist edge, error short-circuit) — rather than adopting LangGraph.

## Status

`accepted` (2026-09-05, D2)

## Considered Options

1. **Self-built CaptureGraph in ArkTS** *(chosen)* — mirrors the LangGraph mental model (nodes take state, return state; conditional edges) with zero dependencies; fully lintable and AST-testable inside the repo's own ArkTS constraints.
2. **Python LangGraph sidecar** — richest ecosystem, but adds an out-of-process service, IPC serialization, and deployment complexity to a single-device HAP deliverable.
3. **langgraphjs** — requires the Node runtime and dynamic-language features that ArkTS strict mode forbids; not embeddable in a HAP.

## Consequences

- **Chosen (1)**: the graph is built per dispatch (`buildGraph`); `AgentState` is a plain typed object copied field-by-field (ArkTS forbids spread). Persistence is injected via `DispatchOptions.dao` (`NoteDaoAdapter`), so `agents/` never depends on `entry`.
- Explicit non-goals (spec 011 §3): no Checkpoint, no HITL, no Subgraph. Revisit only when a real requirement appears — no dead scaffolding.
- **AI failure throws `CaptureGraphError` and short-circuits; no fallback KnowledgeUnit is generated** (spec 011 §9). Placeholder data once leaked into the user's galaxy (ticket #16); failing loudly is the policy.

## Reversibility

**Medium**. The runtime is ~100 LOC with no external deps; replacing it (or upgrading to a real framework, if one ever targets ArkTS) is a mechanical swap behind `Dispatcher.buildGraph`. The node contracts (`CaptureNode`) survive such a swap.

## Related

- [0006 — KnowledgeModel decomposition](./0006-knowledge-model-decomposition-plan.md) — the graph nodes wrap these collaborators
- [spec 011 — CaptureGraph ArkTS refactor](../specs/011-capturegraph-arkts-refactor.md)
- [D2 teaching doc — 踩坑与经验](../agents/d2-capturegraph-teaching-2026-09-05.md)
