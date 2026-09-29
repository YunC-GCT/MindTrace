# AgentFloatWindow 组件清点与替换候选调研 — 2026-09-11

> **Date:** 2026-09-11
> **Scope:** `entry/src/main/ets/overlays/AgentFloatWindow/` 全部 .ets 文件的组件清点 + 死组件检测 + 容器职责拆解 + 鸿蒙官方替换候选 + React 生态对照 — 只读调研, 不改任何代码
> **Project:** MindTrace (`entry` module)
> **Status (2026-09-17):** `[obsolete]` `QuickSuggestions` 组件已删除;本文对 QuickSuggestions 的引用 (4 个推荐 chip) 不再反映当前实现。
> **Author:** 研究后台 agent (只读代码 + `devecocli docs` 本地官方文档库检索)

---

**TL;DR:** AgentFloatWindow 目录共 **11 个 .ets / 1124 行**, 全部 import 有渲染点、**零全死/零半死组件**; 但有 3 处**局部死**: ① `renderKey` state 只写不读 (AgentFloatWindow.ets:54,91), ② `promptAction` 死 import (AgentFloatWindow.ets:15), ③ "深度思考" 开关是**装饰性控件** — 只改颜色、从不影响请求 (实际思考模式在 ReplyService.ets:54,81,123 硬编码 `enableThinking: false`)。浮窗实现方式判定: **应用内 Stack overlay (自绘底部 sheet), 非真子窗口** — `@ohos.window` 仅用于监听键盘高度 (AgentFloatWindow.ets:97-101)。替换最优解不是"换组件"而是"收口到官方半模态 **bindSheet**"(内建手势/多档高度/键盘避让, 可删掉约 60 行手写动画+键盘位移代码); 消息列表已是 List+LazyForEach, 距官方最佳实践只差 `@Reusable` 复用一步; SessionBar/QuickSuggestions 与官方 **Chip** (API 11+) 语义几乎一一对应。另: 任务简报所称 "AgentFloatWindow 使用 AppStorage 'notesVersion' 手工事件总线" **已过时** — 当前浮窗 0 处引用 notesVersion。

## Question

1. AgentFloatWindow 目录下每个 .ets 文件的精确清单: 行数 / struct 职责 / 状态字段 / import 依赖 / 消费方 / 值得注意的方法?
2. 死组件检测: 每个组件是全死 / 半死 / 局部死 / 活? 每条结论需 file:line 证据; 目录内是否有未引用的资源/常量?
3. 容器 AgentFloatWindow 持有哪些职责? 哪些是业务 (必须保留)、哪些是纯 UI (可随替换丢弃)? 浮窗是应用内 overlay 还是真子窗口?
4. 每个 UI 角色的鸿蒙官方替换候选 (component + documentId + 能力 + 适配度)?
5. 每个组件角色的 React 生态概念参照 (明确标注非鸿蒙 API)?

## Method

- 通读 `entry/src/main/ets/overlays/AgentFloatWindow/` 全部 11 个 .ets (含 `chat/` 子目录), 逐文件记录行数/状态字段/import/build 结构。
- 全仓 grep (`entry/src/main/ets/`, 扩展名 `*.ets`) 每个 struct 的 import 与渲染点, 建立消费映射; 对 `renderKey` / `deepThink` / `promptAction` / `notesVersion` / AgentChatService 各方法名做专项 grep。
- 读服务 seam (`services/AgentChatService.ets`, `services/ReplyService.ets`, `services/OverlayService.ets`, `services/ChatStatusMachine.ets`) 与 workflow (`workflows/conversation/ConversationState.ets`, `ConversationWorkflow.ets`) 验证容器职责与接线完整性; 追到 `common/src/main/ets/llm/` (LlmClient/LlmTypes) 确认思考模式参数链。
- 与 2026-09-06 审计快照 ([frontend-component-audit-2026-09-06.md](./frontend-component-audit-2026-09-06.md) §6) 逐条核对, 标注漂移。
- 鸿蒙候选: `devecocli docs search <关键词>` 检索本地官方文档库, 只采信命中文档 (记录 documentId); React 对照为概念参照, 标注 "生态参照"。
- 行数口径: 文件物理行数 (含空行, 与编辑器一致); PowerShell `Get-Content | Measure-Object -Line` 漏计空行, 不采用。

## Findings

### 1. 精确组件清单 (Q1)

目录现状: 顶层 4 文件 + `chat/` 子目录 7 文件。与 2026-09-06 快照相比: 文件数不变 (11), 但快照未单列 `ChatSession.ets` (持久化, 非 UI) 与 `ChatModels.ets` (类型); 容器从 ~272 行 (audit §裁决2) 增至 **299 行** (+27, 新增 NoteDetailOverlay 草稿接线与键盘监听)。

| 文件 | LOC | struct/类 | 一句话职责 |
|---|---|---|---|
| `AgentFloatWindow.ets` | 299 | `AgentFloatWindow` | 浮窗容器: 自绘底部 sheet + 拖拽调高 + 多会话编排 + AgentChatService 回调装配 + 草稿流接线 |
| `AgentInputBar.ets` | 78 | `AgentInputBar` | 底部输入行: TextInput + 拍照按钮 + 发送按钮 |
| `AgentMessageList.ets` | 133 | `AgentMessageList` + `ChatMessageDataSource` | 消息列表: List + LazyForEach(IDataSource) + 空态 + 处理中状态行 |
| `ImagePreviewBar.ets` | 44 | `ImagePreviewBar` | 发送前已选图片缩略图行 + 清除按钮 |
| `chat/ChatHeader.ets` | 107 | `ChatHeader` | 头部: 模型名 + 深度思考开关 + 新建对话 + 关闭 |
| `chat/SessionBar.ets` | 94 | `SessionBar` | 水平滚动会话标签条: 切换/删除/新建 |
| `chat/QuickSuggestions.ets` | 60 | `QuickSuggestions` | 4 个推荐快捷词 chip, 点击直接发送 |
| `chat/EmptyStateHint.ets` | 55 | `EmptyStateHint` | 无消息时的双层钻石 SVG + 引导文案 |
| `chat/ChatBubble.ets` | 139 | `ChatBubble` | 单条消息气泡: user/ai 双分支 + 思考链折叠面板 + 流式/公式/Markdown 三态渲染 |
| `chat/ChatSession.ets` | 62 | `ChatSessionManager` + `sid()` (非 UI) | 会话历史持久化 (@kit.ArkData preferences) |
| `chat/ChatModels.ets` | 53 | `ChatMsg`/`ChatStatusStep`/`ChatStatusMeta`/`ChatSession` (纯类型) | 子组件共享数据结构 |
| **合计** | **1124** | 9 个 @Component + 1 类 + 1 类型文件 | |

逐文件明细 (a LOC 已列上表; 以下为 b-f):

**AgentFloatWindow.ets** (容器)
- (c) 状态: `@Prop @Watch('onShowChange') show: boolean` (:40), `@Prop @Watch('onPendingImageChange') pendingImageUri: string` (:43), `@State @Watch('onMessagesChange') messages: ChatMsg[]` (:45), `@State inputText: string` (:46), `busy: boolean` (:47), `statusMeta: ChatStatusMeta | null` (:48), `deepThink: boolean` (:49), `imagePreview: string` (:50), `keyboardHeight: number` (:51), `sessions: ChatSession[]` (:52), `activeSid: string` (:53), `renderKey: number` (:54), `floatHeight: number` (:55), `overlayVisible: boolean` (:56), `maskOpacity: number` (:57), `sheetOpacity: number` (:58), `sheetOffset: number` (:59), `generatedDraft: NoteDraftReadyEvent | null` (:60); 无装饰器: `onClose`/`onGoCamera` 回调 (:41-42), `motionSeq`/`dragStartH`/`mainWindow: window.Window | null`/`scroller: Scroller`/`sm: ChatSessionManager`/`service: AgentChatService | null` (:61-66)
- (d) import: common 令牌 (BG_DARK/TEXT_4/BORDER/S_3/S_6/R_XL/OVERLAY_MASK/SCREEN_H/DUR_FAST/DUR_BASE, :9-14), `promptAction` (@kit.ArkUI, **死 import**, :15), `common` (@kit.AbilityKit, :16), `window` (@ohos.window, :17), `AgentChatService`/`AgentChatCallbacks` (:18), `LlmConfig` (:19), 本地 7 组件 + ChatSessionManager/sid + ChatModels (:20-27), `NoteDraftReadyEvent`/`KnowledgeUnit` (common, :28-30), `NoteDetailOverlay` (跨 overlay import, :29)
- (e) 消费方: `pages/Index.ets:14` (import) → `:94` (渲染)
- (f) 值得注意: 拖拽手柄 `PanGesture({direction: Vertical})` 连续改 `floatHeight` 30-90% (:253-257); `openAnimated`/`closeAnimated` 用 `animateTo` + `motionSeq` 竞态守卫 + 延迟卸载 (:203-238); `initKeyboard` 经 `window.getLastWindow` 监听 `keyboardHeightChange` (:97-101); sheet 定位 `position y:'100%' + markAnchor + translate(-(74+keyboardHeight)+sheetOffset)` (:280); 隐藏时 `hitTestBehavior(HitTestMode.None)` 透传 (:297)

**AgentInputBar.ets**
- (c) `@Prop inputText: string` (:16), `@Prop canSend: boolean` (:17); 回调 `onTextChange`/`onSubmit`/`onCamera` (:18-20)
- (d) common 令牌 (MINT/BG_DARK/TEXT/TEXT_3/BORDER/F_SM/F_LG/W_BOLD, :9-12); 资源 `$r('app.media.ic_camera')` (:43, 资源存在: `entry/src/main/resources/base/media/ic_camera.svg`)
- (e) AgentFloatWindow.ets:27 → :275 渲染
- (f) TextInput 受控模式 (`text: this.inputText` + onChange 上抛, :25-39); 无 @Builder

**AgentMessageList.ets**
- (c) `@Prop @Watch('onMessagesChanged') messages: ChatMsg[]` (:60), `@Prop busy: boolean` (:61), `@Prop statusMeta: ChatStatusMeta | null` (:62); 普通引用 `scroller: Scroller` (:63), `dataSource: ChatMessageDataSource` (:64); 回调 `onToggleReasoning` (:65)
- (d) common 令牌 (S_2/S_4/MINT/TEXT_4, :9), ChatBubble/EmptyStateHint/ChatModels (:10-12); 系统全局类型 `IDataSource`/`DataChangeListener` (:18, :36)
- (e) AgentFloatWindow.ets:25 → :270 渲染
- (f) `ChatMessageDataSource implements IDataSource` (:18-56, slice 拷贝 + onDataReloaded); LazyForEach keyGen 含 `content.length + streaming + reasoningExpanded` (:98, 流式刷新粒度关键); `initialIndex` 滚到底 (:127-132); busy 时尾部 LoadingProgress + statusMeta 行 (:101-115)

**ImagePreviewBar.ets**
- (c) `@Prop imagePreview: string` (:13); 回调 `onClear` (:14)
- (d) common 令牌 (BORDER/TEXT_3/F_XS/F_BASE, :9)
- (e) AgentFloatWindow.ets:26 → :274 渲染
- (f) 条件渲染 `imagePreview.length > 0` (:17); 纯展示, 无手势/动画

**chat/ChatHeader.ets**
- (c) `@Prop modelName: string` (:27), `@Prop deepThink: boolean` (:30); 可选回调 `onToggleThink`/`onNewChat`/`onClose` (:33-39)
- (d) common 令牌 (MINT/MINT_LIGHT/BG_DARK/TEXT_2/TEXT_3/TEXT_4/S_1-S_4/R_FULL/F_XS/F_MD/W_MEDIUM, :19-22); 系统绘制组件 Circle/Ellipse/Path (:44, :56-59, :90-96)
- (e) AgentFloatWindow.ets:20 → :259 渲染
- (f) "深度思考"胶囊 = 3 个 Ellipse 旋转拼花瓣 (:56-59); 关闭钮 Path 画 X (:90-96); 无状态提升

**chat/SessionBar.ets**
- (c) `@Prop sessions: ChatSession[]` (:28), `@Prop activeSid: string` (:31); 回调 `onSwitch`/`onDelete`/`onNew` (:34-40)
- (d) common 令牌 (MINT/MINT_LIGHT/TEXT_3/TEXT_4/S_1/S_2/R_FULL/F_XS/F_SM/W_MEDIUM/GLASS_10, :22), ChatModels (:23)
- (e) AgentFloatWindow.ets:23 → :268 渲染
- (f) 横向 `Scroll` + `ForEach` (keyGenerator = `s.id`, :48-73); ●/○ 前缀 + ✕ 删除钮 (仅会话数 > 1, :57-63)

**chat/QuickSuggestions.ets**
- (c) 无状态; 可选回调 `onSelect` (:23)
- (d) common 令牌 (PURPLE/PURPLE_LIGHT/TEXT_4/S_2-S_4/R_FULL/F_XS/W_SEMIBOLD, :18)
- (e) AgentFloatWindow.ets:21 → :273 渲染
- (f) `@Builder Chip(label)` 复用 4 个硬编码快捷词 (:48-59)

**chat/EmptyStateHint.ets**
- (c) 无状态无 props
- (d) common 令牌 (MINT/TEXT/TEXT_3/S_2/S_3/S_6/F_XS/F_MD/W_SEMIBOLD, :16); 系统绘制组件 Path (:25-35)
- (e) AgentMessageList.ets:11 → :83 渲染 (条件: `messages.length === 0 && !busy`, :81; 可达 — `newSession()` 置空 messages, AgentFloatWindow.ets:169)
- (f) 双层钻石 Path + 透明度叠加 (:23-37)

**chat/ChatBubble.ets**
- (c) `@Prop msg: ChatMsg` (:17); 回调 `onToggleReasoning` (:18); 私有 `contentProtocol: ContentProtocol` (:19)
- (d) common (MINT/PURPLE_LIGHT/TEXT/TEXT_3/TEXT_4/S_1-S_3/R_MD/F_SM/W_SEMIBOLD + **ContentProtocol 类**, :5-10), ChatModels (:11), **shared 分子** `FormulaSplitRenderer` + `MarkdownRenderer` (../../../shared/molecules/, :12-13)
- (e) AgentMessageList.ets:10 → :90 渲染 (LazyForEach 内)
- (f) user/ai 双分支 (:23-54 / :54-132); ai 侧思考链折叠面板 (reasoning 非空才显, :64-92; 数据源活: ConversationWorkflow.ets:335 → LlmClient.ets:512-13 emit 'reasoning' kind); 内容三态: 流式纯 Text (避免逐 token Markdown 重解析, :96-103) / 含公式 FormulaSplitRenderer (:104-109) / 其余 MarkdownRenderer (:110-116); 长文 (>240 字符) 换底色加宽 (:124-125); `containsFormulaSyntax` 走 ContentProtocol (:136-138)

**chat/ChatSession.ets** (非 UI)
- (c/d) `ChatSessionManager`: 私有 `prefs: preferences.Preferences | null` (:30); import `@kit.ArkData preferences` (:20) + ChatModels (:21); `sid()` 36 进制时间戳 ID (:24-26)
- (e) AgentFloatWindow.ets:22 (`sm` :65, `sid` :169)
- (f) `init(ctx)` 读 preferences "chat_history"/"sessions" JSON, 失败降级默认会话 (:34-49); `save()` putSync + flush, 静默失败 (:52-61)

**chat/ChatModels.ets** (纯类型)
- (d) import `ConversationProgressStep` (workflows/conversation/ConversationState, :11)
- (e) 7 个消费文件: AgentFloatWindow.ets:24, SessionBar.ets:23, ChatSession.ets:21, ChatBubble.ets:11, AgentMessageList.ets:12, **services/AgentChatService.ets:6**, **services/ChatStatusMachine.ets:12** (type-only)
- (f) `ChatMsg` 6 字段含 `streaming`/`reasoning`/`reasoningExpanded?` (:13-34); `ChatStatusStep` = ConversationProgressStep 别名 (:36) — 浮窗类型反向锚定 workflow 层的唯一接缝

### 2. 死组件检测 (Q2)

**四类裁决总表:**

| 组件 | 裁决 | 关键证据 (file:line) |
|---|---|---|
| AgentFloatWindow | **活** | Index.ets:14 import → :94 渲染 |
| ChatHeader | **活** | AgentFloatWindow.ets:20 → :259 |
| SessionBar | **活** | AgentFloatWindow.ets:23 → :268 |
| QuickSuggestions | **活** | AgentFloatWindow.ets:21 → :273 |
| ImagePreviewBar | **活** | AgentFloatWindow.ets:26 → :274; 数据可达 (Index.ets:35-42 相机回传 pendingImageUri) |
| AgentInputBar | **活** | AgentFloatWindow.ets:27 → :275 |
| AgentMessageList | **活** | AgentFloatWindow.ets:25 → :270 |
| EmptyStateHint | **活** | AgentMessageList.ets:11 → :83; 分支可达 (AgentFloatWindow.ets:169 newSession 置空) |
| ChatBubble | **活** | AgentMessageList.ets:10 → :90 (LazyForEach 内) |
| ChatSession (manager) | **活** | AgentFloatWindow.ets:22 → :65/:131/:169 |
| ChatModels | **活** | 7 消费文件 (见 Q1) |

(a) **全死: 0 个** — 全仓 grep (entry 模块全部 .ets) 每个 export 均有 import 点。
(b) **半死: 0 个** — 所有 import 均在 build() 有渲染点, 且渲染分支可达 (EmptyStateHint/ImagePreviewBar 的条件分支均有真实触发路径, 见上表)。
(c) **局部死: 3 处** — 这是本次检测的一等公民交付:

1. **`renderKey` state 只写不读** — 定义 AgentFloatWindow.ets:54, 唯一写点 `this.renderKey++` (:91, onMessagesChange 内), build() 与全文件无任何读点 (grep `renderKey` 在本文件仅 2 处)。疑似历史遗留的"强制刷新键", 现 LazyForEach keyGen (AgentMessageList.ets:98) 已接管刷新, 可删。
2. **`promptAction` 死 import** — AgentFloatWindow.ets:15 import, 全文件仅此 1 处出现 (grep 证据), 无任何调用。
3. **"深度思考" 开关是装饰性控件 (功能级死分支)** — UI 链: `@State deepThink` (AgentFloatWindow.ets:49) → 切换 (:262) → 传 ChatHeader 仅改颜色 (ChatHeader.ets:56-70); **业务链断裂**: `send()` (:176-186) 只调 `service?.captureReply/realReplyStream`, 不传任何思考参数; `ConversationRequest` 三种形态均无思考字段 (ConversationState.ets:29-47); 实际请求的 `enableThinking` 在 ReplyService.ets:54/:81/:123 **硬编码 `false`** (entry 模块全部 3 处赋值)。而 `LlmRequest.enableThinking` 参数本身存在且接线完备 (LlmTypes.ets:144; LlmClient.ets:86-88 缺省回退 config, :281-285 thinking 配置注入) — 即底层能力在, UI 开关没接上。注意区分: ChatBubble 的 reasoning 折叠面板**不因此而死** — deepseek-v4-pro 服务端默认思考模式仍会回 reasoning_content (LlmClient.ets:495 注释, :512-513 emit), 数据源活。

**服务 seam 层附带发现** (超出目录范围但与容器消费直接相关): `AgentChatService` 101 行中有 **6 个 facade 方法全仓无调用方** — `realReply` (:74), `restoreDraft` (:95), `retryDraft` (:96), `regenerateNote` (:98), `requestRegeneration` (:99), `listRecoverableDrafts` (:100)。AgentFloatWindow 实际只消费 4 个: `captureReply`/`realReplyStream`/`confirmDraft`/`cancelDraft` (:182-184, :200, :290)。spec index 称 "AgentChatService 76 LOC UI facade" (docs/specs/index.md:47), 现为 101 行 — 差值主要来自这批待接线 (或待删) 的透传方法。

(d) **活: 11/11**。

**资源/常量检查**: 目录内无独立资源/常量文件 (仅 11 个 .ets); 唯一资源引用 `ic_camera.svg` 存在于 entry resources (AgentInputBar.ets:43)。ChatModels 是共享类型文件, 4 个 export 全部被消费 (Q1 明细)。

**对任务简报的两处修正** (以当前代码为准):
- 简报称 "AgentFloatWindow 还使用 AppStorage 'notesVersion' 手工事件总线" — **已过时**。grep 全目录 0 处 `notesVersion`; 手工总线现集中在 9 文件 17 处 (Home/Notes/Review 页 + HomeViewModel/NotesViewModel/UiDataCacheService/KnowledgeUnitPostCommitEffects 等), 与浮窗无关。浮窗的显隐走的是另一条 AppStorage 键 `activeOverlay` (OverlayService.ets:17)。
- 简报称 spec 018 "AgentChatService 76 行 UI facade" — 现为 101 行 (见上)。

### 3. 容器职责拆解 (Q3)

**业务逻辑 (替换 UI 壳时必须原样保留或等价迁移):**

| 职责 | 证据 | 说明 |
|---|---|---|
| AgentChatService 回调装配 (12 项 AgentChatCallbacks) | AgentFloatWindow.ets:105-134 | addAiMsg/addAiMsgEmpty/appendAiMsg(kind 二分流)/finishAiMsg/setBusy/setStatusMeta/getContext/getConversationText/getSessionId/onDraftReady — 浮窗是回调的**唯一实现方**, 与 ConversationWorkflow (spec 018 唯一编排) 的接缝 |
| 发送分流: 有图→captureReply / 纯文本→realReplyStream | :176-186 (`send`) | 图片整链 vs SSE 流式两条产品路径 |
| 消息不可变更新 (map+spread) | :107-121, :162-164, :270 | streaming/reasoning/reasoningExpanded 三态字段维护 |
| 会话编排: sync/switchSession(含流式中断收尾)/newSession/deleteSession | :136-170 | + ChatSessionManager preferences 读写 (:131, :80/:92/:169-170) |
| conversationText 构建 (上下文拼装) | :140-157 (`buildConversationText`) | 供 workflow 做 memory context |
| 草稿流接线: onDraftReady→generatedDraft→NoteDetailOverlay→confirmDraft/cancelDraft | :128, :196-201, :282-296 | 跨 overlay 业务流 (Note 生成预览/确认/取消) |
| 状态条元数据透传 | :124, :270 | ChatStatusMachine → statusMeta → 列表 busy 行 |

**纯 UI (可随组件替换丢弃/重写):**

| 职责 | 证据 |
|---|---|
| 开/关动画: overlayVisible/maskOpacity/sheetOpacity/sheetOffset + animateTo + motionSeq 竞态守卫 + 延迟卸载 | :56-59, :203-238 |
| 拖拽手柄: PanGesture 连续改 floatHeight (30-90%) | :253-257 |
| 底部 sheet 自绘定位: position y:'100%' + markAnchor + translate | :277-280 |
| 键盘避让手写: initKeyboard 监听 keyboardHeightChange → keyboardHeight → translate 偏移 | :51, :97-101, :280; 全局避让被 Index.ets:31 设为 KeyboardAvoidMode.NONE (因 sheet 用 translate 定位, 系统默认避让对它无效, 只能手工) |
| hitTestBehavior 显隐透传 | :297 |
| modelLabel 展示 (LlmConfig 只读) | :188-194 |
| 分隔线/内边距/圆角等样式 | :266, :271, :278 |

**浮窗实现方式判定: 应用内 overlay (Stack 叠加), 非真子窗口。** 证据链:
1. `pages/Index.ets:44-103` — AgentFloatWindow 作为页面根 `Stack()` 的子组件渲染在 Tabs 之上 (:94-102), 与 CameraOverlay 互斥由 AppStorage `activeOverlay` 驱动 (:27, :86-91);
2. `AgentFloatWindow.ets:242-297` — build 为自绘 mask Column + sheet Column, 底部锚定靠 position/markAnchor/translate, 是标准**应用内伪浮层**写法;
3. `@ohos.window` 仅用于 `getLastWindow` + `on('keyboardHeightChange')` 键盘高度监听 (:17, :63, :97-101), 全仓 grep 无 `createSubWindow`/`createWindow` 调用;
4. 显隐动画全在组件内 animateTo (:214, :228), 无窗口级 loadContent/dispatchWindowLifecycle。

### 4. 鸿蒙替换候选 (Q4, 官方文档为唯一信源)

检索工具: `devecocli docs search`。以下 documentId 均为本地官方文档库命中项。

**角色 1: 消息列表 (AgentMessageList)**

| 候选 | documentId | 提供的能力 | 适配度 |
|---|---|---|---|
| List + LazyForEach (现状即此) | `arkts-layout-development-create-list` (创建列表), `ts-container-listitem` (ListItem), `bpta-lazyforeach-optimization` (懒加载优化) | 超屏自动滚动、按需创建/销毁 | **已达标** — AgentMessageList.ets:80-124 已是 List+LazyForEach+IDataSource |
| @Reusable 组件复用 | `ts-custom-component-decorator-reusable` | @Reusable 装饰自定义组件, reuseId 区分类型, aboutToReuse 回调收参; 官方点名"列表滚动、频繁切换显隐"场景 | **高** — 唯一缺口: ChatBubble 未加 @Reusable; 官方长列表最佳实践 `bpta-best-practices-long-list` 原文点名"聊天应用"列表场景 |
| ListItemGroup | `ts-container-listitemgroup` | 分组头尾 + 组内懒加载 | 低 — 消息无分组语义, 现状无需 |

**角色 2: 浮窗容器 (AgentFloatWindow 壳) — 两条官方路线**

| 路线 | documentId | 提供的能力 | 适配度 |
|---|---|---|---|
| **A. 应用内半模态 bindSheet** (推荐) | `ts-universal-attributes-sheet-transition` (半模态转场, SheetOptions: height/detents 多档高度), `faqs-arkui-1088` (半模态常见问题: 固定高度禁跟手/侧滑关闭), `faqs-arkui-1087` (UI 跟随 sheet 高度变化) | 系统级半模态: 内建出场/退场动画、手势跟手拖拽、detents 档位高度、onWillDismiss 拦截 | **中高** — 可整体替换 openAnimated/closeAnimated/motionSeq/translate 定位约 60 行; 代价: 现为 30-90% 连续拖拽, detents 是档位式 (交互略降级); 键盘避让见角色 8 |
| **B. @ohos.window 子窗口/悬浮窗** | `faqs-arkui-1196` (设置应用子窗口: moveWindowTo/startMoving/拖动/改大小), `faqs-arkui-1572` (子窗口实现自定义宽高圆角弹窗: "精准的层级控制"), `faqs-arkui-1165` (子窗口无法拖动→PanGesture onActionUpdate + moveWindowTo 官方解法), `faqs-arkui-240` (subwindow 默认不铺满) | 独立窗口层级、真悬浮 (可跨页面存活)、自由拖动 | **中** — 仅当产品形态升级为"全局悬浮球/跨页浮窗"时值得; 代价: 独立 UI 上下文 (promptAction/键盘/共享状态语义变化), 生命周期自管 |
| 手势底座 (两路线通用) | `ts-basic-gestures-pangesture` (PanGesture), `faqs-arkui-827` (Pan 与其他手势冲突), `faqs-arkui-172` (嵌套容器拖拽错乱: distance 1 提灵敏) | 拖拽事件 | 现状已用 (AgentFloatWindow.ets:255), 保留 |

**角色 3: 输入栏 (AgentInputBar)**

| 候选 | documentId | 提供的能力 | 适配度 |
|---|---|---|---|
| TextInput (现状) | `faqs-arkui-1259` (单行, 仅支持单文本样式; 获焦失焦文本效果) | 单行输入 | **保留即可** — 现受控模式健康 |
| TextArea | `faqs-arkui-604` (最多显示行数+滚动条), `faqs-arkui-1419` (长文本注入滚动) | 多行自适应换行 | 中 — 若要长问题输入换行 |
| RichEditor | `ts-basic-components-richeditor` (span 级富文本, 支持图文混排), `ts-universal-styled-string` (属性字符串, Text/RichEditor 通用) | 富文本编辑 + **图片 span 内联** | 中 — 若要"输入框内直接贴图"可上; 但 controller 驱动、受控更新模式比 TextInput 重, 现单行+独立 ImagePreviewBar 的组合已够用 |

**角色 4: 会话切换条 (SessionBar)**

| 候选 | documentId | 提供的能力 | 适配度 |
|---|---|---|---|
| **Chip (系统预置组件库, API 11+)** | `ohos-arkui-advanced-chip` ("标签展示和交互场景…可快速实现标签的**创建、删除和交互**能力"), 配套 `ohos-arkui-advanced-chipgroup` (组内间距) | 激活态样式、删除回调、图标 | **最高** — 与 ●/✕ 语义一一对应, 还能顺手替换 QuickSuggestions 的自绘 chip |
| SegmentButton | `ohos-arkui-advanced-segmentbutton` (胶囊单选/多选) | 固定分段切换 | 低 — 不支持动态增删, 会话数不定 |
| Tabs 自定义页签 | `faqs-arkui-917` (官方明说 "Tabs 组件本身并没有提供"页签增删能力, 需自定义模拟浏览器页签) | 页签容器 | 低 — 官方 FAQ 恰好证明 SessionBar 这类"可增删页签条"本来就得自绘/用 Chip |
| Swiper | `faqs-arkui-1447` (滑块视图容器) | 内容区滑动轮播 | 低 — 是内容切换不是页签条 |

**角色 5: 推荐快捷词 (QuickSuggestions)**

| 候选 | documentId | 能力 | 适配度 |
|---|---|---|---|
| Chip | `ohos-arkui-advanced-chip` (官方场景原话: "搜索框历史记录、邮件发送列表") | 可点击标签 | **高** — 与现 @Builder Chip (:48-59) 逐项对应 |

**角色 6: 图片预览行 (ImagePreviewBar)**

| 候选 | documentId | 能力 | 适配度 |
|---|---|---|---|
| Image (现状) + **bindContentCover 全模态** | `arkts-contentcover-page` (官方原话: "全屏模态形式…**适用于查看大图**") | 点击缩略图弹全屏大图 | **高** — 现状只有 48×48 缩略图无法看大图, 此为增量能力补齐 |
| Swiper | `faqs-arkui-1447` | 多图轮播 | 中 — 未来支持多图时 |

**角色 7: 头部 (ChatHeader)**

| 候选 | documentId | 能力 | 适配度 |
|---|---|---|---|
| Toggle | `arkts-common-components-switch` (切换按钮: Button/Checkbox/Switch 三样式, isOn) | 两态开关 | 中 — 可替代自绘"深度思考"胶囊, 但**先决条件是接通 deepThink→enableThinking 业务链** (Finding 2), 否则换了也是装饰 |
| Badge | `faqs-arkui-1577` ("信息标记组件, 可附加在单个组件上") | 状态圆点/数字 | 中 — 可替代自绘在线绿点 (ChatHeader.ets:44-46); 现自绘仅 3 行, 收益小 |
| Chip (激活态) | `ohos-arkui-advanced-chip` | 胶囊选中态 | 中 — 与"深度思考"胶囊形态最像 |

**角色 8: 键盘避让 (容器附属机制)**

| 候选 | documentId | 能力 | 适配度 |
|---|---|---|---|
| bindSheet 内建 keyboardAvoidMode | `faqs-arkui-453` (半模态可通过 keyboardAvoidMode 避让软键盘, SheetKeyboardAvoidMode 枚举), `faqs-arkui-1571` (键盘避让机制/避让模式总述) | 声明式键盘避让 | **高** — 若走路线 A, 手写 initKeyboard + keyboardHeight translate (AgentFloatWindow.ets:97-101, :280) 与全局 KeyboardAvoidMode.NONE (Index.ets:31) 可整体退役 |

**角色 9: 空态 (EmptyStateHint) / 气泡内容 (ChatBubble)**

| 角色 | 结论 | 证据 |
|---|---|---|
| EmptyStateHint | **无官方对应组件** — `docs search "空状态"` 无组件命中 (仅窗口生命周期等无关项); 空态插画+文案属自绘惯例 | 检索记录 2026-09-11 |
| ChatBubble 的 Markdown/公式渲染 | **无官方组件, 现状即官方推荐路线** — 官方原话: "HarmonyOS 目前没有提供专门的数学公式渲染组件, 可以使用 WebView 组件来加载支持数学公式渲染的网页" | `faqs-arkweb-97` (与 2026-09-06 审计补充 3 的 C1 核实一致); MarkdownRenderer+FormulaSplitRenderer (KaTeX WebView) 无替换必要 |

### 5. React 生态对照 (Q5, 概念参照, 均非鸿蒙 API)

| 组件角色 | React/RN 生态等价物 (生态参照) | 封装的模式 (一句话) |
|---|---|---|
| AgentFloatWindow 容器 | @gorhom/bottom-sheet (RN) / vaul (web) | 底部半展开面板 + 手势拖拽调档 + 键盘避让 + 拖拽关闭, 全套手势物理 |
| AgentFloatWindow 拖拽 | framer-motion `drag` (web) / react-native-gesture-handler PanGesture | 声明式拖拽 + 惯性/约束边界 |
| AgentMessageList | react-native-gifted-chat; 虚拟化: Shopify FlashList / react-virtuoso | 聊天列表全家桶 (倒序列表+气泡+输入栏); 懒加载虚拟化列表 |
| ChatBubble | gifted-chat 的 Message/Bubble + react-markdown | 消息气泡骨架 (角色配色/头像/时间) + Markdown 声明式渲染 |
| AgentInputBar | gifted-chat InputToolbar (RN TextInput) | 聊天输入行 (受控 text + 发送态 + 附件按钮) |
| ChatHeader | react-native-paper Appbar/Header | 导航头部骨架 (标题+动作槽位) |
| "深度思考" 开关 | MUI Switch / RN Switch | 受控两态开关 |
| SessionBar | antd Tabs (closable) / react-native-tab-view | 可增删页签条 |
| QuickSuggestions | MUI Chip / antd Tag | 可点击标签 chip |
| ImagePreviewBar | react-native-image-picker 附件条 + react-native-image-zoom-viewer | 发送前附件缩略行 + 全屏大图缩放查看 |
| EmptyStateHint | antd Empty | 空状态插画+主副文案的标准模式 |
| ChatSession 持久化 | zustand persist / react-native-mmkv | 状态自动持久化到 KV 存储 |
| OverlayService (activeOverlay 总线) | zustand store / mitt 事件总线 | 单一响应式状态源替代手工事件广播 |

### 6. 总表 (必含交付)

| 组件 | 行数 | 职责 | 状态 | 鸿蒙替换候选 (documentId) | React 对照 (生态参照) |
|---|---|---|---|---|---|
| AgentFloatWindow | 299 | 浮窗容器/编排 | 活 (局部死: renderKey/promptAction/deepThink 装饰) | **bindSheet** `ts-universal-attributes-sheet-transition` + `faqs-arkui-453` (键盘) / 子窗口 `faqs-arkui-1196` | @gorhom/bottom-sheet |
| AgentInputBar | 78 | 输入行 | 活 | TextInput 保留 `faqs-arkui-1259`; TextArea `faqs-arkui-604`; RichEditor `ts-basic-components-richeditor` | gifted-chat InputToolbar |
| AgentMessageList | 133 | 消息列表 | 活 | 现状 List+LazyForEach 已达标; 补 @Reusable `ts-custom-component-decorator-reusable` + `bpta-best-practices-long-list` | gifted-chat / FlashList |
| ImagePreviewBar | 44 | 图片缩略行 | 活 | + bindContentCover `arkts-contentcover-page`; 多图 Swiper `faqs-arkui-1447` | image-zoom-viewer |
| chat/ChatHeader | 107 | 头部 | 活 | Toggle `arkts-common-components-switch`; Badge `faqs-arkui-1577`; Chip | paper Appbar |
| chat/SessionBar | 94 | 会话标签条 | 活 | **Chip** `ohos-arkui-advanced-chip`; SegmentButton `ohos-arkui-advanced-segmentbutton` (不适配: 无增删) | antd Tabs (closable) |
| chat/QuickSuggestions | 60 | 推荐词 | 活 | **Chip** `ohos-arkui-advanced-chip` | MUI Chip |
| chat/EmptyStateHint | 55 | 空态 | 活 | 无官方组件 (保持自绘) | antd Empty |
| chat/ChatBubble | 139 | 消息气泡 | 活 | 无官方 Markdown/公式组件 `faqs-arkweb-97`; 现状即官方路线 | gifted-chat Bubble + react-markdown |
| chat/ChatSession | 62 | 会话持久化 (非 UI) | 活 | 现状 @kit.ArkData preferences 即官方 API | zustand persist / mmkv |
| chat/ChatModels | 53 | 共享类型 | 活 | — (纯类型) | TS interfaces |

## Conclusion

AgentFloatWindow 是一个**健康的自绘聊天浮窗**: 11 文件 1124 行, 单向数据流纪律良好 (@Link=0, props down/回调上抛), 消息列表已对齐官方 List+LazyForEach 懒加载路线, 公式渲染走在官方唯一推荐的 WebView 路线上 — 组件层面**没有可删的整尸, 只有 3 处局部死肉** (renderKey / promptAction / 装饰性 deepThink 开关) 和服务 seam 上 6 个无调用方的 facade 方法。真正的替换机会在**容器壳**: 自绘 sheet 的开合动画、拖拽调高、键盘避让三套手写机制 (~60 行) 可整体收口到官方半模态 bindSheet (手势/档位/键盘避让全内建); 若产品要"跨页悬浮"形态, 则是 @ohos.window 子窗口路线的活。UI 小件中 SessionBar/QuickSuggestions 与官方 Chip、图片预览与 bindContentCover 是两个即插即用的升级点。

## Implications

- **P0 (删死肉)**: `renderKey` (:54/:91) + `promptAction` import (:15) 两处零风险删除; AgentChatService 6 个无调用方法 (:74/:95-100) 需产品裁决 "接线 (草稿恢复/笔记重生成入口) 还是删除"。
- **P0 (接线或摘牌)**: "深度思考" 开关要么接通 `deepThink → ConversationRequest → ReplyService.enableThinking` (LlmTypes.ets:144 参数已备), 要么摘掉 UI 免得误导用户 — 当前它是纯装饰。
- **P1 (容器收口)**: bindSheet 路线可同时消灭 motionSeq/sheetOffset 手写动画、keyboardHeight 手写避让、Index.ets:31 的全局 KeyboardAvoidMode.NONE 三件套; detents 档位 vs 现 30-90% 连续拖拽的交互取舍需先拍板。
- **P2 (小件升级)**: SessionBar/QuickSuggestions → Chip; ImagePreviewBar → +bindContentCover 看大图; ChatBubble → @Reusable (流式聊天正中官方复用场景)。
- 死组件检测口径可复用于另两大浮层 (CameraOverlay 10 文件 / NoteDetailOverlay 22+ 文件), 本次方法 (import grep + 渲染点 + 分支可达性) 直接平移。

## 裁决记录 (2026-09-11, 用户会话)

- **"深度思考"开关 → 删除** (Implications P0 "接线或摘牌" 二选一裁决为**摘牌**): 删除 ChatHeader 的装饰性开关 UI 及其关联 state, 不做 deepThink→enableThinking 接线。删除范围 (是否连带清理 LlmTypes.ets:144 传输参数与 ReplyService 三处硬编码) 待下一轮拍板。

## Open questions

- bindSheet 的 detents 能否配 `preferType`/自定义连续高度, 保住现有"拖到哪停哪"的手感? (官方 SheetOptions 以档位为主, 需原型验证)
- 子窗口路线下, AppStorage (activeOverlay) 与 promptAction 在独立 UI 上下文的行为差异 — spec 018 的 FormCard/Reminder Kit adapter 是否已有子窗口经验可复用?
- deepThink 若接线, 深度思考与流式 reasoning 面板 (ChatBubble.ets:64-92) 的展示联动 (开启时自动展开 reasoning?) 需一并设计。
- AgentChatService 101 行 vs spec 018 记载的 76 行 facade — 收敛时机与 spec 勘误。

---

## Primary source citations

- `entry/src/main/ets/overlays/AgentFloatWindow/*.ets` (11 文件全文通读) — Q1 全部字段/行数/方法
- `entry/src/main/ets/pages/Index.ets:14,27,31,35-42,44-103` — 浮窗挂载/activeOverlay/全局键盘避让关闭
- `entry/src/main/ets/services/OverlayService.ets:17-39` — activeOverlay 手工总线
- `entry/src/main/ets/services/AgentChatService.ets:9-20,63-101` — 回调接口与 facade 方法清单
- `entry/src/main/ets/services/ReplyService.ets:54,81,123` — enableThinking 硬编码 false
- `entry/src/main/ets/services/ChatStatusMachine.ets:12` — ChatModels 反向消费
- `entry/src/main/ets/workflows/conversation/ConversationState.ets:29-47` — ConversationRequest 无思考参数
- `entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets:19,312-348` — 流式链路与 reasoning 透传
- `common/src/main/ets/llm/LlmTypes.ets:144,184` / `LlmClient.ets:86-88,281-285,495-520` — enableThinking 参数链与 reasoning emit
- 全仓 grep: `renderKey`/`promptAction`/`deepThink`/`notesVersion`/`realReply|restoreDraft|retryDraft|regenerateNote|requestRegeneration|listRecoverableDrafts`/各组件 import — Q2 裁决
- `docs/specs/index.md:47` / `docs/specs/018-agent-workflow-architecture.md:43,70` — spec 018 facade 语义
- `docs/research/frontend-component-audit-2026-09-06.md` §6/裁决2/补充3 — 2026-09-06 基线快照
- 鸿蒙官方文档 (devecocli docs, documentId): `ts-universal-attributes-sheet-transition`, `faqs-arkui-1088`, `faqs-arkui-1087`, `faqs-arkui-453`, `faqs-arkui-1571`, `faqs-arkui-1196`, `faqs-arkui-1572`, `faqs-arkui-1165`, `faqs-arkui-240`, `ts-basic-gestures-pangesture`, `faqs-arkui-827`, `faqs-arkui-172`, `arkts-layout-development-create-list`, `ts-container-listitem`, `ts-container-listitemgroup`, `bpta-lazyforeach-optimization`, `bpta-best-practices-long-list`, `ts-custom-component-decorator-reusable`, `faqs-arkui-1015`, `faqs-arkui-1259`, `faqs-arkui-604`, `faqs-arkui-1419`, `ts-basic-components-richeditor`, `ts-universal-styled-string`, `ohos-arkui-advanced-chip`, `ohos-arkui-advanced-chipgroup`, `ohos-arkui-advanced-segmentbutton`, `faqs-arkui-917`, `faqs-arkui-413`, `faqs-arkui-1447`, `arkts-contentcover-page`, `arkts-common-components-switch`, `faqs-arkui-1577`, `faqs-arkweb-97`

## Last updated

2026-09-11

---

## Update — 2026-09-13 (post-#111 implementation reconciliation)

> **Scope**: amend this research doc so it stops contradicting the implementation &
> the accepted spec decisions reached on 2026-09-13. The original 2026-09-11 analysis
> is preserved above for traceability; this section only reconciles.

### Reconciliations

| Original claim (line) | Original wording | Reconciled statement (2026-09-13) | Source of truth |
|---|---|---|---|
| L10 (TL;DR) | `ReplyService.ets:54,81,123 硬编码 enableThinking: false` | The three overrides are gone. The current file is a 227-LOC module dated 2026-09-13; `enableThinking` is no longer pinned at the call site. Supply defaults to `DEFAULT_ENABLE_THINKING = true` from `common/src/main/ets/llm/LlmConfig.ets:38`. | commit `2990579`; `ReplyService.ets`; `LlmConfig.ets` |
| L10 (TL;DR) | "装饰性深度思考开关" | The decorative toggle has been **removed** in commit `489f88a`; only an unused `S_1` import in `ChatHeader.ets:18` was missed and is a static-analysis nit, not user-visible behavior. | commit `489f88a`; see two-axis review Standards (b) §ChatHeader dead import |
| L68 | `LazyForEach keyGen 含 content.length + streaming + reasoningExpanded (:98)` | **NOT** `reasoningExpanded`. Current `chatItemKey` (in [`entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets`](../../entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets)): `id + content.length + reasoning.length + streaming`. Fold state moved to `ChatBubble` internal `@State` (initialized from `msg.reasoningExpanded`; toggle re-syncs the parent via `onToggleReasoning` so persistence and LazyForEach row identity are preserved). See commit `2e27083` and ADR-0015 § "Accepted UI Amendment — 2026-09-13". | commit `2e27083`; `ChatModels.ets:41-47`; `ChatBubble.ets:24-25` |
| L114 | "ChatMsg 6 字段含 `streaming`/`reasoning`/`reasoningExpanded?`" | Still 6 fields structurally (`id` / `role` / `content` / `ts` / `streaming` / `reasoning` / optional `reasoningExpanded`), but the **default** for legacy messages is `true` (expanded), not collapsed. The `reasoning` field is also now `string \| undefined` with `chatMessageReasoning(msg)` helper for legacy-session safety. | `ChatBubble.ets:24-25`; `AgentFloatWindow.ets:177`; `ChatModels.ets:38-65` |
| L160 | "streaming/reasoning/reasoningExpanded 三态字段维护" | The three-field invariant still holds at the **ChatMsg persistence** layer (`copyChatMsg` preserves `reasoningExpanded`), but at the **list-row** layer the row identity key no longer carries `reasoningExpanded`. Reducer is centralized in `applyStreamEventToChatMsg` (`ChatModels.ets:73-83`); toggling fold never re-keys. |

### Out-of-scope but worth flagging
- A parallel design conversation (spec 021 + render-jank research) proposes dropping `content.length` / `reasoning.length` from `chatItemKey` entirely (third position: `id` only, or `id + streaming`). That is **not** part of the #111 slice and is intentionally not adopted here; the 2026-09-13 UI Amendment's choice to keep length-based keys (so the pure-thinking phase does not freeze) and drop only `reasoningExpanded` is a deliberate middle ground.

### Cross-references after reconciliation
- Spec: [`docs/specs/019-reasoning-process-display-p0.md`](../../specs/019-reasoning-process-display-p0.md)
- ADR: [`docs/adr/0015-structured-stream-events.md`](../../adr/0015-structured-stream-events.md)
- Implementation: [`ChatModels.ets`](../../entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatModels.ets), [`ChatBubble.ets`](../../entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatBubble.ets), [`AgentFloatWindow.ets`](../../entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets)

> 2026-09-13 reconciliation note appended by two-axis code review (no overwrite of the original 2026-09-11 findings, per AGENTS.md red line 3).
