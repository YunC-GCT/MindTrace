# 前端体检合集 — 2026-09-06

> **Date:** 2026-09-06（含 2026-09-11 的一条补充）
> **Scope:** MindTrace `entry` 全量 UI —— 用户路径、交互五态、a11y、i18n、性能、持久化、错误降级、后续待办
> **方法:** 每节自带方法（grep 硬数据 / 路径走查 / 逐组件清点），各节开头保留原始的方法与「配套」说明
> **合并说明 (2026-10-30):** 原本是 8 篇同一天、同一模板的摸底文档（各 6–9 KB，文首互相引用），要开 8 个文件才拼得出「前端现状」。现合并为一篇，节内内容原样保留，只做标题降级；引用这 8 个旧文件名的地方改指本文件。

## 目录

1. 用户路径走查
2. 交互五态完整性
3. 可访问性 a11y
4. 国际化 i18n 与文案一致性
5. 性能与资源
6. 状态序列化与持久化
7. 错误降级与边界
8. 体检后续待办合同

---

## 1. 前端用户路径走查 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Status:** 路径式体检 — 4 主路径 + 3 横切, 事实字段机器提取 + 关键流程实读
> **Source**: 在 [`frontend-ui-design-inventory-2026-09-06.md`](./frontend-ui-design-inventory-2026-09-06.md) 静态清点基础上, 沿用户路径横向排查, 补 "页面状态保留 / 跨页面传参 / 键盘避让 / 沉浸式 / 异常分支"
> **Status (2026-09-17):** `[obsolete]` `QuickSuggestions` 组件已删除;本文对该组件的引用不再反映当前实现。
> **配套**: §8 待办合同 7 候选待办合同 (本档为输入补充)

---

**TL;DR:** 沿用户路径走查发现 **5 处路径级问题** 是静态清点抓不到的: ① HomeTopBar/NotesHeader/AiSettings.PageHeader 用 `@Prop` 传 `statusBarHeight` 不响应折叠屏变化 (C4 候选) ② Index 整体禁键盘避让 (KeyboardAvoidMode.NONE:31), 浮层自实现键盘但普通 TextInput (AiSettings/NoteEditForm) 无处理 ③ AI 浮窗→拍照→返回图: pendingImageUri 跨页面传递只在 Index:25 持有, AgentFloatWindow:40 @Prop 接收但未看消费点 ④ 主页→浮窗→关闭→再开: ChatSessionManager.loadHistory 持久化待核实 ⑤ 笔记详情/AI 浮层 OVERLAY_MASK 色差 (50%/80%) 不一致, 视觉跳跃风险

---

### 路径 1 · 启动 → 首页 (Home)

```
EntryAbility.onCreate
  ├─ 注入 ReminderFacadeImpl 入 AppStorage
  ├─ 读 statusBarHeight: window.getWindowAvoidArea → AppStorage.setOrCreate  ⚠ C4
  └─ loadContent('pages/Index')
       → Index.aboutToAppear: setKeyboardAvoidMode(NONE)  ⚠ P1.2
            Tabs[Home/Notes//Review/Profile] + barHeight(0) TabBar
              → HomePage
                 ├─ HeroBanner → GradientRing (Canvas 渐变弧)  ✓  C7
                 ├─ HomeCollapsedReview (今日复习概览)
                 ├─ ReminderBanner
                 ├─ HomeRecentNotes → NoteCard ×N (点 → NoteDetailOverlay)
                 └─ FloatingButton (onTap → overlays.open('camera'))
                    TabBar.onAiTap → overlays.open('float')
```

**路径级问题清单:**
| # | 问题 | 证据 | 风险等级 |
|---|---|---|---|
| P1.1 | `statusBarHeight` 仅 EntryAbility.onCreate 时种一次, 后续不更新; HomeTopBar `@Prop statusBarHeight` 不会响应变化 | EntryAbility.ets:62, HomeTopBar.ets:24 | 中 (折叠屏 / 横竖屏切换) |
| P1.2 | Index `KeyboardAvoidMode.NONE` 整体禁键盘避让, 主页内若有 TextInput (现无) 风险; AgentFloatWindow 自实现接管但 Index 全局策略切断系统默认 | Index.ets:31 | 低 (主页当前无输入) |

---

### 路径 2 · 拍照 → AI 浮窗识别 → 生成笔记

```
HomePage.onGoCamera → Index.onGoCamera → overlays.open('camera')
  → CameraOverlay (相机浮层)
       CameraPreview (XComponent) + CameraShutterBtn (CAM_* 令牌双环)
       CameraCapture: 拍照后 → cameraPicker/photoAccessHelper 路径
       CameraConfirmBtn → onCameraConfirm(uri, src)
            ↓ Index.onCameraConfirm (Index.ets:35-42)
              overlays.close()  // 关相机
              setTimeout(0) → pendingImageUri = uri; overlays.open('float')  ⚠ P2.1
                ↓ AgentFloatWindow
                   @Watch('onPendingImageChange') pendingImageUri
                   ⤷ 消费点待查 (AgentInputBar? AgentMessageList?)  ⚠ P2.2
                   ⤷ CameraOverlay 内 onGoCamera 路径 (Index.ets:100): switchTo('camera')
                   ⤷ captureReply (AgentChatService.ets:45) → AiService.analyzeImage (persist:false)
                     → 返回 ClassificationResult, 浮窗仅"识别"不"入库"
                 用户发"生成笔记" →
                   IntentClassifier.classify = note_generation
                   → AgentChatService.generateNoteFromConversation (206)
                   → AiService.captureText (persist:true)  ⚠ C0 修复后才走通
                     → NoteDaoAdapter.insert → 知识入库 → bumpNotesVersion (6 文件手工)
```

**路径级问题清单:**
| # | 问题 | 证据 | 风险等级 |
|---|---|---|---|
| P2.1 | pendingImageUri 通过 setTimeout(0) 延迟 0 ms 投递, 与 Index 的 Tabs 切换竞态 | Index.ets:38-41 | 低 (实测稳定) |
| P2.2 | pendingImageUri 在 AgentFloatWindow:40 接收, 真实消费点 (AgentInputBar / AgentMessageList?) 待核实 | AgentFloatWindow.ets:40 | 高 (若未消费=图丢失) |
| P2.3 | analyzeImage → 用户发"生成笔记" 之间, 浮窗需识别"用户意图=生成" → IntentClassifier; 命中失败时降级路径待核实 | AgentChatService.ets:206 | 中 |
| P2.4 | 入库后 `notesVersion` 手工 bump, Notes/Home/星图/详情 各自重读; 漏刷类 bug 已确认存在 (C4 候选) | 6 文件 grep | 高 (已记录) |

---

### 路径 3 · AI 对话 (AgentFloatWindow 内部)

```
AgentFloatWindow.aboutToAppear (66)
  ├─ loadHistory: ChatSessionManager 持久化  ⚠ P3.1
  ├─ initKeyboard: 监听 onKeyboardHeightChange → @State keyboardHeight
  └─ show=true: overlayVisible=true; animateTo(maskOpacity:0→1, DUR_FAST)
       主面板: sheetOffset (open/close 22/18 vp), DUR_BASE  ✓ C7 合规
       主体 Stack(会话消息 + 输入栏)
         ├─ ChatHeader (标题/操作)
         ├─ SessionBar (多会话切换)
         ├─ AgentMessageList → ChatBubble (按消息含公式分支选两个分子)
         ├─ QuickSuggestions
         └─ AgentInputBar (受控 TextInput + 发送)  ⚠ P3.2 键盘避让自实现
       关闭 → animateTo sheetOffset/opacity DUR_FAST → setTimeout(FLOAT_UNMOUNT_DELAY_MS=190ms) 真卸载
```

**路径级问题清单:**
| # | 问题 | 证据 | 风险等级 |
|---|---|---|---|
| P3.1 | loadHistory 持久化实现待核实: 关闭浮窗 190ms 后卸载, 重新打开消息是否恢复 | AgentFloatWindow.ets:33 + ChatSessionManager.ets | 高 (关掉再开=记忆清零=严重 UX) |
| P3.2 | 键盘避让自实现, 监听 onKeyboardHeightChange; Index 全局 NONE 已被本组件覆盖 — 但页面切换时若残留可能错位 | AgentFloatWindow.ets:48, Index.ets:31 | 中 |
| P3.3 | `motionSeq` 防竞态 (animateTo 重入保护) 已就位, 但 TabBar 之类无同款保护 — 快速连点 Tab 应一致 | AgentFloatWindow.ets:57 | 低 |

---

### 路径 4 · 笔记查看/编辑 (NoteDetailOverlay)

```
点击入口三处:
  - HomeRecentNotes → NoteCard.onTap → overlayService.open('detail', noteId)
  - ReviewGraphView 点击星球 → 同上
  - NotesList/SubjectNoteList → 同上

NoteDetailOverlay
  ├─ aboutToAppear: invalidateDetailRender 缓存
  ├─ Stack(OVERLAY_MASK_SOLID 80% 黑 + 主面板 16vp 圆角)
  │   ├─ NoteCloseButton (AppIcon close)
  │   ├─ NoteDetailMeta (元信息 294 行)  ⚠ P4.1
  │   ├─ NoteDetailBody → 5 种 NoteType 策略分派 6 渲染器
  │   │   ├─ Concept/Theorem/Formula/Proof/Fallback → MarkdownRenderer
  │   │   └─ Computation → MarkdownRenderer + DetailStepList (index+item key ⚠)
  │   ├─ NoteActionBar (编辑/删除)
  │   └─ 浮层顶部 padding(top: this.sbh)  ✓ 状态栏让位
  ├─ onClose: 卸载
  └─ onDelete: NoteDao.deleteById + bumpNotesVersion (注: 此处未 grep 到, 待核实)  ⚠ P4.2
```

**路径级问题清单:**
| # | 问题 | 证据 | 风险等级 |
|---|---|---|---|
| P4.1 | NoteDetailMeta 294 行, 包含 ChipTag/ConfDot 渲染逻辑 — 是否分派给局部组件待核实 | NoteDetailMeta.ets | 中 |
| P4.2 | 删除后是否 bump notesVersion 待核实 (notes 列表是否同步刷新依赖此) | NoteDetailOverlay.ets | 高 |
| P4.3 | OVERLAY_MASK_SOLID (80%) vs OVERLAY_MASK (50%, AgentFloatWindow 用): 同场景遮罩色差, 视觉跳跃 | ColorTokens.ets:51-52, 两浮层容器 | 低 (但设计债) |
| P4.4 | 编辑路径: NoteEditForm 4 个受控 TextInput/TextArea, 键盘弹起时浮层是否让位待核实 (Index NONE + 浮层自实现未覆盖此) | NoteEditForm.ets | 中 |

---

### 横切 A · 状态栏高度 (C4 候选的路径证据)

| 页面/组件 | 声明方式 | 响应式? |
|---|---|---|
| HomePage | `@StorageProp('statusBarHeight') sbh` → HomeTopBar `@Prop` | ⚠ Storage 响应, 但 HomeTopBar `@Prop` 不响应 |
| NotesPage | `@StorageProp('statusBarHeight') sbh` → NotesHeader `@Prop` → SubjectHeader `@Prop` | ⚠ 同上, 链式不响应 |
| ReviewPage | `@StorageProp('statusBarHeight') sbh` | ⚠ 是否下传未看, 待核实 |
| ProfilePage | `@StorageProp('statusBarHeight') sbh` | ⚠ 是否下传未看, 待核实 |
| AiSettingsPage | `@StorageProp('statusBarHeight') sbh` → PageHeader `@Prop` | ⚠ 同上, PageHeader 用了 sbh |
| SubjectDetailPage | `@StorageProp('statusBarHeight') sbh` → SubjectHeader `@Prop` | ⚠ 同上 |
| AgentFloatWindow | 直接 `@StorageProp('statusBarHeight') sbh` (不是 @Prop) | ✓ 响应 |
| NoteDetailOverlay | 直接 `@StorageProp('statusBarHeight') sbh` | ✓ 响应 |

**统一诊断**: 仅两个浮层正确用 StorageProp 响应, **6 个页面** 把 StorageProp 读出来后下传给 @Prop 子组件 — AppStorage 变化时**子组件不更新**。这是 C4 候选的路径证据, 优先级比静态清点时评估的更高。

---

### 横切 B · 键盘避让策略

| 组件 | 策略 | 备注 |
|---|---|---|
| Index (全局) | `setKeyboardAvoidMode(NONE)` | Index.ets:31 — 全局禁 |
| AgentFloatWindow | 自实现: onKeyboardHeightChange → @State keyboardHeight, Stack padding bottom | ✓ 浮层内 OK |
| AiSettings.KeyInput | TextInput 受控, 未见键盘处理 | ⚠ 长按输入框键盘弹起可能被浮层/页面截断 |
| AiSettings.EndpointPicker | 同上 | ⚠ |
| NoteEditForm (4 字段) | 未见键盘处理 | ⚠ 详情浮层打开时 + 编辑, 键盘弹起可能遮住输入框 |

**建议**: Index 全局 NONE 是为了让浮层自实现接管 — 但当前实现只覆盖 AgentFloatWindow, 其他三个页面的 TextInput 实际没人处理。可考虑: 让 Index 不全局 NONE, 而要求含 TextInput 的页面单独用 `.expandSafeArea([SafeAreaType.KEYBOARD])` 或自实现; 或统一建一个 KeyboardAvoid 容器 wrapper (类似 C2 的 style-policy 收口位)。

---

### 横切 C · 浮层视觉一致性

| 项 | AgentFloatWindow | NoteDetailOverlay | CameraOverlay |
|---|---|---|---|
| 遮罩色 | OVERLAY_MASK (50% 黑) | OVERLAY_MASK_SOLID (80% 黑) | CAM_MASK 单独定义 |
| 圆角 | R_XL (16) | (未查) | — |
| 入场动画 | sheetOffset/opacity DUR_BASE | (未查) | (未查) |
| 状态栏让位 | ✓ StorageProp | ✓ StorageProp | (未查, 相机通常全屏) |

**P3 视觉一致性**: 三个浮层的遮罩色/圆角/动画时长 / 入场曲线均不一致 — 可视化跳跃。建议 C7 MotionPolicy 收口时一并把遮罩色决策也吸纳入 `(profile → style)` 模块。

---

### 5. 待补充资料 (新增)

§4 待补充资料清单追加:

6. **路径级问题的快速核实**: P2.2 (pendingImageUri 消费点) / P3.1 (loadHistory 持久化) / P4.2 (删除后 bumpNotesVersion) — 这三项决定两条主路径的核心 UX, **应在 C0 真机验收时一并查**, 任何一项失败都构成真机不通过的理由

---

### 6. 结论

体检的"按目录扫"完成了, 但漏掉的"按路径走"层面问题更具 UX 影响。**最关键的发现**: C4 候选 (statusBarHeight 不响应) 在静态扫描时低估了——实际 6 页面都受影响, 浮层则正确 (2 处); 这是路径证据 + 静态证据的合力, 应**提升 C4 优先级**到 Phase A 强候选。

下一轮执行: 真机验收 C0 时, 同步走 §5 第 6 项三项核实 → 三项全过再开 C4 PR, 任何一项失败另立 ticket。

---

### Last updated

2026-09-06 晚

---

## 2. 前端交互五态完整性摸底 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Scope:** MindTrace entry 全 UI 组件的 5 个交互态 (enabled/disabled/loading/empty/error) 覆盖率
> **方法**: grep `@State.*busy/loading/disabled/pending/empty/error/status` + try/catch 模式 + 空态分支, 全机提取
> **配套**: [`frontend-ui-design-inventory-2026-09-06.md`](./frontend-ui-design-inventory-2026-09-06.md) 静态清点 · §1 用户路径走查 路径走查

---

**TL;DR:** 5 态实现严重失衡 — **loading 态只在 2 个文件** (CameraOverlay / AgentFloatWindow), 其他 7+ 个可能 loading 的位置 (save note / save settings / delete / refresh) **全靠 Toast 反馈 + 按钮变灰**, 用户无进度感; **disabled 态几乎不存在** (无 @State disabled), 全部走"按钮变灰"惯例; **error 态 165 处 try/catch 包裹但无结构化错误状态**, 全是 promptAction.showToast 即丢即忘; **empty 态有专门的 *EmptyState 类组件 (4 件)** 是规范亮点; **enabled 是默认, 无显式状态**。

---

### 1. Loading 态 — 全前端只有 2 处真实现

`@State busy` / `@State loading` 全文 grep:

| 文件 | 字段 | 用途 |
|---|---|---|
| `overlays/CameraOverlay/CameraOverlay.ets:23` | `@State busy: boolean` | 拍照中禁用其他按钮 |
| `overlays/AgentFloatWindow/AgentFloatWindow.ets:44` | `@State busy: boolean` + `:45 statusMeta: ChatStatusMeta \| null` | LLM 调用中, 13 步状态文案 (`statusFromStep`) |

**应 loading 却无 loading 态的位置 (高风险):**

| 位置 | 当前行为 | 问题 |
|---|---|---|
| AiSettings save (5 个 picker) | save → `promptAction.showToast` | 用户点完无反馈, 不知道是否在保存 |
| NoteEditForm save | 待核实 (save 路径未 grep) | 同上 |
| NoteDelete | `promptAction.showToast({ message: 'Note deleted', duration: 1200 })` | 删完才提示, 删除中无反馈 |
| HomePage `loadRecentNotes` | `.finally((): void => { ... })` | loading 收口位置, 但 UI 不显示 |
| Profile login (mock) | 立即回调 | mock 不真, 但若改真实现需补 loading |
| HexLogo | animateTo DUR_SLOWEST 1200ms ×3 | 用户点完 1.2 秒内无反馈 |

**判据缺失**: 任何 >200ms 的用户操作都应有 loading 态。`loading-mvp` 风格 = spinner + 禁用交互。

---

### 2. Disabled 态 — 几乎不存在 (全靠"按钮变灰"惯例)

全文 grep `@State.*disabled` **零命中**。

`disabled` 是 ArkUI 组件的内置属性, 但需要有人维护。证据:
- CameraOverlay 唯一可能的地方: `:23 busy` 期间禁用其他按钮 — 需核实是否 `.enabled(!this.busy)`
- AgentFloatWindow:44 busy 期间禁用 send — 需核实

**判据缺失**: 状态变化时 (busy=true) 必须显式 `.enabled(!busy)`, 否则用户可连点造成重入。

---

### 3. Empty 态 — 4 个专门组件, 是规范亮点

| 组件 | 位置 |
|---|---|
| `NotesEmptyState` | `pages/Notes/NotesEmptyState.ets` |
| `SubjectTypeEmpty` | `pages/Notes/SubjectTypeEmpty.ets` |
| `EmptyStateHint` | `overlays/AgentFloatWindow/chat/EmptyStateHint.ets` |
| `SubjectHeader` 内含空态分支 | `pages/Notes/SubjectHeader.ets` |

**亮点**: 这 4 件结构化了"无数据"提示, 没混在 List 组件里。**值得提升为 shared/atoms/EmptyStateHint**, 因为 AgentFloatWindow 内的同名件重复了一份。

**待补空态的位置 (按业务必有):**
- AgentFloatWindow 多会话切到空会话时 — 当前 EmptyStateHint 只在消息列表空, 多会话切换的"选个会话"空态缺失
- ReviewGraphView 知识星系在零笔记时 — 当前 `KnowledgeGalaxyViewModel` 应有 0/0/0 fallback, 待核实
- 相机相册 (album) 无照片时

---

### 4. Error 态 — 165 处 try/catch 但全 Toast 即丢

```
grep -rn '} catch' entry/src/main/ets --include="*.ets" | wc -l
  → 165
```

**主流模式**:
```typescript
try {
  await this.service.x()
  promptAction.showToast({ message: 'OK', duration: 1200 })
} catch (_e) {
  promptAction.showToast({ message: 'Failed', duration: 1500 })  // ← 吞掉 _e
}
```

**问题清单**:
1. **`_e` 被吞** — 没有日志、没有上报、没有结构化错误对象, 出问题后排障无门
2. **无 retry** — 失败后用户只能刷新整个页面或重做操作
3. **无错误状态** — UI 上看不出"上次操作失败", 没有红色横幅或"操作失败 重试"按钮
4. **错误分类缺失** — 网络错 (no network) / LLM 错 (rate limit / context too long) / OCR 错 (image not recognized) / IO 错 (file not found) 应区别处理, 当前全部 1 个 toast

**判据缺失**: 任何失败应有 (错误分类, 用户可读消息, 建议下一步) 三件套, 而不是一行 toast。

---

### 5. Enabled 态 — 默认, 无显式状态

ArkUI 组件默认 enabled, 业务代码不显式维护。**配合 disabled 缺失**, 整个"状态可变性"靠 .enabled 静态属性 + busy @State, 没有体系。

---

### 6. 评级

| 态 | 覆盖 | 评 | 风险 |
|---|---|---|---|
| enabled | 100% (默认) | ✓ | — |
| disabled | ≈10% (仅 2 浮层可能维护) | ✗ | 中 (重入 bug) |
| loading | ≈15% (2 文件真实现) | ✗ | 高 (评委走查会撞上) |
| empty | 60% (4 组件 + 列表 fallback) | △ | 中 (AgentFloatWindow 多会话切空态缺失) |
| error | ≈5% (有 toast, 无结构化) | ✗ | 高 (排障无门, 用户体验差) |

**最该修的 3 项 (不动, 只列)**:
1. **loading 态体系**: 加 @State loading 工具类 + 业务约定 (>200ms 操作必有 loading)
2. **error 态结构化**: ErrorBus module (AppStorage 或 Context) + UI ErrorBanner 组件 + 错误分类 (network / llm / ocr / io / unknown)
3. **disabled 态守门**: 静态检查工具扫描 `.enabled(` 调用面

---

### 7. 待补充资料

§5 第 6 项 (路径级核实) 不变, 新增:
7. **`@State busy` 是否配合 `.enabled(!this.busy)` 的实查**: 在 CameraOverlay / AgentFloatWindow 6 处可能的禁用点上核实; 若缺失, 列入 §8 待办合同 候选列表
8. **错误分类需求**: 真机演示中会出现的错误类型清单 (评审 demo 5 分钟内可能触发的失败), 用于 error 态体系设计

---

### Last updated

2026-09-06 晚

---

## 3. 前端可访问性 (a11y) 摸底 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Scope:** MindTrace entry a11y API 使用 / 焦点管理 / 屏幕阅读器 / 对比度 / 字体缩放
> **方法**: grep `tabIndex / focusable / accessibility / aria / fontScale` + 颜色令牌对比度计算, 全机提取
> **配套**: §4 i18n · [`frontend-ui-design-inventory-2026-09-06.md`](./frontend-ui-design-inventory-2026-09-06.md)

---

**TL;DR:** **项目 a11y 完全空白** — `tabIndex / focusable / accessibilityGroup / accessibilityText / accessibilityDescription / defaultFocus / fontScale` 全部**零引用**; `Image` 没有 `alt` / `objectFit` 描述属性; `Button` 也没有 a11y 适配; 颜色令牌中 **GLASS_8 (8%) / GLASS_10 (10%) / TEXT_3 / TEXT_4 透明度仅 6-10%**, 与 BG_DARK 背景对比度多数 <3:1 (WCAG AA 失败); TextInput 仅有 `placeholder`, 没有 label/aria-label; **盲人/视障用户完全无法使用本应用**。评审 demo 不会查, 但作为完整产品这是必修项。

---

### 1. a11y API 使用现状 (硬数据)

| API | 引用次数 | 备注 |
|---|---|---|
| `accessibilityGroup` | **0** | 屏幕阅读器分组 |
| `accessibilityText` | **0** | 无障碍文本 |
| `accessibilityDescription` | **0** | 无障碍描述 |
| `accessibilityLevel` | **0** | 重要性等级 |
| `tabIndex` | **0** | 键盘 Tab 顺序 |
| `defaultFocus` | **0** | 默认焦点 |
| `focusable` | **0** | 可聚焦 |
| `groupDefaultFocus` | **0** | 分组默认焦点 |
| `aria-*` 属性 | **0** | ARIA 标准 |
| `Image.alt` | **0** | 图片替代文本 |
| `Button.accessibilityText` | **0** | 按钮无障碍文本 |
| `TextInput.label` / `TextInput.aria-label` | **0** | 输入框标签 |
| `fontScale` / `userFontScale` | **0** | 用户字体缩放 |

**结论**: 项目**完全无 a11y 适配**。

---

### 2. 焦点管理 / 键盘导航

#### 2.1 Tab 顺序
- 5 Tab 主页面: Tabs 组件自动接管 (TabBar 自定义后失去默认焦点导航)
- 浮层: 没看到 `focusable(true)` 在入口处显式开启, 浮窗弹出后焦点未明
- 详情浮层 TextInput ×4 (NoteEditForm): 无 focus 自动聚焦, 用户需手动点

#### 2.2 键盘导航 (TV/折叠屏外接键盘)
- 没看到 `onKeyEvent` 处理
- AI 浮窗发送 (回车键): 未在 TextInput 中挂 onSubmit
- 详情浮层保存 (回车键): NoteEditForm 未挂

#### 2.3 屏幕阅读器 (TalkBack / VoiceOver)
- 95% 组件 `accessibilityGroup` 为空, 屏幕阅读器只会读出 Text() 内容
- Image (图标) 全部无 alt, 读屏会跳过或读"图片"
- AppIcon 16 种图标, 都是 SVG 资源, **没附加语义描述** — 屏幕阅读器用户无法理解"主页 / 笔记 / 复习 / 我的"图标

---

### 3. 颜色对比度 (WCAG AA 标准 4.5:1, AAA 7:1)

#### 3.1 令牌 vs BG_DARK (#0A0C10)
| 令牌 | 颜色 | 与 BG_DARK 对比度 | WCAG AA (4.5) | WCAG AAA (7.0) |
|---|---|---|---|---|
| TEXT (#FFFFFF) | 100% 白 | 19.4:1 | ✓ AAA | ✓ AAA |
| TEXT_2 (#B0B3C1) | 浅灰 | 11.6:1 | ✓ AAA | ✓ AAA |
| TEXT_3 (#6B7280) | 中灰 | 4.7:1 | ✓ AA | ✗ |
| TEXT_4 (#4B5563) | 暗灰 | **3.0:1** | **✗ AA 失败** | ✗ |
| GLASS_8 (#08FFFFFF) | 白 8% | ~1.1:1 | ✗ | ✗ |
| GLASS_10 (#1AFFFFFF) | 白 10% | ~1.2:1 | ✗ | ✗ |
| GLASS_14 (#0DFFFFFF) | 白 5% | ~1.05:1 | ✗ | ✗ |
| BORDER (=GLASS_10) | 白 10% | ~1.2:1 | ✗ | ✗ |
| MINT (#5BE3B0) | 薄荷绿 | 12.5:1 | ✓ AAA | ✓ AAA |
| MINT_BORDER (#475BE3B0) | 薄荷 7% | ~1.15:1 | ✗ | ✗ |
| AMBER (#B8A7D9) | 浅紫 | ~9:1 | ✓ AAA | ✓ AAA |
| DANGER (#6B6B6B) | 灰红 | ~3.5:1 | ✗ | ✗ |
| DANGER_BRIGHT (#EF4444) | 亮红 | ~5.5:1 | ✓ AA | ✗ |
| WARNING (#FBBF24) | 琥珀 | 12.4:1 | ✓ AAA | ✓ AAA |

#### 3.2 实际 UI 上的对比度问题
- **TEXT_4 在暗背景上**: 暗灰, 大量用于次要信息 (NotesPage, SubjectHeader, ...), 视觉上"看不清"是常见抱怨
- **GLASS_8/10/14 边框**: 卡片边框用这些, 边框在暗背景上**几乎看不见** — 设计上故意的"无边框感", 但 a11y 视角下用户无法识别可点击区域
- **MINT_BORDER (7% 透明度)**: 渐变类型图标的外圈描边, 在 NotesTab 等场景下不明显

#### 3.3 渐变色对比度
- `linearGradient` 透明色叠加: 透明度渐变叠加后实际颜色难以计算, 但**普遍存在"中间色"对比度问题**

---

### 4. 字体缩放

- ArkUI 系统支持用户字体缩放 (`Display.setUserFontScale` 或 `fontScale` 属性)
- 项目**未做任何响应式字体缩放适配**: F_XS=11 / F_SM=12 / F_BASE=14 是**绝对值**, 用户调到 1.5x 也不会自动放大
- 这意味着**视障 / 老年用户在系统设置放大字体, 本应用不响应**

---

### 5. 评级

| 维度 | 评 | 备注 |
|---|---|---|
| 焦点管理 | ✗ | tabIndex/defaultFocus 0 引用 |
| 键盘导航 | ✗ | onKeyEvent 0 引用 |
| 屏幕阅读器 | ✗ | accessibilityGroup/Text 0 引用 |
| 颜色对比度 | △ | 主文白/浅灰 OK, 暗灰/玻璃色失败 |
| 字体缩放 | ✗ | 字号绝对值, 不响应系统 |
| TouchTarget (44dp) | △ | 大部分按钮 ≥44vp, IconButton 22vp 偏小 |
| 减动效偏好 | n/a | 系统提供, 未显式 opt-in |

---

### 6. 应有但缺的结构

#### 6.1 a11y 工具函数 (建议)
```typescript
// common/.../a11y/A11yText.ets
export class A11yText {
  static icon(name: string): string  // '主页' / '笔记' / '复习' / '我的'
  static button(label: string): string
  static tab(label: string, active: boolean): string
  static error(kind: ErrorKind): string  // 复用 ErrorBus
}
```

#### 6.2 关键组件 a11y 适配 (建议清单)
- **AppIcon**: 加 `accessibilityText: this.name → 中文映射`
- **NoteCard**: 加 `accessibilityGroup(true)` + `accessibilityText('笔记: 标题, 类型, 日期')`
- **NoteCloseButton / IconButton**: 加 `accessibilityText('关闭' / '编辑' / '分享')`
- **TextInput (4 处)**: 加 `label` 或 `accessibilityText` 关联 placeholder
- **TabBar 5 Tab**: 加 `accessibilityText('Tab 1/5, 首页')` 等
- **HomeTopBar / NotesHeader / SubjectHeader**: 在 `accessibilityGroup` 内合并 statusBarHeight 占位区 + 标题区, 避免读屏朗读两次

#### 6.3 颜色令牌增补 (对比度修复)
- 新增 `TEXT_5`: 当前 TEXT_4 (3:1) 提升至 ≥4.5:1 (建议 #8B95A5)
- 玻璃色 (GLASS_*) 保持当前透明度, 但**边框相关场景**用纯色 BG_CARD_OVERLAY 替代
- 给 MINT_BORDER 加 `MINT_BORDER_SOLID` 别名, 关键边框 (可点击卡片) 用实色

#### 6.4 字体缩放适配
- 把硬字号改为 `vp + 字号 token`, 在 `onConfigurationUpdate` (ArkUI) 监听 `fontScale` 重新计算
- 或者用 `fp` (font pixel) 替代 `vp`, 系统会自动缩放

---

### 7. 待补充资料

§14/§15/§16 不变, 新增:
17. **a11y 是否在比赛评审范围**: 鸿蒙高校创新赛有"无障碍"评分维度吗? 若无, 第 6 节仅作长远建议; 若有, 是必补
18. **字体缩放响应是否 demo 必要项**: 真机演示中如果用大字号, 字号不响应会暴露
19. **盲人/低视用户实测**: 若团队有视障成员, 可实测告知优先级

---

### Last updated

2026-09-06 晚

---

## 4. 前端国际化 (i18n) 与文案一致性摸底 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Scope:** MindTrace entry 全 UI 文案硬编码程度 / 中英文一致性 / 本地化框架存在性 / 错误提示风格统一性
> **方法**: grep 中文字面量 + showToast 文案 + resources/ 目录 + i18n 框架引用, 全机提取
> **配套**: §7 错误降级 (本档是其 i18n/文案子面) · §2 交互五态

---

**TL;DR:** **i18n 框架零使用**, 文案 100% 硬编码在 .ets 文件中 (Text("…") 70 处 + promptAction.showToast message 25+ 处); 中英文**直接混杂**在同一处出现 — 失败提示 25 条里有 5 条英文 ("Failed" / "Delete failed" / "Note deleted" / "Failed to load notes" / "搜索功能开发中"), 其余中文; resources/string.json 仅 5 条权限文案, 没分 en/ 等多语言子目录, dark/ 目录是深色模式而非 i18n; **错误提示风格不一** (10-12 字随机长度 / "失败" 与 "Failed" 混用 / 中英混杂无规则), 评委走查会撞上。

---

### 1. i18n 现状硬数据

| 指标 | 数值 | 备注 |
|---|---|---|
| `Text("…")` 含中文字面量 | 70+ | entry 模块 |
| `promptAction.showToast({ message })` 文案 | 25+ | 风格混乱 (见 §4) |
| `resources/base/element/string.json` 条目 | 5 | 仅权限文案 (module_desc, EntryAbility_*, camera_reason, internet_reason) |
| 多语言目录 (`en/` / `zh-rCN/` / `zh-rTW/`) | **0** | 未建立 |
| `@ohos.i18n` 引用 | **0** | 框架未使用 |
| `Intl.NumberFormat` / `Intl.DateTimeFormat` | **0** | 数字/日期本地化未做 |
| `Date.now()` 在 UI 展示 | 多处 | 散落 hard-coded, 未走本地化 |
| `dark/` 目录 | 存在 | ⚠ 不是 i18n, 是深色资源 (color.json / float.json) |

**结论**: 项目当前**无任何 i18n 机制**, 不支持多语言, 评委若用英文 demo 或现场看中文 + 英文混杂的 Toast, 会有明显粗糙感。

---

### 2. 文案硬编码分类

#### 2.1 文本展示 (Text() 70 处) — 影响可见
- 页面标题、Tab 名、按钮文案、空态提示、Tab 名称
- 全部中文, 散落 pages/ / overlays/ 96 文件中
- 改文案需 grep 全仓, **无中心注册**

#### 2.2 提示消息 (showToast 25+ 处) — 影响最大
- 错误提示、加载成功、保存成功、操作成功
- 中英文混杂 (见 §3)
- 风格长度不一 (见 §4)

#### 2.3 长篇文案 (Comments / DocStrings)
- 文件头、@Builder 内说明、// 注释
- 这些不展示给用户, 不影响 i18n

#### 2.4 AI 提示词 (PromptBuilder.ets)
- 这是发给 LLM 的, 不是用户文案, 单独评估

---

### 3. 中英文混杂分析 (25 条 showToast)

| 文案 | 语言 | 长度 | 风格评 |
|---|---|---|---|
| "Failed to load notes" | 英 | 20 字 | ✗ 与其他不统一 |
| "Note deleted" | 英 | 12 字 | ✗ |
| "Delete failed" | 英 | 13 字 | ✗ |
| "搜索功能开发中" | 中 | 8 字 | ⚠ 与 "Failed" 同位置 |
| "笔记加载失败" | 中 | 6 字 | ✓ 简短 |
| "复习数据加载失败" | 中 | 8 字 | ✓ |
| "知识星系加载失败" | 中 | 8 字 | ✓ |
| "删除笔记失败" | 中 | 6 字 | ✓ |
| "已删除笔记" | 中 | 5 字 | ✓ |
| "已删除计划" | 中 | 5 字 | ✓ |
| "已加入实时队列" | 中 | 7 字 | ✓ |
| "已移回复习队列" | 中 | 7 字 | ✓ |
| "已移至实时队列顶部" | 中 | 9 字 | ✓ |
| "请先输入 API Key" | 中 | 8 字 (中英混) | △ |
| "请输入复习计划" | 中 | 7 字 | ✓ |
| "请输入标题" | 中 | 5 字 | ✓ |
| "配置加载失败" | 中 | 6 字 | ✓ |
| "重置失败" | 中 | 4 字 | ✓ |
| "AI 正在回复中..." | 中英 | 8 字 | △ |
| "保存失败：" | 中 | 5 字 (含冒号) | △ 风格不一致 |
| "分享功能暂未开放" | 中 | 9 字 | ✓ |
| "摘要和正文至少填写一项" | 中 | 11 字 | ✓ |
| "笔记仍在加载" | 中 | 6 字 | ✓ |
| "将返回登录页, 随后可选择其他账号。" | 中 | 18 字 | ✓ 长 |
| "退出后可再次使用华为账号登录。" | 中 | 16 字 | ✓ 长 |

**问题分级**:
- ✗ **3-4 条英文**: Failed to load notes / Note deleted / Delete failed — 明显是早期提交后未统一
- △ **冒号 / 省略号**: "保存失败：" / "AI 正在回复中..." — 标点不统一
- △ **混合专有名词**: "请先输入 API Key" / "AI" — 专有名词中英混排可接受但应规则化

---

### 4. 文案风格规范缺口

缺一份**文案 style guide**, 应规定:

#### 4.1 长度规范
- 短消息 (Toast): 4-10 字为佳, 最长不超过 14 字 (含标点)
- 中消息 (空态): 12-20 字
- 长消息 (说明文案): 不限, 但需分段落

#### 4.2 语气规范
- 第二人称 ("请输入..." / "你可以...") vs 被动 ("请先输入")
- 当前混合: "请输入标题" / "摘要和正文至少填写一项" / "笔记仍在加载" — 应统一第二人称

#### 4.3 标点规范
- 句号: 全句末尾是否需要 (短 Toast 通常不带, 长说明需要)
- 冒号: "保存失败：" (带冒号) vs "保存失败" (不带) — 不统一
- 省略号: "AI 正在回复中..." (Toast) vs 用户进度 (loading spinner) — 二选一

#### 4.4 失败/成功语义
- 失败模板: `[动作]失败` / `[动作]失败:[原因]` / `Failed to [动作]`
- 成功模板: `已[动作]` / `[动作]成功`
- 当前 "已删除笔记" / "笔记加载失败" — 动词在前/后不统一

---

### 5. 本地化框架存在性

#### 5.1 resources 目录
```
resources/
├── base/
│   ├── element/        ← string.json (5 条)
│   ├── media/          ← 图标
│   └── profile/        ← main_pages.json
├── dark/               ← 深色资源 (color.json / float.json)
└── rawfile/katex/      ← KaTeX 离线渲染资源
```

**关键缺口**:
- 无 `en/element/string.json` (英语)
- 无 `zh-rCN/`, `zh-rTW/`, `ja/`, etc.
- 即使要 i18n, 也只是把 base/ 的 string.json 复制到 en/, zh-rCN/ 后翻译

#### 5.2 ArkUI i18n 能力 (HK API 24)
- `@ohos.i18n` 模块存在 (Locale, DateTimeFormat, NumberFormat)
- `ResourceManager.getStringSync(context, $r('app.string.xxx').id)` API 可用
- 项目零引用

#### 5.3 当前 string.json 用法 (5 条)
```json
{ "name": "module_desc", "value": "module description" },
{ "name": "EntryAbility_desc", "value": "description" },
{ "name": "EntryAbility_label", "value": "MindTrace" },
{ "name": "camera_reason", "value": "用于拍照识别数学题目" },
{ "name": "internet_reason", "value": "用于访问AI服务进行题目分析" }
```
仅用于 module.json5 权限声明, 未在 UI 中通过 `$r('app.string.xxx')` 调用。

---

### 6. 评级

| 维度 | 评 | 备注 |
|---|---|---|
| i18n 框架 | ✗ | 完全无 |
| 多语言支持 | ✗ | 单语言 (中文) |
| 文案风格统一 | ✗ | 中英混杂, 长度不一 |
| 文案集中管理 | ✗ | 散落 96 文件 |
| 错误提示规范 | ✗ | 见 frontend-error-handling |
| 日期/数字本地化 | ✗ | Date.now() 直接用 |
| 占位符 (i18n 兼容性) | ✗ | 硬编码字符串无法插值 |

---

### 7. 应有但缺的结构

#### 7.1 I18nStrings 中心 (建议)
```typescript
// common/.../i18n/Strings.ets
export class Strings {
  static loadFailedNotes(): string  // 集中管理
  static noteDeleted(): string
  static searchComing(): string
  static apiKeyRequired(): string
  // ...
}
// 后续加 getString() wrapper 走 ResourceManager
```

#### 7.2 Toast 文案模板 (建议)
```
[动作]+[状态]: 动作=加载笔记/删除笔记/保存/..., 状态=成功/失败/进行中
成功: 已[动作] (例: 已删除笔记)
失败: [动作]+失败 (例: 笔记加载失败)  // 不带冒号
进行中: [动作]+中... (例: AI 正在回复中...)
```

#### 7.3 错误提示分级 (与 ErrorBus 配合, 见 frontend-error-handling)
- info: 蓝色, 短提示 (1.5s)
- warn: 琥珀色, 含操作建议 (3s)
- error: 红色, 含"重试"按钮 (不自动消失)

#### 7.4 评审前最低修复 (建议做)
1. **统一 3-4 条英文 Toast → 中文** (5 分钟)
2. **去掉 "保存失败：" 末尾冒号** (5 分钟)
3. **抽出最常用的 10 条 toast 到 I18nStrings** (半小时)
4. **错误提示改成 ErrorBus + ErrorBanner** (参考 frontend-error-handling §6)

---

### 8. 待补充资料

§5/§6/§7/§8/§9/§10/§11 不变, 新增:
12. **真机演示是否需要英文版**: 若评委来自海外或现场要求英文, i18n 是必修; 若仅中文 demo, 第 7.4 节"评审前最低修复"足够
13. **是否计划长期 i18n**: 若只是中文 demo, 抽出 I18nStrings 即可; 若计划双语, 必须先建 en/ 目录骨架

---

### Last updated

2026-09-06 晚

---

## 5. 前端性能与资源摸底 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Scope:** MindTrace entry 列表虚拟化 / Webview 内存峰值 / 图片懒加载 / 缓存策略
> **方法**: grep `LazyForEach / ForEach / Web / WebviewController / cacheKey`, 全机提取
> **配套**: [`frontend-ui-design-inventory-2026-09-06.md`](./frontend-ui-design-inventory-2026-09-06.md) 三维档案 · §6 持久化 UiDataCacheService

---

**TL;DR:** 性能是项目**已被部分治理但暗藏峰值风险**的领域 — **LazyForEach 仅 3 处** (AgentMessageList/SubjectNoteList/FormulaSplitRenderer), 31 处 ForEach 未虚拟化 (HomeRecentNotes/NotesList 等); **MathTextRenderer KaTeX Webview 缓存做得好** (LRU 64 条 / TTL 10min, 评审亮点) 但 Webview 实例数上限无强制 — 详情浮层 6 renderer + MarkdownRenderer 7 块 + ChatBubble 同时打开可能引发 7+ 个 Webview; 笔记列表缓存靠 UiDataCacheService 进程级 LRU, **失效机制与 AppStorage 双轨制** (`invalidateNotesSnapshots` vs `notesVersion bump`, 谁触发谁不明)。

---

### 1. 列表虚拟化覆盖

| 组件 | 用法 | 评 |
|---|---|---|
| `NotesList.ets` (Notes Tab) | `List()` 容器 + `ForEach()` 长列表 | ⚠ List 是惰性容器, 但 ForEach 内是即时构建 (vs LazyForEach) — 改 LazyForEach 可显著提升长笔记场景 |
| `SubjectNoteList.ets` (学科详情) | `LazyForEach` + ListItem | ✓ 已虚拟化 |
| `HomeRecentNotes.ets` | `ForEach()` NoteCard ×N | ⚠ 最近笔记数量小, 但列表增长后风险 |
| `AgentMessageList.ets` (AI 浮窗) | `LazyForEach` ChatBubble ×N | ✓ 已虚拟化 (聊天滚动核心) |
| `FormulaSplitRenderer` (分子) | `LazyForEach` MathTextRenderer ×N | ✓ 范本: 用 IDataSource 控制 |
| `MarkdownRenderer` (分子) | `ForEach(this.visibleBlocks(), ...)` 渐进展开 | △ 不是 LazyForEach, 但 visibleBlockCount 控制展开量 — 设计 OK, 命名混淆 |
| `ReviewGraphView` (星系) | ForEach ×11 | ⚠ 星系渲染 (1880 行) 整体自绘, 无虚拟化概念 |

**长列表未虚拟化清单 (按风险)**:
- `HomeRecentNotes` / `NotesList`: 笔记多时 (10+ 条) 全渲染, NoteCard 含 MathPreviewText 进一步叠加成本
- `NotesSummaryPanel` / `SubjectGrid`: 学科 3-6 个 + 卡片列表, 风险中
- `SubjectCard`: 含 MathPreviewText (公式预览) ×N, 风险中

---

### 2. Webview 内存峰值

#### 2.1 MathTextRenderer 缓存现状 (亮点)
`shared/atoms/MathTextRenderer.ets`:
- 模块级 LRU: `MATH_RENDER_CACHE` 64 条 / TTL 10 min / 600k chars 上限 (`:44-58`)
- 渲染: 三模式管线 (katex / native / plainFallback), `setTimeout` 分槽延迟 (note profile)
- 缓存键: `profile | version | forceDisplay | contentHash(markdown)`
- **评测亮点**: 这是项目唯一一处"Webview 渲染 + 缓存"组合的成熟实现, 是 W3 公式渲染计划的资产

#### 2.2 Webview 实例数峰值风险
| 场景 | Webview 实例数估算 |
|---|---|
| AI 浮窗 1 条消息 | 1 个 (ChatBubble → MarkdownRenderer) |
| AI 浮窗 1 条含公式消息 | N 个 (FormulaSplitRenderer LazyForEach, 每个 block 1 个) |
| 笔记详情 1 屏 | 6 renderer × 1 MarkdownRenderer + DetailSection × N → 7+ 个 |
| 笔记详情 + AI 浮窗后台 | 7 + 1 = 8+ 个 |
| ReviewGraphView (星系页) | 0 个 (纯 Canvas, OK) |
| HomePage 首页 | 0 个 (HeroBanner 自绘, OK) |

**风险点**: 笔记详情 + AI 浮窗同时打开 (评审 demo 常见) → 8+ 个 Webview 在 ArkTS 进程内, **每个 Webview 占用 JS 引擎 + 渲染线程**。HarmonyOS 6.1 单进程 Webview 上限需查 SDK d.ts (常见 6-8 个)。

#### 2.3 Webview 内存控制现状
- MathTextRenderer 有模块级 LRU 缓存 (HTML 字符串缓存), 但**Webview 实例本身没有限制** — 每个 MathTextRenderer struct 持有自己的 WebviewController
- 没有"Webview 实例池", 每次 MathTextRenderer 创建就 new 一个 Webview
- aboutToDisappear 时**没有显式销毁 Webview**: 看 `MathTextRenderer.ets:233-235`, 只有 `renderSeq += 1`, WebviewController 由 ArkUI 框架 GC

**判据缺失**: Webview 数上限 + 跨组件共享池 (类似 OkHttp 连接池)

---

### 3. 图片与资源

#### 3.1 Image 懒加载
- `Image($r('app.media.ic_xxx'))` 是**资源引用**, ArkUI 内置按需加载, 无需手动懒加载
- `ImagePreviewBar` (AI 浮窗预览图) 用 `imagePreview: string` 持有 uri, 单图
- 相机拍照后 `ImageUriResolver.resolve` 复制到沙箱, 已优化
- **唯一可能 OOM 风险**: 评审 demo 连续拍照 + 多次 AI 浮窗不释放, 沙箱图片累积

#### 3.2 字体与外部资源
- `rawfile/katex/fonts/`: KaTeX 字体离线包 (评审亮点, W3 公式计划落地)
- `rawfile/render.html`: KaTeX 渲染页 (440 行), 单文件
- 这两件是 Webview 内加载, 受 Webview 数影响

#### 3.3 笔记卡片 MathPreviewText 渲染成本
- `NoteCard` 每张 = MathPreviewText (单行预览) + 渐变图标 + 文本
- MathPreviewText 内部含 MathTextRenderer (有公式时)
- **列表 20 条笔记全含公式** = 20 个 MathTextRenderer 实例 = 20 个潜在 Webview (受 NoteCard 复用策略影响, 滚动时可能复用)

---

### 4. 缓存层盘点 (与 persistence 文档呼应)

#### 4.1 模块级缓存
| 缓存 | 位置 | 范围 | 评 |
|---|---|---|---|
| MathTextRenderer LRU | `shared/atoms/MathTextRenderer.ets:44` | 64 条渲染 HTML | ✓ 范本 |
| UiDataCacheService detail | `services/UiDataCacheService.ets:124` | DetailCacheEntry[] | ✓ LRU + trim |
| UiDataCacheService snapshot | UiDataCacheService 内 | 笔记列表快照 | ✓ |
| PreloadQueue | UiDataCacheService | 预加载队列 | △ 与 detailEntries 关系不清 |

#### 4.2 失效机制
- **MathTextRenderer**: 缓存键是内容哈希 + profile, 内容变则自动失效
- **UiDataCacheService**: 
  - `invalidateNotesSnapshots()` 静态方法, 显式触发 (AiService.buildNoteDao 后调用一次)
  - 但**触发点 grep 不到完整覆盖**: NotesPage / HomePage / ReviewGraphView 通过 `AppStorage.get<number>('notesVersion')` 监听 (onPageShow 重读)
- **双轨制嫌疑**: in-memory 失效 + AppStorage notesVersion bump 谁触发谁, 路径不清

---

### 5. 长任务 / 同步阻塞

| 位置 | 风险 |
|---|---|
| `KnowledgeGalaxyViewModel:790 行` (数据建模) | onPageShow 时全量计算星系数据, **无后台线程** |
| `HexLogo.ets` animateTo ×3 (DUR_SLOWEST 1200ms ×2) | 主线程串行, 期间无法响应 |
| `MathTextRenderer.ets:226` renderSeq 保护 | ✓ 已有竞态保护 |
| `DatabaseHelper.getStore()` (RDB) | 同步, 入口调用无异步包装, 启动时阻塞 |
| `ChatSession.ets:35` preferences.getPreferences | 异步, 在 aboutToAppear 中调用, 无 await error 处理 |

---

### 6. 启动性能

| 阶段 | 耗时估计 | 优化点 |
|---|---|---|
| EntryAbility.onCreate | ReminderFacade 注入 + 状态栏读取 + 数据库 init | ✓ 已是同步, 无明显问题 |
| pages/Index aboutToAppear | setKeyboardAvoidMode | ✓ 单调用 |
| HomePage onPageShow | loadRecentNotes → read all notes | ⚠ 全量加载, 大笔记库时风险 |
| ReviewGraphView onPageShow | KnowledgeGalaxyViewModel.build() | ⚠ 全量构建, 1880 行渲染组件 |
| AgentFloatWindow aboutToAppear | loadHistory + initKeyboard | ✓ 异步 + 监听 |

---

### 7. 评级

| 维度 | 评 | 备注 |
|---|---|---|
| 列表虚拟化 | △ | LazyForEach 3 处, ForEach 31 处 |
| 渲染缓存 | ✓ | MathTextRenderer LRU 是亮点 |
| Webview 内存 | ⚠ | 无实例上限, 评审 demo 高峰 8+ 个 |
| 图片加载 | ✓ | 资源引用内置优化 |
| 失效机制 | △ | 双轨制路径不清 |
| 启动性能 | △ | HomePage/ReviewGraphView 全量加载 |
| 长任务阻塞 | △ | 主线程 animateTo ×3 (HexLogo) |

---

### 8. 应有但缺的结构

#### 8.1 列表虚拟化清单
- NotesList → LazyForEach (高优先, 长列表风险)
- HomeRecentNotes → LazyForEach (中优先, 笔记多时)
- NotesSummaryPanel / SubjectGrid → List 容器 (中)
- ReviewGraphView 不需要 (Canvas 自绘, 范围固定)

#### 8.2 Webview 实例上限 (建议)
- 在 MathTextRenderer 中加**实例池**: `MathWebviewPool` 单例, acquire/release 模式, 限制并发 ≤3
- 或在 NoteDetailOverlay 关闭时主动 `controller.destroy()`
- 查 SDK d.ts: HarmonyOS 6.1 Webview 单进程上限, 是否原生提供

#### 8.3 长任务异步化
- KnowledgeGalaxyViewModel.build() 挪到 worker thread (ArkTS TaskPool)
- HexLogo animateTo ×3 拆为更细粒度或加 progress hint

#### 8.4 启动分片
- HomePage onPageShow 全量加载改为分页 (前 20 条 + 滚动加载)
- ReviewGraphView 同理

---

### 9. 待补充资料

§12/§13 不变, 新增:
14. **Webview 上限 (HarmonyOS 6.1)**: SDK d.ts 是否有原生限制; 若有, 是否达到
15. **AI 浮窗 + 详情浮窗同开场景**: 真机演示中是否会出现, 决定 Webview 优化的优先级
16. **大笔记库场景 (100+/500+ 笔记)**: 启动 + HomePage 加载是否卡顿

---

### Last updated

2026-09-06 晚

---

## 6. 前端状态序列化与持久化摸底 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Scope:** MindTrace entry 状态持久化 4 层 (AppStorage / preferences / RDB / in-memory) 的覆盖面与生命周期
> **方法**: grep `AppStorage.*setOrCreate/get/set` / `preferences.getPreferences` / `DatabaseHelper.getStore` / `UiDataCacheService`, 全机提取
> **配套**: §1 用户路径走查 §C4 候选 · 本档聚焦于"什么状态存在哪里、生命周期谁管"

---

**TL;DR:** 4 层持久化面**边界还算清晰**, 但有 3 处问题: ① AppStorage 当**全局事件总线**用 (`notesVersion` 6 文件手工 bump/watch) — 错位, 应改用响应式; ② in-memory 的 UiDataCacheService 静态缓存 + `invalidateNotesSnapshots` 与 AppStorage notesVersion 双轨制, 关系不清 (谁触发谁?); ③ preferences 3 个 store (chat_history / kit_reminder_map / profile_auth) 各自命名但**没有 store 名中心登记**, 后续新增容易撞名。

---

### 1. 4 层持久化全景

#### 1.1 AppStorage (全局 in-memory, 进程生命周期)
| 键 | 类型 | 写者 | 读者 | 备注 |
|---|---|---|---|---|
| `notesVersion` | number | 6 文件手工 `setOrCreate(v+1)` | 6 文件手工 `get` in onPageShow | ⚠ C4 候选: 当事件总线用 |
| `reminderFacade` | ReminderFacadeImpl | EntryAbility.onCreate (组合根) | ReminderFacadeImpl.getReminderFacade() | ✓ 单点注入 |
| `statusBarHeight` | number | EntryAbility.onCreate | 6 页面 `@StorageProp` + 2 浮层 `@StorageProp` | ✓ 单点种, 6 页面下传 @Prop 是问题 |

#### 1.2 preferences (KV 持久化, 跨进程)
| store 名 | 位置 | 用途 | 备注 |
|---|---|---|---|
| `kit_reminder_map` (隐式常量) | `entry/kit/ReminderFacadeImpl.ets:53` | unitId → reminderId 映射 | ⚠ store 名是变量, 不在中心登记 |
| `chat_history` (字符串字面量) | `overlays/AgentFloatWindow/chat/ChatSession.ets:35` | 多会话对话历史 | ⚠ store 名是字面量, 同上 |
| `profile_auth` (字符串字面量) | `viewmodels/ProfileAuthViewModel.ets:98` | mock 登录态 | ⚠ 同上 |

**问题**: 3 个 store 名散落各文件, 中心无登记 (建议: `common/.../storage/StorageNames.ets`)。

#### 1.3 RDB (关系数据库, MindTrace.db, schema v4)
| 表 | 用途 | DAOs |
|---|---|---|
| knowledge_unit (24 列, SM-2 字段) | 笔记 | NoteDao |
| study_plan | 学习计划 | StudyPlanDao |
| chat_message | 聊天消息 (与 preferences chat_history 重叠?) | ChatMessageDao |
| agent_memory | 智能体记忆 | AgentMemoryDao |

**重叠嫌疑**: `chat_message` (RDB) 与 `chat_history` (preferences) 两套聊天持久化并存 — 职责不清, 哪条管什么?

#### 1.4 in-memory (UiDataCacheService, 进程生命周期, 静态缓存)
- `detailEntries: DetailCacheEntry[]` (笔记详情渲染缓存, LRU 淘汰)
- `invalidateNotesSnapshots()` (清笔记快照, 触发点: AiService.buildNoteDao 后)
- `PreloadQueue` (预加载队列)

**双轨制嫌疑**: `UiDataCacheService.invalidateNotesSnapshots()` (in-memory) 与 `AppStorage.setOrCreate('notesVersion', v+1)` (全局) 在 AiService.buildNoteDao 同一行调用 — 谁触发谁刷新? 看了三处才确认两个都触发, 关系不清。

---

### 2. 状态归属与生命周期

| 状态类 | 持久化层 | 生命周期 | 触发回收 |
|---|---|---|---|
| 笔记数据 | RDB (knowledge_unit) | 永久 | 显式 delete |
| 对话历史 | preferences (chat_history) | 永久 | 显式清空 |
| 智能体记忆 | RDB (agent_memory) + preferences(?) | 永久 | 显式清空 |
| 学习计划 | RDB (study_plan) | 永久 | 显式 delete |
| 提醒映射 | preferences (kit_reminder_map) | 永久 | 取消提醒时删 |
| Mock 登录 | preferences (profile_auth) | 永久 | mock 重置 |
| 状态栏高度 | AppStorage | 进程 | 进程退出 |
| ReminderFacade | AppStorage | 进程 | 进程退出 |
| 笔记版本号 | AppStorage | 进程 | 进程退出 |
| 笔记列表快照 | UiDataCacheService | 进程 (LRU 淘汰) | invalidateNotesSnapshots / LRU |
| 笔记详情渲染 | UiDataCacheService | 进程 (LRU) | trimDetailCache |
| 当前会话列表 | AgentFloatWindow @State | 进程 (in-memory) | 浮窗卸载 (190ms 后) |
| AI 输入草稿 | AgentFloatWindow @State inputText | 进程 | 浮窗卸载即丢 ⚠ |

**⚠ 发现**: AI 输入草稿 (inputText) 关闭浮窗后即丢 — 用户"输了半句话误触关闭"时无任何恢复路径, P3.1 已记。

---

### 3. 评级

| 层 | 评 | 备注 |
|---|---|---|
| 持久化分层清晰度 | △ | 4 层各有职责, 但聊天持久化两套并存 |
| 跨层一致性 | ✗ | in-memory 失效 + AppStorage bump 双轨制, 关系不清 |
| 状态栏高度 (AppStorage) | △ | 单点种 OK, 6 页面下传 @Prop 是 C4 |
| ReminderFacade (AppStorage) | ✓ | 组合根单点注入 |
| notesVersion (AppStorage) | ✗ | 当事件总线用, 应改 @StorageProp 响应式 |
| preferences store 名 | ✗ | 散落无中心, 撞名风险 |
| in-memory 缓存 | ✓ | UiDataCacheService 单例 + LRU 清晰 |
| 输入草稿持久化 | ✗ | inputText 关闭即丢, 用户体验差 |

---

### 4. 应有但缺的结构

#### 4.1 StorageNames 中心登记 (建议)
```typescript
// common/.../storage/StorageNames.ets
export const PREF_REMINDER_MAP = 'kit_reminder_map';
export const PREF_CHAT_HISTORY = 'chat_history';
export const PREF_PROFILE_AUTH = 'profile_auth';
export const APP_KEY_NOTES_VERSION = 'notesVersion';
export const APP_KEY_REMINDER_FACADE = 'reminderFacade';
export const APP_KEY_STATUS_BAR_HEIGHT = 'statusBarHeight';
```

#### 4.2 C4 候选 (statusBarHeight + notesVersion)
详见 §8 待办合同 §1 C4 — 已升级到 Phase A 强候选 (路径走查证据)。

#### 4.3 输入草稿持久化 (新候选建议 C8)
AgentFloatWindow.inputText 在 190ms 卸载后即丢 — 建议持久化到 preferences 的 `chat_draft:<sid>` 键, 重新打开浮窗时自动恢复。可作为后续单独候选。

#### 4.4 聊天持久化两套并存 (新候选建议 C9)
RDB chat_message + preferences chat_history 各自管什么? 待核实职责分工, 若重叠 → 合并; 若分工 → 写 ADR 明确边界。

---

### 5. 与现有契约的冲突

- **不冲突**: 与 spec 012 / 014 / CONTEXT.md 无明确接口
- **机会**: C4 (AppStorage 响应式) 与 frontend-healthcheck-plan §1 C4 是同一项, 优先级 Phase A 强候选
- **机会**: C8 输入草稿是新发现, 可独立 PR

---

### 6. 待补充资料

§5 第 6-10 项不变, 新增:
11. **preferences store 名列表**: 我 grep 的 3 个是否完整 (含未引用的 store 名)
12. **RDB chat_message 表实际使用**: 是否还在写, 还是已被 preferences 取代 — 决定 C9 是否需要治理
13. **UiDataCacheService 与 AppStorage notesVersion 调用先后顺序**: 决定两者谁触发谁刷新

---

### Last updated

2026-09-06 晚

---

## 7. 前端错误降级与边界摸底 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Scope:** MindTrace entry 错误处理结构 + 降级路径 + 用户反馈
> **方法**: grep `try/catch` + `throw` + `console/hilog/Logger` + 错误字面量, 全机提取
> **配套**: §2 交互五态 五态摸底 (本档是其 error 态深挖)

---

**TL;DR:** 错误处理"两极分化" — **99 处 catch, 18 处有结构化日志 (≈18%), 81 处直接吞 `_e`**; 错误分类**完全不存在**, 全是字符串 Toast 即丢即忘; 用户感知只有 Toast 一条路, 没有"重试"按钮、没有红色错误横幅、没有分级 (网络错 vs LLM 错 vs IO 错) 区分; **降级路径稀缺**: 仅 LlmClient `extractContent` 文本为空回退 `reasoning_content` 算有降级 (但可能把思维链当正文), 其余 catch 一律 Toast 离场。

---

### 1. 错误处理规模

| 指标 | 数值 | 备注 |
|---|---|---|
| `try { } catch` 出现处 | 99 | entry 模块 |
| 有结构化日志 (`console.error` / `hilog.error` / `Logger`) | 18 | ≈18% |
| 直接吞 `_e` (无日志) | ≈81 | 82% |
| 错误字面量 (中英文错误消息) | 15+ | 散落各页, 风格不一致 |
| Error 枚举 / 分类常量 | **0** | 无 |
| Retry 按钮 / 重试入口 | **0** | 用户失败后只能重做操作 |

---

### 2. 错误分类缺失 (按业务失败源)

#### 2.1 网络失败
- LLM 调用失败 (api.deepseek.com) → LlmClient: throw 普通 Error / LlmError, 上层 Toast 提示
- OCR 服务失败 (127.0.0.1:8000) → OcrTool: throw + retry 2 次, 上层 Toast
- **没有任何"离线"判断**: 移动网络/Wi-Fi 切换无感知, 失败原因无法定位

#### 2.2 LLM 错误
- API key 错 (401) / 限流 (429) / 服务端 (5xx) → 一律 Toast "Failed"
- **context too long / 输出截断** 未单独提示
- DeepSeek 思考模式失败 → reasoning_content 路径被 fallback 用, **可能把思维链当正文返回** (C2 已知坑)

#### 2.3 OCR 错误
- 图片无法识别 (空文本 / 错误) → OcrTool throw "未获取到照片"
- **未告诉用户"为什么"**: 光线差 / 角度偏 / 公式太复杂 — 用户不知道是图的问题还是服务的问题

#### 2.4 IO 错误
- NoteDao 写失败 (磁盘满 / 权限) → Toast "保存失败"
- imageUri 复制失败 (ImageUriResolver) → throw, 上层 Toast "图片准备失败"
- ChatSession preferences 写失败 → try/catch 包裹, 不影响 UI

#### 2.5 服务不可用
- OCR 服务未启动 (port 8000 无响应) → OcrTool retry 后失败, Toast 含糊
- **没有"启动 OCR 服务"的引导**: 用户不知道有 `tools/ocr_service/start.bat`

---

### 3. 降级路径盘点

#### 3.1 真有降级的 2 处

| 位置 | 降级行为 | 风险 |
|---|---|---|
| `common/.../llm/LlmClient.ets:180-184` extractContent | 文本空 → 回退 `reasoning_content` | ⚠ 思维链当正文 (C2 已知坑) |
| `common/.../llm/LlmClient.ets:293-301` 首字节超时 | 8s 内无首字节 → 抛 STREAM_FAILED | ⚠ 用户等 8s 才反馈, 期间无进度 |

#### 3.2 缺降级的高风险点

| 场景 | 当前 | 应有 |
|---|---|---|
| LLM 限流 (429) | Toast "Failed" | "请求过于频繁, X 秒后重试" + 自动 retry with backoff |
| OCR 识别空 | Toast "未获取到照片" | "光线可能不足, 换个角度重试" + 重新拍照快捷按钮 |
| RDB 写失败 | Toast "保存失败" | "存储空间不足, 请清理后再试" + 错误日志 |
| 网络断开 | Toast "Failed" | 顶部红色横幅 + 网络恢复自动 retry |
| API key 失效 | Toast "Failed" | "API Key 失效, 点击跳转设置" |

---

### 4. 错误反馈现状样本 (15 处中抽 5)

| 位置 | 字面量 |
|---|---|
| `CameraOverlay.ets:94` | "未获取到照片" |
| `CameraOverlay.ets:118` | "未选择图片" |
| `NoteDetailOverlay.ets:371` | "摘要和正文至少填写一项" (校验) |
| `NoteDetailOverlay.ets:550` | "分享功能暂未开放" (feature flag) |
| `AiSettingsPage.ets:46` | "已保存" / "保存失败" |
| `AiSettingsPage.ets:61` | "请先输入 API Key" (前置校验) |
| `NotesPage.ets:54` | "笔记加载失败" |
| `NotesPage.ets:75` | "搜索功能开发中" |

**问题**: 中英文混杂 (Failed / 失败 / 加载失败), 风格不统一, 长度不规整 (8-12 字), 没用 i18n (后述)。

---

### 5. 评级

| 维度 | 评 | 备注 |
|---|---|---|
| 错误捕获覆盖率 | ✓ (99 处) | 业务代码几乎全 wrap |
| 结构化日志 | ✗ (18%) | 多数 catch 吞 `_e` |
| 错误分类 | ✗ (0) | 缺业务级 ErrorKind 枚举 |
| 用户感知分级 | ✗ (全 Toast) | 没有 ErrorBanner / 重试按钮 / 分级提示 |
| 降级路径 | △ (极少) | LlmClient 2 处, 业务侧零 |
| 错误字面量风格 | △ | 中英混杂, 待 i18n 收口 |
| Retry 自动恢复 | ✗ (0) | 失败需用户手动重做 |

---

### 6. 应有但缺的结构

#### 6.1 ErrorKind 枚举 (建议)
```typescript
// common/.../errors/AppError.ets
export enum ErrorKind {
  NETWORK_OFFLINE = 'network_offline',
  NETWORK_TIMEOUT = 'network_timeout',
  LLM_AUTH_FAIL = 'llm_auth_fail',
  LLM_RATE_LIMIT = 'llm_rate_limit',
  LLM_CONTEXT_TOO_LONG = 'llm_context_too_long',
  LLM_OUTPUT_INVALID = 'llm_output_invalid',
  OCR_NOT_RECOGNIZED = 'ocr_not_recognized',
  OCR_SERVICE_DOWN = 'ocr_service_down',
  RDB_WRITE_FAIL = 'rdb_write_fail',
  RDB_READ_FAIL = 'rdb_read_fail',
  FILE_NOT_FOUND = 'file_not_found',
  UNKNOWN = 'unknown',
}
```

#### 6.2 ErrorBus (建议)
```typescript
// common/.../errors/ErrorBus.ets
class ErrorBus {
  publish(error: AppError)  // 顶层 UI 监听, 弹 ErrorBanner
  subscribe(cb) → unsubscribe
}
```

#### 6.3 ErrorBanner 组件 (建议)
- 顶部固定显示, 区分 severity (info / warn / error)
- 文案模板: `[图标] [分类名] [用户可读消息] [重试/查看详情 按钮]`
- 自动消失 (3-5s) 或用户手动关闭

#### 6.4 LlmClient 改造 (建议)
- 把 12 种 LlmErrorKind 映射到 ErrorKind
- 加 retry-with-backoff (1s / 2s / 4s)
- 401/429 触发自动跳设置页

---

### 7. 与现有契约的冲突

- **不冲突**: 与 spec 012 / ADR-0008-0012 / CONTEXT.md 无明确接口
- **机会**: ErrorBus 改造时可与 KnowledgeUnit 复用 CaptureGraphError 的结构 (kind/message/step/retriable/cause)

---

### 8. 待补充资料

§5 第 6/7 项不变, 新增:
9. **真机演示中可能触发的失败清单**: 评委会演示时若遇失败, 当前 Toast 含糊到什么程度? (用于 ErrorBanner 文案设计)
10. **OCR 服务是否在真机演示中启动**: `tools/ocr_service/start.bat` 在 demo 前是否会被执行? 若不, OcrTool 失败是必然

---

### Last updated

2026-09-06 晚

---

## 8. 前端体检后续待办合同 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Status:** 待办合同 — 等补充资料后逐项执行, 当前**不动任何代码**
> **Source**: [`frontend-component-audit-2026-09-06.md`](./frontend-component-audit-2026-09-06.md) 分层裁决 + [`frontend-ui-design-inventory-2026-09-06.md`](./frontend-ui-design-inventory-2026-09-06.md) 三维档案 + HTML 升级版报告(`architecture-review-20260906-225531-upgrade.html`)

---

### 0. 体检结论速读 (TL;DR)

| 轴 | 判定 | 证据 |
|---|---|---|
| spec 012 分层 | 骨架合规 ≈75% | 2 硬违例 (MathTextRenderer 假原子 / MathPreviewText atom→atom) + overlays 43 组件规范真空 |
| React 理念 | 数据流高度符合 (单向下/受控), 组件理念 3 处偏离 (index-key ×3 / AppStorage 手工总线 ×6 / 胖容器) | grep + 实读 |
| 设计/动效 | 静态半边健康, 动态半边半接入 | animateTo 5 文件 (3 令牌合规, 2 绕过), 111 处字面量 |
| 死令牌 | LH_HEADING / SUCCESS / WARNING 真死 | 96 文件 + common 侧零消费者 |
| OcrNode 断链 | **已修复** (b60f491, TDD 绿) | agents module, 未 push |

---

### 1. 待办矩阵 (7 项候选, 按强度 + 触发条件排序)

> 符号: ✅已落地 / ⏸待资料 / 🔒锁定需裁决 / 🚫驳回不动

#### ✅ C0 · OcrNode payload 断链修复 (已完成)
- **位置**: `bugfix/ocrnode-payload-break` (73c84cb 红 + b60f491 绿)
- **触发**: 交接文档 §2 真机未验 TBD
- **状态**: TDD 已转绿, hvigor assembleHsp BUILD SUCCESSFUL, lint 0 error, 待 push + 真机验收

---

#### ⏸ C1 · MathTextRenderer 重分层 + 缓存/调度外移
- **Strength**: Strong
- **涉及**: `shared/atoms/MathTextRenderer.ets` (536 行)
- **触发条件 (待补充)**:
  - [ ] spec 012 后续 PR 计划批文
  - [ ] 决定缓存淘汰策略 (LRU 64 + TTL 10min 维持 / 改 LFU / 引入 persistent store)
  - [ ] 决定 defer 分槽策略 (note profile 24ms+slot×22ms 维持 / 改成 IntersectionObserver)
- **执行路径**: `grill-with-docs` → `to-spec` → `implement(tdd)`
- **判据**: struct 缩到 ~200 行; RenderCache / DeferScheduler 独立 module + Node 守门测试 ≥5 例; 三个直连消费者零行为变化
- **依赖**: 无前置 PR
- **风险**: 中 (接口稳定, 内部重组)

---

#### ⏸ C2 · 公式样式 profile 四态收口为 style-policy module
- **Strength**: Strong
- **涉及**: MathTextRenderer / MarkdownRenderer / FormulaSplitRenderer (三处 rgba 同值异处)
- **触发条件 (待补充)**:
  - [ ] 是否同步进公式组件的 React 风格拆分 (pre-design)
  - [ ] 决定 style-policy module 路径 (common/ 下 vs agents/ 下, ADR-0009 边界)
  - [ ] 决定 rgba 是否上 Token (ColorTokens 新增 profile 色组) 或保持 literals 但聚合
- **执行路径**: `grill-with-docs` → `to-spec` → `implement(tdd)`
- **判据**: 三公式组件零 rgba 字面量 (硬编码搬到 style-policy); ColorTokens 字面量总量 <50; 行为零变化
- **依赖**: 无前置 PR
- **风险**: 低 (纯静态资源搬运)

---

#### ⏸ C7 · MotionPolicy 动效收口 (Strong · 升级版新加)
- **Strength**: Strong (与 C1 并列)
- **涉及**: 新增 `common/.../motion/MotionPolicy.ets`; 受益方 ReviewGraphView / GradientRing / FloatingButton / AiTabButton / HexLogo / AgentFloatWindow + 全部未来动效件
- **触发条件 (待补充)**:
  - [ ] **裁决呼吸周期**: 令牌 DUR_BREATH=3000 vs 实现 ≈1500, 哪个为准 (设计裁决)
  - [ ] **裁决 ReviewGraphView 8 处硬编码时长迁移目标**: 180/220/240 → DUR_INSTANT(80) / FAST(150) / BASE(250) 中哪档
  - [ ] 决定 FloatingButton / AiTabButton 按压反馈 scope (scale + shadow / 仅 scale / 仅 shadow)
  - [ ] 决定 animateTo 包装器命名 (animateToMotion / animate / useMotion) 与签名
- **执行路径**: `grill-with-docs` → `to-spec` → `implement(tdd)`
- **判据**: 6 文件硬编码收敛为 1 文件; HexLogo 等 3 令牌合规件零行为变化; 渐变圆钮按压反馈可见; 评审 demo 走查动效达标
- **依赖**: 无前置 PR
- **风险**: 低 (评审可感知; 模块新增, 不动现有)

---

#### ⏸ C3 · ReviewGraphView 1880 行拆 5 个内部模块
- **Strength**: Worth exploring
- **涉及**: `pages/Review/ReviewGraphView.ets` 单文件
- **触发条件 (待补充)**:
  - [ ] spec 012 的"单消费者不进 shared"是否允许局部内部 module (建议: 文件级拆分, 仍留 pages/Review/ 目录)
  - [ ] 拆后 KnowledgeGalaxyViewModel (790 行) 是否一并治理 (高风险, 单独 spec)
  - [ ] 决定 5 模块拆法 (StarField / OrbitRings / PlanetNode / GalaxyLinkLayer / GestureViewport 与否)
- **执行路径**: `implement(tdd)` 纯视觉拆分
- **判据**: 主文件 ≤300 行 + 5 模块各 ≤400 行; 行为零变化 (手势/动画/数据绑定全保); UI 守门 (若加 snapshot)
- **依赖**: 无前置 PR (独立)
- **风险**: 高 (1880 行无内 seam; 拆分前应先加 helper 抽取假动作, 再开 spec)

---

#### ⏸ C4 · AppStorage 'notesVersion' 手工总线 → @StorageProp 响应式
- **Strength**: Worth exploring
- **涉及**: 6 文件 (AgentFloatWindow:119 / ReviewGraphView:291 / NoteDetailOverlay:529 / HomePage:51 / NotesPage:30,45 / SubjectDetailPage:52)
- **触发条件 (待补充)**:
  - [ ] 确认 ArkUI `@StorageProp` 在 HarmonyOS 6.1.1 (API 24) 上行为稳定 (查 SDK d.ts)
  - [ ] 决定写侧入口 (单点 publish vs 沿用 6 处 setOrCreate)
- **执行路径**: `implement(tdd)` 重构
- **判据**: 6 文件零 onPageShow 手动 get; bug 类别"漏刷"归零
- **依赖**: 无前置 PR
- **风险**: 中 (响应式可能带来额外重渲)

---

#### ⏸ C5 · IconButton 原子上收 + MathPreviewText 升分子
- **Strength**: Worth exploring
- **涉及**: 新增 `shared/atoms/IconButton.ets`; `shared/atoms/MathPreviewText.ets` 移入 `shared/molecules/`; 受益方 5+ 浮层按钮
- **触发条件 (待补充)**:
  - [ ] 决定 IconButton 接口签名 (icon/iconSize/color/strokeWidth/active/onTap/background)
  - [ ] 决定 MathPreviewText 升分子后, 原 atom 文件是删还是保留 (建议删, 守门测试守住)
- **执行路径**: `implement(tdd)` 纯移动 + 守门锁定
- **判据**: 5 处按钮收敛为 IconButton; MathPreviewText 移目录后 lint 0 error; spec 012 atom 零内部依赖违例清零
- **依赖**: 无前置 PR
- **风险**: 极低

---

#### 🚫 C6 · AiSettings 九子件上收
- **Strength**: Speculative
- **驳回原因**: 无第二个消费者, YAGNI
- **触发条件 (重审)**: 出现第二个设置类页面时再开
- **状态**: 锁定不碰, 未来 review 反复重提时直接看本文

---

### 2. 死令牌裁决 (随 audit #1 doc expiry)

| 令牌 | 状态 | 处理 |
|---|---|---|
| LH_HEADING (行高 30) | 真死 (entry+common 零消费者) | 🔒 随 audit #1 决议删或保留 (有 PR 偏好可提前拍板) |
| SUCCESS (=MINT) | 真死 (语义色 alias) | 🔒 同上, 评估是否真有"成功态"未上色 |
| WARNING (琥珀) | 真死 (ConfidenceDot 用了字面量绕过) | 🔒 建议保留: 未来加警告 toast 可用; 或先删后补 |
| SUBJECT_COLORS / TYPE_COLORS | **假死** (经 NoteTaxonomy 包装) | 不动 |

---

### 3. PR 推送顺序建议 (按风险/收益排序)

```
Phase A (强候选, 可独立):
  - PR-A1: C0 推送 (bugfix/ocrnode-payload-break 已有)
  - PR-A2: C7 MotionPolicy (评审可感知, 接触面独立)
  - PR-A3: C1 MathTextRenderer 重分层 (接口稳定)
  - PR-A4: C2 公式样式收口 (纯静态)

Phase B (中型, 可独立):
  - PR-B1: C5 IconButton + MathPreviewText (低风险快速)
  - PR-B2: C4 @StorageProp 响应式 (依赖 SDK 验证)

Phase C (高风险, 单 PR):
  - PR-C1: C3 ReviewGraphView 拆分 (前置: helper 抽取假动作 spec)
  - PR-C1.5: KnowledgeGalaxyViewModel 治理 (独立高风险)
```

**无依赖**: A1 / A2 / A4 / B1 可并行 PR
**B2 前置**: SDK d.ts 验证
**C1 前置**: helper 抽取 spec (建议合并到 spec 012 收口 PR)

---

### 4. 待补充的资料 (触发全部 PR 的输入)

> 这些资料不到位, 任何 PR 都不开工 (除 C0 已落地)

1. **真机验收 C0**: 按 [demo-script-2026-09-06.md §2 步骤 3](../agents/demo-script-2026-09-06.md) 走一遍"AI 对话→笔记入库"
2. **动效设计裁决**: C7 的呼吸周期 + ReviewGraphView 时长迁移 + 按压反馈 scope (见 §1 C7 触发条件)
3. **API 兼容性检查**: C4 的 @StorageProp 在 API 24 (HarmonyOS 6.1.1) 的官方 d.ts 行为
4. **spec 012 收口计划**: C1 + C2 + C5 是一组 spec 012 后续 PR (PR1-PR3?), 给出顺序与边界
5. **(可选) 重审现有浮层组件目录规则**: overlays 43 组件规范真空是否要补 spec 012 §Layering rules

---

### 5. 不在体检范围 (避免跑题)

- 服务交互 (AiService / AgentChatService 等): 本次体检刻意排除, 由 spec 007 AgentChatService 拆分独立处理
- 后端 CaptureGraph / Dispatcher 业务流: 已落 D2 (spec 011), 不重复扫
- 测试覆盖率: 70 单元测试 + Hypium 行为测试, 不再扩
- 命名规范: naming-lint 0 违反, OK

---

### 6. 文件清单 (现状, 不动)

- `docs/research/frontend-component-audit-2026-09-06.md` — 叙述 + 体检裁决 + 补充 2
- `docs/research/frontend-ui-design-inventory-2026-09-06.md` — 三维档案
- `agents/src/test/CaptureTextFlow.test.ets` — OcrNode 回归守门 (已绿, 待真机验)
- HTML 体检报告 ×2 (临时目录, 不入库)

---

### Last updated

2026-09-06 晚 — 体检合同就位, 等补充资料后逐项执行。
