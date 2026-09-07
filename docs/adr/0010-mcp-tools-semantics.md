# 0010 — `mcp/` keeps MCP-tool semantics; `tools/` is reserved for CRUD tools

ADR-0005 renamed `agents/mcp/tools/` to `tools/` on the premise "no MCP server runs, so the name is false advertising". That premise missed the team's intent: **`OcrTool` is a teammate-built MCP 工具** — the `mcp/` directory classifies tools by MCP semantics (按 MCP 语义封装的 agent 工具), not by whether an MCP server is currently running. We revert the rename (restoring `agents/src/main/ets/mcp/tools/OcrTool.ets`) and reserve `tools/` for the planned CRUD tools (增删查改类). This ADR supersedes ADR-0005.

## Status

`accepted` (2026-09-06) — supersedes [ADR-0005](./0005-mcp-to-tools-rename.md)

## Considered Options

1. **Restore `mcp/tools/`, reserve `tools/` for CRUD tools** *(chosen)* — naming follows the team's tool taxonomy: MCP-语义工具 under `mcp/`, data-manipulation (增删查改) tools under `tools/`.
2. **Keep ADR-0005's `tools/` rename** — loses the teammate's design intent and occupies the directory planned for CRUD tools.
3. **Invent a third name (e.g. `agent-tools/`)** — new vocabulary nobody asked for; CONTEXT.md now defines `mcp/` precisely, so no rename is needed.

## Consequences

- **Chosen (1)**: `agents/src/main/ets/mcp/tools/OcrTool.ets` is the canonical path again; `tools/` stays uncreated until real CRUD tools land.
- Open note (文档不替人下结论): OcrTool 当前实现为端侧 CoreVisionKit + HTTP OCR;"MCP 工具"指工具定位与封装语义。是否/何时以 MCP 协议对外暴露(如 JSON-RPC server),由该工具的维护队员决定。
- New MCP-semantic tools go under `mcp/`; CRUD tools go under `tools/`.

## Reversibility

**Low** — a directory rename + import paths, mechanical via `git mv`.

## Related

- [ADR-0005](./0005-mcp-to-tools-rename.md) — superseded by this ADR
- [spec 010](../specs/010-mcp-to-tools-rename.md) — executed then reverted
- `CONTEXT.md` — `MCP 工具 (mcp/)` term
