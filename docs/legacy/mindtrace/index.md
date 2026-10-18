# MindTrace — Legacy Docs

> **This directory is frozen.** It keeps only records that still explain a current decision or provide audit evidence for it.
>
> **Do not add new files here.** Create new docs in their canonical location per [`docs/style/naming-conventions.md`](../../style/naming-conventions.md).

## Contents

| Subdir | What is there | Count |
|---|---|---|
| [`architecture/`](./architecture/) | 2026-09-01 full audit + deep-dive + lint baselines | 5 files (2 md + 1 html + 2 json) |
| [`competition/`](./competition/) | Competition reference list (licenses / upstream projects) | 1 md |
| [`plans/`](./plans/) | Note-generation origin design (see status note below) | 1 md |
| [`handoffs/`](./handoffs/) | One-off session handoffs / execution traces, frozen 2026-10-18 | 14 files (10 + 4 in `llm-settings/`) |

Total: 22 files.

## 2026-10-18 purge — what was removed and why

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

Kept because they are still the evidence behind current decisions:

- `architecture/audit-full-2026-09-01.md` — the 21-finding audit that drove ADR-0001..0018 and specs 003–018.
- `architecture/deep-dive-2026-09-01.md` — analysis of the 7 largest files at audit time.
- `architecture/lint-baseline-*.json` — the lint baseline those decisions measured against.
- `competition/references-2026-07-26.md` — upstream projects and licenses used in submission material.
- `handoffs/` — see [`handoffs/index.md`](./handoffs/index.md) for the per-file status.

## Note on `plans/note-generation-origin-plan-2026-09-08.md`

A 482-line design for incremental verifiable note generation (routing, SourceBundle, evidence ledger, checkpoint rollback). Its core contracts landed and were reshaped by spec 015 / 018 and ADR-0018; a bounded evaluator-optimizer loop with checkpoint rollback remains the main idea not implemented. It is kept as the only source for that unimplemented part, not as current guidance.

## Why this directory exists

The content in `architecture/` is **frozen at 2026-09-01** (the last audit date). It records what the code looked like when the current architecture was chosen. Current decisions live in `docs/adr/`, `docs/specs/`, and `docs/agents/`.

The audit identified 21 findings. Of those:

- ✅ #9 (LlmConfig throw on reserved keyword) — fixed in TDD commit
- ✅ #15 (ArkTS 铁律反例) — fixed via `docs/style/arkts-1.1.md` + lint engines
- ✅ #16 (production fixture data leak) — fixed in TDD commit
- ✅ #10 (mcp→tools rename) — resolved as ADR-0010 (keep `mcp/`)
- 🟡 #1 / #3 / #4 / #5 / #7 — tracked in `docs/specs/index.md`

## If you need to reference MindTrace

- **For current project decisions**: read `docs/adr/` and `docs/specs/`
- **For the original audit**: read `architecture/audit-full-2026-09-01.md`
- **For ArkTS rules**: read `docs/style/arkts-1.1.md`
