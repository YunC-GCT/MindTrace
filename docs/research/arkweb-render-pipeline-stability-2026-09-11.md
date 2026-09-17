# ArkWeb 渲染链路稳定性与预加载姿势调研 — 2026-09-11

> **Date:** 2026-09-11
> **Scope:** ArkWeb 渲染进程模型 / 引擎与渲染进程生命周期 / THREAD_BLOCK_6S 根因 / 官方性能优化手册 / Web 实例管理成本 / 稳定性与降级设计 / 渲染方案对比 / 预热与预缓存姿势 — 只做设计调研, 不改代码
> **Project:** MindTrace (`entry` module, SDK 6.1.1(24))
> **Author:** research agent (devecocli docs 一手信源 + SDK d.ts 签名核实 + 项目源码与 appfreeze 故障日志对照)
> **Trigger:** appfreeze `THREAD_BLOCK_6S` (2026-09-11 11:30:29, x86_64 emulator) — 聊天公式渲染批量创建 Web 组件触发渲染进程 spawn 风暴; `EntryAbility.ets` 已落地 SINGLE + initializeWebEngine 应急修复, 本调研验证该修复是否"姿势正确"并回答"下一步怎么设计"

---

**TL;DR:** 根因链已用日志+一手文档闭环: 每公式块一个 Web 组件 (5 分钟 77 个实例) 在每组件独立渲染进程模式下触发 nwebspawn 孵化风暴 (CPU 93.26%), 渲染进程 6s channel connect 超时被强杀 ×4, 每次终止状态经**主线程同步 binder IPC** `GetRenderProcessTerminationStatus` 查询, 单次 >6s → `THREAD_BLOCK_6S`。已落地的 `setRenderProcessMode(SINGLE)` + `initializeWebEngine()` 与官方示例逐字一致 (arkts-apis-webview-webviewcontroller), 姿势正确; 但 SINGLE 只治"进程数", 不治"churn" — 官方文档明确 "至少一个 Web 组件存活时渲染进程一直存在, 所有 Web 组件销毁时才终止" (bpta-web-develop-optimization §预启动), 因此**结构性修复 = 常驻一个隐藏保活 Web 组件**, 官方称其为"预启动Web渲染进程"方案 (收益 ~140ms, 空白组件 ~200MB)。原生替代方案被官方 FAQ 直接排除 ("HarmonyOS目前没有提供专门的数学公式渲染组件, 可以使用WebView组件", faqs-arkweb-97)。网络类优化 (预解析/预连接/预下载/预取POST) 对 `resource://rawfile` 本地页全部不适用。

## Question

1. ArkWeb 渲染进程模型: 有哪些进程? 默认渲染进程模式是什么? SINGLE 与 MULTIPLE 的确切语义?
2. 引擎与渲染进程生命周期: `initializeWebEngine` 到底预热了什么? nwebspawn 是什么? `onRenderExited` / `RenderExitReason` 的语义与恢复方式?
3. 主线程阻塞来源: 本次 THREAD_BLOCK_6S 的完整因果链? 官方视角下哪些操作会阻塞主线程、如何规避?
4. 官方性能优化手册: 预启动/预解析/预连接/预渲染/预取POST/预编译JS 各自的收益、代价与适用场景? 哪些适用于 MindTrace 的本地 KaTeX 页?
5. Web 实例管理成本: 每个 Web 组件的内存/算力代价? 官方对实例数量的建议? 单常驻 Web + 批量注入 vs N 个小 Web 的取舍? LazyForEach 相关注意事项?
6. 稳定性与降级设计: 渲染进程异常退出的标准处理姿势? MindTrace 现有降级链与官方姿势的差距?
7. 渲染方案对比: (a) 现状 N-Web 分块 / (b) 单常驻 Web 批量注入 / (c) 原生替代 — 各自依据与裁决?
8. 预热与预缓存的正确姿势: 引擎预热时机与成本 (实测模拟器 onCreate 阻塞 ~2.1s)? 页面预加载? 资源缓存?

## Method

- `devecocli docs search/read` 逐篇研读 13 篇官方文档 (ArkWeb 进程模型 / 生命周期 / 离线 Web 组件 / 渲染模式 / 加速访问 / 加载性能优化最佳实践 / 4 篇稳定性 FAQ / 3 篇 ArkWeb FAQ / WebviewController API 参考), 以 SDK d.ts 注释为 API 语义最终事实源。
- 核实 SDK 签名: `$DEVECO_HOME/default/openharmony/ets/api/@ohos.web.webview.d.ts` 与 `$DEVECO_HOME/default/openharmony/ets/component/web.d.ts` 关键接口行号。
- 通读项目渲染链路: `MathTextRenderer.ets` / `FormulaSplitRenderer.ets` / `ChatBubble.ets` / `EntryAbility.ets` / `rawfile/render.html`。
- 逐行核对 appfreeze 故障日志 (`THREAD_BLOCK_6S`, 2026-09-11 11:30:29, 模拟器, 进程存活 297s): 主线程栈、RenderProcessHost 事件、nwebspawn CPU、web id 计数。

## Findings

### 1. ArkWeb 进程模型与渲染进程模式 (Q1)

ArkWeb 为多进程架构, 共五类进程 (docId `web_component_process`):

| 进程 | 数量 | 职责 |
|---|---|---|
| 应用进程 | 1 | 承载 ArkWeb 组件与 SDK, 接收回调 |
| Web 渲染进程 | ≥1 | Blink 排版引擎 + V8, 执行页面渲染与 JS |
| Web GPU 进程 | 应用唯一 | GPU 任务合成 |
| Web 孵化进程 (nwebspawn) | 系统唯一 | 孵化渲染进程与 GPU 进程, 沙箱降权, 预加载动态库 |
| Foundation 进程 | 系统 | 管理应用与渲染进程的绑定关系 |

**默认模式**: "移动设备默认为单渲染进程模式 (SINGLE), 2in1 设备默认为多渲染进程模式 (MULTIPLE)" (docId `web_component_process`); FAQ 同样确认 "默认情况下, Web 组件采用单渲染子进程模式" (docId `faqs-arkweb-187`)。

**SINGLE / MULTIPLE 语义** (SDK `api/@ohos.web.webview.d.ts:3324`):
- `SINGLE = 0`: "multiple Web pages reuse a rendering subprocess" — 全部 Web 组件复用一个渲染子进程。
- `MULTIPLE`: "one rendering subprocess per Web component" — 每个 Web 组件独占渲染进程; 可用 `sharedRenderProcessToken` 让指定组件分组共享 (docId `web_component_process`)。
- `setRenderProcessMode` 传入无效值时回落 MULTIPLE (SDK `:6368`; docId `web_component_process`)。

**共享进程的连锁后果** (方案设计必须知道的官方语义):
- 渲染进程异常时, **所有共享该进程的 Web 组件都会触发 `onRenderExited`** — "Multiple Web components may share a single rendering process, and each affected Web component will trigger the callback" (SDK `component/web.d.ts:9132`; docId `faqs-arkweb-187`)。
- `terminateRenderProcess` 会影响该渲染进程关联的全部实例 (docId `web_component_process`)。

### 2. 引擎与渲染进程生命周期 (Q2)

**`initializeWebEngine` 预热的是引擎动态库, 不是渲染进程**: "在Web组件初始化之前, 通过此接口加载Web引擎的动态库文件, 以提高启动性能。自动预连接历史访问过的高频网站" (docId `arkts-apis-webview-webviewcontroller`)。约束: 必须在**UI 线程**调用 (异步线程调用会崩溃), 全局整个 APP 生命周期调用一次, 已有 Web 组件加载后调用无效 (SDK `:3812`)。官方示例位置即 `EntryAbility.onCreate`。

**渲染进程的生死规则**: 渲染进程在**首个 Web 组件创建时**由 nwebspawn 孵化; "当至少一个Web组件存活时, Web渲染进程将一直存在"; "仅在所有Web组件销毁时, 该进程才会终止" (docId `bpta-web-develop-optimization` §预启动Web渲染进程)。因此"保活一个 Web 组件"="保活渲染进程"。

**生命周期钩子的官方定位** (docId `web-event-sequence`):
- `onControllerAttached`: Controller 绑定后、页面加载前 — 注入 JS / 注册 proxy 的合法最早时机。
- `onPageEnd`: 官方推荐执行 `runJavaScript` 的时机。
- `onRenderExited`: 渲染进程退出回调 — 可保存数据/释放资源; **恢复需要显式 `refresh()` / `loadUrl()` 重载** (SDK `component/web.d.ts:9132`; docId `faq-stability-33`)。
- `aboutToDisappear`: 销毁 Web 组件与其 JS 运行环境 — 即每个 Web 组件实例化一个独立 JS 上下文, 销毁即释放。

**`RenderExitReason`** (SDK `component/web.d.ts:1585`): `ProcessAbnormalTermination=0` / `ProcessWasKilled=1` (如被系统 SIGKILL、任务管理器) / `ProcessCrashed` (如段错误) 等 — 区分"自己崩"与"被系统杀"的权威依据。

**销毁时机可调**: `setWebDestroyMode(FAST_MODE)` (API 20+) 让 Web 组件销毁时**立即**释放 JS/渲染上下文, 提升特定场景性能; 代价是销毁时机提前, 更易触发 17100001 (未绑定) 异常, 官方建议配合 `getAttachState` 查询防护 (docId `arkts-apis-webview-webviewcontroller`)。

### 3. THREAD_BLOCK_6S 根因链 (Q3)

用本次故障日志 + 上述官方模型可完整闭环 (日志 = appfreeze `THREAD_BLOCK_6S`, 20260911113029, x86_64 模拟器, 进程存活 297s, RSS 399,620kB):

1. **触发面**: 聊天流式回复完成 → `ChatBubble` 切换 `FormulaSplitRenderer` → 按 `$$` 拆块, 每块一个 `MathTextRenderer`, 每个渲染器**一个 Web 组件** (`MathTextRenderer.ets:521`)。日志中 5 分钟内 web id 已达 **77** (`OnPageVisible, web id = 73/67/77`, 日志 :3167/:3456/:3519)。
2. **孵化风暴**: 每组件独占渲染进程时, 77 个组件 = 77 次 nwebspawn 孵化。日志: nwebspawn CPU **93.26%** (:3651), 渲染进程 "channel connect timeout(6s), terminate process" **连续 ×4** (pid 15278/15287/15296/15299, :969/:1407/:1520/:1627), 对应 `RenderExited` ×4 (pid 15276/15278/15287/15296, :967/:1405/:1487/:1625) — 孵化饱和 → 6s 握手超时 → 强杀 → 再孵化, 恶性循环。
3. **主线程阻塞点**: 渲染进程终止状态由 NWeb 适配层经 AppMgr **同步 binder IPC** 查询 — 主线程栈: `AppMgrProxy::GetRenderProcessTerminationStatus` → `AppMgrClient` → `NWeb AafwkAppMgrClientAdapterImpl` (日志 :136-138)。阻塞任务 `webViewTask` 自 11:30:20.700 起持续运行, dump 时刻 11:30:24.258 仍未完成 (≥3.5s) (:47-51), 最终 6s watchdog 判定 `THREAD_BLOCK_6S` (Reason, :18-19; fault time 11:30:24)。
4. **修复验证**: 已落地 `setRenderProcessMode(SINGLE)` + `initializeWebEngine()` (`EntryAbility.ets:36-41`)。SINGLE 把 77 个组件压回 1 个渲染进程, spawn 风暴失去燃料; `initializeWebEngine` 预加载引擎动态库, 避免首个 Web 组件冷启动叠加孵化延迟。两者与官方示例一致, 姿势正确。

**官方视角下的主线程阻塞规避原则**:
- 减少渲染进程生命周期事件的频率与数量 (进程 spawn/terminate 都会牵动主线程 binder 查询);
- 保活: 只要有一个 Web 组件存活, 渲染进程不终止 (docId `bpta-web-develop-optimization`);
- `runJavaScript` 本身是异步 Promise (SDK `:4908`), JS 执行不阻塞主线程 — 项目每块注入 LaTeX 的方式 (`MathTextRenderer.ets:291`) 没有阻塞问题;
- watchdog 定位公式: 阻塞时长 = Timestamp − Current Running start at (docId `faq-stability-66`)。

**剩余风险**: SINGLE 模式下, 若某一时刻**所有** Web 组件都被销毁 (如聊天滚出视口、LazyForEach 全部回收), 渲染进程仍会按官方规则终止; 下次块进入视口再次拉起 — churn 根因只是被 SINGLE 稀释, 未被消除。这是 §Recommendation 保活方案的直接依据。

### 4. 官方性能优化手册与适用性 (Q4 / Q8)

官方优化全集及量化收益 (docId `bpta-web-develop-optimization` §方法概览表 + `faqs-arkweb-185`):

| 优化方式 | 官方量化收益 | 代价 | 适用 MindTrace? |
|---|---|---|---|
| **预启动Web渲染进程** (空白 Web 常驻) | 消除拉起渲染进程耗时 **~140ms** (案例 44ms vs 82ms) | 空白组件 ~**200MB** 内存、算力 | ✅ **高度适用, 建议落地** (§Recommendation P0) |
| 预解析 (DNS) | ~66ms | 可能解析未访问域名 | ❌ `render.html` 是 `resource://rawfile` 本地页, 无 DNS |
| 预连接 (`prepareForPageLoad`, SDK `:5744` 静态) | ~80ms | 同上 | ❌ 同上 |
| 预下载 | ~641ms | 网络/存储 | ❌ 同上 |
| 预取POST (`prefetchResource`, SDK `:6342`, API 22+) | ~313ms | 网络/存储 | ❌ 同上 |
| 预渲染 (离线 Web 组件, NodeController/NodeContainer, Hidden/InActive) | ~486ms, 页面"秒开" | 内存算力, 后台 Web 应 <**200** 个 | 🟡 可选 (组件级复用方向) |
| 预编译 JS 字节码缓存 | 5.76MB → ~2915ms (前两次) | 存储 | ❌🟡 明确限定 HTTP/HTTPS JS; 对 rawfile 本地 JS 未验证 (Open question 5) |
| 拦截替换 Code Cache (`onInterceptRequest`) | 2.4MB → ~67ms (第三次起) | 存储 | 🟡 需改走自定义协议拦截, 未验证 |

**官方对预启动的两条黄金约束** (docId `bpta-web-develop-optimization` §预启动Web渲染进程):
1. "额外创建ArkWeb组件会消耗内存和算力, 预创建一个空白的Web组件大约消耗200MB内存。因此, **建议后续页面加载复用预创建的Web组件**。"
2. "应用全局共享一个Web渲染进程, 仅在所有Web组件销毁时, 该进程才会终止。因此, **建议应用确保至少有一个Web组件处于活动状态**。"

时机建议: "建议在Web页面启动前执行预启动Web渲染进程, 例如在应用冷启动阶段…如果无法在冷启动期间预启动, 建议在系统空闲时间进行预启动。"

**引擎预热成本**: `initializeWebEngine` 官方无耗时数据; 项目实测 x86_64 模拟器 onCreate 中阻塞主线程 ~2.1s (项目实测, 见 `EntryAbility.ets:29-35` 注释背景)。官方明确不支持异步线程调用 (会崩溃), 示例位置固定在 onCreate — 只能接受该成本或换真机验证 (Open question 3)。

### 5. Web 实例管理成本与复用姿势 (Q5)

- **单组件内存量级**: "每个Web组件会额外占用一定的内存 (约200MB)" (docId `web-offline-mode`); 同样数字见 bpta 预启动节。注意: 该数字是**独立组件**的量级; SINGLE 共享渲染进程下, 新增组件的真实增量主要是 JS 上下文等, 官方未给出量化 (Open question 4) — 但方向不变: **实例越少越好**。
- **数量红线**: "单个应用后台创建的ArkWeb组件数量应少于200个" (docId `bpta-web-develop-optimization` 预渲染节); 动态创建在非 UI 线程执行 (docId `faqs-arkweb-52`)。
- **窗口级建议**: "每个窗口推荐只使用一个Web组件" (docId `web-offline-mode`) — MindTrace 当前聊天浮层内同时可见 3-8 个块级 Web, 与该建议差距明显。
- **一控一**: "一个WebviewController对象只能控制一个Web组件" (docId `arkts-apis-webview-webviewcontroller`) — 批量注入必须由持有目标组件的 controller 逐个执行。
- **复用与释放**: 离线 Web 组件用 `loadUrl('about:blank')` 重置后复用; 解绑后 `dispose()` 释放 (docId `web-offline-mode`)。三方库 **nodepool** 提供全局自定义组件复用, 官方推荐用于 Web 预渲染复用场景 (docId `bpta-web-develop-optimization` 预渲染节)。
- **渲染模式决定高度上限** (docId `web-render-mode`): 默认 `ASYNC_RENDER` = surface 节点, 物理高度上限 **7,680px**, Web 内部滚动, 性能功耗更优; `SYNC_RENDER` = canvas 节点, 上限 **500,000px**, 随 ArkUI 组件树合成滚动, 官方定位 "Web 作为富文本载体与其他组件共同滑动" 的场景, 不可动态切换。项目当前每块 `.height(webHeight)` + 外层 List 滚动, 属于 ASYNC 内部滚动受限后用分块规避 — 若走"每消息单 Web"路线, SYNC_RENDER 是官方对口模式。
- **高度抖动**: Web 高度频繁变化会引发卡顿, 官方建议节流/防抖 (docId `faqs-arkweb-140`, 摘要级引用)。项目已用估算高度兜底 + `clampHeight` 缓冲 + LRU 缓存高度 (`MathTextRenderer.ets:417-424`, `:44-48`) 对冲。

### 6. 稳定性与降级设计 (Q6)

官方标准姿势:
- `onRenderExited` → 读 `RenderExitReason` → 可保存数据/释放资源 → **显式 `refresh()`/`loadUrl()` 重载恢复** (SDK `component/web.d.ts:9132`; docId `faq-stability-33`)。
- 系统内存回收型被杀 (App Memory Deterioration) 会导致页面冻结, 恢复需**限次重试**避免死循环 (docId `faq-stability-23`)。
- 陷阱: `onPageEnd` 内 `setCustomUserAgent` 会引发二次加载, 应改到 `onControllerAttached` (docId `faqs-arkweb-134`/`faqs-arkweb-62`, 摘要级引用); 离线加载后需 `onActive` (docId `faqs-arkweb-56`, 摘要级引用)。

MindTrace 现有降级链与官方姿势对照 — **结构上已对齐, 且比官方最小要求更保守**:

| 环节 | 项目现状 | 官方姿势 |
|---|---|---|
| 前置降级 | `ContentProtocol` / `LatexRiskNormalizer` 判定 `plainFallback` 直接走 Text (`MathTextRenderer.ets:426-449`) | — |
| 渲染进程退出 | `onRenderExited` → `webFailed = true` → 整块降级纯 Text, 不留白 (`:534-538`, 注释明确引用 faq-stability-33) | 保存数据 + 显式重载 |
| bridge 超限 | `renderForCache` → `render` → `webFailed` 三级降级 (`:288-333`) | — |
| 流式守卫 | 流式期间纯 Text, 完成后才建 Web (`ChatBubble.ets`) | — |
| 缓存 | LRU 64 条 / TTL 10min / 60 万字符上限 (`:44-48`) | — |

差距: 项目选择**降级不重载** (退出即纯文本), 官方姿势是**可重载恢复**。在保活方案落地后渲染进程几乎不再退出, 当前保守策略可接受; 若后续要做重载, 必须带重试上限 (faq-stability-23 模式)。

### 7. 渲染方案对比 (Q7)

| | (a) 现状: N-Web 分块 | (b) 单常驻 Web 保活 (+ 现有分块) | (b+) 深化: 每消息单 Web 批量注入 | (c) 原生替代 |
|---|---|---|---|---|
| 做法 | 每公式/文本块一个 Web (`MathTextRenderer.ets:521`) | **追加一个隐藏空白 Web 常驻**, 分块渲染不变 | 每条消息一个 Web (SYNC_RENDER ≤500,000px), `runJavaScript` 一次注入整段 markdown | 自研 ArkUI Canvas 公式排版 |
| 实例数 | O(可见块), 日志 77/5min | O(可见块)+1, 但渲染进程**永不终止** | O(消息) | 0 |
| 官方依据 | onPageEnd→JS 时机正确 (web-event-sequence) | "至少一个Web组件处于活动状态" + "复用预创建的Web组件" (bpta); 离线 Web 组件模式 (web-offline-mode) | "每个窗口推荐只使用一个Web组件" (web-offline-mode); SYNC_RENDER 富文本载体场景 (web-render-mode) | **官方明示不存在**: "HarmonyOS目前没有提供专门的数学公式渲染组件, 可以使用WebView组件" (docId `faqs-arkweb-97`) |
| 风险 | churn 残留: 全部块滚出视口时渲染进程仍会终止再拉起 | +200MB 常驻; 保活组件自身被杀需恢复策略 | 高度协议/流式增量渲染需重构 `render.html` 协议; SYNC_RENDER 不可动态切换 | KaTeX 级排版质量无法短期复刻, 无一手依据 |
| 降级粒度 | 块级 (最细) | 块级 (不变) | 消息级 | — |
| 改动量 | 0 | 小 | 大 | 极大 |

**裁决**: 短期 (b), 中期评估 (b+), (c) 排除 (官方无组件支持, faqs-arkweb-97)。

## Recommendation

1. **(已落地, 保持)** `EntryAbility.onCreate` 中 `setRenderProcessMode(SINGLE)` + `initializeWebEngine()` — 与官方示例一致; SINGLE 必须早于任何 Web 组件加载, 位置不可后移 (`EntryAbility.ets:36-41`)。
2. **(P0, 结构性修复)** 常驻保活隐藏 Web 组件: 应用级单例 (冷启动后或首次进入聊天页时创建, `visibility.Hidden` 或 0 尺寸空白页), 使渲染进程按官方规则永不终止 — 直接消除"全部块滚出视口 → 渲染进程终止 → 再拉起"的 churn 残留。对应官方"预启动Web渲染进程"方案 (~140ms 收益, ~200MB 代价), 并遵循"复用预创建的Web组件"约束, 不反复创建销毁。
3. **(P1) 实例峰值治理**: `MathPreviewText` / `MarkdownRenderer` / `FormulaSplitRenderer` 多入口并存时建立全局在册 Web 组件计数与上限 (官方绝对上限 200, 项目目标应定在 ~10-20 量级); 预览/卡片场景优先纯文本估算或复用缓存 HTML。
4. **(P1) 降级链保持并补观测**: `onRenderExited` 降级纯 Text 保留; 补记 `RenderExitReason` 上报, 出现 `ProcessWasKilled` (系统杀) 时按 faq-stability-23 模式限次重载。
5. **(P2, 可选 spike)** 每消息单 Web (SYNC_RENDER) 批量注入, 或引入 nodepool 组件复用 — 需重构 `render.html` 的注入/高度回传协议 (`render.html:236-308`), 先做原型验证滚动与流式增量。
6. **(不建议)** 原生公式渲染替代 — 官方明示无此组件 (faqs-arkweb-97)。

## Open questions

1. x86_64 模拟器 nwebspawn 孵化渲染进程 >6s (CPU 93.26% 饱和) 的根因 — 无一手文档; 疑似模拟器特有, 需真机对照验证。
2. 模拟器的设备形态判定 (移动 vs 2in1) 决定默认 SINGLE/MULTIPLE — 日志的"每组件独立进程风暴"现象无法从一手信源反推当时默认模式; 显式 SINGLE 后未复现是侧面佐证, 非直接证据。
3. `initializeWebEngine` 在模拟器 onCreate 阻塞 ~2.1s 是否设备特有 — 官方无耗时数据, 且明确禁止异步线程调用, 无官方异步替代; 只能真机验证或接受。
4. "每个 Web 组件 ~200MB" 在 SINGLE 共享渲染进程下的真实增量 (JS 上下文等) 无官方量化。
5. 预编译 JS 字节码 / 拦截替换 Code Cache 对 `resource://rawfile` 本地 JS 是否生效 — 官方文档限定 HTTP(S)/自定义协议场景, 未验证。
6. 保活组件自身被系统内存回收 (App Memory Deterioration) 后的恢复策略 — 保活组件也会收到 `onRenderExited`, 需要限次重载保活 (faq-stability-23 模式), 具体实现待设计。

## Sources

**官方文档** (devecocli docs, 以 documentId 标识):
- `开发指南/ArkWeb_方舟Web/ArkWeb进程/web_component_process` — 五进程模型, 默认模式, sharedRenderProcessToken, terminateRenderProcess
- `开发指南/ArkWeb_方舟Web/Web组件的生命周期/web-event-sequence` — onControllerAttached/onPageEnd/onRenderExited/aboutToDisappear 定位
- `开发指南/ArkWeb_方舟Web/使用离线Web组件/web-offline-mode` — ~200MB/组件, 每窗口一个 Web, 保活, loadUrl('about:blank') 复用, dispose
- `开发指南/ArkWeb_方舟Web/Web渲染和布局/Web组件渲染模式/web-render-mode` — ASYNC_RENDER 7,680px / SYNC_RENDER 500,000px
- `开发指南/ArkWeb_方舟Web/管理网页加载与浏览记录/加速Web页面的访问/web-predictor` — prepareForPageLoad / prefetchPage
- `最佳实践/性能场景优化案例/Web性能优化/Web加载性能优化/bpta-web-develop-optimization` — 优化全集与量化表, 预启动两黄金约束, nodepool, <200 实例
- `FAQ/Web框架/Web开发_ArkWeb/如何避免多个页面同时触发onRenderExited回调/faqs-arkweb-187` — 默认 SINGLE, 共享进程回调级联
- `FAQ/Web框架/Web开发_ArkWeb/返回的html里包含数学公式_怎么合理渲染到页面/faqs-arkweb-97` — 无原生数学公式组件, WebView 是官方方案
- `FAQ/Web框架/Web开发_ArkWeb/动态创建web组件应该在什么场景下使用_性能如何/faqs-arkweb-52` — 非UI线程创建, 实例建议
- `FAQ/Web框架/Web开发_ArkWeb/Web加载网页性能提升方式与使用场景总结/faqs-arkweb-185` — 优化方式汇总
- `FAQ/技术质量/稳定性/AppFreeze-主线程卡死_THREAD_BLOCK_6S_故障定位/faq-stability-66` — watchdog 机制与定位公式
- `FAQ/技术质量/稳定性/应用启动时长时间白屏后启动失败/faq-stability-33` — 渲染进程退出诊断与恢复
- `FAQ/技术质量/稳定性/应用导入大量图片后卡死/faq-stability-23` — 内存回收型被杀与限次重载
- `API参考/ArkWeb_方舟Web/ArkTS_API/ohos_web_webview_Webview_/Class_WebviewController/arkts-apis-webview-webviewcontroller` — initializeWebEngine/setWebDestroyMode/一控一
- 摘要级引用 (仅搜索摘要, 未全文核对): `faqs-arkweb-140` (高度抖动节流), `faqs-arkweb-56` (onActive), `faqs-arkweb-134`/`faqs-arkweb-62` (setCustomUserAgent 时机)

**SDK d.ts** (`$DEVECO_HOME/default/openharmony/ets/`):
- `api/@ohos.web.webview.d.ts` — RenderProcessMode `:3324`, initializeWebEngine `:3812`, runJavaScript `:4908`, prefetchPage `:5704`, prepareForPageLoad `:5744`, prefetchResource `:6342`, setRenderProcessMode `:6368`
- `component/web.d.ts` — RenderExitReason `:1585`, onRenderExited `:9132`

**项目源码** (相对路径):
- `entry/src/main/ets/entryability/EntryAbility.ets:29-41` — SINGLE + initializeWebEngine 修复及其注释
- `entry/src/main/ets/shared/atoms/MathTextRenderer.ets:44-48` (缓存常量), `:288-333` (三级降级), `:417-424` (clampHeight), `:426-449` (前置降级), `:465-480` (note defer), `:506-538` (降级分支/Web/onPageEnd/onRenderExited)
- `entry/src/main/ets/shared/molecules/FormulaSplitRenderer.ets:30-31` (块上限), `:53-97` (拆分算法), `:235-272` (LazyForEach)
- `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatBubble.ets:29,105` (流式守卫切换点)
- `entry/src/main/resources/rawfile/render.html:217-219` (KaTeX 资源), `:236-308` (render/renderForCache/applyCached/renderFormula 协议)

**故障日志**: appfreeze `THREAD_BLOCK_6S` 20260911113029 (本地文件, 行号引用: :18-19 Reason, :47-51 主线程任务, :136-138 IPC 栈, :967/:1405/:1487/:1625 RenderExited, :969/:1407/:1520/:1627 channel connect timeout, :3167/:3456/:3519 web id, :3651 nwebspawn CPU)
