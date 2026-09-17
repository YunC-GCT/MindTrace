# 聊天 Markdown+LaTeX 一次性渲染卡顿与预缓存缺口调研 — 2026-09-13

> **Date:** 2026-09-13
> **Scope:** 聊天浮窗流式渲染链路 (AgentFloatWindow → AgentMessageList → ChatBubble → FormulaSplitRenderer / MarkdownRenderer → MathTextRenderer → rawfile/render.html) / 流式结束一次性卡顿因果链 / 现有缓存覆盖面盘点 / 官方预热与预缓存手段 (离线Web组件池 / 渲染进程保活 / JS 字节码缓存 / JSBridge 成本 / KaTeX 输出裁剪) / 修复路线排序 — 只做设计调研, 不改代码
> **Project:** MindTrace (`entry` module, SDK 6.1.1(24))
> **Author:** research agent (devecocli docs 一手信源 + katex.org 官方文档 + 项目源码逐行核对)
> **Trigger:** 聊天浮窗 AI 回复流式结束瞬间可感知卡顿; 且全仓 grep `initializeWebEngine` / `setRenderProcessMode` 0 命中 — 2026-09-11 调研记载"已落地"的 EntryAbility 引擎预热在当前代码树丢失, 需重新盘点"预缓存到底缺哪块"

---

**TL;DR:** 流式→结束的一次性卡顿不是单一原因, 是三层叠加: **(1) 流式期间每个 delta 都在做全量隐性工作** — `messages` 全量 map、`chatItemKey` 含内容长度导致流式行整行销毁重建、`sm.save()` 每 delta `JSON.stringify` 全部会话 + `putSync` + `flush`; **(2) finish 瞬间 key 翻转, 可见渲染块在一帧内同步挂载 N 个 Web** (`MathTextRenderer` 的 chat profile 没有_note_ profile 的错峰 defer), 每个独立加载 `render.html` 并重新解析执行 marked + KaTeX + auto-render 三个 JS 文件, 再各走一次 `runJavaScript` 往返 (官方实测 ArkTS 侧 7~9ms/次) + 高度回传触发重排; **(3) 现有 MATH_RENDER_CACHE 只缓存 KaTeX HTML 字符串** — 命中仍要创建 WebView、加载页面、建 JS 上下文、跑协议往返, "省了 KaTeX, 没省 WebView"。官方生态可用的杠杆按序: 恢复 EntryAbility 预热 (回归修复) → 流式存盘节流 + key 去长度化 (纯 UI 层, 零风险) → KaTeX `output:'html'` 裁掉默认 MathML 冗余 (白捡) → chat 错峰挂载 → 保活 Web (`WebKeepAlive.ets` 已有半成品但全仓 0 引用) + 官方"离线Web组件"池 (`web-offline-mode`, NodeContainer 预建 Hidden/Inactive 实例) 是结构性修复; 原生公式渲染仍被官方排除 (faqs-arkweb-97), API 26 的文本增量渲染 (`PARAGRAPH_CACHE`) 是官方方向但 SDK 6.1.1(24) 用不了。

## 问题陈述

1. 聊天浮窗 AI 回复在流式结束瞬间的一次性卡顿, 完整因果链是什么? 由哪些成本叠加构成?
2. 现有预缓存 (`MATH_RENDER_CACHE` / `MarkdownParseCache`) 到底缓存了什么、没缓存什么? 为什么缓存命中时首次出现仍卡?
3. 官方生态有哪些适用于本场景的预热 / 预建 / 预缓存 / 增量渲染手段? 各自收益、代价与前提条件?
4. 原生 (非 WebView) 渲染 LaTeX 的替代方案在当前 SDK 版本是否存在?
5. 综合以上, 修复路线应如何排序?

## 调研方法

- `devecocli docs search/read` 逐篇研读官方文档, 本篇直接引用的: `bpta-web-develop-optimization` (全文精读), `web-offline-mode`, `web-component-migrate`, `web-event-sequence`, `web-predictor`, `faqs-arkweb-21`, `faqs-arkweb-42`, `faqs-arkweb-59`, `faqs-arkweb-97`, `faqs-arkweb-132`, `faqs-arkweb-140`, `ts-text-common`, `ts-universal-attributes-reuse`, `ts-custom-component-decorator-reusable`, `ts-container-list`, `ts-universal-styled-string`, `ts-basic-components-richeditor`, `faqs-network-80`。
- KaTeX 一手信源: [katex.org/docs/api](https://katex.org/docs/api) + [katex.org/docs/options](https://katex.org/docs/options) (官方文档, KaTeX 仓库背书)。
- 项目源码逐行核对: `AgentFloatWindow.ets` / `AgentMessageList.ets` / `ChatBubble.ets` / `ChatModels.ets` / `ChatSession.ets` / `FormulaSplitRenderer.ets` / `MathTextRenderer.ets` / `WebKeepAlive.ets` / `render.html` / `EntryAbility.ets`, 并用全仓 grep 验证关键 API 0 引用。
- 空结果如实记录: `devecocli docs search precompileJavaScript` / `warmup` / `打字机` 均 0 hits — 官方没有"LLM 流式聊天 UI"专门最佳实践文档, 本篇依据仅为通用性能指南。

## 现状诊断 (源码, 对应 Q1 + Q2)

### D1. 流式期间: 每个 delta 的全量隐性成本

流式路径上每个 SSE delta 触发的完整动作链:

1. **`messages` 数组全量 map** — `appendAiMsg` 对整个数组做一次 `map` 生成新数组 (仅目标消息内容变化)。源: `AgentFloatWindow.ets:110-112`。
2. **`@Watch` 触发全量存盘** — `@State @Watch('onMessagesChange') messages` (`AgentFloatWindow.ets:46`), 每次 delta 执行 `sync()` + `sm.save(this.sessions)` (`AgentFloatWindow.ets:88-92`; `sync()` 定义 `AgentFloatWindow.ets:129-132`)。而 `save` = `JSON.stringify(全部会话)` + `putSync` + `flush` (`ChatSession.ets:52-61`) — 成本 O(全部历史消息), 频率 = token 到达频率, 全部发生在主线程。
3. **流式行整行销毁重建** — `chatItemKey` 把 content 长度、reasoning 长度、streaming 标志编进 key (`ChatModels.ets:41-47`), 且被用作 LazyForEach 的 keyGenerator (`AgentMessageList.ets:97`) → 流式行的 key 每个 delta 都变, 该 ListItem 整行销毁重建。流式分支是轻量 `Text` (`ChatBubble.ets:136-143`), 所以这里烧的是组件 churn + 序列化, 不是 Web。
4. **列表全量刷新通知** — `@Prop @Watch` 级联到 `AgentMessageList.onMessagesChanged` → `setMessages` → `slice` + `onDataReloaded` 全量通知 (`AgentMessageList.ets:42-51`, `:68-76`)。滚动到底已有 50ms 节流 (`AgentMessageList.ets:74`), 但数据通知本身没有节流。

### D2. 结束瞬间: 一帧内的"惊群"挂载

1. `finishAiMsg` 把 streaming 翻转为 false (`AgentFloatWindow.ets:113-115`) → key 最后一次翻转 → ChatBubble 重建 → 渲染分支从轻量 `Text` 切换: 含公式 → `FormulaSplitRenderer(profile:'chat')`, 否则 → `MarkdownRenderer(progressive:false)` (`ChatBubble.ets:135-157`)。
2. `FormulaSplitRenderer` 按 `$$` 边界拆块并合并相邻文本块 (设计注释称减少 ~40% WebView 数量, `FormulaSplitRenderer.ets:16`), 硬上限 30 块 (`:30`), LazyForEach 按需创建 — 惊群规模 = 视口内可见块数, 典型是结束消息的最近几个公式/文本块。
3. **chat profile 没有错峰**: `shouldDeferWebRender()` 仅对 `note` 返回 true (`MathTextRenderer.ets:465-467`); note profile 有 24ms 基距 / 22ms 步距 / 8 槽的错峰机制 (`MathTextRenderer.ets:50-52`), chat 全部同步挂载。
4. 每个块 = 一个 `Web({ src: $rawfile('render.html'), controller })` (`MathTextRenderer.ets:521`), 同帧创建。每个实例独立: 加载 `render.html` → 解析执行 `marked.min.js` + `katex.min.js` + `auto-render.min.js` (`render.html:217-219`) → `onPageEnd` 置 `pageReady` 后才发起渲染 (`MathTextRenderer.ets:530-533`)。每个 Web 是独立 JS 运行环境, 销毁即释放 (docId `web-event-sequence`, 转引自 [arkweb-render-pipeline-stability-2026-09-11](./arkweb-render-pipeline-stability-2026-09-11.md) §2)。
5. 渲染 = 每块至少一次 `runJavaScript('renderForCache(...)')` 往返 (`MathTextRenderer.ets:288-291`); 官方实测 ArkTS 侧与前端页通信 7~9ms/次 (docId `bpta-web-develop-optimization` §JSBridge)。高度经 promise 返回 → `webHeight` 更新 → Web 与 List 重排 (`MathTextRenderer.ets:292-306`, `:529`)。多块同时到达 → 多次高度跳变; 官方 FAQ 明确 "Web组件频繁改变高度卡顿", 解法是节流/防抖 (docId `faqs-arkweb-140`)。现有 `estimateHeight` 先行占位 (`MathTextRenderer.ets:482-503`) 已缩小跳变幅度, 但块级重排仍逐个发生。
6. `build()` 内联调用 `normalizeForRender` (ContentProtocol 规范化 + 风险清洗) (`MathTextRenderer.ets:506`), 主线程执行, 每次重建重复计算。
7. 桥返回值有长度上限: 公式多时 `encodeURIComponent(innerHTML)` 超 `runJavaScript` 返回值上限 → 降级为 `render()` 只返高度、放弃缓存 (`MathTextRenderer.ets:307-333`) — `runJavaScript` 只能返回 string (docId `faqs-arkweb-21`), 该降级链是代码对这一限制的自适应。

### D3. 预缓存覆盖面: 省了 KaTeX, 没省 WebView

1. `MATH_RENDER_CACHE`: LRU 64 条 / 600k 字符 / TTL 10min, key = `profile|v2|forceDisplay|contentHash` (`MathTextRenderer.ets:44-48`, `:406`), 值 = `encodedHtml + height`。
2. **命中路径仍要 WebView 全流程**: 命中时 `webHeight` 直接用缓存值, 但 `applyCachedRender` 仍需 `runJavaScript` 注入 HTML (`MathTextRenderer.ets:336-349`), 前提是 Web 已 `onPageEnd`。即缓存消除的只是 `marked.parse` + `katex.renderToString` 的 JS 执行; **不消除**: WebView 实例创建、`render.html` 页面加载、三个 JS 文件的解析执行、JS 上下文建立、协议往返。
3. `MarkdownParseCache` (LRU 48 / 256KB) 只省 ArkTS 侧 Markdown 解析, 与 Web 无关。
4. **与 NoteDetailOverlay 的基建差距**: 笔记详情有 `DetailRenderQueue` (16ms 节拍 / 8ms 帧预算 / 优先级 / 上限 80) + `DetailRenderCache` 串行渲染队列与模型缓存, chat 一概没有 — chat 的所有块在同一帧并发竞争。
5. `WebKeepAlive.ets` 已完整实现保活 Web (about:blank + `onRenderExited` 恢复 ≤3 次, `WebKeepAlive.ets:21`, `:27`), 但**全仓 0 引用** — 从未被挂载。
6. **回归发现**: `EntryAbility.ets` (119 行) 无 `initializeWebEngine` / `setRenderProcessMode`, 全仓 grep 0 命中 — [arkweb-render-pipeline-stability-2026-09-11](./arkweb-render-pipeline-stability-2026-09-11.md) 记载"已落地"的引擎预热 + 单渲染进程修复在当前树**丢失**, 首个 Web 仍要现拉引擎动态库与渲染进程。

## 生态调研 (官方一手信源, 对应 Q3 + Q4)

### E1. Web 组件池: 官方"离线Web组件"就是预建姿势

- docId `web-offline-mode`: "Web组件能够实现在不同窗口的组件树上进行挂载或移除操作，这一能力使得开发者可以预先创建Web组件，从而实现性能优化…此类组件创建后不会立即挂载到组件树中，状态为Hidden和Inactive" — 基于 NodeContainer/BuilderNode 命令式创建。
- docId `web-event-sequence`: "Web页面保活可以参考使用离线Web组件"。
- docId `web-component-migrate`: 同一机制支持跨窗口迁移。
- 含义: **预建 K 个 `render.html` 实例轮转复用 (组件池) 是官方明确支持的姿势**, 可把 D2-4 的"创建+加载+JS 解析"整段从用户路径上移除。

### E2. 渲染进程保活 (预启动Web渲染进程)

- docId `bpta-web-develop-optimization` §预启动: 收益约 140ms (消除渲染进程拉起耗时); 空白组件约 200MB 内存; "当至少一个Web组件存活时，Web渲染进程会一直存在"; "建议后续页面加载复用预创建的Web组件"; 官方案例 82ms → 44ms。
- 与 [arkweb-render-pipeline-stability-2026-09-11](./arkweb-render-pipeline-stability-2026-09-11.md) 的结论一致: 保活一个 Web = 保活渲染进程。

### E3. JS 字节码缓存的边界 (对 rawfile 不友好)

- 预编译 (`precompileJavaScript`): "仅HTTP或HTTPS协议请求的JavaScript文件可以预编译"、"不支持本地JavaScript文件预编译缓存" (docId `bpta-web-develop-optimization` §预编译) → `render.html` 的本地 JS **不可用**。
- 拦截替换 Code Cache: "Web组件默认支持HTTP协议和自定义协议的JavaScript生成字节码缓存", 需 `customizeSchemes` (isCodeCacheSupported) + ResponseDataID 标识版本, 响应数据 ≥1024 字节才生成, 第三次加载起生效 (2.4MB 资源 ~67ms) — `render.html` 的 JS 走 `resource://rawfile`, **要吃到 Code Cache 必须迁移到自定义协议拦截**, 官方适配难度评级"高"。
- 网络类优化 (预解析/预连接/预下载/预取POST) 对本地页全部不适用 (docId `web-predictor`: 仅域名级 DNS/TCP) — 沿用 2026-09-11 调研裁决, 不重述。

### E4. JSBridge 成本与注入姿势

- 通信成本: ArkTS 侧 7~9ms/次, NDK 侧 2~6ms (docId `bpta-web-develop-optimization` §JSBridge 实测表); 同步注册的 JSBridge 函数实测阻塞 1398~2707ms, 异步 2~4ms; "注册在ETS侧的JSBridge函数调用时需要在主线程上执行" — 高频回调注册为同步函数是主线程杀手。
- `runJavaScript` 是运行时注入, 页面导航后失效; `javaScriptOnDocumentStart` 是文档初始化注入, 可跨导航存续 (docId `faqs-arkweb-42`); `onControllerAttached` → 页面加载前、`onPageEnd` → 官方推荐执行 `runJavaScript` 的时机 (docId `web-event-sequence`, 转引自 2026-09-11 调研)。
- `runJavaScript` 与 `runJavaScriptExt` 均为异步; 前者仅返回 string, 后者返回结构化 JsMessageType (docId `faqs-arkweb-21`)。

### E5. 高度与滚动嵌套

- docId `faqs-arkweb-140`: Web 高度频繁变化导致卡顿, 官方解法 = 对高度更新节流/防抖。
- docId `faqs-arkweb-132`: `layoutMode(WebLayoutMode.FIT_CONTENT)` + `RenderMode.SYNC_RENDER` 可让 Web 适配内容高度并随 Scroll 统一滚动 — 这是"单 Web 渲染整条消息"架构的前提条件 (若走该路线)。

### E6. 原生渲染能力: 现状与前瞻

- docId `faqs-arkweb-97` (2026-09-13 复核原文): "HarmonyOS目前没有提供专门的数学公式渲染组件，可以使用WebView组件来加载支持数学公式渲染的网页" → **原生替代继续被官方排除**。
- docId `ts-text-common`: 文本渲染增量更新策略 (枚举 `NONE`=全量布局 / `PARAGRAPH_CACHE`=段落级缓存, 要求 styled string 对象不变), **API 26.0.0 起步** — 官方已有流式文本增量渲染方向, 但项目 SDK 6.1.1(24) (build-profile.json5 `targetSdkVersion`) 不可用, 仅作前瞻。
- `StyledString`/`CustomSpan` (C-API 头文件明确列举聊天应用场景, docId `ts-universal-styled-string` / `capi-custom-span-h`) 与 `RichEditor`/`Span` 只解决富文本排版; LaTeX 排版引擎仍无官方组件。

### E7. 列表与组件复用

- docId `ts-container-list`: List + LazyForEach + 预加载 "适用于消息列表" — 现有 `AgentMessageList` 骨架正确, 缺的是细粒度通知 (见 D1-4)。
- `@Reusable` (V1) / `@ReusableV2` (API 18+, docId `ts-custom-component-decorator-reusable` / `ts-universal-attributes-reuse`) 通过组件复用减少创建销毁; 但 Web 生命周期绑定 Controller 与自定义组件 (销毁即释放 JS 环境), **Web 的复用应走 E1 离线节点池, 而非 @Reusable**。

### E8. KaTeX 官方选项 (katex.org)

- [katex.org/docs/options](https://katex.org/docs/options) §output: 默认 `htmlAndMathml` = "HTML for visual rendering + MathML for accessibility" **双份输出**; 设 `output:'html'` 即纯视觉输出, 砍掉并行的 MathML 冗余。
- `displayMode: true` 关闭自动换行; `throwOnError:false` 把非法 LaTeX 渲染为红色源码 (已是现状)。
- **项目现状**: `render.html` 的 `renderFormula` (`render.html:287-293`) 与 auto-render 调用 (`render.html:240-253`) 均**未设 `output`** → 走默认双份输出。加一行 `output: 'html'` 是白捡的裁剪; 代价是失去 MathML 无障碍层 (团队决策项)。
- [katex.org/docs/api](https://katex.org/docs/api): `renderToString` 即服务端式"渲染成 HTML 字符串", 与现有 `renderForCache` 用法一致, 无姿势问题。

### E9. 空结果记录 (如实)

- `devecocli docs search` 对 `precompileJavaScript`、`warmup`、`打字机` 均 0 hits; 官方无 "LLM 流式聊天 UI / 打字机效果" 专门最佳实践文档 — 流式 UI 的节流/增量策略只能依据通用性能指南 (docId `bpta-time-optimization-of-the-main-thread` 等) 与 FAQ 推导。

## 可行方案对比 (对应 Q5)

| # | 方案 | 内容 | 预期收益 | 代价/风险 | 优先级 |
|---|---|---|---|---|---|
| 1 | **恢复引擎预热 (回归修复)** | `EntryAbility.onCreate` 恢复 `initializeWebEngine()` + `setRenderProcessMode(SINGLE)` (姿势已被 2026-09-11 调研逐字核对) | 消除首个 Web 的引擎动态库/渲染进程拉起 | 无 (0 业务改动) | **P0** |
| 2 | **流式存盘节流** | `onMessagesChange` 的 `sm.save` 从每 delta 改为 finish 时 + 防抖 (如 2s); `sync()` 保留 | 消除每 token 的全量 JSON 序列化+落盘 | 崩溃时丢最近 2s 草稿 (可接受, 需团队确认) | **P0** |
| 3 | **chatItemKey 去长度化** | key 改为 `id + streaming` (去掉 content/reasoning 长度), 流式行不再整行重建 | 消除流式期组件 churn; finish 仅一次受控重建 | 需验证 @Prop 内容 diff 仍驱动 Text 更新 | **P0** |
| 4 | **KaTeX `output:'html'`** | `render.html` 两处 KaTeX 调用加 `output:'html'` | 砍掉 MathML 冗余, 输出与 DOM 显著减小, 渲染/传输/注入全链受益 | 失去 MathML 无障碍层 | **P0** (白捡) |
| 5 | **chat 错峰挂载** | `shouldDeferWebRender` 扩展到 chat profile, 复用 note 的 defer 时槽机制 | finish 惊群摊到多帧 | 结束瞬间块逐个出现 (视觉可接受, note 已如此) | P1 |
| 6 | **结束增量通知** | finish 时以 `onDataChange`/`onDataAdd` 替代 `onDataReloaded` | 消除全列表重建 | IDataSource 需精细化改造 | P1 |
| 7 | **高度回传节流** | 多块高度跳变合并/防抖 (官方 faqs-arkweb-140 姿势) | 减少重排次数 | 高度短暂滞后 | P1 |
| 8 | **保活 Web + 离线组件池** | 先挂 `WebKeepAlive` (已有半成品, 0 引用) 保渲染进程; 进阶按 `web-offline-mode` 用 NodeContainer 预建 K 个 `render.html` 实例轮转 | 结构性修复: 把"创建+加载+JS 解析"移出用户路径 | 内存 (官方空白组件 ~200MB 为进程级参考); 池管理复杂度; 浮窗 subwindow 场景未验证 | **P2** |
| 9 | 单 Web per 消息 | `faqs-arkweb-132` FIT_CONTENT + SYNC_RENDER | WebView 数量降为每消息 1 个 | 与 1800vp 上限/分块拆分的历史决策冲突 (formula-split-render-plan), 架构级大改 | P3 |
| 10 | Code Cache 自定义协议 | rawfile JS 迁移 scheme 拦截 + ResponseDataID | 第三次起 JS 编译 ~67ms 级 | 适配难度"高" (官方评级), 收益上限小 | P3 |
| 11 | 原生公式渲染 / API 26 增量文本 | — | — | faqs-arkweb-97 排除 / SDK 版本不够 | **否决** |

排序逻辑: P0 全部是低风险高确定性 (1 是回归修复, 2+3 是纯 UI 层, 4 是一行裁剪); P1 消除剩余惊群; P2 才动架构 (池化), 且官方给了完整姿势; P3 收益/风险比不支持现在做。

## 与既有研究的关系

- **[arkweb-render-pipeline-stability-2026-09-11](./arkweb-render-pipeline-stability-2026-09-11.md)**: 本篇是其"下一章" — 进程模型、保活结论、网络优化不适用性**直接继承不重述**; 焦点从进程稳定性 (THREAD_BLOCK_6S) 转向 UI 层卡顿与预缓存缺口。**行动项: 其记载的 EntryAbility 修复在当前树丢失, 应作为回归项立即恢复** (本篇方案 #1)。
- **[agent-reasoning-process-display-research-2026-09-11](./agent-reasoning-process-display-research-2026-09-11.md)**: 同一 ChatBubble 渲染路径的 reasoning 展示侧; 其"无官方折叠/打字机组件"的结论与本篇 E9 空结果一致。
- **[docs/legacy/mindtrace/plans/w4/formula-split-render-plan-2026-07-24.md](../legacy/mindtrace/plans/w4/formula-split-render-plan-2026-07-24.md)**: WebView 1800vp 可见上限 (超出留白) 是"多 WebView 分块拆分"的源头约束; 任何"单 Web 整消息"方案 (本篇 #9) 必须正面回答它。

## Open questions

1. `WebKeepAlive` / 离线 Web 组件池在浮窗 (subwindow) 组件树上的挂载可行性未验证 — `web-offline-mode` 文档未明确 subwindow 场景。
2. `runJavaScript` 桥返回值长度上限的准确数值未测 (现状靠降级链自适应, `MathTextRenderer.ets:307-333`)。
3. KaTeX `output:'html'` 的无障碍损失是否可接受, 需团队/评委演示场景决策。
4. Code Cache 迁移自定义协议后对 `render.html` (katex.min.js 等) 的实际收益未实测 — 收益上限本身较小, 优先级低。
5. API 26 `PARAGRAPH_CACHE` 增量文本渲染的升级窗口 — 官方方向的长期解, 当前 SDK 不可用。

## 参考资料

官方文档 (docId, `devecocli docs read`):

- `bpta-web-develop-optimization` — 预启动Web渲染进程 (~140ms / ~200MB / 存活规则 / 82→44ms 案例); 预编译 JS 仅 HTTP(S)、"不支持本地JavaScript文件预编译缓存"; Code Cache 需自定义协议 + ResponseDataID、≥1024 字节、第三次起 ~67ms; JSBridge ArkTS 7~9ms / NDK 2~6ms / 同步阻塞 1398~2707ms vs 异步 2~4ms / ETS 侧注册函数在主线程执行。
- `web-offline-mode` — 离线Web组件: NodeContainer 预建 Hidden/Inactive 实例, 跨组件树挂载/移除。
- `web-component-migrate` — Web 组件跨窗口迁移 (同 BuilderNode 机制)。
- `web-event-sequence` — 生命周期: onControllerAttached / onPageEnd 推荐时机 / 销毁即释放 JS 环境 / "Web页面保活可以参考使用离线Web组件"。
- `web-predictor` — prepareForPageLoad 仅域名级 DNS/TCP。
- `faqs-arkweb-21` — runJavaScript 仅返回 string; runJavaScriptExt 返回 JsMessageType。
- `faqs-arkweb-42` — runJavaScript 运行时注入导航即失; javaScriptOnDocumentStart 跨导航存续。
- `faqs-arkweb-59` — javaScriptOnDocumentStart / javaScriptOnDocumentEnd 时机语义。
- `faqs-arkweb-97` — "HarmonyOS目前没有提供专门的数学公式渲染组件，可以使用WebView组件"。
- `faqs-arkweb-132` — Scroll 嵌套 Web: layoutMode(FIT_CONTENT) + RenderMode.SYNC_RENDER 适配内容高度。
- `faqs-arkweb-140` — Web 高度频繁变化卡顿, 节流/防抖。
- `ts-text-common` — 文本渲染增量更新策略 (NONE / PARAGRAPH_CACHE), API 26.0.0 起。
- `ts-universal-attributes-reuse` / `ts-custom-component-decorator-reusable` — @ReusableV2 (API 18+) / @Reusable 复用选项。
- `ts-container-list` — List + LazyForEach 懒加载/预加载, "适用于消息列表"。
- `ts-universal-styled-string` / `capi-custom-span-h` — StyledString/CustomSpan 自定义绘制, C-API 列举聊天应用场景。
- `ts-basic-components-richeditor` / `ts-basic-components-span` — 原生富文本组件边界。
- `faqs-network-80` — SSE 官方 FAQ (EventSource 三方库)。
- 空结果: `precompileJavaScript` / `warmup` / `打字机` 搜索 0 hits。

KaTeX 官方 (一手):

- [https://katex.org/docs/api](https://katex.org/docs/api) — renderToString / render 语义, throwOnError 行为, 持久 macros。
- [https://katex.org/docs/options](https://katex.org/docs/options) — output 默认 htmlAndMathml (双份), 'html' 纯视觉; displayMode 换行语义; maxExpand/trust。

项目源码 (file:line):

- `entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets` — :46 (@Watch messages), :88-92 (每 delta save), :110-115 (map/finish), :129-132 (sync)。
- `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatSession.ets` — :52-61 (JSON.stringify 全量 + putSync + flush)。
- `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets` — :41-47 (chatItemKey 含长度/streaming)。
- `entry/src/main/ets/overlays/AgentFloatWindow/AgentMessageList.ets` — :42-51 (onDataReloaded 全量), :68-76 (级联+滚动), :97 (keyGenerator)。
- `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatBubble.ets` — :135-157 (streaming Text → FormulaSplitRenderer/MarkdownRenderer 切换)。
- `entry/src/main/ets/shared/molecules/FormulaSplitRenderer.ets` — :16 (~40% 合并注释), :30-31 (30 块/1500 字符上限)。
- `entry/src/main/ets/shared/atoms/MathTextRenderer.ets` — :44-52 (缓存常量 + note defer 时槽), :240-270 (cache 命中仍走 Web), :288-333 (runJavaScript 往返 + 桥超限降级), :336-349 (applyCachedRender), :406 (cacheKey), :465-467 (chat 无 defer), :506 (build 内联 normalize), :521-533 (Web 挂载 + onPageEnd)。
- `entry/src/main/ets/shared/atoms/WebKeepAlive.ets` — :21, :27 (完整实现, 全仓 0 引用)。
- `entry/src/main/resources/rawfile/render.html` — :217-219 (每实例加载 3 个 JS), :240-253 (auto-render 无 output), :287-293 (renderToString 无 output)。
- `entry/src/main/ets/entryability/EntryAbility.ets` — 全文 119 行, 无 initializeWebEngine / setRenderProcessMode (全仓 grep 0 命中, 回归)。
- `build-profile.json5` — targetSdkVersion / compatibleSdkVersion 6.1.1(24)。
