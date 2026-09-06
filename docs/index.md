# Docs index

> **Where to start, where to find what.** This is the entry point for anyone (human or agent) navigating the `docs/` directory.

## Quick start

- **First time here?** Read [`AGENTS.md`](../AGENTS.md) (agent entry point) → [`CONTEXT.md`](../CONTEXT.md) (project glossary) → this file.
- **Need a coding rule?** [`docs/style/naming-conventions.md`](./style/naming-conventions.md) is the single source of truth.
- **Need to lint the repo?** [`scripts/naming-lint/`](../scripts/naming-lint/) (read `README.md` first).
- **Looking at historical content?** [`docs/legacy/`](./legacy/) (frozen, do not add to).

## Top-level layout

```
docs/
├── index.md                # This file
├── onboarding.md           # 5/30-min onboarding path for new agents + humans
├── style/                  # Coding rules, naming conventions
├── adr/                    # Architecture Decision Records (why we did X)
├── specs/                  # Implementation specs (how to do Y)
├── research/               # Active research (current project questions)
├── template/               # Copy-paste skeletons for new docs
├── agents/                 # Agent workflow docs (issue tracking, triage, conventions, patterns)
└── legacy/                 # Frozen project docs (older, archived — see docs/legacy/index.md)
    └── mindtrace/          # MindTrace (HarmonyOS ArkTS, 2026-09-01 frozen)
        ├── architecture/   # Audit + deep-dive from 2026-09-01 (21 findings)
        ├── api/            # API contract
        ├── competition/    # Hackathon submission docs (鸿蒙高校创新赛 semifinal)
        ├── plans/          # W3 / W4 era design plans
        └── research/       # MindTrace-specific research (HarmonyOS / ArkUI / WebView / formula rendering)
```

## By purpose

| I want to… | Look in… |
|---|---|
| **Record a hard-to-reverse design decision** | `docs/adr/` — create `NNNN-{slug}.md` from [`docs/template/adr-template.md`](./template/adr-template.md) |
| **Plan the implementation of a ticket** | `docs/specs/` — create `NNN-{slug}.md` from [`docs/template/spec-template.md`](./template/spec-template.md) |
| **Investigate a question (e.g. "should we use X?")** | `docs/research/` — `{topic-slug}-{YYYY-MM-DD}.md` from [`docs/template/research-template.md`](./template/research-template.md) |
| **Set a coding rule** | `docs/style/naming-conventions.md` (the canonical spec) |
| **Find a coding rule for a specific framework** | `docs/style/` (e.g. `langgraph-style.md` when added) |
| **Understand the current architecture** | `docs/adr/` (current decisions) — for historical audits see [`docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md`](./legacy/mindtrace/architecture/audit-full-2026-09-01.md) |
| **Find an API contract** | [`docs/legacy/mindtrace/api/contract.md`](./legacy/mindtrace/api/contract.md) |
| **Look up a workflow (issue tracking, triage)** | `docs/agents/{topic}.md` (13 workflow docs + `patterns/`) |
| **Create a new doc** | Pick a template from `docs/template/`, then run `node scripts/naming-lint/index.mjs` to verify the name conforms |

## By audience

### For agents (new session reading this)

1. Read `AGENTS.md` (top-of-mind hard rules)
2. Read `CONTEXT.md` (project vocabulary)
3. Read `docs/style/naming-conventions.md` (file/dir/code naming)
4. When you need to do work, find the relevant `docs/agents/*.md` or `docs/specs/NN-{slug}.md`
5. **Always run `node scripts/naming-lint/index.mjs` after writing a new file** to catch violations early

### For humans (new to repo)

1. Read top of `AGENTS.md` (project context + 7 hard rules)
2. Skim `CONTEXT.md` (glossary)
3. Skim `docs/index.md` (this file)
4. Read the relevant ADR/spec for your task
5. Use `node scripts/naming-lint/index.mjs` to verify anything you add

### For evaluators (competition judges)

1. Read top of `AGENTS.md` (project positioning + demo path)
2. Skim the "项目亮点" table in `AGENTS.md` (5 highlights)
3. Walk the demo path (5 minutes)
4. Inspect `docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md` for the full audit
5. Inspect `docs/adr/` and `docs/specs/` for design decisions
6. **New here?** Start with [`docs/onboarding.md`](./onboarding.md) for a 5/30-min reading path

## Doc type cheat sheet

| Type | Location | File naming | Created via template |
|---|---|---|---|
| ADR | `docs/adr/` | `NNNN-{slug}.md` | `docs/template/adr-template.md` |
| Spec | `docs/specs/` | `NNN-{slug}.md` | `docs/template/spec-template.md` |
| Research | `docs/research/` | `{slug}-{YYYY-MM-DD}.md` | `docs/template/research-template.md` |
| Style rule | `docs/style/` | `{framework}-{topic}.md` | (ad-hoc, see existing) |
| Agent workflow | `docs/agents/` | `{topic-slug}.md` | `docs/template/agent-workflow-template.md` |

## Index files (per directory)

Every doc directory has an `index.md` (NOT `README.md`) that:
- Lists the files in that directory
- Explains the directory's purpose
- Links to the canonical template

Currently:
- `docs/index.md` — this file
- `docs/adr/index.md`
- `docs/specs/index.md`
- `docs/research/index.md`
- `docs/template/index.md`
- `docs/legacy/index.md`
- `docs/legacy/mindtrace/index.md`
- `scripts/naming-lint/README.md` (the one exception: tooling uses README.md per ecosystem convention)

If you add a new doc directory, also add an `index.md` for it.

## How this index stays current

- When a new doc type is added (e.g. RFCs), update §"Doc type cheat sheet" and §"By purpose"
- When a new agent workflow is created, update §"By purpose" → `docs/agents/`
- When the project structure changes, update §"Top-level layout"
- Updates go via a `docs(index):` commit; bump this file's `Last updated` timestamp

Last updated: 2026-09-06 (governance status refresh: ADR-0008/0009, research index listed, agents/ count)