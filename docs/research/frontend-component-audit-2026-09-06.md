# 前端 UI 组件设计审查 — 2026-09-06

> **Date:** 2026-09-06
> **Scope:** MindTrace 前端组件的三层设计 (Atom/Molecule/Organism) 与页面级组装关系 — 只查组件设计与组合, 不涉及服务交互逻辑
> **Project:** MindTrace (`entry` module)
> **Author:** 主线程审查 agent (research skill; 后台代理因并发限制不可用, 由主会话完成)

---

**TL;DR:** `shared/` 三层库只有 7 个组件 (4 原子 + 2 分子 + 1 器官), 但通过 3 个渲染类组件 (MathTextRenderer / MarkdownRenderer / FormulaSplitRenderer) 间接铺满全 App 的公式/Markdown 呈现; 真正的 UI 体量藏在三大浮层的 **43 个本地组件**里, 它们按 spec 012 组合规则消费 shared 组件、方向全部自上而下合规。两处硬违例: **MathTextRenderer 名为原子实为最重组件** (536 行 Webview+缓存+调度, 且 import 内部模块 `utils/UiCacheDebug`), **MathPreviewText 原子组合原子** (atom→atom)。

## Question

本项目前端 UI 的原子组件有哪些? 每个分子组件由哪些原子 (与其他部件) 组成? 这些分子/原子又是如何组装成完整 UI 界面的? (只查组件设计, 不探讨服务交互)

## Method

- 读 `docs/specs/012-frontend-component-model.md` 拿权威层定义与依赖方向规则 (§Layering rules / §Naming rules)。
- 通读 `entry/src/main/ets/shared/` 全部 7 个组件源码 (约 1655 行)。
- grep 全 `entry/src/main/ets/` 的 import 语句, 建立"shared 组件 → 使用方"映射。
- 对 5 Tab 页面容器、`pages/` 子组件、三大浮层容器及其本地组件逐一读 import 与 build 结构, 归类组合关系。
- 文件清单以 `find entry/src/main/ets/{shared,pages,overlays}` 为准。

## Findings

### 1. 权威分层规则 (spec 012)

| 层 | 目录 | 依赖规则 | Source |
|---|---|---|---|
| Atom | `shared/atoms/` | **0 依赖内部模块** | `docs/specs/012-frontend-component-model.md:40` |
| Molecule | `shared/molecules/` | Atom | 同上 `:41` |
| Organism | `shared/organisms/` 或 `<page>/components/` | Atom + Molecule + Service 接口 | 同上 `:42` |
| Template | `<page>/templates/` 或页面根 | Organism + Atom + Molecule | 同上 `:43` |
| Page | `<page>/` | Template + ViewModel | 同上 `:44` |

依赖方向只能自上而下: Page → Template → Organism → Molecule → Atom (`:46`)。文件头注释要求含: 组件名 / 所属层 / 依赖列表 / 状态字段 (`:53`)。

### 2. 原子组件清单 (shared/atoms/, 4 个)

| 原子 | 行数 | 对外接口 (props) | 职责 | 复用 (import 方) |
|---|---|---|---|---|
| **AppIcon** | 132 | `name` (16 种图标名), `iconSize`, `color`, `strokeWidth` | 图标统一入口: SVG 资源 / 字形字符 / 手绘形状 (trash/search 用 Stack+Row/Circle 拼画) 三类实现 | **17 个文件** — 全 App 复用最广的组件 |
| **MathTextRenderer** | **536** | `text`(@Watch), `textColor/formulaColor/formulaBackground/formulaBorder`, `fontSize/lineHeight`, `formulaFontSize/formulaLineHeight`, `profile`(chat/chatUser/note/preview), `forceDisplay`, `minHeight` | KaTeX Webview 渲染包装: 三模式管线 (native/katex/plainFallback) + 模块级 LRU 缓存 (64 条/TTL 10min/600k 字符) + 高度估算 + note profile 延迟分槽渲染 | 3 个 (MathPreviewText, FormulaSplitRenderer, MarkdownRenderer), 但经它们**间接铺满全 UI** |
| **MathPreviewText** | 53 | `text`, `textColor`, `fontSize`, `lineHeightValue`, `maxLines`, `minHeight`, `maxChars` | 列表预览: 含公式语法走 MathTextRenderer(preview profile), 否则纯 Text 截断 | 2 个 (NoteCard, SubjectCard) |
| **StatsBox** | 32 | `value`, `label` | 玻璃质感统计方块 | 1 个 (ProfileStatsRow) |

Source: `entry/src/main/ets/shared/atoms/AppIcon.ets:11-15`, `MathTextRenderer.ets:183-204`, `MathPreviewText.ets:9-16`, `StatsBox.ets:9-11`; 复用数据来自全仓 grep。

### 3. 分子组件组成 (shared/molecules/, 2 个)

**FormulaSplitRenderer** (276 行) — 由以下组成:
- **MathTextRenderer ×N** (原子, 经 `LazyForEach` + 自建 `FormulaBlockDataSource` 按需创建/销毁, 仅可见块持有 WebView) — `FormulaSplitRenderer.ets:235-272`
- 模块级纯函数 `splitByFormulas` (按 `$$` 拆块、合并相邻文本段省 ~40% WebView、硬上限 30 块) — `:53-97`
- `splitLongTextBlocks` (超 1500 字符文本块按段落二次拆) — `:103-144`
- `ContentProtocol` (common) 做 split 前归一化 — `:209-215`
- 接口: `text`(@Watch), `profile`(chat/chatUser); profile 决定配色三件套 — `:188-231`
- 数据流 (文件头自述): `ChatBubble.text → splitByFormulas() → FormulaBlock[] → DataSource → LazyForEach → MathTextRenderer` — `:11-13`

**MarkdownRenderer** (417 行) — 由以下组成:
- **MathTextRenderer** (原子) — 段落含公式时整体接管 (`Paragraph` builder `:116-128`), display 公式块 `forceDisplay:true` (`FormulaBlock` builder `:231-243`)
- **AppIcon** (原子) — "继续阅读"展开条的 chevron-down 图标 (`:275`)
- **entry utils 三件**: `MarkdownParser` / `MarkdownInlineParser` / `MarkdownParseCache` (块解析/行内 Span 解析/解析缓存) — `:19-21`
- 7 类 `@Builder` 块: Heading / ListBlock / QuoteBlock / CodeBlock / FormulaBlock / RuleBlock / Paragraph — `:103-253`
- 渐进渲染状态机: 前 3 块先出 (16ms 延迟解析), "继续阅读"一次展开全部; `profile`(note/chat) 驱动全套字号行高 — `:25-29, :326-392`
- **注意: 分子内部不再分子化** — 两个分子互不引用, 各自独立组合原子。

### 4. 器官组件 (shared/organisms/, 1 个)

**NoteCard** (87 行) — 组成:
- **MathPreviewText** (原子) 做一行协议安全正文预览 — `NoteCard.ets:68-76`
- `common` 的类型色系统 (typeColor/typeChar/typeGlassColor/glassHighlightColor/...) 自绘 36×36 渐变类型图标 (未复用 AppIcon, 因类型图标需要渐变底+动态色) — `:27-44`
- 接口: `note: NoteItem`, `isLast`, `onTap?` 回调上抛 — `:20-22`
- 使用方: `HomeRecentNotes` / `NotesList` / `SubjectNoteList` 三个页面局部器官 (grep 确认, 无其他)

### 5. 页面级组装 (谁用 shared, 谁用本地)

**Tab 容器** `pages/Index.ets`: HomePage / NotesPage / ReviewPage / ProfilePage + `MainTabs/TabBar`(TabButton+AiTabButton 本地组装) + 两大浮层 (AgentFloatWindow / CameraOverlay) — `pages/Index.ets:3-10`。中间 Tab(2) 不进页面, 触发浮窗开关 (`Index.ets:66-75`, 本报告只记组件事实)。

| 页面 | 本地组件树 (页面局部组件 → 消费的 shared 组件) |
|---|---|
| **Home** | HomePage ← HomeTopBar / HeroBanner(←GradientRing) / HomeCollapsedReview* / ReminderBanner* / HomeRecentNotes ← **NoteCard**(器官) ; FloatingButton (* = 用 AppIcon) |
| **Notes** | NotesPage ← NotesHeader* / NotesEmptyState / NotesSummaryPanel / SubjectGrid ← SubjectCard(←**MathPreviewText**) / SubjectViewToggle ; 二级页 SubjectDetailPage ← SubjectHeader* / SubjectNoteList ← **NoteCard** |
| **Review** | ReviewPage ← ReviewTabSwitch / ReviewPlanView ← ReviewPlanRow* / **ReviewGraphView***(←AppIcon, 星系渲染全自绘) ; ReviewPage 直连 **AppIcon** 原子 (Tab 内图标) |
| **Profile** | ProfilePage ← ProfileHeader / ProfileStatsRow ← **StatsBox** / ProfileMenuList ← ProfileMenuItemRow* / ProfileLoginPanel* |
| **AiSettings** | AiSettingsPage ← PageHeader / ConnectionStatus / ActionBar / EndpointPicker / ModelPicker / KeyInput / OcrConfigSection — **全本地, 零 shared 组件** (grep 确认) |

Source: 各页面文件 import 块 (`pages/Home/HomePage.ets:5-14` 等)。

### 6. 三大浮层的组件树 (UI 体量主体, 共 43 个 .ets)

**AgentFloatWindow** (11 文件) — 对话浮窗:
```
AgentFloatWindow (容器, 拖拽/缩放/多会话编排)
├─ ChatHeader, SessionBar, QuickSuggestions, ImagePreviewBar, AgentInputBar  (本地控制件)
└─ AgentMessageList
   ├─ EmptyStateHint
   └─ ChatBubble (气泡)
      ├─ FormulaSplitRenderer  (分子) — 含公式消息
      └─ MarkdownRenderer      (分子) — 纯文本/富文本消息
```
Source: `overlays/AgentFloatWindow/AgentFloatWindow.ets:4-12`, `AgentMessageList.ets`, `ChatBubble.ets` import 块。本地 7 件 (ChatHeader/SessionBar/QuickSuggestions/ImagePreviewBar/AgentInputBar/EmptyStateHint/ChatBubble) 按 spec 012 尺度可归**原子~器官**之间: 单一控件 (原子级) 但各自持样式系统与文案, spec 未对 overlay 本地组件的层级归属给规则 (见 Finding 8)。

**CameraOverlay** (10 文件) — 相机浮层:
```
CameraOverlay (容器: cameraPicker/MediaLibrary 编排)
├─ CameraPreview (取景器) + CameraCapture (拍照实现)
├─ ViewfinderCorners (四角框)
└─ 按钮五件: CameraShutterBtn / CameraAlbumBtn* / CameraBackBtn* / CameraCloseBtn* / CameraConfirmBtn
   (* = 内部组合 AppIcon 原子; ConfirmBtn 为自绘双环)
```
Source: `overlays/CameraOverlay/CameraOverlay.ets:8-9` + 各按钮文件 import。**CameraCloseBtn/CameraAlbumBtn 组合 AppIcon — 又是"原子包原子"**, 但发生在 overlay 本地层。

**NoteDetailOverlay** (22 文件) — 笔记详情浮层, 结构最深的组合树:
```
NoteDetailOverlay (容器)
├─ NoteCloseButton*, NoteIconButton*   (壳件, 组合 AppIcon)
├─ NoteDetailMeta (元信息) / NoteActionBar / NoteEditForm / ChipTag / ConfDot
└─ NoteDetailBody (按 NoteType 分派)
   ├─ renderers/ 六件: Concept / Theorem / Formula / Proof / Computation / Fallback DetailView
   │   ├─ MarkdownRenderer (分子) — 正文/定义/证明文本
   │   └─ DetailMetaFooter*, DetailSection(←MarkdownRenderer), DetailStepList(←MarkdownRenderer+AppIcon),
   │      DetailStepsSection, DetailRenderQueue (components/ 五件)
   └─ model/ 两件: DetailRenderCache, DetailRenderModel (渲染缓存, 非视觉组件)
```
Source: `NoteDetailOverlay/NoteDetailBody.ets` import 块 + `ConceptDetailView.ets` / `DetailSection.ets` / `DetailStepList.ets` import 块。renderers/ 是**策略型器官** (按 5 种 NoteType 各自组装分子), components/ 五件按 spec 012 `:42` 的 `<page>/components/` 规则属**器官层**。

### 7. 组合全景表 (核心交付)

| 组件 | 层级 (spec 012 判定) | 由什么组成 | 被谁使用 |
|---|---|---|---|
| AppIcon | 原子 ✓ | 纯自绘/资源, 零内部依赖 (仅 common token) | 17 文件: MarkdownRenderer + 相机 2 钮 + 详情浮层 3 件 + 12 页面子件 |
| MathTextRenderer | **名原子, 实为最重组件** ⚠ | Web(KaTeX) + Text 双分支; 模块级缓存/哈希/调度器; import `utils/UiCacheDebug` | MathPreviewText, FormulaSplitRenderer, MarkdownRenderer (3 直连, 间接全 UI) |
| MathPreviewText | **原子组合原子** ⚠ | MathTextRenderer + ContentProtocol/ContentExcerptBuilder (common) | NoteCard, SubjectCard |
| StatsBox | 原子 ✓ | 纯 token | ProfileStatsRow (1 处) |
| FormulaSplitRenderer | 分子 ✓ | MathTextRenderer ×N (LazyForEach) + 拆块纯函数 ×2 | ChatBubble (1 处) |
| MarkdownRenderer | 分子 ✓ | MathTextRenderer + AppIcon + utils 解析三件 + 7 @Builder | ChatBubble + NoteDetailOverlay 10 件 (共 11 处) |
| NoteCard | 器官 ✓ | MathPreviewText + 类型色渐变自绘图标 | HomeRecentNotes / NotesList / SubjectNoteList |
| ChatBubble | 浮层本地 (分子级组合) | FormulaSplitRenderer + MarkdownRenderer 二选一 | AgentMessageList |
| renderers/ 六件 DetailView | 器官 (策略分派) | MarkdownRenderer + components/ 五件 | NoteDetailBody 按 NoteType 分派 |
| 相机按钮五件 / 详情壳件 | 浮层本地 (原子级) | AppIcon 或自绘 | 各浮层容器 |

### 8. 组件设计评估

1. **MathTextRenderer 是全库最大的分层失真** (536 行): 名为 Atom, 实际持有 Webview 控制器、模块级 LRU 缓存 (`MathTextRenderer.ets:44-58`)、三模式渲染管线 (`:426-449`)、分槽延迟调度 (`:469-480`)、高度估算器 (`:482-503`) — 这是"分子/器官级"复杂度; 且 `:13` import `../../utils/UiCacheDebug` 直接违反 Atom "0 依赖内部模块" 规则 (spec 012 `:40`)。建议: 升格为 Molecule 或独立"渲染组件层", 缓存/调度外移到 utils。
2. **MathPreviewText atom→atom 违例**: `MathPreviewText.ets:31` 组合 MathTextRenderer — 按 spec 012 这是 Molecule 行为, 应移入 `shared/molecules/`。
3. **浮层本地"原子包原子"**: CameraCloseBtn/CameraAlbumBtn/NoteIconButton/NoteCloseButton/DetailStepList 组合 AppIcon — 方向合法 (向下), 但暴露 spec 012 **没有对 `overlays/*/` 本地组件的层级归属与目录规则** (spec 只定义了 `<page>/components/`); 43 个浮层组件处于规范真空。
4. **复用分布不均**: AppIcon 17 处、MarkdownRenderer 11 处 → shared 化收益明显; StatsBox 仅 1 处、FormulaSplitRenderer 仅 1 处 → 是否值得进 shared 存疑 (Rule: 至少 2 消费者再上收, 单消费者的留在页面侧)。
5. **AiSettings 页零 shared 组件** (9 个子件全本地): 是"下一个 shared 化候选"还是刻意独立, 待裁决。
6. **文件头注释四要素** (组件名/所属层/依赖列表/状态字段, spec 012 `:53`) 仅 FormulaSplitRenderer 的头注释部分达标 (有职责/依赖/数据流, 无所属层/状态字段), 其余 6 个 shared 组件只有一句话头 — naming 规则未执行。
7. **依赖方向总体合规**: 全仓 grep 未发现任何 shared→pages/overlays 反向 import, 未发现 molecule 引用 organism; Page 直连 service 的问题存在 (AgentFloatWindow→AgentChatService 等) 但属 spec 012 已知未完成项, 且不在本次"组件设计"范围深究。
8. **两个分子互不引用、各自独立组合原子** — 目前无分子复用分子的场景; 若未来 ChatBubble 与 DetailView 需要"同构气泡框架", 会出现第一个 molecule→molecule 组合, 届时需在 spec 012 补充该方向是否允许。

## Conclusion

MindTrace 前端的 shared 三层库收敛在 7 个组件, 全部围绕一条主线: **公式/Markdown 的协议安全呈现** (MathTextRenderer 为核心, 向上被 MathPreviewText → NoteCard 和两个分子消费, 再铺向 5 Tab 与三大浮层)。组装方向全链合规; 真正的设计债集中在两处——MathTextRenderer 的"假原子"身份 (含内部模块依赖) 与 43 个浮层本地组件的层级规范真空, 两者都是 spec 012 后续 PR 的直接素材。

## Implications

- spec 012 的下一批 PR 候选 (按收益排序): ① MathTextRenderer 重分层 + 缓存外移; ② MathPreviewText 移入 molecules/; ③ 给 overlays 本地组件补层级/目录规则 (spec 012 §Layering rules 增行); ④ shared 组件文件头补齐四要素注释。
- "复用 ≥2 才进 shared" 可作为新候选组件的收编门槛, StatsBox/FormulaSplitRenderer 是现行反例 (单消费者)。
- 若做 ①/②, `entry/src/test/MarkdownRendererProtocol.test.ets` 是现成的行为锚点。

## Open questions

- MathTextRenderer 若升为 Molecule, `profile` 四态 (chat/chatUser/note/preview) 是否应拆成独立样式策略组件?
- overlays 本地组件是否应统一迁入 `shared/` (spec 012 §Migration plan 的"overlay 迁移待做"具体指什么范围, 待与作者确认)?
- AiSettings 的 9 个本地子件是否有跨页复用计划 (决定是否上收)?

---

## Primary source citations

- `docs/specs/012-frontend-component-model.md:36-54` — 分层规则/依赖方向/命名与文件头要求
- `entry/src/main/ets/shared/atoms/AppIcon.ets:11-15,37-131` — 接口与三类图标实现
- `entry/src/main/ets/shared/atoms/MathTextRenderer.ets:44-58,183-204,426-503` — 缓存/接口/管线/估算
- `entry/src/main/ets/shared/atoms/MathPreviewText.ets:9-16,28-51` — 接口与 atom→atom 组合点
- `entry/src/main/ets/shared/atoms/StatsBox.ets:9-31` — 接口与实现
- `entry/src/main/ets/shared/molecules/FormulaSplitRenderer.ets:26-28,53-144,186-276` — 依赖/拆块算法/组合
- `entry/src/main/ets/shared/molecules/MarkdownRenderer.ets:19-29,55-88,103-253,326-392` — 依赖/渐进渲染/builder 套件
- `entry/src/main/ets/shared/organisms/NoteCard.ets:9-22,27-76` — 依赖与组成
- `entry/src/main/ets/pages/Index.ets:3-10,66-75` — Tab 容器与浮层挂载
- `entry/src/main/ets/pages/{Home,Notes,Review,Profile,AiSettings}/*.ets` import 块 — 页面组件树
- `entry/src/main/ets/overlays/{AgentFloatWindow,CameraOverlay,NoteDetailOverlay}/**` import 块 — 浮层组件树
- 全仓 grep (`import ... from .../shared/...`) — 复用计数 (AppIcon 17 / MarkdownRenderer 11 / MathTextRenderer 3 / MathPreviewText 2 / StatsBox 1 / FormulaSplitRenderer 1 / NoteCard 3)

## Last updated

2026-09-06
