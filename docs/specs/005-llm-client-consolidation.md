# Ticket #5 — LLMClient consolidation

> **Status**: implemented (2026-09-06 — 单一 `call(request)` 入口, `callSseTokens` 死路删除, 聊天走真 SSE 流式)
> **Source ADR**: [`../adr/0004-llm-call-layer-consolidation.md`](../adr/0004-llm-call-layer-consolidation.md)
> **Files affected**: `common/src/main/ets/llm/LlmClient.ets` (change); `agents/src/main/ets/agents/TypeClassifier.ets`, `agents/src/main/ets/agents/KnowledgeModel.ets`, `entry/src/main/ets/services/AgentChatService.ets` (migrate callers)
> **Test files**: `scripts/arkts-lint/tests/llm-client-api.test.mjs` (new, TDD), existing tests in affected modules

## Why this ticket

`LlmClient` exposes 3 public methods today:
- `call(messages, opts)` — JSON response via `request()` + manual JSON parse
- `callStream(messages, onDelta, opts)` — true SSE via `requestInStream()` + `on('dataReceive')`
- `callSseTokens(messages, opts)` — pseudo-stream (no `requestInStream`); a workaround for an old limitation

The 3 paths share 90% of their code (URL, headers, body, error mapping) but expose 3 different call surfaces. The 3rd path (`callSseTokens`) is the workaround path; per the audit, no production caller currently needs streaming behavior that `callSseTokens` actually provides (real SSE is what `callStream` does). The artifact of the 3-way split is that callers must pick the right method at the call site, and that future LLM transport (e.g. Anthropic prompt caching, OpenAI's new stream format) requires adding a 4th method.

## What we will build

A single public API `call(opts)` with two adapters selected by the `stream` flag:

```ts
interface CallOptions {
  messages: ChatMessage[];
  // 0 = no reasoning (default), 1 = thinking-mode if model supports
  reasoning?: 0 | 1;
  // Stream the response. Default false.
  stream?: boolean;
  // Stream callback (only used when stream=true). One chunk per token.
  onDelta?: (delta: string, kind: 'reasoning' | 'content') => void;
  // Model override; default from LlmConfig
  model?: string;
  // Sampling params
  temperature?: number;
  maxTokens?: number;
  timeoutMs?: number;
}

interface CallResult {
  // For stream=false: the full text
  // For stream=true: undefined (caller should use onDelta instead)
  text?: string;
  // Whether the call was streaming (caller info)
  streamed: boolean;
  // Provider-specific metadata; always present, content depends on stream
  meta?: { /* e.g. usage, finishReason */ };
}

class LlmClient {
  async call(opts: CallOptions): Promise<CallResult>;
  // (Internal adapters; not exported)
}
```

## Public surface change (breaking)

The 3 current methods are **removed** in this ticket. Callers must migrate. The migration is small (see "Migration" below) and the test suite catches any missed call site at compile time (TypeScript) and at runtime (existing tests in each caller module).

**Why breaking, not deprecating**: per ADR-0004, the 3-way split is accidental, not architectural. A deprecation period would keep the wrong surface around. One PR, one rename, one migration.

## Out of scope (intentionally)

- LlmGuard integration with the new `call` (currently LlmGuard wraps `call` for JSON validation; this ticket does not touch that path)
- Switching from `http.RequestModule` to `@kit.NetworkKit.fetch` (separate concern)
- Adding a 3rd adapter (Anthropic, Gemini, etc.); the adapter pattern is the seam for future expansion

## Migration (small, mechanical)

```ts
// TypeClassifier: was
const raw = await this.llm.call(messages, { /* ... */ });
// now
const r = await this.llm.call({ messages, /* ... */ });
const text = r.text!;

// KnowledgeModel: was
const raw = await this.llm.call(messages, opts);
// now
const r = await this.llm.call({ messages, ...opts });
const text = r.text!;

// AgentChatService.realReplyStream: was
await this.llm.callStream(messages, (delta) => onDelta(delta), opts);
// now
await this.llm.call({
  messages,
  stream: true,
  onDelta: (delta) => onDelta(delta),
  ...opts
});
```

3 callers, ~6 lines of diff each.

## Test plan (TDD)

**Red → Green → Refactor** (per `/tdd` skill):

1. Write `scripts/arkts-lint/tests/llm-client-api.test.mjs` that parses `LlmClient.ets` AST and asserts:
   - exactly **one** public async method named `call` exists (the 3 old methods do not exist)
   - the method's first parameter is a typed object (CallOptions)
   - CallOptions type has a `stream?: boolean` field
2. Run test → **fails** (current code has 3 methods)
3. Refactor `LlmClient.ets` to expose `call(opts)` with 2 adapters
4. Update the 3 callers
5. Run test → **passes**
6. Run all 65 existing arkts-lint tests → must still pass (regression)

## Reversibility

Per ADR-0004: **high** for restoring 3-way split (additive). **Hard** for the new `call(opts)` API (callers' argument shape changes). If rollback is needed, `git revert` brings the 3-way split back. The `opts` shape can be retro-fitted into the old 3 methods via overloads.

## Acceptance criteria

- [ ] `node scripts/arkts-lint/index.mjs --quiet` shows 0 errors, ≤ 200 warnings (current: 253)
- [ ] `node --test scripts/arkts-lint/tests/llm-client-api.test.mjs` passes
- [ ] `node --test scripts/arkts-lint/tests/*.test.mjs` all 65+ pass
- [ ] All 3 callers (`TypeClassifier`, `KnowledgeModel`, `AgentChatService`) compile and run
- [ ] No change in observable behavior: same response shape for non-streaming, same per-token callbacks for streaming

## Sequence (suggested PRs)

To keep this PR reviewable, split into 3 atomic commits:

1. **`refactor(llm): collapse 3 call methods to 1 call(opts)`** — `LlmClient.ets` only, TDD red→green. New API live, old APIs still work (compat shim).
2. **`refactor(callers): migrate TypeClassifier + KnowledgeModel to new call(opts)`** — drop the JSON-only path. Tests must pass.
3. **`refactor(chat): migrate AgentChatService.realReplyStream to call(opts) + stream:true`** — drop the dual path. Tests must pass.
4. **`refactor(llm): remove compat shim, old methods deleted`** — breaking. CI must stay green.

Each commit is self-contained and reverts cleanly.

## Open questions (none blocking)

- **Q: should the 12-test baseline (audit §8 Q8) be lifted by this ticket?**
  A: no. This ticket is the *first* user of the new `call(opts)` shape. The 12-test baseline (Phase 4 ticket #13) is a separate work item: it adds 12 unit tests for `StructureService`/`TruthCheckService`/`PromptBuilder` (per ADR-0006). Different scope.

- **Q: what about `LlmGuard`?**
  A: unchanged. `LlmGuard` wraps `call()` (today's JSON path) for JSON validation. After this ticket, `LlmGuard.callJsonWithRetry(messages, opts)` should call `client.call({ messages, ...opts })` internally. That refactor is also out of scope here (tracked separately if needed).
