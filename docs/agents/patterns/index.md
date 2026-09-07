# Agent Patterns

> **For:** agents (and humans) executing common tasks
> **Format:** each pattern is a step-by-step recipe with completion criteria

Patterns are **reusable procedures** for tasks an agent or human might do repeatedly. They're not just docs — they include commands, completion checks, and anti-patterns.

## How patterns differ from regular docs

| Doc type | Purpose | Example |
|---|---|---|
| `AGENTS.md` / `docs/index.md` | Navigation (where to find what) | "Read this first" |
| **Pattern** (here) | **Recipe** (how to do X step by step) | "To add an ADR, do this, this, this" |
| `docs/adr/NNNN-*.md` | Decision (why we did X) | "We chose X because Y" |
| `docs/specs/NNN-*.md` | Plan (what to do for ticket Y) | "To implement #3, do this TDD plan" |
| `docs/research/{slug}-YYYY-MM-DD.md` | Investigation (what we found) | "Is this LangGraph-based? — no" |

Patterns fill the **how** gap that specs and ADRs don't cover.

## Available patterns

| Pattern | When to use | Time |
|---|---|---|
| [`add-new-adr.md`](./add-new-adr.md) | Recording a hard-to-reverse design decision | 30-60 min |
| [`refactor-x.md`](./refactor-x.md) | Restructuring code without changing behavior (TDD) | varies (1-3 days) |
| [`investigate.md`](./investigate.md) | Answering a question with multiple plausible answers | 1-2 hours |
| [`capability-to-implementation.md`](./capability-to-implementation.md) | 推进 agent 能力级工作(工具层/调用协议/god-class 拆分/Kit 接线)从想法到实施 | varies (1-3 days) |

## How to use a pattern

1. **Read the Trigger section** — does this apply to your situation?
2. **Check the "When NOT to use"** — if your case is there, use a different pattern (or none)
3. **Follow the Quick reference** — copy-paste the commands
4. **Read the Full procedure** when you need context for a step
5. **Use the Anti-patterns section** as a checklist before committing

## Adding a new pattern

When you find yourself doing a task repeatedly (3+ times), write a pattern:

1. `cp docs/template/{some-template}.md docs/agents/patterns/{task-slug}.md` — or write from scratch
2. Structure (recommended):
   - **When to use** (1 line)
   - **When NOT to use** (anti-patterns)
   - **Quick reference** (commands)
   - **Full procedure** (step-by-step)
   - **Common pitfalls**
   - **Anti-patterns** (what NOT to do)
   - **Related** (links to other patterns / docs)
   - **Last updated** (date)
3. Add it to the table in this `index.md`
4. Run `node scripts/naming-lint/index.mjs` to verify
5. Commit: `docs(agents): add pattern-{task-slug}`

Patterns should be **specific recipes**, not general documentation. If a pattern is too general, it's probably a spec or ADR instead.

## Pattern vs skill — when to use which

- **Pattern** (here): "How do I do task X in this repo?" — concrete steps, this repo's tools
- **Skill** (e.g. `tdd`, `domain-modeling`): "How do I do task X in general?" — methodology, applies anywhere

Use a pattern when the answer depends on **this repo's tools and conventions**. Use a skill when the answer is the same across projects.

## Last updated

2026-09-02 (created as part of naming governance refactor)