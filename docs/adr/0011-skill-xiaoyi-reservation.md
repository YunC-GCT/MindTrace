# 0011 — `skill/` is retained as the Xiaoyi (小艺) skill development reservation

The 2026-09-06 agent-tools audit ([F4](../architecture/agent-tools-inventory-2026-09-06.md)) flagged the `skill/` HSP as a candidate for freezing or removal: the whole module is one `SKILL_VERSION` constant plus a placeholder `SkillAbility`. The team ruled that `skill/` is the **reserved slot for Xiaoyi (小艺) skill development** — development has not started yet, but the module must be kept. This ADR records that ruling so future audits do not re-suggest deletion. The freeze/removal suggestion (audit finding F4) is withdrawn.

## Status

`accepted` (2026-09-06, team ruling recorded during the agent-tools audit grilling loop)

## Considered Options

1. **Retain as a reservation** *(chosen)* — `skill/oh-package.json5` self-describes as "MindTrace xiaoyi skill" and already declares dependencies on `common` + `agents`; `skill/src/main/module.json5` declares 7 intent actions (`CaptureNote` / `VoiceReview` / `SearchNote` / `RecommendReview` / `KGRelated` / `KGCrossTime` / `SetPreferences`) plus the `entity.system.intent` entity. Deleting the module would discard this declared intent surface.
2. **Freeze** (the audit's original F4 suggestion) — mark the module as non-shipping until W1 block 3. Rejected by the team: keeping the full 5-module topology is part of the competition-stage narrative.
3. **Remove from the build topology** — git history makes this cheap to undo, but it erases the explicit reservation signal the module provides.

## Consequences

- **Chosen (1)**: the stub state of `skill/` is *deliberate*. Future audits and agents must not treat it as dead code or propose its removal.
- Implementation path when work starts: register the intents with Intents Kit (`@InsightIntent{Link,Page,Function,Form,Entry}` decorators, API 11+; the target SDK 6.1.1 = API 24 supports it), route `want.action` in `SkillAbility` through an IntentRouter onto the shared tool surface ([spec 014](../specs/014-tool-calling-protocol.md) ToolRegistry). A2A Server capabilities are API 26 — roadmap only. Survey: [agent-toolkit-and-skill-dispatch-2026-09-06](../research/agent-toolkit-and-skill-dispatch-2026-09-06.md) §4-5.
- Topology constraint to design around: `skill/` (HSP) can only see `common` + `agents`; all DAOs and chat orchestration live in `entry` (HAP) and are unreachable — read-only intents first.
- Open item before any implementation spec: the 7 intent actions' semantics are inferred from their names only; a teammate must confirm them.

## Reversibility

**Low** — keeping an empty module costs nothing; what would be hard to reverse is deleting it and losing the declared intent actions and the team's recorded intent.

## Related

- [agent-tools inventory 2026-09-06](../architecture/agent-tools-inventory-2026-09-06.md) — finding F4 (withdrawn by this ADR)
- [ADR-0009](./0009-kit-facade-injection-boundary.md) — the same contract-first / inject-later philosophy
- [ADR-0010](./0010-mcp-tools-semantics.md) — the `tools/` taxonomy this module will eventually consume
- `CONTEXT.md` — 「小艺 skill 预留位 (skill/)」 term
