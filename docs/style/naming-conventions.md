# Naming Conventions

> **Authority:** This file is the single source of truth for all naming rules in this repo. AGENTS.md references it for hard rules. When in doubt, this file wins.
>
> **Scope:** All files — docs (`.md`), code (`.ts`/`.tsx`/`.py`/`.mjs`/`.json`/`.json5`/`.yml`), configs, and directories.
>
> **Version:** 1.1 (last updated 2026-09-02)

---

## Versioning

This spec follows [Semantic Versioning](https://semver.org/) (MAJOR.MINOR.PATCH):

- **MAJOR** bump — breaking change. Any rule in this spec changes such that existing files become violations. E.g. adding a new rule, changing an existing rule, renaming a category.
- **MINOR** bump — additive change. New rules or sections are added. Existing files are NOT affected.
- **PATCH** bump — clarification or wording fix only. No rule changes.

**When to bump:**

| Change | Bump |
|---|---|
| Renaming a section without rule change | PATCH |
| Adding a new rule (e.g. "no .html in docs/") | MINOR |
| Expanding an existing rule (e.g. "skip _template.mjs" → "skip files starting with _") | MINOR |
| Tightening a rule (e.g. "kebab-case" → "kebab-case with 50-char limit") | MAJOR (existing files may violate) |
| Changing the lint tool's exit code semantics | MAJOR |
| Fixing a typo / clarifying wording | PATCH |

**Version policy enforcement:**
- Each commit that changes this file bumps the version in the header
- The version is referenced in [`scripts/naming-lint/index.mjs`](../../scripts/naming-lint/index.mjs) `--json` output
- Breaking changes (MAJOR) require a migration note in this file

## Changelog

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-09-02 | Initial spec with 9 sections (universal, top-level, docs, code branches, commits, forbidden) |
| 1.1 | 2026-09-02 | Added §2.1 top-level whitelist, expanded §5 branches, expanded §6 commits, added §7 test files, added §8 file headers, added §9 generated files, added §10 env files, added §11 logs/temp, expanded §12 forbidden, added §13 validation, added §14 when to update, bumped version 1.0 → 1.1 |

---

## 1. Universal Rules

These apply to **every** file and directory in this repo.

| Rule | Correct | Incorrect |
|---|---|---|
| **No spaces in file/dir names** | `state-graph.md` | `state graph.md` |
| **kebab-case for doc/config files and directories** | `layer-boundaries.md`, `langgraph-rules/` | `layerBoundaries.md`, `langgraph_rules/` |
| **kebab-case for code file basenames (most languages)** | `has-decorator.mjs`, `qa-chain.py` | `hasDecorator.mjs`, `qaChain.py` |
| **Date suffix is `YYYY-MM-DD`** (with dashes) | `langgraph-vs-mvp-2026-09-15.md` | `langgraph-vs-mvp-20260915.md` ❌, `langgraph-vs-mvp-2026_09_15.md` ❌ |
| **No leading numbers in doc names** (ADR/spec numbers are fine as prefix) | `001-dispatcher.md` (spec) | `2026-09-02-report.md` (unless it's a date suffix) |
| **No abbreviations that aren't widely known** | `service.ts`, `state.md` | `svc.ts`, `st.md` |
| **Renames must use `git mv`** (preserves history) | `git mv old.md new.md` | `mv old.md new.md` ❌ |

## 2. Top-level Files

### 2.1 Whitelist (top-level repo files)

The following are the only files allowed at the repo root. Anything else must be in `docs/`, `scripts/`, or a subdirectory.

| Path | Naming | Required? | Notes |
|---|---|---|---|
| `AGENTS.md` | exact | **Required** | Agent entry point, navigation, hard rules |
| `CONTEXT.md` | exact | **Required** | Project glossary (project-specific terms) |
| `README.md` | exact | **Required** | Human-facing project overview |
| `LICENSE` | exact | required for distribution | SPDX format, no extension |
| `NOTICE` | exact | optional | Third-party attributions |
| `SECURITY.md` | exact | optional | Security policy / how to report |
| `CHANGELOG.md` | exact | optional | Release history (use semver) |
| `CONTRIBUTING.md` | exact | optional | For external contributors |
| `CODE_OF_CONDUCT.md` | exact | optional | Community standards |
| `package.json` | exact | per-language | Node tooling |
| `tsconfig.json` | exact | per-language | TypeScript root config |
| `pyproject.toml` | exact | per-language | Python tooling |
| `build-profile.json5` | exact | per-platform | DevEco / HarmonyOS |
| `oh-package.json5` | exact | per-platform | DevEco / HarmonyOS |
| `start_*.bat`, `start_*.sh` | `kebab-case` (lowercase) | optional | Convenience scripts |
| `.gitignore` | exact | **Required** | See `docs/agents/git-conventions.md` for the actual rules |
| `.editorconfig` | exact | recommended | Auto-applied by IDEs |
| `.gitattributes` | exact | recommended | LF line endings, linguist flags |

### 2.2 Naming rule

If a file is not in the whitelist, it must be in a subdirectory (`docs/`, `scripts/`, etc.). Common-level files use UPPERCASE single-word (e.g. `AGENTS.md`); project-level use `kebab-case` (e.g. `package.json`).

## 3. Documentation Files (`docs/`)

### 3.1 Path Conventions

| Type | Path | File naming |
|---|---|---|
| ADR (Architecture Decision Record) | `docs/adr/` | `NNNN-{topic-slug}.md` (4-digit seq) |
| ADR index | `docs/adr/` | `index.md` |
| Spec (implementation spec) | `docs/specs/` | `NNN-{topic-slug}.md` (3-digit seq) |
| Spec index | `docs/specs/` | `index.md` |
| Style / coding standard | `docs/style/` | `{scope}-{topic}.md` |
| Research note | `docs/research/` | `{topic-slug}-{YYYY-MM-DD}.md` |
| Agent workflow pointer docs | `docs/agents/` | `{topic-slug}.md` |
| Agent handoff (session 交接) | `docs/agents/handoffs/` | `{topic-slug}-handoff-{YYYY-MM-DD}.md` |
| Template (canonical) | `docs/template/` | `{doc-type}-template.md` |
| **Legacy / old project** | `docs/legacy/{project}/` | (preserves old naming — frozen) |

### 3.2 ADR — `NNNN-{topic-slug}.md`

- `NNNN` = 4-digit zero-padded sequence (`0001`, `0002`, …). Permanent — never renumber.
- `{topic-slug}` = kebab-case, ≤ 5 words, describes the decision, not the area.
- Example: `0001-layer-boundaries-in-5-module-arkts-app.md`

### 3.3 Spec — `NNN-{topic-slug}.md`

- `NNN` = 3-digit zero-padded sequence.
- `{topic-slug}` matches the corresponding ADR where possible.
- Example: `003-knowledge-model-decomposition.md`

### 3.4 Style — `{scope}-{topic}.md`

- `{scope}` is the framework or topic: `langgraph`, `react`, `arkts`, `python`, `naming`, etc.
- `{topic}` is `style`, `strict`, `atomic`, `hooks`, `conventions`, etc.
- Examples: `langgraph-style.md`, `react-atomic.md`, `naming-conventions.md`

### 3.5 Research — `{topic-slug}-{YYYY-MM-DD}.md`

- One research file per investigation. One date per question, not per update.
- HTML rendered version: same name + `.html` (gitignored, generated only).

### 3.6 Architecture / audit — `{scope}-{YYYY-MM-DD}.md`

- One file per audit. No re-audits under the same date.

### 3.7 Agent workflow pointer docs (`docs/agents/`)

- One topic per file: `domain.md`, `issue-tracker.md`, `triage-labels.md`, `git-conventions.md`, etc.
- Each file is **a pointer to a deeper doc or a process**, not the full content.

### 3.8 Legacy (`docs/legacy/{project}/`)

- Frozen subdirectory: old project's docs go here, no new docs added.
- The `project` name identifies the project (e.g., `mindtrace`).
- Subdirs preserve the original structure (`docs/legacy/mindtrace/adr/`, `…/specs/`, `…/research/`).

## 4. Code Files

### 4.1 TypeScript (`.ts`)

| What | Naming | Example |
|---|---|---|
| File basename | `kebab-case.ts` | `http-client.ts`, `format-date.ts` |
| Class | `PascalCase` | `class Dispatcher { … }` |
| Interface | `I` + `PascalCase` | `interface IDispatcher { … }` |
| Type alias | `T` + `PascalCase` | `type TState = …` |
| Enum | `PascalCase` | `enum Direction { … }` |
| Function | `camelCase` | `function buildPrompt() { … }` |
| Variable | `camelCase` | `const maxRetry = 3` |
| Constant | `UPPER_SNAKE_CASE` | `const MAX_RETRY = 3` |
| Test | `{name}.test.ts` (sibling) or `__tests__/{name}.test.ts` | `http-client.test.ts` |

### 4.2 React (`.tsx`)

| What | Naming | Example |
|---|---|---|
| File basename (component) | `PascalCase.tsx` | `Button.tsx`, `SearchField.tsx` |
| File basename (non-component, e.g. utility) | `kebab-case.tsx` | `layout-helper.tsx` |
| Class component | `PascalCase` extending `React.Component` | `class UserCard extends React.Component { … }` |
| Function component | `PascalCase` (function declaration) or `PascalCase` const | `function Button() { … }` or `const Button = () => { … }` |
| Hook | `use` + `PascalCase` | `useAuth.ts`, `useFetch.ts` |
| Prop type | Component name + `Props` | `ButtonProps` |
| Test | `{Name}.test.tsx` (sibling) | `Button.test.tsx` |

### 4.3 Atomic Design (React)

The frontend follows Brad Frost's Atomic Design. Each layer has a strict directory and naming:

| Layer | Directory | File naming | Examples |
|---|---|---|---|
| **Atom** | `frontend/src/atoms/` | `PascalCase.tsx` (no `Atom` suffix) | `Button.tsx`, `Input.tsx`, `Label.tsx`, `Icon.tsx` |
| **Molecule** | `frontend/src/molecules/` | `PascalCase.tsx` | `SearchField.tsx`, `FormField.tsx` |
| **Organism** | `frontend/src/organisms/` | `PascalCase.tsx` | `Header.tsx`, `UserCard.tsx` |
| **Template** | `frontend/src/templates/` | `PascalCase.tsx` | `MainLayout.tsx`, `AuthLayout.tsx` |
| **Page** | `frontend/src/pages/` | `{Name}Page.tsx` | `HomePage.tsx`, `LoginPage.tsx` |
| **Service** | `frontend/src/services/` | `{name}-service.ts` or `{name}Service.ts` (be consistent within layer) | `auth-service.ts`, `http-client.ts` |
| **Hook** | `frontend/src/hooks/` | `use{Name}.ts` | `useAuth.ts`, `useFetch.ts` |
| **Util** | `frontend/src/utils/` | `{name}.ts` | `format-date.ts` |
| **Type** | `frontend/src/types/` | `{name}-types.ts` or `{name}.ts` | `api-types.ts` |
| **Test** | sibling `*.test.tsx` | — | `Button.test.tsx` |

**Layer rules:**
- Atom: no other component dependency; single-purpose
- Molecule: composed of atoms; minimal or no state
- Organism: business logic; may have state and side effects
- Template: page skeleton with slots; no business content
- Page: route endpoint; composes template + organisms + molecules + atoms
- Service: API client / external integration (no React)

A file's directory determines its layer. **Don't put a `Page.tsx` in `atoms/`** — that would violate the layer rule.

### 4.4 Python (`.py`)

| What | Naming | Example |
|---|---|---|
| File basename | `snake_case.py` | `state_graph.py`, `retrieve_node.py` |
| Class | `PascalCase` | `class StateGraph: …` |
| Module-level function | `snake_case` | `def build_prompt() → str: …` |
| Variable | `snake_case` | `max_retry = 3` |
| Constant | `UPPER_SNAKE_CASE` | `MAX_RETRY = 3` |
| Private (module-internal) | `_` prefix | `def _helper(): …` |
| Test | `{name}.test.py` (sibling) or `tests/test_{name}.py` | `retrieve_node.test.py` |

### 4.5 LangGraph Backend

| Role | Directory | File naming | Example |
|---|---|---|---|
| State schema (TypedDict) | `backend/src/graphs/state/` | `{graph}_state.py` | `qa_state.py` |
| Node (atom) | `backend/src/nodes/` | `{verb}_node.py` | `retrieve_node.py`, `classify_node.py` |
| Node class | (same file) | `{Verb}Node` | `class RetrieveNode: …` |
| Chain (molecule) | `backend/src/chains/` | `{name}_chain.py` | `rag_chain.py` |
| Graph (organism) | `backend/src/graphs/` | `{name}_graph.py` | `qa_graph.py` |
| Service | `backend/src/services/` | `{name}_service.py` | `vector_store.py`, `llm_client.py` |
| Tool | `backend/src/tools/` | `{name}_tool.py` | `search_tool.py` |
| Checkpointer | `backend/src/checkpointers/` | `{backend}_checkpointer.py` | `postgres_checkpointer.py` |
| Test | sibling `*.test.py` | — | `retrieve_node.test.py` |

**Layer rules (mirror Atomic Design):**
- **Node (atom)**: one operation; takes/returns a `dict` (state slice)
- **Chain (molecule)**: composes 2+ nodes; a sub-graph
- **Graph (organism)**: full `StateGraph` with entry/exit; entry point of an agent

### 4.6 JavaScript / Node (`.mjs`, `.cjs`)

| What | Naming | Example |
|---|---|---|
| File basename | `kebab-case.mjs` | `parse-arkui.mjs`, `index.mjs` |
| Function | `camelCase` | `function buildRule() { … }` |
| Constant | `UPPER_SNAKE_CASE` | `const MAX_RETRIES = 3` |
| Test | `{name}.test.mjs` (sibling) | `parser.test.mjs` |

### 4.7 Configs

| Type | Naming | Example |
|---|---|---|
| `package.json` | exactly `package.json` | — |
| `tsconfig.json` | `tsconfig.json` (root), `tsconfig.{name}.json` (variant) | `tsconfig.build.json` |
| `pyproject.toml` | exactly `pyproject.toml` | — |
| `.eslintrc` family | `.eslintrc.{scope}.{ext}` | `.eslintrc.js`, `.eslintrc.react.js` |
| `vite.config.ts` | `vite.config.ts` (build-tool-specific, keep) | — |
| `*.yml` / `*.yaml` | `kebab-case.yml` | `arkts-lint.yml` |

## 5. Branches

### 5.1 Main branch

- `main` — protected, no direct commits (only via PRs from work branches).
- `develop` — long-lived integration branch, no direct commits (only via PRs from `feature/*` / `bugfix/*`).
- Local work happens on `feature/*` / `bugfix/*` (per `docs/agents/git-conventions.md` §"分支工作流").

### 5.2 Work branch names

Format: `<prefix>/<short-description>`

| Prefix | When to use | Examples |
|---|---|---|
| `feat/` | new feature or capability | `feat/langgraph-state-graph`, `feat/atomic-modal` |
| `fix/` | bug fix | `fix/preview-units-leak`, `fix/llm-config-overwrite` |
| `refactor/` | code change without behavior change | `refactor/dispatcher-single-entry` |
| `docs/` | docs only | `docs/naming-conventions`, `docs/adopt-langgraph` |
| `test/` | test addition/correction | `test/12-test-baseline` |
| `chore/` | tooling, deps, no production change | `chore/bump-node-20`, `chore/lockfile-update` |
| `release/` | release prep (version bump) | `release/v1.0.0` |
| `user/<name>/` | personal WIP (rare) | `user/alice/proto-state-graph` |

### 5.3 Constraints

- `kebab-case` only — no spaces, no underscores, no uppercase
- ≤ 50 characters total (descriptive but not novel-length)
- No issue numbers (use commit message body, not branch name)
- One branch per ticket; delete after merge

## 6. Commit Messages

### 6.1 Format (Conventional Commits)

```
<type>(<scope>): <subject>
<BLANK LINE>
<body>
<BLANK LINE>
<footer>
```

- **type**: see table below
- **scope**: affected module (lowercase, optional but recommended)
- **subject**: 50 chars max, imperative mood, no period, no uppercase
- **body**: 72 chars per line, explain what & why (not how)
- **footer**: references (e.g. `Refs: #N`, `Closes: #N`)

### 6.2 Types

| Type | When |
|---|---|
| `feat` | new feature or capability |
| `fix` | bug fix |
| `refactor` | code change without behavior change |
| `docs` | documentation only |
| `test` | test addition/correction |
| `chore` | tooling, deps, no production change |
| `style` | formatting only |
| `perf` | performance improvement |
| `ci` | CI / build changes |

### 6.3 Scopes (recommended)

- `frontend`, `backend`, `agents`, `common`, `entry` — modules
- `lint`, `docs`, `agents` — meta concerns
- `tests` — test infrastructure
- `(no scope)` — repo-wide refactor

### 6.4 Examples

- `fix(backend): throw LlmError on reserved keyword override`
- `docs(agents): add naming-conventions spec`
- `chore(lint): exclude HTML reports from git`
- `feat(frontend): add Button atom to atomic design`

## 7. Test Files

### 7.1 Test file naming

| Stack | Sibling | Test dir | Notes |
|---|---|---|---|
| TypeScript / Node | `{name}.test.ts` | `__tests__/{name}.test.ts` | sibling preferred |
| React | `{Name}.test.tsx` | `__tests__/{Name}.test.tsx` | component test in same dir |
| Python | `{name}.test.py` | `tests/test_{name}.py` | pytest convention |
| LangGraph | `{name}.test.py` | `tests/{name}/` | graph-level test |

### 7.2 Test name (inside the test)

- `describe` / `it` for JS, `def test_*` for Python
- Format: `test_<action>_<expected>` or `it('should <expected>')`
- Example: `test_reserved_keyword_throws`, `it('should normalize empty input')`

### 7.3 What NOT to put in test filenames

- Date suffixes (not research, tests are tied to code)
- Long descriptions (move description to test name inside the file)
- Version numbers

## 8. File Headers (per language)

Each language has its own header convention. Apply consistently in every new file.

### 8.1 Markdown (`.md`)

```markdown
# Title

> One-line summary of what this file is and why it exists.

## Section 1

...
```

### 8.2 TypeScript (`.ts`)

```typescript
/**
 * {FileName}.ts — {one-line role}
 *
 * 路径: {path from src/}
 * 职责: {specific responsibility}
 * 依赖: {imports}
 *
 * 数据流:
 *   {upstream} → {this file's key function} → {downstream}
 */
```

### 8.3 Python (`.py`)

```python
"""
{FileName}.py — {one-line role}

Responsibility: {specific responsibility}
Dependencies: {imports}

Data flow:
    {upstream} → {key function} → {downstream}
"""
```

### 8.4 React (`.tsx`)

```typescript
/**
 * {ComponentName}.tsx — {one-line role}
 *
 * Layer: Atom | Molecule | Organism | Template | Page
 * Props: {PropName} — {description}
 *
 * Used by: {parent components}
 */
```

### 8.5 YAML (`.yml`)

```yaml
# Purpose: {what this config does}
# Owner: {team or person}
# Last updated: YYYY-MM-DD

key: value
```

## 9. Generated and Vendored Files

These files are typically **not** hand-written and should be excluded from naming lint:

| Pattern | Source | Naming |
|---|---|---|
| `*.gen.ts` / `*.gen.tsx` | codegen output | kebab-case gen-name (e.g. `api-types.gen.ts`) |
| `__generated__/` | schema codegen, GraphQL | match source schema |
| `*.pb.go` / `*.pb.cc` | protobuf | match source proto |
| `vendor/` (Go) | third-party copy | preserve upstream naming |
| `third_party/` (C++) | third-party | preserve upstream naming |
| **`*.html` in `docs/`** | pandoc / vitepress / mermaid render | **don't commit** — see [`./html-in-docs.md`](./html-in-docs.md) |

**Rule**: Generated files should be marked with `# AUTO-GENERATED — DO NOT EDIT` at the top, AND `.gitattributes` should mark them `linguist-generated` so diff stats don't count them.

**HTML in docs/** (special case): HTML is a render, not a source. See [`./html-in-docs.md`](./html-in-docs.md) for the full decision tree, recipes for each case (generated / paired render / frozen legacy / true source), and how to whitelist specific files in `.naminglintrc.json` when they're intentional.

**Linter behavior**: `scripts/naming-lint/index.mjs` should skip these paths (currently it skips `node_modules/`, `build/`, etc.; add generated paths as needed).

## 10. Environment Configuration Files

Env files configure runtime, never check into git with secrets.

| File | Committed? | Notes |
|---|---|---|
| `.env` | **NO** | Real secrets, machine-specific |
| `.env.local` | **NO** | Local-only overrides |
| `.env.production` | **NO** | Production-only, has real secrets |
| `.env.development` | **NO** | Dev-only, has real keys |
| `.env.test` | **NO** | CI secrets |
| `.env.example` | **YES** | Template with empty / placeholder values |
| `.env.sample` | **YES** | Same as .env.example |
| `local.properties` | **NO** (usually gitignored) | HarmonyOS DevEco machine-specific |

**Rule**: If you must commit an env file, name it `.env.example` or `.env.sample` and **strip all real values**. Only `EXAMPLE_API_KEY=` (empty) is allowed.

## 11. Logs and Temp Files

These files are runtime outputs / editor scratch / system state. They should **never** be committed.

| Pattern | Source | Gitignore? |
|---|---|---|
| `*.log` | application logs | yes |
| `*.pid` | process IDs | yes |
| `*.seed` | random seeds | yes |
| `*.pid.lock` | lockfiles | yes |
| `nohup.out` | Unix nohup | yes |
| `core.*` (core dump) | crash dumps | yes |
| `*.bak`, `*.tmp` | backup / temp | yes |
| `*.swp`, `*.swo` | vim swap | yes |
| `*.rej`, `*.orig` | merge conflicts | yes |
| `.DS_Store` | macOS metadata | yes |
| `Thumbs.db` | Windows metadata | yes |
| `desktop.ini` | Windows folder metadata | yes |
| `*.tsbuildinfo` | TypeScript build cache | yes |

**Rule**: If you see any of these in `git status`, **do not** `git add` them. Add a `.gitignore` line if needed.

## 12. Forbidden Patterns

| Anti-pattern | Why |
|---|---|
| Spaces in file/dir names | breaks shell, npm scripts, URLs |
| `camelCase.md` in `docs/` | inconsistent with kebab-case for all other docs |
| `snake_case.md` in `docs/` | inconsistent |
| `YYYYMMDD.md` date suffix | harder to read, no separator |
| `lb.md`, `tmp.md`, `new.md` | abbreviations / generic names |
| `My Component.tsx` (space + capital in name) | breaks JSX, looks like import |
| `mv old.md new.md` (without `git`) | loses git history |
| `package-lock.json` (committed) | except where intended (`scripts/*/package-lock.json` is intentionally committed for CI reproducibility) |
| `.html` in `docs/research/` or `docs/legacy/` | HTML is a generated render, not the source — only `.md` is committed. See [`./html-in-docs.md`](./html-in-docs.md) for exceptions and recipes. |
| `node_modules/`, `build/`, `oh_modules/`, `dist/` | always gitignored |
| `__pycache__/`, `*.pyc` | Python bytecode |
| `__snapshots__/`, `__mocks__/` | test framework internals (gitignored) |
| Hand-edited `*.gen.ts` | generated, modify the source instead |
| `package.json` rename to `package.jsonc` | not a real format, breaks tooling |

## 13. Validation

The `scripts/naming-lint/` tool enforces these rules in CI. Run locally:

```bash
node scripts/naming-lint/index.mjs                     # human-readable
node scripts/naming-lint/index.mjs --json docs scripts  # CI / pre-commit
node scripts/naming-lint/install-hook.mjs install      # install pre-commit hook
node scripts/naming-lint/install-hook.mjs uninstall    # remove pre-commit hook
```

Run before any commit:

```bash
node scripts/naming-lint/index.mjs && node --test scripts/naming-lint/tests/*.test.mjs
```

## 14. When to Update This File

- New framework or tool adopted (e.g., adding Go): add a code-file section
- New doc type (e.g., RFCs): add to section 3
- New forbidden pattern discovered: add to section 12
- Layer rule change (e.g., new component layer): update section 4.3 or 4.5
- New section gap: add it

Update via a `docs(naming):` commit, with the diff in the body explaining why. Bump the version (top of file) on breaking changes.