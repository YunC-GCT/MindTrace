# MindTrace · 数学学习助手

> 工程: [YunC-GCT/MindTrace](https://github.com/YunC-GCT/MindTrace) · HarmonyOS 数学学习助手
> 作者: YunC-GCT <2549237929@qq.com> · 当前主笔: Z
> 当前版本: **v1.0**(2026-09-04 release) · 阶段: **复赛冲刺**(2026-09-05 ~ 09-09)
> 最近更新: 2026-09-13

MindTrace 通过 **拍照 → OCR → AI 分类 → 知识结构化 → 持久化 → 复习** 的整链,把"看到的数学题"变成"可复习的知识"。5 module: `entry`(HAP) + `common` / `agents` / `skill` / `cardservice`(HSP)。

---

## 一、初赛阶段 (2026-07 ~ 09-01) · 谁做了什么

> 逐日完整日志已收敛至 `docs/legacy/` 与 git 历史; 本节按时间线保留分工与关键交付的技术要点。

#### W0 · 工程搭建 (07-12)

**团队**: 5 module HarmonyOS 脚手架(entry HAP + 4 HSP), 5/5 编译通过(`bfaa8e5`)。

#### W1 · 公共层 + UI 骨架 (07-13 ~ 14) — Z / center 合并

- **Z**: 公共层五件套(CommonTypes 共享类型、logger、uuid、timeWindow、confidenceSort, merge `d6220c4`); 5 Tab 装配 + 沉浸式状态栏; HomePage(Hero/进度环/FAB)、CameraOverlay、AgentFloatWindow(已接真实 LLM)、NoteDetailOverlay。
- **center 合并**(`53b09c0`): AiSettingsPage(端点/模型/Key/参数/测试连接); LlmConfig `saveAll`/`loadAll` preferences 持久化; DeepSeek V4(`deepseek-v4-pro`)全 Agent 接入。
- **CameraPicker**(`9db3309` 等): 系统相机 `cameraPicker.pick()`(免 CAMERA 运行时申请)+ 后置镜头枚举 + 相册入口; module.json5 声明 CAMERA/INTERNET。

#### D1 拍照链 · OCR 接入 (07-13 ~ 15) — D / L

- 精简拍照链 8 文件骨架建好, build 验证后由 D/L 填真实现。
- **L**(`babdba8`): OcrTool 改 HarmonyOS `http.request` + 手动 multipart(HarmonyOS 沙箱兼容, `multiFormDataList` 不可用), 默认端点 `127.0.0.1:8000`; 合并 OCR 文本 + LaTeX 公式; TypeClassifier 调 DeepSeek 分类、失败降级本地规则。

#### Z 端 refactor · pages 重组 + MVP 合并 (07-17, `81a6ef6`)

- 6 个单文件 page 重组为"每页一文件夹 + 子组件"(Home/Profile/Notes/StudyPlan/AiSettings 等)。
- KnowledgeModel 等 `*MVP.ets` 合并进正式类(KnowledgeModel 644 行), 旧实验移入 archive; 15 个配套 commit(聊天气泡加固/删除接入/进度环/学习计划行交互等)。

#### ✨ 整链接入 (07-17, `5b6f155`)

Index.ets `onCameraConfirm` 调 `AiService.capture(uri)`——拍照 → ImageUriResolver 沙箱化 → Dispatcher → TypeClassifier(OCR+分类) → KnowledgeModel.structure(结构化+真值检验) → NoteDao.insert → Toast。W0 以来最关键一步, 全链从此可跑。

#### W3 · 渲染协议与数据层 (07-19 ~ 22) — Z

- **MM-MD-v1 渲染协议**: AI/OCR/历史三源统一走 ContentProtocol 归一化 + 风险校验 → Markdown 解析 → KaTeX 只编译确认公式; 无公式气泡走原生渲染不建 WebView; 协议失败显示原文不空白; 显示与入库同一份归一化结果。
- **ContentExcerptBuilder**: 列表摘要按公式边界安全截断(不切 `$...$` 内部), 新笔记 summary 约 220 字。
- **长正文按需加载**: 列表只查元数据; 详情 LRU 8 条/512KB; 二阶段 List+LazyForEach(首挂 3 节点, "继续阅读"追加); 超长段落在公式边界外安全切块。
- **subject/category 字段独立**(7 文件链路: CommonTypes/KnowledgeUnitExt/NoteDao/NoteItemMapper/DatabaseHelper 等), 旧数据缺列兼容(补列不迁移 + tags 兜底推断)。
- 纯文字生成笔记刷新链路(notesVersion 版本号驱动三页自动刷新); Review 页合并 StudyPlan; Notes 页"概览统计 + 学科入口"重设计。

#### W4 · 多 WebView 分块渲染 (07-23 ~ 24) — Z

- 解决 ArkUI WebView **1800vp 高度上限**(超限全空白): FormulaSplitRenderer 按 `$$` 拆块 + 合并相邻文本(WebView 数 -40%) + LazyForEach/IDataSource 仅可见块持有实例 + block 硬上限 30 + 超长段落段落边界二次拆分。
- `renderFormula` bridge 跳过全 DOM 扫描直接 `katex.renderToString`, 公式块快 30-50% 且无高度上限; 4 处 UTF-8 乱码修复; MathTextParser 支持 `$...$`/`$$...$$`/`\(...\)`/`\[...\]` 四定界符混排。
- 方案与调研存档: [formula-split-render-plan-2026-07-24](./docs/legacy/mindtrace/plans/w4/formula-split-render-plan-2026-07-24.md)。

#### 09-01 · 审计 + 工程化 — Z

- **全库架构审计**: 21 项 finding(P0/P1/P2)+ 7 大文件深读, 存档 [audit-full-2026-09-01](./docs/legacy/mindtrace/architecture/audit-full-2026-09-01.md)——后续所有 ADR/spec 的源头。
- **arkts-lint 双轨制**: v1 regex(25 规则)+ v0.3 AST(34 规则 + 63 单元测试), GitHub Actions 三 job CI 守门; 规则手册 [arkts-1.1.md](./docs/style/arkts-1.1.md)。

#### 09-04 · v1.0 release — YunC-GCT

v1.0 打 tag 发布; 3 人 Git Flow 团队手册、CODEOWNERS 三 owner 路由、main/develop 分支保护 rulesets。

---

## 二、初赛期结构快照 (2026-07-20 · 供对比)

> 复赛 D3(2026-09-06)已将组件层规范为 `shared/{atoms,molecules,organisms}`, `components/` / `prototypes/` / `archive/` 相继退役。以下为初赛期快照, 保留供对比; 现行结构以 [AGENTS.md](./AGENTS.md)「关键架构」为准。

```text
entry/src/main/ets/
├── pages/                              # 每个 page 一个子文件夹
│   ├── Index.ets                       # 主容器: 5 Tab + 全局浮层 + 整链触发
│   ├── Home/                           # 首页(拆 3 个组件)
│   │   ├── HomePage.ets
│   │   ├── HomeTopBar.ets
│   │   └── HomeRecentNotes.ets
│   ├── Notes/                          # 笔记页: 一级学科总览 + 二级学科笔记列表
│   │   ├── NotesPage.ets
│   │   ├── NotesHeader.ets
│   │   ├── NotesList.ets
│   │   ├── NotesSummaryPanel.ets
│   │   ├── SubjectGrid.ets
│   │   ├── SubjectCard.ets
│   │   ├── SubjectViewToggle.ets
│   │   ├── SubjectDetailPage.ets
│   │   ├── SubjectHeader.ets
│   │   ├── SubjectNoteList.ets
│   │   ├── SubjectTypeEmpty.ets
│   │   ├── TypeTabRow.ets
│   │   └── NotesEmptyState.ets
│   ├── Profile/                        # 我的(原 MePage, 拆 5 个组件)
│   │   ├── ProfilePage.ets
│   │   ├── ProfileHeader.ets
│   │   ├── ProfileStatsRow.ets
│   │   ├── ProfileMenuList.ets
│   │   └── ProfileMenuItemRow.ets
│   ├── Review/                         # 复习
│   │   └── ReviewPage.ets
│   ├── StudyPlan/                      # 学习计划(拆 4 个组件)
│   │   ├── StudyPlanPage.ets
│   │   ├── PlanHeader.ets
│   │   ├── PlanInputBar.ets
│   │   ├── PlanListView.ets
│   │   └── PlanStatsBar.ets
│   └── AiSettings/                     # AI 设置(拆 6 个组件)
│       ├── AiSettingsPage.ets
│       ├── ActionBar.ets
│       ├── ConnectionStatus.ets
│       ├── EndpointPicker.ets
│       ├── KeyInput.ets
│       ├── ModelPicker.ets
│       └── SectionHeader.ets
├── overlays/                           # 顶层浮层(被 Index 引用)
│   ├── AgentFloatWindow.ets            # 真实 LLM 对话
│   ├── CameraOverlay.ets               # 真实 cameraPicker
│   └── NoteDetailOverlay.ets           # 5 子组件拆分
├── prototypes/                         # 独立完整的页面级 UI 原型(后退役)
│   ├── AgentFloatWindow.ets
│   ├── CameraOverlay.ets
│   ├── NoteDetailOverlay.ets
│   ├── AgentMessageList.ets
│   ├── NoteDetailOverlay/              # 5 个子组件
│   └── chat/                           # AI 浮窗 8 个子组件
│       ├── ChatBubble.ets
│       ├── ChatHeader.ets
│       ├── ChatModels.ets
│       ├── ChatSession.ets
│       ├── ChatTextSanitizer.ets
│       ├── EmptyStateHint.ets
│       ├── MessageInput.ets
│       ├── QuickSuggestions.ets
│       ├── SessionBar.ets
│       └── TypingIndicator.ets
├── components/                          # 旧 atom 命名(已废弃)
│   └── HexLogo.ets
├── atoms/                               # 16 个原子组件
│   ├── AiTabButton / AppIcon / CameraAlbumBtn / CameraBackBtn
│   ├── CameraCloseBtn / CameraConfirmBtn / CameraShutterBtn
│   ├── ConfBadge / FloatingButton / GradientRing
│   ├── HexLogo / PageHeader / PriorityBadge / StatsBox
│   ├── TabButton / ViewfinderCorners
├── molecules/                           # 7 个分子组件
│   ├── CameraCapture.ets
│   ├── CameraPreview.ets
│   ├── HeroBanner.ets
│   ├── NoteCard.ets
│   ├── PlanItemRow.ets
│   ├── ReminderBanner.ets
│   └── TabBar.ets
├── database/                            # RDB 数据访问
│   ├── DatabaseHelper.ets               # RDB 封装
│   ├── NoteDao.ets                      # 完整 CRUD
│   └── StudyPlanDao.ets                 # 学习计划 DAO
├── viewmodels/
│   └── StudyPlanViewModel.ets           # MVVM
├── services/
│   ├── ApiClient.ets                    # HTTP 客户端
│   ├── AiService.ets                    # 整链入口
│   └── ImageUriResolver.ets             # file:// URI 沙箱化
└── utils/
    └── NoteItemMapper.ets               # NoteItem ↔ KnowledgeUnit

common/src/main/ets/
├── models/                              # 共享类型(KnowledgeUnit + 5 个 enum)
├── constants/                           # ColorTokens / 字号 / 间距
├── tools/                               # logger / uuid / timeWindow / confidenceSort
├── data/                                # MockNotes
└── llm/                                 # LlmConfig + LlmClient(OpenAI 兼容)

agents/src/main/ets/
├── agents/
│   ├── TypeClassifier.ets               # OCR + DeepSeek 分类
│   └── KnowledgeModel.ets               # AI 结构化 + 真值检验
├── core/
│   └── Dispatcher.ets                   # 精简链调度
└── mcp/tools/
    └── OcrTool.ets                      # 本地 FastAPI HTTP
```

---

## 三、复赛冲刺 (2026-09-05 起) · 谁做了什么

> **更新策略**(沿初赛冲刺惯例): 冲刺期间本节按日期追加, 每条 ≤ 1 屏; 更早条目压缩进初赛节或 `docs/legacy/`。架构决策落 [`docs/adr/`](./docs/adr/index.md), 实施计划落 [`docs/specs/`](./docs/specs/index.md)。复赛期由 YunC-GCT 主导方向与裁决, **AI 结对多会话并行**实施。

### 2026-09-05 · Day 1

- **YunC-GCT**: v1.0 release; Git Flow 团队手册 + 分支保护 rulesets。
- **AI 结对**: D2 spec 011 落地——Dispatcher 单入口 + **CaptureGraph**(LangGraph 设计模型的 ArkTS 原生承载, ADR-0008): 节点 capture→classify→structure→truth_check→persist(条件边), AI 失败显式报错不造假笔记; Node 守门测试体系建立。

### 2026-09-06 · Day 2 (多会话并行)

- **YunC-GCT**: 全部方向裁决(Kit 延后→F3 最小闭环、命名裁决、UI 暂不动); 全量 Hypium 真机验证。
- **治理与文档 (主会话)**: 治理刷新(specs/ADR 状态全量同步); **README 维护本页**; 全仓工具清点 + 演示脚本 + 交接报告; 双轴审查(笔记入库链路确认无损)与硬伤清理。累计 **12 ADR + 11 spec**。
- **拆分收口 (主会话, spec 015)**: KnowledgeModel 878 行 god class → **554 行轻量编排 agent**(名字经裁决保留), 拆出 PromptBuilder(提示词 49 行)与 TruthCheckService(真值检查 283 行); 全程纯提取, 字节级 diff 证据存 PR #40/#41。
- **LLM 工具化 (并行会话, spec 014)**: `call(request)` 单一调用入口(真 SSE); 工具调用协议 + ToolRegistry + ToolLoop 落地 `common/src/main/ets/tools/`; **F1 P1 只读工具**(note_query 等)实现。
- **其他 (并行会话)**: spec 007 PR1 IntentClassifier 自 AgentChatService 抽出; 全仓 agent 工具清点报告。

### 2026-09-06 · entry 层 (主会话)

- **F2 小步先修**: StudyPlan AI 生成抽到 `services/StudyPlanService`(ViewModel 回归 UI 状态层)。
- **F3 Kit 接线**: `kit/ReminderFacadeImpl`(reminderAgentManager 日历提醒)实现并组合根注入; UI 入口按裁决暂不挂, 守门反向锁定。
- 双轴审查结论: **笔记入库链路无损**(持久化关键文件零触碰)。

### 2026-09-09 · LLM 设置页重构 (spec 017 / ticket #83)

- **多供应商配置**: AI 设置页支持 DeepSeek / 通义千问 / 智谱 GLM / Kimi / 豆包与自定义供应商; 每个供应商独立维护 API Key 与模型目录。
- **折叠编辑**: 点击供应商右侧「编辑」展开本地草稿;「取消」丢弃草稿,「保存」提交当前供应商 key/models 并执行 LLM-only 持久化; 模型输入支持回车与 `+` 添加。
- **持久化与调用链**: `LlmConfig` 持久化 vendorId / customVendors / vendorModels / activeVendorModels / vendorApiKeys; `LlmClient` 按当前 vendor 解析 endpoint、model 与 key; 自定义供应商 id 跨重启保持稳定。

### 2026-09-10 · Agent 工作流架构重构 (spec 018)

- **整体 LangGraph 设计**: ArkTS 原生 `StateGraph<State, Step>` 统一承载 Capture、ToolCalling、Conversation、SkillIntent 四个领域 workflow；不是 Python/langgraphjs runtime，也不是多后端。
- **原链路修复**: 修复 TruthCheckNode 丢 KnowledgeUnit、TruthCheck 通过语义反向/失败仍入库、PersistNode 覆盖分类与难度、payload source 丢失；最终 KnowledgeUnit 原样进入唯一 DAO adapter。
- **入口收敛**: `Dispatcher.dispatch(req, options)` 是 Capture 唯一入口；`AgentChatService` 收敛为 UI facade，业务只在 `ConversationWorkflow`；ToolLoop 删除旧 while 后委托 ToolCalling workflow。
- **鸿蒙能力**: BackgroundTasksKit 短时任务、FormKit 卡片刷新与 GSKV 跨进程 snapshot 已接线；卡片固定 mock 删除；skill SearchNote 复用唯一 `note_query` 工具面。
- **职责分离**: per-vendor 面板负责保存大模型配置; 页面底部 ActionBar 仅负责「重置 OCR / 保存 OCR」; 顶部连接测试读取当前供应商的 API Key。
- **模型目录**: DeepSeek 默认模型为 `deepseek-v4-pro`; 当前允许 `deepseek-v4-flash`、`deepseek-v4-pro`、`deepseek-v4-flash-vision-exp`,模型选择按供应商独立保存。
- **真实 LLM 验证**: 连接测试与悬浮对话已在设备完成真实 DeepSeek 调用;日志确认 `deepseek-v4-flash` 分别走非流式与 SSE 流式请求且 HTTP 200。请求日志只打印 vendor / model / endpoint / stream,不输出 API Key。

### 2026-09-13 · AI 对话推理流收口 (#111 / #113 / #115)

- **结构化推理流**: `StreamEvent` 统一承载 thinking/text 通道;思考内容进入独立「深度思考」区块,最终回答不再混入推理文本。
- **交互验收**: 思考区默认展开,支持独立折叠;流式增长保持展开态;折叠不会强制聊天列表滚到底部;状态文案为「生成中」/「已完成」。
- **截断降级**: 供应商返回 `finish_reason=length` 时,流式与非流式均保留已生成内容并追加截断提示,不再抛出或静默丢失回复。
- **验证结果**: `arkts_check`、arkts-lint、naming-lint、Hypium 测试与 `assembleApp` 均通过;本组改动已整理到 `feature/spec-019-p0` 分支。

### 2026-09-13 · Chat 网络流容错热修复

- **请求容错**: 修复 HarmonyOS `requestInStream` 错误回调中状态码为空导致的 `toString` 崩溃;网络/DNS/超时错误统一映射为稳定的网络失败提示。
- **流式恢复**: 首个事件到达前的网络失败最多重试一次;流式占位消息在失败时复用并结束,不再遗留「MindTrace AI 正在生成」。
- **回复一致性**: 流式空响应的 fallback 复用 JSON 校验与 Reply Body 解码,避免将 `{"answer": ...}` envelope 直接展示给用户。
- **验证结果**: `arkts_check`、arkts-lint 96/96、naming-lint、debug build 均通过;设备对话验证正常。

---

## 四、工程化与质量

| 项 | 现状 |
|---|---|
| 编译 | 5/5 module BUILD SUCCESSFUL(DevEco GUI 或 hvigor CLI 均可) |
| ArkTS 守门 | 自研 AST lint(34 规则, CI 三 job)+ naming-lint + link-check |
| 测试 | Node 测试套件(数量以 `npm --prefix scripts/arkts-lint test` 输出为准)+ Hypium(TruthCheck 7 / PromptBuilder 2 / CaptureGraph 3, DevEco GUI 执行) |
| 文档守门 | link-check 全库死链清零; ADR/spec 状态列随实现 PR 同步(团队手册 PR 检查单) |

---

## 五、构建与运行

```bash
# 1. OCR 服务 (Windows PC)
tools/ocr_service/start.bat          # 端口 8000; 真机需在 App 内把 endpoint 改为 PC 局域网 IP

# 2. 构建/运行
DevEco Studio: Build → Build Hap(s)/APP(s), Run → Run 'entry'
# 或 hvigor CLI (AI 可主动调用; 环境变量见 docs/agents/d2-capturegraph-teaching-2026-09-05.md §6.11)

# 3. LLM 配置
App 内 我的 → AI 设置:
1. 选择预设供应商或添加自定义供应商
2. 点「编辑」填写该供应商 API Key、维护模型目录
3. 点面板内「保存」持久化当前供应商配置
4. 点页面顶部「测试」验证当前 vendor / endpoint / model / key 链路

# 当前已知问题
# 若测试连接失败,保留界面错误信息与设备日志;不得把真实 API Key 写入仓库或测试文件。
# 若要确认模型切换,查看设备日志中的 [LlmClient] request vendor=... model=... stream=...

# 4. 提交前验证
node --test "scripts/arkts-lint/tests/*.test.mjs"  # 284 passed
node scripts/naming-lint/index.mjs                  # 0 violations
# DevEco / hvigor: BUILD SUCCESSFUL
```

完整演示流程(5 分钟 8 步)、失败降级口径、赛前检查清单见 [docs/agents/demo-script-2026-09-06.md](./docs/agents/demo-script-2026-09-06.md)。

---

## 六、资料定位 (文档地图)

| 要找什么 | 去哪 |
|---|---|
| Agent 工作入口(红线 + 必读指针) | [AGENTS.md](./AGENTS.md) — **第一个必读** |
| 项目词汇表(术语消歧) | [CONTEXT.md](./CONTEXT.md) |
| 全部文档导航 | [docs/index.md](./docs/index.md) |
| 架构决策(why) / 实施计划(how) | `docs/adr/`(12 篇, [索引](./docs/adr/index.md)) · `docs/specs/`(11 篇, [索引](./docs/specs/index.md)) |
| 调研 / 架构体检 / 演示与交接 | `docs/research/` · `docs/architecture/`([工具清点](./docs/architecture/agent-tools-inventory-2026-09-06.md)) · `docs/agents/`(含 [演示脚本](./docs/agents/demo-script-2026-09-06.md) · [交接报告](./docs/agents/handoff-2026-09-06.md)) |
| 编码规范 / 文件头模板 | `docs/style/arkts-1.1.md` · `docs/agents/file-header-template.md` |
| 初赛存档(冻结, 勿新增) | `docs/legacy/`([说明](./docs/legacy/index.md)) |

已舍弃的方案文档(初赛期旧方案原文、archived MVP 清单等)不再于本文件引用; 需要考古走 `docs/legacy/` 与 git 历史。
