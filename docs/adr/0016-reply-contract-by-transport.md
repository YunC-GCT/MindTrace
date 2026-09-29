# 0016 — Reply contract is scoped by transport: stream emits the Reply Body directly, complete keeps the JSON envelope

Both reply transports shared one prompt contract — strict JSON envelope (`{"answer": ...}`, `JSON_ONLY_RULES`) — but the streaming UI consumes Markdown body deltas and nothing between the SSE delta and the bubble decodes the envelope, so the float window rendered raw JSON, while envelope violations (single-backslash LaTeX, trailing prose) surfaced as `Bad escaped character` / `additional input` parse failures on the complete path (research: [llm-json-answer-parsing-2026-09-12](../research/llm-json-answer-parsing-2026-09-12.md)). Decision: the stream transport's prompt asks for the Reply Body (MM-MD-v1 Markdown, natural single-backslash LaTeX) directly — no envelope; the complete transport keeps the envelope + `LlmGuard` gate; `ReplyService` exclusively owns the envelope→body conversion, with the invariant that chat message content is always a Reply Body (terms registered in `CONTEXT.md`).

## Status

`accepted` (2026-09-12, grill session); implementation tracked by spec 020 (upcoming)

## Considered Options

1. **Transport-scoped contract** *(chosen)* — the stream prompt drops `JSON_ONLY_RULES`; complete keeps the envelope. This kills the entire JSON-escape error class on the stream path: raw Markdown `\frac` is exactly what KaTeX wants, and no `JSON.parse` sits between the SSE delta and the renderer. Smallest change; the demo path (float-window SSE chat) is the stream path.
2. **Single JSON contract + incremental envelope decoder in ReplyService** — rejected for now: SSE chunk boundaries can split escape sequences (`\\` halved across deltas), so incremental JSON parsing/unescaping must be hand-built in ArkTS, and first-token display needs buffering or typewriter replay. Recorded as the evolution path: if the stream ever needs structured fields (citations, confidence), build the decoder then — consumers stay body-speakers, so the migration adds a module without re-breaking the chain.
3. **Decode at render (ChatBubble strips the envelope)** — rejected: the conversion complexity spreads to three consumers (ChatBubble, session store, memory service); the seam belongs above them.

## Consequences

- **This is not dual-track.** One reply feature, two transport wire contracts; the app-internal contract is single — chat content is always a Reply Body. spec 018's single-backend constraint governs the workflow backend, which is untouched.
- The double-backslash LaTeX rule (`LlmOutputRules` #10) is a JSON-escape requirement; the stream prompt uses natural single-backslash LaTeX because there is no JSON layer to escape for. Keeping `\\frac` in raw Markdown would render a line break in KaTeX — the rule splits by transport together with the contract.
- The stream path gains a post-stream gate before persistence: ContentProtocol normalization without interception; `ok` becomes graded (recoverable issues normalize-and-pass, unrecoverable fail). Issue-marked bodies must be flagged so `AgentMemoryService` does not treat them as high-quality memory (spec 020).
- A one-shot envelope-strip heuristic at stream end (the model may still emit the envelope out of habit) reuses the LlmGuard extraction — bounded, no incremental parsing (spec 020).

## Risks (recorded per grill 2026-09-12)

- **Complete-path envelope necessity is under periodic re-review** — if LlmGuard extraction + retry proves low-value, complete can also go Markdown-direct with a different validation gate.
- **Issue-marked persistence may pollute cross-turn memory** — if amplification effects show up, re-evaluate the rejected alternative (post-stream validation failure → one non-stream retry) or add a retry gate.

## Reversibility

**Medium** — the stream prompt change is one prompt-builder edit and stream consumers already speak body; moving to the recorded evolution path (incremental decoder) adds a module without re-breaking consumers.

## Related

- [ADR-0004](./0004-llm-call-layer-consolidation.md) — the single call surface both transports live on
- [ADR-0015](./0015-structured-stream-events.md) — the StreamEvent channel the body deltas ride
- [spec 018 §7](../specs/018-agent-workflow-architecture.md) — single-backend constraint; why transport-scoped prompts are not a second backend
- [Research](../research/llm-json-answer-parsing-2026-09-12.md) — JSON escape / additional-input root-cause basis
