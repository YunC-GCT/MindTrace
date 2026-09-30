# Naming Conventions

This repository keeps the competition submission branch compact. Use these rules for new files that remain in the public submission package.

## Repository Files

| File type | Rule | Example |
|---|---|---|
| Root documents | Uppercase words | `README.md`, `CONTEXT.md`, `AGENTS.md` |
| Markdown under `docs/` | `kebab-case.md` | `readme-en.md` |
| Directories | `kebab-case` | `ocr-service`, `link-check` |
| Tests | `*.test.mjs` or local project convention | `sync-renames.test.mjs` |
| ArkTS source | Existing HarmonyOS module convention | `AgentChatService.ets` |

Avoid spaces, ad-hoc abbreviations, date-only filenames, duplicate index files, and generated HTML documents in `docs/`.

## Branches and Commits

- Branches: `feature/<short-topic>` or `bugfix/<short-topic>`.
- Commits: conventional commits, for example `docs: slim submission docs` or `fix(entry): isolate note context`.
- Renames: use `git mv` so history is retained.

## Checks

```bash
node scripts/naming-lint/index.mjs
node scripts/link-check/index.mjs
git diff --check
```
