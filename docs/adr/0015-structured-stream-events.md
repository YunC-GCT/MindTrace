# 0015 — Structured streaming events (`StreamEvent`) replace the `(delta, kind)` callback

The streaming path delivered deltas as `(delta: string, kind: 'reasoning' | 'content')` (LlmTypes.ets:133), which cannot carry tool-call payloads and forced the 2026-09-07 deepseek-v4-pro fix (LlmClient.ets:519-521) to re-emit `reasoning_content` disguised as `content` — duplicating thinking text into the final answer. We replace it with a single structured event object `{type, ...payload}`, `type ∈ thinking | text | tool_call | tool_result`, defined in full now but with only `thinking`/`text` emitted in P0 — `tool_call`/`tool_result` are the reserved seats for the future SSE tool loop (spec 014 explicitly excluded SSE+tool-loop). Research basis: [agent-reasoning-process-display-research-2026-09-11](../research/agent-reasoning-process-display-research-2026-09-11.md).

## Status

`accepted` (2026-09-11, grill session); implementation tracked by the P0 process-display spec (upcoming)

## Considered Options

1. **Structured event object, full 4-value union now** *(chosen)* — one breaking change across LlmTypes / LlmClient / ReplyService / ConversationWorkflow / AgentChatService / AgentFloatWindow instead of two; tool events need payloads (tool name / arguments / result) that a `(delta, kind)` pair cannot carry. Vercel AI SDK's TextStreamPart is the reference shape (single stream, typed parts).
2. **Extend the `kind` union to 4–5 values, keep the callback signature** — rejected: backward-compatible on paper, but P1 tool events would force a second full-chain signature change, and the fallback masquerade would survive.
3. **P0 defines only `thinking | text`, extend the union in P1** — rejected: extending a union re-triggers exhaustive-switch fixes across the same chain; defining all four seats now *is* the reservation.

## Consequences

- Terminology: event types use the task-brief vocabulary (`thinking` / `text`); the wire field stays `reasoning_content`; the UI word is 思考. Registered in `CONTEXT.md` as **StreamEvent**.
- The reasoning→content fallback (LlmClient.ets:519-521, the 2026-09-07 UI-blank fix) is **removed in the same change** — safe only because new consumers accept `thinking` events, so a thinking-only response lands in the process block instead of a blank UI. Deleting it before the protocol change re-creates the blank-UI bug; keeping it after preserves the duplication. Same-PR constraint.
- `AgentChatService.realReplyStream`'s `kind !== 'content'` filter (the reason the fallback existed) becomes a two-channel dispatch.
- `enableThinking` supply: wired through the existing `LlmConfig` persistence seat (`setEnableThinking`, previously zero callers), default `true`, no UI toggle (the decorative one was removed the same day — different concern).
- keyGen (AgentMessageList.ets:98): gains `reasoning.length` (in a pure-thinking phase the key never changed while content stayed empty, freezing the panel), drops `reasoningExpanded` (row-rebuild on toggle killed the `animateTo` fold animation).

## Reversibility

**Low** — the callback signature fans out to six files and the P1 tool events build on it; reverting means re-introducing the `(delta, kind)` pair and the fallback masquerade.

## Related

- [ADR-0004](./0004-llm-call-layer-consolidation.md) — the single-call surface this streaming path belongs to
- [ADR-0012](./0012-tool-calling-protocol.md) — the tool-calling protocol whose stream events `tool_call`/`tool_result` anticipate
- [Research](../research/agent-reasoning-process-display-research-2026-09-11.md) — the 14-decision-point basis
