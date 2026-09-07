# 前端性能与资源摸底 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Scope:** MindTrace entry 列表虚拟化 / Webview 内存峰值 / 图片懒加载 / 缓存策略
> **方法**: grep `LazyForEach / ForEach / Web / WebviewController / cacheKey`, 全机提取
> **配套**: [`frontend-ui-design-inventory-2026-09-06.md`](./frontend-ui-design-inventory-2026-09-06.md) 三维档案 · [`frontend-persistence-2026-09-06.md`](./frontend-persistence-2026-09-06.md) UiDataCacheService

---

**TL;DR:** 性能是项目**已被部分治理但暗藏峰值风险**的领域 — **LazyForEach 仅 3 处** (AgentMessageList/SubjectNoteList/FormulaSplitRenderer), 31 处 ForEach 未虚拟化 (HomeRecentNotes/NotesList 等); **MathTextRenderer KaTeX Webview 缓存做得好** (LRU 64 条 / TTL 10min, 评审亮点) 但 Webview 实例数上限无强制 — 详情浮层 6 renderer + MarkdownRenderer 7 块 + ChatBubble 同时打开可能引发 7+ 个 Webview; 笔记列表缓存靠 UiDataCacheService 进程级 LRU, **失效机制与 AppStorage 双轨制** (`invalidateNotesSnapshots` vs `notesVersion bump`, 谁触发谁不明)。

---

## 1. 列表虚拟化覆盖

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

## 2. Webview 内存峰值

### 2.1 MathTextRenderer 缓存现状 (亮点)
`shared/atoms/MathTextRenderer.ets`:
- 模块级 LRU: `MATH_RENDER_CACHE` 64 条 / TTL 10 min / 600k chars 上限 (`:44-58`)
- 渲染: 三模式管线 (katex / native / plainFallback), `setTimeout` 分槽延迟 (note profile)
- 缓存键: `profile | version | forceDisplay | contentHash(markdown)`
- **评测亮点**: 这是项目唯一一处"Webview 渲染 + 缓存"组合的成熟实现, 是 W3 公式渲染计划的资产

### 2.2 Webview 实例数峰值风险
| 场景 | Webview 实例数估算 |
|---|---|
| AI 浮窗 1 条消息 | 1 个 (ChatBubble → MarkdownRenderer) |
| AI 浮窗 1 条含公式消息 | N 个 (FormulaSplitRenderer LazyForEach, 每个 block 1 个) |
| 笔记详情 1 屏 | 6 renderer × 1 MarkdownRenderer + DetailSection × N → 7+ 个 |
| 笔记详情 + AI 浮窗后台 | 7 + 1 = 8+ 个 |
| ReviewGraphView (星系页) | 0 个 (纯 Canvas, OK) |
| HomePage 首页 | 0 个 (HeroBanner 自绘, OK) |

**风险点**: 笔记详情 + AI 浮窗同时打开 (评审 demo 常见) → 8+ 个 Webview 在 ArkTS 进程内, **每个 Webview 占用 JS 引擎 + 渲染线程**。HarmonyOS 6.1 单进程 Webview 上限需查 SDK d.ts (常见 6-8 个)。

### 2.3 Webview 内存控制现状
- MathTextRenderer 有模块级 LRU 缓存 (HTML 字符串缓存), 但**Webview 实例本身没有限制** — 每个 MathTextRenderer struct 持有自己的 WebviewController
- 没有"Webview 实例池", 每次 MathTextRenderer 创建就 new 一个 Webview
- aboutToDisappear 时**没有显式销毁 Webview**: 看 `MathTextRenderer.ets:233-235`, 只有 `renderSeq += 1`, WebviewController 由 ArkUI 框架 GC

**判据缺失**: Webview 数上限 + 跨组件共享池 (类似 OkHttp 连接池)

---

## 3. 图片与资源

### 3.1 Image 懒加载
- `Image($r('app.media.ic_xxx'))` 是**资源引用**, ArkUI 内置按需加载, 无需手动懒加载
- `ImagePreviewBar` (AI 浮窗预览图) 用 `imagePreview: string` 持有 uri, 单图
- 相机拍照后 `ImageUriResolver.resolve` 复制到沙箱, 已优化
- **唯一可能 OOM 风险**: 评审 demo 连续拍照 + 多次 AI 浮窗不释放, 沙箱图片累积

### 3.2 字体与外部资源
- `rawfile/katex/fonts/`: KaTeX 字体离线包 (评审亮点, W3 公式计划落地)
- `rawfile/render.html`: KaTeX 渲染页 (440 行), 单文件
- 这两件是 Webview 内加载, 受 Webview 数影响

### 3.3 笔记卡片 MathPreviewText 渲染成本
- `NoteCard` 每张 = MathPreviewText (单行预览) + 渐变图标 + 文本
- MathPreviewText 内部含 MathTextRenderer (有公式时)
- **列表 20 条笔记全含公式** = 20 个 MathTextRenderer 实例 = 20 个潜在 Webview (受 NoteCard 复用策略影响, 滚动时可能复用)

---

## 4. 缓存层盘点 (与 persistence 文档呼应)

### 4.1 模块级缓存
| 缓存 | 位置 | 范围 | 评 |
|---|---|---|---|
| MathTextRenderer LRU | `shared/atoms/MathTextRenderer.ets:44` | 64 条渲染 HTML | ✓ 范本 |
| UiDataCacheService detail | `services/UiDataCacheService.ets:124` | DetailCacheEntry[] | ✓ LRU + trim |
| UiDataCacheService snapshot | UiDataCacheService 内 | 笔记列表快照 | ✓ |
| PreloadQueue | UiDataCacheService | 预加载队列 | △ 与 detailEntries 关系不清 |

### 4.2 失效机制
- **MathTextRenderer**: 缓存键是内容哈希 + profile, 内容变则自动失效
- **UiDataCacheService**: 
  - `invalidateNotesSnapshots()` 静态方法, 显式触发 (AiService.buildNoteDao 后调用一次)
  - 但**触发点 grep 不到完整覆盖**: NotesPage / HomePage / ReviewGraphView 通过 `AppStorage.get<number>('notesVersion')` 监听 (onPageShow 重读)
- **双轨制嫌疑**: in-memory 失效 + AppStorage notesVersion bump 谁触发谁, 路径不清

---

## 5. 长任务 / 同步阻塞

| 位置 | 风险 |
|---|---|
| `KnowledgeGalaxyViewModel:790 行` (数据建模) | onPageShow 时全量计算星系数据, **无后台线程** |
| `HexLogo.ets` animateTo ×3 (DUR_SLOWEST 1200ms ×2) | 主线程串行, 期间无法响应 |
| `MathTextRenderer.ets:226` renderSeq 保护 | ✓ 已有竞态保护 |
| `DatabaseHelper.getStore()` (RDB) | 同步, 入口调用无异步包装, 启动时阻塞 |
| `ChatSession.ets:35` preferences.getPreferences | 异步, 在 aboutToAppear 中调用, 无 await error 处理 |

---

## 6. 启动性能

| 阶段 | 耗时估计 | 优化点 |
|---|---|---|
| EntryAbility.onCreate | ReminderFacade 注入 + 状态栏读取 + 数据库 init | ✓ 已是同步, 无明显问题 |
| pages/Index aboutToAppear | setKeyboardAvoidMode | ✓ 单调用 |
| HomePage onPageShow | loadRecentNotes → read all notes | ⚠ 全量加载, 大笔记库时风险 |
| ReviewGraphView onPageShow | KnowledgeGalaxyViewModel.build() | ⚠ 全量构建, 1880 行渲染组件 |
| AgentFloatWindow aboutToAppear | loadHistory + initKeyboard | ✓ 异步 + 监听 |

---

## 7. 评级

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

## 8. 应有但缺的结构

### 8.1 列表虚拟化清单
- NotesList → LazyForEach (高优先, 长列表风险)
- HomeRecentNotes → LazyForEach (中优先, 笔记多时)
- NotesSummaryPanel / SubjectGrid → List 容器 (中)
- ReviewGraphView 不需要 (Canvas 自绘, 范围固定)

### 8.2 Webview 实例上限 (建议)
- 在 MathTextRenderer 中加**实例池**: `MathWebviewPool` 单例, acquire/release 模式, 限制并发 ≤3
- 或在 NoteDetailOverlay 关闭时主动 `controller.destroy()`
- 查 SDK d.ts: HarmonyOS 6.1 Webview 单进程上限, 是否原生提供

### 8.3 长任务异步化
- KnowledgeGalaxyViewModel.build() 挪到 worker thread (ArkTS TaskPool)
- HexLogo animateTo ×3 拆为更细粒度或加 progress hint

### 8.4 启动分片
- HomePage onPageShow 全量加载改为分页 (前 20 条 + 滚动加载)
- ReviewGraphView 同理

---

## 9. 待补充资料

§12/§13 不变, 新增:
14. **Webview 上限 (HarmonyOS 6.1)**: SDK d.ts 是否有原生限制; 若有, 是否达到
15. **AI 浮窗 + 详情浮窗同开场景**: 真机演示中是否会出现, 决定 Webview 优化的优先级
16. **大笔记库场景 (100+/500+ 笔记)**: 启动 + HomePage 加载是否卡顿

---

## Last updated

2026-09-06 晚
