# Ticket #10 — Rename `agents/mcp/tools/` to `agents/tools/`

> **Status**: implemented (2026-09-06 — `agents/src/main/ets/tools/`, `mcp/` 已删除)
> **Source ADR**: [`../adr/0005-mcp-to-tools-rename.md`](../adr/0005-mcp-to-tools-rename.md)
> **Files affected**: `agents/src/main/ets/mcp/tools/` → `agents/src/main/ets/tools/` (rename); import paths in `agents/src/main/ets/Index.ets` and any consumers of `OcrTool`

## Why this ticket

`agents/src/main/ets/mcp/tools/` is named "mcp" (Model Context Protocol) but the project does not run an MCP server. `OcrTool.ets` is plain HTTP. The directory name is false advertising and confuses new contributors who wonder "where is the MCP server?".

Per ADR-0005: rename to `tools/`. One `git mv`, plus a search-replace of any `mcp` path references.

## What we will build

```
agents/src/main/ets/
├── mcp/tools/   →   tools/        # git mv
```

That's it. The contents of `OcrTool.ets` do not change. The interface it exports does not change. Only the path moves.

## Public surface change

None. The exports of `agents/src/main/ets/Index.ets` (or wherever `OcrTool` is re-exported) keep the same names. Only the **import path** changes:

```ts
// Before
import { OcrTool } from 'agents/src/main/ets/mcp/tools/OcrTool';
// After
import { OcrTool } from 'agents/src/main/ets/tools/OcrTool';
```

## Migration (mechanical, single commit)

```bash
# 1. Rename directory
git mv agents/src/main/ets/mcp agents/src/main/ets/tools

# 2. Find all import statements referencing mcp/
grep -r "mcp/tools" --include="*.ets" .
# Update each match.

# 3. (Optional) Search for any literal "mcp" string in user-facing copy
#    that should now say "tools" (or just drop the prefix)
```

Likely 1-3 import lines. Low risk, no behavior change.

## Test plan (TDD, but light)

This ticket is a pure rename. The existing test surface (if any) should still pass without modification. If `OcrTool` has Hypium tests, they test the class behavior, not the path.

A non-TDD sanity check: `node scripts/arkts-lint/index.mjs --quiet` should still show 0 errors. If the path is referenced anywhere in the rule registry, that would fail to load.

## Reversibility

**Trivial**. `git mv tools mcp` (one commit). The directory name is cosmetic.

## Acceptance criteria

- [ ] `ls agents/src/main/ets/tools/` shows the same files as the old `mcp/tools/`
- [ ] `grep -r "mcp/tools" --include="*.ets" .` returns 0 results
- [ ] `grep -r "/mcp/" --include="*.ets" .` returns 0 results (broader sweep)
- [ ] `node scripts/arkts-lint/index.mjs --quiet` shows 0 errors
- [ ] `node --test scripts/arkts-lint/tests/*.test.mjs` all pass
- [ ] `agents/src/main/ets/mcp/` directory no longer exists

## Sequence (single commit)

This is small enough for one commit:

1. **`chore(agents): rename mcp/tools/ to tools/`** — `git mv` + import path updates + one-line commit message referencing ADR-0005

If a `OcrTool.test.ets` exists (none today per the audit), update its import path in the same commit.

## Out of scope (intentionally)

- Adopting the actual Model Context Protocol (would mean introducing an MCP server; this is a much larger architectural shift)
- Renaming other files (only `mcp/` directory is in scope; the `OcrTool.ets` file name is fine)
- Renaming references to "agent" terminology in `OcrTool` (covered by ADR-0002 if relevant)
