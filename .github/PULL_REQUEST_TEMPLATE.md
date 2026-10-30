# Pull Request

> **Required**: complete every section below. CI will fail if Lint section is not marked.

---

## Summary

<!-- 1-3 sentences: what does this PR do and why? -->

**Tied to ticket(s)**: <!-- e.g. #3, #16, or "none — housekeeping" -->

**Type**: <!-- one of: feat / fix / refactor / docs / test / chore / style -->

**Branch type**: <!-- one of: feature / release / hotfix / bugfix; per `docs/agents/git-conventions.md` §"分支工作流" -->

**Target branch**: <!-- usually `develop` for feature/bugfix, `main` for release/hotfix -->

**Merge strategy**: <!-- squash for feature/bugfix; merge commit for release/hotfix -->

---

## Changes

<!-- Bullet list of concrete changes. Link files where useful. Use `[path/to/file.ts:42]` style refs. -->

- [ ] <!-- change 1 -->
- [ ] <!-- change 2 -->
- [ ] <!-- change 3 -->

---

## Test plan

<!-- How was this verified? Be specific — "I ran X, saw Y, then did Z". -->

- [ ] Manual smoke test (per [`docs/agents/smoke-test.md`](../docs/agents/smoke-test.md) if UI change)
- [ ] Unit test added/updated (if logic change)
- [ ] E2E verified (if full-chain change: OCR / LLM / DB)

**Manual verification log** (optional but recommended for non-trivial changes):

```
# command / observation / result
```

---

## Lint

> **Required**: CI fails if any item below is ❌.

- [ ] `node scripts/naming-lint/index.mjs` — 0 violations
- [ ] `node scripts/link-check/index.mjs` — 0 broken links
- [ ] `node scripts/arkts-lint/index.mjs --quiet` — 0 errors (if `.ets` files changed)
- [ ] `npm --prefix scripts/arkts-lint test` — all green (if `.ets` files changed)

---

## Documentation

- [ ] `AGENTS.md` pointer table updated (if you added/changed a doc location)
- [ ] `docs/index.md` updated (if you added a new top-level doc directory)
- [ ] New ADR created via [`docs/template/adr-template.md`](../docs/template/adr-template.md) (if hard-to-reverse architectural decision)
- [ ] New spec created via [`docs/template/spec-template.md`](../docs/template/spec-template.md) (if implementation plan introduced)

---

## Risks & Rollback

**Risk level**: <!-- low / medium / high -->

**What could break**: <!-- 1-2 sentences -->

**Rollback plan**: <!-- `git revert <sha>` is the default; specify anything else -->

---

## Reviewer checklist

<!-- For the reviewer — copy to comments when reviewing -->

- [ ] Commit messages follow conventional commits + module prefix (per [`docs/agents/git-conventions.md`](../docs/agents/git-conventions.md))
- [ ] Commits land on `feature/*` / `bugfix/*` / `hotfix/*` / `release/*` (per `docs/agents/git-conventions.md` §"分支工作流");NOT on `main` or `develop`
- [ ] No secrets / API keys committed (per [`docs/agents/security.md`](../docs/agents/security.md))
- [ ] Diff size is proportional to ticket scope (no drive-by refactors)
- [ ] Public API changes called out in Summary
- [ ] Tests cover the happy path + at least one error path
- [ ] If touching the audit-tracked code, no new warnings introduced (lint baseline: see [`docs/legacy/mindtrace/architecture/lint-baseline-ast-2026-09-01.json`](../docs/legacy/mindtrace/architecture/lint-baseline-ast-2026-09-01.json))

---

## Related

<!-- Links to ADRs, specs, prior PRs, or related issues -->

- ADR: <!-- e.g. `docs/adr/0006-knowledge-model-decomposition-plan.md` -->
- Spec: <!-- e.g. `docs/specs/036-multi-image-single-pass-consolidation.md` -->
- Closes: <!-- e.g. #16 -->
- Follow-up: <!-- e.g. "post-merge, file ticket for #3 follow-up" -->

---

<!-- For the merger: after PR is merged, close any linked tickets and update audit log. -->