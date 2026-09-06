# 0009 — Kit adoption boundary: HSPs declare facade contracts, entry injects implementations

D4 adopts HarmonyOS Kits (reminders, background tasks, form cards — [kits survey](../research/harmonyos-kits-survey-2026-09-05.md)). Business HSPs (`common` / `agents` / `skill` / `cardservice`) must not import `@kit.*`. Capability contracts live in `common/src/main/ets/kit/` (`ReminderFacade`, `BackgroundTaskFacade`, `FormCardFacade` — interfaces only); `entry` is the only module that imports kit APIs, implements the facades, and injects them.

## Status

`accepted` (2026-09-06, D4 P0)

## Considered Options

1. **Contract + injection** *(chosen)* — HSPs stay free of system-API coupling: lintable, AST-testable, swappable. Mirrors the existing `NoteDaoInterface` → `NoteDaoAdapter` seam.
2. **Import `@kit.*` directly from HSPs** — least code today, but welds business modules to the system API surface and breaks the "agents/ does not depend on entry" topology rule (ADR-0001).
3. **Dedicated kit-wrapper HSP** — one more module in the topology for what is already an interface seam; over-engineering at 3 capabilities.

## Consequences

- **Chosen (1)**: every kit capability costs a contract + an entry-side implementation + injection wiring. The 3 P0 contracts currently have no entry implementations — compile-clean but inert until wired (D4 pending work).
- P1 candidates (AIEngine capability probe) follow the same pattern if adopted.

## Reversibility

**Low**. Interfaces without implementations can be moved or deleted freely; the only cost is the injection wiring, which is additive.

## Related

- [0001 — layer boundaries](./0001-layer-boundaries-in-5-module-arkts-app.md) — the topology rule this preserves
- [spec 013 — Kit adoption boundary](../specs/013-kit-adoption-boundary.md)
