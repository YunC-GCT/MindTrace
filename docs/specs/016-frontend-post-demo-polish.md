# Spec 016 — 评审后前端改造方案 (Post-demo polish)

> **Status**: spec ready (评审后开始, 2026-09-06 后)
> **Date**: 2026-09-06
> **Source**: [frontend-ui-design-inventory-2026-09-06.md](../research/frontend-ui-design-inventory-2026-09-06.md) §2-3 + [frontend-i18n-audit-2026-09-06.md](../research/frontend-i18n-audit-2026-09-06.md) §6-7 + [frontend-a11y-audit-2026-09-06.md](../research/frontend-a11y-audit-2026-09-06.md) §6 + [frontend-performance-audit-2026-09-06.md](../research/frontend-performance-audit-2026-09-06.md) §8 + [frontend-healthcheck-plan-2026-09-06.md](../research/frontend-healthcheck-plan-2026-09-06.md) C1-C7 + [frontend-error-handling-2026-09-06.md](../research/frontend-error-handling-2026-09-06.md) §6
> **Scope**: MindTrace entry 前端评审后 (W6+ 复赛尾声 / 决赛筹备) 改造。聚焦"评委走查/真用户"必看的体验闭环, **不重做架构**。
> **ADR 来源**: 复用 ADR-0008 (CaptureGraph 自建运行时) · ADR-0009 (Kit 接缝) · ADR-0010 (mcp/tools) · ADR-0011 (skill) · ADR-0012 (tool-calling)。**不立新 ADR**, 与既有决策保持一致。
> **Out of scope**: 服务交互层 (AiService / AgentChatService 拆分走 spec 007) · 后端 CaptureGraph 改造 · Kit 深度集成 · 新功能

---

## Why this ticket

评审 demo 前 (W6 之前) 已经做过 4 项评审前最低修复 (commit 44b3e57 + 2bf85b2): 5 条英文 Toast → 中文 + 22 条 Strings 抽取 + "保存失败：" 冒号去掉 + AppError/ErrorBus/ErrorBanner 错误分级骨架。**这些是字面打磨 + 骨架**; 真要提升到 "产品级" 还差很远。复赛尾声/决赛筹备窗口, 改造目标 = **闭环节点 (评审 demo 已通过验证的 UX) + 长尾项 (评审 demo 不会查的 a11y / 性能上限)**, 不重做架构。

体检背景 (评审后待办, 优先级):
- **C7 MotionPolicy 动效收口** (Strong): 5 文件动效 (3 令牌合规 + 2 绕过), ReviewGraphView ×8 硬编码 180-240ms, GradientRing setInterval 手摇帧
- **C1 MathTextRenderer 重分层** (Strong): 假原子, 缓存/调度埋在 536 行 struct
- **C5 IconButton 原子上收** (Worth exploring): 4+ 处 AppIcon+圆底 重复
- **i18n 骨架扩展** (评审前 PR #60 已铺基础): 70 处 Text() 中文字面量待抽出, 启动 en/ 目录
- **a11y 接入** (体检 ✗ 全空): accessibilityGroup/Text/Description/tabIndex/fontScale 全部 0 引用
- **Suspense/skeleton 接入**: HomePage / ReviewGraphView 全量加载无骨架

不做 (按价值/收益判断):
- **架构重构** (spec 012 后续 PR C1/C2/C5 留在 AGENTS.md 待办合同, 不插队)
- **新功能** (例如: 富文本编辑器、AI 自动出题、学科推荐系统 — 走需求/产品线, 不在本 spec)
- **后端改造** (CaptureGraph / Dispatcher / LlmClient 已落 D2, 稳定)

---

## What we will build

按 ROI 排 3 个 Phase, 每个 Phase 是 1-2 个独立 PR, 每个 PR 独立可回滚:

### Phase 1 · MotionPolicy 动效收口 + spec 012 同批次收口
**目标**: 评委 demo 必看的微交互闭环 + MathTextRenderer 重分层

1. **PR-A: MotionPolicy 收口 (C7 候选)** — `common/.../motion/MotionPolicy.ets`
   - 单一入口 `MotionPolicy.animateToMotion(name, opts?)` 替代散落各文件的 `animateTo({duration: xxx, curve: yyy}, ...)`
   - name 枚举 ↔ DUR_* + Curve 唯一映射 (含 HexLogo / HomePage / AgentFloatWindow 已合规的 3 文件)
   - ReviewGraphView ×8 硬编码 180-240ms → 迁令牌 (裁决: 180→DUR_INSTANT=80 / 220→DUR_FAST=150 / 240→DUR_BASE=250, 接近但不等于)
   - 渐变圆钮补按压反馈 (FloatingButton scale 0.96 / AiTabButton shadow 收缩 / HexLogo 触摸涟漪)
   - 呼吸周期裁决: GradientRing 1500ms vs ColorTokens:174 DUR_BREATH=3000 — 选 3000 (与令牌一致, 评审更易解释)

2. **PR-B: MathTextRenderer 重分层 (C1 候选)** — `shared/atoms/MathTextRenderer.ets` (536 行) → 拆 3 文件
   - `shared/atoms/MathTextRenderer.ets` (薄 adapter ~200 行, 仅 normalize+调度+web 应用)
   - `shared/.../render/RenderCache.ets` (LRU + 哈希, Node 守门可测纯逻辑)
   - `shared/.../render/DeferScheduler.ets` (note profile 分槽延迟)
   - 行为零变化, 三个直连消费者 (MathPreviewText/FormulaSplitRenderer/MarkdownRenderer) 零改动
   - 消除 UiCacheDebug 内部模块导入违例

3. **PR-C: IconButton 原子上收 (C5 候选)** — `shared/atoms/IconButton.ets`
   - 统一 AppIcon+圆底 模式, NoteIconButton/NoteCloseButton/CameraAlbumBtn/CameraBackBtn/CameraCloseBtn/ProfileMenuItemRow 6 处替换
   - MathPreviewText 同步升分子 (atoms→molecules), 守门测试守住 spec 012 atom 零内部依赖

### Phase 2 · i18n 骨架扩展 + ErrorBanner 业务迁移
**目标**: 真正多语言准备 + 评审 demo 失败体验闭环

4. **PR-D: i18n 骨架扩展** — en/ 目录 + ResourceManager 接入
   - `entry/src/main/resources/en/element/string.json` (英文版 70 处 Text + 25 toast + 5 权限文案)
   - `common/.../i18n/Strings.ets` 改用 `$r('app.string.xxx').id` + `getStringSync(context, id)`
   - 守门: 编译期检查 string.json 完整性 (中英对齐)
   - LlmConfig / OcrConfig endpoint 文案也走 i18n

5. **PR-E: ErrorBanner 业务迁移** — 25 处 catch 错误点批量改 ErrorBus
   - 网络错 / LLM 错 / OCR 错 / IO 错 按 frontend-error-handling §6.1 ErrorKind 分类
   - 错误分级 (info/warn/error) + Retry/Jump 按钮 + 接入 router
   - 已有 Toast 保留 (操作反馈) + ErrorBanner (长错误), 分工明确
   - 评审前 1.5 项 (PR #60) 留的 handleAction 占位 → 接到对应 router

### Phase 3 · 长尾: a11y + Suspense + 性能上限
**目标**: 评委一般不查, 但作为产品级收口, 复赛尾声或决赛筹备做

6. **PR-F: a11y 接入** — AppIcon/NoteCard/NoteCloseButton/TextInput/TabBar 五类加 accessibilityGroup/Text/Description
   - 屏幕阅读器 (TalkBack / VoiceOver) 适配
   - 字号系统: F_XS / F_SM / F_BASE 硬值 → fp 系统自动缩放 (或 vp + onConfigurationUpdate)
   - TEXT_5 新增修对比度 (TEXT_4 3:1 → ≥4.5:1)

7. **PR-G: Suspense / skeleton 接入** — HomePage / ReviewGraphView / AgentFloatWindow 加载长任务时
   - `loadingBuilder` ArkUI 机制 (官方推荐)
   - KnowledgeGalaxyViewModel.build() 异步化 (TaskPool)

8. **PR-H: 性能上限** — Webview 实例池 + 列表虚拟化收口
   - `MathWebviewPool` 单例, acquire/release 限制 ≤3 并发 (NotesList/HomeRecentNotes → LazyForEach)
   - 大笔记库场景 (100+/500+ 条) 启动优化

---

## Public surface change

每个 PR 严格限制影响范围 (评审后改造不动公共面契约):

| PR | 公共面变化 | 破坏性 |
|---|---|---|
| PR-A (MotionPolicy) | 无 — 内部新增 module, 业务调用可选迁 | 无 |
| PR-B (MathTextRenderer 重分层) | shared/atoms/MathTextRenderer.ets 接口 (12 prop) **不变**; 子模块新增在 `shared/.../render/` | 无 |
| PR-C (IconButton) | shared/atoms/IconButton.ets 新增; 6 处替换是组件实例化而非接口 | 无 |
| PR-D (i18n) | common/.../i18n/Strings.ts 字段不变 (硬编码中文); 新增 en 资源 + 加载机制 (默认 base/zh) | 无 |
| PR-E (ErrorBanner 业务) | ErrorBus 已有; 调用方加 publish 调用 | 无 |
| PR-F (a11y) | shared 组件 prop 不变 (accessibilityText 是可选); 仅在 default value 加 | 无 |
| PR-G (Suspense) | 无 — 框架机制, 不动组件接口 | 无 |
| PR-H (性能) | 无 — 内部 LRU/pool 改造 | 无 |

---

## Migration

按 PR 顺序, 每个独立 PR = 1 分支 + 1 commit (尽量) + 1 PR:
- **branch 命名**: `polish/motion-policy` · `polish/mathtextrenderer-split` · `polish/iconbutton-up` · `polish/i18n-en-skeleton` · `polish/errorbus-migrate` · `polish/a11y-basics` · `polish/suspense-skeleton` · `polish/perf-headroom`
- **每个 PR 单独 review + merge**, 不串行
- 评审后**第一周做 PR-A/B/C** (动效闭环, 演示升级)
- 评审后**第二周做 PR-D/E** (i18n 骨架 + 错误体验)
- 评审后**第三周起做 PR-F/G/H** (长尾, 慢工出细活)

---

## Test plan (TDD)

每个 PR 都按现有守门链:
- **Node 单元测试** (scripts/arkts-lint 套件): AST 形状 / 公开 API / 错误分类
- **Hypium 行为测试** (common/test/ 或 agents/test/ 或 shared/test/): 组件行为, 评审后建议补
- **hvigor BUILD SUCCESSFUL** (common + entry 双模块)
- **lint 0 error** (baseline WARN + 新组件可接受 +2)
- **naming-lint OK** / **link-check 0 新增**

PR-A/B/C 重点 (动效相关):
- MotionPolicy.animateToMotion(name) 的 name 枚举覆盖测试 (DUR_INSTANT/FAST/BASE/SLOW/SLOWER/SLOWEST 6 档)
- MathTextRenderer 重分层后: 渲染一致性 (同输入产出同输出), LRU 行为 (Node 测)
- IconButton 6 处替换后视觉一致 (snap diff 或注释核对)

PR-D/E 重点 (i18n + 错误):
- ResourceManager.getStringSync 在 zh/en 切换时正确返回
- ErrorBus.publish 25 处迁移后, 触发条件全部覆盖 (mock Test 验证 ErrorKind 与原 catch 一致)

PR-F/G/H 重点 (长尾):
- accessibilityGroup 5 类组件属性扫描测试 (AST 级别)
- 字号缩放测试: F_BASE=14 在 fontScale=1.5 时实际 21 fp
- WebviewPool 并发上限: mock 7 个 Webview 请求, 只 3 个并发

---

## Reversibility

每个 PR 独立可回滚:
- 8 个独立分支, 单 PR merge 单 commit (或 1-2 原子 commit)
- 评审 demo 期间任一 PR 出问题: `git revert <sha>` 单点回滚
- 评审 demo 已 merge 的 PR 保留 (产品级沉淀, 决赛可继续)

不引入新 ADRs / 不重命名现有契约 / 不删除现有公共面导出 → 难度极低。

---

## Acceptance criteria

每个 PR 必须:
- [ ] lint 0 error
- [ ] hvigor common + entry 共 BUILD SUCCESSFUL ≤ 60s
- [ ] node 守门 70/70 (新测试可加, 不破坏旧)
- [ ] naming-lint OK / link-check 0 新增
- [ ] Hypium 测试覆盖新组件/新模块关键路径
- [ ] 至少 1 个 commit 含 "fix:" 或 "feat:" 前缀
- [ ] commit message 含触发条件 + 收口判据 + 风险

Phase 整体收口 (评审后 3-4 周):
- [ ] Phase 1-3 全部 PR 合入 develop
- [ ] frontend-i18n-audit §6 三色对比度全部达标 (新 TEXT_5)
- [ ] frontend-a11y-audit §1 a11y API 引用 > 0
- [ ] frontend-performance-audit §1 LazyForEach 使用 ≥ 6 处
- [ ] frontend-error-handling §1 ErrorBus 业务迁移 ≥ 25 处

---

## Sequence (concrete commit list)

| # | 阶段 | PR | commit 前缀 | 估时 |
|---|---|---|---|---|
| 1 | Phase 1 | PR-A MotionPolicy 收口 | `feat(common):` + `refactor(entry):` | 1.5 天 |
| 2 | Phase 1 | PR-B MathTextRenderer 重分层 | `refactor(shared):` | 1 天 |
| 3 | Phase 1 | PR-C IconButton 上收 | `refactor(shared):` + `refactor(entry):` | 0.5 天 |
| 4 | Phase 2 | PR-D i18n 骨架扩展 | `feat(common):` + `feat(entry):` | 1.5 天 |
| 5 | Phase 2 | PR-E ErrorBanner 业务迁移 | `refactor(entry):` | 1 天 |
| 6 | Phase 3 | PR-F a11y 接入 | `feat(shared):` + `feat(entry):` | 2 天 |
| 7 | Phase 3 | PR-G Suspense/skeleton | `feat(entry):` | 1.5 天 |
| 8 | Phase 3 | PR-H 性能上限 | `feat(shared):` + `refactor(entry):` | 1 天 |

总计 ~10 天评审后改造 (1 人 2 周工作量)。

---

## Out of scope

**明确不做** (评审后改造不是这些):
- 服务交互层改造 (走 spec 007 AgentChatService 拆分)
- 后端 CaptureGraph / Dispatcher 重构 (D2 已稳定)
- Kit 深度集成 (BackgroundTask/FormCard facade, 走 spec 013 后续)
- 新功能 (富文本编辑器 / AI 自动出题 / 学科推荐 — 走产品需求)
- 国际化全文案翻译 (PR-D 仅启动 en/ 骨架, 实际翻译走产品决策)
- 多主题 (浅色模式等) — a11y 调整字号时顺路扩, 不单独立项
- 测试覆盖补全 (a11y/性能/E2E) — 与 F/G/H 同步走, 不单独

**评审前不动** (评审 demo 之后再开干):
- 8 个 PR 中**任一个**在评审前 commit 都是污染
- 分支命名 `polish/*` 区别于 `fix/demo-polish-2026-09-06` (评审前打磨)

---

## Cross-references

- 评审前 4 项最低修复: PR #58 (OcrNode 修复) + PR #59 (docs 摸底) + PR #60 (i18n+ErrorBanner) — 本 spec 不重复
- 待办合同 [frontend-healthcheck-plan-2026-09-06.md](../research/frontend-healthcheck-plan-2026-09-06.md) §1 C1/C5/C7 已正式纳入 Phase 1
- 三件套 [frontend-a11y-audit](../research/frontend-a11y-audit-2026-09-06.md) §6 与 [frontend-error-handling-2026-09-06.md](../research/frontend-error-handling-2026-09-06.md) §6 与 [frontend-performance-audit-2026-09-06.md](../research/frontend-performance-audit-2026-09-06.md) §8 提供 Phase 2-3 完整清单
- AGENTS.md "读哪" 表新增的 "改 entry UI 设计/动效/token" 指针会指向本 spec (评审后 PR 启动时)

---

## Last updated

2026-09-06 — 评审前规划完成, 评审后开干。
