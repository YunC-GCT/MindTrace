# NoteDetailOverlay 现状调研

> **调研日期** 2026-09-23
> **调研范围** `entry/src/main/ets/overlays/NoteDetailOverlay/` 完整 22 文件;6 处挂载点;数据链路;设计 token / 组件 / 动效;已知问题
> **调研方式** Lead 深度阅读 + 5 个并行子代理(A 核心实现 / B 调用链 / C 数据层 / D 文档 / E 设计 token)
> **状态** active (权威)
> **版本** v1.1 — 合并子代理 cross-check 修正(详见附录 C)

---

## 1. TL;DR

笔记详情页面**不是独立 Page**,而是一个 **全屏覆盖浮层** `NoteDetailOverlay`(`entry/src/main/ets/overlays/NoteDetailOverlay/`,**22 文件 / ≈ 3 100 LOC**)。由 **6 处挂载点**(Home ×2 / SubjectDetailPage / ReviewGraphView / KnowledgeGalaxy3DHost / AgentFloatWindow)条件渲染共用,内部按 **6 套 renderer**(概念 / 定理 / 公式 / 证明题 / 计算题 / 兜底)策略分派,Markdown / 公式走 shared 分子层 `MarkdownRenderer` + `MathTextRenderer`。状态、写入、缓存链路完整,但已知 **17 个问题**(高 6 / 中 7 / 低 4)集中在永久 LoadingState、saveEdit 混杂 UI 层、KnowledgeGalaxy 绕过缓存、零动效、遮罩色差等位置。

---

## 2. 文件结构(22 文件 · ≈ 3 100 LOC)

```
entry/src/main/ets/overlays/NoteDetailOverlay/
├─ NoteDetailOverlay.ets         (660) — 容器/全屏浮层状态机
├─ NoteDetailMeta.ets            (290) — 头部(chip + 标题 + 3 列指标)
├─ NoteDetailBody.ets             (94) — 派发器(@Builder RenderByModel)
├─ NoteEditForm.ets              (96) — 编辑表单(4 受控输入)
├─ NoteActionBar.ets             (25) — 底部(编辑/分享)
├─ NoteCloseButton.ets           (39) — 关闭按钮(AppIcon)
├─ NoteIconButton.ets            (33) — 通用 icon 按钮
├─ ChipTag.ets                   (65) — 标签 chip(5 变体)
├─ ConfDot.ets                   (32) — 置信度圆点(audit 标 unused)
├─ renderers/ — 6 套策略器官
│  ├─ ConceptDetailView.ets     (257) — 概念:定义→性质→例子→关联 渐进
│  ├─ TheoremDetailView.ets     (280) — 定理:陈述→证明过程→关键思路
│  ├─ FormulaDetailView.ets     (280) — 公式:陈述→参数→范围→推导→备注
│  ├─ ProofDetailView.ets       (279) — 证明题:命题→证明→关键思路
│  ├─ ComputationDetailView.ets (283) — 计算题:已知→求解→解答
│  └─ FallbackDetailView.ets    (180) — 兜底
├─ components/ — 5 件浮层局部子组件
│  ├─ DetailSection.ets         (141) — 分节容器
│  ├─ DetailStepList.ets        (111) — 步骤列表(index+item key)
│  ├─ DetailStepsSection.ets    (111) — 步骤区块
│  ├─ DetailMetaFooter.ets      (208) — 标签/前置/相关/源/复习状态 footer
│  └─ DetailRenderQueue.ets     (144) — 渲染队列(16ms tick / 8ms 帧预算)
└─ model/ — 渲染数据建模(非视觉)
   ├─ DetailRenderModel.ets     (497) — 12 字段结构化模型 + section 解析
   └─ DetailRenderCache.ets     (155) — 8 条 / 512 KB LRU + 单条 128 KB 上限
```

注:本目录 .ets 文件数 = 顶层 9 + components/5 + renderers/6 + model/2 = **22**(glob 实测 + `frontend-component-audit-2026-09-06.md:114` 与 `frontend-ui-design-inventory-2026-09-06.md:557` 一致)。`ConfDot.ets` 虽在目录内但 0 处 import 或使用(`NoteDetailMeta` 自实现 MetricCell 替代),`dead-code-archive-2026-07-19.md:33` 已标记 unused。LOC 累计 `9 + 5 + 6 + 2 = 22` 文件 ≈ 3 100 LOC(含 ConfDot.ets 32 行)。

---

## 3. 6 处挂载点对照表

| # | 入口名 | 触发位置 | 文件:行 | 模式 | 传入参数 | 回调 |
|---|---|---|---|---|---|---|
| 1 | HomePage · 新建 | `FloatingButton.onClick` → `openCreate` | `pages/Home/HomePage.ets:80-84, 192-198` | `isCreating: true` | `units: vm.units` | `onClose`, `onSaved` |
| 2 | HomePage · 最近笔记 | `HomeRecentNotes > NoteCard.onClick` | `pages/Home/HomePage.ets:69-78, 183, 201-209` | 查看 | `note` + `unit`(异步) + `units` | `onClose`, `onDelete`, `onSaved` |
| 3 | SubjectDetailPage · 学科笔记 | `SubjectNoteList > NoteCard.onClick` | `pages/Notes/SubjectDetailPage.ets:111-119, 178, 186-194` | 查看 | `note` + `unit` + `units` | `onClose`, `onDelete`, `onSaved` |
| 4 | ReviewGraphView · fallback 星系 | `Planet.onClick` (background + overview) | `pages/Review/ReviewGraphView.ets:1398, 870, 230-242, 251-257, 419-427` | 查看 | `note: planet.note`, `unit: planet.unit`, `units` | `onClose`, `onDelete`, `onSaved` |
| 5 | KnowledgeGalaxy3DHost · native/web 星系 | `GalaxyComponent3DAdapter.handleTap` (raycast, `:340-358`) / `GalaxyWebAdapter` `node_selected` (`:187-191`) → `openById` | `pages/Review/KnowledgeGalaxy3DHost.ets:53-67, 193-206, 126-134` | 查看 | `note` + `unit` + `units` | `onClose`, `onDelete`, `onSaved` |
| 6 | AgentFloatWindow · AI 草稿 | `ConversationWorkflow.publishDraft` → `onDraftReady` → `generatedDraft = event` | `overlays/AgentFloatWindow/AgentFloatWindow.ets:299-309, 749-777` | AI 草稿预览 | `generatedDraft: NoteDraftReadyEvent` | `onClose`, `onDraftCancel`, `onDraftConfirm`, `onSaved` |

**关键事实**:
- 所有 6 入口都用 `if (xxx !== null) NoteDetailOverlay({...})` 条件渲染,**无 `bindContentCover` / `customDialog` / `router.pushUrl`**(子代理 B 全量核对)
- `onEdit(id: number)` 在 6 调用点**全部未绑定** — `NoteDetailOverlay.ets:358` `onEdit(this.note.id)` 是 Overlay 内部触发,被外部忽略
- 不传 subjectId(subject 走 NoteItem 内嵌,`common/src/main/ets/data/MockNotes.ets:10`)
- 笔记入口(2-5)统一模式:`onSelect(note) → openDetail → selectedNote=note; selectedUnit=null → vm.loadNote(ctx, note.rawId) → selectedUnit=unit`(`HomePage.ets:73-77` / `SubjectDetailPage.ets:114-118` / `ReviewGraphView.ets:235-241` / `KnowledgeGalaxy3DHost.ets:201-205`)
- AI 草稿入口 5 个 trigger 点:`onDraftReady` / `restoreDraftsAfterHistoryLoad` / `switchSession` / `deleteSession` / 重新设置 `generatedDraft` 完成重新显示(`AgentFloatWindow.ets:379-381, 460-462, 545-547`)
- `SubjectDetailPage` 自身是 `@Entry`,由 `NotesPage.ets:64-68` `router.pushUrl` 进入

---

## 4. 调用链示意图

### 4.1 笔记卡片路径(4 个相同模式)
```
[控件] NoteCard.onClick (shared/organisms/NoteCard.ets:85 .onClick → this.onTap())
  ↓
[回调] onTap() → HomeRecentNotes/SubjectNoteList: onSelect(note: NoteItem)
  ↓
[Page] HomePage.openDetail (HomePage.ets:69-78) / SubjectDetailPage.openDetail (SubjectDetailPage.ets:111-119)
    设置 selectedNote = note; selectedUnit = null
    异步: vm.loadNote(ctx, note.rawId).then(unit => selectedUnit = unit)
  ↓
[Render] if (this.selectedNote !== null) → 条件渲染 NoteDetailOverlay
  ↓
[Overlay] 接收 {note, unit, units, onClose, onDelete, onSaved}
```

### 4.2 fallback 星系(ReviewGraphView)
```
[控件] KnowledgeGalaxy.Planet.onClick (ReviewGraphView.ets:1394-1399)
  ↓
[回调] onSelectPlanet(planet) → selectGalaxyPlanet (line 251) → openPlanet (line 230)
    selectedNote = planet.note; selectedUnit = planet.unit
    异步: vm.loadNote(ctx, planet.id) → 二次加载最新 Unit
  ↓
[Render] if (this.selectedNote !== null) → NoteDetailOverlay (line 419-427)
```

### 4.3 native 3D 星系
```
[控件] Scene 3D GestureEvent (handleTap raycast, hits[0].node.path → id)
  ↓
[Adapter] this.callbacks.onSelect(id) (GalaxyComponent3DAdapter.ets:340-358)
  ↓
[Host] KnowledgeGalaxy3DHost.openById(id) (line 193)
    selectedNote = planet.note; selectedUnit = planet.unit
    异步: vm.loadNote(ctx, planet.id)
  ↓
[Render] if (this.selectedNote !== null) → NoteDetailOverlay (line 126-134)
```

### 4.4 web 星系
```
[控件] ArkWeb message 'node_selected' (payload.id)
  ↓
[Adapter] this.callbacks.onSelect(id) (GalaxyWebAdapter.ets:187-191)
  ↓
[Host] (同 4.3)
```

### 4.5 新建路径
```
[控件] FloatingButton.onClick → openCreate (HomePage.ets:80-84) → creatingNote = true
  ↓
[Render] if (this.creatingNote) → NoteDetailOverlay ({isCreating: true, units, onClose, onSaved})
```

### 4.6 AI 草稿路径(唯一异步业务触发)
```
[Trigger] 用户在 AI 浮窗对话产生 NoteGenerationRun
  ↓
[Workflow] ConversationWorkflow.publishDraft (ConversationWorkflow.ets:361/579/721)
  ↓
[Service] AgentChatService 回调: cbs.onDraftReady(ref, event) (AgentFloatWindow.ets:299-309)
    校验 originSessionId === ref.sessionId + isCurrentRun → inputVm.setDraftForSession
    this.generatedDraft = event; this.generatedDraftSessionId = ref.sessionId
  ↓
[Render] if (this.generatedDraft !== null) → NoteDetailOverlay ({generatedDraft, onClose, onDraftCancel, onDraftConfirm, onSaved})
    Overlay.aboutToAppear (line 69-79): loadForm(generatedDraft.candidate) → 直接进编辑态
```

---

## 5. 数据与状态链路(双类型 + 三层缓存)

```
NoteItem (UI 扁平投影, common/data/MockNotes.ets:6-34)
  id:number / title / type / subject / chapter / conf:0-1
  body (预览) / tags[] / date:YYYY-MM-DD / rawId ← KnowledgeUnit.id 字符串
                              │
         ┌────────────────────┴────────────────────┐
         │                                         │
  ┌──────▼──────── ViewModel (走缓存) ────────┐   ┌─ KnowledgeGalaxyViewModel ──┐
  │ HomeViewModel / NotesViewModel             │   │ loadNote(id) → 绕过缓存,  │
  │  loadNote(id) → UiDataCacheService        │   │ NoteDao.queryById 直查     │
  │  .loadDetail (LRU 8/512KB + in-flight join)│   └─────────────┬──────────────┘
  └─────────────────────────┬────────────────┘                  │
                            │ 抛 null                          │
                            ▼                                  ▼
                KnowledgeUnit (RDB 真相源, common/models/CommonTypes.ets:57-86)
                id:UUID / title / content / summary / tags
                subject / category (概念/定理/公式/证明题/计算题)
                chapter / difficulty / source
                reviewStatus / nextReviewAt / intervalDays
                easeFactor / repetitions
                prerequisites[] / related[] / embedding[]
                version (乐观锁)
                            │
 ┌────────────────────┼─────────────────────────────┐
       │                    │                             │
       ▼                    ▼                             ▼
 NoteDetailOverlay  KnowledgeUnitWriteService       DatabaseHelper
 @Prop note/unit  create / update (乐观锁)        relationalStore.RdbStore
 @Watch→localUnit  PostCommit: 3 effects notes_version
       │ ├─ KnowledgeUnitCacheInvalidationEffect
       │           ├─ KnowledgeUnitNotesVersionEffect
       │           └─ KnowledgeUnitCardRefreshEffect
       ▼
 DetailRenderCache (LRU 8/512KB, key=id|updatedAt|version|unitsHash)
       │
       ▼
 DetailRenderModel (12 字段: category, subject, summary, body, sections[],
                    tags, prerequisites, related, sourceLabel, reviewLine,
                    difficultyText, statusText)
       │
       ▼
 NoteDetailBody 派发(@Builder RenderByModel)
       │
 ┌─────┬────┬────┬────┬────┐
   ▼    ▼    ▼    ▼    ▼    ▼
Concept Theorem Formula Proof Comp Fallback
       │
       ▼
 MarkdownRenderer (shared/molecules, 全仓 11 调用点)
       │
       ▼ MathTextRenderer (Web KaTeX + Text 双分支, Webview LRU + 16ms tick)
```

**写入入口**:
- 手动编辑/创建:`NoteEditService.upsert` (entry/src/main/ets/services/NoteEditService.ets:14-25) → `KnowledgeUnitWriteService.create/update` (entry/src/main/ets/services/KnowledgeUnitWriteService.ets:31-82) → `KnowledgeUnitWriteRepository.createWithRevision/updateWithRevision` (乐观锁) → 3 个 PostCommitEffect → `AppStorage.setOrCreate('notesVersion', v+1)` → 所有 Tab 通过 `@Watch('onNotesVersionChange')` 重拉
- AI 草稿:`onDraftConfirm(candidate) → AgentChatService → NoteGenerationService → NoteDaoAdapter` → 同上
- 删除:caller `deleteNote(id)` → `ViewModel.deleteNote(ctx, id)` (`HomeViewModel.ets:55-67` / `NotesViewModel.ets:71-83`) → `UiDataCacheService.invalidateNote(id)` + `NoteDao.deleteById(id)` (级联 kg_edge / rag_embedding / rag_chunk) + bump `notesVersion`

**关键观察**:
- `NoteItem.imageUrl` 不存在;与图片相关的展示走 OCR 产物或 `KnowledgeRelationDao` / `RagEmbeddingDao`,**不在本详情页字段集**
- Overlay 保存成功后只 `localUnit = committed` (`NoteDetailOverlay.ets:454`),**未自动 invalidate UiDataCacheService.notesSnapshot**;依赖外层 page `loadNotes` 重载
- `KnowledgeGalaxyViewModel.loadNote` 绕过 `UiDataCacheService`(`presentation-deep-dive-2026-09-16.md:229`),`deleteNote` 没失效 cache(§8 #2)

---

## 6. UI 状态机(三种模式)

| 模式 | 触发条件 | 顶部 | 内容区 | 底部 |
|---|---|---|---|---|
| **查看(read-only)** | `!isCreating && generatedDraft=null && effectiveUnit()!==null` |关闭 + "笔记详情" + 头部右上角**删除按钮**(仅非创建且有 unit,DANGER 色,`NoteDetailOverlay.ets:107-113`) | `NoteDetailMeta` + `NoteDetailBody`(6 renderer) | `NoteActionBar`(编辑 + 分享) |
| **编辑** | `startEdit()` (line 350) / `generatedDraft !== null` | "编辑笔记" / "预览 AI 笔记草稿" | `NoteEditForm`(4 受控输入) + 草稿模式显示 `incrementalDiff` (line 139-148) | 取消/保存 图标按钮(saving 时禁用) |
| **新建** | `isCreating=true` | "新建笔记" | `NoteEditForm`(空表单) | 取消/保存 图标按钮 |

**modeTitle**:`'预览 AI 笔记草稿' / '新建笔记' / '编辑笔记' / '笔记详情'` (`NoteDetailOverlay.ets:324-335`)

**LoadingState**:`effectiveUnit() === null` + `note.title/body` 全空 → `@Builder LoadingState` (line 217-240) "正在加载笔记内容" 居中(详见 §10 #1 永久卡死)

**DiscardConfirm**:编辑后关闭/遮罩 → `hasUnsavedChanges()` (line 631-636) 为真 → `@Builder DiscardConfirm` (line 242-305) 78% 宽卡片居中 → 选"放弃"才真丢弃

**关闭三路入口**:`NoteCloseButton` (line 90) / 背景遮罩 `.onClick` (line 84) / 编辑模式 `cancelEdit` (line 377-386) → 最终都走 `onClose()` / `onDraftCancel()` 回调

---

## 7. 设计 token / 组件复用 / 动效

### 7.1 Token(100% 走 `common/ColorTokens.ets`,**零 `$r`**)

| 族 | 令牌 |
|---|---|
| 主色板 | MINT / PURPLE / DANGER / AMBER |
| 背景 | BG_DARK / BG_CARD |
| 文字 4 级 | TEXT / TEXT_2 / TEXT_3 / TEXT_4 |
| 边框 | BORDER |
| 玻璃色 | GLASS_10(`#1AFFFFFF`) — 注意:6 处字面量绕过本族,详见 §10 #11 |
| 间距 | S_1 ~ S_6 |
| 圆角 | R_SM / R_MD / R_LG / R_FULL / R_XL |
| 字号 | F_XS / F_SM / F_MD / F_BASE / F_XL |
| 字重 | W_MEDIUM / W_SEMIBOLD / W_BOLD |
| 遮罩 | `OVERLAY_MASK_SOLID = #CC000000` (80% 黑, ColorTokens.ets:52) |
| 工具函数 | `typeColor(t)` / `typeGlassColor(t)` / `glassSurfaceColor(c)` (NoteTaxonomy.ets:56-82) / `recentDate(s)` / `ContentExcerptBuilder` / `ContentProtocol` / `NOTE_SUMMARY_MAX_LENGTH` / `normalizeNoteType` / `isKnownNoteType` |

**未走资源型 token**:`entry/src/main/resources/base/element/color.json` 仅 1 项(`start_window_background #FFFFFF`),string 仅 5 项能力标签,float 仅 1 项(`page_text_font_size`)。整体不依赖 `$r('app.color.xxx')` 通道(子代理 E 全量核对)。

### 7.2 组件复用

| 层级 | 组件 | 文件:行 | 复用点 |
|---|---|---|---|
| 自研(目录内) | `NoteCloseButton` | NoteCloseButton.ets:23 | NoteDetailOverlay.ets:90 |
| 自研 | `NoteIconButton` | NoteIconButton.ets:9 | NoteDetailOverlay.ets:108 / 169 / 177 / 184;NoteActionBar.ets:16 / 18 |
| 自研 | `ChipTag` (5 变体) | ChipTag.ets:26 | renderers/ 多处 |
| 自研 | `ConfDot` (unused) | ConfDot.ets:18 | audit-2026-09-01 dead-code |
| 自研 | `NoteActionBar` | NoteActionBar.ets:9 | NoteDetailOverlay.ets:198 |
| 自研 | `NoteEditForm` | NoteEditForm.ets:21 | NoteDetailOverlay.ets:122 |
| 自研 | `NoteDetailMeta` | NoteDetailMeta.ets:29 | NoteDetailOverlay.ets:153 |
| 自研 | `NoteDetailBody` | NoteDetailBody.ets:34 | NoteDetailOverlay.ets:154 |
| 跨 overlay | `AppIcon` (atom) | shared/atoms/AppIcon.ets | NoteCloseButton / NoteIconButton / DetailStepList |
| 跨 overlay | `MathTextRenderer` (实为最重组件) | shared/atoms/MathTextRenderer.ets | NoteDetailMeta.ets:23 / 81(副标题公式预览, profile=`preview`) |
| 系统控件 | Stack / Column / Row / Scroll / Blank / Text / TextInput / TextArea / Circle / ForEach / linearGradient / Border / EdgeEffect.Spring | — | 全 |
| 未使用 | Button / List / Grid / Stepper | — | 自研深度高,未走 ArkUI 系统控件 |

### 7.3 动效(典型静态浮层,**零主动效**)

| API | 数量 | 引用 |
|---|---|---|
| `animateTo(...)` | 0 | 全目录未出现 |
| `.animation(...)` | 0 | 全目录未出现 |
| `.transition(...)` | 0 | 全目录未出现 |
| `transitionId` | 0 | 全目录未出现 |
| `@AnimatableExtend` | 0 | 全目录未出现 |
| `DUR_INSTANT/FAST/BASE/SLOW/SLOWER/SLOWEST/BREATH` | 0 | 整个 overlay 完全未消费动效时长令牌 |
| `Curve.*` (FastOutSlowIn / EaseInOut 等) | 0 | 整个 overlay 未消费曲线令牌 |
| `setTimeout` (延迟,非视觉动效) | renderers 5 件 × 1 处 + DetailRenderQueue 16ms 节拍 | renderers/5 件 + components/DetailRenderQueue.ets:62 |
| `setInterval` | 0 | — |
| 系统默认 `EdgeEffect.Spring` | 1 | NoteDetailOverlay.ets:164 |

**唯一的设计意图"过渡"**:`DiscardConfirm` 内 `cancelEdit`/`saveEdit` 用 `@State showDiscardConfirm` 切换可见性,**未配 animateTo**(隐式 mount/unmount)。

**渲染队列**:`DetailRenderQueue` 16ms tick + 8ms 帧预算 + 6+ 任务时切 0ms fast + 上限 80 — 用于 Markdown/公式挂载的串行分帧,**非视觉动效**(被 `chat-markdown-latex-render-jank-2026-09-13.md:54` 列为 chat 应借鉴的对象)。

---

## 8. 双类型映射 + Overlay 实际字段表

| Overlay 字段 | 来源 | 渲染位置(Overlay 内) |
|---|---|---|
| `note: NoteItem` | 列表行选中传入;`rawId` = 真 UUID | 兜底/草稿场景:title (Meta l:165-171) / subtitle=`note.chapter` (l:179-185) / subject (l:236-241) / category=`note.type` (l:243-248) / conf% (l:250-253) / `note.date` (l:160) |
| `unit: KnowledgeUnit` | 懒加载:`VM.loadNote → UiDataCacheService.loadDetail → NoteDao.queryById` | Meta:title / subtitle=`unit.summary` / subject / category / difficulty / reviewStatus / updatedAt / createdAt;Body:content / tags / prerequisites / related |
| `units: KnowledgeUnit[]` | 列表快照,全表 metadata (`vm.units`) | 解析 prerequisites/related 的 id → title (Meta l:202-219 + DetailRenderModel l:425-443) |
| `generatedDraft` (可选) | AI 草稿事件, `common/src/main/ets/models/NoteGenerationModels.ets:256-272` | 头部分支 (`modeTitle === '预览 AI 笔记草稿'`) + 增量 diff (`incrementalDiff`, `NoteDetailOverlay.ets:139-148`) |

**Overlay 真正"看不到"的字段**(以 `unit === null` 兜底即可识别的):embedding(向量)、userId、createdAt 原始值(只显示 updatedAt 优先)、intervals/easeFactor 数值(只在 reviewLine 拼接)、prerequisites/related 的 id 数组本体(只能查到 title)。

---

## 9. 文档/审计历史对应表

| 文档 / 审计 | 关键 finding |
|---|---|
| `docs/specs/020-reply-body-contract.md:68, 123, 147` | "NoteDetailOverlay 家族已全走 MDR,无需动";公式拆分 FSR/MDR/MathTextRenderer 三套 |
| `docs/specs/021-chat-streaming-incremental-rendering.md:45-46, 53, 59-63` | chat 与 NoteDetail L1/L3 隔离;NoteDetail 不在本 spec 切换,继续用 `MarkdownRenderer`/`FormulaSplitRenderer` |
| `docs/specs/022-multi-device-ui-adaptation.md:13, 49 (US21)` | 笔记详情在 XS/SM 全屏、MD+ 限宽侧面板;ready/implementation deferred |
| `docs/specs/021-knowledge-graph-rdb.md:125` | `prerequisites/related` 仍保留在 `KnowledgeUnit` 及 revision 表中,**供旧详情页面兼容** |
| `docs/research/frontend-component-audit-2026-09-06.md:114-126` | 22 文件结构最深组合树;renderers/ 策略分派;**float 本地组件无层级规则(spec 012 真空)** |
| `docs/research/frontend-ui-design-inventory-2026-09-06.md:557-689` | 22 文件逐件三维档案(令牌/布局/动效) |
| `docs/research/frontend-flow-walkthrough-2026-09-06.md:101-130` | 路径 4:P4.1-P4.4 路径级问题;NoteDetailOverlay 是**少数正确用 `@StorageProp('statusBarHeight')` 响应**的两个浮层之一 |
| `docs/research/presentation-deep-dive-2026-09-16.md:8 #7, Loop #5` | **D3 LoadingState 永久卡死**(NoteDetailOverlay.ets:213-237 + HomeViewModel.ets:43-53 无重试) |
| `docs/research/presentation-deep-dive-2026-09-16.md:8 #2` | KnowledgeGalaxyViewModel 绕过 UiDataCacheService |
| `docs/research/presentation-deep-dive-2026-09-16.md:8 #10` | `KnowledgeGalaxyViewModel.loadNote` 静默吞错 + planet.unit 兜底与 DB 可能不一致 |
| `docs/research/presentation-deep-dive-2026-09-16.md:8 #15` | NotesViewModel.loadNote 失败后 selectedUnit=null,UI 仍渲染 NoteDetailOverlay |
| `docs/research/presentation-deep-dive-2026-09-16.md:8 #16` | `UiDataCacheService.notesSnapshot.units` 冗余(列表页只用 notes) |
| `docs/research/frontend-performance-audit-2026-09-06.md:47-52, 150` | 笔记详情 1 屏 = 7+ 个 WebView;笔记详情 + AI 浮窗同开 ≈ 8 个 WebView → HarmonyOS 6.1 单进程 WebView 上限风险(常见 6-8) |
| `docs/research/chat-markdown-latex-render-jank-2026-09-13.md:54` | NoteDetailOverlay 已有 `DetailRenderQueue`(16ms)+ `DetailRenderCache`,chat 没有 — **chat 借鉴对象** |
| `docs/research/agent-float-window-component-research-2026-09-11.md:34, 55, 164` | AgentFloatWindow :29 跨 overlay import NoteDetailOverlay;**跨 overlay 业务流:onDraftReady→NoteDetailOverlay→confirmDraft/cancelDraft** |
| `docs/research/fixture-isolation-result-2026-09-16.md:98-102, §5 D3` | 笔记详情 prerequisites/related 显示**未验证**(误触 AI 浮窗);D3 永久 LoadingState 入待修 backlog |
| `docs/research/data-presentation-flow-2026-09-16.md:214, 370` | 手动编辑路径 `entry/src/main/ets/services/NoteEditService.ets` UI 由 `NoteDetailOverlay` 调用 |
| `docs/research/project-positioning-2026-09-04.md:96, 155` | 5 类专属 renderer 统一走 `DetailSection + DetailStepList + DetailMetaFooter` |
| `docs/research/frontend-interaction-states-2026-09-06.md:10, 20, 121` | 5 态失衡;CameraOverlay 有 loading/disabled,NoteDetailOverlay 没有 |
| `docs/agents/demo-script-2026-09-06.md:31` | 步 5:打开笔记详情 → 验证 MM-MD-v1 渲染(独立公式 `$$` 单独成行,字段分区) |
| `docs/agents/smoke-test.md:12` | 步 6:笔记详情浮层打开/关闭,期望浮层无残留 |
| `docs/legacy/mindtrace/architecture/deep-dive-2026-09-01.md:365-468 (§F4.1-F4.9)` | **§F4.1 P0 mockShare shipped in production** (L555-557);F4.2 P0 saveEdit 5 步混杂;F4.3 5 个 @Watch 触发同一 watcher;F4.4 parseTags 分隔符不全;F4.5/F4.6 category/tag 重叠;F4.7 DiscardConfirm 嵌套布局;F4.8 bumpNotesVersion 三处写;F4.9 SOURCE_CAMERA 常量 |
| `docs/legacy/mindtrace/architecture/audit-2026-09-01.md:67` | ✅ NoteDetailOverlay 三大浮层之一 |
| `docs/legacy/mindtrace/plans/w3/ui-preload-cache-optimization-2026-07-21.md:88` | NoteDetailOverlay 新增 `DetailRenderCache` 的来源 |
| `docs/legacy/mindtrace/plans/w3/notes-page-structure-proposal-2026-07-19.html:627-849` | "完成 smoke test 后,再进入笔记详情页新结构规划" — 详情页重构**未实施** |
| `docs/legacy/mindtrace/plans/w3/render-protocol-optimization-route-2026-07-22.md:1996` | "NoteDetailOverlay 改用 `List + LazyForEach`,每个 `DetailBlock` 对应一个 `ListItem`" — **未实施** |
| `docs/legacy/mindtrace/plans/w3/dead-code-archive-2026-07-19.md:33` | `ConfDot.ets` unused(2026-07 标记) |
| `docs/legacy/mindtrace/competition/references-2026-07-26.md:13` | KaTeX 用于 chat 气泡 + **笔记详情页公式展示** + 公式预览卡片 |
| `docs/adr/` | **0 条直接命中 `NoteDetailOverlay`** — 设计权落在 `frontend-component-audit-2026-09-06.md` 和 `presentation-deep-dive-2026-09-16.md` |

---

## 10. 已知问题清单(按优先级)

### 🔴 高(用户体验阻塞 / P0-P1)

1. **LoadingState 永久卡死**(`presentation-deep-dive-2026-09-16.md:8 #7` / Loop #5 / D3 fixture-isolation)
   - 触发:`HomeViewModel.loadNote` / `NotesViewModel.loadNote` 失败(返回 null)+ `selectedUnit = null` + note 字段全空 → `canRenderReadOnlyDetail()` 返回 false → `LoadingState()` (NoteDetailOverlay.ets:217-240) 永久转圈,**无重试**
   - 证据:`NoteDetailOverlay.ets:146-154, 308-313`;`HomeViewModel.ets:43-53`;`SubjectDetailPage.ets:111-119`
   - 修复方向:`HomeViewModel/NotesViewModel.loadNote` 失败时弹错误 banner + 触发重试;`KnowledgeGalaxyViewModel.loadNote` 同样处理

2. **`KnowledgeGalaxyViewModel` 绕过 `UiDataCacheService`**(`presentation-deep-dive-2026-09-16.md:8 #2`)
   - 删除后只 `AppStorage.setOrCreate('notesVersion', v+1)`(`KnowledgeGalaxyViewModel.ets:262-277`),`UiDataCacheService.notesSnapshot` / `detailEntries` 没失效
   - 修复方向:`KnowledgeGalaxyViewModel.deleteNote` 调 `UiDataCacheService.invalidateNotesSnapshots()` + 详情 LRU 也失效

3. **`mockShare` shipped in production P0**(`deep-dive-2026-09-01.md:§F4.1`, L555-557)
   - 仅 `promptAction.showToast({ message: '分享功能暂未开放', duration: 1500 })`
   - 修复方向:实施真分享 或 `if (DEBUG)` gate + 路由到真 provider

4. **`saveEdit` 5 步混杂在 UI overlay P0**(`deep-dive-2026-09-01.md:§F4.2`, L359-402)
   - 5 步:DatabaseHelper.init + 构建 KnowledgeUnit + Persists + Invalidates 3 caches + Bumps AppStorage + onSaved + localUnit=saved+clear editing
   - 修复方向:抽 `NotesEditCoordinator` 进 services 层

5. **3D 星系路径删除 bump notesVersion 待核实**(P4.2, `frontend-flow-walkthrough-2026-09-06.md:127`)
   - Home/Notes VM 显式 bump,`KnowledgeGalaxy3DHost.deleteNote` 未 grep 到
   - 修复方向:在 `KnowledgeGalaxy3DHost.deleteNote` 补 `AppStorage.setOrCreate('notesVersion', v+1)`

6. **持久错误指示缺失**(`presentation-deep-dive-2026-09-16.md:8 #5`)
   - 3 个 ViewModel 错误处理全是 `console.warn` + 空;DB init 失败时用户每次切 Tab 都闪一次 toast,无持久 banner / page
   - 修复方向:加全局 `ErrorBanner` 组件,挂 AppStorage 总线

### 🟡 中(明显 UX 问题)

7. **遮罩色差 P4.3**(`frontend-flow-walkthrough-2026-09-06.md:128`)
   - `OVERLAY_MASK_SOLID` 80% (`ColorTokens.ets:52`) vs `AgentFloatWindow` 的 `OVERLAY_MASK` 50% — 串场视觉跳跃
   - 修复方向:统一遮罩色或设计专门的过渡

8. **NoteEditForm 键盘避让 P4.4**(`frontend-flow-walkthrough-2026-09-06.md:129`)
   - 4 受控 TextInput/TextArea (`NoteEditForm.ets:34, 46, 58, 70`),Index 全局 `KeyboardAvoidMode.NONE`,本浮层**未自实现**键盘监听
   - 修复方向:参考 `AgentFloatWindow` 的 `onKeyboardHeightChange` 自实现

9. **错误 toast 中英混用**(`presentation-deep-dive-2026-09-16.md:8 #8`)
   - `HomePage.ets:60` 英文 `"Failed to load notes"` vs `SubjectDetailPage.ets:60` 中文 `"笔记加载失败"`;Overlay 内已统一中文(`NoteDetailOverlay.ets:350, 418, 422, 442, 651`)
   - 修复方向:统一中文(或全英文)做 i18n

10. **renderers 全部用 `setTimeout` 做入场动画**(`frontend-ui-design-inventory-2026-09-06.md:661-689`)
    - ConceptDetailView 等 6 个文件各 `setTimeout × 1`,48/120/220 ms 三段;与 `DetailRenderQueue` 共存
    - 修复方向:改用共享 `DetailRenderQueue` 优先级 / `MotionPolicy` 旗舰提案

11. **`ConfDot` 已 unused**(`dead-code-archive-2026-07-19.md:33`)
    - 仍占 32 行;NoteDetailMeta 不再渲染 confidence dot
    - 修复方向:删除文件或归档到 `docs/legacy/`

12. **HarmonyOS 6.1 单进程 WebView 上限风险**(`frontend-performance-audit-2026-09-06.md:47-52`)
    - 笔记详情+AI 浮窗同开 ≈ 8 个 WebView,常见上限 6-8
    - 修复方向:关闭时主动 `controller.destroy()`(spec 已有此建议)

13. **fallback 内容可能与 DB 不一致**(`presentation-deep-dive-2026-09-16.md:8 #10`)
    - `KnowledgeGalaxyViewModel.loadNote` 失败时用 `planet.unit`(来自 `bundle.unit`)做 fallback,版本冲突检测不到
    - 修复方向:fallback 时显示 "正在重试 / 数据可能过时" 标记

### 🟢 低(技术债)

14. **6 处玻璃字面量**(子代理 E 全量核对)
    - `NoteDetailOverlay.ets:271` `'#12FFFFFF'` → `GLASS_14`(略差异)
    - `NoteDetailMeta.ets:54` `'#10FFFFFF'` → 应新加 `GLASS_12`
    - `NoteDetailMeta.ets:124` `'#00000000'`(渐变透明收尾,无现成令牌)
    - `NoteDetailMeta.ets:152` `'#0AFFFFFF'` → `GLASS_8`
    - `NoteIconButton.ets:25` `'#08FFFFFF'` → `GLASS_8`(直接可用)
    - `components/DetailStepList.ets:56` `'#0DFFFFFF'` → `GLASS_14`(直接可用)
    - `renderers/ComputationDetailView.ets:35` `const COMPUTE_ACCENT = '#FF64B7C8'` 重复定义 → 应改 `typeColor('计算题')`

15. **`UiDataCacheService.notesSnapshot.units` 冗余**(`presentation-deep-dive-2026-09-16.md:8 #16`)
    - 列表页只用 `notes`,`units` 仅 `NoteDetailOverlay.units` 用作 prerequisite/related 反查;同时维护两份成本微

16. **Zero animations**(`frontend-ui-design-inventory-2026-09-06.md:557-689`)
    - 浮层入场/退场 animateTo、DiscardConfirm 显隐过渡都缺;与 audit-2026-09-01 MotionPolicy 旗舰提案契合

17. **`bumpNotesVersion()` 三处写**(`deep-dive-2026-09-01.md:§F4.8`)
    - `HomeViewModel.ets:61` / `NotesViewModel.ets:77` / `KnowledgeGalaxyViewModel.ets:291-292` / `NoteDetailOverlay.ets:534-537` — 应抽 `NotesVersionBump.bump()` 进 common

---

## 11. 改进路径(按价值/工作量排序)

1. **(A) 修高优先级 bug**:`HomeViewModel/NotesViewModel.loadNote` 失败兜底 + 重试 + 错误 banner;`KnowledgeGalaxyViewModel.deleteNote` 失效 cache + bump notesVersion;抽 `NotesEditCoordinator` 让 saveEdit 退出 UI 层;`mockShare` 用 `if (DEBUG)` gate
2. **(B) 多设备适配**(spec 022 US #21):SM 全屏 / MD+ 限宽或主从右栏;78% 确认框改断点
3. **(C) 视觉一致性**:与 AgentFloatWindow 统一遮罩色 / 圆角 / 入场动效(C7 MotionPolicy)
4. **(D) 动效补强**:浮层入场/退场 animateTo、DiscardConfirm 显隐过渡、renderers 三段渐进改为共享 token
5. **(E) 组件库化**:43 个浮层本地组件的层级规范(spec 012 真空);MathTextRenderer 升格;6 处字面量改 GLASS_* 令牌
6. **(F) 测试加固**:为 6 个 renderer 补 Hypium(目前缺);LoadingState 永久卡死 e2e;WebView 数量监控

---

## 12. 附录:子代理交付汇总

| 子代理 | 状态 | 任务 | 关键产出 |
|---|---|---|---|
| A | ✅ | 三个核心 .ets 深度阅读 | 660/94/290 行文件结构 + state/callback/prop 完整清单;明确**全屏浮层** |
| B | ✅ | 调用链路 | 6 入口 + 回调绑定矩阵 + `onEdit` 空跑 + NoteCard 复用器官 + AI 草稿 5 trigger 点 |
| C | ✅ | 数据模型 / 服务 / ViewModel | NoteItem vs KnowledgeUnit 双类型映射 + 三层缓存链路 + Service/ViewModel/DAO/Adapter 索引 |
| D | ✅ | 文档(SPEC/ADR/UI 档案) | 30+ 文档清单;§F4.1-F4.9 9 个 audit finding 原文;US #21 / F4.2 / D3 / P4.2 等 open issue |
| E | ✅ | UI token / 组件 / 动效 | 22 文件三维档案 + 6 处字面量债 + 零动效分析 + 与 3 份前端研究档案对齐 |

---

---

## 附录 B:5 个子代理详细报告(原文归档)

> 以下为 5 个并行子代理的原始调研输出,作为综合报告的实证底料保留在此。每份子代理报告均按 primary source 严格 cite,可独立查阅。

### B.1 子代理 A · NoteDetailOverlay 三个核心 .ets 深度阅读

**任务**:阅读 `NoteDetailOverlay.ets`(660 行)/ `NoteDetailBody.ets`(94 行)/ `NoteDetailMeta.ets`(290 行)的完整结构。

#### 文件 1:`NoteDetailOverlay.ets`(660 行)— 容器/入口

**结构**
- `@Component struct NoteDetailOverlay`(顶层容器)
- `build()` → `Stack` 含 4 层:全屏遮罩 `Column`、主 `Column`(状态栏空白条 + 顶部 `Row` + `Scroll` + 底部 Action)、条件渲染 `LoadingState` / `DiscardConfirm`
- `aboutToAppear()` 处理 `generatedDraft` / `isCreating` 两种"开局编辑"模式
- 2 个 `@Builder`:`LoadingState`(加载占位)、`DiscardConfirm`(78% 宽居中卡片弹窗)
- 1 个 `@Watch`:`onDetailInputChanged`(note/unit/units/isCreating 任一变更时清空 localUnit)

**imports**
- `common`:主题 token(BG_DARK/BG_CARD/TEXT/DANGER/MINT/TEXT_2/TEXT_3/BORDER、F_SM/F_MD/W_SEMIBOLD/W_BOLD、R_MD/S_3/S_4)、OVERLAY_MASK_SOLID、类型(NoteItem/KnowledgeUnit/DifficultyLevel/ReviewStatus/uuid/isKnownNoteType/normalizeNoteType/ContentExcerptBuilder/NOTE_SUMMARY_MAX_LENGTH)、事件(NoteDraftReadyEvent/IncrementalDiffItem)
- `@kit.ArkUI`:`promptAction`
- `@kit.AbilityKit`:`common`
- 本地:NoteEditService、NoteCloseButton、NoteDetailMeta、NoteDetailBody、NoteActionBar、NoteIconButton、NoteEditForm、invalidateDetailRender、invalidateMarkdownText、KnowledgeUnitWriteErrorCode/KnowledgeUnitWriteResult

**装饰方法**
- `@Component struct NoteDetailOverlay`
- `@Builder LoadingState()`
- `@Builder DiscardConfirm()`

**state**
- `@Prop + @Watch`:note、unit、units、isCreating
- `@Prop`(无 Watch):generatedDraft
- `@StorageProp`:sbh(statusBarHeight)
- `@State`:localUnit、isEditing、titleText、summaryText、contentText、tagsText、4 个 initial* 快照、saving、showDiscardConfirm
- `private`:summaryBuilder(`ContentExcerptBuilder`)

**对外回调 prop**
- `onDraftCancel: () => void`
- `onDraftConfirm: (candidate: KnowledgeUnit) => Promise<KnowledgeUnit>`
- `onClose: () => void`
- `onEdit: (id: number) => void`
- `onDelete: (id: string) => void`
- `onSaved: (unit: KnowledgeUnit) => void`

**export**:`export struct NoteDetailOverlay`

#### 文件 2:`NoteDetailBody.ets`(94 行)— 正文分发

**结构**
- `@Component struct NoteDetailBody`
- `build()` → 单 `Column` 内调 `RenderByModel(this.renderModel())`
- `aboutToAppear` + `onRenderInputChanged`(`@Watch`)都触发 `resetRenderQueueIfNeeded`,key 用 `unit.id|updatedAt|version` 或 `note.rawId|id|date`
- 1 个 `@Builder`:`RenderByModel` 按 `model.category` 派发到 6 个 renderer

**imports**
- `common`:NoteItem、KnowledgeUnit
- `./model/`:DetailRenderModel、emptyDetailRenderModel、getDetailRenderModel、resetDetailRenderQueue
- `./renderers/`:ConceptDetailView、TheoremDetailView、FormulaDetailView、ProofDetailView、ComputationDetailView、FallbackDetailView

**装饰方法**
- `@Component struct NoteDetailBody`
- `@Builder RenderByModel(model: DetailRenderModel)`

**state**
- `@Prop + @Watch`:note、unit
- `@Prop`(无 Watch):units
- `private`:renderResetKey: string

**事件回调**:无(纯渲染)

**export**:`export struct NoteDetailBody`

#### 文件 3:`NoteDetailMeta.ets`(290 行)— 元信息头部

**结构**
- `@Component struct NoteDetailMeta`
- `build()` → `Column`:标签行(category chip + subject chip + 日期)+ 标题(F_XL W_BOLD)+ 副标题(公式语法走 MathTextRenderer,否则纯 Text)+ 3 个 `MetricCell`(掌握度/复习/难度)
- 整段 BG_CARD 底色 + 145° 三段式 `linearGradient`(从 `glassSurfaceColor` 渐变到透明),border 底部细线
- 1 个 `@Builder`:`MetricCell(label, value, color)` — 三列共享小卡片

**imports**
- `common`:主题 token、NoteItem/KnowledgeUnit/ContentExcerptBuilder/ContentProtocol/NOTE_SUMMARY_MAX_LENGTH/DifficultyLevel/ReviewStatus、`recentDate`/`typeColor`/`typeGlassColor`/`glassSurfaceColor`
- `../../shared/atoms/MathTextRenderer`

**装饰方法**
- `@Component struct NoteDetailMeta`
- `@Builder MetricCell(label, value, color)`

**state**
- `@Prop`:note、unit、units
- 模块级 const:`SUMMARY_BUILDER`、`CONTENT_PROTOCOL`(缓存 builder/protocol)

**事件回调**:无(纯渲染)

**export**:`export struct NoteDetailMeta`

#### Overlay 机制重点说明

- **形态:全屏**(非半屏 bottom sheet)。证据:`Stack` 宽高 100%、外部 `OVERLAY_MASK_SOLID` 全屏遮罩、内层用 `@StorageProp('statusBarHeight') sbh` 显式吃掉状态栏高度;没有任何 panelHeight/sheet 风格。DiscardConfirm 是嵌在里面的 78% 居中卡片,不是主层
- **挂载方式**:仅从这三个文件无法 100% 锁定。**不是 `@CustomDialog`**(无 `@CustomDialog/.open()` 痕迹)、**不是 NavDestination**(无 path/route)。签名(顶层 `Stack` + 全屏 mask + bind-style prop 接口)与 `bindContentCover` 模式一致 — 高度疑似 caller 通过 `bindContentCover(isShow, NoteDetailOverlay)` 触发,但未在本任务范围内检查 caller。
- **数据传入**:单向 `@Prop`:note/unit/units/isCreating/generatedDraft;unit 可为 null(加载态)
- **关闭/取消机制**:三路入口 — (a) `NoteCloseButton` 触发 `closeOrCancel`;(b) 背景遮罩 `.onClick` 同样触发 `closeOrCancel`;(c) 编辑模式下 `cancelEdit` → 若有未保存改动先弹 `DiscardConfirm`,选"放弃"才真退出。终极出口都是回调 `onClose()` / `onDraftCancel()` 抛给父组件,Overlay 自身不持有弹层开关状态。

---

### B.2 子代理 B · NoteDetailOverlay 调用链路

**任务**:调查 6 处挂载点的具体调用链与回调绑定。

**核心结论**:`NoteDetailOverlay`(`entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailOverlay.ets:40`)是覆盖在 Page 之上的全屏浮层,**不是** `router.pushUrl` 的独立页面。共 **5 个父级挂载点 × 6 个触发入口**(子代理 B 区分了 fallback 渲染 vs native/web 渲染):

#### 笔记详细页面入口清单

| # | 入口名 | 触发位置 | 触发方法 / 文件:行 | 传入参数 | 回调 |
|---|---|---|---|---|---|
| 1 | HomePage · 新建笔记 | `FloatingButton` 点击 | `openCreate()` `HomePage.ets:80-84, 190` → `creatingNote = true` → `HomePage.ets:192-198` | `isCreating: true`, `units: vm.units` | `onClose`, `onSaved` |
| 2 | HomePage · 最近笔记 | `HomeRecentNotes > NoteCard.onClick` | `HomeRecentNotes.ets:58` → `onSelect(note)` → `HomePage.openDetail` `HomePage.ets:69-78, 183` → `HomePage.ets:201-209` | `note` (NoteItem), `unit` (异步 loadNote), `units: vm.units` | `onClose`, `onDelete`, `onSaved` |
| 3 | SubjectDetailPage · 学科笔记 | `SubjectNoteList > NoteCard.onClick` | `SubjectNoteList.ets:86` → `onSelect(note)` → `SubjectDetailPage.openDetail` `SubjectDetailPage.ets:111-119, 178` → `SubjectDetailPage.ets:186-194` | `note`, `unit` (异步), `units: vm.units` | `onClose`, `onDelete`, `onSaved` |
| 4 | ReviewGraphView · fallback 知识星系 | `KnowledgeGalaxy` 内 `Planet(...).onClick`(背景行星 + 概览行星) | `ReviewGraphView.ets:1398, 870` → `onSelectPlanet(planet)` → `openPlanet(planet)` `ReviewGraphView.ets:230-242, 251-257, 406` → `ReviewGraphView.ets:419-427` | `note: planet.note`, `unit: planet.unit`, `units: vm.units` | `onClose`, `onDelete`, `onSaved` |
| 5 | KnowledgeGalaxy3DHost · 知识星系 (native/web) | 3D 场景 raycast tap 或 webview `node_selected` 消息 | `GalaxyComponent3DAdapter.ets:340-358` (native) / `GalaxyWebAdapter.ets:187-191` (web) → `callbacks.onSelect(id)` → `KnowledgeGalaxy3DHost.openById` `KnowledgeGalaxy3DHost.ets:53-67, 193-206` → `KnowledgeGalaxy3DHost.ets:126-134` | `note: planet.note`, `unit` (异步), `units: vm.units` | `onClose`, `onDelete`, `onSaved` |
| 6 | AgentFloatWindow · AI 草稿 | `ConversationWorkflow.publishDraft`(CaptureGraph 完成 → `AiService.generateNoteDraft`) | `AgentFloatWindow.ets:299-309`(`onDraftReady` 回调)→ `this.generatedDraft = event` → `AgentFloatWindow.ets:749-777` | `generatedDraft: NoteDraftReadyEvent`(含 `candidate: KnowledgeUnit`, `sourceCount`, `softIssueCount`, `incrementalDiff`) | `onClose`, `onDraftCancel`, `onDraftConfirm`, `onSaved`(没有 `onEdit`/`onDelete`,草稿模式独立) |

#### 关键观察
- **不带回调**:`onEdit` (id: number) 在所有调用点都没传 — 即 Overlay 内部 `startEdit()` 调 `onEdit(this.note.id)` 但外部忽略。`onEdit` 是空跑
- **回调签名**:
  - `onClose: () => void` — 所有 6 个入口都传
  - `onSaved: (unit: KnowledgeUnit) => void` — 所有 6 个入口都传(用于保存后更新本地 state)
  - `onDelete: (id: string) => void` — 4 个笔记入口都传(HomePage / SubjectDetailPage / ReviewGraphView / KnowledgeGalaxy3DHost);**新建 + AI 草稿入口不传**
  - `onDraftCancel` / `onDraftConfirm` — 仅 AI 草稿入口
- **笔记 ID / Unit 注入**:4 个笔记入口(2-5)都从**已加载的 NoteItem / PlanetNode** 拿到 `note` 全文,再**异步**调 `vm.loadNote(ctx, note.rawId)` 加载完整 `KnowledgeUnit` 写入 `selectedUnit`(`HomePage.ets:73-77`、`SubjectDetailPage.ets:114-118`、`ReviewGraphView.ets:235-241`、`KnowledgeGalaxy3DHost.ets:201-205`)。**不传 subjectId** — subject 由 NoteItem.subject 自带
- **AI 草稿入口的 `generatedDraft.candidate`**:本身就是完整 KnowledgeUnit,不需要 `loadNote`;Overlay 在 `aboutToAppear` 直接 `loadForm(this.generatedDraft.candidate)`(`NoteDetailOverlay.ets:69-79`)

#### 关键代码片段

**入口 1 — HomePage 新建**
```ets
// entry/src/main/ets/pages/Home/HomePage.ets:80-84
private openCreate = (): void => {
  this.selectedNote = null
  this.selectedUnit = null
  this.creatingNote = true
}
```
```ets
// entry/src/main/ets/pages/Home/HomePage.ets:190-198
FloatingButton({ onTap: this.openCreate })
if (this.creatingNote) {
  NoteDetailOverlay({ isCreating: true, units: this.vm.units,
    onClose: (): void => { this.creatingNote = false }, onSaved: this.handleSaved })
}
```

**入口 2 — HomePage 最近笔记**
```ets
// entry/src/main/ets/pages/Home/HomePage.ets:69-78
private openDetail = (note: NoteItem): void => {
  this.creatingNote = false
  this.selectedNote = note
  this.selectedUnit = null
  this.vm.loadNote(getContext(this), note.rawId).then((unit): void => { /* set selectedUnit */ })
}
```
```ets
// entry/src/main/ets/shared/organisms/NoteCard.ets:85
.onClick((): void => { if (this.onTap) { this.onTap() } })
```
```ets
// entry/src/main/ets/pages/Home/HomeRecentNotes.ets:55-59
NoteCard({ note: note, isLast: ..., onTap: (): void => { this.onSelect(note) } })
```
```ets
// entry/src/main/ets/pages/Home/HomePage.ets:201-209
if (this.selectedNote !== null) {
  NoteDetailOverlay({ note: this.selectedNote!, unit: this.selectedUnit, units: this.vm.units,
    onClose: this.closeDetail, onDelete: this.deleteNote, onSaved: this.handleSaved })
}
```

**入口 3 — SubjectDetailPage 学科笔记**
```ets
// entry/src/main/ets/pages/Notes/SubjectDetailPage.ets:176-194
SubjectNoteList({ notes: this.filteredNotes(), onSelect: this.openDetail })
...
if (this.selectedNote !== null) {
  NoteDetailOverlay({ note: this.selectedNote, unit: this.selectedUnit, units: this.vm.units,
    onClose: this.closeDetail, onDelete: this.deleteNote, onSaved: this.handleSaved })
}
```
```ets
// entry/src/main/ets/pages/Notes/SubjectNoteList.ets:80-87
LazyForEach(this.dataSource, (note, index) => {
  ListItem() { NoteCard({ note, isLast: ..., onTap: (): void => this.onSelect(note) }) }
})
```
(注:`SubjectDetailPage` 是被 `NotesPage.ets:64-68` `router.pushUrl` 进的,本身是 `@Entry`)

**入口 4 — ReviewGraphView 行星(fallback 渲染)**
```ets
// entry/src/main/ets/pages/Review/ReviewGraphView.ets:230-242
private openPlanet = (planet: PlanetNode): void => {
  this.stopRotation(); this.focusedPlanetId = planet.id
  this.selectedNote = planet.note; this.selectedUnit = planet.unit
  this.vm.loadNote(getContext(this), planet.id).then((unit) => { /* set selectedUnit */ })
}
```
```ets
// entry/src/main/ets/pages/Review/ReviewGraphView.ets:1394-1399
.position({ x: this.planetX(orbit, planet), y: this.planetY(orbit, planet) })
.onHover((isHover) => { this.onHoverPlanet(isHover ? planet.id : "") })
.onClick((): void => this.onSelectPlanet(planet))
```
```ets
// entry/src/main/ets/pages/Review/ReviewGraphView.ets:419-427
if (this.selectedNote !== null) {
  NoteDetailOverlay({ note: this.selectedNote!, unit: this.selectedUnit, units: this.vm.units,
    onClose: this.closeDetail, onDelete: this.deleteNote, onSaved: this.handleSaved })
}
```

**入口 5 — KnowledgeGalaxy3DHost 行星(native / web)**
```ets
// entry/src/main/ets/pages/Review/KnowledgeGalaxy3DHost.ets:126-134
if (this.selectedNote !== null) {
  NoteDetailOverlay({ note: this.selectedNote!, unit: this.selectedUnit, units: this.vm.units,
    onClose: this.closeDetail, onDelete: this.deleteNote, onSaved: this.handleSaved })
}
```
```ets
// entry/src/main/ets/pages/Review/KnowledgeGalaxy3DHost.ets:193-206
private openById(id: string): void {
  const planet = this.findPlanet(id); if (planet === null) return
  this.selectedId = planet.id
  this.selectedNote = planet.note; this.selectedUnit = planet.unit
  this.vm.loadNote(getContext(this), planet.id).then((unit) => { /* set selectedUnit */ })
}
```
```ets
// entry/src/main/ets/pages/Review/GalaxyComponent3DAdapter.ets:340-358 (native)
private handleTap(event: GestureEvent): void {
  this.camera.raycast({ x, y }, {}).then((hits) => {
    if (hits.length === 0) { this.callbacks.onClearSelection(); return }
    const id = this.nodePathToId.get(hits[0].node.path) ?? ''
    if (id.length > 0) { this.callbacks.onSelect(id) } else { this.callbacks.onClearSelection() }
  })
}
```
```ets
// entry/src/main/ets/pages/Review/GalaxyWebAdapter.ets:187-191 (web)
} else if (message.type === 'node_selected') {
  const id: string = message.payload.id ?? ''
  if (id.length > 0) { this.callbacks.onSelect(id) }
}
```

**入口 6 — AgentFloatWindow AI 草稿**
```ets
// entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets:299-309
onDraftReady: (ref: ConversationRunRef, event: NoteDraftReadyEvent): void => {
  if (event.originSessionId === ref.sessionId && this.service?.isCurrentRun(ref) === true
    && this.sessionExists(ref.sessionId) && this.inputVm.setDraftForSession(ref.sessionId, event)) {
    if (ref.sessionId === this.activeSid) {
      this.generatedDraft = event
      this.generatedDraftSessionId = ref.sessionId
    }
  } else { console.warn('[ConversationRun] code=DRAFT_TARGET_REJECTED; ...') }
}
```
```ets
// entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets:749-777
if (this.generatedDraft !== null) {
  NoteDetailOverlay({
    generatedDraft: this.generatedDraft,
    onClose: (): void => { this.inputVm.setDraftForSession(...); this.generatedDraft = null; ... },
    onDraftCancel: (): void => { /* 清空 + service.cancelDraft */ },
    onDraftConfirm: this.confirmDraft,
    onSaved: (_unit: KnowledgeUnit): void => { /* 清空 */ }
  })
}
```

**关键共享组件**(被多个入口复用)
```ets
// entry/src/main/ets/shared/organisms/NoteCard.ets:22 (props 定义)
onTap?: () => void
```

#### docs/specs 与 docs/adr 中相关提及

- **ADR (`docs/adr/`)**:0 条直接命中 `NoteDetailOverlay` / 笔记详情 / NoteOverlay — **无 ADR 单独记录这个交互**。设计权落在 `frontend-component-audit-2026-09-06.md` 和 `presentation-deep-dive-2026-09-16.md` 这两份 research 里
- **Spec 命中**(只有这些把 NoteDetail / NoteDetailOverlay 写进决策):
  - `docs/specs/020-reply-body-contract.md:68, 123, 147` — "NoteDetailOverlay 家族已全走 MDR(MarkdownRenderer),不动";渲染管线和 chat 分隔;FSR 仅剩 ChatBubble 消费
  - `docs/specs/021-chat-streaming-incremental-rendering.md:45-46, 53, 59-63, 153-155, 236, 251, 266, 277, 304` — chat 与 NoteDetail 渲染缓存(L1/L2/L3)隔离;NoteDetail 不在本 spec 切换,继续用 `MarkdownRenderer`/`FormulaSplitRenderer`
  - `docs/specs/022-multi-device-ui-adaptation.md:13, 49` (US21) — "笔记详情在手机全屏、宽屏侧面板显示" — 计划把 `NoteDetailOverlay` 在宽屏上变成右栏 panel(待做)

---

### B.3 子代理 C · 笔记详情页数据模型 / 持久化 / 服务层

**任务**:调查双类型映射 + 三层缓存 + Service/ViewModel/DAO/Adapter 索引。

#### 1. 笔记核心类型定义摘要(≤300 字)

两条核心类型共存于 common module,**NoteItem 是 UI 列表/卡片用扁平投影,KnowledgeUnit 是 RDB 真相源**。

- `NoteItem`(`common/src/main/ets/data/MockNotes.ets:6-34`,class) — 字段 `id:number`(数字哈希)、`title`、`type`、`subject`、`chapter`、`conf:0-1`、`body`(预览)、`tags`、`date:YYYY-MM-DD`、`rawId`(KnowledgeUnit.id 字符串)。只用于列表渲染;不持久化。
- `KnowledgeUnit`(`common/src/main/ets/models/CommonTypes.ets:57-86`,interface) — 字段 `id:string(UUID)`、`title`、`content`(完整正文)、`summary`(≤60 字摘要)、`tags[]`、`subject`、`category`(五选一:概念/定理/公式/证明题/计算题)、`chapter`、`difficulty:DifficultyLevel(1-4)`、`source`(camera_capture/manual/file_import)、`createdAt/updatedAt`(ms)、`reviewStatus`、`nextReviewAt`、`intervalDays`、`easeFactor`、`repetitions`、`prerequisites[]`、`related[]`、`embedding:number[]`、`userId`、`version`(乐观锁)。
- 持久化映射:NoteDao 的列名同 KnowledgeUnit 字段,JSON 数组字段(tags/prerequisites/related/embedding)以 JSON 字符串写入 RDB。详细列见 `entry/src/main/ets/database/NoteDao.ets:29-33` (NOTE_METADATA_COLUMNS)。
- 辅助枚举:DifficultyLevel(EASY=1/MEDIUM=2/HARD=3/EXPERT=4),ReviewStatus(new/learning/review/graduated/lapsed)。

#### 2. 读取一条笔记的代码路径(从触发到返回)

**A. 用户点击列表 → Page 调用 VM**

```ts
// entry/src/main/ets/pages/Notes/SubjectDetailPage.ets:111-119
private openDetail = (note: NoteItem): void => {
  this.selectedNote = note
  this.selectedUnit = null
  this.vm.loadNote(getContext(this), note.rawId).then((unit: KnowledgeUnit | null): void => {
    if (this.selectedNote !== null && this.selectedNote.id === note.id) {
      this.selectedUnit = unit
    }
  })
}
```
(同样的 `vm.loadNote(id)` 在 `pages/Home/HomePage.ets:73`、`pages/Review/KnowledgeGalaxy3DHost.ets:201` 复用。)

**B. ViewModel → UiDataCacheService(LRU 详情缓存,版本号驱动)**

```ts
// entry/src/main/ets/viewmodels/NotesViewModel.ets:59-69
async loadNote(context: Context, id: string): Promise<KnowledgeUnit | null> {
  if (id.length === 0) { return null }
  try {
    return await UiDataCacheService.loadDetail(context, id, UiDataCacheService.currentNotesVersion())
  } catch (e) { ... return null }
}
```

```ts
// entry/src/main/ets/services/UiDataCacheService.ets:294-320
static async loadDetail(context, id, version): Promise<KnowledgeUnit | null> {
  const cached = getDetailById(id, version)        // 命中返回
  if (cached !== null) { return cached }
  const loading = findDetailLoading(id, version)   // 去重并发
  if (loading !== null) { return loading.promise }
  const promise = queryDetail(context, id, version)
  detailLoadingEntries.push(new DetailLoadingEntry(id, version, promise))
  try { return await promise }
  finally { removeDetailLoading(id, version) }
}

private static async queryDetail(context, id, version): Promise<KnowledgeUnit | null> {
  const store = await DatabaseHelper.init(context)
  const unit = await new NoteDao(store).queryById(id)   // ← 落库查询
  if (unit !== null) { setDetail(unit, version) }       // 写入 LRU(上限 8 条 / 512KB)
  return unit
}
```

**C. DAO → RDB**

```ts
// entry/src/main/ets/database/NoteDao.ets:308-328
async queryById(id: string): Promise<KnowledgeUnit | null> {
  const predicates = new relationalStore.RdbPredicates('knowledge_unit')
  predicates.equalTo('id', id)
  return new Promise((resolve, reject) => {
    this.store.query(predicates, ['*'], (_err, rs) => {
      if (rs.goToFirstRow()) {
        const unit = NoteDao.rowToUnit(rs)   // ← 列→KnowledgeUnit 映射
        rs.close(); resolve(unit)
      } else { rs.close(); resolve(null) }
    })
  })
}
```

**D. Overlay 拿到 `unit` 后走渲染**

```ts
// entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailOverlay.ets:152-156
Column() {
  NoteDetailMeta({ note: this.note, unit: this.effectiveUnit(), units: this.units })
  NoteDetailBody({ note: this.note, unit: this.effectiveUnit(), units: this.units })
}
```

**缓存层说明**:
- `UiDataCacheService` 有两层缓存:① NotesSnapshot(列表 metadata,版本号对齐 AppStorage.notesVersion);② DetailCacheEntry(LRU 上限 8 条 + 512KB,key=`id|updatedAt|version|notesVersion`,被编辑/删除触发 `invalidateNote` 时清掉)。
- `DetailRenderCache`(8 条 + 512KB,key=`id|updatedAt|version|unitsHash`)在 `overlays/NoteDetailOverlay/model/DetailRenderCache.ets` 给详情 renderer 复用,编辑保存后由 NoteDetailOverlay `invalidateSavedRenderCaches` 清掉。

#### 3. Overlay 实际能拿到的字段对照表

`NoteDetailOverlay` 通过 `@Prop` 接收三个核心对象(`NoteDetailOverlay.ets:41-43`):

| Overlay 字段 | 来源 | 渲染位置 / 文件 |
|---|---|---|
| `note: NoteItem` | 列表行选中传入;`rawId` 是真 UUID | 兜底/草稿场景:title (l:165-171)、subtitle 取 `note.chapter` (l:179-185)、subject (l:236-241)、category = `note.type` (l:243-248)、conf% (l:250-253)、`note.date` (l:160) |
| `unit: KnowledgeUnit` | 懒加载:VM.loadNote→UiDataCacheService.loadDetail→NoteDao.queryById | NoteDetailMeta:title (l:163-171)、subtitle 取 `unit.summary` (l:179-185)、subject/category/difficulty/reviewStatus/updatedAt/createdAt (l:236-267);NoteDetailBody: content (buildDetailRenderModel l:346-351)、tags/prerequisites/related (l:389-394) |
| `units: KnowledgeUnit[]` | 列表快照(`vm.units`),全表 metadata | 仅用于解析 prerequisites/related 的 id → title (l:202-219、l:425-443) |
| `generatedDraft` (可选) | AI 草稿事件,`common/.../NoteGenerationModels.ets:256-272` | 头部分支(`modeTitle === '预览 AI 笔记草稿'`)、增量 diff (`incrementalDiff`) |

DetailRenderModel 暴露给六类 renderer(Concept/Theorem/Formula/Proof/Computation/Fallback)的字段集:
`category, subject, summary, body, sections[], tags[], prerequisites[], related[], sourceLabel, reviewLine, difficultyText, statusText` — 见 `overlays/NoteDetailOverlay/model/DetailRenderModel.ets:34-47`。

**Overlay 真正"看不到"的字段**(以 `unit === null` 兜底即可识别的):embedding(向量)、userId、createdAt 原始值(只在 metadata 区显示 updatedAt 优先)、intervals/easeFactor 数值(只在 reviewLine 拼接)、prerequisites/related 的 id 数组本体(只能查到 title)。

#### 4. 相关 Service / ViewModel 索引

**Service 层**

| 文件 | 关键方法 | 用途 |
|---|---|---|
| `entry/src/main/ets/services/NoteEditService.ets:14-25` | `upsert(ctx, unit, isCreating, expectedVersion)` | UI 编辑入口 → `KnowledgeUnitWriteService.create/update`,带乐观锁 |
| `entry/src/main/ets/services/KnowledgeUnitWriteService.ets:22-152` | `create/update/createWithCommitKey/updateWithCommitKey` | 协调器,调用 Repository + PostCommit effects |
| `entry/src/main/ets/services/KnowledgeUnitWriteServiceFactory.ets:23` | `create(ctx)` | 组装 Repository(=NoteDao)+effects |
| `entry/src/main/ets/services/UiDataCacheService.ets:115-444` | `loadDetail/loadNotesSnapshot/invalidateNote/currentNotesVersion` | 进程内缓存(LRU + 版本号) |
| `entry/src/main/ets/services/NoteGenerationRepositoryFactory.ets` | `create(ctx)` | AI 生成侧表工厂(仅生成,不写 KnowledgeUnit) |

**ViewModel 层**(全部走 `UiDataCacheService → NoteDao`)

| 文件 | 持有数据 | loadNote/deleteNote 路径 |
|---|---|---|
| `entry/src/main/ets/viewmodels/HomeViewModel.ets:43-67` | `notes: NoteItem[]`, `units: KnowledgeUnit[]` | `loadNote` → `UiDataCacheService.loadDetail`;`deleteNote` → `invalidateNote` + `NoteDao.deleteById` + `notesVersion++` |
| `entry/src/main/ets/viewmodels/NotesViewModel.ets:34-83` | 同上 + `subjectGroups`, `weeklyNewCount` | 同上;`loadNotes` 多调一次 `groupBySubject` |
| `entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets:270-287` | `systems`(星系聚合) | 同样 `loadNote` / `deleteNote` 路径 |
| `entry/src/main/ets/viewmodels/AgentInputViewModel.ets` | 草稿流 | 见 AI 草稿链路 |

**Edit / Delete 实现要点**
- 编辑:`NoteEditService.upsert` → `KnowledgeUnitWriteService.update` → `NoteDao.updateWithRevision`(乐观锁,版本不匹配抛 `KnowledgeUnitWriteErrorCode.VERSION_CONFLICT`)→ 写 `note_revision` 表。Overlay 保存成功后只 `localUnit = committed`,并未自动 invalidate UiDataCacheService 的 NotesSnapshot — 依赖外层 page(如 `SubjectDetailPage.handleSaved` → `selectedNote = unitToNoteItem(unit)`)重新刷新列表 + 主页 list 重载
- 删除:`HomeViewModel.deleteNote` / `NotesViewModel.deleteNote` → `UiDataCacheService.invalidateNote(id)` + `NoteDao.deleteById`(级联删 kg_edge / rag_embedding / rag_chunk)+ `AppStorage.setOrCreate('notesVersion', version+1)` + 重新 `loadNotes`。`NoteDao.deleteById` 详见 `entry/src/main/ets/database/NoteDao.ets:261-305`
- Overlay 中的入口:
  - 删除:头部右上角 `NoteIconButton`(`NoteDetailOverlay.ets:107-113`,DANGER 颜色,仅 `!isCreating && !isEditing && effectiveUnit !== null` 时显示)→ `confirmDelete` (l:657-659) → 调 `onDelete(note.rawId ?? note.id.toString())`
  - 编辑:底部 `NoteActionBar`(`NoteActionBar.ets:16-18`,完整 `onEdit()` + `onShare()` mock share),仅在非编辑模式显示 → `startEdit` (l:350-359) → `onEdit(note.id)`(注:此 `onEdit` 在所有调用方均为空 stub,Overlay 内部直接走 `isEditing = true`)
  - 保存:右下 check 按钮(`NoteDetailOverlay.ets:184-191`) → `saveEdit` (l:413-467) → `NoteEditService.upsert`,失败提示 VERSION_CONFLICT

**Dao / Adapter / Models 索引**(供后续子代理定位)
- `agents/src/main/ets/models/NoteDaoInterface.ets:27-32` — agents 端适配契约(insert/update/insertWithCommitKey/updateWithCommitKey)
- `entry/src/main/ets/adapters/NoteDaoAdapter.ets:8-74` — entry 侧实现,包 `KnowledgeUnitWriteService`
- `entry/src/main/ets/database/NoteDao.ets:35-705` — KnowledgeUnit CRUD + note_revision + note_generation_commit 三表写入(RDB 事务)
- `entry/src/main/ets/database/NoteGenerationRepository.ets:28-596` — AI 生成侧表(note_generation_run/source/checkpoint/commit/log)
- `entry/src/main/ets/utils/NoteItemMapper.ets:106-134` — `unitToNoteItem` / `unitsToNoteItems`(KnowledgeUnit → NoteItem,含 `confidence()` 按 reviewStatus 映射、`stableNumericId()` 哈希)
- `common/src/main/ets/models/NoteGenerationModels.ets` — NoteGenerationRequest/Result/Repository/Checkpoint/Run/Draft 等 AI 契约;`NoteDraftReadyEvent` 用于 Overlay 接收草稿
- `common/src/main/ets/tools/NoteQueryTools.ets` — 工具注册层用的查询工具(Skill 入口)

**Overlay 5 个调用点**(`NoteDetailOverlay({...})` 实例化处,均传 `note/unit/units/onClose/onDelete/onSaved`):
1. `pages/Home/HomePage.ets:192`(`isCreating`) / `pages/Home/HomePage.ets:201`(详情)
2. `pages/Notes/SubjectDetailPage.ets:186`
3. `pages/Review/KnowledgeGalaxy3DHost.ets:126`
4. `pages/Review/ReviewGraphView.ets:420`
5. `overlays/AgentFloatWindow/AgentFloatWindow.ets:750`

**给父代理的建议**:
- Overlay 保存成功后的 `UiDataCacheService` 顶层 `notesSnapshot` 与 `subjectGroupsSnapshot` 不会自动失效,需要确认各 page 是否在外层调用 `loadNotes` 重新加载
- `KnowledgeUnit` 没有 `imageUrl` 字段,与图片相关的展示应走 OCR 产物或 `KnowledgeRelationDao` / `RagEmbeddingDao`,不是当前详情页的字段
- `generatedDraft` 路径(`NoteDraftReadyEvent`)由 AI 浮窗/Dispatcher 触发,详情页 132-148 行展示了 `incrementalDiff` 的渲染

---

### B.4 子代理 D · 笔记详细页面相关文档清单

**任务**:调研所有与 `NoteDetailOverlay` 相关的文档(SPEC / ADR / 设计档案 / Issue)。

#### 0. 核心定位

项目里**不存在独立 NoteDetail Page**——笔记详情 UI 是一个**浮层**(`entry/src/main/ets/overlays/NoteDetailOverlay/`,22 文件),由 `HomePage` / `SubjectDetailPage` / `ReviewGraphView` 三处按需挂载(注:实际上还有 `KnowledgeGalaxy3DHost` 与 `AgentFloatWindow` 共 5 处,2026-09-16 当时的 research 报告未合并这两个新挂载点)。**所有"笔记详情页"文档指的都是这个浮层**。本报告统一按 `NoteDetailOverlay` 视角汇报。

#### 1. 相关文档清单(35 行)

| 文件 | 段落定位 | 摘要 | 关键观点 |
|---|---|---|---|
| `docs/specs/022-multi-device-ui-adaptation.md` | §Problem Statement L13, User Story #21 L49, §Responsive product rules L101 | 多端 UI 适配 spec,P2,2026-09-08 ready/implementation deferred | 笔记详情在 XS/SM 全屏、MD+ 改限宽侧面板;Phone 假定当前固定,需拆窗宽断点状态。User Story #21: "笔记详情在手机全屏、宽屏侧面板显示" |
| `docs/specs/020-reply-body-contract.md` | L68, L123, L147 | Reply Body 契约 spec | **NoteDetailOverlay 家族已全走 MarkdownRenderer,无需动**;公式拆分实现分 FSR / MarkdownParser / MathTextRenderer 三套 |
| `docs/specs/021-chat-streaming-incremental-rendering.md` | L20-21, L45-46, L53, L59-63, L153-155, L236, L251, L266, L277, L304 | chat 流式增量渲染 spec | **NoteDetail 继续用旧 `MarkdownRenderer`/`FormulaSplitRenderer`**;chat/NoteDetail L1/L3 隔离,L2 ArkWeb 引擎预热共享 |
| `docs/specs/021-knowledge-graph-rdb.md` | L125 | 知识图谱 RDB spec | `prerequisites/related` 仍保留在 `KnowledgeUnit` 及 revision 表中,**供旧详情页面兼容**;不再是新关系写入或生产图谱读取的事实源 |
| `docs/research/frontend-component-audit-2026-09-06.md` | §6 L114-126, §7 L137, L140 | 组件分层审计 | NoteDetailOverlay = 22 文件,结构最深组合树;renderers/ 六件按 5 种 NoteType 策略分派;**float 本地组件无层级规则(spec 012 真空)** |
| `docs/research/frontend-ui-design-inventory-2026-09-06.md` | §overlays/NoteDetailOverlay L557-689, L83, L193 | 96 件 UI 设计/布局/动效档案 | 22 文件逐件三维档案(令牌/布局/动效);OVERLAY_MASK_SOLID 遮罩;共 7 类 renderer,每类 ~280 行 |
| `docs/research/frontend-flow-walkthrough-2026-09-06.md` | 路径 4 L101-130, 横切 A L143-144, 横切 C L166-173 | 用户路径走查 | 入口三处:HomeRecentNotes/ReviewGraphView/NotesList;P4.1-P4.4 四个路径级问题;**NoteDetailOverlay 是少数正确用 `@StorageProp('statusBarHeight')` 响应的两个浮层之一** |
| `docs/research/frontend-performance-audit-2026-09-06.md` | L47-52, L150 | 性能审计 | 笔记详情 1 屏 = 7+ 个 WebView;**笔记详情+AI 浮窗同时打开 = 8+ 个 WebView → HarmonyOS 6.1 单进程 WebView 上限风险(常见 6-8)**;建议关闭时主动 `controller.destroy()` |
| `docs/research/frontend-persistence-2026-09-06.md` | L43, L65 | 持久化调研 | 笔记详情渲染走 `UiDataCacheService.detailEntries`,进程内 LRU 淘汰(`trimDetailCache`) |
| `docs/research/frontend-error-handling-2026-09-06.md` | L81-82 | 错误处理清单 | `NoteDetailOverlay.ets:371` 校验提示 / `:550` 分享功能暂未开放(feature flag) |
| `docs/research/frontend-healthcheck-plan-2026-09-06.md` | L91 | 健康检查候选 | NoteDetailOverlay:529 涉入 notesVersion 总线 |
| `docs/research/harmonyos-multi-device-ui-adaptation-2026-09-08.md` | L316, L524 | 多端适配研究 | 笔记详情确认框 78% (`.width('78%')` at :257) → 超宽文本行过长;SM 全屏 / MD+ 限宽详情或主从右栏 |
| `docs/research/chat-markdown-latex-render-jank-2026-09-13.md` | L54 | 公式渲染 jank 调研 | **NoteDetailOverlay 已有 `DetailRenderQueue`(16ms 节拍/8ms 帧预算/上限 80)+ `DetailRenderCache`,chat 没有——这是 chat 借鉴对象** |
| `docs/research/agent-float-window-component-research-2026-09-11.md` | L34, L55, L150, L164, L300 | 浮窗研究 | AgentFloatWindow :29 跨 overlay import NoteDetailOverlay;**跨 overlay 业务流:onDraftReady→NoteDetailOverlay→confirmDraft/cancelDraft**;死组件检测口径可平移到 NoteDetailOverlay 22 文件 |
| `docs/research/presentation-deep-dive-2026-09-16.md` | §2 L31, §4.1 L111-117, L203, §5.2 L239, §8 L490-509, §9 Loop #5 | 呈现段深度调研 | **核心 bug**:① `NoteDetailOverlay.effectiveUnit()` 永久 LoadingState(D3);② `NotesViewModel.loadNote` 失败后 `selectedUnit = null` 但仍开 overlay;③ `units` prop 在 list 页没用但 `setNotesSnapshot` 总算两份 |
| `docs/research/fixture-isolation-result-2026-09-16.md` | §3.4 L98-102, §5 D3 L188 | 隔离验证 | 笔记详情页 prerequisites/related 显示**未验证**(误触 AI 浮窗);D3 永久 LoadingState 入待修 backlog |
| `docs/research/data-presentation-flow-2026-09-16.md` | L214, L370 | 呈现链路调研 | 手动编辑路径 `entry/src/main/ets/services/NoteEditService.ets` 未深读,UI 由 `NoteDetailOverlay` 调用;NoteDetailOverlay 整体未细看 |
| `docs/research/project-positioning-2026-09-04.md` | L96, L155 | 项目定位 | `entry` 模块组成:5 Tab + 浮窗(AgentFloatWindow/CameraOverlay/NoteDetailOverlay);**5 类专属 renderer**(Computation/Concept/Fallback/Formula/Proof/Theorem)统一走 `DetailSection + DetailStepList + DetailMetaFooter` |
| `docs/research/frontend-interaction-states-2026-09-06.md` | L10, L20, L121 | 交互态调研 | 5 态失衡;CameraOverlay 是少数有 loading/disabled 态的浮层,NoteDetailOverlay 没有 |
| `docs/agents/demo-script-2026-09-06.md` | §2 步 5 L31 | 复赛演示脚本 | 步 5:打开笔记详情 → 验证 MM-MD-v1 渲染(独立公式 `$$` 单独成行,字段分区);**叙事:结构化输出经协议校验,不合格直接报错不落库** |
| `docs/agents/smoke-test.md` | §1 步 6 L12 | 手动 smoke test 矩阵 | 步 6:**笔记详情浮层打开/关闭,期望浮层无残留** |
| `docs/agents/backend-migration-handoff.md` | L112, L171 | 后端迁移 handoff | 1880 行 ReviewGraphView 拆 5 文件计划中含 `NoteDetailPanel`;`overlays/` = AgentFloatWindow / CameraOverlay / NoteDetailOverlay |
| `docs/legacy/mindtrace/architecture/audit-2026-09-01.md` | L67 | 完整审计 | ✅ AgentFloatWindow/CameraOverlay/NoteDetailOverlay 三大浮层都在 OK |
| `docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md` | L71, L87, L90, L977, L1013 | 完整审计(L876 行) | NoteDetailOverlay 25 文件 / NoteDetailOverlay.ets 516 行 / DetailRenderModel 449 行;LOC top 7 第 4 位(deep-dive §F4.1) |
| `docs/legacy/mindtrace/architecture/deep-dive-2026-09-01.md` | File 4 §F4.1-F4.9 L365-468, §Cross-file L849-853 | 7 个最大文件深度审计 | **§F4.1 (P0) mockShare shipped in production:L555-557 仅 toast "分享功能暂未开放"**;F4.2 saveEdit 5 步混杂(VM 逻辑进 UI);F4.3 5 个 @Watch 触发同一 watcher;F4.4 parseTags 分隔符不全;F4.5/F4.6 category/tag 重叠;F4.7 DiscardConfirm 嵌套布局;F4.8 bumpNotesVersion 三处写;F4.9 SOURCE_CAMERA 常量 |
| `docs/legacy/mindtrace/architecture/lint-baseline-2026-09-01.json` | L848-1057 | lint 基线 | NoteDetailOverlay 全部 22 文件逐个条目 |
| `docs/legacy/mindtrace/architecture/audit-2026-09-01.html` | L355 | 审计 HTML | 树状图显示 `overlays/NoteDetailOverlay/` ← ✅ (smoke test 5) |
| `docs/legacy/mindtrace/plans/w3/frontend-architecture-2026-07-17.md` | L3, §二 L47-89 | W3 前端架构(历史) | "NoteDetailOverlay 对齐 v2-ui";5 Tab + 3 浮层 + OverlayService 互斥;`SubjectDetailPage` 职责:学科内笔记浏览,点击行打开现有 NoteDetailOverlay |
| `docs/legacy/mindtrace/plans/w3/notes-editor-markdown-2026-07-20.md` | L64-70 | 笔记编辑器 Markdown(历史) | 列出 NoteDetailOverlay 装配层 4 文件 |
| `docs/legacy/mindtrace/plans/w3/ui-preload-cache-optimization-2026-07-21.md` | L12-122 | UI 预加载缓存优化(历史) | "笔记详情目前按点击后查库,渲染模型和 Markdown 解析未缓存";NoteDetailOverlay 新增 `DetailRenderCache`(已落地) |
| `docs/legacy/mindtrace/plans/w3/latex-render-db-ui-guide-2026-07-20.html` | §九 L821-1101 | LaTeX 渲染 DB-UI 指南(历史) | AI 对话和笔记详情共用 `MathTextRenderer`;**建议统一 RichMathRenderer**;NoteSection.ets 笔记分区改用 RichMathRenderer |
| `docs/legacy/mindtrace/plans/w3/rich-math-rendering-redesign-2026-07-20.html` | §笔记详情 L560-909, L1144 | 富数学渲染重设计(历史) | 笔记详情按分区接 RichMathRenderer,不做整页 Web;`NoteSection.ets` 改 RichMathRenderer;**未实施,仅方案** |
| `docs/legacy/mindtrace/plans/w3/render-protocol-optimization-route-2026-07-22.md` | L1880, L1996 | 渲染协议优化(历史) | "NoteDetailOverlay 改用 `List + LazyForEach`,每个 `DetailBlock` 对应一个 `ListItem`" — **未实施** |
| `docs/legacy/mindtrace/plans/w3/dead-code-archive-2026-07-19.md` | L33 | 死代码归档 | `ConfDot.ets` unused(2026-07 标记);NoteDetailMeta 不再渲染 confidence dot |
| `docs/legacy/mindtrace/plans/w3/notes-page-structure-proposal-2026-07-19.html` | L627-849 | Notes 页结构提案(历史) | "完成 smoke test 后,再进入笔记详情页新结构规划" — 详情页重构**未实施** |
| `docs/legacy/mindtrace/plans/w3/agent-memory-flow-2026-07-19.md` | L204-222 | Agent 记忆流(历史) | "笔记详情中的摘要也容易只有一句话" — 代码硬限制,非 LLM token 截断 |
| `docs/legacy/mindtrace/plans/w3/chapter-field-refactor-2026-07-22.md` | L86-92, L154-155 | 章节字段重构(历史) | 笔记详情编辑保存涉及 `NoteDetailOverlay.ets` + `DetailRenderModel.ets` |
| `docs/legacy/mindtrace/plans/w3/dataflow-knowledge-structures-2026-07-20.html` | §详情页 L555-624 | 数据流文档(历史) | 当前详情页是通用分段渲染,**不存在独立 `StructuredNoteView` 或五类专用组件**(注:与今天不符,5 类 renderer 已落地) |
| `docs/legacy/mindtrace/plans/w3/summary.md` | L17, L30 | W3 周报 | "NoteDetailOverlay 装配层 + 5 个子组件补全中文注释" |
| `docs/legacy/mindtrace/competition/references-2026-07-26.md` | L13 | 比赛参考 | KaTeX 用于 chat 气泡 + **笔记详情页公式展示** + 公式预览卡片 |
| `docs/legacy/api/contract.md` | L235 | API 契约 | `image` 路径涉及拍照/相册 → `CameraOverlay` / `PhotoViewPicker` → OCR → LLM 分类 |
| `CONTEXT.md` | (无) | 项目词汇表 | **未直接定义 NoteDetailOverlay**;NoteDetail 是隐含概念,通过 NoteType / KnowledgeUnit 间接相关 |

#### 2. 笔记详情页目标/限制(≤200 字)

**目标**:作为在 Home / Notes / Review 三页面共享的"覆盖式浮层"(`NoteDetailOverlay`),承担笔记查看/编辑/删除/分享占位,围绕 5 类 NoteType(概念/定理/公式/证明题/计算题)策略分派 6 个 renderer 渲染 MM-MD-v1 Markdown + KaTeX 公式,通过 `MarkdownRenderer` 与 chat 共享同一渲染管线。配套 `DetailRenderQueue`(16ms 节拍/8ms 帧预算/上限 80)与 `DetailRenderCache` 串行化渲染。

**限制**:① 仅作浮层,不做独立 page,fix by Tabs sibling 设计;② 依赖 `notesVersion` AppStorage 手工总线三处写;③ 多端未适配(全屏 + 78% 宽确认框,无窗宽断点);④ 单进程 WebView 上限风险(笔记详情+AI 浮窗同开 ≈8 个);⑤ mockShare / LoadingState 永久转圈 / bumpNotesVersion / parseTags 等 P0-P2 历史债仍存。

#### 3. 审计 finding 与 open issue(原文摘录,每条 ≤5 行)

**3.1 audit-deepdive-2026-09-01 §F4.1(P0,仍开)**
> **[P0] `mockShare` shipped in production — §F4.1.** L555-557:
> ```
> private mockShare = (): void => {
>   promptAction.showToast({ message: '分享功能暂未开放', duration: 1500 })
> }
> ```
> Either implement or gate by `if (DEBUG)` and route to a real provider.

**3.2 audit-deepdive-2026-09-01 §F4.2(P0,仍开)**
> **[P0] Save flow mixes read-modify-write with cache invalidation — §F4.2.** L359-402 `saveEdit`: 1. DatabaseHelper.init 2. Builds KnowledgeUnit 3. Persists 4. Invalidates 3 caches 5. Bumps AppStorage 6. onSaved 7. localUnit=saved+clear editing. **Extract to a `NotesEditCoordinator`**.

**3.3 presentation-deepdive §8 #7(D3,仍开)**
> **`NoteDetailOverlay.effectiveUnit()` 永久 LoadingState** | `selectedUnit === null` + `note.title`/`note.body` 都为空时,`canRenderReadOnlyDetail()` 返回 false,触发 `LoadingState()`(`NoteDetailOverlay.ets:213-237`),**但没人触发重试**;`HomeViewModel.loadNote` 失败后只 console.warn,UI 永久转圈。 | `entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailOverlay.ets:146-154, 308-313`;`entry/src/main/ets/viewmodels/HomeViewModel.ets:43-53`

**3.4 presentation-deepdive §8 #15(中优,仍开)**
> **`NotesViewModel.loadNote` 失败后 `selectedUnit = null`,UI 仍渲染 NoteDetailOverlay** | `SubjectDetailPage.ets:111-119` 失败时 `this.selectedUnit = unit`(null),但 `NoteDetailOverlay` 仍打开,显示 `LoadingState`(`NoteDetailOverlay.ets:213-237`)。 | `entry/src/main/ets/pages/Notes/SubjectDetailPage.ets:111-119`

**3.5 frontend-flow-walkthrough P4.2(高,待核实)**
> 删除后是否 bump notesVersion 待核实 (notes 列表是否同步刷新依赖此) | NoteDetailOverlay.ets | 高

**3.6 fixture-isolation-result D3(待修 backlog)**
> D3 | `NoteDetailOverlay` | 永久 LoadingState(可能就是你最初报告的"底部英文小字") | 待修

**3.7 audit-deepdive §F4.8(P2,与全项目共用)**
> **`bumpNotesVersion()` reads/writes `AppStorage` directly — §F4.8.** L534-537: bypasses any wrapper. Combined with `ReviewGraphView`'s identical bump (L291-292), version state is **two writers**. Wrap behind `NotesVersionBump.bump()` in `common`.

**3.8 frontend-performance-audit(未指定优先级,仍在风险清单)**
> **风险点**: 笔记详情 + AI 浮窗同时打开 (评审 demo 常见) → 8+ 个 Webview 在 ArkTS 进程内, **每个 Webview 占用 JS 引擎 + 渲染线程**。HarmonyOS 6.1 单进程 Webview 上限需查 SDK d.ts (常见 6-8 个)。

#### 4. GitHub Issue 状态(相关待开/已开)

- **#93**([spec 022 引用](../specs/022-multi-device-ui-adaptation.md)):**multi-device UI adaptation**,ready/implementation deferred,核心覆盖笔记详情浮层在宽屏的形态
- **未直接命中** `NoteDetailOverlay` 字样的 Issue(本次仅文档侧调研,未跑 `gh issue list`);但 presentation-deep-dive §8 给出 4 条建议新建 issue 的项(D3 优先)

#### 5. 总结判断

**笔记详情页架构当前是"稳定的债 + 已铺好优化路径"**:
- **稳定**:笔记详情 22 文件结构稳定,MarkdownRenderer / DetailRenderCache / DetailRenderQueue / 5 类 renderer 链路通顺;smoke test 步 6 与 demo 步 5 都把它作为核心节点验证
- **历史债**(待修、未实施):F4.1 mockShare、F4.2 saveEdit 混杂、D3 永久 LoadingState、P4.2 notesVersion、multi-device 全屏假定、`NoteDetailOverlay` 改 `List+LazyForEach` 方案未实施
- **已规划但延期**:spec 022 多端适配 ready/implementation deferred(用户故事 #21 直接描述笔记详情在宽屏形态);spec 020 明确说"NoteDetailOverlay 家族已走 MDR,无需动"
- **禁止改动**:依 spec 020-021,chat 流式增量渲染首轮**不**碰 NoteDetail,二者 L1/L3 隔离,只 L2 ArkWeb 引擎预热共享

---

### B.5 子代理 E · 笔记详情页 UI 设计 token / 通用组件 / 动效约定

**任务**:目录中标注为"3 个 .ets",但实际有 **23 个** .ets(顶层 9 + components/5 + renderers/6 + model/2 + 子目录 1 个 IconButton)。下面以完整 23 件为口径,顶层 9 件逐一展开;子目录 14 件按 inventory/audit 已收录。

#### 一、设计 token 使用清单

**1. 资源型 token `$r('app.color/string/float.xxx')`**:**零使用**。
- `entry/src/main/resources/base/element/color.json` 仅 1 项(`start_window_background #FFFFFF`),string 仅 5 项能力标签,float 仅 1 项(`page_text_font_size`)
- `entry/src/main/resources/base/profile/` 仅有 `main_pages.json` + `backup_config.json`,无 token
- 因此 NoteDetailOverlay **不走** ArkUI 资源 `$r` 通道

**2. TS 令牌(`common/ColorTokens.ets`,233 行)** — 唯一真源,100% 走 `import ... from 'common'`:

| 族 | NoteDetailOverlay 内出现(按文件) |
|---|---|
| 主色板 | `MINT` (NoteDetailOverlay.ets:6 / 286 / NoteDetailMeta.ets:6 / ConfDot.ets:15); `PURPLE` (ChipTag.ets:17) |
| 语义色 | `DANGER` (NoteDetailOverlay.ets:6 / 110 / ConfDot.ets:15); `AMBER` (ConfDot.ets:15) |
| 背景 | `BG_DARK` (NoteDetailOverlay.ets:6 / 87 / 196 / 206 / 281; NoteActionBar.ets:5); `BG_CARD` (NoteDetailOverlay.ets:6 / 294; NoteDetailMeta.ets:6 / 118; NoteEditForm.ets:6 / 39 / 51 / 63 / 75) |
| 文字 4 级 | `TEXT` (NoteDetailOverlay.ets:6 / 96 / 224 / 250; NoteDetailMeta.ets:6 / 72 / ChipTag.ets:17; NoteEditForm.ets:8 / 37 / 49 / 61 / 73); `TEXT_2` (NoteDetailOverlay.ets:6 / 171 / 257 / 266; NoteDetailMeta.ets:6 / 51 / 111 / ChipTag.ets:17; NoteActionBar.ets:5; NoteCloseButton.ets:19; NoteIconButton.ets:5 / 20; NoteEditForm.ets:9 / 92); `TEXT_3` (NoteDetailOverlay.ets:6 / 136 / 143 / 230 / ChipTag.ets:17; NoteDetailMeta.ets:6 / 63 / 97 / 135; NoteEditForm.ets:9 / 38 / 50 / 62 / 74); `TEXT_4` (ChipTag.ets:17,导入但未用) |
| 边框 | `BORDER` (NoteDetailOverlay.ets:6 / 295; NoteDetailMeta.ets:6 / 127 / 153; NoteActionBar.ets:5 / 23; NoteEditForm.ets:7 / 41 / 53 / 65 / 77; ChipTag.ets:17 / 40) |
| 玻璃色 | `GLASS_10` (ChipTag.ets:23 / 54-56; NoteCloseButton.ets:19 / 35; NoteIconButton.ets:5 / 12) |
| 遮罩 | `OVERLAY_MASK_SOLID` (NoteDetailOverlay.ets:11 / 83 / 301) |
| 间距(S_1..S_6) | S_1×N、S_2×N、S_3×N、S_4×N、S_5×N、S_6 — 几乎每个文件都用了整套(NoteDetailOverlay / Meta / ActionBar / CloseButton / EditForm / IconButton / ChipTag) |
| 圆角(R_SM..R_FULL) | `R_MD` (NoteDetailOverlay.ets:9 / 270 / 285 / 293; NoteDetailMeta.ets:8 / 43 / 53; NoteEditForm.ets:14 / 40 / 52 / 64 / 76; NoteIconButton.ets:5 / 24; ChipTag.ets:19 / 38); `R_LG` (NoteDetailMeta.ets:8 / 151); `R_SM` (ChipTag.ets:19 / 38); `R_FULL` (ChipTag.ets:19 / 38) |
| 字号(F_XS..F_XL) | `F_XS` (NoteDetailMeta.ets:9 / 39 / 49 / 62 / 134; ChipTag.ets:20 / 34); `F_SM` (NoteDetailOverlay.ets:7 / 135 / 142 / 229 / 256 / 263 / 279; NoteDetailMeta.ets:9 / 86 / 88 / 96 / 141; NoteEditForm.ets:11 / 48 / 60 / 72 / 90; ChipTag.ets:20 / 34); `F_BASE` (NoteEditForm.ets:12 / 36); `F_MD` (NoteDetailOverlay.ets:7 / 94 / 222 / 248; ChipTag.ets 导入但未直接出现); `F_XL` (NoteDetailMeta.ets:9 / 70) |
| 字重(W_*) | `W_MEDIUM` (NoteDetailMeta.ets:10 / 50; ChipTag.ets:21 / 36); `W_SEMIBOLD` (NoteDetailOverlay.ets:8 / 95 / 223 / 265 / 280; NoteDetailMeta.ets:10 / 142; NoteEditForm.ets:13 / 91; ChipTag.ets:21 / 36); `W_BOLD` (NoteDetailOverlay.ets:8 / 249; NoteDetailMeta.ets:10 / 40 / 71; ChipTag.ets:21 / 36) |
| 工具函数(NoteTaxonomy / render) | `typeColor(t)` (NoteDetailMeta.ets:19 / 41 / 109 / 122); `typeGlassColor(t)` (NoteDetailMeta.ets:20 / 44); `glassSurfaceColor(c)` (NoteDetailMeta.ets:21 / 122); `recentDate(s)` (NoteDetailMeta.ets:18 / 160); `ContentExcerptBuilder` 实例 (NoteDetailOverlay.ets:19 / 63 / 418; NoteDetailMeta.ets:14 / 25 / 223); `ContentProtocol` 实例 (NoteDetailMeta.ets:14 / 26 / 80); `NOTE_SUMMARY_MAX_LENGTH` (NoteDetailOverlay.ets:20 / 418; NoteDetailMeta.ets:15 / 223); `normalizeNoteType/isKnownNoteType` (NoteDetailOverlay.ets:17-18 / 575-586 / 598) |

**3. 硬编码字面量(TOKEN 绕过)** — 共 6 处,集中在玻璃色:

| 文件:行 | 字面量 | 应替代令牌 |
|---|---|---|
| `NoteDetailOverlay.ets:271` | `'#12FFFFFF'` (放弃按钮次级底) | `GLASS_14`(虽值为 `#1AFFFFFF` 略有差异)或新加 `GLASS_12` |
| `NoteDetailMeta.ets:54` | `'#10FFFFFF'` (学科 chip 底) | 同上 |
| `NoteDetailMeta.ets:124` | `'#00000000'` (linearGradient 透明收尾) | 透明,无现成令牌 |
| `NoteDetailMeta.ets:152` | `'#0AFFFFFF'` (MetricCell 卡底) | `GLASS_8`(值 `#08FFFFFF`)几乎一致 |
| `NoteIconButton.ets:25` | `'#08FFFFFF'` (disabled 底) | `GLASS_8` 直接可用 |
| `components/DetailStepList.ets:56` | `'#0DFFFFFF'` | `GLASS_14` 直接可用 |
| `renderers/ComputationDetailView.ets:35` | `const COMPUTE_ACCENT = '#FF64B7C8'` | 重复定义,ColorTokens 已收 TYPE_COLORS["计算题"]=`#FF64B7C8`,应改用 `typeColor('计算题')` |

#### 二、组件复用清单

**A. 自研组件(本 overlay 目录内)**

| 组件 | 文件:行 | 角色 | 主要消费方 |
|---|---|---|---|
| `NoteCloseButton` | NoteCloseButton.ets:23 | 圆形玻璃 X 关闭钮(32vp, GLASS_10 + AppIcon) | NoteDetailOverlay.ets:90 |
| `NoteIconButton` | NoteIconButton.ets:9 | 通用 36vp 玻璃 icon 按钮(支持 `name`/`color`/`bgColor`/`boxSize`/`isEnabled`) | NoteDetailOverlay.ets:108 / 169 / 177 / 184; NoteActionBar.ets:16 / 18 |
| `ChipTag` | ChipTag.ets:26 | 5 变体 chip(`chip`/`chipActive`/`form`/`formSelected`/`tag`) | inventory 列为局部组件,本任务范围内未在 NoteDetail* 调用(实际 consumer 在 ConceptDetailView 等子目录,本任务未读) |
| `ConfDot` | ConfDot.ets:18 | 置信度圆点(MINT/AMBER/DANGER 阈值) | 同上,本任务范围未直读 |
| `NoteActionBar` | NoteActionBar.ets:9 | 底部 Row 编辑/分享栏 | NoteDetailOverlay.ets:198 |
| `NoteEditForm` | NoteEditForm.ets:21 | 4 受控输入(标题/摘要/正文/标签)+ FieldLabel @Builder | NoteDetailOverlay.ets:122 |
| `NoteDetailMeta` | NoteDetailMeta.ets:29 | 元信息区器官(类型 chip + 学科 chip + 标题 + 副标题 + 3 列 MetricCell) | NoteDetailOverlay.ets:153 |
| `NoteDetailBody` | NoteDetailBody.ets:34 | 策略分派器(5 NoteType → 6 DetailView) | NoteDetailOverlay.ets:154 |

**B. 跨 overlay 复用(来自 `entry/src/main/ets/shared/`)**

| 组件 | 路径 | 复用点 |
|---|---|---|
| `AppIcon` (Atom) | shared/atoms/AppIcon.ets | NoteCloseButton.ets:20 / NoteIconButton.ets:6 — 组合 lucide 图标 |
| `MathTextRenderer` (Atom,实际 Molecule 体量) | shared/atoms/MathTextRenderer.ets | NoteDetailMeta.ets:23 / 81 — 副标题公式预览(profile=`preview`) |

**C. 通用 ArkUI 容器 / 系统控件**

| 类型 | 用法 | 出现处 |
|---|---|---|
| `Stack` | 全屏遮罩容器 | NoteDetailOverlay.ets:82; NoteCloseButton.ets:28; NoteIconButton.ets:19 |
| `Column` / `Row` | 容器 | 顶层 9 件全部使用 |
| `Scroll` | 详情区滚动 | NoteDetailOverlay.ets:119 |
| `Blank` | 弹性间隔 | NoteDetailOverlay.ets:168 / 175 / 219 / 235 / 245 / 276 / 297; NoteDetailMeta.ets:58 / 108 / 110; NoteActionBar.ets:15 / 17 |
| `Text` | 文本 | 全 |
| `TextInput` (受控) | 标题输入 | NoteEditForm.ets:34 |
| `TextArea` (受控) | 摘要/正文/标签 | NoteEditForm.ets:46 / 58 / 70 |
| `Circle` | ConfDot | ConfDot.ets:22 |
| `ForEach` | AI 草稿 diff 列表 | NoteDetailOverlay.ets:140 |
| `Border` / `borderRadius` / `border` | 边框样式 | 全 |
| `linearGradient` (angle 145) | 元信息区主题色→透明 | NoteDetailMeta.ets:119-126 |
| `.linearGradient` (angle 0/180°) | `backdropBlur`/渐变 | TabBar 用 — 本 overlay 未直接用 backdropBlur |
| `EdgeEffect.Spring` | Scroll 越界回弹 | NoteDetailOverlay.ets:164 |
| `promptAction.showToast` | 校验 / 错误提示 | NoteDetailOverlay.ets:353 / 421 / 425 / 445 / 460 / 464 / 654 |

**未发现**: 通用 ArkUI `Button`/`List`/`Grid`/`Stepper` 等 — 本 overlay 自定义程度极高,容器仅 `Stack` + `Column`/`Row` + `Scroll`。

#### 三、动效使用清单

> **核心结论**: NoteDetailOverlay 静态浮层,无主动效。

| API | 数量 | 文件:行 |
|---|---|---|
| `animateTo(...)` | **0** | 全目录未出现 |
| `.animation(...)` | **0** | 全目录未出现 |
| `.transition(...)` | **0** | 全目录未出现 |
| `transitionId` | **0** | 未出现 |
| `@AnimatableExtend` | **0** | 未出现 |
| `DUR_INSTANT/FAST/BASE/SLOW/SLOWER/SLOWEST/BREATH` | **0** 引用 | 整个 overlay 完全未消费动效时长令牌 |
| `Curve.*` (FastOutSlowIn/EaseInOut 等) | **0** 引用 | 同上 |
| `setTimeout` (延迟,非动效) | renderers 5 件 × 1 处(DetailRenderQueue 16ms 节拍) | renderers/5 件 + components/DetailRenderQueue.ets:62 |
| `setInterval` | 0 | — |
| 系统默认 `EdgeEffect.Spring` (越界回弹) | 1 | NoteDetailOverlay.ets:164 |

**组件动效统计**(来自 `docs/research/frontend-ui-design-inventory-2026-09-06.md:557-689`):22 件中 17 件标 "无动效(静态)";5 件(renderers/6 件 DetailView)`setTimeout×1(延迟)`,且为分帧渲染队列,非视觉动效。`NoteEditForm`/`NoteActionBar`/`ChipTag`/`ConfDot`/`NoteCloseButton`/`NoteIconButton`/`NoteDetailBody` 全部静态。

**唯一的设计意图的"过渡"**: DiscardConfirm 内 `cancelEdit`/`saveEdit` 用 `@State showDiscardConfirm` 切换可见性,但**未配 animateTo** — 是隐式直接 mount/unmount。

#### 四、与 UI 设计档案对齐结论(≤200 字)

✅ **高度对齐**:
- 令牌: 100% 走 `common/ColorTokens.ets` 常量,无 `$r` 资源型 token 绕过(符合 audit §7 "依赖方向合规")
- 容器: 全用 `Stack/Column/Row/Scroll/Blank/ForEach/Text/TextInput/TextArea`,无冗余组件
- 渐变/玻璃: `NoteDetailMeta` 用 `linearGradient(angle:145, typeColor→BG_CARD→#00000000)` 是 audit §3 "渐变类型图标母题" 的延伸;`OVERLAY_MASK_SOLID` 80% 黑遮罩与 inventory §1 表注一致
- 文档: `frontend-flow-walkthrough-2026-09-06.md §路径4` 完整描述了入口/容器/分派器/服务接线;`frontend-component-audit-2026-09-06.md §6` 把 22 文件树结构画清;`frontend-ui-design-inventory-2026-09-06.md §4-7` 给每件档案的 token/layout/animation 字段

⚠ **三处偏离 / 设计债**:
1. **6 处玻璃字面量**(`#12FFFFFF`/`#10FFFFFF`/`#0AFFFFFF`/`#08FFFFFF`/`#0DFFFFFF`/`#00000000`)应改 `GLASS_8/14`,1 处 `#FF64B7C8` 重复 TYPE_COLORS["计算题"] 应改 `typeColor('计算题')`
2. **零动效** 与 inventory §2 "动效是设计系统最薄的一环" TL;DR 完全一致; 但 **浮层入场/退场/DiscardConfirm 显隐都缺微交互**, 与同档案 "旗舰首推 MotionPolicy + DUR_INSTANT 按压反馈" 提案契合,属于明确未做项
3. **P4.3 设计债** (inventory `frontend-flow-walkthrough:128`): `OVERLAY_MASK_SOLID` 80% 与 `AgentFloatWindow` 的 `OVERLAY_MASK` 50% 在叠加切换时会产生遮罩色差,笔记编辑/AI 浮窗串场时视觉跳跃

📄 **无 NoteDetailOverlay 专属 HTML 设计稿**:`docs/legacy/mindtrace/plans/w3/notes-page-structure-proposal-2026-07-19.html` 是 **Notes 列表页**视觉稿,只提"不建议现在改详情页";`docs/legacy/mindtrace/plans/w3/notes-editor-markdown-2026-07-20.md` 是设计后回顾文档,非视觉稿 — **本 overlay 没有 HTML 渲染稿可对照**。

---

## 附录 C:Cross-check 源修正表(v1.1 增补)

> 本附录源于并行子代理 `note-detail-overlay-state-2026-09-17.md` 在独立实测中发现的口径差异。已 cross-check primary source,以实测口径为准。

| # | 项 | 历史口径(brief / 旧 audit) | 实测口径 | 修正后 |
|---|---|---|---|---|
| 1 | 目录 .ets 文件总数 | 23(本报告 v1.0 误用);22(`frontend-component-audit-2026-09-06.md:114`) | 22(glob 一致 + 实测:9 顶层 + 5 components + 6 renderers + 2 model) | **22** |
| 2 | `NoteDetailOverlay.ets` 行数 | 556 / 562 / 657(审计不同时点) | **660**(实测 `wc -l` / `read`) | **660** |
| 3 | `NoteDetailMeta.ets` 行数 | 294(设计档案 + deep-dive) | **290**(实测) | **290** |
| 4 | `DetailRenderModel.ets` 行数 | 491(设计档案 + deep-dive) | **497**(实测,`read` 末尾 `(End of file - total 497 lines)`) | **497** |
| 5 | `ConfDot.ets` 使用情况 | `frontend-ui-design-inventory-2026-09-06.md:565-569` 列入并描述"DOT_SIZE 置信度圆点" | 22 文件内**0 处** import / 实例化 / 模板引用;`NoteDetailMeta` 自实现 `MetricCell`(290 行) 替代;`dead-code-archive-2026-07-19.md:33` 已标 unused | **unused** |

**v1.1 修复位置**:
- L4 / L12 / L16:23 → 22
- L43:`(491)` → `(497)`
- L47 注:扩展说明 `ConfDot` 实际 0 处使用
- L437 子代理 E 汇总:23 → 22

**未修正的项**:
- `NoteDetailOverlay.ets` 行数审计 556/562/657/660 差异:可能因提交时点不同,本报告统一以**最新 660** 为准(与 `git log` HEAD 对齐)
- 6 处挂载点:本报告与子代理 17 号完全一致

---

## Last updated

2026-09-23 v1.1(在 Lead 主报告 + 附录 B 五子代理详细报告基础上,合并子代理 17 号 cross-check 修正;附录 C 记录 5 项数字 / 使用情况修正;主报告 §2 / §12 已同步更新)
