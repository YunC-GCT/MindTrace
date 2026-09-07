# 前端用户路径走查 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Status:** 路径式体检 — 4 主路径 + 3 横切, 事实字段机器提取 + 关键流程实读
> **Source**: 在 [`frontend-ui-design-inventory-2026-09-06.md`](./frontend-ui-design-inventory-2026-09-06.md) 静态清点基础上, 沿用户路径横向排查, 补 "页面状态保留 / 跨页面传参 / 键盘避让 / 沉浸式 / 异常分支"
> **配套**: [`frontend-healthcheck-plan-2026-09-06.md`](./frontend-healthcheck-plan-2026-09-06.md) 7 候选待办合同 (本档为输入补充)

---

**TL;DR:** 沿用户路径走查发现 **5 处路径级问题** 是静态清点抓不到的: ① HomeTopBar/NotesHeader/AiSettings.PageHeader 用 `@Prop` 传 `statusBarHeight` 不响应折叠屏变化 (C4 候选) ② Index 整体禁键盘避让 (KeyboardAvoidMode.NONE:31), 浮层自实现键盘但普通 TextInput (AiSettings/NoteEditForm) 无处理 ③ AI 浮窗→拍照→返回图: pendingImageUri 跨页面传递只在 Index:25 持有, AgentFloatWindow:40 @Prop 接收但未看消费点 ④ 主页→浮窗→关闭→再开: ChatSessionManager.loadHistory 持久化待核实 ⑤ 笔记详情/AI 浮层 OVERLAY_MASK 色差 (50%/80%) 不一致, 视觉跳跃风险

---

## 路径 1 · 启动 → 首页 (Home)

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

## 路径 2 · 拍照 → AI 浮窗识别 → 生成笔记

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

## 路径 3 · AI 对话 (AgentFloatWindow 内部)

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

## 路径 4 · 笔记查看/编辑 (NoteDetailOverlay)

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

## 横切 A · 状态栏高度 (C4 候选的路径证据)

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

## 横切 B · 键盘避让策略

| 组件 | 策略 | 备注 |
|---|---|---|
| Index (全局) | `setKeyboardAvoidMode(NONE)` | Index.ets:31 — 全局禁 |
| AgentFloatWindow | 自实现: onKeyboardHeightChange → @State keyboardHeight, Stack padding bottom | ✓ 浮层内 OK |
| AiSettings.KeyInput | TextInput 受控, 未见键盘处理 | ⚠ 长按输入框键盘弹起可能被浮层/页面截断 |
| AiSettings.EndpointPicker | 同上 | ⚠ |
| NoteEditForm (4 字段) | 未见键盘处理 | ⚠ 详情浮层打开时 + 编辑, 键盘弹起可能遮住输入框 |

**建议**: Index 全局 NONE 是为了让浮层自实现接管 — 但当前实现只覆盖 AgentFloatWindow, 其他三个页面的 TextInput 实际没人处理。可考虑: 让 Index 不全局 NONE, 而要求含 TextInput 的页面单独用 `.expandSafeArea([SafeAreaType.KEYBOARD])` 或自实现; 或统一建一个 KeyboardAvoid 容器 wrapper (类似 C2 的 style-policy 收口位)。

---

## 横切 C · 浮层视觉一致性

| 项 | AgentFloatWindow | NoteDetailOverlay | CameraOverlay |
|---|---|---|---|
| 遮罩色 | OVERLAY_MASK (50% 黑) | OVERLAY_MASK_SOLID (80% 黑) | CAM_MASK 单独定义 |
| 圆角 | R_XL (16) | (未查) | — |
| 入场动画 | sheetOffset/opacity DUR_BASE | (未查) | (未查) |
| 状态栏让位 | ✓ StorageProp | ✓ StorageProp | (未查, 相机通常全屏) |

**P3 视觉一致性**: 三个浮层的遮罩色/圆角/动画时长 / 入场曲线均不一致 — 可视化跳跃。建议 C7 MotionPolicy 收口时一并把遮罩色决策也吸纳入 `(profile → style)` 模块。

---

## 5. 待补充资料 (新增)

§4 待补充资料清单追加:

6. **路径级问题的快速核实**: P2.2 (pendingImageUri 消费点) / P3.1 (loadHistory 持久化) / P4.2 (删除后 bumpNotesVersion) — 这三项决定两条主路径的核心 UX, **应在 C0 真机验收时一并查**, 任何一项失败都构成真机不通过的理由

---

## 6. 结论

体检的"按目录扫"完成了, 但漏掉的"按路径走"层面问题更具 UX 影响。**最关键的发现**: C4 候选 (statusBarHeight 不响应) 在静态扫描时低估了——实际 6 页面都受影响, 浮层则正确 (2 处); 这是路径证据 + 静态证据的合力, 应**提升 C4 优先级**到 Phase A 强候选。

下一轮执行: 真机验收 C0 时, 同步走 §5 第 6 项三项核实 → 三项全过再开 C4 PR, 任何一项失败另立 ticket。

---

## Last updated

2026-09-06 晚
