# Pattern: Refactor X (TDD-driven)

> **When to use:** You're changing the internal structure of code without changing its observable behavior. Examples: extract a service, rename a function across the codebase, split a god class, consolidate three call paths into one.

> **Audience:** agents + humans

## Trigger

- A spec exists at `docs/specs/NNN-{slug}.md` with a TDD plan
- OR you have an ADR at `docs/adr/NNNN-{slug}.md` that says "refactor X"
- OR the code is **objectively wrong** by current conventions (e.g. violates naming-conventions.md)
- OR there's a TODO in the code that's well-defined

## When NOT to use

- The change also changes **behavior** — that's a new feature, not a refactor
- The change is "extract method" on 5 lines — just commit it
- You're not sure the new structure is better — prototype first

## Quick reference

```bash
# 1. Identify existing tests for the area
git log --oneline -- <path-to-area> | head -10
# (find which tests cover the behavior you're about to refactor)

# 2. Verify existing tests pass
node --test <existing-test-glob>

# 3. Refactor in atomic commits (Red → Green → Refactor)
# (see "Full procedure" below)

# 4. Verify after each commit
node --test <existing-test-glob>
node scripts/naming-lint/index.mjs
```

## Full procedure (TDD red → green → refactor)

### Step 1: Find existing tests (5 min)

Before changing code, find what tests cover the area. Run them.

```bash
# Recent commits to the area
git log --oneline -- agents/src/main/ets/subagents/KnowledgeModel.ets | head -10

# Tests in the same dir
ls agents/src/test/      # ArkTS / Hypium
node --test scripts/arkts-lint/tests/*.test.mjs  # Node tests
```

If no tests exist for the behavior you're refactoring, **write them first** (that's "characterization tests"). See the `investigate.md` pattern.

### Step 2: Write characterization tests (if needed, 20-60 min)

If the existing test surface doesn't cover the behavior you're refactoring, add tests BEFORE refactoring. These are "characterization tests" — they pin down the current behavior so you can verify it's preserved.

```ts
// Example: before splitting a 929-line class
test('KnowledgeModel.structure returns correct unit for math input', () => {
  // pin current behavior
});
```

### Step 3: Refactor in atomic commits (10-30 min per commit)

Each commit should:
- Be self-contained (can be reverted without breaking anything else)
- Preserve observable behavior (all tests pass)
- Have a clear message (conventional commit)

**Pattern for god-class splits**:
1. **First commit**: extract one helper into a new file; update the original to call it
2. **Second commit**: extract another helper
3. **Nth commit**: when only the orchestrator remains, split the orchestrator itself

For each commit:
```bash
git checkout -b refactor/{topic}
# edit code
node --test <existing-test-glob>     # all pass
git add -p
git commit -m "refactor(llm): extract {helper-name} from LlmClient"
```

### Step 4: Update tests (if call sites change)

If the refactor changes the **public API** (renames a method, changes a signature), update tests + call sites. If only **internal** structure changes, tests stay the same.

### Step 5: Verify

```bash
node --test <existing-test-glob>          # all pass
node scripts/naming-lint/index.mjs      # 0 violations
node scripts/link-check/index.mjs        # 0 broken links
```

### Step 6: Update ADR/spec references

If the refactor changes an interface documented in an ADR/spec:
- Update the spec at `docs/specs/NNN-{slug}.md` (mark items done, add notes)
- If the refactor contradicts an existing ADR, add a "supersedes" note

### Step 7: Commit + PR

```bash
git add .
git commit -m "refactor(llm): collapse 3 call paths to call(opts) per spec 005"
git push -b origin feature/dispatcher-single-entry  # (per AGENTS.md: never push to main)
```

## Common pitfalls

- **Don't refactor + change behavior in one commit.** The reviewer can't tell what's a refactor vs. a feature. Use TDD: pin behavior first, refactor with tests as the safety net.
- **Don't skip the verification step.** Even "obvious" refactors can break a test. Run lint + tests after every commit.
- **Don't leave the working tree dirty** between commits. Each commit should be a clean checkpoint.
- **Don't rename public APIs casually.** If you must, update all call sites in the same commit, OR provide a deprecation path (keep old method, add new one, deprecate next release).

## Anti-patterns

- ❌ "Refactor while I'm at it" — leave unrelated cleanups for separate commits / PRs
- ❌ "Let me just rewrite this whole module" — that's a rewrite, not a refactor
- ❌ "Tests will be done in a follow-up PR" — they're part of THIS refactor
- ❌ "I'll refactor without running tests" — they'll fail somewhere you didn't expect

## Related

- [naming-conventions spec](../../style/naming-conventions.md) — what to name the new files
- [ADR template](../../template/adr-template.md) — for recording the decision
- [Spec template](../../template/spec-template.md) — for the TDD plan
- TDD skill (built-in): for the red-green-refactor loop

## Last updated

2026-09-02 (created as part of naming governance refactor)