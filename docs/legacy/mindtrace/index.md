# MindTrace — Legacy Docs

> **This directory is frozen.** It contains docs from earlier MindTrace iterations: the 2026-09-01 audit era, W3/W4 design plans, superseded research, and (since 2026-10-18) one-off session handoffs.
>
> **Do not add new files here.** Create new docs in their canonical location per [`docs/style/naming-conventions.md`](../../style/naming-conventions.md). The only exception is the `handoffs/` archive described below, which is a closed set.

## Contents

| Subdir | What was there | Count |
|---|---|---|
| [`architecture/`](./architecture/) | Audit + deep-dive from 2026-09-01 (21 findings) | 7 files (5 md + 2 html) |
| [`plans/w3/`](./plans/w3/) | W3 era design plans (July 2026) | 20 files (9 md + 11 html) |
| [`plans/w4/`](./plans/w4/) | W4 era design plans (July 2026) | 4 files (3 md + 1 html) |
| [`plans/`](./plans/) (root) | Plan artifacts rescued from local agent workspaces (`.deveco/plans`, `.reasonix/attachments`) before cleanup | 7 md files |
| [`research/`](./research/) | Superseded research notes (HarmonyOS / ArkUI / WebView / formula rendering); the merged versions live in `docs/research/` | 10 .md files |
| [`competition/`](./competition/) | Competition submission docs (鸿蒙高校创新赛 semifinal) | 2 files |
| [`api/`](./api/) | MindTrace API contract | 1 file |
| [`handoffs/`](./handoffs/) | One-off session handoffs / execution traces, frozen 2026-10-18 | 13 files (9 + 4 in `llm-settings/`) |

Total: 66 files.

## Rescued from local agent workspaces (2026-10-18)

`.deveco/plans/` and `.reasonix/attachments/` held plan artifacts written by AI coding workspaces. They were the only non-regenerable files in the dot-directories, so they were copied here before `.deveco/`, `.reasonix/`, `.idea/`, `.cache/`, `.scratch/`, and `.worktree-merge/` were removed:

| File | Original | Content |
|---|---|---|
| [`note-generation-origin-plan-2026-09-08.md`](./plans/note-generation-origin-plan-2026-09-08.md) | `.deveco/plans/1788864754257-clever-mountain.md` | 482-line origin design for incremental verifiable note generation (routing, SourceBundle, evidence ledger, checkpoints, regeneration). Not implemented verbatim; current shape is in spec 015 / 018 and `docs/specs/execution/`. |
| [`issue-101-standard-generation-2026-09-11.md`](./plans/issue-101-standard-generation-2026-09-11.md) | `.deveco/plans/1789068240183-sunny-lagoon.md` | Completion note for issue #101 (standard generation contracts) |
| [`issue-104-incremental-regeneration-2026-09-11.md`](./plans/issue-104-incremental-regeneration-2026-09-11.md) | `.deveco/plans/1789073902304-tidy-tiger.md` | Completion note for issue #104 (incremental regeneration) |
| [`mathmind-agent-architecture-v3-1-2026-07-14.md`](./plans/mathmind-agent-architecture-v3-1-2026-07-14.md) | `.reasonix/attachments/clipboard-…-000001.md` | Pre-rename MathMind v3.1 architecture: 21 modules, 7 dispatch chains, 4 MCP tools, 3 entry agents |
| [`d1-capture-chain-design-2026-07-14.md`](./plans/d1-capture-chain-design-2026-07-14.md) | `.reasonix/attachments/clipboard-…-000002.md` | D1 photo chain: capture → OCR → 3×3 classification → template + truth check → persist, with fallback chain |
| [`mathmind-four-layer-directory-2026-07-14.md`](./plans/mathmind-four-layer-directory-2026-07-14.md) | `.reasonix/attachments/clipboard-…-000003.md` | Four-stage directory plan: template → slim capture → full capture → MVP |
| [`mathmind-model-switching-2026-07-14.md`](./plans/mathmind-model-switching-2026-07-14.md) | `.reasonix/attachments/clipboard-…-000004.md` | Model switching architecture (requirement v3.1 §F16): built-in/custom models + fallback ordering |

The `.reasonix` copy duplicated one file (`…000005` was byte-identical to `…000003`); only one copy was kept. These are the earliest design records in the corpus and predate the `docs/legacy/mindtrace/plans/w3` set (2026-07-17).

## Handoffs archive (2026-10-18)

These were previously mixed into `docs/agents/`, which is reserved for process and pointer docs. They are time-point records, not current guidance:

- `handoff-2026-09-06.md`, `handoff-langgraph-migration.md` (SUPERSEDED)
- `backend-migration-handoff.md` (superseded by spec 018)
- `agent-run-timeline-handoff.md`
- `git-flow-setup-2026-09-04.md`
- `llm-settings-scope-2026-09-06.md`, `llm-settings/` (4 PR records)
- `note-generation-fix-handoff-2026-09-20.md`, `note-generation-failure-diagnostics-handoff-2026-09-29.md`
- `qwen-deepseek-reasoning-handoff-2026-09-12.md`

Current equivalents: `docs/specs/` (design), `docs/specs/execution/` (execution + verification), `docs/agents/` (process).

## Why archived

The content in `architecture/`, `plans/`, `research/`, `competition/`, and `api/` is **frozen at 2026-09-01** (the last audit date) and reflects the MindTrace project's specific architecture (HarmonyOS ArkTS, 5 modules, W4 design). Current decisions live in `docs/adr/`, `docs/specs/`, and `docs/agents/`.

The audit (`audit-full-2026-09-01.md`) identified 21 findings. Of those:

- ✅ #9 (LlmConfig throw on reserved keyword) — fixed in TDD commit
- ✅ #15 (ArkTS 铁律反例) — fixed via `docs/style/arkts-1.1.md` + lint engines
- ✅ #16 (production fixture data leak) — fixed in TDD commit
- ✅ #10 (mcp→tools rename) — resolved as ADR-0010 (keep `mcp/`)
- 🟡 #1 / #3 / #4 / #5 / #7 — tracked in `docs/specs/index.md`

## What's NOT here

- `docs/agents/*` — process / pointer docs (still in `docs/agents/`)
- `docs/adr/*` — current ADRs
- `docs/specs/*` — current design specs; `docs/specs/execution/*` — current execution records
- `docs/research/*` — active research (this directory holds only superseded versions)
- `docs/style/arkts-1.1.md`, `docs/style/naming-conventions.md` — still active rules
- `docs/template/*` — copy-paste templates for new docs

## If you need to reference MindTrace

- **For current project decisions**: read `docs/adr/` and `docs/specs/`
- **For the original audit**: read `architecture/audit-full-2026-09-01.md` in this directory
- **For ArkTS rules**: read `docs/style/arkts-1.1.md` (still active)
