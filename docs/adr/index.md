# Architecture Decision Records

This directory holds ADRs that capture **why** the project is shaped a certain way, not just what
it does. Every ADR documents one decision: the context, the alternatives considered, the
choice made, and the reversibility.

## Index

| # | Decision | Status |
|---|-----------|--------|
| [0001](./0001-layer-boundaries-in-5-module-arkts-app.md) | Allow direct cross-layer imports (`entry/services/` → `agents/`) for now; add interface layer when 5+ services import `agents/` — 现状：2 个 service（`AiService` / `SubjectRepairService`），阈值未触发 | accepted |
| [0002](./0002-agent-terminology-disambiguation.md) | Keep code names `Agent*`; migrate user-facing copy to "AI 助手"; document disambiguation in CONTEXT.md | accepted |
| [0003](./0003-dispatcher-single-entry-design.md) | Collapse 3 public methods (`analyze` + `dispatch` + `routeDispatch`) to one `dispatch(req, opts?)`; `analyze` becomes a private step — 现状：`dispatch` + 批量包装 `dispatchSet`（`:153`），语义入口仍唯一 | accepted |
| [0004](./0004-llm-call-layer-consolidation.md) | Collapse 3 call methods to one `call(opts)` with adapter selection via `opts.stream`; remove `callSseTokens` (dead path) | accepted |
| [0005](./0005-mcp-to-tools-rename.md) | Rename `agents/mcp/tools/` to `agents/tools/`; `mcp` is misleading (no MCP server runs) | superseded by [0010](./0010-mcp-tools-semantics.md) |
| [0006](./0006-knowledge-model-decomposition-plan.md) | Split 870-LOC god class into collaborators (PromptBuilder + TruthCheckService + StructureService); Dispatcher orchestrates — 现状：`StructureService` 未落地，结构化在 `CaptureStructurer`（643 行），`KnowledgeModel` 已降到 105 行 | accepted |
| [0007](./0007-test-baseline-12-unit-tests.md) | Adopt audit's 12-test baseline (4+4+2+2 across 4 units) as the test floor — 现状：145 个 `*.test.mjs`、gate `pass=953 fail=0`，12 仅为下限 | accepted |
| [0008](./0008-capturegraph-self-built-runtime.md) | Adopt LangGraph as the canonical Agent workflow architecture design root, implemented natively in ArkTS; `CaptureGraph` is the first concrete workflow, not the whole architecture — no Python sidecar / langgraphjs runtime dependency | accepted |
| [0009](./0009-kit-facade-injection-boundary.md) | Kit capability seam: pipeline consumes kits via `common/kit/` facade contracts, implementations injected at composition root — a seam, not an import ban; **2026-10 补充**：Kit 按「被哪些进程 eval」分三档，受限 Kit（`DataAugmentationKit`）不得经 `common` barrel 导出 | accepted |
| [0010](./0010-mcp-tools-semantics.md) | `mcp/` keeps MCP-tool semantics (`OcrTool` is a teammate-built MCP 工具); `tools/` reserved for CRUD tools — supersedes ADR-0005, PR #28 rename reverted | accepted |
| [0011](./0011-skill-xiaoyi-reservation.md) | `skill/` retained for Xiaoyi; SearchNote now routes through the typed SkillIntent workflow to the shared note_query tool, remaining actions explicit unsupported pending semantics — 现状：`skill/` 是 **HAP**（`type: feature`），原文误写为 HSP | accepted |
| [0012](./0012-tool-calling-protocol.md) | OpenAI-compatible tool-calling fields in `LlmTypes`; `ToolRegistry` lives in `common/` (shared by the in-app LLM loop and the future `skill/` IntentRouter); read-only tools first — implemented by [spec 014](../specs/014-tool-calling-protocol.md) | accepted |
| [0013](./0013-llm-provider-presets.md) | LLM provider presets | accepted |
| [0014](./0014-asset-store-kit-migration.md) | Asset Store Kit migration | accepted |
| [0015](./0015-structured-stream-events.md) | Structured streaming events (`StreamEvent`, `type ∈ thinking \| text \| tool_call \| tool_result`) replace the `(delta, kind)` callback; reasoning→content fallback removed in the same change; `enableThinking` wired via LlmConfig default `true` | accepted |
| [0016](./0016-reply-contract-by-transport.md) | Reply contract scoped by transport: stream prompt emits the Reply Body (MM-MD-v1 Markdown) directly, complete keeps the JSON envelope + LlmGuard; ReplyService exclusively owns envelope→body; chat content is always a Reply Body | accepted |
| [0017](./0017-renderer-scheduler-budget-baseline.md) | Renderer scheduler budget baseline for ticket #124: maxWebCreatesPerFrame=1, maxWebWorkMsPerFrame=16; derived from webWorkDurationSamplesMs (n=16, median=150ms, p75=426ms); DevEco emulator performance target NOT_MET — recorded as ticket-1 follow-up | accepted |
| [0018](./0018-note-evidence-provenance.md) | Separate note assertions, immutable source provenance, and read-only verification; the model returns positional statuses while the pipeline owns IDs and exact source spans | accepted |
| [0019](./0019-note-command-and-outcome.md) | `NoteCommand` (capture / generation / regenerate / preparedCandidate / analysisOnly) and `NoteOutcome` (needsInput / readyPreview / committed / failed / cancelled) as discriminated unions; `failed` carries code + retryable, `cancelled` carries whether a write was committed; subgraph scope revised in ADR-0008 — **目标契约，代码零实现**（#238/#239/#241 未开工） | accepted（未实现） |
| [0021](./0021-shared-read-port-implementation-in-common.md) | 只读端口实现放 `common/ports/impl`（skill/cardservice 无法依赖 entry，且 common 已持有 ArkData）；写实现留 `entry`；`agents` 只依赖契约不碰实现；只读端口返回投影而非整行 `KnowledgeUnit` | accepted |
| [0022](./0022-review-and-video-scope.md) | `#242` 拍板：MathVideoAgent 只产脚本（不做 mp4 renderer）；ReviewAgent 新建 `review_item` / `review_log`，`study_plan` 保持待办语义；测试态按本地开发数据处理迁移（v14 → v15，回滚 = DROP） | accepted |

## How to write a new ADR

Per `~/.agents/skills/domain-modeling/ADR-FORMAT.md`, ADRs are minimal:

```md
# {Short title of the decision}

{1-3 sentences: what's the context, what did we decide, and why.}
```

Optional sections (only when they add value):
- **Status** frontmatter (`proposed | accepted | deprecated | superseded by ADR-NNNN`)
- **Considered Options** — only when rejected alternatives are worth remembering
- **Consequences** — only when non-obvious downstream effects need to be called out

## When to create an ADR

**All three must be true**:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If a decision is easy to reverse, skip the ADR — you'll just reverse it. If it's not surprising, nobody will wonder why. If there was no real alternative, there's nothing to record beyond "we did the obvious thing."

## What qualifies

- **Architectural shape.** "We're using a monorepo." "The pipeline is orchestrated, the helpers are pure."
- **Integration patterns between layers.** "Services communicate via direct method calls, not events."
- **Technology choices that carry lock-in.** Database, message bus, auth provider, deployment target.
- **Boundary and scope decisions.** "Fixture data is debug-only; production never sees preview content."
- **Deliberate deviations from the obvious path.** "We use V1 lint even though V0.3 is the recommendation, because V1 is what was in place when CI was wired."
- **Constraints not visible in the code.** "We can't use async here because DevEco Studio's ArkTS runtime doesn't support top-level await."
- **Rejected alternatives when the rejection is non-obvious.** If you considered GraphQL and picked REST for subtle reasons, record it.

## ADR 列表（近期）

- [`0018-note-evidence-provenance.md`](./0018-note-evidence-provenance.md) — 证据可溯源（noteId/version 引用校验）
- [`0019-note-command-and-outcome.md`](./0019-note-command-and-outcome.md) — NoteCommand/NoteOutcome 命令 seam
- [`0021-shared-read-port-implementation-in-common.md`](./0021-shared-read-port-implementation-in-common.md) — 读端口实现位置
- [`0022-review-and-video-scope.md`](./0022-review-and-video-scope.md) — 复习/视频范围
- [`0023-rag-local-fts-retrieval.md`](./0023-rag-local-fts-retrieval.md) — RAG 一期：本机 FTS5 + 证据注入（Kit retrieveRdb 暂缓）

## Relationship to other docs

- **`docs/specs/`** — implementation specs derived from ADRs (the "what" + "how")
- **`docs/style/arkts-1.1.md`** — ArkTS rules (technical, not architectural decisions)
- **[`docs/legacy/mindtrace/audit-full-2026-09-01.md`](../legacy/mindtrace/audit-full-2026-09-01.md)** — original audit (2026-09-01, archived) that surfaced the design issues these ADRs resolve
- **`CONTEXT.md`** — project glossary; ADRs reference terms defined there

## Numbering

ADRs use 4-digit sequential numbering: `0001-slug.md`, `0002-slug.md`, etc. New ADRs get
the next available number. Slugs are kebab-case short descriptions.

## When ADRs are wrong

ADRs that turn out to be wrong are not deleted; they are marked `superseded by ADR-NNNN` and
the new ADR links to the old one. The git history preserves the original reasoning.
