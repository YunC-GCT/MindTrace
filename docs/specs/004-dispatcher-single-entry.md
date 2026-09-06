# Ticket #4 — Dispatcher single entry

> **Status**: implemented (2026-09-05 · D2 落地; 进度以 [`index.md`](./index.md) 为准)
> **Source ADR**: [`../adr/0003-dispatcher-single-entry-design.md`](../adr/0003-dispatcher-single-entry-design.md)
> **Files affected**: `agents/src/main/ets/core/Dispatcher.ets` (change); `entry/src/main/ets/services/AgentChatService.ets`, `entry/src/main/ets/services/AiService.ets` (migrate callers)
> **Test files**: new `agents/src/test/Dispatcher.test.ets` (Hypium, behavior); new `scripts/arkts-lint/tests/dispatcher-api.test.mjs` (Node, AST-level shape)

## Why this ticket

`Dispatcher` has 3 public methods today:
- `analyze(req, context?)` — runs only the OCR + classification step, returns analysis
- `dispatch(req, context?)` — full pipeline, persists result
- `routeDispatch(req, context?)` — duplicate of `dispatch`, zero non-test callers (per audit)

The 3-way split is accidental, not architectural. `analyze` leaks a pipeline step as a public API; `routeDispatch` is dead code. Two of the three methods do essentially the same thing with different defaults.

## What we will build

A single public API `dispatch(req, opts?)` with internal `analyze` step:

```ts
interface DispatchOptions {
  // When false: do not persist the result. Default true.
  persist?: boolean;
  // When true: also include raw OCR text in the response. Default false.
  includeRawText?: boolean;
}

class Dispatcher {
  async dispatch(req: DispatchRequest, opts?: DispatchOptions): Promise<DispatchResult>;
  // The internal pipeline is no longer reachable from outside.
  // (internal helper methods stay private.)
}
```

The pipeline inside `dispatch` is unchanged: `analyze` step → `classify` step → `structure` step → optional `persist`. The difference vs today:
- `analyze()` was a public surface; now it's a private helper called by `dispatch`.
- `dispatch()` now takes `opts: { persist?: boolean }`. `persist: false` does what `analyze()` used to do (no DB write).

## Migration (small, mechanical)

```ts
// AiService.analyzeImage: was
const result = await dispatcher.analyze(req, context);
// now
const result = await dispatcher.dispatch(req, { persist: false, includeRawText: false });

// AgentChatService.captureReply: was
const result = await dispatcher.dispatch(req, context);
// now
const result = await dispatcher.dispatch(req);  // opts undefined → persist: true (default)
```

2 callers, 1 line of diff each.

## Test plan (TDD)

**Red → Green → Refactor** (per `/tdd` skill):

1. Write `scripts/arkts-lint/tests/dispatcher-api.test.mjs` (Node-side, AST):
   - parses `Dispatcher.ets`
   - asserts exactly **one** public async method named `dispatch` exists
   - asserts the 2 dead methods (`analyze`, `routeDispatch`) do NOT exist
   - asserts the method's signature is `dispatch(req, opts?)` with `opts` being an object literal with `persist?: boolean`
2. Run test → **fails** (current code has 3 methods)
3. Refactor `Dispatcher.ets`: collapse to one public method
4. Update 2 callers
5. Run test → **passes**
6. Run full arkts-lint suite (65+ tests) → must stay green (regression)
7. (Optional) `agents/src/test/Dispatcher.test.ets` (Hypium, behavior) — per ADR-0007, the 2 integration tests belong here

## Reversibility

**Low** for the surface change (additive, callers can be migrated back to `analyze` if needed). **High** for the design (the 3-way split was accidental; restoring it requires re-introducing `analyze` and `routeDispatch`).

## Acceptance criteria

- [ ] `node scripts/arkts-lint/index.mjs --quiet` shows 0 errors, warnings count ≤ 200 (currently 253)
- [ ] `node --test scripts/arkts-lint/tests/dispatcher-api.test.mjs` passes
- [ ] `node --test scripts/arkts-lint/tests/*.test.mjs` all 65+ pass
- [ ] All 2 callers compile and run

## Sequence (atomic commits)

1. **`refactor(dispatcher): collapse 3 methods to dispatch(req, opts?)`** — `Dispatcher.ets` only. TDD red → green. `analyze` and `routeDispatch` deleted.
2. **`refactor(services): migrate AiService to dispatch(req, {persist:false})`** — drop the `analyze` call.
3. **`refactor(services): migrate AgentChatService to dispatch(req)` (no opts)** — drop the `routeDispatch` alias.

Each commit reverts cleanly.

## Out of scope (intentionally)

- Changing the internal pipeline order or steps
- Adding a 4th public method (per ADR-0004, the LLM client consolidation is a separate ticket)
- Hypium behavior tests (covered by ADR-0007 / ticket #13)
