# 0012 — OpenAI-compatible tool-calling protocol; ToolRegistry lives in `common/`, read-only tools first

The audit's F1 finding ([agent-tools inventory](../architecture/agent-tools-inventory-2026-09-06.md)) showed the LLM layer cannot express tool calls: `LlmRequestBody` has no `tools`/`tool_choice`, and `LlmClient` never parses `tool_calls` — so the `tools/` slot reserved by [ADR-0010](./0010-mcp-tools-semantics.md) has no calling protocol to plug into. We adopt the OpenAI-compatible function-calling protocol fields (all optional, wire-compatible additions to `LlmTypes`), put the `ToolRegistry` and the `AgentTool` interface in **`common`** (reachable by both the `agents` pipeline and the `skill/` HSP — [ADR-0011](./0011-skill-xiaoyi-reservation.md)), and gate the first batch of tools to **read-only**. Research basis: [agent-toolkit-and-skill-dispatch-2026-09-06](../research/agent-toolkit-and-skill-dispatch-2026-09-06.md) — on-device system LLMs do not exist on phones at API 24, so the cloud OpenAI-compatible route is the only tool-calling channel; reference shapes are the Vercel AI SDK tool loop and LangGraph's prebuilt ToolNode (design only, no dependency — consistent with [ADR-0008](./0008-capturegraph-self-built-runtime.md)).

## Status

`accepted` (2026-09-06); implementation tracked by [spec 014](../specs/014-tool-calling-protocol.md)

## Considered Options

1. **Protocol fields in `LlmTypes` + `ToolRegistry` in `common` + read-only first** *(chosen)* — backward-compatible (every new field optional), one tool surface serving two callers (in-app LLM loop, future `skill/` IntentRouter), zero write-path risk during the competition window.
2. **Registry in `entry`** — rejected: `skill/` (HSP) cannot import `entry` (HAP), which would fork the tool surface and defeat the unified-surface goal.
3. **Write tools now** — rejected: three AI-triggered write paths already exist with inconsistent gating (inventory F2); adding LLM-initiated writes before that unification would compound the risk. Write tools are a post-competition phase.
4. **Wait for a framework** (LangGraph.js etc.) — rejected by [ADR-0008](./0008-capturegraph-self-built-runtime.md) and re-confirmed by the 2026-09 research: no ArkTS-targeting runtime exists; the loop is ~1 interface + ~100 LOC.

## Consequences

- **Chosen (1)**: `ChatMessage.role` gains `'tool'` and `ChatMessage` gains optional `tool_calls` (the loop-back assistant message needs somewhere to carry them, `content:''`); `LlmRequestBody`/`LlmCallRequest` gain optional `tools`/`tool_choice`; `LlmResponseChoice.message` gains optional `tool_calls`; `LlmCallResult` gains optional `toolCalls` (filled by `extractToolCalls`, gated on `message.tool_calls` presence — not `finish_reason`, which varies across OpenAI-compatible endpoints); `ToolLoop` consumes the existing `LlmCaller` seam (mockable, same pattern as `LlmGuard`); `LlmErrorKind` gains `'TOOL_LOOP_MAX_STEPS'`. Requests without tools stay byte-equivalent to today.
- `AgentTool` implementations in this spec are read-only queries over `DatabaseHelper`'s RDB store; they run in `common` and must not import `entry`. The store is reached via `DatabaseHelper.getStore()` (null → `ok:false 'store not ready'`; context/init ownership stays with the entry composition root). Caveat: table schemas (`knowledge_unit` etc.) are currently declared by `entry` DAOs — P1 tools must either lift shared schema constants into `common` or cite NoteDao as the schema source-of-truth, to prevent drift.
- `OcrTool` stays where it is (`mcp/`, MCP-semantic) — registering it as an `AgentTool` is a possible follow-up, not part of this decision.
- When the competition window closes, write tools should land together with the F2 write-path unification (single validation gate), not before.

## Reversibility

**Medium** — the protocol fields are additive and can be dropped without breaking callers; the registry interface may move behind `Dispatcher` if a real framework ever targets ArkTS (same mechanical-swap clause as ADR-0008).

## Related

- [ADR-0004](./0004-llm-call-layer-consolidation.md) — the single-`call()` surface this protocol extends
- [ADR-0008](./0008-capturegraph-self-built-runtime.md) — design-over-runtime philosophy the tool loop follows
- [ADR-0010](./0010-mcp-tools-semantics.md) — `tools/` taxonomy; [ADR-0011](./0011-skill-xiaoyi-reservation.md) — the second consumer of the registry
- [spec 014](../specs/014-tool-calling-protocol.md) — implementation spec
