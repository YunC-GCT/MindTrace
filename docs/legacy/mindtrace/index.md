# MindTrace — Legacy Docs

> **This directory is frozen.** It keeps only records that still explain a current decision or provide audit evidence for it.
>
> **Do not add new files here** — with one exception: a fully superseded spec that a current ADR/spec still cites may be archived here with a banner (2026-10-30: spec 003 / spec 007 / note-generation plan). New design docs go to their canonical location per [`docs/style/naming-conventions.md`](../../style/naming-conventions.md).
>
> **Layout (2026-10-30)**: flattened from `architecture/` `competition/` `plans/` `handoffs/` (each held 1–5 files plus its own `index.md`) into one flat directory: 13 files, 1 index, no subdirectories.

## Contents (13 files)

| File | Why it is still here | Referenced by |
|---|---|---|
| [`audit-full-2026-09-01.md`](./audit-full-2026-09-01.md) | The 21-finding audit that drove ADR-0001…0018 and specs 003–018 | `AGENTS.md`, `docs/index.md`, `docs/adr/index.md`, `docs/onboarding.md`, `docs/specs/index.md`, `docs/specs/017`, 3x research |
| [`deep-dive-2026-09-01.md`](./deep-dive-2026-09-01.md) | Per-file analysis of the 7 largest classes at audit time; the evidence behind ADR-0006's split | `docs/specs/index.md`, 2x research |
| [`lint-baseline-2026-09-01.json`](./lint-baseline-2026-09-01.json) | The lint numbers those decisions were measured against | `docs/research/note-detail-overlay-state-2026-09-23.md` |
| [`competition-references-2026-07-26.md`](./competition-references-2026-07-26.md) | Upstream projects + licenses used in submission material | `docs/plans/xiaoyi-latency-tuning-plan.md`, 1x research |
| [`note-generation-origin-plan-2026-09-08.md`](./note-generation-origin-plan-2026-09-08.md) | 482-line origin design for verifiable note generation. Core contracts landed via spec 015/018 + ADR-0018; the bounded evaluator-optimizer loop with checkpoint rollback is still unimplemented — this file is its only source | (self-contained) |
| [`backend-migration-handoff.md`](./backend-migration-handoff.md) | Background for spec 018 (backend/workflow migration); the pointer new owners are sent to | `AGENTS.md`, 1x research |
| [`note-generation-fix-handoff-2026-09-20.md`](./note-generation-fix-handoff-2026-09-20.md) | Explains the current `LLM_TRUNCATED` / generation-budget behaviour | `docs/plans/xiaoyi-latency-tuning-plan.md`, `docs/specs/execution/note-generation-stability/plan.md` |
| [`note-generation-failure-diagnostics-handoff-2026-09-29.md`](./note-generation-failure-diagnostics-handoff-2026-09-29.md) | Postmortem of `VERIFIER_UNAVAILABLE` and how the diagnostics were added | (self-contained) |
| [`qwen-deepseek-reasoning-handoff-2026-09-12.md`](./qwen-deepseek-reasoning-handoff-2026-09-12.md) | Why `enableThinking` defaults to true and how reasoning content is routed (ADR-0015) | 4x `docs/specs/execution/*/verification-record.md` |
| [`llm-settings-scope-2026-09-06.md`](./llm-settings-scope-2026-09-06.md) | Scope decisions behind spec 016 / ADR-0013 / ADR-0014 | `docs/specs/016-llm-settings-redesign.md`, `docs/plans/xiaoyi-latency-tuning-plan.md` |
| [`spec-003-knowledge-model-decomposition.md`](./spec-003-knowledge-model-decomposition.md) | 被 spec 015 取代的 KnowledgeModel 三拆方案（2026-09-06） | `docs/specs/index.md`, `docs/specs/015`, ADR-0006 |
| [`spec-007-agent-chat-service-decomposition.md`](./spec-007-agent-chat-service-decomposition.md) | 被 spec 018 取代的 AgentChatService 三拆方案（2026-09-07） | `docs/specs/index.md`, ADR-0012, `backend-migration-handoff` |
| [`note-generation-stability-plan-2026-09-21.md`](./note-generation-stability-plan-2026-09-21.md) | 笔记生成稳定性实施计划（唯一副本，588 行） | `docs/specs/execution/archive-2026-09.md` |

## 2026-10-30 cleanup — what was removed and why

| Removed | Why |
|---|---|
| `architecture/audit-full-2026-09-01.html` (44 KB) | Render of the `.md` above; zero inbound links; the markdown is the authoritative record |
| `architecture/lint-baseline-ast-2026-09-01.json` (104 KB) | Baseline of the pre-0.3 AST engine; that engine has since been rewritten (34 rules, gate `pass=953`), so the file can no longer be diffed against anything |
| `handoffs/handoff-2026-09-06.md` | Sprint-week session handoff; every pointer in it (spec coverage map, demo prep) is long resolved |
| `handoffs/handoff-langgraph-migration.md` | Plan for migrating to LangGraph — a route **rejected** by ADR-0008 (self-built ArkTS `StateGraph`) |
| `handoffs/agent-run-timeline-handoff.md` | Timeline infrastructure that never landed (`grep -r "RunTimeline|AgentRunEvent"` → 0 hits) |
| `handoffs/git-flow-setup-2026-09-04.md` | Owner's one-time setup checklist; promoted into [`docs/agents/git-flow-lightweight-2026-09-04.md`](../../agents/git-flow-lightweight-2026-09-04.md), which itself marks it as no longer needed |
| `handoffs/llm-settings/` (5 files) | PR-by-PR implementation notes for a shipped feature; ADR-0013 / ADR-0014 / spec 016 are the authoritative record |
| 5 subdirectory `index.md` files | Superseded by this single index after the flattening |

## 2026-10-18 purge (kept for provenance)

The corpus had accumulated three generations of design docs that no longer match the current direction (5 modules, single backend, native `StateGraph`, `Dispatcher` single entry, MM-MD-v1). They were deleted rather than kept "for history", because they describe architectures the project explicitly rejected:

| Removed | Why |
|---|---|
| `plans/w3/` (20 files, July 17–22) | Pre-D2 frontend/render/UI-cache plans; implemented or replaced by spec 012 / 021 and the current render research. The still-normative MM-MD-v1 grammar was extracted to [`docs/style/mm-md-v1.md`](../../style/mm-md-v1.md) first. |
| `plans/w4/` (4 files, July 23–24) | Streaming / long-reply / multi-WebView plans; superseded by spec 019 / 020 / 021 and `LlmClient`'s structured streaming. |
| `research/` (10 files) | Pre-D2 formula/WebView/HTTP research; merged into [`docs/research/capturegraph-architecture-evolution-2026-09-16.md`](../../research/capturegraph-architecture-evolution-2026-09-16.md) or replaced by spec 021. |
| `plans/mathmind-*` (3 files, July 14) | Pre-rename MathMind v3.1: 21 modules / 3 entry agents / four-stage MVP directory — contradicts the current 5-module design. |
| `plans/d1-capture-chain-design-2026-07-14.md` | Origin of the capture chain; the current chain is documented in `AiService` / `CONTEXT.md` and implemented in `Dispatcher` + `CaptureGraph`. |
| `plans/issue-101-*.md`, `plans/issue-104-*.md` | Completion notes for implemented features; no unimplemented proposals. |
| `api/contract.md` | W1 skeleton API contract with the old `Dispatcher.dispatch(payload)` signature. |
| `architecture/audit-2026-09-01.md` + html | Single-document AGENTS audit explicitly superseded by `audit-full-2026-09-01.md`. |
| `competition/ocr-setup.md` | Superseded by `README.md` + `tools/ocr_service/README.md`. |

## Audit findings — where they stand

The 2026-09-01 audit identified 21 findings:

- #9 (LlmConfig throw on reserved keyword) — fixed in TDD commit
- #15 (ArkTS 铁律反例) — fixed via `docs/style/arkts-1.1.md` + lint engines
- #16 (production fixture data leak) — fixed in TDD commit
- #10 (mcp→tools rename) — resolved as ADR-0010 (keep `mcp/`)
- #1 / #3 / #4 / #5 / #7 — tracked in `docs/specs/index.md`

## Where to look instead

- **Current project decisions**: [`docs/adr/`](../../adr/) and [`docs/specs/`](../../specs/)
- **Original audit (frozen at 2026-09-01)**: [`audit-full-2026-09-01.md`](./audit-full-2026-09-01.md)
- **ArkTS rules**: [`docs/style/arkts-1.1.md`](../../style/arkts-1.1.md)
