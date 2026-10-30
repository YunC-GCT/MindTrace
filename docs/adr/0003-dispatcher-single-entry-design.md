# 0003 — Dispatcher single-entry design

`agents/core/Dispatcher.ets` has three public methods: `analyze`, `dispatch`, `routeDispatch`. `routeDispatch` is dead code (zero non-test callers per audit). `analyze` leaks a pipeline step as a public API. We collapse to one public method.

## Considered Options

1. **Single `dispatch(req, opts?)` public method, internal `analyze` step** *(chosen)*. `opts` is `{ persist?: boolean, includeRawText?: boolean }`. `routeDispatch` deleted.
2. **Keep all three methods**. `routeDispatch` stays for "compatibility" (no callers), `analyze` stays because two `entry/` services call it (per audit).
3. **Split into two public APIs**: `analyze(req)` for read-only classification, `dispatch(req)` for full pipeline. Two semantic intents, two methods.

## Consequences

- **Chosen (1)**: cleanest surface. `Dispatcher` exposes one verb. The `analyze` step is reachable via `dispatch(req, { persist: false })` for the two callers that need it. `routeDispatch` deletion is uncontroversial (zero callers).
- Reject (2): `routeDispatch` is dead code; keeping it as "API surface" is misleading. `analyze` as public method encourages callers to skip persistence, which is a leaky abstraction.
- Reject (3): the `persist: false` option is a 1-line difference. Two methods for a 1-line difference is API bloat.

## 现状（2026-10-30 回填）

公开入口现在是**两个**，不是三个：

- `dispatch(req, options)` — `agents/src/main/ets/core/Dispatcher.ets:145`
- `dispatchSet(req, options)` — 同文件 `:153`，批量 capture set 的循环入口，逐条转调 `dispatch`

本 ADR 的核心结论仍然成立：`analyze` 已降为私有步骤，`routeDispatch` 已删，持久化语义只有 `dispatch` 一处定义。`dispatchSet` 是 2026-10 为「一次多图」加的第二入口，它不暴露分析能力、也不绕过 `dispatch` 的写路径，因此不构成对本 ADR 的回退；但「Dispatcher 只暴露一个动词」这句话已经不再字面为真，引用时按「一个语义入口 + 一个批量包装」理解。

## Reversibility

Low. `dispatch` signature is the natural API; restoring two methods is additive. The only risk is that two existing callers (`AiService.analyzeImage`, `services/AgentChatService.captureReply`) currently call `analyze` and `dispatch` separately and need to migrate to `dispatch(req, { persist: false | true })`. ~4 line change per caller.

## Migration plan

Phase 4 ticket #4 (already in audit): collapse methods. The two callers change to:
- `dispatcher.analyzeImage(imageUri, userText)` → `dispatcher.dispatch({ kind: 'image', imageUri, userText, persist: false })`
- `dispatcher.dispatch(req)` unchanged

Tests: `agents/src/test/KnowledgeModel.test.ets` already covers the analyze path; no new tests needed if behavior is preserved.

## Related

- Audit §4.5 — original finding
- Phase 4 ticket #4 — implementation ticket
