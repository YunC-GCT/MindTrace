# Spec 022 — HarmonyOS 多端 UI 适配

> **Status**: ready；implementation deferred（2026-09-08）
> **Priority**: P2
> **Tracking issue**: [#93](https://github.com/YunC-GCT/MindTrace/issues/93)
> **Source research**: [`../research/harmonyos-multi-device-ui-adaptation-2026-09-08.md`](../research/harmonyos-multi-device-ui-adaptation-2026-09-08.md)
> **Architecture input**: [`../architecture/window-layout-strategy-2026-09-08.md`](../architecture/window-layout-strategy-2026-09-08.md)
> **Prototype**: API 24 独立应用壳原型，已在 MatePad Pro 13 模拟器验证
> **Scope**: `entry` 窗口布局、应用壳、页面排列、浮层表现、输入与回归验证；不改业务流程

## Problem Statement

MindTrace 的安装声明已经覆盖手机、平板和 2-in-1，但当前 UI 仍按照固定手机窗口设计：所有窗口均使用 74vp 底部导航，页面缺少统一窗口断点状态，Notes 没有宽屏主从布局，AI 与笔记详情浮层依赖手机尺寸假设，知识星系以 360×520 为固定基准。

因此用户即使能在平板或 2-in-1 安装应用，也会遇到宽屏留白、内容过度拉伸、导航形态不合适、浮层遮挡、窗口缩放后安全区失效及状态丢失等问题。每个页面若自行读取窗口宽度或判断设备类型，将进一步形成多套断点、重复监听和四套 UI。

原型还验证了三个实施风险：测试应用若只声明 phone，会在平板进入手机兼容窗口；内容区使用 `height('100%')` 会把底部导航挤出可视区；XL 学科卡片自动增加至四列会产生过密视觉。

## Solution

MindTrace 将建立唯一的窗口布局状态 module，把 HarmonyOS 窗口、UIObserver 和避让区事实转换为一个只读布局快照，并通过当前跨 `@Entry` 页面可用的状态通道发布。页面只消费底栏/轨道/侧栏、Stack/Split、bottom sheet/side panel、内容约束和 viewport 等语义，不接触平台监听或设备类型。

应用在 XS/SM 使用底部导航，在 MD 使用左侧窄轨道，在 LG/XL 使用固定侧栏；Notes 在 LG/XL 切换为列表—详情双栏；AI 在 XS/SM 使用 bottom sheet，在 MD 及以上使用右侧 panel。主从结构只由窗口宽度档位决定，高度档位仅处理可用高度、滚动和键盘避让。

现有页面内容、视觉令牌、业务状态、ViewModel 和 Service 将继续复用。不会复制手机、平板、折叠屏和 2-in-1 四套页面，也不会把原型代码直接迁入生产。

## User Stories

1. As a 手机用户, I want MindTrace 保留熟悉的底部导航, so that 多端改造不会降低现有手机体验。
2. As a 极窄窗口用户, I want 所有主入口仍可触达, so that 小于 320vp 时导航不会溢出或被裁切。
3. As a 平板用户, I want 主导航位于左侧, so that 横向空间得到有效利用且内容底部不被占用。
4. As a 2-in-1 用户, I want 窗口从窄到宽时导航自动从底栏切为轨道和侧栏, so that 我不需要重启应用。
5. As a 用户, I want 窗口变化时当前页面保持不变, so that 调整窗口不会打断学习。
6. As a 用户, I want 窗口变化时当前 Subject 和 KnowledgeUnit 保持不变, so that 我不会丢失阅读位置。
7. As a 用户, I want 窗口变化时滚动位置保持不变, so that 我可以继续浏览原来的内容。
8. As a 用户, I want 窗口变化时 AI 会话和草稿保持不变, so that 调整窗口不会清空对话。
9. As a Notes 用户, I want SM/MD 保持单栏浏览, so that 窄窗口中的列表和详情具有足够宽度。
10. As a Notes 用户, I want LG/XL 同时查看列表和详情, so that 宽屏减少无意义的往返跳转。
11. As a Notes 用户, I want 主从切换以 840vp 为明确分界, so that 839/840vp 两侧行为可预测。
12. As a Notes 用户, I want 学科卡片继续支持一列列表或两列卡片偏好, so that XL 不会强制变成过密的四列布局。
13. As a Notes 用户, I want 宽屏详情复用现有详情内容, so that 单栏页和双栏页不会出现两套行为。
14. As a Notes 用户, I want 详情编辑、保存和删除在两种布局下结果一致, so that 多端只改变呈现而不改变业务。
15. As a 长笔记列表用户, I want 列表按需创建项目, so that 数据增长后滚动仍然顺畅。
16. As a 手机 AI 用户, I want AI 继续以 bottom sheet 出现, so that 输入和返回手势符合手机习惯。
17. As a MD 窗口用户, I want AI 以可收起右侧 panel 出现, so that 对话不会永久挤压主内容。
18. As a LG/XL 用户, I want AI 使用右侧 panel, so that 主内容与学习助手可以协同查看。
19. As a 用户, I want AI 入口是动作而不是伪 Tab, so that 导航选中状态不会发生跳回或空页闪烁。
20. As a 用户, I want AI 面板打开时输入区始终可见, so that 软键盘和窗口缩放不会遮挡发送操作。
21. As a 用户, I want 笔记详情在手机全屏、宽屏侧面板显示, so that 文本行宽和操作区适合当前窗口。
22. As a Home 用户, I want 首页在宽屏限制正文宽度并合理分区, so that 信息不会无限拉伸或过度留白。
23. As a Profile 用户, I want 设置和资料表单限制最大宽度, so that 输入控件在平板上仍然易读。
24. As an AiSettings 用户, I want 独立路由页获得与主页相同的窗口布局状态, so that 页面之间不会出现断点不一致。
25. As a Review 用户, I want 知识星系根据可绘制 viewport 排列, so that 360×520 固定基准不会在宽屏失真。
26. As a 2-in-1 用户, I want 使用鼠标和键盘操作主导航、详情和 AI 输入, so that 应用不依赖触摸。
27. As a 字体放大用户, I want 1.5x 字体下标题、按钮和卡片不裁切, so that 多端布局仍然可读。
28. As a 用户, I want 系统栏和安全区在窗口变化后重新计算, so that 内容不会与状态栏或导航区域重叠。
29. As a 用户, I want 真实窗口大小而不是设备名称决定布局, so that 分屏和自由窗口行为正确。
30. As a 开发者, I want 全项目只有一个窗口监听 owner, so that 页面进入退出不会叠加监听或泄漏。
31. As a 开发者, I want 页面只消费一个完整布局快照, so that 宽高断点、viewport 和避让区不会成为多个真相源。
32. As a 开发者, I want 布局策略不引用 ViewModel、Service 或 DAO, so that UI 尺寸变化不会触发业务流程。
33. As a 开发者, I want 布局映射可以脱离设备运行进行测试, so that 断点行为能快速回归。
34. As a 维护者, I want 独立路由页和应用壳共享同一布局事实, so that 当前多 `@Entry` 结构在迁移期仍然可靠。
35. As a 维护者, I want 测试 harness 同样声明 phone/tablet/2in1, so that 平板测试不会误入手机兼容窗口。
36. As a reviewer, I want 每个关键断点有截图证据, so that 我能发现重叠、裁切、异常留白和导航错误。
37. As a reviewer, I want 断点变化不会重复加载 Notes 或触发网络请求, so that 响应式刷新不污染业务行为。
38. As a release owner, I want 手机拍照—AI—入库主链在多端改造后保持可用, so that UI 迁移不会破坏比赛演示。

## Implementation Decisions

### Window layout module and seam

- The entry module gains one window layout module with one external seam: an immutable `WindowLayoutSnapshot` consumed by pages and tests.
- The snapshot contains width/height breakpoints, navigation presentation, Notes detail presentation, assistant presentation, note detail presentation, page padding, content maximum width, drawable viewport, and top/bottom insets.
- The snapshot never contains current Tab, Subject, KnowledgeUnit, scroll position, chat session, draft, ViewModel, Service, DAO, device type, model name, orientation string, or fold state.
- The snapshot does not expose Subject column count. Subject list/card density remains the Notes page's existing user preference; XL remains one-column list or two-column cards.
- Snapshot updates replace the complete object reference. Callers do not mutate individual fields.

### Internal module design

- A pure layout policy maps one complete set of window facts to one layout snapshot. It has no ArkUI, storage, ViewModel, Service, or DAO dependency.
- A platform source adapter owns the Window, UIContext, UIObserver, exact callback references, viewport reads, and avoid-area reads.
- A store coordinates source, policy, and publisher. It publishes an initial snapshot before waiting for events, suppresses equivalent updates, and makes start/stop idempotent.
- An AppStorage publisher is the first publication adapter because the current app has multiple independent `@Entry` roots. Pages consume the snapshot read-only.
- A future migration may replace the AppStorage publisher with a component-tree provider after routing is unified. The policy and snapshot interface must not change for that migration.
- The store belongs to one WindowStage and is constructed by the application composition root. It is not a process-wide singleton.

### Platform event ownership

- Initial width and height classifications come from UIContext breakpoint getters.
- Breakpoint changes are registered on the UIObserver obtained from UIContext, not on UIContext itself.
- Exact viewport changes and system avoid-area changes use the same Window adapter and feed one refresh path.
- Every listener is registered once and removed from the same source instance with the same callback reference.
- The composition root publishes a compact fallback before page loading and starts the store after page content loads successfully.
- Existing status-bar storage is maintained during migration and removed only after all consumers use the new snapshot.

### Responsive product rules

- XS/SM uses bottom navigation; MD uses a vertical navigation rail; LG/XL uses a fixed sidebar.
- Notes uses Stack in XS/SM/MD and Split in LG/XL. The switch is explicit at 840vp.
- The assistant uses a bottom sheet in XS/SM and a side panel in MD/LG/XL.
- Note detail uses fullscreen presentation in compact windows and a constrained side-panel presentation in wider windows.
- Width breakpoint is the sole primary criterion for navigation, Notes Stack/Split, and assistant presentation.
- Height breakpoint may alter vertical spacing, scrolling, visible header density, and keyboard behavior, but never reverses the width-selected information architecture.
- `AUTO_WITH_ASPECT_RATIO` is not used.
- GridRow custom breakpoints must be configured when five width classes are required; its default four classes are not treated as equivalent to Window WidthBreakpoint.
- Navigation occupies structural space. Content uses remaining-space layout and must not use a full-height child that pushes navigation outside the visible area.

### Page migration

- The application shell continues to host the same business pages while switching only navigation presentation.
- The fake assistant Tab and its index-reversion behavior are removed. The assistant becomes an action in each navigation presentation.
- Notes first extracts reusable detail content so independent route and wide-screen pane share one implementation.
- Notes ViewModel instances, load guards, selections, and scroll state are not recreated by layout changes.
- Home, settings, profile, overlays, and galaxy migrate after the shell and Notes tracer bullet establish the seam.
- Long lists migrate to lazy data sources without changing displayed content or persistence behavior.
- The prototype's mock data, debug strip, forced-width chips, and visual styling are not copied into production.

### Delivery phases and ownership

- Phase 1 delivers the window layout module, source adapter, publisher, composition-root lifecycle, fallback snapshot, compatibility status-bar publication, and pure mapping/lifecycle tests.
- Phase 2 delivers responsive application navigation, removal of the fake assistant Tab, reusable Notes detail content, and the Notes Stack/Split tracer bullet.
- Phase 3 migrates Home, settings/profile, list virtualization, overlays, and viewport-driven galaxy behavior in blocker-first tickets.
- Phase 1 and Phase 2 have one UI owner. Shared layout, platform, token, shell, and navigation files are owned only by the UI integrator.
- Phase 3 may run in isolated worktrees by page. Page owners do not edit shared layout, platform, token, shell, or navigation files.
- Backend/LLM workstreams do not modify entry pages during this work.

## Testing Decisions

### Test philosophy

- Tests assert behavior at the highest stable seam: window facts in, one layout snapshot out; source events in, published snapshots out; page actions and visible layouts out.
- Tests do not assert private helper names, internal object allocation, exact file layout, or copied source text except for explicit architectural guardrails.
- Business behavior remains covered by existing ViewModel, Service, persistence, and smoke tests; responsive tests prove it is not re-triggered or reset.

### Policy tests

- Cover every WidthBreakpoint across representative HeightBreakpoint values.
- Assert XS/SM → bottom navigation, MD → rail, LG/XL → sidebar.
- Assert XS/SM/MD → Notes Stack and LG/XL → Notes Split.
- Assert XS/SM → assistant bottom sheet and MD+ → assistant side panel.
- Assert height changes do not alter navigation, Notes Stack/Split, or assistant presentation selected by width.
- Assert XL does not produce a four-column Subject policy.
- Assert content maximum width and padding remain bounded on XL.

### Store and source tests

- Initial snapshot publishes before the first asynchronous event.
- Repeated start does not duplicate subscriptions.
- One breakpoint event updates width and height classifications together.
- Window-size changes refresh viewport without creating a second breakpoint policy.
- Avoid-area changes refresh insets.
- Equivalent facts do not republish equivalent snapshots.
- Stop removes all listeners using original callback references and is idempotent.
- Partial registration failure is cleanable.

### Structural guardrails

- Pages and overlays do not call breakpoint APIs, register window listeners, inspect device type, or inspect fold state.
- The pure policy does not import ArkUI, ViewModels, Services, DAOs, or business types.
- The snapshot contains no business state or business model.
- Test harness manifests declare phone, tablet, and 2-in-1 when used for multi-device validation.
- The assistant is not represented as an empty or redirecting Tab.

### Component and integration tests

- The same business page instances render under bottom, rail, and sidebar shells.
- SM → LG → SM preserves current page, selected Subject/KnowledgeUnit, scroll position, assistant session, and draft.
- Notes changes Stack/Split at 839/840vp without duplicate loading.
- Independent settings and Subject-detail routes receive the same layout snapshot as the main shell.
- Assistant input remains visible when keyboard, window size, and presentation change.
- Bottom navigation remains visible at 599vp and does not overlay or get pushed outside content.
- Phone camera/OCR/AI/persist smoke flow remains unchanged.

### Visual and device matrix

- Boundary widths: 599/600vp and 839/840vp.
- Representative widths: 300, 360, 768, 1024, and 1440vp.
- Every representative width has a high-window and low-window case.
- Real window auto mode is the acceptance source; forced width selection exists only in test harnesses.
- Phone plus one tablet receive release-device validation; adjustable 2-in-1 emulator covers free-window and keyboard/mouse behavior.
- Screenshots check overlap, clipping, unexpected whitespace, navigation mode, Notes pane mode, empty data, long content, and long formulas.
- Existing ArkTS lint, lint unit tests, naming lint, build, and applicable Hypium tests must remain green.

## Out of Scope

- Foldable-specific APIs, fold-status listeners, fold-angle listeners, display-mode listeners, and crease avoidance.
- Wearable and TV device types.
- Business logic, CaptureGraph, KnowledgeUnit schema, AI prompts, LLM calls, OCR, persistence, review scheduling, or database changes.
- Redesigning MindTrace's established visual language, colors, fonts, motion, copy, or component styling based on the prototype.
- Copying prototype data, debug controls, forced-width chips, or prototype UI into production.
- Adopting `AUTO_WITH_ASPECT_RATIO`.
- Replacing the entire router or moving all independent entry pages under Navigation in Phase 1.
- Full multi-window support; the first implementation supports one main WindowStage.
- Adding a new UI/state-management dependency.
- Changing Subject list/card preference beyond preserving one-column list and two-column cards.

## Further Notes

- The approved architecture and test seam are documented in the linked window-layout strategy design. This issue intentionally defers implementation; follow-up tickets should be produced with `/to-tickets` when the team schedules the work.
- Ticket order must be blocker-first: layout module → application shell and Notes tracer bullet → independent page migrations → overlays/galaxy → input/resources → release matrix.
- The prototype proved product semantics and exposed scaffold/viewport mistakes; it is a primary source, not production-quality code.
- Specs 016, 017, 018, 019, 020, and 021 are occupied by other in-flight work (LLM settings, agent workflow architecture, reasoning-process display, reply-body contract, knowledge-graph RDB), so this work uses Spec 022.
