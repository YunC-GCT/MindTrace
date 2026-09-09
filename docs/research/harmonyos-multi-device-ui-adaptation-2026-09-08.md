# HarmonyOS NEXT API 24 一次开发、多端部署调研

> MindTrace `entry` 模块适配手机、平板、折叠屏与 2-in-1 的研究依据和实施输入。

- Date: 2026-09-08
- Scope: ArkUI 页面布局、导航、窗口、资源、输入与测试，不涉及业务逻辑改造
- SDK baseline: HarmonyOS 6.1.1, API 24, SDK `6.1.1.125 Release`
- Evidence policy: 平台事实只引用华为官方文档、官方 API Reference 和 DevEco 随附 SDK；项目事实引用仓库源码与已有审计

## 结论摘要

1. **MindTrace 已能被打包到多类设备，但还没有完成多端 UI 适配。** `entry/src/main/module.json5` 已声明 `phone`、`tablet`、`2in1`，然而 `entry` 中没有统一窗口断点、窗口变化监听、折叠状态监听或多端导航策略。设备声明解决“可部署”，不解决“如何显示”。
2. **布局决策应以当前窗口而不是设备名称为主。** API 24 已提供 `UIContext.getWindowWidthBreakpoint()` 和 `windowSizeLayoutBreakpointChange`，官方宽度档位为 `<320`、`320-599`、`600-839`、`840-1439`、`>=1440vp`。同一台 2-in-1 或折叠屏在自由窗口、分屏、展开前后会跨越多个档位。
3. **自适应与响应式需要组合使用。** 自适应用弹性尺寸、约束、滚动和内容最大宽度吸收连续变化；响应式在断点处切换列数、导航位置、主从布局和浮层形态。只做其中一种都不足以覆盖 MindTrace。
4. **建议建立一个窗口布局策略作为单一入口。** 页面不应各自读取屏幕宽度或判断 `tablet`。策略统一输出宽高断点、内容最大宽度、列数、导航模式和浮层模式；页面只消费这些语义值。
5. **主导航是第一优先级。** 当前始终显示 74vp 底部五 Tab。建议紧凑窗口保留底栏，中等窗口改为侧边导航，宽窗口采用侧栏加主内容，并让笔记列表/详情形成主从布局。
6. **折叠状态是补充信号，不是主要布局信号。** 先响应窗口尺寸，再在需要避让折痕、保持相机/浮层连续性时读取 `display` 的折叠能力和折痕区域。
7. **实施应先打基础再逐页迁移。** 先建立断点策略和尺寸回归，再迁移导航、Notes/Home、浮层和知识星系，最后补齐键鼠、焦点、资源与真机矩阵。不要按设备复制四套页面。

## 1. 研究范围与证据边界

### 1.1 本文回答的问题

本文回答：如何让同一套 MindTrace ArkUI 工程在手机、平板、折叠屏和 2-in-1 的不同窗口形态下保持可用、信息密度合理、导航连续，并可以通过自动化与真机矩阵验收。

“一次开发、多端部署”在本文中的含义是：

- 共享领域模型、ViewModel、Service、组件和大部分资源；
- 通过窗口断点和组件约束选择少量布局模式；
- 对相机、鼠标、键盘、折痕等设备能力做局部增强或降级；
- 不为每类设备复制一套业务页面。

### 1.2 一手证据

根 `build-profile.json5` 已配置 API 24。本机 DevEco Studio 随附的官方 `sdk/default/sdk-pkg.json` 进一步确认：

| 字段 | 值 |
|---|---|
| `apiVersion` | `24` |
| `displayName` | `HarmonyOS 6.1.1` |
| SDK version | `6.1.1.125` |
| release type | `Release` |

本文将 `<DevEco-SDK>` 表示 DevEco Studio 安装目录下的 `sdk/default`，避免把机器绝对路径写入仓库。API 事实由以下官方 SDK 声明交叉验证：

- `<DevEco-SDK>/openharmony/ets/component/grid_row.d.ts`
- `<DevEco-SDK>/openharmony/ets/component/grid_col.d.ts`
- `<DevEco-SDK>/openharmony/ets/component/navigation.d.ts`
- `<DevEco-SDK>/openharmony/ets/component/sidebar.d.ts`
- `<DevEco-SDK>/openharmony/ets/component/tabs.d.ts`
- `<DevEco-SDK>/openharmony/ets/component/enums.d.ts`
- `<DevEco-SDK>/openharmony/ets/component/common.d.ts`
- `<DevEco-SDK>/openharmony/ets/api/@ohos.arkui.UIContext.d.ts`
- `<DevEco-SDK>/openharmony/ets/api/@ohos.arkui.observer.d.ts`
- `<DevEco-SDK>/openharmony/ets/api/@ohos.mediaquery.d.ts`
- `<DevEco-SDK>/openharmony/ets/api/@ohos.window.d.ts`
- `<DevEco-SDK>/openharmony/ets/api/@ohos.display.d.ts`

### 1.3 在线文档限制

华为开发者文档页面在本次环境中以动态 SPA 加载，直接 HTTP 请求只能稳定取得页面外壳，无法为正文生成可重复的离线快照。因此：

- 报告仍提供华为官方指南和 API Reference 链接，供人在浏览器中复核；
- 精确的 API 名称、枚举阈值和 `@since` 以本机 API 24 官方 SDK 声明为准；
- 未在 SDK 中核实的具体接口不写成实施要求；
- 正式编码前仍需在 DevEco Studio 对目标 API 24 工程进行补全和编译验证。

## 2. 官方多端开发模型与适用边界

HarmonyOS 的多端工程包含三个不同层次，不能混为一谈：[H1][H2]

| 层次 | 解决的问题 | MindTrace 当前状态 |
|---|---|---|
| 设备声明 | HAP 可以面向哪些设备类型安装 | 已声明 `phone`、`tablet`、`2in1` |
| 共享实现 | 业务、数据和组件是否复用 | 五模块与 ViewModel/Service 已具备共享基础 |
| 运行时适配 | 不同窗口如何布局、导航和交互 | 尚未建立统一策略 |

适用边界：

- **同构业务适合共享。** OCR、AI 分类、KnowledgeUnit、复习调度和数据访问不应因设备改变。
- **布局应随窗口变化。** 分屏、自由窗口和折叠展开意味着“平板”也可能只有手机宽度，“2-in-1”也可能被缩到紧凑窗口。
- **硬件能力必须单独处理。** 相机、触摸、鼠标、键盘和折叠能力不能仅由 `deviceTypes` 推断。
- **可部署不代表体验达标。** 声明三类设备后仍需为溢出、留白、导航、输入和状态连续性设置验收门槛。
- **本轮不覆盖穿戴和智慧屏。** 当前 manifest 未声明这两类设备，其交互和信息架构也不适合直接复用当前五 Tab 体验。

## 3. 自适应布局与响应式布局

官方布局指南将多尺寸处理拆成自适应和响应式思路。[H2][H3][H4]

| 方式 | 变化方式 | 适合解决 | MindTrace 用法 |
|---|---|---|---|
| 自适应 | 连续变化 | 宽高约束、弹性空白、滚动、内容最大宽度、图片裁切 | 表单、列表、卡片、浮层正文 |
| 响应式 | 在断点切换 | 列数、导航位置、单栏/双栏、浮层/侧面板 | Index、Notes、详情、AI 对话 |

组合原则：

1. 先让组件在一个布局模式内可伸缩，使用百分比、`layoutWeight`、`constraintSize`、合理的 `min/max` 和滚动容器。
2. 再用宽度断点切换结构，例如底栏变侧栏、两列变四列、列表详情由覆盖式变并排式。
3. 对可复用局部组件优先参考组件宽度；对全页导航与信息架构参考窗口宽度。`GridRow` 的 `BreakpointsReference.WindowSize` 和 `ComponentSize` 均已在 API 24 SDK 中提供。
4. 不直接用物理像素或具体机型名驱动布局；统一使用 vp 和窗口断点。
5. 断点变化必须保留用户状态，例如当前 Tab、已选 Subject、打开的 KnowledgeUnit、聊天会话和星系相机位置。

## 4. 窗口尺寸、方向与自由窗口

### 4.1 API 24 官方宽度档位

`WidthBreakpoint` 在 API 24 SDK 中定义如下；枚举自 API 13 提供，跨平台标注自 API 22 提供：[H7]

| 档位 | 窗口宽度 | 推荐语义 |
|---|---:|---|
| `WIDTH_XS` | `<320vp` | 极窄，仅保证基本可达性 |
| `WIDTH_SM` | `320vp` 至 `<600vp` | 手机/窄窗口，单栏 |
| `WIDTH_MD` | `600vp` 至 `<840vp` | 展开折叠屏/小平板，过渡布局 |
| `WIDTH_LG` | `840vp` 至 `<1440vp` | 平板/2-in-1 主窗口，双栏 |
| `WIDTH_XL` | `>=1440vp` | 超宽 2-in-1，可增加内容密度但需限制行宽 |

`HeightBreakpoint` 以窗口宽高比分类，而不是固定高度：[H7]

| 档位 | SDK 定义的 aspect ratio |
|---|---:|
| `HEIGHT_SM` | `<0.8` |
| `HEIGHT_MD` | `0.8` 至 `<1.2` |
| `HEIGHT_LG` | `>=1.2` |

项目应以官方枚举为内部事实源，不再另外维护一套含义相同但阈值不同的 `small/medium/large`。

### 4.2 监听策略

API 24 可选的三层信号：[H7][H9][H10]

| 信号 | API 24 状态 | 使用建议 |
|---|---|---|
| `UIContext.getWindowWidthBreakpoint()` | 可用；基础能力 since 13 | 初始读取宽度档位 |
| `UIContext.getWindowHeightBreakpoint()` | 可用；since 13 | 初始读取高度档位（与宽度成对，勿只读宽） |
| `UIObserver` `windowSizeLayoutBreakpointChange`（**经 `UIContext.getUIObserver()` 获取实例**，非 UIContext 本身） | 可用；since 22 | 全局布局模式变化的首选事件 |
| `Window.on('windowSizeChange')` | 可用；since 7 | 需要精确宽高、画布或浮层尺寸时使用 |
| UIContext `MediaQuery.matchMediaSync()` | 可用；since 10 | 方向、宽高等组合条件的局部查询 |
| 顶层 `mediaquery.matchMediaSync()` | API 24 仍存在，但 since 18 已废弃（SDK 标注 `@useinstead ohos.arkui.UIContext.MediaQuery#matchMediaSync`） | 新代码禁止使用，改用 UIContext |

`windowSizeLayoutBreakpointChange` 回调负载为 `uiObserver.WindowSizeLayoutBreakpointInfo`（since 22），含两个只读字段 `widthBreakpoint: WidthBreakpoint` 与 `heightBreakpoint: HeightBreakpoint`；一次事件即可同时更新宽高两档，无需在回调里再各查一次。注册方式：`this.getUIContext().getUIObserver().on('windowSizeLayoutBreakpointChange', cb)`，`off` 成对注销。

监听必须成对注册和注销。MindTrace 应把监听放在 UI 生命周期明确的组合位置，更新单一布局状态；页面不得各自创建重复监听器。

### 4.3 横竖屏与自由窗口

- 横竖屏是窗口形状，不是设备类型。主布局先由宽度档位决定，再用高度档位或媒体查询处理高度不足。
- 2-in-1 的自由窗口可从 XL 缩到 SM；布局必须在运行时切换，不能只在 Ability 启动时计算一次。
- 当前 `EntryAbility.ets` 只在 `onWindowStageCreate` 中读取一次状态栏避让区。窗口变化后状态栏、可绘制区域和布局档位可能变化，应建立持续更新机制。
- 精确绘制使用 `WindowProperties.drawableRect` 而不是假定全屏尺寸；该字段在当前 SDK 可用。[H10]

## 5. 布局组件技术选型

| 组件/机制 | 适用场景 | 不适合的场景 | MindTrace 建议 | API 24 证据 |
|---|---|---|---|---|
| `GridRow` + `GridCol` | 页面级响应式栅格；按断点配置 span/offset/order | 长列表虚拟化 | 首页模块、设置表单、宽屏主从区域 | since 9；支持窗口/组件宽度断点 [H5] |
| `Flex` | 单行/换行的轻量自适应排列 | 需要明确响应式列跨度的复杂页面 | 标签、摘要指标、操作区 | 当前 SDK 可用 [H3] |
| `Grid` | 同类重复卡片、多列集合 | 页面整体信息架构 | Subject 卡片；列模板由断点策略生成 | 当前 SDK 可用 [H3] |
| `List` + `LazyForEach` | 长列表、按需创建、滚动状态 | 少量静态信息块 | Notes、复习项、聊天、长公式块 | 当前 SDK 可用 [H3] |
| `Row` / `Column` | 简单局部线性布局 | 直接承担宽屏页面全部结构 | 原子/分子组件内部 | 当前 SDK 可用 [H3] |
| `Navigation` | 页面路由、Stack/Split/Auto 主从导航 | 仅装饰性的五按钮切换 | Notes 列表-详情、设置二级页 | `NavigationMode` 可用；API 24 新增 `AUTO_WITH_ASPECT_RATIO` [H6] |
| `SideBarContainer` | 侧栏与内容区域，可自动隐藏 | 需要完整路由栈管理 | 主应用导航壳或筛选栏 | 基础 since 8，`AUTO` since 10 [H8] |
| 媒体查询 | 方向、宽高组合条件、局部样式差异 | 作为全项目另一套断点状态 | 少量方向/高度条件 | UIContext 版本可用 [H7] |

选择规则：

- 页面整体先由布局策略决定导航和主从结构；页面内部再用 `GridRow/GridCol` 或 `Grid`。
- `GridRow/GridCol` 的 12 列语义适合跨页面保持对齐；`Grid` 更适合同构数据项。
- 长数据集合即使宽屏显示多列，也要保留懒加载和稳定 key，避免用普通 `ForEach` 一次创建全部内容。
- 超宽窗口不应无限拉伸文本。内容区要有最大宽度，剩余空间用于侧栏、辅助信息或留白。

**注意：GridRow 断点与窗口 `WidthBreakpoint` 是两套系统，阈值相同但档位数量不同。** 官方指南明确：GridRow 默认只有 4 档（xs/sm/md/lg，`lg=[840,+∞)`），需显式配置 `breakpoints: { value: ['320vp','600vp','840vp','1440vp'] }`（最多 6 档，可再开 xl/xxl）才与窗口 5 档（XL `>=1440vp`）对齐。若直接用默认配置，`840vp` 以上全部落入 GridRow 的 `lg`，无法区分 §6 的 LG/XL 两态。另：API 20 起 `GridRow.columns` 默认值改为 `{ xs:2, sm:4, md:8, lg:12, xl:12, xxl:12 }`，API 24 工程可依赖该默认列数。

## 6. 导航形态切换

MindTrace 当前 `Index.ets` 始终渲染五个 `Tabs`，并隐藏系统 TabBar、使用 74vp 自绘底栏。建议保留内容索引语义，但把导航表现交给响应式壳：

| 宽度档位 | 主导航 | 页面组织 |
|---|---|---|
| XS/SM | 底部四个内容入口 + 中央 AI 操作 | 单栏，详情覆盖或全屏 |
| MD | 左侧窄导航栏或竖向 Tabs | 单栏为主，局部可双栏 |
| LG/XL | 固定侧栏 + 主内容 | Notes/Review 可主从双栏，设置内容限制最大宽度 |

建议：

1. 将“当前业务页”和“导航如何画”分开，避免页面状态绑定到底栏组件。
2. AI 是动作而非持久内容页，宽屏可以成为固定侧面板或可收起面板，但仍复用同一聊天状态。
3. Notes 的 Subject、KnowledgeUnit 列表和详情适合 `Navigation` 的 Stack/Split 模式。[H6][H14]
4. API 24 的 `AUTO_WITH_ASPECT_RATIO` 可作为候选，但必须在原型中验证其切换规则是否符合比赛 UI；不要仅因它是新 API 就替代所有显式产品决策。其 SDK 标注的精确规则（since 24, 仅 Stage 模型）：导航宽 > `minNavBarWidth`(默认 240vp) + `minContentWidth`(默认 360vp) **且** aspect ratio（height/width）≤ 1.2 时显示 Split，否则 Stack——这意味着窄横屏（如手机横屏 SM 档、高宽比大）会回退 Stack，需确认该行为是否符合 MindTrace 的 MD 侧栏意图。
5. 切换导航模式不得重建 ViewModel、清空滚动位置或关闭用户正在查看的详情。

## 7. 资源、图片、字体与间距适配

HarmonyOS 资源系统支持按设备能力和配置选择资源；资源限定应服务于不可由布局表达的差异，而不是复制整页。[H11]

### 7.1 当前缺口

`entry/src/main/resources` 目前只有：

- `base`：颜色、尺寸、字符串、图像；
- `dark`：颜色；
- `rawfile`：KaTeX 与渲染文件。

没有针对不同窗口/设备形态的资源变体。代码中也存在大量直接字符串和固定尺寸。

### 7.2 建议

- 颜色、字符串、可调尺寸继续走资源和统一 token；不要在每个页面写设备分支。
- 方向、语言、深浅色和必要的设备特定资源按官方资源限定规则组织；具体限定目录名在落地 PR 中由 DevEco 资源校验确认。[H11]
- SVG 图标优先保持矢量；位图设置稳定宽高、合理 `objectFit`，并为无障碍提供语义。
- 文本使用字体单位和系统字体缩放能力，验证 1.0x、1.3x、1.5x；卡片不得用固定高度容纳可增长文本。
- 间距 token 增加布局语义，而不是复制 `S_4` 的变体，例如紧凑页边距、宽屏内容最大宽度、侧栏宽度和面板宽度。
- KaTeX WebView/公式块必须在不同内容宽度下重新测量，不能假定 360vp。

## 8. 触摸、鼠标、键盘与悬停

API 24 官方 SDK 确认以下通用事件可用：[H12]

| 能力 | 最早 `@since` | MindTrace 要求 |
|---|---:|---|
| `onTouch`、`onKeyEvent` | 7 | 保持触摸；为 Escape、Enter、方向键等关键操作定义行为 |
| `onHover`、`onMouse`、`focusable` | 8 | 2-in-1 提供悬停反馈、鼠标命中和焦点可达性 |
| `tabIndex` | 9 | 建立可预测的键盘遍历顺序 |
| `tabStop` | 14 | 精细控制某节点是否参与 Tab 遍历（可选增强） |
| `nextFocus` | 18 | 显式指定焦点移动方向（可选增强，不必全面使用） |

输入适配原则：

- 所有主要命令都必须可点击和可键盘触发；悬停只能增强，不能成为唯一信息来源。
- 自绘 Tab、图标按钮、星系节点和浮层关闭按钮要显式处理焦点与无障碍文本。
- 触控目标不因宽屏而缩小；鼠标环境可以提高信息密度，但不能牺牲触控可用性。
- AI 输入支持 Enter 提交与组合输入法，详情编辑支持焦点移动和键盘避让。
- 浮层打开时焦点进入面板，关闭后回到触发元素；Escape/返回行为需要一致。

仓库现状：除知识星系局部 `.onHover` 外，未发现系统性的 `focusable`、`tabIndex`、`onKeyEvent` 或无障碍接入。已有 `frontend-a11y-audit-2026-09-06.md` 可作为后续实现输入。

## 9. 折叠屏状态与窗口变化

API 24 SDK 中的 `display` 能力：[H13]

| API/事件 | 最早 `@since` | 用途 |
|---|---:|---|
| `getFoldStatus()`、`foldStatusChange` | 10 | 获取/监听折叠状态 |
| `getFoldDisplayMode()`、`foldDisplayModeChange` | 10 | 获取/监听显示模式 |
| `getCurrentFoldCreaseRegion()` | 10 | 获取折痕区域 |
| `isFoldable()` | 12 | 判断当前显示设备是否可折叠 |
| `foldAngleChange` | 12 | 需要连续角度体验时监听 |

MindTrace 的处理顺序：

1. 始终先依据窗口宽度断点选择布局。
2. 仅当 `isFoldable()` 为真时订阅折叠事件。
3. 用折痕区域避免把 AI 发送按钮、相机快门、详情主操作或星系焦点节点放在不可交互区域。
4. 展开/折叠时保留当前 Tab、KnowledgeUnit、聊天会话和相机流程，不重新创建 Order。
5. 状态栏/安全区与可绘制区域随窗口事件重新计算，修复当前仅启动时计算一次的问题。
6. 在生命周期结束时成对 `off`，避免重复回调和内存泄漏。

不建议仅根据 `FoldStatus` 决定单栏/双栏：分屏后的展开折叠屏仍可能是 SM，普通平板也可能是 LG，两者都应由同一宽度策略处理。

## 10. API 24 可用与不适用接口

| 能力 | API 24 | 采用裁决 |
|---|---|---|
| `GridRow/GridCol` 响应式 span/offset/order | 可用，since 9 | 采用 |
| `BreakpointsReference.WindowSize/ComponentSize` | 可用，since 9 | 采用；页面/组件分别选基准 |
| `GridRow.onBreakpointChange` | 可用，since 9 | 可用于局部栅格，不作为全局第二状态源 |
| UIContext `MediaQuery.matchMediaSync()` | 可用，since 10 | 局部条件采用 |
| 顶层 `mediaquery.matchMediaSync()` | 已废弃 since 18 | 新代码禁用 |
| `getWindowWidthBreakpoint()` | 可用，基础 since 13 | 采用为初始断点 |
| `getWindowHeightBreakpoint()` | 可用，since 13 | 采用为初始高度断点（§4.2 已补） |
| `windowSizeLayoutBreakpointChange` | 可用，since 22（**挂在 `UIObserver` 上，经 `UIContext.getUIObserver()` 取得**） | 采用为全局断点事件（回调同时带宽高两档） |
| `Window.on('windowSizeChange')` | 可用，since 7 | 画布/浮层需要精确尺寸时采用 |
| `NavigationMode`、`mode()` | 可用，since 9 | Notes 主从导航候选 |
| `NavigationMode.AUTO_WITH_ASPECT_RATIO` | API 24 新增（仅 Stage 模型） | 原型验证后决定 |
| `Navigation.minContentWidth()` | 可用，since 10，默认 360vp | 为自动 Split 设置内容底线 |
| `SideBarContainerType.AUTO` | 可用，since 10 | 主壳侧栏候选 |
| `Tabs.vertical()`、`barPosition()` | 可用（since 7 / since 9） | 自绘侧栏前的低成本候选 |
| 折叠状态/模式/折痕区域 | 可用，since 10；`isFoldable` since 12 | 作为补充信号采用 |
| 键鼠、悬停、焦点、Tab 顺序 | 可用；`tabStop` since 14 / `nextFocus` since 18 | 2-in-1 必须接入（基础三件套），tabStop/nextFocus 可选 |
| 容器断点 `ContainerReader` | **API 26 起，超出 API 24** | **不可用**，勿在 MindTrace 引入；局部响应式走 `BreakpointsReference.ComponentSize` |
| 项目旧规范中“当前 API 9”的限制 | 与构建配置冲突 | 不作为 API 裁决依据；本轮已同步修正相关活动文档 |

**官方 Code Linter 佐证**：`@cross-device-app-dev/one-multi-breakpoint-check` 规则要求“一多特性必须使用系统断点判断是否开启，不能通过设备类型、设备方向或是否可折叠等属性来判断”——与本报告 §2 边界、§6 导航决策和 §9 折叠信号次序一致，可作为团队规约的官方依据。

所有采用项仍需通过 API 24 工程编译；“SDK 中存在”不自动证明当前写法符合 MindTrace 的 ArkTS 1.1 lint 规则。

## 11. 设备支持矩阵

布局矩阵按窗口而不是产品型号执行：

| 设备/形态 | 常见窗口变化 | 默认布局 | 特别验证 |
|---|---|---|---|
| 手机竖屏 | 主要为 SM | 底栏、单栏、全屏详情 | 安全区、键盘、相机、字体缩放 |
| 手机横屏 | 宽度可能 MD，垂直空间紧 | 由宽度决定，结合高度档位压缩头部 | 不裁切输入区和操作栏 |
| 折叠屏外屏 | 多为 SM | 与手机共享紧凑布局 | 展开前后状态连续 |
| 折叠屏内屏 | MD/LG 均可能 | 侧边导航、局部双栏 | 折痕避让、窗口事件、星系重排 |
| 平板竖屏 | MD/LG | 侧边导航，内容限宽 | 列数、留白、详情宽度 |
| 平板横屏 | LG | 侧栏、列表详情双栏 | 鼠标/键盘可选、分屏缩窄 |
| 2-in-1 最大化 | LG/XL | 固定侧栏、多面板、内容限宽 | 键鼠、焦点、自由窗口 |
| 2-in-1 缩小窗口 | SM/MD/LG 动态跨档 | 实时降级到对应模式 | 无重启切换、状态不丢失 |

当前 `deviceTypes` 已覆盖 phone/tablet/2in1。折叠屏不应通过复制一个新业务模块支持，而应在 phone/tablet 窗口策略上增加折叠能力处理。是否需要额外 manifest 类型必须以目标设备和 DevEco 打包校验为准。

## 12. MindTrace `entry` 迁移建议

### 12.1 已确认缺口

| 位置 | 当前事实 | 风险 | 建议 |
|---|---|---|---|
| `entry/src/main/ets/entryability/EntryAbility.ets` | 状态栏高度仅创建时读取一次 | 旋转/折叠/自由窗口后避让失效 | 建立窗口生命周期监听并更新统一布局状态 |
| `entry/src/main/ets/pages/Index.ets` | 始终五 Tab + 74vp 底栏；全局 `KeyboardAvoidMode.NONE` | 宽屏浪费、普通输入框可能被键盘遮挡 | 引入响应式应用壳和分区键盘策略 |
| `pages/MainTabs/TabBar.ets` | 只提供底部 Row 表现 | 平板/2-in-1 无侧边导航 | 保留业务入口模型，增加侧边表现 |
| `pages/Notes/SubjectGrid.ets` | 只有一列或两列 | 宽屏卡片过宽 | 列数和 span 随断点变化 |
| `pages/Notes/NotesList.ets` | `ForEach` 创建全部笔记 | 数据增长后宽屏/滚动性能风险 | 切换稳定 DataSource + `LazyForEach` |
| `pages/Home/HomeRecentNotes.ets` | 单列 `ForEach` | 宽屏信息密度低 | MD+ 采用摘要/最近笔记分区，保留懒加载边界 |
| `overlays/AgentFloatWindow/AgentFloatWindow.ets` | 全宽手机 bottom sheet，位置依赖固定 `SCREEN_H` 和 74 | 自由窗口、宽屏和键盘组合易错 | SM 为 bottom sheet；MD+ 为限宽侧面板/浮层 |
| `overlays/NoteDetailOverlay/NoteDetailOverlay.ets` | 全屏详情，确认框宽 78% | 超宽文本行过长 | SM 全屏；MD+ 为限宽详情或主从右栏 |
| `pages/Review/ReviewGraphView.ets` | 360x520 基准和大量绝对定位 | 宽屏留白或缩放失真 | 保留领域模型，新增 viewport/可绘制区域接缝 |
| `entry/src/main/resources` | 仅 base/dark/rawfile | 无方向/设备资源策略 | 先资源审计，再只为必要差异增加限定资源 |
| 全 `entry` | 键盘/焦点/a11y 基本空白 | 2-in-1 不可完整操作 | 从导航、图标按钮、表单和星系逐步接入 |

### 12.2 建议的布局策略接口

后续 Spec 应定义一个“小接口、大行为”的布局策略，至少输出：

- 当前 `WidthBreakpoint` 和 `HeightBreakpoint`；
- `bottom | rail | sidebar` 导航模式；
- 页面内容最大宽度与页边距；
- Subject/摘要区域列数；
- `fullscreen | dialog | side-panel` 浮层模式；
- Notes 是否启用列表-详情双栏；
- 精确 viewport 和 avoid area，供星系与浮层使用。

该策略属于 UI 布局语义，不应进入 KnowledgeUnit、AgentState 或 CaptureGraph。它可以由 `entry` 的组合根读取 ArkUI/window/display API，再通过受控状态提供给页面。

### 12.3 页面迁移顺序

1. Index 响应式壳、窗口状态和状态连续性。
2. Notes：SubjectGrid、列表与详情，是验证单栏/双栏的最佳 tracer bullet。
3. Home：限宽、模块栅格和最近笔记性能。
4. AI/Note 浮层：按断点切换表现并统一键盘避让。
5. ReviewGraphView：viewport 注入、折痕避让和键鼠缩放。
6. AiSettings/Profile：表单最大宽度、焦点和字体缩放。
7. 资源、a11y 与全矩阵收口。

## 13. 真机、模拟器与截图回归矩阵

### 13.1 断点边界测试

每个断点至少测试边界两侧，避免只测“典型手机”和“典型平板”：

| 宽度 | 目的 |
|---:|---|
| 319 / 320vp | XS-SM 边界 |
| 599 / 600vp | SM-MD、底栏-侧栏边界 |
| 839 / 840vp | MD-LG、单栏-双栏边界 |
| 1439 / 1440vp | LG-XL 边界 |

每个关键宽度至少配一个高窗口和一个低窗口，覆盖横屏、软键盘和自由窗口。

### 13.2 分层矩阵

| 层级 | 环境 | 覆盖内容 | 每次 PR |
|---|---|---|---|
| 静态/单元 | Node + ArkTS 结构测试 | 断点到布局语义的纯映射、监听成对、禁用旧 mediaquery | 必跑 |
| Previewer | 手机/平板/折叠/2-in-1 配置 | 页面结构、溢出、限宽、导航模式 | UI PR 必跑 |
| 模拟器 | 可调整窗口的平板/2-in-1 | 运行时跨断点、键鼠、键盘、路由状态 | Phase 验收 |
| 真机 | 手机 + 至少一台平板或展开折叠屏 | 安全区、相机、折叠、性能、字体 | 发布前必跑 |
| 截图回归 | 四个断点代表尺寸 + 边界尺寸 | 重叠、裁切、异常留白、导航错误 | 建立基线后必跑 |

### 13.3 核心场景

在现有八步 smoke test 上增加：

1. 窗口从 SM 连续扩大到 LG，再缩回 SM，当前 Tab 和选中 KnowledgeUnit 不丢失。
2. Notes 在 599/600 和 839/840vp 切换时，列数与详情模式正确，无重复加载。
3. AI 面板在键盘弹出、窗口缩放和横竖切换后输入区仍可见。
4. 折叠屏外屏进入聊天，展开后会话、草稿和待处理图片保持。
5. 星系在四档宽度下可见、可缩放、节点不落入折痕/不可绘制区域。
6. 2-in-1 只用键盘完成主导航、打开详情、关闭浮层、输入和提交。
7. 系统字体 1.0x/1.3x/1.5x 下按钮和标题不裁切。
8. 截图像素检查同时验证非空渲染和布局边界，不能只判断测试进程成功。

## 14. 分阶段实施、风险与验收标准

| Phase | 交付 | 主要风险 | 退出标准 |
|---|---|---|---|
| 0 决策与原型 | 设备范围、断点语义、三尺寸应用壳原型 | 过早锁定 UI | 团队确认 SM/MD/LG/XL 行为；无业务代码迁移 |
| 1 布局基础 | 单一窗口策略、监听、状态栏/avoid area、纯映射测试 | 多状态源和监听泄漏 | 跨四断点事件唯一、成对注销、状态连续 |
| 2 导航 tracer bullet | Index + Notes 主从布局 | Tabs 状态丢失、路由重建 | SM 底栏、MD+ 侧栏、LG 双栏全部通过 |
| 3 页面迁移 | Home、Settings、Profile、列表虚拟化 | 大量固定尺寸回归 | 边界截图无溢出，长列表无一次性创建退化 |
| 4 浮层与星系 | AI/详情模式切换、viewport、折痕避让 | 键盘与绝对定位组合 | 折叠/缩放/键盘场景均可操作 |
| 5 输入与资源 | 键鼠焦点、a11y、字体、限定资源 | 触控体验被桌面优化破坏 | 触控与键盘双路径通过，1.5x 字体不裁切 |
| 6 发布验证 | 模拟器、真机、截图回归、性能 | 设备覆盖不足 | 全矩阵记录归档，核心拍照-AI-入库链无回归 |

### 14.1 主要风险裁决

- **风险：按设备分支导致四套 UI。** 控制：窗口策略输出语义，页面只保留少量结构分支。
- **风险：断点与媒体查询成为两个真相源。** 控制：全局只存官方宽高断点；媒体查询仅作局部条件。
- **风险：窗口变化重建页面状态。** 控制：业务状态留在现有 ViewModel/Service，布局状态不拥有业务数据。
- **风险：绝对定位星系迁移过大。** 控制：先注入 viewport 和安全区域，不重写 KnowledgeGalaxyViewModel。
- **风险：SDK 存在但项目 lint 不接受写法。** 控制：每个 tracer bullet 同时跑 hvigor build 与 ArkTS lint。
- **风险：只有模拟器结论。** 控制：相机、折叠、键盘和安全区必须有真机记录。

## 15. 可执行代码审计清单

以下命令从仓库根执行，输出是审计入口，不是自动裁决：

```powershell
# 1. 设备声明与 SDK 基线
rg -n 'deviceTypes|targetSdkVersion|compatibleSdkVersion' build-profile.json5 entry/src/main/module.json5

# 2. 是否存在统一断点、窗口和折叠监听
rg -n --glob '*.ets' 'getWindowWidthBreakpoint|windowSizeLayoutBreakpointChange|windowSizeChange|matchMediaSync|foldStatusChange|foldDisplayModeChange|getCurrentFoldCreaseRegion' entry/src/main/ets

# 3. 导航形态是否仍只有手机底栏
rg -n --glob '*.ets' 'Tabs\(|TabBar|Navigation\(|SideBarContainer\(|vertical\(' entry/src/main/ets

# 4. 固定大尺寸和绝对定位热点
rg -n --glob '*.ets' '\.(width|height)\([0-9]{3,}|\.position\(|\.offset\(' entry/src/main/ets

# 5. 固定 Grid 列模板
rg -n --glob '*.ets' 'columnsTemplate|rowsTemplate|GridRow\(|GridCol\(' entry/src/main/ets

# 6. 长列表是否仍使用普通 ForEach
rg -n --glob '*.ets' 'List\(|Grid\(|ForEach\(|LazyForEach\(' entry/src/main/ets

# 7. 键鼠、焦点和无障碍
rg -n --glob '*.ets' 'onHover|onMouse|onKeyEvent|focusable|tabIndex|defaultFocus|accessibility' entry/src/main/ets

# 8. 安全区和键盘策略
rg -n --glob '*.ets' 'statusBarHeight|AvoidArea|drawableRect|KeyboardAvoidMode|expandSafeArea' entry/src/main/ets

# 9. 资源变体
Get-ChildItem -Directory -Recurse entry/src/main/resources | Select-Object -ExpandProperty FullName

# 10. 多端测试与截图基线
rg -n 'phone|tablet|2in1|fold|breakpoint|screenshot|windowSize' entry/src/test entry/src/ohosTest docs/agents/smoke-test.md
```

人工复核项：

- [ ] 每个 `on` 有同一实例上的 `off`，页面多次进入不会重复监听。
- [ ] 页面没有读取设备型号决定布局。
- [ ] 断点切换不创建新的 ViewModel、DAO、Dispatcher 或 Order。
- [ ] SM/MD/LG/XL 都有明确导航、列数、浮层和内容宽度。
- [ ] 文本、公式、图片和按钮在 1.5x 字体及长中文下不裁切。
- [ ] 所有自绘可点击组件有焦点、键盘、读屏和触控路径。
- [ ] Fold crease 与 avoid area 不覆盖主操作。
- [ ] 窗口缩放期间无崩溃、闪白、状态清空或重复网络请求。
- [ ] 截图回归同时覆盖空数据、少量数据、长列表和长公式。
- [ ] `node scripts/arkts-lint/index.mjs --quiet` 与 hvigor build 全绿。

## 16. 官方一手资料

> 在线页面由华为动态文档站提供；精确版本事实同时以 §1.2 列出的 API 24 SDK 声明为准。

- [H1：一次开发，多端部署概览 - HarmonyOS 指南][H1]
- [H2：ArkUI 布局开发概览][H2]
- [H3：自适应布局][H3]
- [H4：响应式布局][H4]
- [H5：GridRow / GridCol API Reference][H5]
- [H6：Navigation API Reference][H6]
- [H7：UIContext API Reference][H7]
- [H8：SideBarContainer API Reference][H8]
- [H9：mediaquery API Reference][H9]
- [H10：Window API Reference][H10]
- [H11：资源分类与访问][H11]
- [H12：通用事件 API Reference][H12]
- [H13：Display API Reference][H13]
- [H14：Navigation 开发指南][H14]

[H1]: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/introduction-to-one-time-development-for-multi-device-deployment
[H2]: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-layout-development-overview
[H3]: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-layout-development-adaptive-layout
[H4]: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-layout-development-responsive-layout
[H5]: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-gridrow
[H6]: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-navigation
[H7]: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-arkui-uicontext
[H8]: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-sidebarcontainer
[H9]: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-mediaquery
[H10]: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-window
[H11]: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/resource-categories-and-access
[H12]: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-events-touch
[H13]: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-display
[H14]: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-navigation-navigation

## 17. 下一步

本报告是决策输入，不是实施 Spec。拷问与 SM/MD/LG/XL 应用壳原型已完成；最终裁决及布局 module 的 interface、seam 和所有权见 [`../architecture/window-layout-strategy-2026-09-08.md`](../architecture/window-layout-strategy-2026-09-08.md)。下一阶段进入 `/to-spec`，再按 blocker-first 顺序 `/to-tickets`；不要直接按本报告章节机械拆 Issue。

## 18. 核实记录 (2026-09-08)

按本报告的 Evidence policy 对本机 SDK 与仓库源码做了一轮逐条核实，结论：**全部既有事实成立，无错误条目**；本轮的增量是补充了原文未写出的细节（已合入对应小节）。

### 18.1 SDK 事实核对（`<DevEco-SDK>` = DevEco Studio 安装目录 `sdk/default`）

| 声明 | SDK 证据 | 结论 |
|---|---|---|
| §1.2 SDK 基线 6.1.1.125 / API 24 / Release | `sdk/default/sdk-pkg.json` | ✅ |
| §4.1 Width/HeightBreakpoint 阈值 | `component/enums.d.ts:10364-10511`（since 13, crossplatform since 22） | ✅ |
| §4.2 各监听 since | `@ohos.arkui.UIContext.d.ts:4798/4816`、`UIObserver.on/off` 位于同文件 `:2282/:2295`（class `UIObserver` `:1632`，经 `getUIObserver()` `:4141` 获取——**注意事件属于 UIObserver 而非 UIContext**，已由原型编译实测确认）、`@ohos.window.d.ts:5414`（since 7）、`@ohos.mediaquery.d.ts:343`（`@deprecated since 18`, `@useinstead` UIContext.MediaQuery#matchMediaSync） | ✅（已修正: 事件挂 UIObserver） |
| §4.3 `drawableRect` | `@ohos.window.d.ts:1443`（since 11） | ✅ |
| §5 `AUTO_WITH_ASPECT_RATIO` | `component/navigation.d.ts:303`（since 24, `@stagemodelonly`） | ✅（规则细节见 §6.4） |
| §5 `minContentWidth` | `component/navigation.d.ts:2678`（since 10, 默认 360vp, Auto=240+360） | ✅ |
| §5 `SideBarContainerType.AUTO` | `component/sidebar.d.ts:101`（since 10） | ✅ |
| §5 GridRow 断点两套系统 / API 20 columns 默认 | `component/grid_row.d.ts:525/1000` + 官方指南"栅格布局 (GridRow/GridCol)" | ✅（已补 §5 注意段） |
| §8 输入事件 since | `component/common.d.ts`：onTouch/onKeyEvent 7、onHover/onMouse/focusable 8、tabIndex 9、tabStop 14、nextFocus 18 | ✅（tabStop/nextFocus 已补 §8 表） |
| §9 折叠 API since | `@ohos.display.d.ts:298-608` | ✅ |
| §10 `Tabs.vertical`/`barPosition` | `component/tabs.d.ts:1117/1145`（since 7 / 9） | ✅ |
| §10 `ContainerReader` 不可用 | 官方指南：API 26.0.0 起 | ✅（已补 §10 表） |

### 18.2 仓库事实核对（代码行号以核实当日 HEAD 为准）

| 声明 | 代码证据 | 结论 |
|---|---|---|
| §2/§11 deviceTypes | `entry/src/main/module.json5:7-11` phone/tablet/2in1 | ✅ |
| §12.1 EntryAbility 状态栏只读一次 | `entryability/EntryAbility.ets:61-62`（onWindowStageCreate 内一次性 `AppStorage.setOrCreate('statusBarHeight', …)`，无任何窗口事件监听） | ✅ |
| §12.1 Index 五 Tab + 74vp 底栏 + NONE | `pages/Index.ets:31,47,65,77`；`common/.../ColorTokens.ets:207` `TAB_BAR_HEIGHT=74` | ✅ |
| §12.1 TabBar 仅底部 Row | `pages/MainTabs/TabBar.ets:42-70` | ✅ |
| §12.1 SubjectGrid 一/两列 | `pages/Notes/SubjectGrid.ets:50`（"1fr" / "1fr 1fr"） | ✅ |
| §12.1 NotesList 全量 ForEach | `pages/Notes/NotesList.ets:29-31`（`List()` + `ForEach`，无 `LazyForEach`） | ✅ |
| §12.1 HomeRecentNotes 单列 ForEach | `pages/Home/HomeRecentNotes.ets:53` | ✅ |
| §12.1 浮窗 bottom sheet + SCREEN_H + 74 | `overlays/AgentFloatWindow/AgentFloatWindow.ets:245,268` | ✅ |
| §12.1 详情确认框 78% | `overlays/NoteDetailOverlay/NoteDetailOverlay.ets:257`（`.width('78%')`） | ✅ |
| §12.1 星系 360x520 基准 | `pages/Review/ReviewGraphView.ets:21-24` + `viewmodels/KnowledgeGalaxyViewModel.ets:700-701,732-733`（该文件 1880 行） | ✅ |
| §7.1 资源仅 base/dark/rawfile | `entry/src/main/resources/` 目录列表 | ✅ |
| §8 输入现状（仅星系局部 onHover） | 全 entry grep：`onHover` 仅 `ReviewGraphView.ets:1395`；无 focusable/tabIndex/onKeyEvent/accessibility | ✅ |
| §8 a11y 审计已存在 | `docs/research/frontend-a11y-audit-2026-09-06.md` 存在 | ✅ |

### 18.3 交叉验证的官方指南（devecocli docs 本地文档库）

- 栅格布局 (GridRow/GridCol)：默认断点 4 档 `["320vp","600vp","840vp"]`、最多 6 档、API 20 columns 默认 `{xs:2,sm:4,md:8,lg:12,xl:12,xxl:12}`。
- Code Linter `@cross-device-app-dev/one-multi-breakpoint-check`：一多特性必须用系统断点判断，禁用设备类型/方向/可折叠判断。
- 容器断点 ContainerReader：API 26 起，不在 API 24 范围。

### 18.4 对后续工作的约束增量

1. **GridRow 默认断点与窗口断点不同档**——凡用 GridRow 做页面栅格，必须先显式配置 5 档 breakpoints 数组，否则 840vp 以上全部是 `lg`（§5 注意段）。
2. **高度信号完整可用**——`getWindowHeightBreakpoint()` 与事件回调的 `heightBreakpoint` 字段都已在 API 24 存在，布局策略接口（§12.2）应宽高成对输出，不应只输出宽度。
3. **不采用 `AUTO_WITH_ASPECT_RATIO`**——其宽高比规则与 MindTrace 已裁决的导航和主从布局语义冲突；正式策略显式输出 Stack/Split，宽度档位是唯一主判据。
4. **tabStop/nextFocus 可作为 2-in-1 焦点增强的可选项**，但不替代基础的 focusable/tabIndex（§8 表）。

### 18.5 原型实测增量

- 独立原型的 `module.json5` 最初只声明 `phone`，安装到平板后被系统放入手机兼容窗口，视觉表现为“平板中间放了一台手机”。补齐 `phone/tablet/2in1` 后，MatePad Pro 13 才按平板全屏窗口运行。正式工程已声明三类设备，但所有测试 harness 也必须保持相同声明。
- API 24 编译实测确认：`windowSizeLayoutBreakpointChange` 必须由 `UIContext.getUIObserver()` 返回的 `UIObserver` 注册和注销，不能直接调用 `UIContext.on/off`。
- SM 壳层的内容区若使用 `height('100%')` 会把 74vp 底栏挤出可视区；应用壳必须用剩余空间布局（如 `layoutWeight(1)`），将导航占位纳入结构而不是覆盖内容。
- XL 学科卡片四列视觉过密，用户确认保持现有一列列表/两列卡片选择；全局布局策略不应输出或接管 `subjectColumns`。
- 折叠屏专有能力延期：本轮不接入 `isFoldable`、折叠监听或折痕避让，折叠设备仅按普通可变窗口处理。
