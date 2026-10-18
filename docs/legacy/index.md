# Legacy

> **Frozen content from previous iterations of this repo.** Read-only.

## Layout

| Path | Project | Last updated |
|---|---|---|
| [`mindtrace/`](./mindtrace/) | MindTrace (HarmonyOS ArkTS) — audit evidence + frozen handoffs; pre-D2 plans/research purged 2026-10-18 | 2026-10-18 |

## When to add a new entry

Only when **archiving an entire project's docs** as a single unit. If you have just a few stale docs, use the git history or a one-line reference in the current docs — don't create a new project subdirectory.

## When to update existing entries

**Never.** Existing entries are frozen. If something in `mindtrace/` is wrong or outdated, the project is no longer active — fix by deleting, not by editing.

If a file here is needed in the current project, **copy** it to the current docs location rather than editing in place. The legacy copy is a historical record.

## Naming convention for new legacy entries

```
docs/legacy/{project-name}/
```

- `{project-name}` is the original project's name (e.g., `mindtrace`)
- kebab-case
- Single subdirectory per archived project
- No deeper nesting (preserve original layout within)

See [`../style/naming-conventions.md`](../style/naming-conventions.md) §3.8 for the formal spec.