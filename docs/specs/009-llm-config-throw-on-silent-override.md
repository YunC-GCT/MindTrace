# Ticket #9 — LlmConfig silent-override → throw

> **Status**: implemented (2026-09-06 · TDD; 进度以 [`index.md`](./index.md) 为准)
> **Source ADR**: implicit (defensive coding principle; matches ADR-0002 philosophy)
> **Files affected**: `common/src/main/ets/llm/LlmConfig.ets`

## Why this ticket

`LlmConfig.normalizeModel()` and `LlmConfig.normalizeEndpoint()` silently overwrite user input:

- If `model` contains `"v3"`, `"flash"`, `"deepseek-chat"`, `"deepseek-reasoner"`, `"r1"` → silently returns `DEFAULT_MODEL` (DeepSeek v4-pro)
- If `endpoint` contains `"siliconflow"` → silently returns `DEFAULT_ENDPOINT` (DeepSeek)

Per the audit, this is a **silent override** that makes debugging hard. The user sets up a config, then sees their model overridden with no indication. The audit flagged this as a security/UX concern (P0: "禁止再扩展").

The fix: instead of silently returning a default, **throw an `LlmError`** with a clear message that tells the user what was rejected and why.

## What we will build

Two new behaviors in `LlmConfig.normalizeModel` and `LlmConfig.normalizeEndpoint`:

```ts
// Before
normalizeModel(v: string): string {
  // ... keyword check ...
  if (matches) return DEFAULT_MODEL;  // silent override
  return v;
}

// After
normalizeModel(v: string): string {
  // ... keyword check ...
  if (matches) {
    throw new LlmError(
      `LlmConfig.normalizeModel: input "${v}" matches reserved keyword; ` +
      `use DEFAULT_MODEL or override normalizeModel() if this is intentional.`,
      'NORMALIZE_KEYWORD_REJECTED'
    );
  }
  return v;
}
```

Same shape for `normalizeEndpoint` with `'siliconflow'` check.

## Public surface change

**Breaking** for any caller relying on the silent fallback. The audit identifies the actual callers:

```bash
grep -rn "normalizeModel\|normalizeEndpoint" common/src/main/ets/llm/
```

Result: these helpers are called from `LlmClient` and `LlmOutputRules` (the only two real consumers). They both have explicit null-checks, so they will propagate the throw correctly.

If a future caller relies on the silent fallback, it gets a clear error instead of an unexpected default. The contract is now: **silently fail at the user input level is a bug; throw with context**.

## Test plan (TDD, Node AST-level + functional)

| Test | What it verifies |
|------|------------------|
| `normalizeModel("deepseek-v3-pro")` throws | reserved keyword triggers throw |
| `normalizeModel("claude-3-opus")` returns input | non-reserved input passes through |
| `normalizeModel("")` returns DEFAULT | empty input still gets default (not throw) |
| `normalizeModel(null)` returns DEFAULT | null still gets default (not throw) |
| `normalizeEndpoint("siliconflow.com/v1")` throws | reserved keyword triggers throw |
| `normalizeEndpoint("api.openai.com/v1")` returns input | non-reserved input passes through |

6 unit tests. Existing `LlmClient` / `LlmOutputRules` tests should also pass (no call site relies on the silent fallback).

## Reversibility

**Trivial** for the throwing path. The silent fallback is gone — if a user explicitly depended on it, the new behavior is: error or no-op depending on caller code. The throw is loud, so reversibility is just "revert the commit".

## Acceptance criteria

- [ ] `normalizeModel` with reserved keyword throws `LlmError` (not silently returns default)
- [ ] `normalizeEndpoint` with reserved keyword throws `LlmError`
- [ ] Non-reserved input passes through unchanged
- [ ] Empty/null input still returns default (the function has 2 paths: keyword-match + empty, only the first throws)
- [ ] All existing `LlmClient` and `LlmOutputRules` tests still pass
- [ ] The throw's `message` includes the rejected input and a hint on how to proceed
- [ ] `LlmError.kind` is a new enum value `NORMALIZE_KEYWORD_REJECTED`

## Sequence (single commit)

**`fix(llm-config): throw LlmError on reserved keyword override`**

1. Add the throw paths
2. Update 2 unit tests
3. Verify all `LlmClient` + `LlmOutputRules` tests pass
4. Update `LlmConfig` doc comment to call out the new error path

## Out of scope (intentionally)

- Rewriting `LlmConfig` entirely (the config object is fine; only the normalize helpers change)
- Adding a UI for users to see why their config was rejected (separate, larger work)
- Migrating to a different LLM provider (covered by ADR-0004 if relevant)
- The other 6 keyword checks in `LlmConfig.normalizeModel` (those are for "valid alternative spellings", not "silent override"; they should still pass through)
