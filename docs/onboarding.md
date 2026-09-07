# Onboarding Guide

> **For:** new agents, new human contributors, evaluators
> **Time:** 5-minute tour, 30-minute deep dive, common tasks

This guide helps you orient quickly. After this, you'll know:
1. What this repo is and what to do first
2. Where the entry points are
3. Where to find what you need
4. How to add a new doc / file safely

---

## 5-Minute Tour (everyone)

### What is this?

MindTrace is a **HarmonyOS math learning assistant** for the **鸿蒙高校创新赛 semifinal (复赛)**. It has:

- 5 modules (1 HAP + 4 HSP): `entry`, `common`, `agents`, `skill`, `cardservice`
- AI pipeline: photo → OCR → classify → structure → persist
- Custom ArkTS lint engine (34 rules, 70 tests)
- Architecture: 4 layers + 5 modules (see `AGENTS.md`)

### Read in this order

1. **Top of [`AGENTS.md`](../AGENTS.md)** — project context + 7 hard rules
2. **Top of [`CONTEXT.md`](../CONTEXT.md)** — project glossary (KnowledgeUnit, CaptureGraph, …)
3. **Top of [`docs/index.md`](./index.md)** — full doc navigation
4. The "改什么 → 读哪" pointer table in `AGENTS.md` — answers "where do I find X?"

### 1-minute sanity check

```bash
# Are you in the right repo?
pwd                                      # should be <本地仓库根>
git status                               # should be clean
node scripts/naming-lint/index.mjs       # should print "OK: 0 violations"
node scripts/link-check/index.mjs         # should print "OK: 0 broken links"
```

If all three pass, you're set up correctly.

---

## 30-Minute Deep Dive (agents + serious contributors)

### 1. Read the design layer (15 min)

- [`docs/adr/`](./adr/) — architecture decisions, **read in order**
- [`docs/specs/`](./specs/) — implementation specs (TDD plans)
- [`docs/style/arkts-1.1.md`](./style/arkts-1.1.md) — 40+ ArkTS rules
- [`docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md`](./legacy/mindtrace/architecture/audit-full-2026-09-01.md) — 21 audit findings

### 2. Read the code (10 min)

- `agents/src/main/ets/core/Dispatcher.ets` — main agent orchestrator (single entry `dispatch`, runs the CaptureGraph)
- `common/src/main/ets/llm/LlmClient.ets` — LLM call layer
- `agents/src/main/ets/agents/KnowledgeModel.ets` — knowledge structuring orchestration agent (spec 015 done: PromptBuilder / TruthCheckService collaborators extracted)
- `scripts/arkts-lint/index.mjs` — the custom AST lint engine

### 3. Run the tests (5 min)

```bash
# 111 unit tests across the project
node --test scripts/arkts-lint/tests/*.test.mjs          # 70 tests
node --test scripts/naming-lint/tests/*.test.mjs         # 23 tests (8 helpers + 15 config)
node --test scripts/link-check/tests/link-parser.test.mjs # 18 tests
```

---

## Common Tasks

### "I want to add a new ADR"

1. `cp docs/template/adr-template.md docs/adr/NNNN-{topic-slug}.md` (next sequence number)
2. Fill in the template (Context, Considered Options, Consequences, Reversibility, When to revisit, Related)
3. Run `node scripts/naming-lint/index.mjs` to confirm the file name is correct
4. Add a row to `AGENTS.md` ticket table if it's a P0/P1
5. Commit: `docs(adr): add NNNN-{topic-slug}`

### "I want to add a new spec"

1. `cp docs/template/spec-template.md docs/specs/NNN-{topic-slug}.md`
2. Reference the corresponding ADR in the header
3. Include a TDD plan (Red → Green → Refactor)
4. Run `node scripts/naming-lint/index.mjs` and `node scripts/link-check/index.mjs`

### "I want to add a new agent workflow doc"

1. `cp docs/template/agent-workflow-template.md docs/agents/{topic-slug}.md`
2. Fill the sections: When to use / NOT use / Quick reference / Procedure / Pitfalls
3. Add a row to `AGENTS.md` pointer table
4. Run lint + link-check

### "I want to fix a lint violation"

```bash
node scripts/naming-lint/index.mjs --json > /tmp/lint.json
# Inspect violations:
cat /tmp/lint.json | jq '.violations[] | "\(.path) [\(.rule)]: \(.message)"'
# Fix each: usually rename the file with git mv
git mv <bad-name> <good-name>
# Verify
node scripts/naming-lint/index.mjs
```

### "I want to fix a broken link"

```bash
node scripts/link-check/index.mjs --json | jq '.broken[] | "\(.sourceFile):\(.line)  ->  \(.href)"'
# Edit the source file, fix the path
# Verify
node scripts/link-check/index.mjs
```

### "I want to add a CI guard"

The CI lives at `.github/workflows/`. Existing workflows:
- `arkts-lint.yml` — 3 jobs (test, lint-ast, lint-regex) for the ArkTS lint engine
- `naming-lint.yml` — 3 jobs (test, lint, pr-comment) for the naming lint

Pattern: each new tool gets a workflow file. Mirror the `naming-lint.yml` structure.

### "I want to make a code change to .ets"

1. Check the spec in `docs/specs/NNN-{topic-slug}.md` (if it exists)
2. Check ADR in `docs/adr/NNNN-{slug}.md` (if it exists)
3. Follow TDD: write the test first (red), then implementation (green), then refactor
4. Run naming-lint + arkts-lint to confirm compliance
5. Update the spec / ADR if the change is significant

---

## What's NOT in this onboarding

- **DevEco Studio setup** — see AGENTS.md "Setup commands (DevEco Studio)" section
- **Production deployment** — not yet decided; see audit `docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md` for context
- **User-facing app testing** — see `docs/agents/smoke-test.md` (8-step manual matrix)
- **Competition details** — see AGENTS.md "比赛定位 & 演示流程" section

---

## Glossary

For project-specific terms, see [`CONTEXT.md`](../CONTEXT.md).

For naming conventions (file/dir/code), see [`docs/style/naming-conventions.md`](./style/naming-conventions.md).

For ADR / spec / research format, see the corresponding template in [`docs/template/`](./template/).

---

## Where to ask questions

- **Bug or feature request**: open a GitHub issue on `YunC-GCT/MindTrace`
- **Naming / lint question**: see `docs/agents/naming-exceptions.md`
- **CI failure**: see `docs/agents/ci-failure-workflow.md`
- **TDD / domain-modeling / writing-for-agents**: invoke those skills

---

## Last updated

2026-09-06 (counts refreshed after D2; de-hardcoded doc counts where possible)