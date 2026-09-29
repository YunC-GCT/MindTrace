# 021 — Chat 流式增量 Markdown/LaTeX 渲染与持久化降载

> **Status**: proposed + ticket-0 evidence complete (2026-09-13 grill session; §6 defaults frozen from corrected #124 raw evidence; emulator performance follow-up recorded)
> **Source**: [chat Markdown/LaTeX render research](../research/chat-markdown-latex-render-jank-2026-09-13.md) · code fact verification · grill decisions Q1–Q35
> **Related**: [spec 019](./019-reasoning-process-display-p0.md) · [spec 020](./020-reply-body-contract.md) · [ADR-0015](../adr/0015-structured-stream-events.md) · [ADR-0016](../adr/0016-reply-contract-by-transport.md)
> **Official API evidence**: `API参考/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/使用文本/属性字符串_StyledString_MutableStyledString/arkts-styled-string` · `API参考/ArkUI_方舟UI框架/ArkTS组件/文本与输入/属性字符串/ts-universal-styled-string` · `API参考/ArkTS_方舟编程语言/ArkTS_API/ohos_taskpool_启动任务池_/js-apis-taskpool` · `API参考/Core_File_Kit_文件基础服务/ArkTS_API/ohos_file_fs_文件管理_/js-apis-file-fs`

## Problem Statement

MindTrace 的 chat 流式回复目前在 SSE 期间主要以轻量 `Text` 展示，消息完成后才切换到 Markdown/LaTeX 渲染路径。现有 chat 路径将整条消息交给 `MarkdownRenderer` 或 `FormulaSplitRenderer`，导致 finish 时出现整行身份变化、多个 Web 组件集中挂载、页面加载、JavaScript 执行、JSBridge、高度回传和重排叠加的卡顿。

流式期间每个 delta 还会触发消息数组重建、全量列表 reload 和会话快照保存路径。现有 `chatItemKey` 包含正文长度、思考长度和 `streaming`，使同一条消息在追加内容时失去列表身份。现有 `MATH_RENDER_CACHE` 缓存最终 HTML 与高度，但不缓存或复用 Web 实例，不能解决 Web 生命周期成本。

本 spec 的目标不是把 finish 后的全量渲染拆成几批，而是建立真正的增量渲染契约：Markdown 在流式期间实时进入原生文本排版；未闭合公式显示占位；公式闭合后保留原 slot 身份并进入有预算的 ArkWeb 渲染；finish 只关闭剩余 `OpenTail`，不触发全量富文本升级。

## Solution

为每条 chat 消息建立一个 `StreamingReplyDocument` 派生渲染视图。它从原始 Reply Body 增量构建稳定的 `ReplyBlock`，只重新解析仍可变化的 `OpenTail`，对已 `SealedBlock` 生成 patch，不执行整条消息重建。

渲染后端按模型显式声明：普通 Markdown 使用 `StyledString`/`MutableStyledString`，行内公式使用 `CustomSpan` 占位和替换，块级公式使用 ArkWeb slot。所有块级 Web 工作进入通用 `RendererScheduler`，由浮窗实例级 `RenderTick` 按可见性、每帧 Web 数量和工作时间预算调度。

会话历史仍由 `messages` 作为唯一持久化真源。流式保存从 Preferences 快照迁移到应用私有文件，通过官方 `fileIo.AtomicFile` 在异步任务中提交完整 JSON 快照。迁移成功后不双写，旧 Preferences 只读保留。

## User Stories

1. 作为学生，我希望 SSE 输出期间立即看到标题、列表、粗体、斜体和行内代码排版，而不是等待回复完成。
2. 作为学生，我希望未闭合的块级公式显示灰色 LaTeX 或“公式生成中”，而不是空白或破碎的公式。
3. 作为学生，我希望块级公式闭合后原地替换为渲染结果，而不是整条消息消失后重建。
4. 作为学生，我希望未闭合行内公式保留稳定的占位宽度，不因每个 token 到达而反复改变整行布局。
5. 作为学生，我希望公式渲染完成后只发生必要的局部高度变化，不被整条消息跳回底部。
6. 作为学生，我希望主动上滑查看历史时，流式消息和公式高度变化不会强制把我拉回底部。
7. 作为学生，我希望仍在底部时新内容和高度变化能渐进贴底，避免停在消息中间。
8. 作为学生，我希望回复完成时不会再次全量 Markdown/LaTeX 重渲染。
9. 作为学生，我希望历史会话重开后与流式结束后的 Reply Body 保持一致。
10. 作为学生，我希望持久化失败不会损坏上一份可读取的聊天历史。
11. 作为学生，我希望应用被后台回收时，最近已完成的消息和关键生命周期边界已经保存。
12. 作为维护者，我希望同一消息在流式期间具有稳定的外层列表身份，以便内容更新不会销毁整个消息行。
13. 作为维护者，我希望每个 ReplyBlock 有稳定的源文本身份，而不是依赖数组序号。
14. 作为维护者，我希望已 sealed 的块不再被重复解析，长尾只处理新增的 dirty range。
15. 作为维护者，我希望列表增量更新使用行级 IDataSource 通知，而不是 `onDataReloaded()`。
16. 作为维护者，我希望 Web 创建和注入受到单帧数量与时间预算双重限制。
17. 作为维护者，我希望可见区域和距离视口一屏内的公式优先，远端内容不提前制造 Web 工作。
18. 作为维护者，我希望 RendererScheduler 不依赖 chat 的消息、块或持久化模型。
19. 作为维护者，我希望 Document 与 AgentFloatWindow 生命周期绑定，不存在全局渲染文档单例。
20. 作为维护者，我希望 chat 新模型和 NoteDetail 旧模型的缓存语义明确隔离。
21. 作为维护者，我希望 ArkWeb 引擎预热是共享的 L2 能力，但不会把 chat 的 L1/L3 缓存或实例策略泄漏到 NoteDetail。
22. 作为维护者，我希望 KaTeX 输出模式默认保留 `htmlAndMathml`，不会因为性能实验而偷偷改变产品无障碍语义。
23. 作为维护者，我希望 HTML-only 是否启用按产品级 EAA/Section 508 合规判定，而不是按 chat profile 局部豁免。
24. 作为维护者，我希望每个保存请求都有明确的失败回传、重试和错误记录策略。
25. 作为维护者，我希望旧 Preferences 迁移失败时可以下次重试，而不会删除旧数据。
26. 作为测试维护者，我希望 ticket-0 先验证 ArkUI、TaskPool、文件路径和性能采集前提，再允许后续实施。
27. 作为测试维护者，我希望性能 fixture、计时起点、可见定义、p50/p95 样本量和长帧规则固定且可复现。
28. 作为项目维护者，我希望后续 NoteDetail 渲染优化可以复用通用调度机制，但不复用 chat 的 Document 状态。

## Implementation Decisions

### 1. Scope and migration gate

- 首轮只改 `AgentFloatWindow` chat 路径；NoteDetail 继续使用现有 `MarkdownRenderer`/`FormulaSplitRenderer`。
- `RendererScheduler` 与 `RenderTick` 是不带 chat 语义的通用机制；`StreamingReplyDocument`、`OpenTail`、`SealedBlock`、chat 的 `GeometryChanged` 语义属于 entry chat 专属层。
- L2 ArkWeb 引擎预热/渲染进程能力对 chat 与 NoteDetail 共享；L1 内容缓存和 L3 Web 实例/slot 策略按链路隔离。
- ticket-0 全部通过后才允许实施 ticket-1~4。ticket-0 失败时不接入新 chat 路径、不移除旧 chat 调用、不删除旧 Preferences 读写、不做部分迁移。
- 旧 chat 对 `MarkdownRenderer`/`FormulaSplitRenderer` 的调用在 ticket-4 完成并验收通过时移除，而不是 ticket-0 后立即移除。旧渲染器继续服务 NoteDetail。
- 当前架构假设只有一个 `AgentFloatWindow` 实例。若开发构建发现第二个实例被创建，应断言失败；多实例并发持久化和跨浮窗几何事件不在本 spec 范围。

### 2. StreamingReplyDocument contract

- `StreamingReplyDocument` 是 chat 渲染层唯一公共模型；`StreamingBlockStore` 不作为第二个公共概念出现，可作为内部实现名或直接合并。
- Document 是渲染派生视图，不是真源，不参与 `ChatSessionManager` 保存。`messages` 仍是唯一持久化真源；历史消息可从 `messages` 重建 Document。
- Document 持有稳定的 `ReplyBlock` 索引、当前 `OpenTail` 引用和 `FinalizedMessage`/几何事件订阅关系。
- 外部增量接口是 `applyDelta(delta: string): BlockPatch[]`，禁止提供 `setAll(text)` 作为 chat 生产入口，禁止以全量字符串替换代替 patch。
- block 身份为 `String(messageId) + '#' + startOffset`。`messageId` 当前为 `number`；`startOffset` 是原始 Reply Body 的 UTF-16 code-unit 起点，在块首次创建时确定且之后不变。
- `startOffset` 必须来自 raw Reply Body 的扫描，不得来自规范化文本、渲染 HTML、渲染后文本、字节偏移或可变数组序号。开发构建中应校验 block ID 对应的 raw 片段范围。
- 该身份保证只适用于当前消息 append-only、不可编辑的生命周期。未来消息编辑必须换 message ID，或另行设计编辑后的身份映射，不由本 spec 猜测。
- `ReplyBlock` 显式声明渲染后端：`TextBlock → StyledString`、`InlineFormulaBlock → CustomSpan`、`BlockFormulaBlock → ArkWeb slot`。渲染层不得从模糊 `kind` 推断后端。

### 3. Block lifecycle and incremental parser

- 生命周期为 `OpenTail → SealedBlock → FinalizedMessage`。`FinalizedMessage` 表示不再有新 delta 且剩余 tail 已关闭，不表示所有 Web 工作完成。
- `OpenTail` 保留固定 `startOffset`，并维护 `stablePrefixLen`。每个 delta 只扫描 `[stablePrefixLen, end)` 的新增/未稳定区域；已确认不会改变的前缀不重复解析。
- 已 sealed block 不重新解析。块级公式闭合后立即产生 stable formula slot，slot 的渲染状态可以从 placeholder 变为 rendered，但 blockId/formulaSlotId 不变。
- seal 触发条件必须逐条实现：空行且无未闭合 inline marker；单行标题且不是续行；列表项且不是续行；fenced code 闭合；块级公式闭合。`inCodeFence`/`inInlineCode` 时，任何空行或公式触发条件都无效。
- `**`、反引号和 `$` 等未闭合 inline marker 阻止相关文本块 sealed。代码上下文内的 marker 不参与 seal 判定。
- 块级公式未闭合时产生 placeholder block；闭合瞬间复用同一 slot 入队 Web 渲染。
- `FinalizedMessage` 之后允许继续产生 `GeometryChanged`；只有消息已 finalized、Scheduler 队列为空且所有块具有有效 rendered height 时，才将 `allBlocksSettled` 置为 true。

### 4. Raw source and per-block normalization

- parser 直接扫描原始 Reply Body；规范化按块类型作用于渲染输入副本，不写回 rawBody，不参与 offset 计算。
- 规范化规则必须按块类型列出，不允许全局规范化后再以例外修补：

| Block | 渲染副本规则 |
|---|---|
| Paragraph | 处理协议允许的换行与转义；保留可识别的 inline marker 供 StyledString 分段 |
| Heading | 剥离标题结构标记，处理协议允许的转义和 inline marker |
| List | 剥离列表结构标记，保留列表层级与顺序信息，处理项目内 inline marker |
| Quote | 剥离引用前缀后按段落规则处理内容 |
| FormulaBlock / InlineFormulaBlock | 复用 ContentProtocol 的公式边界和已确认 LaTeX 修正规则，仅作用于渲染副本 |
| CodeBlock | 规范化规则为空集；原始换行、制表、反斜杠和代码内容必须原样保留 |
| Unsupported/fallback | 走唯一的转义纯文本投影；Markdown 标记作为字面量显示，不直接喂 raw HTML 或 WebView |

- 首轮基线语法为 MM-MD-v1/现有 `MarkdownBlock`：H1–H3、段落、引用、有序/无序列表、fenced code、分隔线、粗体、斜体、行内代码、已协议化公式定界符。
- 表格、链接、图片、删除线、HTML 和未知语法首轮不扩展；统一转义为纯文本 fallback。fallback 不是 TextBlock 内的另一种半渲染状态。
- 普通正文禁止 WebView。任何正文语法风险导致 WebView fallback 都是 bug；只有块级公式可以进入 ArkWeb slot。

### 5. Native Markdown and formula placeholders

- 普通文本块使用 `StyledString`/`MutableStyledString`；粗体、斜体和行内代码使用 style span，不创建每个 span 一个 Text 子组件。
- 行内公式第一次进入 `InlineFormulaBlock` 时按当前已知内容估算一次 CustomSpan 宽度；后续 delta 追加不改变占位宽度，直到公式闭合。
- CustomSpan 状态更新使用同一实例的内容/尺寸状态和 `invalidate()`；不得为每个 token 替换整条 Text 组件。
- 未闭合块级公式显示灰色原始 LaTeX 和弱提示“公式生成中”，显示长度受 `FORMULA_PLACEHOLDER_MAX_CHARS` 配置限制，默认值由 ticket-0 固化。
- 块级公式实际高度与占位高度不同允许造成局部后续内容位移，但不允许改变 messageId、blockId 或 slot 身份。高度变化必须进入 Document 的合并事件通道。
- 当前 API 24 可用 StyledString、MutableStyledString、CustomSpan 的测量/绘制/invalidate；API 26 的 `PARAGRAPH_CACHE` 和 CustomSpan `maxWidth/layoutPolicy` 不作为当前基线能力。

### 6. RendererScheduler and RenderTick

- `RendererScheduler` 只接收纯数据任务，例如 blockId、raw formula text、slot hint 和完成回调；Scheduler 不持有 Document，不读取 messages，不依赖 `messageId`、`OpenTail` 或 chat profile。
- Document 将新 sealed 的 block 任务注入 Scheduler；Scheduler 完成 Web 创建、HTML 注入或高度回传后，以 `onBlockHeightChanged(blockId, height)` 回调 Document。
- `maxWebCreatesPerFrame` 是硬数量上限，在每个 Web 工作单元创建前检查；达到上限后本帧不再创建。
- `maxWebWorkMsPerFrame` 是软时间预算，每个 Web 工作单元结束后累加耗时并检查；超出后本帧剩余任务顺延。不能只在循环开始检查一次。
- 任务优先级为视口内，其次距视口不超过一屏；更远 block 延迟到进入前一屏再调度。可见优先与预算限制是两条独立规则。
- 两个预算的最终默认值在 ticket-0 真机测量后固化；ticket-0 后不得被后续 ticket 随意修改。固化落点为 [ADR-0017](../adr/0017-renderer-scheduler-budget-baseline.md)，推导规则可复算：
  - `perCreateWorkMs` = 每个 Web 工作单元从创建（进入 Web 渲染决策）到首次真实高度回传应用的实测耗时样本集。
  - `maxWebCreatesPerFrame = clamp(floor(32 / median(perCreateWorkMs)), 1, 4)`
  - `maxWebWorkMsPerFrame = clamp(round(p75(perCreateWorkMs)), 1, 16)`
  - 数值状态（post-code-review corrected evidence）：基于 `spec/ticket-0-6-chat-render-fixtures-budgets/raw/` 中 A/B/C/C′ 4×20 JSONL 原始行，直接 `webWorkDurationSamplesMs` 样本 `n=16`，median=150ms，p75=426ms → `maxWebCreatesPerFrame=1`、`maxWebWorkMsPerFrame=16`。percentile 用 nearest-rank（`ceil(p/100 * n)`），clamp 上下界为冻结常量。证据基线交付状态为 `PASS_WITH_EMULATOR_PERFORMANCE_FOLLOW_UP`；`T_finishToStable` p95: B=554ms、C=2649ms、C′=687ms > 500ms，且 B 连续长帧 13/20，均作为 DevEco 模拟器上的性能跟进项记录，不否定本 ticket 的证据交付。任何最终数值修改需新设备证据。
- `RenderTick` 是通用、浮窗实例级的 50ms 节拍源，唯一常量为 `TICK_MS = 50`，使用 `setInterval`。
- RenderTick 按需启动：第一个 pending 事件入队时启动计时器，不同步执行；tick 触发后派发本 tick pending，检查 pending 为空后暂停。暂停保留实例、引用和订阅，下一次入队复用；`aboutToDisappear` 才是 dispose，清空 pending、断开订阅、释放 timer，dispose 后入队为 no-op 或开发态断言。
- `show=false` 只暂停 RenderTick，不销毁 Document；停止前先按订阅者有效性 flush pending。若 List 已销毁，只更新 Document 状态，不回调失效组件。
- 每个浮窗实例各自拥有 RenderTick；当前产品只支持单实例，第二实例开发态断言失败。

### 7. RenderTick event order and geometry

- 单个 tick 的固定顺序为：数据通知 → 几何事件 → 滚动贴底。数据通知、几何合并和滚动逻辑不得各自创建独立的 50ms timer。
- Document 是块高度的唯一持有者。Scheduler 不合并高度回调；每个块完成后立即回调，Document 负责唯一的 50ms 几何合并，避免两层合并叠加。
- chat `GeometryChanged` 首轮结构为 `messageId: number`、`totalHeightDelta: number`、`ts: number`，`totalHeightDelta` 为有符号权威值。`blocks?: Array<{ blockId: string, delta: number }>` 保留为 `@since v2` 扩展，首轮永远不构造、不测试。
- 若未来输出 `blocks`，必须满足明细 delta 之和等于 `totalHeightDelta`；首轮因不输出 blocks，不构造明细数组。
- 每个块的 `currentKnownHeight` 初始为进入 Scheduler 时的 estimateHeight；渲染完成后更新为真实高度；未占位块视为 0。`delta = newHeight - currentKnownHeight`，Document 更新 renderedHeight 后才进入合并。
- `AgentMessageList` 在 aboutToAppear 订阅 Document，在 aboutToDisappear 对称退订。Document 在 AgentFloatWindow 创建并通过稳定组件输入传递给 List，不使用全局 Document 单例。
- List 根据 `isAtBottom` 状态消费三类信号：行级数据变化、GeometryChanged、allBlocksSettled。用户主动上滑后暂停自动贴底；回到底部后恢复。贴底处理渐进调整，不把每次几何变化粗暴变成整列表跳变。

### 8. Message identity and IDataSource updates

- `chatItemKey` 只返回 `messageId`，不包含 `streaming`、`content.length` 或 `reasoning.length`。这是对早期 `id + streaming` 建议的明确推翻。
- ChatBubble 保持同一个 struct，通过内部 `if/else` 切换流式 Document 与 finalized 状态；不得将两条路径拆成会随状态切换而替换外层消息项的独立自定义组件。
- ticket-0 必须先验证 key 不变时 `@Prop` 内容变化能够驱动 ChatBubble/Text 更新。若失败，回退 `id + streaming` 仅作为重新评估的临时分支，不视为本 spec 已完成。
- `AgentMessageList` 继续使用 LazyForEach，但流式 delta 禁止 `onDataReloaded()`，改为按稳定 index 的 `onDataChange(index)`；新消息使用 `onDataAdd(index)`，删除使用 `onDataDelete(index)`。
- 数据通知默认以 `TICK_MS` 合并，不按每个 delta 通知。当前流式消息位于数组尾部；若未来支持中途插入，必须先更新 index 映射或引入基于 key 的通知，不得静默使用旧 index。
- 滚动不再依赖全量 reload；数据变化、几何变化和 allBlocksSettled 是独立驱动源。

### 9. ArkWeb cache, warmup and KaTeX output

- 新 chat 模型首轮不复用旧 `MATH_RENDER_CACHE`；旧缓存语义仍归 NoteDetail/旧渲染链路。若未来引入 stream cache，必须使用独立版本命名空间，例如 `stream:v1`，不得混用旧 encoded HTML 条目。
- 当前 L2 引擎预热是全局共享修复项：恢复/验证官方支持的 ArkWeb 初始化和渲染进程配置，但不得猜测不存在于当前 SDK 的 API。EntryAbility 当前无相关调用，ticket-0 负责编译和真机验证。
- L1 内容缓存与 L3 Web 实例/slot 池按 chat/NoteDetail 隔离；首轮不接入 `WebKeepAlive` 或离线 Web 组件池。
- KaTeX output 纳入配置化和对照测量，默认保持 `htmlAndMathml`。HTML-only 只有在产品级 EAA/Section 508 合规判定允许后，才可通过 flag 启用；实验数据只进入 ADR Evidence，不是启用依据；不得按 chat profile 单独豁免。

### 10. Chat history persistence

- 新基准文件为应用私有 `filesDir/chat-history/sessions.json`；临时写入由官方 `fileIo.AtomicFile` 内部管理，业务层不指定、不读取、不清理、不重命名内部临时文件。
- 快照 JSON 保留现有会话结构并增加 `schemaVersion`，迁移成功的快照包含 `migratedFrom: "preferences"`。快照必须是纯数据对象；TaskPool/Worker 不传递函数、闭包、UI 状态代理、组件实例或 Context。
- UI 线程只做 immutable plain snapshot 转换和入队；JSON stringify、AtomicFile 写入和提交在 TaskPool 中执行，TaskPool 不可用时降级 Worker；二者都不可用时阻塞，不得回退 UI 线程同步写盘。
- TaskPool 任务参数和返回值遵守官方序列化类型及单次数据量限制；worker 写失败必须通过 Promise rejection 或 Worker 请求响应协议回传阶段、错误码和版本。
- 所有保存请求进入一个 FIFO 单写入者队列，合并窗口内只提交最新完整快照。500ms 默认值由 `STREAM_SAVE_THROTTLE_MS` 配置常量控制，仅影响 SSE delta 保存。
- 强制提交边界包括：`finishAiMsg`、`show=false`、前台转后台、`aboutToDisappear`、切换会话、取消/切换当前流式消息、新建会话、删除会话、切换到相机浮层。强制提交绕过 500ms 节流。
- `finishAiMsg` 后即使 Web 仍排队，保存的是 `messages` 的 Reply Body 真源，不是 Document 状态。
- 启动读取分为三态：新文件不存在时读取旧 Preferences 并迁移；新文件存在且 schema/结构有效时只读新文件；新文件存在但损坏时不 fallback 旧 Preferences，保留损坏正式文件、记录错误并使用可恢复的内存错误路径。
- 迁移顺序为读旧 Preferences → 生成带 schemaVersion 的新快照 → AtomicFile 写入并验证 → 新文件成为唯一读取源。迁移写入失败时调用 `failWrite()`，保留旧 Preferences，下一次启动重试；迁移成功后不再双写，旧 Preferences 只读保留。
- AtomicFile 失败阶段固定为 `PREPARE`、`WRITE`、`COMMIT`、`VERIFY`。失败调用 `failWrite()`，保留上一份正式快照，不保留包含聊天内容的临时文件。日志只记录阶段、错误码、schemaVersion 和时间戳，不记录快照内容。
- 连续保存失败记录并重试；达到产品配置的连续失败次数后向上层报告可恢复持久化错误。进程 crash/系统强杀无回调可接，接受最多丢失未完成 500ms 窗口增量的取舍，不承诺零丢失。
- `filesDir` 获取失败时阻塞存储 ticket，走 EntryAbility → AppStorage/单例 → AgentFloatWindow 的 context 注入；禁止回退 Preferences。

### 11. KaTeX and accessibility decision

- 首轮不改变默认 MathML 输出语义。
- output flag 的粒度可以是渲染配置，但是否启用的决策粒度是产品发布市场；chat 公式同样属于产品内容，不能以 profile 规避无障碍要求。
- 如果合规判定不允许 HTML-only，保留 `htmlAndMathml`，即使实验显示 DOM/耗时收益；如果合规判定允许，才由独立 ADR 根据 Evidence 决定是否启用 flag。

### 12. Ticket-0 hard gate and failure branches

ticket-0 是生产实现前置验证，不是可选 benchmark。至少验证：

1. 稳定 `chatItemKey` 下 `@Prop` 内容 diff 可刷新；
2. 当前 AgentFloatWindow 可获得正确 `filesDir`，必要时完成 context 注入；
3. TaskPool 纯数据传输、`@Concurrent` 任务、Promise 结果和失败回传；Worker fallback 的构建接线和消息错误回传；
4. CustomSpan 占位的测量、绘制、`invalidate()` 更新和高度变化；
5. A/B/C/C′ fixture、统一可见定义、指标采集和真机重复运行；
6. RendererScheduler 的 Web 数量/时间预算在目标设备上的默认值。

失败分支必须是子 ticket 级，不阻塞不相关子 ticket；DevEco 模拟器上的性能目标偏差应记录为后续性能跟进，不应伪装成达标，也不应否定已经完成的 ticket-0 证据链：

| 失败项 | 动作 |
|---|---|
| `@Prop` diff 失败 | 临时回退 `id + streaming`，重新评估列表重建代价；Q24 不算完成 |
| `filesDir` 不可得 | 阻塞存储子 ticket，完成 context 注入；不回退 Preferences |
| TaskPool/Worker 都不可用 | 阻塞异步存储子 ticket；不回退 UI 线程写盘 |
| CustomSpan 占位更新失败 | 回到三态渲染契约重新设计；不退化为 finish-only |
| 性能采集不可复现 | ticket-0 不通过，先修 fixture/指标定义；不凭主观“无明显掉帧”放行 |
| DevEco 模拟器 `T_finishToStable` p95 超过初始目标 | 记录 `NOT_MET_ON_DEVECO_EMULATOR`，保留原始数据并转为后续 RendererScheduler 性能跟进；不降低目标，不将证据交付误报为性能达标 |

## Testing Decisions

测试只断言外部行为和稳定 seam，不把 `blocks` v2 明细、私有 Map 或具体定时器实现作为首轮行为测试目标。

### ticket-0 fixtures and metrics

- A：短 Markdown、无公式。
- B：与 A 纯文本字符数相同或按固定比例控制，少量公式。
- C：与 A/B 纯文本字符数相同，多公式。
- C′：C 的连续闭合公式变体，用于同一调度窗口的压力测试。
- 每组至少重复 20 次，在同一真机采集 p50/p95；记录 steady memory（finish 后 30 秒）而非只记录瞬时峰值。
- `visible` 统一定义为：block 已完成渲染、已进入视口、且高度回传已应用（`renderedHeight > 0`）。
- `T_firstDeltaToVisible`：首个公式可见时刻减去 SSE 首个 delta 到达时刻；p95 超过 1.5s 作为观测告警线，不阻塞 ticket 验收；用户最终可接受阈值待产品确认。
- `T_sealedToVisible`：公式 sealed 时刻到该公式满足 visible 定义的时刻；100ms 是初始建议值，ticket-0 采基线后固化。若基线已超过 100ms，ticket-0 不通过，不通过降低阈值解决。
- `T_finishToStable`：finish 事件到视口及前一屏所有 block 终态且之后 500ms 无高度变化；p95 初始性能目标 500ms。DevEco 模拟器未达到该目标时记录性能跟进，不否定已完成的 benchmark 证据交付；目标本身不降低。
- 首个 500ms 窗口内长帧定义为帧耗时 `>32ms`；数量门槛在 ticket-0 后固化，但不得连续出现两帧长帧，该视觉连续性约束直接冻结。
- 额外记录 delta 更新耗时、行级通知次数、Web 创建数、每块高度更新次数、首屏稳定时间、finish 稳定时间和错误降级次数。

### Unit and structure tests

- `StreamingReplyDocument`：只追加 delta、OpenTail/stablePrefixLen 推进、seal 条件、代码上下文短路、公式 slot 身份、UTF-16 offset、finalized 后继续 GeometryChanged。
- Native Markdown projection：支持矩阵、inline style、代码块原样、fallback 转义纯文本、ContentProtocol 只作用渲染副本。
- CustomSpan seam：一次估算宽度、闭合替换、invalidate 后内容/尺寸刷新；不测试完整 LaTeX 排版，因为 CustomSpan 不提供 LaTeX 引擎。
- RendererScheduler：可见优先、距离一屏优先、数量硬上限、时间预算后置检查、队列顺序、单层高度回调。
- RenderTick：pending 才启动、首 tick 延迟、tick 后空队列暂停、show=false 暂停、dispose 释放、单一 50ms 顺序。
- IDataSource：delta 用 `onDataChange(index)`，新消息用 `onDataAdd`，删除用 `onDataDelete`，chat 路径不调用 `onDataReloaded`；首轮不测试 `blocks` 明细。
- Persistence：schemaVersion、迁移三态、AtomicFile finish/fail 分支、单写入者合并、强制保存边界、失败重试、日志不含聊天正文。
- `ChatMsg` key：messageId 变化、内容变化 key 不变、streaming 翻转 key 不变；若 ticket-0 失败则保留回退分支测试。

### Device acceptance

- 在目标真机运行四组 fixture，采集性能指标和 ArkUI/ArkWeb trace。
- 验证 SSE 期间标题、列表、粗体、行内代码实时显示；未闭合公式占位；闭合公式按 slot 原地替换。
- 验证用户上滑时不自动贴底、回到底部后恢复渐进贴底。
- 验证 finish 后仍有排队 Web 工作时，后续 GeometryChanged 不破坏列表身份和最终贴底。
- 验证 chat 流式期间打开 NoteDetail，NoteDetail 旧渲染链路不回退；chat/NoteDetail 分开采集并增加交叉场景。
- 验证关闭浮窗、切相机、前后台切换、切会话、新建/删除、取消流式均触发保存边界；验证异常保存不损坏上一快照。
- 验证旧 Preferences 迁移：新文件不存在时迁移；迁移失败重试；新文件有效时不读旧 Preferences；新文件损坏时不回退旧数据。

## Phasing

| Ticket | Scope | Gate |
|---|---|---|
| 0 | 真机前提验证、fixture、指标、ArkUI/TaskPool/AtomicFile/context 能力 | 全部硬门禁通过后解锁后续 ticket |
| 1 | 通用 RendererScheduler、RenderTick、预算与 L2 预热验证 | 不引入 chat Document |
| 2 | StreamingReplyDocument、raw parser、block 生命周期、native Markdown/公式 placeholder | 纯逻辑测试先红后绿 |
| 3 | chat ChatBubble/MessageList 接入、key、IDataSource、GeometryChanged、滚动契约 | ticket-0 已通过 |
| 4 | chat 旧渲染调用移除、KaTeX output 配置化、chat cache 隔离、真机交叉验收 | ticket-3 行为稳定 |
| 5 | ChatSession 文件快照、TaskPool/Worker、AtomicFile、Preferences 迁移与生命周期 flush | 独立存储子 ticket，可与 2/3 并行但不得切换半成品 |

ticket-4 完成并验收后，chat 路径才删除旧 `MarkdownRenderer`/`FormulaSplitRenderer` 调用。NoteDetail 不在本 spec 内切换。

## Acceptance Criteria

- [ ] SSE 期间原生 Markdown 结构实时更新，不等待 finish。
- [ ] 未闭合块级公式显示受限占位，闭合后复用 slot 身份进入 Web 调度。
- [ ] 行内公式使用一次估算宽度的 CustomSpan，占位更新不随每个 delta 改宽度。
- [ ] finish 不触发全量富文本重渲染；FinalizedMessage 后可继续 GeometryChanged，allBlocksSettled 后才最终贴底。
- [ ] `StreamingReplyDocument` 是 chat 唯一渲染模型；messages 是唯一持久化真源。
- [ ] blockId 使用 raw Reply Body UTF-16 startOffset；已 sealed block 不重解析。
- [ ] chat `chatItemKey` 只依赖 messageId，ticket-0 验证 `@Prop` diff 通过。
- [ ] chat delta 不调用 `onDataReloaded()`；使用固定 tick 合并的行级通知。
- [ ] RendererScheduler 同时满足可见优先、数量硬预算、时间软预算；预算值由 ticket-0 固化。
- [ ] GeometryChanged 首轮只输出 messageId、signed totalHeightDelta、ts；`blocks` 保留但不构造、不测试。
- [ ] RenderTick 按需启动、show=false 暂停、aboutToDisappear dispose，事件顺序固定为数据→几何→滚动。
- [ ] chat/NoteDetail 的 L1/L3 渲染模型隔离，L2 引擎预热共享；交叉场景 NoteDetail 无回退。
- [ ] KaTeX 默认 `htmlAndMathml`；HTML-only 仅在产品级合规判定允许后经 flag 启用。
- [ ] ChatSession 通过异步 TaskPool/Worker 和官方 AtomicFile 保存；失败保留正式快照并调用 failWrite，不在日志中记录正文。
- [ ] Preferences 迁移区分不存在、有效、损坏和迁移中失败；迁移成功后不双写，损坏新文件不 fallback 旧数据。
- [ ] 所有强制保存边界和最多丢失 500ms 窗口的取舍有测试/真机证据。
- [ ] A/B/C/C′ fixture 每组至少 20 次；p50/p95、visible 定义、稳定定义和长帧规则可复现。
- [ ] ticket-0 未通过时未切换 chat 新路径、未删除旧 chat 调用、未删除旧 Preferences 读写。
- [ ] full ArkTS check、项目 lint、Node tests、naming-lint、diff check 和完整 build 通过。

## Out of Scope

- 首轮 NoteDetail 增量渲染；它后续使用独立 spec 和专属 Document 状态。
- WebKeepAlive、离线 Web 组件池和 L3 Web 实例池；仅在 P1 绝对门槛不达标时触发后续评估。
- API 26 `PARAGRAPH_CACHE`、CustomSpan `maxWidth/layoutPolicy` 或其他超出 API 24 基线的能力。
- 默认切换 KaTeX 到 HTML-only；无障碍合规判定前不裁剪 MathML。
- Markdown 表格、链接、图片、删除线、HTML 和未知语法的首轮原生支持。
- 通过 WebView 渲染非公式正文的 fallback。
- 多浮窗实例、跨浮窗 Document/GeometryChanged、跨进程聊天快照并发。
- 将 StreamingReplyDocument 变成持久化真源，或把 Document 状态写入 ChatSession 快照。
- RDB 迁移；本 spec 选择文件快照，未来若历史查询规模要求再单独设计。
- 进程 crash/系统强杀时的零丢失保证；接受最多丢失未完成保存窗口的增量。

## Rejected Alternatives

- **finish 后纯文本升级为富文本**：违反用户的实时 Markdown/公式契约。
- **继续每个 delta 全量解析/全量 reload**：不能满足稳定 block、单帧预算和增量更新目标。
- **`StreamingBlockStore` 与 `StreamingReplyDocument` 并列公共模型**：造成两套命名和职责边界。
- **新 chat 复用旧 `MATH_RENDER_CACHE`**：旧缓存含 encoded HTML + height，与新 Web-side HTML/slot 协议语义不同。
- **chat profile 单独启用 HTML-only**：无障碍合规按产品/发布市场判定，不按 profile 豁免。
- **普通 rename 替代 AtomicFile**：官方没有为普通 rename 给出同文件系统崩溃原子性保证；API 24 可用的 `fileIo.AtomicFile` 已提供官方提交/回滚语义。
- **业务层保留 AtomicFile 内部临时文件**：临时内容可能含完整聊天正文，诊断价值低于敏感数据残留风险；失败使用 `failWrite()` 回滚并删除临时写入。
- **保存失败退回 UI 线程同步写盘**：会把持久化卡顿重新引入渲染主线程。
- **新文件损坏 fallback 到旧 Preferences**：可能把新版本历史静默回退为旧快照，造成数据丢失。
- **全局 Document/全局 RenderTick**：与浮窗生命周期和单实例持久化边界冲突。
- **额外 NotificationBus**：Document→List 的局部订阅足够，增加总线会扩大状态传播面。

## Further Notes

- 当前 `MarkdownRenderer`/`FormulaSplitRenderer` 仍服务 NoteDetail；本 spec 对 spec 020 的影响仅限 chat 渲染入口，Reply Body、StreamEvent 和 ContentProtocol 契约继续有效。
- `MarkdownParser`、`MathTextParser` 和 ContentProtocol 提供可复用的边界规则，但当前没有增量 cursor、dirty range 或稳定 block ID；ticket-2 必须新增这些能力，而不是把完整解析器包一层 `progressive` 延迟。
- 官方 `StyledString`/`CustomSpan` 适合 native Markdown 和行内占位，但不是 LaTeX 排版引擎；块级公式仍依赖 ArkWeb，官方 FAQ `faqs-arkweb-97` 也未提供专用原生数学公式组件。
- 官方 `TaskPool` document `API参考/ArkTS_方舟编程语言/ArkTS_API/ohos_taskpool_启动任务池_/js-apis-taskpool` 在 API 24 可用，任务参数需是可序列化纯数据，`@Concurrent` 任务结果可通过 Promise 回传；Worker 作为构建接线后的降级路径。
- 官方 `@ohos.file.fs` document `js-apis-file-fs` 的 `AtomicFile15+` 明确提供 `startWrite`、`finishWrite`、`failWrite`，当前 API 24 可用。普通 `fileIo.rename` 的通用崩溃原子性不作为本方案依据。
- ticket-0 的性能数据是方案门槛，不允许用“相对基线改善”或“无明显掉帧”替代绝对、可复现的指标。
- P2 触发规则：若 P1 验收后 `T_sealedToVisible`、`T_finishToStable` 或长帧绝对门槛不达标，才评估 WebKeepAlive/离线 Web 组件池；若达标，P2 永久搁置，不为架构完整而做。
