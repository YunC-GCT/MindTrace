# 0008 — Agent workflows: the LangGraph model, implemented natively in ArkTS

The Dispatcher pipeline (Capture → Classify → Structure → TruthCheck → Persist) needed explicit graph orchestration (D1 research: agent framework comparison, 2026-09-02 — removed in the 2026-10-18 corpus purge). We **adopted LangGraph as the project's primary Agent workflow architecture design root** — its model and vocabulary (Node, Edge, State, conditional edges, `START`/`END`, `addNode` / `addEdge` / `addConditionalEdge` / `run`) are canonical for every Agent workflow that requires orchestration. `agents/src/main/ets/graph/CaptureGraph.ets` is the first concrete ArkTS workflow implementation, not the name or full scope of the architecture. What was rejected is only the *runtime dependency* (Python sidecar / langgraphjs), never the LangGraph workflow design itself.

## Status

`accepted` (2026-09-05, D2; scope clarified 2026-09-09; Subgraph scope revised 2026-10-27)

## Considered Options

1. **Adopt the LangGraph workflow model, implement it natively in ArkTS** *(chosen)* — LangGraph's graph model becomes the canonical design vocabulary for Capture, conversation, tool-calling and skill intent workflows. `CaptureGraph` is the first concrete implementation; later workflows reuse the architecture and shared production capabilities without duplicating Capture business logic.
2. **Python LangGraph sidecar** — the real LangGraph runtime, but adds an out-of-process service, IPC serialization, and deployment complexity to a single-device HAP deliverable. *(Rejected as a runtime dependency; the LangGraph design itself is adopted.)*
3. **langgraphjs** — brings the LangGraph API surface but requires the Node runtime and dynamic-language features that ArkTS strict mode forbids; not embeddable in a HAP.

## Consequences

- **Chosen (1)**: the Capture workflow is built per dispatch (`buildGraph`); `AgentState` is its typed State, copied field-by-field because ArkTS forbids spread. The workflow vocabulary follows LangGraph naming (`addNode` / `addEdge` / `addConditionalEdge` / `run`, `START`/`END`; universal definitions in `docs/agents/agent-glossary.md`). Persistence is injected via `DispatchOptions.dao` (`NoteDaoAdapter`), so `agents/` never depends on `entry`.
- Capture, conversation, tool-calling and skill intent are separate domain workflows under one architecture. They may have different typed State schemas and Node sets; they are not separate backends and must share each production capability through its single owner (`Dispatcher`, `LlmClient`, `ToolRegistry`, DAO adapters and Kit facades).
- A workflow may invoke another workflow only through its stable entry. Conversation note generation delegates to `Dispatcher`; it must not copy Capture nodes. Migration must not use old/new workflow runtimes in parallel, dual reads/writes or production fallback.
- Explicit non-goals (spec 011 §3): no runtime Checkpoint, no in-graph HITL, **Subgraph 有限放开**（2026-10-27 修订，见下节「Subgraph 放开范围」）. Revisit only when a real requirement appears — no dead scaffolding. This does not limit LangGraph to Capture; it limits which workflow features are currently justified.
- **AI failure throws `CaptureGraphError` and short-circuits; no fallback KnowledgeUnit is generated** (spec 011 §9). Placeholder data once leaked into the user's galaxy (ticket #16); failing loudly is the policy.

## Subgraph 放开范围（2026-10-27 修订）

原非目标「no Checkpoint, no HITL, no Subgraph」修订为：**runtime Checkpoint 与图内 HITL 继续禁止，Subgraph 有限放开**。放开的是「子图作为节点组合」这一结构能力，不是新的 runtime，也不改变本 ADR 的主结论（LangGraph 模型 + 自建 ArkTS 执行器，无 Python sidecar / langgraphjs 依赖）。

**允许（必须同时满足）：**

- **子图作为节点接入父图**：父图用普通节点调 `child.run(mappedState)`，子图是父图的一个节点，不新增第二套调度器。
- **父子共享同一个 `CancellationToken` 与 deadline**：取消与超时是同一份，不在子图边界新建 token，也不重置 deadline。
- **共享 `runId` / `parentRunId`**：run 身份只在父图创建，子图事件带 `parentRunId`；业务级 checkpoint 归属同一个 run。
- **子图的领域错误穿边界不被压成 `Error`**：`CaptureGraphError` / `GenerationJsonError` / `LlmError` 的 `kind` 与 `retriable` 必须保留，父图不得统一改写。现状 `agents/src/main/ets/graph/CaptureGraph.ets:41-43` 会把节点内异常压成 `NODE_ERROR`、`retriable` 固定 `false`，迁移时必须先区分领域错误与未知错误。
- **节点预算父子累计**：父图的 `maxNodeRuns` 计入子图消耗。现状 `common/src/main/ets/workflow/StateGraph.ets:55-75` 每次 `run` 重置 `nodeRuns`（默认 128），父子各算各的；新增的子图节点必须显式传递剩余预算。

**禁止：**

- **runtime checkpoint**（图内序列化状态并恢复）：checkpoint 仍是业务级草稿 / 审批（§17.5；终态语义见 [ADR-0019](./0019-note-command-and-outcome.md)）。
- **图内 HITL / `interrupt()`**：确认在图外，预览 → 用户确认 → 提交仍是三次独立调用。
- **子图伪装成 Tool 走 ToolLoop**：ToolLoop 的重试与输出语义是工具结果，不是图状态；子图只能作为图节点。
- **新旧两套 runtime 并行或长期 feature flag**：迁移必须在同一切片删旧实现，不允许双跑兜底。

## Reversibility

**Medium**. The runtime is ~100 LOC with no external deps; replacing it (or upgrading to a real framework, if one ever targets ArkTS) is a mechanical swap behind `Dispatcher.buildGraph`. The node contracts (`CaptureNode`) survive such a swap.

## Related

- [0006 — KnowledgeModel decomposition](./0006-knowledge-model-decomposition-plan.md) — the graph nodes wrap these collaborators
- [0019 — NoteCommand / NoteOutcome](./0019-note-command-and-outcome.md) — command/terminal-state semantics; subgraph errors and cancellation must preserve these outcomes
- [spec 011 — CaptureGraph ArkTS refactor](../specs/011-capturegraph-arkts-refactor.md)
- [spec 018 — Agent workflow architecture](../specs/018-agent-workflow-architecture.md)
- [D2 teaching doc — 踩坑与经验](../agents/d2-capturegraph-teaching-2026-09-05.md)
