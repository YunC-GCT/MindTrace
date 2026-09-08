# MindTrace issue 盘点与取舍教程 - 2026-09-07

> **目的**: 读完项目现状、开放 GitHub Issues、本地 specs/tickets 后，判断哪些 issue 是正确的、值得做的、应该先做什么。
> **结论先行**: 现在最值得做的是 **#62 真机验收并关闭**、**#65/#66/#67 前端 Phase 1 三个小 PR**、以及 **AgentChatService PR3 补 issue**。#68/#69 需要先确认被依赖的 PR #60 没有合入这件事。#73/#74 是赛后/决赛功能，不适合复赛窗口直接开工。

## 1. 本次怎么读的

### 1.1 先读项目入口

按项目规则，任何新 session 先看:

1. [`AGENTS.md`](../../AGENTS.md): 红线、当前状态、必读指针。
2. [`CONTEXT.md`](../../CONTEXT.md): MindTrace 专用术语，尤其是 `Order`、`KnowledgeUnit`、`CaptureGraph`、`Sub-agent`。
3. [`docs/agents/issue-tracker.md`](../agents/issue-tracker.md): issue 来源是 GitHub Issues，PR 不作为 triage 面。
4. [`docs/agents/triage-labels.md`](../agents/triage-labels.md): 标签映射就是 `needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`。

### 1.2 再读当前进度

主要进度源:

- [`docs/specs/index.md`](../specs/index.md): specs 总索引和剩余项。
- [`docs/agents/handoff-2026-09-06.md`](../agents/handoff-2026-09-06.md): 2026-09-06 交接，尤其是真机待验事项。
- [`docs/research/frontend-healthcheck-plan-2026-09-06.md`](./frontend-healthcheck-plan-2026-09-06.md): 前端体检后的候选清单。
- [`docs/research/frontend-component-audit-2026-09-06.md`](./frontend-component-audit-2026-09-06.md): 组件分层证据。
- [`docs/research/frontend-ui-design-inventory-2026-09-06.md`](./frontend-ui-design-inventory-2026-09-06.md): 动效、令牌、组件三维盘点。
- [`docs/research/frontend-a11y-audit-2026-09-06.md`](./frontend-a11y-audit-2026-09-06.md): 无障碍证据。
- [`docs/research/frontend-error-handling-2026-09-06.md`](./frontend-error-handling-2026-09-06.md): 错误提示证据。
- [`docs/research/frontend-performance-audit-2026-09-06.md`](./frontend-performance-audit-2026-09-06.md): 性能证据。

### 1.3 最后对照代码和 GitHub

本机没有 `gh` CLI，所以本次用 GitHub REST API 读取开放 issues。读取到 13 个开放 issue: #62 到 #74，以及 #11。

另外核对了关键 PR:

| PR | 状态 | 对判断的影响 |
|---|---|---|
| #58 OcrNode payload 修复 | closed 且 merged 到 `develop` | #62 不应再做代码修复，只需要真机验收后关闭 |
| #60 评审前最低修复包 | closed 但未 merged | #68/#69 提到的 i18n/ErrorBanner 骨架不能当作已在 `develop` 存在 |
| #77 LLM config / AssetStoreKit / SSE 修复 | closed 且 merged 到 `develop` | 本地 LLM 设置 tickets 的 PR0/PR1 类事项已经落地 |

## 2. 判断标准

本次把每个 issue 放进 5 个桶:

| 桶 | 含义 | 下一步 |
|---|---|---|
| 立刻值得做 | 代码/文档证据充分，边界清楚，风险可控 | 开分支实现或验收 |
| 值得做但先补信息 | 方向对，但依赖、spec、设计裁决不完整 | 先补 issue/spec，再实现 |
| 赛后再做 | 价值真实，但不是复赛窗口目标 | 保留，不抢当前优先级 |
| 应关闭或改成索引 | 已完成、重复、或只是总览 | 验证后关闭，避免污染 backlog |
| 需要补 issue | 本地文档有待办，但 GitHub 没有对应开放 issue | 新建真正可执行 issue |

一个 issue 值得做，至少要满足三点:

1. 能指出为什么现在有问题。
2. 能指出改哪些文件或哪一层。
3. 能写出验收标准。

如果只写了愿望，没有边界和验收，就先放 `needs-info`。

## 3. 总推荐顺序

### 第 0 步: 先把 backlog 清干净

1. **#62**: 真机按 demo 走完后关闭。
2. **#64**: 修正 spec 链接/编号，或者改成 umbrella tracking issue。
3. **#63**: 已经被 #64 和 #65-#72 细分吸收，建议关闭或改成资料索引。
4. **补一个新 issue**: `AgentChatService PR3: ReplyService 抽出 + facade 收口`。

### 第 1 步: 前端 Phase 1，最值得做

推荐顺序:

1. **#67 IconButton + MathPreviewText**: 小、快、风险最低。
2. **#65 MotionPolicy**: 评审观感收益明显，证据充分。
3. **#66 MathTextRenderer 重分层**: 架构收益高，但触碰核心渲染，放在 #67 后更稳。

### 第 2 步: 体验/质量项

1. **#69 ErrorBanner 迁移**: 先确认 #60 未合入后的真实基线，再做。
2. **#68 i18n 扩展**: 同样先确认基础字符串抽取是否已在当前分支存在。
3. **#70 a11y**: 正确且值得做，但评审前收益较弱，赛后产品化优先。

### 第 3 步: 性能长尾

1. **#71 Suspense / skeleton**
2. **#72 WebviewPool + LazyForEach**

这两个都值得做，但建议等 Phase 1 和错误/i18n 基础稳定后再碰。

### 第 4 步: 赛后/决赛功能

1. **#73 错题本自动归档**
2. **#74 学习计划自动生成**

它们都有用户价值，但需要产品裁决、数据模型迁移和真实使用路径验证，不建议在复赛收口阶段直接开工。

## 4. 逐 issue 判断

### #62 OcrNode payload 断链修复

- 链接: <https://github.com/YunC-GCT/MindTrace/issues/62>
- 标签: `bug`, `needs-triage`, `P0`
- 判断: **正确，但代码已修完**
- 推荐状态: `ready-for-human`
- 是否值得做: **值得做，但不是继续写代码，是做真机验收并关闭**

证据:

- PR #58 已 merged 到 `develop`。
- 当前代码中 [`agents/src/main/ets/graph/AgentState.ets`](../../agents/src/main/ets/graph/AgentState.ets) 已有 `payload?: DispatchPayload`。
- 当前 [`agents/src/main/ets/graph/nodes/OcrNode.ets`](../../agents/src/main/ets/graph/nodes/OcrNode.ets) 已从 `input.payload` 调 `recognizeText`，缺失时返回 `CAPTURE_NO_PAYLOAD`。
- [`docs/agents/handoff-2026-09-06.md`](../agents/handoff-2026-09-06.md) 明确唯一待定验证是“AI 对话 → 笔记真实入库，真机未验”。

保姆级下一步:

1. 用 DevEco Studio 跑 `entry`。
2. 启动 OCR 服务，按 [`docs/agents/demo-script-2026-09-06.md`](../agents/demo-script-2026-09-06.md) 的主流程走一遍。
3. 拍照或输入题目，让 AI 生成笔记。
4. 确认最近笔记列表出现新笔记。
5. 重启 app，确认笔记仍在。
6. 如果通过，在 GitHub #62 留验收记录并关闭。

### #63 前端摸底 9 件套落地

- 链接: <https://github.com/YunC-GCT/MindTrace/issues/63>
- 标签: `needs-triage`, `P1`, `docs`
- 判断: **内容正确，但已经不是可执行 issue**
- 推荐状态: `wontfix` 或关闭为“已拆分”
- 是否值得做: **不建议作为实现任务继续做**

证据:

- 相关研究文档已经存在，包括 `frontend-*.md` 多份体检文档。
- 后续行动已经被 #64 和 #65-#72 拆开。

保姆级下一步:

1. 不要从 #63 直接开代码分支。
2. 在 #63 评论说明“已被 #64 和 #65-#72 吸收”。
3. 关闭 #63，或者把它改成前端摸底资料索引。

### #64 spec 016 评审后前端改造方案

- 链接: <https://github.com/YunC-GCT/MindTrace/issues/64>
- 标签: `enhancement`, `needs-triage`, `P1`
- 判断: **方向正确，但引用的 spec 有明显问题**
- 推荐状态: `needs-info`
- 是否值得做: **值得保留为总控 issue，但先修文档链接**

关键问题:

- issue 写的是 `docs/specs/016-frontend-post-demo-polish.md`。
- 当前仓库没有这个文件。
- 当前存在的 [`docs/specs/016-llm-settings-redesign.md`](../specs/016-llm-settings-redesign.md) 是 LLM 设置页重构，不是前端评审后打磨。

保姆级下一步:

1. 先决定: 是新建 `docs/specs/017-frontend-post-demo-polish.md`，还是把前端方案只放在 #64 body。
2. 如果新建 spec，更新 [`docs/specs/index.md`](../specs/index.md)。
3. 在 #65-#72 的正文里把 `docs/specs/016 §2` 改成正确 spec。
4. #64 保留为 umbrella，不直接写代码。

### #65 MotionPolicy 动效收口

- 链接: <https://github.com/YunC-GCT/MindTrace/issues/65>
- 标签: `enhancement`, `ready-for-agent`, `P1`
- 判断: **正确，值得做**
- 推荐状态: `ready-for-agent`
- 是否值得做: **高优先级**

证据:

- [`docs/research/frontend-ui-design-inventory-2026-09-06.md`](./frontend-ui-design-inventory-2026-09-06.md) 指出动效令牌半接入。
- 当前 [`entry/src/main/ets/pages/Review/ReviewGraphView.ets`](../../entry/src/main/ets/pages/Review/ReviewGraphView.ets) 存在多处 `animateTo({ duration: 180/220/240 })` 硬编码。
- [`common/src/main/ets/constants/ColorTokens.ets`](../../common/src/main/ets/constants/ColorTokens.ets) 已有 `DUR_FAST` / `DUR_BASE` / `DUR_BREATH` 等令牌。

保姆级下一步:

1. 从 `develop` 新建 `polish/motion-policy`。
2. 新增 `common/src/main/ets/motion/MotionPolicy.ets`。
3. 先写结构守门测试: 不允许 `ReviewGraphView` 继续出现硬编码 `duration: 180/220/240`。
4. 把 ReviewGraphView 迁到 MotionPolicy。
5. 把 GradientRing 呼吸周期统一到裁决值。
6. 给 FloatingButton / AiTabButton / HexLogo 补按压反馈。
7. 跑 lint 和相关 Node 测试。

### #66 MathTextRenderer 重分层

- 链接: <https://github.com/YunC-GCT/MindTrace/issues/66>
- 标签: `ready-for-agent`, `P1`, `refactor`
- 判断: **正确，值得做**
- 推荐状态: `ready-for-agent`
- 是否值得做: **高优先级，但要小心**

证据:

- [`docs/research/frontend-component-audit-2026-09-06.md`](./frontend-component-audit-2026-09-06.md) 明确 `MathTextRenderer` 是“名为原子、实为最重组件”。
- 当前 [`entry/src/main/ets/shared/atoms/MathTextRenderer.ets`](../../entry/src/main/ets/shared/atoms/MathTextRenderer.ets) 仍在 atoms 下，并持有 WebviewController、缓存、调度、高度估算等多种职责。
- 它被 MarkdownRenderer、FormulaSplitRenderer、MathPreviewText 间接铺满全 UI，改动价值高但风险也高。

保姆级下一步:

1. 先不要改调用方行为。
2. 先抽纯逻辑: `RenderCache` 和 `DeferScheduler`。
3. 给缓存 key、LRU、调度策略补 Node 测试。
4. 保持 MathTextRenderer 的入参不变。
5. 跑渲染相关单元测试和 lint。
6. 最后只做文件位置/层级收口，不混入视觉改版。

### #67 IconButton 原子上收 + MathPreviewText 升分子

- 链接: <https://github.com/YunC-GCT/MindTrace/issues/67>
- 标签: `ready-for-agent`, `P1`, `refactor`
- 判断: **正确，最适合先做**
- 推荐状态: `ready-for-agent`
- 是否值得做: **高优先级，低风险**

证据:

- 当前有多个局部按钮重复组合 AppIcon，例如 `NoteIconButton`、相机按钮、关闭按钮。
- 当前 [`entry/src/main/ets/shared/atoms/MathPreviewText.ets`](../../entry/src/main/ets/shared/atoms/MathPreviewText.ets) 组合了 `MathTextRenderer`，按 spec 012 不应继续留在 atom。

保姆级下一步:

1. 新建 `entry/src/main/ets/shared/atoms/IconButton.ets`。
2. 先替换最小一处，例如 NoteDetailOverlay 的按钮。
3. 再逐步替换相机按钮/ProfileMenuItemRow。
4. 用 `git mv` 把 `MathPreviewText.ets` 移到 `shared/molecules/`。
5. 更新 import。
6. 加结构测试: atom 不允许 import sibling atom 组成复杂组件。

### #68 i18n 骨架扩展

- 链接: <https://github.com/YunC-GCT/MindTrace/issues/68>
- 标签: `enhancement`, `ready-for-agent`, `P2`
- 判断: **方向正确，但当前基线需要重核**
- 推荐状态: `needs-info`
- 是否值得做: **值得做，但不要直接按 issue body 开工**

原因:

- issue 依赖“PR #60 已铺基础”。
- PR #60 实际 closed 但未 merged。
- 当前代码搜索没有看到 `ResourceManager` / `getStringSync` 这类基础实现。

保姆级下一步:

1. 先确认 PR #60 为什么关闭未合入。
2. 如果 PR #60 被放弃，就把 #68 拆成两个 PR: i18n 最小骨架、英文资源补齐。
3. 不要一口气改 70 处 Text 和 25 处 toast，先做 1 个页面试点。
4. 补中英 string key 对齐检查。

### #69 ErrorBanner 业务迁移

- 链接: <https://github.com/YunC-GCT/MindTrace/issues/69>
- 标签: `ready-for-agent`, `P1`, `refactor`
- 判断: **方向正确，但当前基线需要重核**
- 推荐状态: `needs-info`
- 是否值得做: **值得做，但要先补骨架或修正文案**

原因:

- issue 同样依赖“PR #60 已铺 AppError/ErrorBus/ErrorBanner 骨架”。
- PR #60 未合入。
- 当前代码搜索只在研究文档中看到 `AppError` / `ErrorBus` / `ErrorBanner`，没看到实现落在 `common/` 或 `entry/`。

保姆级下一步:

1. 先新建或恢复最小错误骨架: `AppError`、`ErrorBus`、`ErrorBanner`。
2. 只迁移 3-5 个最关键 catch 验证交互。
3. 再分批迁移剩余 catch。
4. Toast 保留为短反馈，ErrorBanner 只承载长错误和可重试错误。

### #70 a11y 接入 5 类组件

- 链接: <https://github.com/YunC-GCT/MindTrace/issues/70>
- 标签: `enhancement`, `ready-for-agent`, `P2`
- 判断: **正确，值得做**
- 推荐状态: `ready-for-agent`
- 是否值得做: **中高优先级，偏赛后产品化**

证据:

- [`docs/research/frontend-a11y-audit-2026-09-06.md`](./frontend-a11y-audit-2026-09-06.md) 指出 `accessibilityGroup` / `accessibilityText` / `accessibilityDescription` 等几乎为空。
- 这是完整产品必须补的基础能力。

保姆级下一步:

1. 先做 AppIcon、NoteCard、TabBar 三类高复用组件。
2. 每个组件补 `accessibilityText` 和必要描述。
3. 同步修对比度 token，不要只堆描述文本。
4. 真机打开屏幕阅读器走查。

### #71 Suspense / skeleton 接入

- 链接: <https://github.com/YunC-GCT/MindTrace/issues/71>
- 标签: `enhancement`, `ready-for-agent`, `P2`
- 判断: **正确，值得做，但排在 Phase 1 后**
- 推荐状态: `ready-for-agent`
- 是否值得做: **中优先级**

证据:

- [`docs/research/frontend-performance-audit-2026-09-06.md`](./frontend-performance-audit-2026-09-06.md) 指出 KnowledgeGalaxyViewModel.build 和部分页面加载存在长任务风险。
- skeleton 是体验补强，不是当前最紧急结构问题。

保姆级下一步:

1. 先选一个最慢页面做试点: ReviewGraphView。
2. 把 `KnowledgeGalaxyViewModel.build()` 异步化。
3. 加 skeleton/loadingBuilder。
4. 再扩到 HomePage / AgentFloatWindow。

### #72 WebviewPool + LazyForEach 收口

- 链接: <https://github.com/YunC-GCT/MindTrace/issues/72>
- 标签: `ready-for-agent`, `P2`, `refactor`
- 判断: **正确，值得做，但属于性能长尾**
- 推荐状态: `ready-for-agent`
- 是否值得做: **中优先级**

证据:

- [`docs/research/frontend-performance-audit-2026-09-06.md`](./frontend-performance-audit-2026-09-06.md) 指出 `LazyForEach` 覆盖不完整，Webview 实例无硬上限。
- 当前 `NotesList` / `HomeRecentNotes` 仍使用 `ForEach`。
- 当前 `MathTextRenderer` 每个 struct 持有自己的 WebviewController。

保姆级下一步:

1. 先把 `NotesList` 改为 LazyForEach，复用 `SubjectNoteList` 的 IDataSource 思路。
2. 再处理 `HomeRecentNotes`。
3. WebviewPool 先做接口和上限策略，不要同时重写渲染协议。
4. 用 100+/500+ 笔记场景做手动性能验收。

### #73 新功能 N2: 错题本自动归档

- 链接: <https://github.com/YunC-GCT/MindTrace/issues/73>
- 标签: `enhancement`, `needs-info`, `P3`
- 判断: **方向有价值，但现在信息不足**
- 推荐状态: `needs-info`
- 是否值得做: **赛后/决赛再做**

需要补的问题:

1. “答错”从哪里来: 用户手动标记、复习结果、AI 判断，还是题目练习系统?
2. `KnowledgeUnit.status` 是否要和现有 `ReviewStatus` 合并，还是另建字段?
3. RDB schema v5 migration 怎么保证旧数据兼容?
4. 错题本是新 Tab、Notes 过滤器，还是 Review 的一个视图?

### #74 新功能 N3: 学习计划自动生成

- 链接: <https://github.com/YunC-GCT/MindTrace/issues/74>
- 标签: `enhancement`, `needs-info`, `P3`
- 判断: **方向有价值，但依赖 #73**
- 推荐状态: `needs-info`
- 是否值得做: **赛后/决赛再做**

原因:

- issue 自己写了前置: N2 错题本。
- StudyPlanService 已有 LLM 接入是好基础，但“30 天复习计划”的产品规则还没定。

需要补的问题:

1. 输入只有考试日期和学科，还是还要输入每天可学时长?
2. 计划按 KnowledgeUnit、章节、难度，还是错题优先?
3. 生成失败时是否允许本地规则 fallback?
4. 与现有 ReviewPlanView 是复用还是替换?

### #11 D4 Kit 替换边界

- 链接: <https://github.com/YunC-GCT/MindTrace/issues/11>
- 标签: 无
- 判断: **历史决策 issue，已经大部分落地**
- 推荐状态: `needs-triage`
- 是否值得做: **不建议直接做代码；先决定是否关闭或拆子 issue**

证据:

- [`docs/specs/013-kit-adoption-boundary.md`](../specs/013-kit-adoption-boundary.md) 显示 P0 facade 契约已落地，ReminderFacadeImpl 已实现并注入。
- #11 评论说明 UI 入口暂缓，BackgroundTask / FormCard 实现延后。

保姆级下一步:

1. 给 #11 补标签: `enhancement` + `needs-triage` 或 `ready-for-human`。
2. 如果复赛已结束，决定是否拆: BackgroundTaskFacade 实装、FormCardFacade 实装、Reminder UI 入口解锁。
3. 如果暂时不做，保留为 open 也可以，但要在 body 顶部写“当前不作为 agent-ready 实现任务”。

## 5. GitHub 外的本地待办

### AgentChatService PR3 需要补 GitHub issue

本地 [`docs/specs/007-agent-chat-service-decomposition.md`](../specs/007-agent-chat-service-decomposition.md) 显示:

- PR1 `IntentClassifier` 已落地。
- PR2 `ChatStatusMachine` 已落地。
- PR3 `ReplyService` 抽出仍 pending。

但 GitHub `#7` 实际是已关闭 PR，不是这个 ticket。因此建议新建 issue:

```text
标题: AgentChatService PR3: ReplyService 抽出 + facade 收口
标签: refactor, ready-for-agent, P1
正文: 引用 docs/specs/007-agent-chat-service-decomposition.md 的 PR3 段落。
验收:
- AgentChatService.ets 收到薄 facade
- 新增 ReplyService.ets
- 现有 public surface 不变
- Node 结构守门和 Hypium 计划补齐
```

这是当前 backlog 里**比 #68-#72 更偏架构主线**的一项，建议排在 #65-#67 之后、性能长尾之前。

### LLM 设置 tickets 的状态

本地 `docs/agents/tickets/llm-settings/` 有 4 个票据:

| 票据 | 当前判断 |
|---|---|
| `pr0-fix-pro-model.md` | 已落地: `normalizeModel` 已允许 `DEFAULT_MODEL` 本身 |
| `pr1-asset-store-kit-upgrade.md` | 已落地: `ApiKeyVault` 已存在，`LlmConfig` 已委托 |
| `pr2-t1-llm-config-data.md` | 未落地: 没看到 `providers.ets` |
| `pr2-t2-ui-redesign.md` | 未落地: 没看到 `VendorPicker` / `CustomVendorForm` |

注意:

- 当前 [`common/src/main/ets/llm/LlmConfig.ets`](../../common/src/main/ets/llm/LlmConfig.ets) 的 `DEFAULT_MODEL` 仍是 `deepseek-v4-pro`。
- [`docs/specs/016-llm-settings-redesign.md`](../specs/016-llm-settings-redesign.md) 内部存在自相矛盾: 前文说 `PRO_MODEL → deepseek-chat`，后面的 providers 示例又写 DeepSeek 默认 `deepseek-v4-pro`。
- 这块建议单独做一次 spec 校准，不要和 #64-#72 的前端打磨混在一起。

## 6. 最终分组清单

### 立刻值得做

| Issue | 标题 | 建议 |
|---|---|---|
| #62 | OcrNode payload 断链修复 | 真机验收后关闭 |
| #67 | IconButton 原子上收 + MathPreviewText 升分子 | 低风险先做 |
| #65 | MotionPolicy 动效收口 | 高收益，Phase 1 |
| #66 | MathTextRenderer 重分层 | 高收益，高谨慎 |

### 值得做但先补信息

| Issue | 标题 | 缺什么 |
|---|---|---|
| #64 | 前端改造总方案 | spec 文件缺失/编号冲突 |
| #68 | i18n 骨架扩展 | PR #60 未合入，需重核基线 |
| #69 | ErrorBanner 迁移 | PR #60 未合入，需先补骨架 |
| #11 | D4 Kit 替换边界 | 已落地部分需写清，剩余拆子 issue |

### 赛后/产品化再做

| Issue | 标题 | 原因 |
|---|---|---|
| #70 | a11y 接入 5 类组件 | 正确，但偏产品化 |
| #71 | Suspense / skeleton | 正确，但排在结构收口后 |
| #72 | WebviewPool + LazyForEach | 正确，但属于性能长尾 |
| #73 | 错题本自动归档 | 需要产品裁决和 schema migration |
| #74 | 学习计划自动生成 | 依赖 #73，且产品规则未定 |

### 建议关闭或转索引

| Issue | 标题 | 建议 |
|---|---|---|
| #63 | 前端摸底 9 件套落地 | 已被细分 issue 吸收，关闭或转资料索引 |

### 建议新建

| 新 issue | 来源 | 为什么 |
|---|---|---|
| AgentChatService PR3: ReplyService 抽出 + facade 收口 | `docs/specs/007-agent-chat-service-decomposition.md` | 本地 spec 有 pending，但 GitHub 没有对应开放 issue |

## 7. 给新手的执行模板

每次拿一个 issue，照这个顺序走:

1. 打开 issue，复制标题、标签、正文、链接。
2. 搜 issue 里提到的 spec/research 文件是否真的存在。
3. 搜 issue 里提到的目标代码是否真的存在。
4. 看它是不是已经被 PR 合入。
5. 判断它属于 bug、enhancement、docs、refactor 还是决策 issue。
6. 判断它现在应该是 `ready-for-agent`、`needs-info`、`ready-for-human` 或 `wontfix`。
7. 如果要做代码，先建分支，先写测试，再改实现。
8. 如果只是验证或关闭 issue，写清证据，不要假装做了新功能。

## 8. 最小行动清单

如果今天只做 5 件事:

1. 真机验收 #62，通过后关闭。
2. 修 #64 的 spec 链接/编号问题。
3. 关闭或转索引 #63。
4. 新建 AgentChatService PR3 issue。
5. 从 #67 开始做前端 Phase 1。

## Last updated

2026-09-07
