# Doc templates

> Copy-paste starters for new docs. Each template is the canonical skeleton — when creating a new doc, start by copying the matching template, then fill in the placeholders.

## Templates

| Template | When to use | File naming after copy |
|---|---|---|
| [ADR template](./adr-template.md) | Recording a hard-to-reverse design decision | `docs/adr/NNNN-{slug}.md` |
| [Spec template](./spec-template.md) | Implementing a ticket from an ADR (TDD plan) | `docs/specs/NNN-{slug}.md` |
| [Research template](./research-template.md) | Investigating a question against primary sources | `docs/research/{slug}-{YYYY-MM-DD}.md` |
| [Agent workflow template](./agent-workflow-template.md) | Writing a workflow / pointer doc under `docs/agents/` | `docs/agents/{topic-slug}.md` |

## Conventions

- **Naming**: see [`../style/naming-conventions.md`](../style/naming-conventions.md)
- **Validation**: `node scripts/naming-lint/index.mjs` — run after creating
- **Index files**: every doc dir has an `index.md` (renamed from `README.md` per convention)
- **Dates**: `YYYY-MM-DD` format only, no separators

## How to add a new template

1. Identify a doc type that's needed (e.g., RFC, runbook, release notes)
2. Write the template following the conventions in this repo
3. Add it to the table above
4. Cite which docs/style rule (in `naming-conventions.md`) it implements