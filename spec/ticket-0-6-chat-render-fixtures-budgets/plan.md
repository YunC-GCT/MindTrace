# Implementation Plan: Ticket 0.6 Chat Render Fixtures and Budgets

**Input**: Feature specification from `spec/ticket-0-6-chat-render-fixtures-budgets/spec.md`

## Summary

为 spec 021 ticket-0 建立可复现的 chat 渲染基准：定义确定性 A/B/C/C′ fixtures 与冻结的指标定义（`visible`、`T_firstDeltaToVisible`、`finish→visible`、`T_finishToStable`、长帧规则、steady memory、Web create count、height update count），通过临时 harness 页复用生产 `ChatBubble`/`FormulaSplitRenderer`/`MathTextRenderer` 只读渲染，在 MatePad Pro 13 模拟器上每组 ≥20 次采集 p50/p95，并从证据推导 `RendererScheduler` 的 `maxWebCreatesPerFrame`/`maxWebWorkMsPerFrame` 默认值，冻结于新 ADR-0017 并回填 spec 021 §6。测量 seam 是生产渲染器上唯一的代码改动（纯计数+时间戳，零渲染逻辑变更）；harness 观察后删除，零残留。

## Technical Context

**Language/Version**: ArkTS in HarmonyOS Stage model；项目 target/compatible SDK 为 `6.1.1(24)`（`build-profile.json5`），本 ticket 只用 API 24 可用能力（DisplaySync API 11+、hichecker API 9+/11+、hidebug 均可用）。
**Primary Dependencies**: `@kit.ArkGraphics2D`（`displaySync` 帧时间戳）、`@kit.PerformanceAnalysisKit`（`hichecker` 慢事件规则、`hidebug.getAppVMMemoryInfo`、`hilog`）、`@ohos.web.webview`（既有渲染器）、现有 `common` exports、生产渲染器 `MathTextRenderer`/`FormulaSplitRenderer`/`ChatBubble`、`ArkWebWarmupService`（ticket-0.1 前置查询）。
**State Management**: 保留现有 State Management V1 约定；harness 页用 `@State ChatMsg` 驱动生产 `ChatBubble` 的 `@Prop` 更新，不引入 V2。
**Storage**: 基准原始样本按 fixture 追加写入应用私有 `filesDir/chat-render-benchmark/<fixture>.json`（每 run 一条原始记录）并同步输出结构化 hilog（双通道，`hdc_log` 采集后转录进 verification-record 与 ADR）；中断时已完成组数据保留、不整轮重跑；不碰 Preferences chat history。
**Testing**: TDD 红步（先写 `entry/src/test/ChatRenderFixturesBudget.test.ets` 再实现）、Node regression harness（`scripts/arkts-lint/tests/chat-render-benchmark-gate.test.mjs` 做生产边界与 ADR/spec 回填断言）、每步 `arkts_check`、最终 full entry Hypium suite + naming lint + `git diff --check` + debug build；hvigor 用 DevEco bundled runner（#123 记录的环境：`"D:\HarmoNova\DevEco Studio\tools\node\node.exe" "D:\HarmoNova\DevEco Studio\tools\hvigor\bin\hvigorw.js"`，`DEVECO_SDK_HOME="D:\HarmoNova\DevEco Studio\sdk"`）。
**Target Platform**: HarmonyOS mobile app，`entry` HAP；基线目标设备 = MatePad Pro 13 模拟器（127.0.0.1:5555，与 #120–#123 一致）。
**Project Type**: 既有多 module HarmonyOS application（增量 seam，非新工程）。
**Performance Goals**: 每 fixture ≥20 次可复现运行；p50/p95 报告；`T_finishToStable` p95 初始性能目标 500ms（DevEco 模拟器未达标时记录性能跟进，不降低目标，也不否定完整证据交付）；长帧规则 32ms 且禁连续两帧长帧，模拟器偏差记录为性能跟进；`T_firstDeltaToVisible` p95 >1.5s 仅作观测告警。
**Constraints**: warmup precondition 非 `valid` 时 fail fast 不采集；harness 页临时（观察后删除，`main_pages.json`/`EntryAbility.ets` 恢复字节一致）；测量 seam 零渲染逻辑变更；不引入 StreamingReplyDocument/RendererScheduler/RenderTick；KaTeX output 不变；`spec/feature.json` 不重指向本 ticket。
**Scale/Scope**: 1 个测量 seam 服务 + 1 个 fixture/stats 纯逻辑服务 + 1 个临时 harness 页 + 2 个测试文件 + 1 个新 ADR + spec 021 §6 回填 + verification-record；预计 harness 全量运行时长（4 组 × 20 次 × 约 5s 运行 + 每次 finish+30s 稳态采样）约 50–60 分钟。

## Project Structure

### Documentation (this feature)

```text
spec/ticket-0-6-chat-render-fixtures-budgets/
├── spec.md
├── plan.md
├── tasks.md
└── verification-record.md
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── services/
│   ├── ChatRenderBenchmarkStats.ets      # 新: 测量 seam（计数器/时间戳/帧采样缓冲/结构化 hilog）
│   └── ChatRenderFixtures.ets            # 新: 确定性 fixtures + 纯统计（p50/p95、预算推导函数）
├── shared/atoms/
│   └── MathTextRenderer.ets              # 改: 最小测量埋点（onPageEnd 计数、setWebHeight 包装、cache hit/miss、降级计数）
└── overlays/AgentFloatWindow/chat/
    └── ChatRenderBenchmarkHarness.ets    # 临时: 基准 harness 页（观察后删除）

entry/src/test/
└── ChatRenderFixturesBudget.test.ets     # 新: 聚焦 Hypium 测试（fixtures/统计/预算推导/统计语义）

scripts/arkts-lint/tests/
└── chat-render-benchmark-gate.test.mjs   # 新: 生产边界 + ADR/spec 回填 Node 回归断言

docs/adr/
└── 0017-renderer-scheduler-budget-baseline.md   # 新: 预算默认值冻结（含推导规则、设备、证据摘要）

docs/specs/
└── 021-chat-streaming-incremental-rendering.md  # 改: §6 回填冻结的预算默认值
```

**Structure Decision**: 遵循 MindTrace 现有架构与目录约定（`entry/src/main/ets/services/` 放 seam 服务，#121/#123 先例；harness 页临时放入 `overlays/AgentFloatWindow/chat/` 便于复用生产 import 路径；测试进既有 `entry/src/test/` 与 `scripts/arkts-lint/tests/`）。不做 MVVM 迁移、不新建目录层级。fixture 与统计作为纯逻辑服务放 main 源集（非 test）是因为 harness 页运行时必须 import 它，且 `src/test` import main 是仓库正常测试方向（#121 先例）。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 生产渲染器 `MathTextRenderer` 增加测量埋点（计数/时间戳调用） | #124 验收明确要求记录 Web create count 与 height update count；这两个值只存在于生产渲染器内部，外部（harness/日志）无法精确观测 | 外部间接推断（onAreaChange 次数代理）精度不足且无法区分 Web 创建与高度回传；DevEco Profiler 是手动外部工具，无法做 20 次自动重复的 p50/p95 报告 |
| harness 全量运行约 50–60 分钟 | 每 run 必须采样 finish+30s 稳态内存（spec 021 明文，非瞬时峰值），4×20 次无并行 | 缩短到 10s 或只抽样子集会违反 spec 021 的 30s 稳态定义；并行运行会互相污染内存/CPU 测量 |

## Research & Decisions

- **Decision**: 长帧规则用 `displaySync`（`@kit.ArkGraphics2D`）逐帧 `timestamp`/`targetTimestamp`（纳秒）测量，帧耗时 = 相邻帧 `timestamp` 差，长帧 = >32ms；测量窗口 = finish 后首个 500ms；同时开 `hichecker`（`RULE_CAUTION_PRINT_LOG | RULE_THREAD_CHECK_SLOW_PROCESS | RULE_CHECK_ARKUI_PERFORMANCE`）作为 hilog 侧第二信源。
  - **Rationale**: 官方 `hichecker.addCheckRule(rule)` 无 32ms 阈值参数（阈值系统固定），无法精确实现 spec 021 的 32ms 规则；`displaySync.on('frame')` 提供单调纳秒时间戳，API 11+ 且本机基线可用，回调轻量只做时间戳差计算。`requestAnimationFrame` 仅存在于类 Web JS 范式，ArkTS 声明式不可用（官方文档确认）。DisplaySync 不调用 `setExpectedFrameRateRange`，保持跟随应用当前帧率，不改变渲染行为。
  - **Alternatives considered**: 纯 hiccheker 慢事件规则（阈值不可控，弃）；`setInterval(0)` 差值代理（是 UI 线程停顿代理，不是真实帧耗时，弃）；DevEco Profiler 手工 trace（无法自动化 20 次，弃）。

- **Decision**: steady memory 用 `hidebug.getAppVMMemoryInfo()` 在每 run finish+30s 单点采样（VM 内存 usedSize 等字段，实现期以 `js-apis-hidebug` API 文档为准核对字段名）。
  - **Rationale**: spec 021 要求 finish 后 30s 稳态而非瞬时峰值；hidebug 是官方内存采集 API。采样点在测量窗口之外，不受 hidebug 调用自身耗时（官方注明可达秒级）影响。
  - **Alternatives considered**: 瞬时峰值采样（违反 spec 021 稳态定义，弃）；外部 AppAnalyzer（非自动化，弃）。

- **Decision**: 测量 seam `ChatRenderBenchmarkStats.ets` 放在 `entry/src/main/ets/services/`，计数器恒开（纯整数自增，零分配），样本缓冲与 hilog 输出由 `enable` 门控（默认关闭，harness 使能）；`MathTextRenderer` 以私有方法 `setWebHeight()` 包装 `webHeight` 赋值点统一计数，`onPageEnd` 计 Web 创建数，`cacheGet` 计命中/未命中，降级路径计 degradation。
  - **Rationale**: #124 要求精确计数且允许最小测量 seam（用户已确认）；包装赋值点比逐个埋点更集中、可证明行为等价（赋的值完全相同）。计数器恒开满足 spec 的 always-on 语义，缓冲门控避免生产设备长期运行的内存增长。
  - **Alternatives considered**: 全部门控（与 spec 假设冲突，弃）；在 `FormulaSplitRenderer` 埋点（块创建在 `MathTextRenderer` 内部才对应真实 Web 生命周期，上层埋点会重复计数 build 重入，弃）。

- **Decision**: 预算推导规则固定为可复算公式：`maxWebCreatesPerFrame = clamp(floor(32 / medianPerCreateWorkMs), 1, 4)`；`maxWebWorkMsPerFrame = clamp(round(p75(perCreateWorkMs)), 1, 16)`；`perCreateWorkMs` = 每个 Web 工作单元从创建（MathTextRenderer 进入 Web 渲染决策）到首次高度回传应用的实测耗时样本集。
  - **Rationale**: 32ms 是冻结的长帧预算；`maxWebCreatesPerFrame` 保证单帧 Web 创建数×中位单创建成本不越帧预算，上限 4 防样本异常放行；`maxWebWorkMsPerFrame` 用 p75 覆盖典型工作单元且硬上限 16ms（32ms 帧预算的一半安全边际）。公式只依赖 recorded 样本，任何人可从 verification-record 数值复算。
  - **Alternatives considered**: 凭视觉判断取 1 或 2（违反"不允许主观流畅度"）；以平均值推导（长尾被低估，弃）。

- **Decision**: 临时 harness 页 `ChatRenderBenchmarkHarness.ets` 通过 `@State ChatMsg` 驱动生产 `ChatBubble`（`@Prop` 更新），delta 按固定分块/节奏注入（常量 `DELTA_CHUNK_CHARS`/`DELTA_TICK_MS`），finish 翻转 `streaming=false` 触发真实 `FormulaSplitRenderer` 路径；每组 20 次自动串行运行；观测后整页删除（#123 先例）。
  - **Rationale**: 复用生产渲染器只读 + 确定性模拟 SSE 是用户确认的可复现方案；`ChatBubble` 是流式→finish 切换的唯一真实入口，绕过它会让 `T_firstDeltaToVisible`/`finish→visible` 失去语义。
  - **Alternatives considered**: 直接渲染 `FormulaSplitRenderer`（跳过流式阶段，`T_firstDeltaToVisible` 无意义，弃）；真实 LLM SSE（不可复现，用户已确认排除，弃）。

- **Decision**: `T_sealedToVisible` 记 N/A，基线只测 `finish→visible`；`visible` 判定 = 块高度回传已应用（seam 记录首次 height-applied 时间戳）+ 块在视口内（harness 保证 fixture 单屏内，并以列表 `onAreaChange` 证据记录视口成员）。
  - **Rationale**: 当前渲染链路在 finish 前不存在 seal 事件（公式内容 finish 时才首次交给渲染器），用户已确认 N/A 映射。
  - **Alternatives considered**: 强行映射 seal≡finish（用户已明确选择 N/A，弃）。

- **Decision**: 预算默认值与证据冻结于新 `docs/adr/0017-renderer-scheduler-budget-baseline.md`，并回填 `docs/specs/021-chat-streaming-incremental-rendering.md` §6 的"两个预算的最终默认值在 ticket-0 真机测量后固化"条目（用户确认的落点）。
  - **Rationale**: spec 021 §6 明确"ticket-0 后不得被后续 ticket 随意修改"，ADR 记录 why + 推导 + 设备环境，spec 021 记录冻结值。
  - **Alternatives considered**: 仅 verification-record（数值无权威落点，后续 ticket 无从引用，弃）；仅 spec 021（缺 why 与证据链，弃）。

- **Decision**: `spec/feature.json` 不重指向本 ticket，保持指向 `spec/019-reasoning-process-display-p0`（#123 先例，用户既有约定）。
  - **Rationale**: 本 ticket 与 #120–#123 同属 ticket-0 系列，不抢占活动 019 工作的 feature 指针。
  - **Alternatives considered**: 重指向（打破系列 ticket 既定所有权边界，弃）。

## Data Model

- **ChatRenderFixture**
  - Purpose: 一个确定性基准负载；四实例 A/B/C/C′。
  - Fields: `id: 'A' | 'B' | 'C' | 'C_P'`、`bodyText: string`、`formulaCount: number`、`layout: 'none' | 'sparse' | 'dense' | 'consecutive_pairs'`。
  - Validation: 纯文本字符数四组相等；公式数 A=0/B=2/C=6/C′=6 且 C′ 呈 3 对连续闭合；内容无随机/网络/LLM 依赖。

- **FixtureRunSample**
  - Purpose: 单次运行的原始样本。
  - Fields: `runIndex`、`deltaStartTs`、`finishTs`、`firstVisibleTs`（首个高度回传应用）、`stableTs`（最后高度回传 + 500ms 无变化）、`frameDurationsMs[]`（finish 后 500ms 窗口）、`longFrameCount`、`webPageLoadCount`、`heightUpdateCount`、`cacheHitCount`/`cacheMissCount`、`degradationCount`、`steadyMemoryVm`（finish+30s）、`preconditionState`。

- **PercentileReport**
  - Purpose: 每 fixture 的统计输出。
  - Fields: `fixtureId`、`runCount`、各指标 `p50`/`p95`、冷/热 run 区分（首 run 冷）。

- **RendererBudgetProposal**
  - Purpose: 冻结的预算默认值。
  - Fields: `maxWebCreatesPerFrame`、`maxWebWorkMsPerFrame`、`derivationRule`、`evidenceSummary`、`device`。

- **BenchmarkBaselinePrecondition**（既有，来自 `ArkWebWarmupService`）
  - `state: 'initial' | 'valid' | 'invalid'`；采集门禁，非 `valid` fail fast。

- **Gate Status**
  - `PASS` / `FAIL` / `INCOMPLETE`，语义与兄弟 ticket 一致。

## Contracts & Interfaces

### ChatRenderBenchmarkStats seam contract

- **Owner**: `entry/src/main/ets/services/ChatRenderBenchmarkStats.ets`。
- **Responsibility**: 进程内基准计数与样本缓冲；生产渲染器埋点调用；harness 读取快照并输出结构化 hilog。
- **Public surface**（语义，非实现细节）:
  - `enableForRun(fixtureId, runIndex): void` — 清空样本并开始一次运行。
  - `disable(): void` — 停止缓冲（计数器保留）。
  - `recordWebCreate()` / `recordHeightUpdate()` / `recordCacheHit()` / `recordCacheMiss()` / `recordDegradation()` — 纯整数自增。
  - `snapshot(): FixtureRunSample` 形态的数据读取。
  - 结构化 dump: `[ChatRenderBench] fixture=<id> run=<n> metric=<name> value=<number>` 与每 fixture 汇总块（p50/p95）。
- **Guarantees**: 计数器恒开、恒单调；缓冲仅在 enable 期间；不抛出、不阻塞、不改变任何渲染决策。
- **Traceability**: 覆盖 FR-004、FR-005、FR-006。

### MathTextRenderer minimal seam contract

- **Owner**: `entry/src/main/ets/shared/atoms/MathTextRenderer.ets`（生产，最小改动）。
- **Responsibility**: 在真实 Web 生命周期点调用 stats：`onPageEnd` → `recordWebCreate()`；`webHeight` 赋值统一经私有 `setWebHeight()` → `recordHeightUpdate()`；`cacheGet` 命中/未命中计数；降级（`webFailed` 置位与 plainFallback 进入）→ `recordDegradation()`。
- **Required behavior**: 除计数调用外，赋值值、分支条件、缓存逻辑、调度行为与改动前逐字节等价；无任何渲染语义变化。
- **Traceability**: 覆盖 FR-006、FR-010。

### Harness page contract (temporary)

- **Owner**: `entry/src/main/ets/overlays/AgentFloatWindow/chat/ChatRenderBenchmarkHarness.ets`（临时，观察后删除）。
- **Responsibility**: 查询 `ArkWebWarmupService.getBenchmarkBaselinePrecondition()`（非 valid → fail fast + hilog 记录）；按 fixture × 20 次自动运行；确定性 delta 注入（固定 chunk/tick）；DisplaySync 帧采样（finish 后 500ms 窗口）；finish+30s steady memory 采样；输出结构化 hilog 汇总。
- **Retention**: 每 run 原始样本同时追加写 `filesDir/chat-render-benchmark/<fixture>.json` 与结构化 hilog（双通道）；中断可恢复（已完成组数据保留，不整轮重跑）。
- **Single-process**: 启动 → warmup → precondition 查询 → 4×20 采集必须在同一进程内完成，不得中途重启应用（precondition 是进程内状态，重启即重置为 initial/unknown）。
- **Constants**: `DELTA_CHUNK_CHARS`、`DELTA_TICK_MS`、`FRAME_WINDOW_MS = 500`、`LONG_FRAME_MS = 32`、`STEADY_MEMORY_DELAY_MS = 30000`、`RUNS_PER_FIXTURE = 20`。
- **Restoration**: 删除后 `main_pages.json` 与 `EntryAbility.ets` 恢复字节一致，零残留 diff。
- **Traceability**: 覆盖 FR-001、FR-004、FR-005、FR-007、FR-008、FR-011。

### Budget derivation contract

- **Derivation rule**: `perCreateWorkMs` = 每块从 Web 创建到首次高度回传应用的实测样本；`maxWebCreatesPerFrame = clamp(floor(32 / median(perCreateWorkMs)), 1, 4)`；`maxWebWorkMsPerFrame = clamp(round(p75(perCreateWorkMs)), 1, 16)`。
- **Freeze**: 数值 + 公式 + 设备型号 + 证据摘要写入 `docs/adr/0017-renderer-scheduler-budget-baseline.md`；`docs/specs/021-chat-streaming-incremental-rendering.md` §6 回填冻结值。
- **Traceability**: 覆盖 FR-009、SC-005。

### Regression verification contract

- **Hypium focused**: `entry/src/test/ChatRenderFixturesBudget.test.ets` — fixtures 确定性/公式数/C′ 配对、percentile 计算、visible 判定、预算推导公式（合成证据复算）、stats 计数/快照语义；TDD 红步先行并记录。
- **Node regression**: `scripts/arkts-lint/tests/chat-render-benchmark-gate.test.mjs` — 生产 diff 无 StreamingReplyDocument/RendererScheduler/RenderTick；harness 文件不存在、`main_pages.json`/`EntryAbility.ets` 已恢复；`MathTextRenderer` 渲染逻辑保留（renderContent/applyCachedRender 等仍存在）；ADR 与 spec 021 §6 含冻结数值。
- **Cadence**: 每步 `.ets` 编辑后 `arkts_check`；focused 测试在 RED/US 间定期跑；最终 full entry suite 一次；naming lint；`git diff --check`；debug build；设备证据（harness 运行 + `hdc_log` 采集）后 resolve gate。
- **Stop point**: 实现 + 验证完成后停止，`/code-review` 与 commit 前等待用户（AGENTS.md 红线）。
- **Traceability**: 覆盖 FR-012、SC-006、SC-007。
