# 0008 — Agent workflows: the LangGraph model, implemented natively in ArkTS

The Dispatcher pipeline (Capture → Classify → Structure → TruthCheck → Persist) needed explicit graph orchestration (D1 research: [agent framework comparison](../research/agent-framework-comparison-2026-09-02.md)). We **adopted LangGraph as the project's primary Agent workflow architecture design root** — its model and vocabulary (Node, Edge, State, conditional edges, `START`/`END`, `addNode` / `addEdge` / `addConditionalEdge` / `run`) are canonical for every Agent workflow that requires orchestration. `agents/src/main/ets/graph/CaptureGraph.ets` is the first concrete ArkTS workflow implementation, not the name or full scope of the architecture. What was rejected is only the *runtime dependency* (Python sidecar / langgraphjs), never the LangGraph workflow design itself.

## Status

`accepted` (2026-09-05, D2; scope clarified 2026-09-09)

## Considered Options

1. **Adopt the LangGraph workflow model, implement it natively in ArkTS** *(chosen)* — LangGraph's graph model becomes the canonical design vocabulary for Capture, conversation, tool-calling and skill intent workflows. `CaptureGraph` is the first concrete implementation; later workflows reuse the architecture and shared production capabilities without duplicating Capture business logic.
2. **Python LangGraph sidecar** — the real LangGraph runtime, but adds an out-of-process service, IPC serialization, and deployment complexity to a single-device HAP deliverable. *(Rejected as a runtime dependency; the LangGraph design itself is adopted.)*
3. **langgraphjs** — brings the LangGraph API surface but requires the Node runtime and dynamic-language features that ArkTS strict mode forbids; not embeddable in a HAP.

## Consequences

- **Chosen (1)**: the Capture workflow is built per dispatch (`buildGraph`); `AgentState` is its typed State, copied field-by-field because ArkTS forbids spread. The workflow vocabulary follows LangGraph naming (`addNode` / `addEdge` / `addConditionalEdge` / `run`, `START`/`END`; universal definitions in `docs/agents/agent-glossary.md`). Persistence is injected via `DispatchOptions.dao` (`NoteDaoAdapter`), so `agents/` never depends on `entry`.
- Capture, conversation, tool-calling and skill intent are separate domain workflows under one architecture. They may have different typed State schemas and Node sets; they are not separate backends and must share each production capability through its single owner (`Dispatcher`, `LlmClient`, `ToolRegistry`, DAO adapters and Kit facades).
- A workflow may invoke another workflow only through its stable entry. Conversation note generation delegates to `Dispatcher`; it must not copy Capture nodes. Migration must not use old/new workflow runtimes in parallel, dual reads/writes or production fallback.
- Explicit non-goals (spec 011 §3): no Checkpoint, no HITL, no Subgraph. Revisit only when a real requirement appears — no dead scaffolding. This does not limit LangGraph to Capture; it limits which workflow features are currently justified.
- **AI failure throws `CaptureGraphError` and short-circuits; no fallback KnowledgeUnit is generated** (spec 011 §9). Placeholder data once leaked into the user's galaxy (ticket #16); failing loudly is the policy.

## Reversibility

**Medium**. The runtime is ~100 LOC with no external deps; replacing it (or upgrading to a real framework, if one ever targets ArkTS) is a mechanical swap behind `Dispatcher.buildGraph`. The node contracts (`CaptureNode`) survive such a swap.

## Related

- [0006 — KnowledgeModel decomposition](./0006-knowledge-model-decomposition-plan.md) — the graph nodes wrap these collaborators
- [spec 011 — CaptureGraph ArkTS refactor](../specs/011-capturegraph-arkts-refactor.md)
- [spec 018 — Agent workflow architecture](../specs/018-agent-workflow-architecture.md)
- [D2 teaching doc — 踩坑与经验](../agents/d2-capturegraph-teaching-2026-09-05.md)
