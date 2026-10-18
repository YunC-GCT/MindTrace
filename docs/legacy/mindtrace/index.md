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
| [`plans/`](./plans/) (root) | AI workspace plan artifacts rescued from `.deveco/plans` before local cleanup (2026-09-08 / 09-11) | 3 md files |
| [`research/`](./research/) | Superseded research notes (HarmonyOS / ArkUI / WebView / formula rendering); the merged versions live in `docs/research/` | 10 .md files |
| [`competition/`](./competition/) | Competition submission docs (鸿蒙高校创新赛 semifinal) | 2 files |
| [`api/`](./api/) | MindTrace API contract | 1 file |
| [`handoffs/`](./handoffs/) | One-off session handoffs / execution traces, frozen 2026-10-18 | 13 files (9 + 4 in `llm-settings/`) |

Total: 61 files.

## Rescued from the local AI workspace (2026-10-18)

`.deveco/plans/` held three plan artifacts written by an AI coding workspace. They were the only non-regenerable files in the dot-directories, so they were copied here before `.deveco/`, `.idea/`, `.cache/`, and `.worktree-merge/` were removed:

| File | Original | Content |
|---|---|---|
| [`note-generation-origin-plan-2026-09-08.md`](./plans/note-generation-origin-plan-2026-09-08.md) | `1788864754257-clever-mountain.md` | 482-line origin design for incremental verifiable note generation (routing, SourceBundle, evidence ledger, checkpoints, regeneration). Not implemented verbatim; current shape is in spec 015 / 018 and `docs/specs/execution/`. |
| [`issue-101-standard-generation-2026-09-11.md`](./plans/issue-101-standard-generation-2026-09-11.md) | `1789068240183-sunny-lagoon.md` | Completion note for issue #101 (standard generation contracts) |
| [`issue-104-incremental-regeneration-2026-09-11.md`](./plans/issue-104-incremental-regeneration-2026-09-11.md) | `1789073902304-tidy-tiger.md` | Completion note for issue #104 (incremental regeneration) |

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
