# 前端体检后续待办合同 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Status:** 待办合同 — 等补充资料后逐项执行, 当前**不动任何代码**
> **Source**: [`frontend-component-audit-2026-09-06.md`](./frontend-component-audit-2026-09-06.md) 分层裁决 + [`frontend-ui-design-inventory-2026-09-06.md`](./frontend-ui-design-inventory-2026-09-06.md) 三维档案 + HTML 升级版报告(`architecture-review-20260906-225531-upgrade.html`)

---

## 0. 体检结论速读 (TL;DR)

| 轴 | 判定 | 证据 |
|---|---|---|
| spec 012 分层 | 骨架合规 ≈75% | 2 硬违例 (MathTextRenderer 假原子 / MathPreviewText atom→atom) + overlays 43 组件规范真空 |
| React 理念 | 数据流高度符合 (单向下/受控), 组件理念 3 处偏离 (index-key ×3 / AppStorage 手工总线 ×6 / 胖容器) | grep + 实读 |
| 设计/动效 | 静态半边健康, 动态半边半接入 | animateTo 5 文件 (3 令牌合规, 2 绕过), 111 处字面量 |
| 死令牌 | LH_HEADING / SUCCESS / WARNING 真死 | 96 文件 + common 侧零消费者 |
| OcrNode 断链 | **已修复** (b60f491, TDD 绿) | agents module, 未 push |

---

## 1. 待办矩阵 (7 项候选, 按强度 + 触发条件排序)

> 符号: ✅已落地 / ⏸待资料 / 🔒锁定需裁决 / 🚫驳回不动

### ✅ C0 · OcrNode payload 断链修复 (已完成)
- **位置**: `bugfix/ocrnode-payload-break` (73c84cb 红 + b60f491 绿)
- **触发**: 交接文档 §2 真机未验 TBD
- **状态**: TDD 已转绿, hvigor assembleHsp BUILD SUCCESSFUL, lint 0 error, 待 push + 真机验收

---

### ⏸ C1 · MathTextRenderer 重分层 + 缓存/调度外移
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

### ⏸ C2 · 公式样式 profile 四态收口为 style-policy module
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

### ⏸ C7 · MotionPolicy 动效收口 (Strong · 升级版新加)
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

### ⏸ C3 · ReviewGraphView 1880 行拆 5 个内部模块
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

### ⏸ C4 · AppStorage 'notesVersion' 手工总线 → @StorageProp 响应式
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

### ⏸ C5 · IconButton 原子上收 + MathPreviewText 升分子
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

### 🚫 C6 · AiSettings 九子件上收
- **Strength**: Speculative
- **驳回原因**: 无第二个消费者, YAGNI
- **触发条件 (重审)**: 出现第二个设置类页面时再开
- **状态**: 锁定不碰, 未来 review 反复重提时直接看本文

---

## 2. 死令牌裁决 (随 audit #1 doc expiry)

| 令牌 | 状态 | 处理 |
|---|---|---|
| LH_HEADING (行高 30) | 真死 (entry+common 零消费者) | 🔒 随 audit #1 决议删或保留 (有 PR 偏好可提前拍板) |
| SUCCESS (=MINT) | 真死 (语义色 alias) | 🔒 同上, 评估是否真有"成功态"未上色 |
| WARNING (琥珀) | 真死 (ConfidenceDot 用了字面量绕过) | 🔒 建议保留: 未来加警告 toast 可用; 或先删后补 |
| SUBJECT_COLORS / TYPE_COLORS | **假死** (经 NoteTaxonomy 包装) | 不动 |

---

## 3. PR 推送顺序建议 (按风险/收益排序)

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

## 4. 待补充的资料 (触发全部 PR 的输入)

> 这些资料不到位, 任何 PR 都不开工 (除 C0 已落地)

1. **真机验收 C0**: 按 [demo-script-2026-09-06.md §2 步骤 3](../../agents/demo-script-2026-09-06.md) 走一遍"AI 对话→笔记入库"
2. **动效设计裁决**: C7 的呼吸周期 + ReviewGraphView 时长迁移 + 按压反馈 scope (见 §1 C7 触发条件)
3. **API 兼容性检查**: C4 的 @StorageProp 在 API 24 (HarmonyOS 6.1.1) 的官方 d.ts 行为
4. **spec 012 收口计划**: C1 + C2 + C5 是一组 spec 012 后续 PR (PR1-PR3?), 给出顺序与边界
5. **(可选) 重审现有浮层组件目录规则**: overlays 43 组件规范真空是否要补 spec 012 §Layering rules

---

## 5. 不在体检范围 (避免跑题)

- 服务交互 (AiService / AgentChatService 等): 本次体检刻意排除, 由 spec 007 AgentChatService 拆分独立处理
- 后端 CaptureGraph / Dispatcher 业务流: 已落 D2 (spec 011), 不重复扫
- 测试覆盖率: 70 单元测试 + Hypium 行为测试, 不再扩
- 命名规范: naming-lint 0 违反, OK

---

## 6. 文件清单 (现状, 不动)

- `docs/research/frontend-component-audit-2026-09-06.md` — 叙述 + 体检裁决 + 补充 2
- `docs/research/frontend-ui-design-inventory-2026-09-06.md` — 三维档案
- `agents/src/test/CaptureTextFlow.test.ets` — OcrNode 回归守门 (已绿, 待真机验)
- HTML 体检报告 ×2 (临时目录, 不入库)

---

## Last updated

2026-09-06 晚 — 体检合同就位, 等补充资料后逐项执行。
