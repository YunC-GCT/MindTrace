# Bot 交接单 · flow（2026-10-30）

> 交接人：Hermes 主线 session · 接收：flow（deepseek-flash）· 状态：待接手
> 基线：`feature/a2a-text-ingest` @ `dac64c3`（未 push）
> 领域：`workflows/` `services/` `models/` `database/`；本单主战场在 `agents/src/main/ets/graph/` 与 `agents/src/main/ets/core/Dispatcher.ets`。

## 一、现状（已核实）

- 切题算法已经写好，但**只是纯函数，没有任何调用点**：
  - `agents/src/main/ets/graph/problemSegmenter.ets` → `segmentProblems(ocrText): SegmentResult`
  - `agents/src/main/ets/graph/problemMerger.ets` → `mergeProblems(inputs: SourceSegment[]): MergedProblem[]`（`:186`）
  - `grep -rn "segmentProblems\|mergeProblems" --include=*.ets agents/src entry/src` 只命中这两个文件自身与 `build/` 产物。
- `AgentState`（`agents/src/main/ets/graph/AgentState.ets:13`）现有 16 个字段：`captureText / source / payload? / classification? / knowledgeUnit? / truthCheck? / error? / currentStep / persist / analysisOnly / generationRequest? / draft? / standardResult? / subjectVocabulary? / preparedCandidate? / commitResult?` —— **没有 `problemSegments`、没有 `sourceImageIds`**。
- 装配点：`Dispatcher.buildGraph`（`agents/src/main/ets/core/Dispatcher.ets:1786`）里还是旧 capture 图；`CaptureGraph`（`agents/src/main/ets/graph/CaptureGraph.ets:26`）按节点链跑。
- 结果回执：`DispatchResult` 形状被多处依赖，**本轮不许改**。

## 二、任务（按 spec 036 的阶段划分推进，一次只推进一格）

1. **阶段 2a 接线（单图多题）**：给 `AgentState` 加 `problemSegments?: ProblemSegment[]` 与 `sourceImageIds?: string[]`（只加字段，不改既有字段语义）。在 OCR 之后插一个节点，对**每张图**的 OCR 文本调 `segmentProblems`，结果按图 id 扁平化进 state。切题锚点、≥2 锚点才切、合并阈值全部以 [`docs/specs/036-multi-image-single-pass-consolidation.md`](../../specs/036-multi-image-single-pass-consolidation.md) 为准，**不要在这里另抄一份正则**。

2. **阶段 2b 跨图合并（多图多题）**：新增合并节点调 `mergeProblems`，相似度 `≥0.6` 取长文合并、`0.4–0.6` 标 `NEEDS_REVIEW`，**不要再改阈值**（spec 036 已定）。
3. **阶段 3 一题一条 note**：把现在「一次 capture → 一条 unit」的持久化分支改成「N 个 problem → N 条 note」，走现有 `KnowledgeUnitWriteService` 正规写路径，**不许让 `AiService` 直连 `NoteDao`**；扩展进程（`:agent`）同样走正规写路径；单条失败不回滚整批。
4. **文本指纹去重（P2）**：同一段 OCR 文本重复进来（用户重拍同一页）时合并而不是新建，用正文归一化后的指纹，别用时间戳。
5. **`RunStore` run 级事件表（P2，可延后）**：编排层目前没有 run 级可观测性，节点进出只有日志。要做就做成独立 commit，别和上面三格混在一起。

## 三、硬约束

- `DispatchResult` 形状不改；**golden 不重录**（测试绿了再提交，红了改代码不改基线）。
- 每推进一格：独立 commit + 独立 `node scripts/agent-gate/index.mjs`（pty，别接管道，接管道会 `stdout is not a tty`）。
- 新文件禁 BOM；禁正则字面量（ArkTS 10505001，用 `split/filter` 组合）；禁 `any`/`unknown`；`throw` 只抛 `Error`。
- schema 变更（新增表/列）**先过 architect**，本轮预期不需要改表。

## 四、验收

- `node --test` 覆盖：单图两题切 2 段、多图相似题合 1 条、两图无关题合 2 条、`NEEDS_REVIEW` 边界 0.6/0.4。
- `node scripts/e2e-capture/run.mjs` 跑一次端到端：`stage=done ok=N failed=0`，且库里条数 = N（用一题多图/多题多图两种输入各跑一次）。
- `node scripts/agent-gate/index.mjs --all` 必须 `RESULT: PASS`，报告里贴 `pass=/fail=` 与 `.ets` 计数。
- 交付时写清楚：新增字段名、新增节点名、`problemSegments` 在哪个节点被消费、以及两张输入图各自的 N。
