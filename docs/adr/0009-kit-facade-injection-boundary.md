# 0009 — Kit capability seam: pipeline consumes kits via facade contracts

D4 adopts HarmonyOS Kits for reminders, background tasks, and form cards ([kits survey](../research/harmonyos-kits-survey-2026-09-05.md)). The **business pipeline** (CaptureGraph nodes, agents/common services) consumes kit capabilities only through the facade contracts in `common/src/main/ets/kit/` (`ReminderFacade`, `BackgroundTaskFacade`, `FormCardFacade` — interfaces only); implementations are provided at the composition root and injected. This is a **seam for testability and replaceability, not an import ban**: modules shaped by the DevEco template (entry's UIAbility, cardservice's `FormExtensionAbility`/UIAbility) import kit APIs directly — that is their template role, not business coupling. Actual kit resource integration (real `@kit.*` calls behind the facades) is deliberately deferred to a later window (2026-09-06 decision).

## Status

`accepted` (2026-09-06, D4 P0; implementations deferred)

## Considered Options

1. **Contract + injection at the pipeline boundary** *(chosen)* — pipeline classes stay decoupled from system APIs: lintable, AST-testable, swappable. Mirrors the existing `NoteDaoInterface` → `NoteDaoAdapter` seam.
2. **Kit calls inline in pipeline classes** — least code today, but welds AI business logic to the system API surface and makes graph nodes untestable without a device.
3. **Dedicated kit-wrapper HSP** — one more module in the topology for what is already an interface seam; over-engineering at 3 capabilities.

## Consequences

- **Chosen (1)**: every kit capability consumed *by the pipeline* costs a contract + an injection point. The 3 P0 contracts compile clean and are inert until implementations land — intentional, per the deferral above.
- Template modules keep importing kits directly; no lint ban is imposed on `@kit.*` imports anywhere in the repo.
- When integration starts, implementations land at the composition root (entry) and get injected — no contract changes expected.

## Reversibility

**Low**. Interfaces without implementations can be moved or deleted freely; the only cost is the injection wiring, which is additive.

## Related

- [0001 — layer boundaries](./0001-layer-boundaries-in-5-module-arkts-app.md) — the topology rule this preserves
- [spec 013 — Kit adoption boundary](../specs/013-kit-adoption-boundary.md)
