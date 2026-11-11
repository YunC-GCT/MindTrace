# scripts/doc-trace/

Structural traceability check for `docs/`.

## What it checks

1. **Reachability** — every `docs/**/*.md` is reachable from `docs/index.md` through relative links. A directory link counts as a link to that directory's `index.md`.
2. **Index coverage** — every directory `index.md` links every non-index Markdown file sitting directly in that directory.
3. **Numbering** — `docs/specs/NNN-*.md` and `docs/adr/NNNN-*.md` prefixes are unique.

It does **not** judge technical content or status wording. The status vocabulary and document-control block are defined in `docs/agents/document-control.md`.

## Usage

```bash
node scripts/doc-trace/index.mjs
node scripts/doc-trace/index.mjs --json
node scripts/doc-trace/index.mjs docs      # custom root
```

Exit codes: `0` clean, `1` violations, `2` entry missing.

## Tests

```bash
node --test scripts/doc-trace/tests/*.test.mjs
```

## CI

Wired into `.github/workflows/document-links.yml`; both the unit tests and the checker must pass.
