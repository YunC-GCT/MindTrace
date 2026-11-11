# 0009 — Kit capability seam: pipeline consumes kits via facade contracts

D4 adopts HarmonyOS Kits for reminders, background tasks, and form cards ([kits survey](../research/harmonyos-kits-survey-2026-09-05.md)). The **business pipeline** (CaptureGraph nodes, agents/common services) consumes kit capabilities only through the facade contracts in `common/src/main/ets/kit/` (`ReminderFacade`, `BackgroundTaskFacade`, `FormCardFacade` — interfaces only); implementations are provided at the composition root and injected. This is a **seam for testability and replaceability, not an import ban**: modules shaped by the DevEco template (entry's UIAbility, cardservice's `FormExtensionAbility`/UIAbility) import kit APIs directly — that is their template role, not business coupling. Actual kit resource integration (real `@kit.*` calls behind the facades) is deliberately deferred to a later window (2026-09-06 decision).

## Status

`accepted` (2026-09-06, D4 P0; implementations completed 2026-09-10)

## Considered Options

1. **Contract + injection at the pipeline boundary** *(chosen)* — pipeline classes stay decoupled from system APIs: lintable, AST-testable, swappable. Mirrors the existing `NoteDaoInterface` → `NoteDaoAdapter` seam.
2. **Kit calls inline in pipeline classes** — least code today, but welds AI business logic to the system API surface and makes graph nodes untestable without a device.
3. **Dedicated kit-wrapper HSP** — one more module in the topology for what is already an interface seam; over-engineering at 3 capabilities.

## Consequences

- **Chosen (1)**: every kit capability consumed *by the pipeline* costs a contract + an injection point. The 3 P0 contracts compile clean and are inert until implementations land — intentional, per the deferral above.
- Template modules keep importing kits directly; no lint ban is imposed on `@kit.*` imports anywhere in the repo.
- When integration starts, implementations land at the composition root (entry) and get injected — no contract changes expected.
- Follow-up (2026-09-10): Reminder, transient background task and Form card adapters are implemented and injected. Card data uses one GSKV snapshot store across app/card processes; the fixed Form mock was removed.

## 2026-10 补充：Kit 归属三档与受限 Kit 红线

本 ADR 只回答了「pipeline 怎么拿到 Kit」，没回答「**哪个 Kit 可以出现在哪个模块里**」。后续踩过两次坑，补两条规则（细节见 [spec 033](../specs/033-process-boundaries.md) 的 R5 与 `AGENTS.md` 红线 11）：

| 档 | 判据 | 例子 |
|---|---|---|
| 只进主进程 | 依赖 UI / 主线程渲染 | 3D 星系渲染相关 Kit |
| 可进共享模块（`common`） | 多进程都要 eval，且 eval 本身无网络栈副作用 | `@kit.CoreVisionKit`（端侧 OCR，扩展进程里已实测 `PROBE available=true init=true`） |
| 受限 | 在扩展进程 eval 会破坏网络栈 | `@kit.DataAugmentationKit`（`localChatModel`），**只允许在 `entry` 的 UI 进程加载** |

**红线：受限 Kit 不得经 `common` 的 barrel 导出。** 只要 barrel 里有它，`AgentExtAbility` 哪怕只 import 一个 `LlmConfig`，也会把整个 Kit 带进扩展进程，表现为 `proxy SendRequest failed 201`、A2A 的 LLM 调用永不返回。判据不是「这个 Kit 归谁」，而是「**它会被哪些进程 eval**」。

这条补充没有推翻本 ADR 的「seam 不是 import 禁令」，但把「直接 import 合法」收窄成「模板模块与主进程可以，共享模块要按上表分级」。

## Reversibility

**Low**. Interfaces without implementations can be moved or deleted freely; the only cost is the injection wiring, which is additive.

## Related

- [0001 — layer boundaries](./0001-layer-boundaries-in-5-module-arkts-app.md) — the topology rule this preserves
- [spec 013 — Kit adoption boundary](../specs/013-kit-adoption-boundary.md)
