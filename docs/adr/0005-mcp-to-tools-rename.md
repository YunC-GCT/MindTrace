# 0005 — Rename `agents/src/main/ets/mcp/` to `tools/`

The directory `agents/src/main/ets/mcp/tools/` is named "mcp" (Model Context Protocol) but the project does not run an MCP server. `OcrTool.ets` is plain HTTP. The name is false advertising and confuses new contributors.

## Status

**Superseded by [ADR-0010](./0010-mcp-tools-semantics.md)** (2026-09-06). The premise above — "the project does not run an MCP server, so the name is false advertising" — was wrong: `OcrTool` is an MCP-语义 tool (built by a teammate from an MCP tool), so `mcp/` is retained as a by-semantics directory classification and the rename was reverted (spec 010, PR #28 revert). After the revert, `tools/` refers to CRUD-class agent tools instead (see [ADR-0012](./0012-tool-calling-protocol.md)).

## Considered Options

1. **Rename to `tools/`** *(chosen)*. One-time `git mv`, search-replace any imports. ~6 files affected (only `OcrTool.ets` and the index files reference the path).
2. **Keep `mcp/`**. Add a comment at the directory explaining "mcp" is aspirational. Zero cost, zero clarity.
3. **Add an alias without removing**. Symlink `tools/` → `mcp/`. Confusing for git tooling and IDEs.

## Consequences

- **Chosen (1)**: clean naming. New contributor sees `tools/OcrTool.ets` and immediately understands what it is. The word "mcp" is reserved for when (if ever) the project actually adopts Model Context Protocol.
- Reject (2): a comment is documentation that gets out of sync. The directory *is* a directory. Names matter.
- Reject (3): aliases create two truths, one of which is wrong.

## Reversibility

**Trivial** if MCP is ever adopted. `git mv tools mcp` (or vice versa). One commit.

## Migration plan

Phase 4 ticket #10 (already in audit). The change is:

```bash
git mv agents/src/main/ets/mcp agents/src/main/ets/tools
# Update imports in:
#   - agents/src/main/ets/Index.ets (likely exports OcrTool)
#   - entry files that import OcrTool from agents
```

Search for any remaining `mcp` references and update.

## Related

- Audit §4.8 — original finding
- `CONTEXT.md` — no "mcp" term defined (correctly)
- ADR-0002 — "agent" disambiguation (similar false-naming pattern)
