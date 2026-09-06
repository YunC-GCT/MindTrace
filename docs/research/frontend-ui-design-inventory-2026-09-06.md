# 前端 UI 设计/布局/动效三维档案 — 2026-09-06

> **Date:** 2026-09-06
> **Scope:** MindTrace entry 前端全部 96 个 .ets 的设计(视觉语言)、布局(结构模式)、动效(运动系统)三维清点 — 事实字段机器提取, 关键动效件实读
> **Project:** MindTrace (entry module)
> **Author:** 主线程审查 agent (research skill 调度)

---

**TL;DR:** 设计令牌系统在 `common/ColorTokens.ets`(233 行)里定义完整 — 11 色板/玻璃阶梯/6 级间距/8 级字号/7 档动画时长/3 个阴影预设, 静态消费健康(间距/字号/主色为最热令牌)。**动效是设计系统最薄的一环**: 声明式属性动画 `.animation()/.transition()` 全前端 **0 次**, 运动通道是 `animateTo`(5 文件) — 其中 AgentFloatWindow/HomePage/HexLogo 全部走 DUR_*/Curve 令牌(合规范本), **ReviewGraphView 3 处硬编码 180-240ms 绕过令牌**; 旗舰 Canvas 动效 GradientRing 用 setInterval 30ms 手摇帧+时长硬编码 800/1400ms, 呼吸周期≈1.5s 与令牌 DUR_BREATH=3000 相差一倍; 96 组件中仅 5 个有真实运动, 其余全静态, 两颗最显眼的渐变圆钮无按压反馈。

## Question

每个前端组件(按钮到页面)的设计语言、布局结构、动效行为是什么? 令牌系统的实际使用状况如何?

## Method

解析器对 96 个 .ets 逐一机器提取: 令牌引用(TOKEN_RE 全集)/布局容器计数/动效 API 计数/硬编码时长/曲线; GradientRing、FloatingButton、AiTabButton、TabBar 等动效核心件逐行实读; 设计令牌真源 ColorTokens.ets 全读。每条档案的事实字段均为提取结果(●), 备注列才含分析。

## 1. 全局设计语言 (令牌地图, 真源 ColorTokens.ets)

| 令牌族 | 内容 | 证据 |
|---|---|---|
| 主色板 11 | MINT #5BE3B0 系(DARK/LIGHT/GLOW/BORDER) + PURPLE 系 + PINK/AMBER + BG_DARK | ColorTokens.ets:14-25 |
| 语义色 | DANGER 软红/DANGER_BRIGHT 高亮红/WARNING 琥珀/SUCCESS=MINT | :35-38 |
| 玻璃阶梯 | GLASS_8(8%)/GLASS_10(10%,=BORDER 别名)/GLASS_14 | :43-46 |
| 遮罩 | OVERLAY_MASK 50% 黑(浮窗)/OVERLAY_MASK_SOLID 80%(详情) | :51-52 |
| 学科/类型色 | SUBJECT_COLORS(3 学科)/TYPE_COLORS(5 类型→MINT/PURPLE/PINK/AMBER/青) | :57-75 |
| 文字 4 级 | TEXT 白 → TEXT_2 → TEXT_3 → TEXT_4 暗阶 | :80-83 |
| 间距 6 级 | S_1=4 → S_6=24 vp | :93-98 |
| 圆角 6 级 | R_SM=6 → R_2XL=24 + R_FULL | :103-108 |
| 字号 8 级 | F_XS=11 → F_3XL=30 fp | :113-120 |
| 字重/行高 | W 4 级(400-700) / LH 5 级(16-30) | :125-137 |
| 阴影 3 预设 | SHADOW_FAB(radius28)/SHADOW_GLOW_MINT(α参数化)/SHADOW_AI_BTN | :149-163, :228-233 |
| **动效 7 档** | DUR_INSTANT=80/FAST=150/BASE=250/SLOW=400/SLOWER=600/SLOWEST=1200/BREATH=3000(光晕呼吸) + Curve 对照表 | :168-184 |
| 组件尺寸 | FAB 54/HERO_RING 120/NOTE_ICON 36/TAB_BAR 74/CAM_SHUTTER 68·54 等 | :190-233 |

### 令牌使用热度 (96 文件全量统计, Top 组)

| 热度 | 令牌 (出现次数) |
|---|---|
| 高频 | `S_2`×231 · `S_4`×184 · `S_3`×162 · `MINT`×150 · `TEXT_3`×148 · `F_SM`×142 · `F_XS`×136 · `TEXT`×127 · `BORDER`×117 · `W_SEMIBOLD`×115 · `S_1`×101 · `TEXT_2`×96 |
| 中频 | `W_BOLD`×76 · `BG_DARK`×66 · `TEXT_4`×57 · `R_MD`×56 · `BG_CARD`×49 · `S_5`×44 · `S_6`×41 · `F_MD`×41 · `F_BASE`×40 · `R_FULL`×40 · `R_LG`×40 · `SCREEN_W`×38 |
| 低频/濒危 | CAM_MASK · CAM_OVERLAY_BG · CAM_PREVIEW_BG · DUR_BASE · DUR_BREATH · GLASS_14 · LH_BASE · MINT_BORDER · OVERLAY_MASK · PINK_LIGHT · R_SM · SCREEN_H · TAB_BAR_HEIGHT · TAB_BTN_RADIUS |

entry 内零直接引用的令牌: `SUBJECT_COLORS`, `TYPE_COLORS`, `LH_HEADING`, `SUCCESS`, `WARNING`, `LH_TIGHT`, `LH_LOOSE`。其中 `SUBJECT_COLORS`/`TYPE_COLORS` **并非死令牌** — 经 `common/NoteTaxonomy.ets:58,109` 包装为 typeColor()/subjectColor() 间接消费; `LH_HEADING`/`SUCCESS`/`WARNING` 则连 common 侧也无真实消费者 (仅 Index.ets 转出口) — 真死令牌, 随 audit #1 裁决去留。

## 2. 动效全景 (motion)

- **属性动画缺席, animateTo 是唯一运动通道**: `.animation()` ×0 / `.transition()` ×0 (全 96 文件); `animateTo` ×15 处, 分布 5 文件。
- **令牌合规组 (3 文件)**: AgentFloatWindow(DUR_BASE/DUR_FAST)、HomePage(DUR_SLOW ×2)、HexLogo(DUR_SLOWEST ×2 + DUR_SLOWER) — 全部 `Curve.FastOutSlowIn`/`Curve.EaseInOut`, 与 ColorTokens:179-184 的缓动对照表一致。
- **令牌绕过组 (2 文件)**: ReviewGraphView `animateTo` ×8 **全部硬编码** — 180ms×6 / 220ms / 240ms (最接近的 DUR_INSTANT=80/DUR_FAST=150/DUR_BASE=250 均未取); GradientRing setInterval 手摇帧硬编码 800/1400ms (见下)。
- **手摇帧**: setInterval×4 / setTimeout×17; 有真实运动的文件 5/96。
- **toast 时长不算动效**: promptAction.showToast 的 duration (1000-1800ms, 多文件) 是 API 参数, 与 DUR_* 体系无关 — 不计入绕过清单。
- **曲线消费面**: 仅 FastOutSlowIn + EaseInOut 两条; 令牌表预留的 EASE_OUT/EASE_IN/EASE_IN_OUT/EASE_BOUNCE 对照(ColorTokens.ets:180-184)零消费者。
### 旗舰动效件剖析 (实读)

**GradientRing** (`pages/Home/GradientRing.ets` — 唯一的 Canvas 动效组件):
- 渐变弧: Canvas `createLinearGradient(0,0,120,120)` MINT→PURPLE, 圆弧 -π/2 起笔, lineCap round (:100-112)
- 填充动画: **setInterval 16ms 手摇帧**, ease-out cubic `1-(1-t)³`; 首次入场 1400ms (:36), pct 变化重放 800ms (:27) — 两条时长均硬编码, DUR_* 未用
- 呼吸光晕: setInterval 30ms, glow α 0.30↔0.80 步进 ±0.02 → 周期 ≈1500ms; **令牌 DUR_BREATH=3000 定义的呼吸周期与实现不一致** (ColorTokens.ets:174)
- 阴影即光晕: shadow radius 32 + 动态 rgba(91,227,176,glow) — 手工复算了 SHADOW_GLOW_MINT 预设的公式而非调用它 (:83-88 vs ColorTokens.ets:156-163)
- 生命周期纪律好: aboutToDisappear 清双 timer (:56-65)

**TabBar** (`pages/MainTabs/TabBar.ets`): backdropBlur(24) 真·毛玻璃 + 180° 透明→BG_DARK 渐变淡入 + 顶边框; ForEach 用 `tab.idx` 稳定 key — key 纪律范本 (:57-66)

**FloatingButton / AiTabButton**: 渐变+阴影预设全 token (SHADOW_FAB / SHADOW_AI_BTN), 纯静态无按压动效 — 两颗最该有微交互的按钮没有 DUR_INSTANT 反馈

## 3. 布局/视觉模式库 (重复出现的设计母题, 均 file:line 实证)

| 母题 | 定义 | 代表组件 |
|---|---|---|
| 玻璃卡片 | GLASS_8/10 底 + border 0.5 BORDER + radius 12 | StatsBox:29 / NoteCard:84 |
| 渐变类型图标 | linearGradient(angle 145, typeColor 系) + 玻璃高光 + 色阴影 | NoteCard:31-40 |
| 渐变圆钮 | linearGradient(135°/180°) + 阴影预设 | FloatingButton:27 / AiTabButton:25-28 |
| 毛玻璃底栏 | backdropBlur + 透明→BG_DARK 渐变 + 顶边框 | TabBar:62-67 |
| 列表行 | Row + 左图标 + Column(layoutWeight 1) + 底边框(末行去除) | NoteCard:25-84 |
| 分区标题+正文 | MarkdownRenderer @Builder 族 / SectionHeader | MarkdownRenderer:103-253 |
| 步骤列表 | 序号列 + 正文列(layoutWeight) | MarkdownRenderer ListBlock:152-177 / DetailStepList |
| 全屏遮罩浮层 | OVERLAY_MASK(_SOLID) + 容器 | AgentFloatWindow / NoteDetailOverlay |
| 相机双环快门 | CAM_SHUTTER_OUTER 68 / INNER 54 嵌套 | CameraShutterBtn (CAM_* 令牌) |
| 星系自绘 | Canvas-free: Stack+Circle+多边形+手势, 缩放 0.6~4.2 | ReviewGraphView (1880 行) |

## 4. 组件三维档案 (96 件全量, 按目录分组; 事实字段=机器提取)

### shared/atoms（原子 4）

#### `AppIcon` — shared/atoms/AppIcon.ets (132 行) · Atom
- **布局**: 容器 Column×2 Row×5 Stack×3; 对齐 API×5
- **设计**: token: 文字色×2 字号字重×2
- **动效**: 变换 t6/r1/s0 · onClick×0
- **备注**: 16 种图标三类实现(资源/字形/手绘); 零内部依赖范本

#### `MathPreviewText` — shared/atoms/MathPreviewText.ets (53 行) · Atom(违例:应升分子)
- **布局**: 百分比宽度
- **设计**: token: 文字色×2 字号字重×2
- **动效**: 无动效(静态) · onClick×0
- **备注**: 原子组合原子(:31); 候选C5

#### `MathTextRenderer` — shared/atoms/MathTextRenderer.ets (536 行) · Atom(违例:假原子)
- **布局**: 百分比宽度; Web 容器
- **设计**: token: 玻璃×2 文字色×4 字号字重×3; ⚠字面量×1
- **动效**: setTimeout×1(延迟) · onClick×0
- **备注**: Webview 渲染+LRU 缓存+分槽 defer; import 内部模块违 spec012:40; 候选C1

#### `StatsBox` — shared/atoms/StatsBox.ets (32 行) · Atom
- **布局**: 容器 Column×1; layoutWeight×1; padding×1; margin×1; 对齐 API×1
- **设计**: token: 玻璃×2 文字色×4 间距×5 字号字重×6
- **动效**: 无动效(静态) · onClick×0
- **备注**: 玻璃方块范本; 单消费者

### shared/molecules（分子 2）

#### `FormulaSplitRenderer` — shared/molecules/FormulaSplitRenderer.ets (276 行) · Molecule
- **布局**: 容器 Column×1; 百分比宽度; 列表 ForEach×0/LazyForEach×1
- **设计**: token: 文字色×6 字号字重×6; ⚠字面量×4
- **动效**: 无动效(静态) · onClick×0
- **备注**: LazyForEach 按需挂 WebView; 合并文本段省~40%

#### `MarkdownRenderer` — shared/molecules/MarkdownRenderer.ets (417 行) · Molecule
- **布局**: 容器 Column×6 Row×3; layoutWeight×2; padding×2; margin×9; 百分比宽度; 对齐 API×4; 列表 ForEach×3/LazyForEach×0
- **设计**: token: 主色×6 玻璃×2 文字色×14 间距×30 圆角×3 字号字重×25; ⚠字面量×4
- **动效**: setTimeout×1(延迟) · onClick×1
- **备注**: 7类@Builder+渐进渲染; index-key ×2(:139,172)

### shared/organisms（器官 1）

#### `NoteCard` — shared/organisms/NoteCard.ets (87 行) · Organism
- **布局**: 容器 Column×1 Row×2 Stack×2; layoutWeight×1; padding×1; margin×3; 百分比宽度; 对齐 API×2
- **设计**: token: 玻璃×2 文字色×7 间距×6 圆角×2 字号字重×15 组件尺寸×5; linearGradient×1; shadow×1
- **动效**: 无动效(静态) · onClick×1
- **备注**: 类型色渐变图标+MathPreviewText; 数据下行/事件上行范本

### pages/MainTabs（底栏 3）

#### `AiTabButton` — pages/MainTabs/AiTabButton.ets (35 行) · 页面局部组件(原子级)
- **布局**: 容器 Column×1 Stack×1; layoutWeight×1; 对齐 API×1
- **设计**: token: 主色×6 阴影预设×3 组件尺寸×7; linearGradient×1; shadow×1
- **动效**: 无动效(静态) · onClick×1
- **备注**: MINT→PURPLE 135°渐变+SHADOW_AI_BTN; 全 token 合规

#### `TabBar` — pages/MainTabs/TabBar.ets (71 行) · 页面局部组件(分子级)
- **布局**: 容器 Row×1; padding×1; 百分比宽度; 对齐 API×2; 列表 ForEach×1/LazyForEach×0
- **设计**: token: 主色×1 间距×5 组件尺寸×2; linearGradient×1; backdropBlur×1; ⚠字面量×1
- **动效**: 无动效(静态) · onClick×0
- **备注**: backdropBlur(24) 真毛玻璃+渐变淡入底; ForEach 稳定 key(idx) 范本

#### `TabButton` — pages/MainTabs/TabButton.ets (38 行) · 页面局部组件
- **布局**: 容器 Column×1; layoutWeight×1; padding×1; margin×1; 对齐 API×1
- **设计**: token: 主色×4 文字色×3 间距×5 字号字重×4 组件尺寸×5
- **动效**: 无动效(静态) · onClick×1
- **备注**: —

### pages/Home（首页 9）

#### `FloatingButton` — pages/Home/FloatingButton.ets (32 行) · 页面局部组件(原子级)
- **布局**: 容器 Stack×1; margin×1
- **设计**: token: 主色×6 间距×4 阴影预设×3 组件尺寸×4; linearGradient×1; shadow×1
- **动效**: 无动效(静态) · onClick×1
- **备注**: MINT→MINT_DARK 渐变+SHADOW_FAB 预设; 全 token 合规

#### `GradientRing` — pages/Home/GradientRing.ets (114 行) · 页面局部组件(动效核心)
- **布局**: 容器 Stack×1; Canvas 自绘
- **设计**: token: 主色×6; shadow×1; ⚠字面量×3
- **动效**: setInterval×3(手摇帧) · onClick×0
- **备注**: Canvas 渐变弧+setInterval 手摇帧; 时长硬编码 800/1400ms 绕过 DUR_*; 呼吸光晕周期≈1.5s vs 令牌 DUR_BREATH=3000 不一致

#### `HeroBanner` — pages/Home/HeroBanner.ets (136 行) · 页面局部组件
- **布局**: 容器 Column×2 Row×4 Stack×1; padding×2; margin×6; 百分比宽度; 对齐 API×5
- **设计**: token: 主色×13 玻璃×2 文字色×9 间距×17 圆角×5 字号字重×16 组件尺寸×6; linearGradient×2; shadow×1; ⚠字面量×2
- **动效**: 无动效(静态) · onClick×1
- **备注**: 首页主视觉; PINK_LIGHT 渐变收尾(Hero 梯度)

#### `HexLogo` — pages/Home/HexLogo.ets (79 行) · 页面局部组件
- **布局**: —
- **设计**: token: 主色×2; ⚠字面量×2
- **动效**: animateTo×3; DUR_*×9; setTimeout×3(延迟); 变换 t1/r1/s0; Curve: EaseInOut · onClick×0
- **备注**: —

#### `HomeCollapsedReview` — pages/Home/HomeCollapsedReview.ets (133 行) · 页面局部组件
- **布局**: 容器 Column×2 Row×7 Stack×3; layoutWeight×1; padding×1; margin×7; 百分比宽度; 对齐 API×2
- **设计**: token: 主色×7 玻璃×2 文字色×10 间距×14 圆角×5 字号字重×12
- **动效**: 变换 t0/r2/s0 · onClick×1
- **备注**: 复习概览+GradientRing 消费方

#### `HomePage` — pages/Home/HomePage.ets (216 行) · Page
- **布局**: 容器 Column×1 Stack×1; 百分比宽度
- **设计**: 纯几何/无样式调用
- **动效**: animateTo×2; DUR_*×3; Curve: FastOutSlowIn · onClick×0
- **备注**: 组装+回调转发; 挂 NoteDetailOverlay

#### `HomeRecentNotes` — pages/Home/HomeRecentNotes.ets (64 行) · 页面局部组件
- **布局**: 容器 Column×2 Row×1; layoutWeight×2; padding×2; 百分比宽度; 列表 ForEach×1/LazyForEach×0
- **设计**: token: 文字色×4 间距×11 字号字重×6
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `HomeTopBar` — pages/Home/HomeTopBar.ets (52 行) · 页面局部组件
- **布局**: 容器 Column×1 Row×2; padding×1; margin×1; 百分比宽度; 对齐 API×1
- **设计**: token: 文字色×3 间距×7 字号字重×6 组件尺寸×4
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `ReminderBanner` — pages/Home/ReminderBanner.ets (46 行) · 页面局部组件
- **布局**: 容器 Row×1; layoutWeight×1; padding×1; margin×2; 百分比宽度
- **设计**: token: 主色×8 间距×8 圆角×2 字号字重×2; linearGradient×1
- **动效**: 无动效(静态) · onClick×0
- **备注**: MINT 语义横幅

### pages/Notes（笔记 13）

#### `NotesEmptyState` — pages/Notes/NotesEmptyState.ets (42 行) · 页面局部组件
- **布局**: 容器 Column×1; layoutWeight×1; padding×1; margin×1; 百分比宽度; 对齐 API×2
- **设计**: token: 文字色×6 间距×5 字号字重×9
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `NotesHeader` — pages/Notes/NotesHeader.ets (72 行) · 页面局部组件
- **布局**: 容器 Column×1 Row×3; padding×1; margin×1; 百分比宽度; 对齐 API×3
- **设计**: token: 玻璃×2 文字色×7 间距×8 圆角×2 字号字重×9
- **动效**: 无动效(静态) · onClick×1
- **备注**: —

#### `NotesList` — pages/Notes/NotesList.ets (52 行) · 页面局部组件
- **布局**: 容器 Column×1 List×2; layoutWeight×1; 列表 ForEach×1/LazyForEach×0
- **设计**: 纯几何/无样式调用
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `NotesPage` — pages/Notes/NotesPage.ets (128 行) · Page
- **布局**: 容器 Column×2 Row×1; layoutWeight×1; padding×1; margin×1; 百分比宽度; 对齐 API×1
- **设计**: token: 文字色×2 间距×8 字号字重×4
- **动效**: 无动效(静态) · onClick×0
- **备注**: AppStorage notesVersion 手工失效

#### `NotesSummaryPanel` — pages/Notes/NotesSummaryPanel.ets (166 行) · 页面局部组件
- **布局**: 容器 Column×2 Row×5 Flex×1; layoutWeight×2; padding×1; margin×6; 百分比宽度; 对齐 API×5; 列表 ForEach×3/LazyForEach×0
- **设计**: token: 玻璃×2 文字色×7 间距×14 圆角×2 字号字重×10
- **动效**: 无动效(静态) · onClick×0
- **备注**: 学科汇总

#### `SubjectCard` — pages/Notes/SubjectCard.ets (193 行) · 页面局部组件
- **布局**: 容器 Column×2 Row×4 Stack×1; layoutWeight×2; padding×2; margin×6; 百分比宽度; 对齐 API×7
- **设计**: token: 玻璃×3 文字色×11 间距×18 圆角×4 字号字重×17; linearGradient×2
- **动效**: 无动效(静态) · onClick×2
- **备注**: MathPreviewText+学科色(SUBJECT_COLORS)

#### `SubjectDetailPage` — pages/Notes/SubjectDetailPage.ets (201 行) · Page
- **布局**: 容器 Column×2 Stack×1 Scroll×1; layoutWeight×1; padding×1; 百分比宽度; 对齐 API×2
- **设计**: 纯几何/无样式调用
- **动效**: 无动效(静态) · onClick×0
- **备注**: router 页

#### `SubjectGrid` — pages/Notes/SubjectGrid.ets (65 行) · 页面局部组件
- **布局**: 容器 Column×1 Grid×1 Scroll×1; layoutWeight×1; padding×1; 百分比宽度; 对齐 API×2; 列表 ForEach×1/LazyForEach×0
- **设计**: token: 间距×6
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `SubjectHeader` — pages/Notes/SubjectHeader.ets (51 行) · 页面局部组件
- **布局**: 容器 Column×1 Row×2; layoutWeight×1; padding×1; margin×1; 百分比宽度; 对齐 API×1
- **设计**: token: 主色×2 文字色×4 间距×8 字号字重×6
- **动效**: 变换 t0/r1/s0 · onClick×1
- **备注**: —

#### `SubjectNoteList` — pages/Notes/SubjectNoteList.ets (109 行) · 页面局部组件
- **布局**: 容器 Column×2 List×1; layoutWeight×1; padding×2; 百分比宽度; 列表 ForEach×0/LazyForEach×1
- **设计**: token: 间距×3 圆角×2
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `SubjectTypeEmpty` — pages/Notes/SubjectTypeEmpty.ets (35 行) · 页面局部组件
- **布局**: 容器 Column×1; layoutWeight×1; margin×1; 百分比宽度; 对齐 API×2
- **设计**: token: 文字色×4 字号字重×6
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `SubjectViewToggle` — pages/Notes/SubjectViewToggle.ets (60 行) · 页面局部组件
- **布局**: 容器 Row×1; padding×3; 对齐 API×1
- **设计**: token: 主色×3 玻璃×4 文字色×3 圆角×4 字号字重×6
- **动效**: 无动效(静态) · onClick×2
- **备注**: —

#### `TypeTabRow` — pages/Notes/TypeTabRow.ets (64 行) · 页面局部组件
- **布局**: 容器 Row×1 Scroll×1; padding×2; 百分比宽度; 列表 ForEach×1/LazyForEach×0
- **设计**: token: 主色×5 文字色×2 间距×3 圆角×2 字号字重×2
- **动效**: 无动效(静态) · onClick×1
- **备注**: —

### pages/Review（复习 5）

#### `ReviewGraphView` — pages/Review/ReviewGraphView.ets (1880 行) · 页面局部组件(巨型)
- **布局**: 容器 Column×10 Row×13 Stack×16 Scroll×2; layoutWeight×6; padding×4; margin×12; 百分比宽度; 对齐 API×18; 列表 ForEach×11/LazyForEach×0
- **设计**: token: 主色×22 玻璃×5 文字色×26 间距×28 圆角×14 字号字重×34; shadow×1; ⚠字面量×54
- **动效**: animateTo×8; setInterval×1(手摇帧); 变换 t2/r20/s12; Curve: FastOutSlowIn; ⚠animateTo硬编码时长×8: 180ms×6 / 220ms / 240ms · onClick×7
- **备注**: 1880 行无内部拆分; 候选C3

#### `ReviewPage` — pages/Review/ReviewPage.ets (294 行) · Page
- **布局**: 容器 Column×1 Row×2; layoutWeight×1; padding×1; 百分比宽度; 对齐 API×1
- **设计**: token: 主色×2 玻璃×2 间距×8 圆角×2 字号字重×2
- **动效**: 无动效(静态) · onClick×1
- **备注**: 双视图切换

#### `ReviewPlanRow` — pages/Review/ReviewPlanRow.ets (233 行) · 页面局部组件
- **布局**: 容器 Column×2 Row×3; layoutWeight×1; padding×2; 百分比宽度; 对齐 API×3
- **设计**: token: 主色×11 玻璃×5 文字色×8 间距×7 圆角×7 字号字重×12
- **动效**: 变换 t1/r0/s1 · onClick×2
- **备注**: —

#### `ReviewPlanView` — pages/Review/ReviewPlanView.ets (278 行) · 页面局部组件
- **布局**: 容器 Column×5 Row×5; layoutWeight×5; padding×5; margin×4; 百分比宽度; 对齐 API×3; 列表 ForEach×2/LazyForEach×0; TextInput×1(受控)
- **设计**: token: 主色×6 玻璃×6 文字色×12 间距×26 圆角×7 字号字重×14; linearGradient×2; ⚠字面量×3
- **动效**: 无动效(静态) · onClick×2
- **备注**: —

#### `ReviewTabSwitch` — pages/Review/ReviewTabSwitch.ets (39 行) · 页面局部组件
- **布局**: 容器 Row×1; layoutWeight×1; padding×1; 对齐 API×1
- **设计**: token: 主色×2 玻璃×2 文字色×2 圆角×3 字号字重×4
- **动效**: 无动效(静态) · onClick×1
- **备注**: —

### pages/Profile（我的 6）

#### `ProfileHeader` — pages/Profile/ProfileHeader.ets (69 行) · 页面局部组件
- **布局**: 容器 Column×1 Stack×1; padding×1; margin×2; 百分比宽度; 对齐 API×1
- **设计**: token: 主色×3 玻璃×3 文字色×6 间距×10 字号字重×11 组件尺寸×4
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `ProfileLoginPanel` — pages/Profile/ProfileLoginPanel.ets (104 行) · 页面局部组件
- **布局**: 容器 Column×2 Row×3 Stack×1; layoutWeight×2; padding×2; margin×6; 百分比宽度; 对齐 API×4
- **设计**: token: 主色×4 玻璃×2 文字色×7 间距×21 圆角×4 字号字重×11
- **动效**: 无动效(静态) · onClick×1
- **备注**: —

#### `ProfileMenuItemRow` — pages/Profile/ProfileMenuItemRow.ets (60 行) · 页面局部组件
- **布局**: 容器 Row×1; layoutWeight×1; padding×1; margin×1; 百分比宽度
- **设计**: token: 文字色×7 间距×4 字号字重×6
- **动效**: 无动效(静态) · onClick×1
- **备注**: —

#### `ProfileMenuList` — pages/Profile/ProfileMenuList.ets (83 行) · 页面局部组件
- **布局**: 容器 Column×1; margin×1; 百分比宽度
- **设计**: token: 间距×7 圆角×3
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `ProfilePage` — pages/Profile/ProfilePage.ets (147 行) · Page
- **布局**: 容器 Column×1 Row×1 Scroll×1; margin×1; 百分比宽度
- **设计**: token: 玻璃×2 间距×10 圆角×2 字号字重×2 语义色×4
- **动效**: 无动效(静态) · onClick×1
- **备注**: 组装

#### `ProfileStatsRow` — pages/Profile/ProfileStatsRow.ets (48 行) · 页面局部组件
- **布局**: 容器 Row×1; padding×1; 百分比宽度; 对齐 API×1
- **设计**: token: 间距×5
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

### pages/AiSettings（设置 9）

#### `ActionBar` — pages/AiSettings/ActionBar.ets (56 行) · 页面局部组件
- **布局**: 容器 Row×1; layoutWeight×2; padding×1; margin×1; 百分比宽度
- **设计**: token: 主色×5 文字色×3 间距×4 圆角×4 字号字重×4; ⚠字面量×1
- **动效**: 无动效(静态) · onClick×2
- **备注**: —

#### `AiSettingsPage` — pages/AiSettings/AiSettingsPage.ets (205 行) · Page
- **布局**: 容器 Column×4 Row×2 Scroll×1; layoutWeight×1; padding×5; margin×2; 百分比宽度
- **设计**: token: 文字色×10 间距×23 字号字重×15
- **动效**: 无动效(静态) · onClick×0
- **备注**: 唯一零 shared 组件页面; 候选C6

#### `ConnectionStatus` — pages/AiSettings/ConnectionStatus.ets (55 行) · 页面局部组件
- **布局**: 容器 Column×1 Row×1; padding×1; margin×2; 百分比宽度; 对齐 API×1
- **设计**: token: 主色×5 文字色×9 间距×3 圆角×3 字号字重×9
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `EndpointPicker` — pages/AiSettings/EndpointPicker.ets (82 行) · 页面局部组件
- **布局**: 容器 Column×1 Row×2; layoutWeight×1; padding×2; margin×1; 百分比宽度; TextInput×1(受控)
- **设计**: token: 文字色×7 圆角×6 字号字重×6; ⚠字面量×1
- **动效**: 无动效(静态) · onClick×0
- **备注**: 受控 TextInput

#### `KeyInput` — pages/AiSettings/KeyInput.ets (68 行) · 页面局部组件
- **布局**: 容器 Row×1; layoutWeight×1; padding×1; margin×2; 百分比宽度; TextInput×1(受控)
- **设计**: token: 主色×3 文字色×6 圆角×6 字号字重×6
- **动效**: 无动效(静态) · onClick×1
- **备注**: Password TextInput 受控

#### `ModelPicker` — pages/AiSettings/ModelPicker.ets (78 行) · 页面局部组件
- **布局**: 容器 Column×2 Row×2; layoutWeight×2; padding×3; margin×4; 百分比宽度; 对齐 API×1; TextInput×1(受控)
- **设计**: token: 文字色×6 间距×2 圆角×4 字号字重×7; ⚠字面量×1
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `OcrConfigSection` — pages/AiSettings/OcrConfigSection.ets (168 行) · 页面局部组件
- **布局**: 容器 Column×1 Row×6; layoutWeight×8; padding×8; margin×3; 百分比宽度; TextInput×1(受控)
- **设计**: token: 文字色×12 圆角×9 字号字重×12; ⚠字面量×6
- **动效**: 无动效(静态) · onClick×5
- **备注**: —

#### `PageHeader` — pages/AiSettings/PageHeader.ets (20 行) · 页面局部组件
- **布局**: 容器 Row×2; padding×1; 百分比宽度
- **设计**: token: 主色×2 文字色×2 间距×6 字号字重×6
- **动效**: 无动效(静态) · onClick×1
- **备注**: —

#### `SectionHeader` — pages/AiSettings/SectionHeader.ets (42 行) · 页面局部组件
- **布局**: 容器 Column×1; padding×1; margin×1; 百分比宽度; 对齐 API×1
- **设计**: token: 文字色×6 间距×3 字号字重×9
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

### pages/Index（Tab 容器 1）

#### `Index` — pages/Index.ets (106 行) · Page
- **布局**: 容器 Column×2 Stack×1; layoutWeight×1; 百分比宽度
- **设计**: 纯几何/无样式调用
- **动效**: setTimeout×1(延迟) · onClick×0
- **备注**: 5Tab+浮层挂载; Tab2 特判弹窗

### overlays/AgentFloatWindow（AI 浮窗 11）

#### `AgentFloatWindow` — overlays/AgentFloatWindow/AgentFloatWindow.ets (272 行) · 浮层容器(器官)
- **布局**: 容器 Column×2 Row×4 Stack×1; padding×1; 百分比宽度; 对齐 API×1
- **设计**: token: 文字色×2 间距×5 圆角×3 遮罩×2
- **动效**: animateTo×2; DUR_*×5; setTimeout×3(延迟); 变换 t1/r0/s0; Curve: FastOutSlowIn · onClick×1
- **备注**: 容器持服务+手势+多会话; OVERLAY_MASK 遮罩

#### `AgentInputBar` — overlays/AgentFloatWindow/AgentInputBar.ets (78 行) · 浮层局部组件
- **布局**: 容器 Row×1 Stack×2; layoutWeight×1; padding×2; margin×2; 百分比宽度; 对齐 API×3; TextInput×1(受控)
- **设计**: token: 主色×2 文字色×6 字号字重×6; ⚠字面量×3
- **动效**: 无动效(静态) · onClick×2
- **备注**: 受控 TextInput+发送

#### `AgentMessageList` — overlays/AgentFloatWindow/AgentMessageList.ets (133 行) · 器官
- **布局**: 容器 Column×1 Row×1 List×1; layoutWeight×1; padding×2; margin×2; 百分比宽度; 对齐 API×1; 列表 ForEach×0/LazyForEach×1
- **设计**: token: 主色×2 文字色×3 间距×7
- **动效**: setTimeout×1(延迟) · onClick×0
- **备注**: 消息列表容器

#### `ImagePreviewBar` — overlays/AgentFloatWindow/ImagePreviewBar.ets (44 行) · 浮层局部组件
- **布局**: 容器 Row×1; layoutWeight×1; padding×1; margin×1; 百分比宽度
- **设计**: token: 文字色×3 字号字重×4; ⚠字面量×1
- **动效**: 无动效(静态) · onClick×1
- **备注**: 待发图预览条

#### `ChatBubble` — overlays/AgentFloatWindow/chat/ChatBubble.ets (139 行) · 器官(分子级组合)
- **布局**: 容器 Column×5 Row×3; padding×4; margin×6; 百分比宽度; 对齐 API×2
- **设计**: token: 主色×5 文字色×8 间距×29 圆角×7 字号字重×8; ⚠字面量×3
- **动效**: 无动效(静态) · onClick×1
- **备注**: 按消息含公式分支选两个分子

#### `ChatHeader` — overlays/AgentFloatWindow/chat/ChatHeader.ets (107 行) · 浮层局部组件
- **布局**: 容器 Row×2 Stack×2; padding×2; margin×2; 百分比宽度; 对齐 API×1
- **设计**: token: 主色×10 文字色×12 间距×14 圆角×2 字号字重×8
- **动效**: 变换 t0/r2/s0 · onClick×3
- **备注**: 会话头

#### `ChatModels` — overlays/AgentFloatWindow/chat/ChatModels.ets (64 行) · 模型/类型(非视觉)
- **布局**: —
- **设计**: 纯几何/无样式调用
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `ChatSession` — overlays/AgentFloatWindow/chat/ChatSession.ets (62 行) · 模型/类型(非视觉)
- **布局**: —
- **设计**: 纯几何/无样式调用
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `EmptyStateHint` — overlays/AgentFloatWindow/chat/EmptyStateHint.ets (55 行) · 浮层局部组件
- **布局**: 容器 Column×1 Stack×1; padding×1; margin×2; 百分比宽度; 对齐 API×1
- **设计**: token: 主色×5 文字色×6 间距×7 字号字重×6
- **动效**: 无动效(静态) · onClick×0
- **备注**: 空态

#### `QuickSuggestions` — overlays/AgentFloatWindow/chat/QuickSuggestions.ets (60 行) · 浮层局部组件
- **布局**: 容器 Column×1 Row×1; padding×3; margin×1; 百分比宽度
- **设计**: token: 主色×6 文字色×3 间距×13 圆角×2 字号字重×4
- **动效**: 无动效(静态) · onClick×1
- **备注**: 快捷建议 chips

#### `SessionBar` — overlays/AgentFloatWindow/chat/SessionBar.ets (94 行) · 浮层局部组件
- **布局**: 容器 Row×3 Scroll×1; layoutWeight×1; padding×3; margin×2; 百分比宽度; 列表 ForEach×1/LazyForEach×0
- **设计**: token: 主色×7 玻璃×4 文字色×7 间距×12 圆角×2 字号字重×6
- **动效**: 无动效(静态) · onClick×3
- **备注**: 多会话切换条

### overlays/CameraOverlay（相机 10）

#### `CameraAlbumBtn` — overlays/CameraOverlay/CameraAlbumBtn.ets (22 行) · 浮层局部组件
- **布局**: 容器 Stack×1; 对齐 API×1
- **设计**: ⚠字面量×3
- **动效**: 无动效(静态) · onClick×1
- **备注**: —

#### `CameraBackBtn` — overlays/CameraOverlay/CameraBackBtn.ets (22 行) · 浮层局部组件
- **布局**: 容器 Stack×1; 对齐 API×1
- **设计**: token: 文字色×2 字号字重×2; ⚠字面量×2
- **动效**: 无动效(静态) · onClick×1
- **备注**: —

#### `CameraCapture` — overlays/CameraOverlay/CameraCapture.ets (65 行) · 浮层局部组件
- **布局**: 容器 Column×4 Row×2 Stack×1; layoutWeight×1; padding×2; margin×2; 百分比宽度; 对齐 API×4
- **设计**: token: 文字色×2 间距×15 字号字重×9; ⚠字面量×4
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `CameraCloseBtn` — overlays/CameraOverlay/CameraCloseBtn.ets (20 行) · 浮层局部组件
- **布局**: 容器 Stack×1; 对齐 API×1
- **设计**: ⚠字面量×3
- **动效**: 无动效(静态) · onClick×1
- **备注**: —

#### `CameraConfirmBtn` — overlays/CameraOverlay/CameraConfirmBtn.ets (35 行) · 浮层局部组件
- **布局**: 容器 Row×1; layoutWeight×1; margin×1; 对齐 API×2
- **设计**: token: 主色×2 字号字重×6
- **动效**: 无动效(静态) · onClick×1
- **备注**: 自绘双环确认钮

#### `CameraOverlay` — overlays/CameraOverlay/CameraOverlay.ets (132 行) · 浮层容器(器官)
- **布局**: 容器 Column×2 Row×2 Stack×1; margin×1; 百分比宽度; 对齐 API×1
- **设计**: token: 文字色×2 间距×9 组件尺寸×4
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `CameraPreview` — overlays/CameraOverlay/CameraPreview.ets (84 行) · 浮层局部组件
- **布局**: 容器 Column×3 Row×3 Stack×1; layoutWeight×2; padding×3; 百分比宽度; 对齐 API×3
- **设计**: token: 文字色×6 间距×18 字号字重×12 组件尺寸×2; ⚠字面量×2
- **动效**: 无动效(静态) · onClick×1
- **备注**: XComponent 取景器

#### `CameraShutterBtn` — overlays/CameraOverlay/CameraShutterBtn.ets (26 行) · 浮层局部组件
- **布局**: 容器 Stack×3; 对齐 API×1
- **设计**: token: 主色×3 间距×2
- **动效**: 无动效(静态) · onClick×1
- **备注**: CAM_SHUTTER_OUTER/INNER 双环尺寸令牌

#### `CameraTypes` — overlays/CameraOverlay/CameraTypes.ets (6 行) · 模型/类型(非视觉)
- **布局**: —
- **设计**: 纯几何/无样式调用
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `ViewfinderCorners` — overlays/CameraOverlay/ViewfinderCorners.ets (83 行) · 浮层局部组件
- **布局**: 容器 Column×2 Row×1 Stack×5; padding×1; 百分比宽度
- **设计**: token: 主色×3 间距×23
- **动效**: 无动效(静态) · onClick×0
- **备注**: 取景四角(纯几何)

### overlays/NoteDetailOverlay（笔记详情 22）

#### `ChipTag` — overlays/NoteDetailOverlay/ChipTag.ets (65 行) · 浮层局部组件
- **布局**: padding×1
- **设计**: token: 主色×4 玻璃×4 文字色×7 间距×10 圆角×5 字号字重×9
- **动效**: 无动效(静态) · onClick×1
- **备注**: 标签 chip

#### `ConfDot` — overlays/NoteDetailOverlay/ConfDot.ets (32 行) · 浮层局部组件
- **布局**: margin×1
- **设计**: token: 主色×6 间距×3 语义色×3
- **动效**: 无动效(静态) · onClick×0
- **备注**: DOT_SIZE 置信度圆点

#### `NoteActionBar` — overlays/NoteDetailOverlay/NoteActionBar.ets (25 行) · 浮层局部组件
- **布局**: 容器 Row×1; padding×1; 百分比宽度
- **设计**: token: 文字色×3 间距×8
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `NoteCloseButton` — overlays/NoteDetailOverlay/NoteCloseButton.ets (39 行) · 浮层局部组件
- **布局**: 容器 Stack×1; 对齐 API×1
- **设计**: token: 玻璃×3 文字色×3 间距×4
- **动效**: 无动效(静态) · onClick×1
- **备注**: —

#### `NoteDetailBody` — overlays/NoteDetailOverlay/NoteDetailBody.ets (94 行) · 器官(策略分派)
- **布局**: 容器 Column×1; 百分比宽度
- **设计**: 纯几何/无样式调用
- **动效**: 无动效(静态) · onClick×0
- **备注**: 按 5 种 NoteType 分派 6 渲染器

#### `NoteDetailMeta` — overlays/NoteDetailOverlay/NoteDetailMeta.ets (294 行) · 器官
- **布局**: 容器 Column×2 Row×2; layoutWeight×1; padding×4; margin×5; 百分比宽度; 对齐 API×1
- **设计**: token: 主色×2 文字色×9 间距×24 圆角×5 字号字重×17; linearGradient×1; ⚠字面量×3
- **动效**: 无动效(静态) · onClick×0
- **备注**: 元信息区(294 行)

#### `NoteDetailOverlay` — overlays/NoteDetailOverlay/NoteDetailOverlay.ets (556 行) · 浮层容器(器官)
- **布局**: 容器 Column×8 Row×4 Stack×1 Scroll×1; layoutWeight×4; padding×4; margin×4; 百分比宽度; 对齐 API×3
- **设计**: token: 主色×3 文字色×11 间距×11 圆角×4 字号字重×16 语义色×2 遮罩×3; ⚠字面量×1
- **动效**: 无动效(静态) · onClick×4
- **备注**: 556 行; OVERLAY_MASK_SOLID 遮罩; 直连 service

#### `NoteEditForm` — overlays/NoteDetailOverlay/NoteEditForm.ets (96 行) · 浮层局部组件
- **布局**: 容器 Column×1; padding×5; margin×1; 百分比宽度; TextInput×1(受控)
- **设计**: token: 文字色×12 间距×9 圆角×5 字号字重×9
- **动效**: 无动效(静态) · onClick×0
- **备注**: 4 个受控 TextInput/TextArea

#### `NoteIconButton` — overlays/NoteDetailOverlay/NoteIconButton.ets (33 行) · 浮层局部组件
- **布局**: 容器 Stack×1; 对齐 API×1
- **设计**: token: 玻璃×2 文字色×3 圆角×2; ⚠字面量×1
- **动效**: 无动效(静态) · onClick×1
- **备注**: —

#### `DetailMetaFooter` — overlays/NoteDetailOverlay/components/DetailMetaFooter.ets (208 行) · 浮层局部组件
- **布局**: 容器 Column×3 Row×3 Flex×1; layoutWeight×2; padding×1; margin×4; 百分比宽度; 对齐 API×4; 列表 ForEach×1/LazyForEach×0
- **设计**: token: 文字色×7 间距×10 字号字重×11
- **动效**: 无动效(静态) · onClick×1
- **备注**: MarkdownRenderer+AppIcon 组合

#### `DetailRenderQueue` — overlays/NoteDetailOverlay/components/DetailRenderQueue.ets (144 行) · 工具(非视觉)
- **布局**: —
- **设计**: 纯几何/无样式调用
- **动效**: setTimeout×1(延迟) · onClick×0
- **备注**: 分帧渲染队列(性能动效类)

#### `DetailSection` — overlays/NoteDetailOverlay/components/DetailSection.ets (141 行) · 浮层局部组件
- **布局**: 容器 Column×2 Row×1; layoutWeight×1; padding×1; margin×2; 百分比宽度; 对齐 API×2
- **设计**: token: 主色×2 文字色×4 间距×7 字号字重×4
- **动效**: 无动效(静态) · onClick×0
- **备注**: 分节容器

#### `DetailStepList` — overlays/NoteDetailOverlay/components/DetailStepList.ets (111 行) · 浮层局部组件
- **布局**: 容器 Column×2 Row×2; layoutWeight×1; margin×2; 百分比宽度; 对齐 API×4; 列表 ForEach×1/LazyForEach×0
- **设计**: token: 主色×2 文字色×1 间距×5 圆角×2 字号字重×7; ⚠字面量×1
- **动效**: 无动效(静态) · onClick×1
- **备注**: 步骤列表; index+item key(:69)

#### `DetailStepsSection` — overlays/NoteDetailOverlay/components/DetailStepsSection.ets (111 行) · 浮层局部组件
- **布局**: 容器 Column×2 Row×1; layoutWeight×1; padding×1; margin×2; 百分比宽度; 对齐 API×2
- **设计**: token: 主色×2 文字色×4 间距×7 字号字重×4
- **动效**: 无动效(静态) · onClick×0
- **备注**: —

#### `DetailRenderCache` — overlays/NoteDetailOverlay/model/DetailRenderCache.ets (155 行) · 工具(非视觉)
- **布局**: —
- **设计**: 纯几何/无样式调用
- **动效**: 无动效(静态) · onClick×0
- **备注**: 渲染缓存+失效

#### `DetailRenderModel` — overlays/NoteDetailOverlay/model/DetailRenderModel.ets (491 行) · 工具(非视觉)
- **布局**: —
- **设计**: 纯几何/无样式调用
- **动效**: 无动效(静态) · onClick×0
- **备注**: 491 行渲染数据建模(非视觉)

#### `ComputationDetailView` — overlays/NoteDetailOverlay/renderers/ComputationDetailView.ets (283 行) · 浮层局部组件
- **布局**: 容器 Column×7; padding×8; margin×7; 百分比宽度; 对齐 API×7
- **设计**: token: 文字色×11 间距×29 字号字重×18; ⚠字面量×1
- **动效**: setTimeout×1(延迟) · onClick×0
- **备注**: —

#### `ConceptDetailView` — overlays/NoteDetailOverlay/renderers/ConceptDetailView.ets (257 行) · 浮层局部组件
- **布局**: 容器 Column×6; padding×7; margin×6; 百分比宽度; 对齐 API×6
- **设计**: token: 主色×4 文字色×9 间距×26 字号字重×16
- **动效**: setTimeout×1(延迟) · onClick×0
- **备注**: —

#### `FallbackDetailView` — overlays/NoteDetailOverlay/renderers/FallbackDetailView.ets (180 行) · 浮层局部组件
- **布局**: 容器 Column×2 Row×1; padding×3; margin×3; 百分比宽度; 对齐 API×2; 列表 ForEach×1/LazyForEach×0
- **设计**: token: 文字色×7 间距×17 字号字重×11
- **动效**: setTimeout×1(延迟) · onClick×0
- **备注**: —

#### `FormulaDetailView` — overlays/NoteDetailOverlay/renderers/FormulaDetailView.ets (280 行) · 浮层局部组件
- **布局**: 容器 Column×7; padding×8; margin×7; 百分比宽度; 对齐 API×7
- **设计**: token: 主色×4 文字色×11 间距×29 字号字重×18
- **动效**: setTimeout×1(延迟) · onClick×0
- **备注**: —

#### `ProofDetailView` — overlays/NoteDetailOverlay/renderers/ProofDetailView.ets (279 行) · 浮层局部组件
- **布局**: 容器 Column×7; padding×8; margin×7; 百分比宽度; 对齐 API×7
- **设计**: token: 主色×6 文字色×10 间距×29 字号字重×18
- **动效**: setTimeout×1(延迟) · onClick×0
- **备注**: —

#### `TheoremDetailView` — overlays/NoteDetailOverlay/renderers/TheoremDetailView.ets (280 行) · 浮层局部组件
- **布局**: 容器 Column×7; padding×8; margin×7; 百分比宽度; 对齐 API×7
- **设计**: token: 主色×4 文字色×11 间距×29 字号字重×18
- **动效**: setTimeout×1(延迟) · onClick×0
- **备注**: —


（档案共 96 件 — 与 96 文件清单一一对应）

## Conclusion


设计语言的『静态半边』健康: 色板/间距/字号/阴影预设被广泛消费(高频令牌见 §1), 渐变×9 文件、阴影×6 文件、毛玻璃×1 文件构成稳定的视觉母题库, 96 文件 rgba/hex 字面量 111 处集中于三公式组件与浮层。设计语言的『动态半边』半接入: animateTo 通道在 3 个文件里是令牌合规范本, 但 ReviewGraphView 与 GradientRing 两处主力视图绕过令牌各自为政, 属性动画 .animation()/.transition() 全前端缺席, 呼吸周期令牌与实现各说各话 — 动效收口(统一 MotionPolicy)是设计系统下一个最值得做的 PR。

## Implications


- 候选 **C2-动效变体**: 建 MotionPolicy module — animateTo 包装器 + DUR_*/Curve 唯一消费口; ReviewGraphView 180-240ms 迁移到最近令牌(DUR_INSTANT/FAST/BASE 三选一裁决), GradientRing 手摇帧改 Canvas 重绘 + 令牌时长; 呼吸周期 3000 令牌 vs ≈1500 实现需设计裁决

- FloatingButton/AiTabButton 补 DUR_INSTANT 按压反馈(scale 0.96 + shadow 收缩) — 评委可感知的低成本打磨

- 令牌去留裁决: LH_HEADING/SUCCESS/WARNING 为真死令牌(连 common 侧无消费者), 随 audit #1 一并处理

- index-key 修复(MarkdownRenderer:139,172 / DetailStepList:69)与本档案的布局母题表可组成 spec 012 后续 PR 的 checklist

## Open questions


- 呼吸周期以谁为准: 令牌 3000ms 还是实现 1500ms? (需要设计裁决)

- 浮层转场是否有意省略 `.transition()` (现在浮层出现是硬切)?

- ReviewGraphView 星系是否计划加入缓动/惯性缩放? (1880 行内 grep 未见 animation)


---

## Primary source citations

- `common/src/main/ets/constants/ColorTokens.ets:14-233` — 全部设计令牌定义
- `entry/src/main/ets/pages/Home/GradientRing.ets:22-112` — Canvas 渐变弧/手摇帧/呼吸光晕
- `entry/src/main/ets/pages/MainTabs/TabBar.ets:42-70` — 毛玻璃底栏/稳定 key
- `entry/src/main/ets/pages/Home/FloatingButton.ets:18-31` / `MainTabs/AiTabButton.ets:16-35` — 渐变圆钮
- 96 文件机器提取 (令牌热度/动效 API/布局容器/字面量计数) — 本文档 §1/§2/§4 全部数据
- 配套: frontend-component-audit-2026-09-06.md (组件结构与分层判定) · HTML 体检报告(临时目录, 不入库)

## Last updated

2026-09-06
