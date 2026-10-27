# Docs index

> **Where to start, where to find what.** This is the entry point for anyone (human or agent) navigating the `docs/` directory.

## Quick start

- **First time here?** Read [`AGENTS.md`](../AGENTS.md) (agent entry point) → [`CONTEXT.md`](../CONTEXT.md) (project glossary) → this file.
- **English overview?** [`docs/readme-en.md`](./readme-en.md).
- **Need a coding rule?** [`docs/style/naming-conventions.md`](./style/naming-conventions.md) is the single source of truth.
- **Need to lint the repo?** [`scripts/naming-lint/`](../scripts/naming-lint/) (read `README.md` first).
- **Looking at historical content?** [`docs/legacy/`](./legacy/) (frozen, do not add to).

## Top-level layout

```
docs/
├── index.md                # This file
├── readme-en.md            # English README
├── onboarding.md           # 5/30-min onboarding path for new agents + humans
├── plans/                  # Implementation plans pending formal spec
├── style/                  # Coding rules, naming conventions, ArkTS strict
├── adr/                    # Architecture Decision Records (why we did X)
├── specs/                  # Design specs (what + how)
│   └── execution/          # Execution records (what happened, verification evidence)
├── research/               # Active research (current project questions)
├── architecture/           # Architecture snapshots (stable description of current code)
├── agents/                 # Process / pointer docs (git, security, issue tracking, patterns)
├── template/               # Copy-paste skeletons for new docs
└── legacy/                 # Frozen project docs (older, archived — see docs/legacy/index.md)
    └── mindtrace/          # MindTrace (HarmonyOS ArkTS)
        ├── architecture/   # Audit + deep-dive from 2026-09-01 (21 findings)
        ├── competition/    # Hackathon submission docs (鸿蒙高校创新赛 semifinal)
        ├── handoffs/       # One-off session handoffs (frozen 2026-10-18)
        │   └── llm-settings/  # LLM settings / AssetStoreKit migration PR notes
        └── plans/          # Pre-spec design plans (frozen)
```

## By purpose

| I want to… | Look in… |
|---|---|
| **Record a hard-to-reverse design decision** | `docs/adr/` — create `NNNN-{slug}.md` from [`docs/template/adr-template.md`](./template/adr-template.md) |
| **Write the design spec for a ticket** | `docs/specs/` — create `NNN-{slug}.md` from [`docs/template/spec-template.md`](./template/spec-template.md) |
| **Read an implementation design plan** | [`plans/`](./plans/index.md) — implementation designs pending formal spec |
| **Record how a ticket was executed / verified** | `docs/specs/execution/{slug}/` — see [`execution/index.md`](./specs/execution/index.md) |
| **看 v1 端A2A 的设计** | [`specs/031-xiaoyi-batch-capture-entry.md`](./specs/031-xiaoyi-batch-capture-entry.md) — 小艺唤起批量整理（浮窗 / 多选 / 落库） |
| **知道当前做到哪一阶段 / 怎么验收** | [`agents/phase-tracker.md`](./agents/phase-tracker.md) — P0–P6 状态、DoD、证据命令 |
| **Investigate a question (e.g. "should we use X?")** | `docs/research/` — `{topic-slug}-{YYYY-MM-DD}.md` from [`docs/template/research-template.md`](./template/research-template.md) |
| **Describe how the current system is wired** | `docs/architecture/` — `{scope}-{YYYY-MM-DD}.md` |
| **Set a coding rule** | `docs/style/naming-conventions.md` (the canonical spec) |
| **Find an ArkTS rule** | [`docs/style/arkts-1.1.md`](./style/arkts-1.1.md) |
| **Understand the current architecture** | `docs/adr/` (current decisions) — for historical audits see [`docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md`](./legacy/mindtrace/architecture/audit-full-2026-09-01.md) |
| **Find an API contract** | `common/src/main/ets/models/` + `CONTEXT.md`（当前类型与术语契约） |
| **Look up a workflow (issue tracking, triage)** | `docs/agents/` — see [`agents/index.md`](./agents/index.md) |
| **Find an old session's decision trail** | `docs/legacy/mindtrace/handoffs/` (frozen; not current guidance) |
| **Understand the v1 layered architecture** | [`system-architecture-layered.md`](./system-architecture-layered.md) — 五层设计、能力选型、验收清单、小艺开放平台落地路径（唯一权威架构文档，含 §14 评审修正与 v7 目标态） |
| **Read the v7 target-state review** | [`architecture/review-v7-2026-10-27.md`](./architecture/review-v7-2026-10-27.md) — 外评审：有条件可落地、端口与迁移顺序的硬依赖、五条风险 |
| **Pick up the v7 contract work** | [`specs/execution/v7-architecture-contracts/plan.md`](./specs/execution/v7-architecture-contracts/plan.md) — 交接文档：票单 #237–#242、顺序、硬约束、环境命令 |
| **Create a new doc** | Pick a template from `docs/template/`, then run `node scripts/naming-lint/index.mjs` to verify the name conforms |

## By audience

### For agents (new session reading this)

1. Read `AGENTS.md` (top-of-mind hard rules)
2. Read `CONTEXT.md` (project vocabulary)
3. Read `docs/style/naming-conventions.md` (file/dir/code naming)
4. When you need to do work, find the relevant `docs/agents/*.md` or `docs/specs/NNN-{slug}.md`
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
| Design spec | `docs/specs/` | `NNN-{slug}.md` | `docs/template/spec-template.md` |
| Execution record | `docs/specs/execution/{slug}/` | `spec.md` / `plan.md` / `tasks.md` / `verification-record.md` | (copy an existing bundle) |
| Research | `docs/research/` | `{slug}-{YYYY-MM-DD}.md` | `docs/template/research-template.md` |
| Architecture snapshot | `docs/architecture/` | `{scope}-{YYYY-MM-DD}.md` | (ad-hoc) |
| Style rule | `docs/style/` | `{framework}-{topic}.md` | (ad-hoc, see existing) |
| Agent workflow | `docs/agents/` | `{topic-slug}.md` | `docs/template/agent-workflow-template.md` |

## Index files (per directory)

Every doc directory has an `index.md` (NOT `README.md`) that:
- Lists the files in that directory
- Explains the directory's purpose
- Links to the canonical template

Currently (every directory, including execution bundles and legacy subdirectories):
- [`docs/index.md`](./index.md) — this file
- [`docs/adr/index.md`](./adr/index.md)
- [`docs/specs/index.md`](./specs/index.md)
- [`docs/plans/index.md`](./plans/index.md)
- [`docs/specs/execution/index.md`](./specs/execution/index.md)
- [`docs/specs/execution/{bundle}/index.md`](./specs/execution/) — one per bundle
- [`docs/research/index.md`](./research/index.md)
- [`docs/architecture/index.md`](./architecture/index.md)
- [`docs/agents/index.md`](./agents/index.md)
- [`docs/agents/patterns/index.md`](./agents/patterns/index.md)
- [`docs/style/index.md`](./style/index.md)
- [`docs/template/index.md`](./template/index.md)
- [`docs/legacy/index.md`](./legacy/index.md)
- [`docs/legacy/mindtrace/index.md`](./legacy/mindtrace/index.md)
- `docs/legacy/mindtrace/{architecture,competition,plans,handoffs}/index.md`
- `scripts/*/README.md` (tooling uses README.md per ecosystem convention)

If you add a new doc directory — including a new execution bundle — also add an `index.md` for it. Run `node scripts/doc-trace/index.mjs` to verify reachability and coverage.

## How this index stays current

- When a new doc type is added (e.g. RFCs), update §"Doc type cheat sheet" and §"By purpose"
- When a new agent workflow is created, update §"By purpose" → `docs/agents/`
- When the project structure changes, update §"Top-level layout"
- Updates go via a `docs(index):` commit; bump this file's `Last updated` timestamp

Last updated: 2026-10-18 (document control: reachable directory indexes, `doc-trace` gate, ArkTS AI coding checklist, and spec/ADR status reconciliation)
