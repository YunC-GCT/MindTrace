# link-check

> **Mirrors the structure of [`scripts/naming-lint/`](../naming-lint/)** — a single-purpose Node tool, pure-helper module, unit tests, --json output for CI.

## Purpose

Walks `docs/` (or any directory of `.md` files) and verifies that every markdown link `[text](url)` points to an existing file.

Skips:
- External URLs (`http://`, `https://`, `mailto:`, `ftp://`) — no network check
- In-page anchors (`#section-1`) — not validated

Reports:
- Broken relative links
- Source file + line + column
- Resolved absolute path (for debugging)
- Reason (e.g. "target does not exist")

## Usage

```bash
# Default: scan docs/, CONTEXT.md, AGENTS.md, README.md
node scripts/link-check/index.mjs

# Custom root
node scripts/link-check/index.mjs docs/specs

# JSON output (for CI / pre-commit hook)
node scripts/link-check/index.mjs --json

# Run unit tests
node --test scripts/link-check/tests/*.test.mjs
```

Exit codes:
- `0` = all links resolve
- `1` = one or more broken links
- `2` = config / parser error

## Skipped paths

Always skipped:
- `node_modules/`, `.git/`, `_fetched/`, `__snapshots__/`, `__generated__/`, `vendor/`
- Non-`.md` files

## Output format

### Human-readable

```
FAIL: link-check found 2 broken link(s):

  docs/specs/003-foo.md:42:5
    text:  broken link
    href:  ../adr/0000-missing.md
    → docs/adr/0000-missing.md (target does not exist)

  ...
```

### JSON (`--json`)

```json
{
  "tool": "link-check",
  "version": "0.1.0",
  "timestamp": "2026-09-04T...",
  "roots": ["docs", "CONTEXT.md", "AGENTS.md", "README.md"],
  "passed": false,
  "brokenCount": 1,
  "broken": [
    {
      "sourceFile": "docs/specs/003-foo.md",
      "line": 42,
      "column": 5,
      "linkText": "broken link",
      "href": "../adr/0000-missing.md",
      "resolvedPath": "docs/adr/0000-missing.md",
      "reason": "target does not exist"
    }
  ]
}
```

## Known limitations

- **Reference-style links** (`[text][ref]` with `[ref]: url` elsewhere) are not resolved. Only inline `[text](url)` is matched.
- **Links inside code spans** (backticks) are matched (we don't filter). This is documented behavior; filter if needed.
- **External URLs** are not checked (no network call). If a `https://` link is broken, this tool won't catch it.
- **In-page anchors** (`#section`) are not validated against actual heading IDs.

## Adding rules

- New link kinds (e.g. `tel:`): add to `classifyLink()` in `link-parser.mjs`
- New file extensions to scan (e.g. `.mdx`): update the `.endsWith('.md')` check in `walk()`
- New skip patterns: update `SKIP_DIRS` in `index.mjs` (or move to config)

## Synchronizing links after renames (`sync-renames`)

### Why links break

Markdown links in this repo are **static relative paths** (e.g. `[ADR](../adr/0001-x.md)`). They are resolved against the *directory of the file that contains them*, not against any central index. `git mv` only moves the file on disk — it does **not** rewrite the links that point at it, nor the links inside the moved file. After a rename, or a move that changes directory depth, those relative paths silently dangle and `index.mjs` reports them as broken.

`sync-renames.mjs` is the repair step: it reads git's explicit rename mapping (`git diff --name-status --find-renames`) and rewrites only the `href` portion of dangling links so they point at the file's new location.

### Two things it fixes

1. **The target moved** — `docs/a.md` links to `docs/b/old.md`; `old.md` was renamed. The link in `a.md` is updated to the new name.
2. **The referencing doc moved** — `docs/note.md` was moved to `docs/sub/note.md`. Links that resolved at the old depth are recomputed for the new depth.

### Usage

```bash
# 1) Rename with git mv (staged, so the rename is visible to git diff)
git mv docs/adr/0001-old-name.md docs/adr/0001-new-name.md

# 2) Preview what would change (dry-run, no writes)
node scripts/link-check/sync-renames.mjs --base HEAD

# 3) Apply the href rewrites
node scripts/link-check/sync-renames.mjs --base HEAD --write
```

- `--base <ref>` is the git ref to diff against the current working tree. Use `HEAD` after a fresh `git mv`; use `origin/develop` to catch renames accumulated across a whole branch (e.g. `--base origin/develop --write`).
- Without `--write` it is a **dry-run**: it prints the planned replacements and exits `0`; nothing is written.
- It never stages or commits anything — committing is a separate, explicit step.

### What it deliberately does NOT do

- **No guessing.** It only fixes a link when the target can be recovered from an *explicit* rename (`R` in `git diff --find-renames`) or from the referencing file's own pre-move directory. It never infers "same basename elsewhere".
- **Only repairs currently-dangling links.** Links that already resolve are left untouched, so user-edited content is never overwritten.
- **Skips code.** Links inside fenced code blocks and inline code spans are ignored; labels containing backticks are handled correctly (they are links, not code).
- **Preserves fragments and forward slashes** — `../x.md#section-1` keeps its `#section-1`.
- **Excludes `docs/legacy/`** from automatic rewriting — historical links are handled separately.
- **Refuses unsafe writes** — targets outside the repo, or symlinks that escape it, are reported as unsupported and left alone.
- **Reports the rest, does not rewrite it** — broken links with no recoverable target (deleted files, uncommitted intermediate names, URL-encoded spaces) are listed as "unfixable" and left for `index.mjs` / manual review.

### Automatic path fix ≠ semantic review

`sync-renames` only repairs the *path* of a link. It cannot know whether the link's *text*, *line numbers*, *section headings*, or *meaning* are still correct after a move — those still need human review. A green run means "paths now resolve", not "prose is still accurate".

### Relationship to `index.mjs`

`index.mjs` is the **checker** (read-only, reports broken links, exit `0`/`1`). `sync-renames.mjs` is the **fixer** for the rename/move subset. They are complementary: run `sync-renames` after renames, then `index.mjs` to confirm everything resolves. The CI workflow runs the checker and the unit tests only — it never auto-writes or commits, and it is not a required branch check.

## When to update this file

Same as `naming-lint/README.md` — when a rule is added, removed, or changed; bump the version.