# 024 - NoteDetail 渲染性能与调度收敛

> 本规格定义 NoteDetail 渲染性能改造的证据口径、调度边界与真机验收标准。

> **Status**: proposed (2026-09-27; GitHub issue [#182](https://github.com/YunC-GCT/MindTrace/issues/182))
> **Related**: [ADR-0017](../adr/0017-renderer-scheduler-budget-baseline.md) · [spec 021](./021-chat-streaming-incremental-rendering.md) · [NoteDetailOverlay 调研](../research/note-detail-overlay-state-2026-09-23.md) · [ArkWeb 渲染稳定性调研](../research/arkweb-render-pipeline-stability-2026-09-11.md)

## Problem Statement

从用户视角，打开一篇笔记详情时，页面可能先出现空白或分段延迟，随后正文、公式和底部信息连续出现；公式较多或 AI 浮窗同时存在时，滚动和首屏布局会出现明显卡顿。用户需要等待多个内容区域完成渲染，无法判断页面是正在加载还是已经失去响应。

当前 NoteDetail 是全屏覆盖浮层，不是独立 Page。它共用六套类型 renderer，正文由 MarkdownRenderer 分块，公式由 MathTextRenderer 通过 ArkWeb 渲染。一个详情实例可能同时创建多个 Web 组件；缓存只复用结构化模型、KaTeX HTML 和估算高度，不能复用 Web 组件生命周期。

详情页还叠加了多套调度：DetailRenderQueue、各 renderer 的阶段性定时器、Markdown 解析延迟、公式错峰延迟，以及正文和步骤列表的“继续阅读”分页状态。每套机制都局部合理，但没有统一的首屏和每帧预算，导致工作批次、Web 创建和高度更新在同一时间窗口内相互叠加。

已有的 ArkWebWarmupService 已固定 SINGLE 渲染进程模式并执行引擎预热，但 WebKeepAlive 尚未挂载到根容器。所有业务 Web 被卸载后，渲染进程仍可能终止，下一次打开详情时再次承担进程启动成本。

本规格解决首屏卡顿、调度失控和 Web 生命周期抖动，不改变 KnowledgeUnit 数据契约、笔记编辑保存语义、删除语义或聊天流式 Document。

## Solution

建立以 NoteDetailOverlay 只读打开路径为最高测试接缝的性能闭环，并将详情渲染收敛到一个有明确预算的调度模型：

1. 使用固定的 A/B/C/C′ 详情 fixture，分别覆盖无公式、少量公式、多公式和连续公式，测量首屏、公式可见、稳定时间、Web 创建、Web 工作、高度更新和长帧。
2. 新增实例级 NoteDetail render session 作为详情页唯一的分块释放入口，逐个迁移 DetailRenderQueue 调用者并删除旧模块级全局队列；移除 renderer 内部重复的阶段性定时器，正文和步骤列表默认自动全量展开，不再显示“继续阅读”。
3. 将公式 Web 创建纳入统一的 NoteDetail 预算，初始沿用 ADR-0017 冻结的 `maxWebCreatesPerFrame = 1` 和 `maxWebWorkMsPerFrame = 16`，并保留估算高度与纯文本降级。
4. 对 WebKeepAlive 做目标设备开/关 A/B，比较冷开、重复打开、render-exit 与稳态内存；只有收益明确且内存成本可接受时，才在应用根部单实例挂载，否则保持关闭并记录否决证据。
5. 缩小详情状态变化的影响范围：渲染输入变化只重置对应详情实例的队列和子树；编辑状态、删除确认和草稿状态不得触发无关只读分块重新初始化。
6. 缓存 Markdown/公式规范化结果，避免 `build()` 重建时重复执行协议归一化和风险清洗；不把 chat 的 StreamingReplyDocument 或持久化模型引入 NoteDetail。

## User Stories

1. As a student, I want the note detail page to show useful content immediately, so that opening a note does not look frozen.
2. As a student, I want the header and first body section to appear before non-visible formula work, so that I can start reading without waiting for the entire note.
3. As a student, I want all note sections to become available automatically, so that I do not need to press “继续阅读” to reveal content.
4. As a student, I want the note detail page to remain responsive while formulas are being rendered, so that I can scroll or close it without waiting for every formula.
5. As a student, I want formulas to keep their current KaTeX visual quality and fallback behavior, so that performance work does not make mathematical content unreadable.
6. As a student, I want a short note to avoid unnecessary loading gaps, so that a small note does not feel slower than a long note.
7. As a student, I want a long note to be progressively prepared without hidden user controls, so that the page stays readable while the remaining content settles.
8. As a student, I want opening a note while the AI helper is visible to remain usable, so that the two surfaces do not compete for all Web resources.
9. As a student, I want closing a note and reopening it to reuse warm rendering conditions, so that repeated review is faster.
10. As a student, I want an unavailable formula renderer to degrade to readable text, so that one Web failure does not blank the entire note.
11. As a student, I want edit mode to remain independent from read-only rendering, so that typing does not restart already-rendered content.
12. As a student, I want the delete confirmation and close actions to remain unchanged, so that performance work does not alter destructive-action safety.
13. As a student, I want an AI-generated draft preview to keep its current review and confirmation flow, so that rendering improvements do not bypass confirmation.
14. As a maintainer, I want one NoteDetail rendering seam, so that performance regressions can be reproduced without manually navigating six parent pages.
15. As a maintainer, I want deterministic fixtures for no-formula and formula-heavy notes, so that changes can be compared across cold and warm runs.
16. As a maintainer, I want to know how many Web components are created per frame, so that a cache hit is not mistaken for a lifecycle optimization.
17. As a maintainer, I want to measure the time from open to first visible content, so that blank-screen regressions are detected directly.
18. As a maintainer, I want to measure the time from formula scheduling to applied height, so that ArkWeb and layout costs are distinguishable.
19. As a maintainer, I want to measure the time until the page is stable for 500ms, so that late height changes are not hidden by a fast first paint.
20. As a maintainer, I want long frames over 32ms to be counted during the first 500ms, so that frame-budget regressions are visible.
21. As a maintainer, I want consecutive long frames to be reported, so that a visually continuous stall is distinguished from one isolated slow frame.
22. As a maintainer, I want NoteDetail metrics to be scoped separately from chat metrics, so that the two rendering contracts remain independently evolvable.
23. As a maintainer, I want NoteDetail to reuse the frozen Web budget principles, so that a later optimization does not silently increase per-frame work.
24. As a maintainer, I want the scheduler to cancel stale work when a note changes or closes, so that old content cannot update a new detail instance.
25. As a maintainer, I want repeated input changes to reset only the affected detail queue, so that one overlay cannot discard another overlay's pending work.
26. As a maintainer, I want Markdown and formula normalization to be reused for the same render input, so that rebuilds do not repeat CPU-heavy preparation.
27. As a maintainer, I want an accepted WebKeepAlive experiment to mount the component once at the application root, so that it is not accidentally recreated with every note.
28. As a maintainer, I want WebKeepAlive recovery to be bounded, so that a killed renderer does not cause an infinite refresh loop.
29. As a maintainer, I want memory cost of WebKeepAlive to be measured on the target device, so that responsiveness improvements do not hide an unacceptable resident-memory increase.
30. As a maintainer, I want the page to preserve its current NoteType-specific sections, so that performance work does not flatten meaningful concept, theorem, formula, proof, or computation structure.
31. As a maintainer, I want the existing DetailRenderCache to remain valid, so that this work does not remove useful model-level caching.
32. As a maintainer, I want a cold-run and warm-run distinction, so that engine startup cost is not confused with steady-state formula cost.
33. As a maintainer, I want the benchmark to run without network access, so that local render behavior is deterministic.
34. As a reviewer, I want acceptance criteria tied to external behavior and measured budgets, so that “感觉不卡” is not used as the only release decision.
35. As a reviewer, I want the change split into reversible stages, so that WebKeepAlive, scheduler changes, and state-scope changes can be rolled back independently.
36. As a reviewer, I want chat streaming behavior to remain unchanged, so that a NoteDetail optimization cannot regress the already specified chat contract.

## Implementation Decisions

- The highest seam is the read-only `NoteDetailOverlay` open path. The fixture harness supplies a `NoteItem`, an optional `KnowledgeUnit`, and the complete `KnowledgeUnit[]` reference set, then observes the rendered surface rather than private renderer methods.
- The fixture matrix is A/B/C/C′: equal or controlled text size, 0/2/6/6 block-formula patterns, with C′ exercising consecutive closed formula pairs. Each fixture runs at least 20 times with cold/warm distinction when a device harness is available.
- NoteDetail metrics use a surface-specific adapter. It may share low-level counters with existing renderer instrumentation, but it must not depend on chat message models, `StreamingReplyDocument`, chat persistence, or chat list identity.
- The initial budgets are `maxWebCreatesPerFrame = 1`, `maxWebWorkMsPerFrame = 16`, long-frame threshold `>32ms`, and a 500ms quiet window for stability. These values are inherited from ADR-0017 as the starting contract; changing them requires new device evidence and an ADR update.
- A new instance-owned NoteDetail render session becomes the only section-release scheduler. Existing `DetailRenderQueue` callers migrate through an expand-migrate-contract sequence; the module-level queue, epoch, timer, enqueue/reset APIs, and renderer-specific staged timers are deleted after zero-call-site verification. Session state is invalidated when its key changes or the overlay disappears.
- Read-only content is automatically expanded. The user-facing “继续阅读” controls are removed from Markdown and step-list rendering. Automatic release may still be batched, but no content may depend on user interaction to become reachable.
- Formula rendering keeps the existing `MathTextRenderer` WebView/KaTeX route, `ContentProtocol` validation, estimated height, cache, bridge-size fallback, render-exit fallback, and plain-text fallback. This spec does not introduce a native LaTeX engine.
- The formula render decision is placed behind the NoteDetail scheduler so that one frame cannot create an unbounded number of Web components. A cached HTML hit still counts as a Web lifecycle operation for measurement and budgeting.
- `MathTextRenderer` preparation results are memoized by normalized input, profile, display mode, and render protocol version. `build()` must not repeatedly perform the complete normalization pipeline for an unchanged input.
- `WebKeepAlive` remains an experiment until target-device A/B evidence is collected. If accepted, it is mounted once below the application root stack, remains non-interactive and visually hidden, and has bounded render-exit recovery. If its resident-memory cost or cold/warm benefit is unacceptable, it remains disabled and the rejection evidence is retained.
- Existing `ArkWebWarmupService` remains the startup gate for SINGLE process mode and engine initialization. This spec does not move warmup to a background thread or add unsupported platform APIs.
- NoteDetail keeps its current six renderer families and `DetailRenderModel` contract. Model cache invalidation, KnowledgeUnit persistence, delete confirmation, draft confirmation, and status-bar safe-area behavior are unchanged.
- Chat remains on its existing rendering contract. The NoteDetail implementation may reuse generic budget vocabulary and low-level instrumentation, but it must not import or persist chat-specific Document state.
- Implementation is staged: performance observation and the formula correctness contract first; instance-scoped scheduling and state isolation second; automatic expansion and formula-budget integration third; WebKeepAlive A/B independently after the baseline; target-device acceptance and legacy contraction last. Any Web slot pooling or single-Web redesign is a separate follow-up only if measured targets remain unmet.

## Formula Rendering Contract

- `ContentProtocol` and `MarkdownParser` remain the only MM-MD-v1 Markdown/formula boundary. The performance work must not introduce a second formula splitter or parser.
- Block formulas use standalone `$$` boundaries and display mode. `\[` / `\]` are normalized compatibly; `$...$` and `\(...\)` retain inline semantics.
- Natural single-backslash LaTeX such as `\frac` is preserved. Fenced code and inline code protect literal `$` characters from formula recognition.
- Long-text chunking must not split a formula. Consecutive closed formulas must remain distinct and complete.
- Contract fixtures cover fractions, roots, sums, integrals, matrices, `cases`, `aligned`, multiline blocks, consecutive blocks, and inline text/formula mixtures.
- Unclosed delimiters, unbalanced brackets, unbalanced `\left` / `\right`, mismatched environments, KaTeX failures, bridge-size failures, render-exit, and height failures degrade to readable text. One failed formula must not blank or block the note, retry forever, or invalidate the entire render session.
- Existing `htmlAndMathml`, `trust: false`, expansion limits, raw-HTML protection, and dangerous-command protection remain in force.
- Block formulas must not be vertically clipped. Oversized formulas must remain inspectable rather than silently truncated.
- Cold rendering, cache hits, and cache retries must produce equivalent output. A cache retry uses normalized input rather than falling back to raw text; a cache hit still counts as Web lifecycle work.

## Legacy Migration Contract

The scheduling change follows expand-migrate-contract and does not leave a permanent dual path:

1. Add an instance-owned render session with a session key, priorities, budgets, cancellation, and surface-scoped metrics while the old path remains buildable.
2. Migrate `DetailSection`, `DetailStepsSection`, `DetailMetaFooter`, `NoteDetailBody`, and all six NoteType renderer families.
3. Remove NoteDetail's Markdown and step-list “继续阅读” controls. Content is semantically fully expanded; internal release may remain visible-first and batched.
4. Move formula admission to the instance scheduler and remove the NoteDetail-specific defer clock.
5. Verify zero call sites, then delete the module-level `DetailRenderQueue` state/APIs, renderer `visibleStage` state and staged timers, manual NoteDetail pagination, and `NOTE_MATH_RENDER_DEFER_*` logic.

Shared components are not deleted with the NoteDetail path. `MarkdownRenderer` keeps a separate chat profile, `MathTextRenderer` keeps its Web/KaTeX and fallback route, `ContentProtocol` / `MarkdownParser` remain the correctness boundary, `DetailRenderModel` / `DetailRenderCache` remain valid, and `ArkWebWarmupService` remains the shared L2 startup gate.

## Delivery Tickets

1. [#185 - NoteDetail render baseline and state-scope metrics](https://github.com/YunC-GCT/MindTrace/issues/185)
2. [#184 - NoteDetail MM-MD-v1 formula rendering contract](https://github.com/YunC-GCT/MindTrace/issues/184)
3. [#186 - Instance-scoped NoteDetail render session](https://github.com/YunC-GCT/MindTrace/issues/186), blocked by #185
4. [#183 - Automatic expansion with visible-first scheduling](https://github.com/YunC-GCT/MindTrace/issues/183), blocked by #184 and #186
5. [#187 - Formula Web budget and normalized cache](https://github.com/YunC-GCT/MindTrace/issues/187), blocked by #183
6. [#189 - WebKeepAlive target-device A/B](https://github.com/YunC-GCT/MindTrace/issues/189), blocked by #185
7. [#188 - Formula-heavy target-device acceptance](https://github.com/YunC-GCT/MindTrace/issues/188), blocked by #187 and #189

GitHub sub-issues and native blocked-by relationships are the authoritative live execution graph. The final device ticket remains human-gated until a target device is available; lack of device access does not invalidate static or pure-logic prerequisite work.

## Testing Decisions

- Tests assert external behavior and stable seams: content becomes available without a user “继续阅读” action, stale render work is cancelled, formula fallback remains readable, and measured budgets are respected. Tests do not assert private timer names, internal arrays, or exact component nesting.
- A Node-based contract test covers fixture definitions, metric names, frozen budget identifiers, NoteDetail/chat surface isolation, and automatic-expansion semantics. It follows the existing `scripts/arkts-lint/tests/` structural-test style.
- Pure logic tests cover fixture generation, render-session identity, queue cancellation, budget admission, metric aggregation, and cold/warm labeling.
- A Hypium/device harness covers the actual NoteDetail open path with A/B/C/C′ fixtures. It records p50/p95 for first-visible, formula-visible, open-to-stable, Web creates, height updates, and long frames; it also records render-exit reason and steady memory.
- Device acceptance defines `visible` as a rendered block in the viewport with its height applied. `stable` means the viewport and the previous-screen content have no height changes for 500ms after the last scheduled work.
- The first 500ms long-frame window uses `>32ms` as the long-frame threshold. Two consecutive long frames are a direct visual-continuity failure, even if the aggregate p95 is acceptable.
- The benchmark must run once with the AI helper closed and once with it visible, because the known risk is the combined Web component population.
- Existing renderer-scheduler and chat benchmark tests must continue to pass. NoteDetail tests must not weaken or rewrite chat acceptance criteria.
- Full validation includes ArkTS check, project lint, Node tests, naming lint, link check, `git diff --check`, and an entry HAP build. Device results must distinguish “evidence collected” from “target met”.
- If no device harness is available, static and pure-logic tests may land as the measurement prerequisite, but the implementation must not claim that the user-visible performance target has been met.

## Out of Scope

- Replacing KaTeX/WebView with a custom native mathematical layout engine.
- Introducing `StreamingReplyDocument`, chat-specific incremental block state, chat persistence changes, or chat list identity changes.
- Changing the KnowledgeUnit schema, RDB queries, save flow, delete semantics, draft confirmation, or review scheduling.
- Replacing the full NoteDetail overlay with a router page, a new navigation shell, or a multi-device presentation redesign covered by spec 022.
- Adding a global event bus or global mutable NoteDetail Document.
- Removing Markdown/KaTeX correctness validation or silently rendering invalid content as executable HTML.
- Enabling HTML-only KaTeX output without a separate accessibility and product decision.
- Implementing WebKeepAlive pooling, NodeContainer offline Web migration, or one-Web-per-note batch rendering in the first implementation slice.
- Treating the DevEco emulator as proof of target-device performance; emulator misses remain follow-up evidence.
- Adding animation polish, new visual tokens, or unrelated header/action changes.

## Further Notes

- The 2026-09-23 NoteDetail research identified the relevant risks as overlapping renderer timers and the 6.1 single-process WebView population risk. It also records several unrelated correctness and UX debts; they are not folded into this performance ticket.
- The research document predates the current `ArkWebWarmupService` implementation. The implementation spec treats warmup as already present and focuses on the still-unmounted WebKeepAlive seam.
- The existing `MATH_RENDER_CACHE` is a content cache, not a Web instance cache. Benchmark reports must keep these concepts separate.
- A later slot-pooling or single-Web design must be triggered by measured failure of the P1 targets, not by architectural completeness. It requires separate decisions for height synchronization, scroll behavior, render-exit recovery, and accessibility.
- The first implementation should preserve the current visual order of NoteType-specific sections. Performance work is successful only if users can still read the same structured content with the same edit/delete/draft semantics.
