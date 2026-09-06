# 0008 — CaptureGraph: the LangGraph model, implemented natively in ArkTS

The Dispatcher pipeline (Capture → Classify → Structure → TruthCheck → Persist) needed explicit graph orchestration (D1 research: [agent framework comparison](../research/agent-framework-comparison-2026-09-02.md)). We **adopted LangGraph as the project's primary design root** — its model and vocabulary (Node, Edge, State, conditional edges, `START`/`END`, `addNode` / `addEdge` / `addConditionalEdge` / `run`) are the canonical naming and design basis for the pipeline — and implemented it **natively in ArkTS** as `agents/src/main/ets/graph/CaptureGraph.ets`. What was rejected is only the *runtime dependency* (Python sidecar / langgraphjs), never the LangGraph design itself.

## Status

`accepted` (2026-09-05, D2)

## Considered Options

1. **Adopt the LangGraph model, implement natively in ArkTS (`CaptureGraph`)** *(chosen)* — LangGraph's graph model becomes the canonical design vocabulary; the implementation is ~100 LOC of constraint-compliant ArkTS, zero dependencies, fully lintable and AST-testable.
2. **Python LangGraph sidecar** — the real LangGraph runtime, but adds an out-of-process service, IPC serialization, and deployment complexity to a single-device HAP deliverable. *(Rejected as a runtime dependency; the LangGraph design itself is adopted.)*
3. **langgraphjs** — brings the LangGraph API surface but requires the Node runtime and dynamic-language features that ArkTS strict mode forbids; not embeddable in a HAP.

## Consequences

- **Chosen (1)**: the graph is built per dispatch (`buildGraph`); `AgentState` is a plain typed object copied field-by-field (ArkTS forbids spread). The graph vocabulary follows LangGraph naming (`addNode` / `addEdge` / `addConditionalEdge` / `run`, `START`/`END`; universal definitions in `docs/agents/agent-glossary.md`). Persistence is injected via `DispatchOptions.dao` (`NoteDaoAdapter`), so `agents/` never depends on `entry`.
- Explicit non-goals (spec 011 §3): no Checkpoint, no HITL, no Subgraph. Revisit only when a real requirement appears — no dead scaffolding.
- **AI failure throws `CaptureGraphError` and short-circuits; no fallback KnowledgeUnit is generated** (spec 011 §9). Placeholder data once leaked into the user's galaxy (ticket #16); failing loudly is the policy.

## Reversibility

**Medium**. The runtime is ~100 LOC with no external deps; replacing it (or upgrading to a real framework, if one ever targets ArkTS) is a mechanical swap behind `Dispatcher.buildGraph`. The node contracts (`CaptureNode`) survive such a swap.

## Related

- [0006 — KnowledgeModel decomposition](./0006-knowledge-model-decomposition-plan.md) — the graph nodes wrap these collaborators
- [spec 011 — CaptureGraph ArkTS refactor](../specs/011-capturegraph-arkts-refactor.md)
- [D2 teaching doc — 踩坑与经验](../agents/d2-capturegraph-teaching-2026-09-05.md)
