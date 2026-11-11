# HTML Files in `docs/` — Convention

> **TL;DR**: `docs/` is for hand-written **source** content (`.md`). HTML files are **renders**, not source. Don't commit generated HTML. The few exceptions are documented below.

---

## Why no HTML in `docs/`

`docs/style/naming-conventions.md` §8 + §12 enforces this. The reason is operational:

- **Markdown is the source of truth** — `.md` files are what humans edit, review in PRs, and reference in commit messages. HTML is a *rendering* of markdown (via tools like pandoc, vscode preview, mermaid, etc.).
- **HTML drifts** — if you commit both `.md` and `.html` of the same content, they go out of sync the moment anyone edits one and forgets to regenerate the other. Reviewers see the `.md` change but not the stale `.html`.
- **Diff noise** — HTML files have hundreds of lines of generated markup that pollutes `git diff` and obscures real content changes.
- **Repo bloat** — HTML files are typically 5-10× larger than their `.md` source. Committing both doubles the cost of every clone, fetch, and search.

---

## Decision tree

Use this when you're tempted to commit an HTML file in `docs/`:

```
Is the HTML...
│
├─ Generated from a .md source (pandoc, vitepress, mermaid, etc.)?
│   └─ YES → DON'T commit. Add to .gitignore. Keep local copy for personal use.
│
├─ A hand-crafted visual aid PAIRED with a .md source?
│   │         (e.g. design mockup saved as HTML alongside the spec .md)
│   └─ YES → OK in docs/research/ (or wherever the .md lives).
│           Add the specific filename to .naminglintrc.json skip.files.
│           The .md is the source of truth — HTML is auxiliary.
│
├─ A historical artifact from a previous project iteration?
│   └─ YES → OK in docs/legacy/{project}/. Frozen per docs/legacy/index.md.
│           The whole `legacy` dir is in .naminglintrc.json skip.dirs.
│           Don't edit; treat as immutable historical record.
│
└─ True source HTML (rare — e.g. an interactive demo)?
    └─ ASK in your PR description. Default answer: no.
       Convert to .md + JS or move to a non-docs location.
```

---

## Concrete recipes

### Case 1: You generated HTML from a `.md` (most common)

**Bad** (do not commit):
```bash
pandoc -s research/langgraph-migration.md -o research/langgraph-migration.html
git add research/langgraph-migration.html
git commit -m "Add langgraph migration research"
```

**Good** (generate locally, never commit):
```bash
# 1. Generate HTML to a temp dir (not in repo)
pandoc -s research/langgraph-migration.md -o /tmp/render.html

# 2. If you do this often in one project, add to .gitignore:
echo "/research/*.html" >> .gitignore
git add .gitignore
git commit -m "chore: gitignore generated HTML renders"
```

### Case 2: Hand-crafted visual aid (e.g., mockup)

```bash
# Save the HTML next to its .md source (allowed in docs/research/)
ls docs/research/
# agent-framework-comparison-2026-09-02.md   ← source
# agent-framework-comparison-2026-09-02.html ← paired visual

# Add the specific filename to naming-lint config so it doesn't fail CI:
# .naminglintrc.json
"files": [
  ...,
  "agent-framework-comparison-2026-09-02.html",
  "langgraph-migration-2026-09-02.html"
]
```

Then commit the `.md` change + the `.naminglintrc.json` update together.

### Case 3: Historical HTML in `docs/legacy/`

`docs/legacy/mindtrace/` contains ~14 HTML files from the previous project
iteration. They're frozen per `docs/legacy/index.md` and excluded from lint
via:

```json
// .naminglintrc.json
"skip": {
  "dirs": [..., "legacy"]
}
```

**Don't** add individual HTML filenames for legacy content. Don't edit or
delete these files. They're a historical record.

### Case 4: True source HTML (rare)

If you genuinely have HTML that must be committed (e.g., an interactive
demo using `<script>` tags that markdown can't can't express), discuss in
the PR description before adding. The default is to convert to `.md`
with code fences or move out of `docs/`.

---

## What goes where

| Content | Location | Gitignored? |
|---------|----------|-------------|
| Hand-written `.md` doc | `docs/<type>/<name>.md` | No |
| Generated HTML from `.md` | **Local only** (e.g. `/tmp/`, `~/Downloads/`) | Yes |
| Hand-crafted HTML visual aid | `docs/research/<name>-YYYY-MM-DD.html` paired with `.md` | No (whitelist in lint) |
| Historical HTML | `docs/legacy/<project>/...` | No (frozen) |
| Raw research material (downloads, fetched pages) | `docs/research/_fetched/` | **Yes** (already gitignored) |

---

## If you accidentally committed HTML

```bash
# Remove from index but keep local copy
git rm --cached docs/path/to/file.html

# Or remove entirely
git rm docs/path/to/file.html

# Then add to .gitignore so it doesn't come back
echo "docs/path/to/*.html" >> .gitignore
git add .gitignore
git commit -m "chore: remove accidentally-committed generated HTML"
```

If the HTML is already in `git log` (committed in earlier PRs), don't try
to rewrite history — just `git rm --cached` going forward and add to
`.gitignore`. Old copies stay in history.

---

## How naming-lint enforces this

`scripts/naming-lint/index.mjs` has a `no-html-in-docs` rule:

```js
// Normalize to forward slashes — path.relative() returns OS-native separators
if (ext === '.html' && relPath.replace(/\\/g, '/').startsWith('docs/')) {
  violations.push({ relPath, name, rule: 'no-html-in-docs', msg: '...' });
}
```

The rule is enforced in CI (`.github/workflows/naming-lint.yml`). Allowed
exceptions live in `.naminglintrc.json`:

```json
{
  "skip": {
    "dirs": ["legacy"],                                 // frozen legacy
    "files": ["specific-name.html", "..."]              // paired .md+.html
  }
}
```

When you add a new paired HTML render, append the filename to `skip.files`.
When you archive a new project to `docs/legacy/`, no config change needed
(`legacy` is already in `skip.dirs`).

---

## Related

- `docs/style/naming-conventions.md` §8 (file headers — explains the role of `.md` vs `.html`)
- `docs/style/naming-conventions.md` §9 (Generated and Vendored Files)
- `docs/style/naming-conventions.md` §12 (Forbidden Patterns — lists `.html` in docs/)
- `docs/legacy/index.md` — frozen-content policy
- `.gitignore` — has `docs/research/_fetched/` for raw fetched material