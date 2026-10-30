# Legacy

> **Frozen content from previous iterations of this repo.** Read-only.

## Layout

| Path | Project | Last updated |
|---|---|---|
| [`mindtrace/`](./mindtrace/) | MindTrace (HarmonyOS ArkTS) — audit evidence + frozen handoffs. Purged 2026-10-18; flattened 2026-10-30 to a single directory (10 files, no subdirs) | 2026-10-30 |

## Known stale facts in the frozen files

Frozen text is not corrected in place — these notes exist so nobody copies the old wording into current docs:

- `mindtrace/audit-full-2026-09-01.md` (§header, §2 注) 把模块拓扑写成「1 HAP + 4 HSP」。as-built 是 **3 HAP**（`entry` / `skill` / `cardservice`）+ **2 HSP**（`common` / `agents`），见 `AGENTS.md`。
- 同一篇里的 `D:\HMgent\MathMind` 是当时的本地目录名；仓库现名 **MindTrace**。

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
- Keep the original layout inside it **only when the archive is big enough to need it**; a handful of files stays flat (`docs/legacy/mindtrace/*.md`) — subdirectories holding 1–2 files plus their own `index.md` are noise, not structure

See [`../style/naming-conventions.md`](../style/naming-conventions.md) §3.8 for the formal spec.