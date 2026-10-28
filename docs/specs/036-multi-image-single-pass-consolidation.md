# 036 — 一次整理：1..N 张图 → 多题汇总

> 状态: 阶段 1 已落地（`0c60f21`）· 阶段 2–5 未动 · 起点: 2026-10-28 · 主线: v1 采集中枢
> 上游: [`phase-tracker.md`](../agents/phase-tracker.md) P2/P4 · [`ADR-0019`](../adr/0019-note-command-and-outcome.md) NoteCommand / NoteOutcome
> 下游: 采集进度与确认（本 spec §7/§8）、`#241` Dispatcher 定型

## 1. 背景与目标

现状：一次 `AiService.capture(imageUri)` = 一张图 = 一条笔记。UI 的“批量”不是一个功能，而是把同一件事重复 N 次：

```ts
// entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets:965-974
for (let i = 0; i < uris.length; i++) {
  this.showToast('正在整理 ' + (i + 1) + '/' + uris.length);
  await service.capture(uris[i]);   // 每张图独立跑一遍 Ocr→Classify→Structure→Truth→Persist
}
```

这批图之间有语义关系（同一份卷子、题干与解答分页、同一页多道题），但当前实现把它们当成互不相干的 N 个任务，所以：一页 4 道题会合成 1 条臃肿笔记；题干在第 1 页、解答在第 2 页会落成 2 条残缺笔记；重复拍同一页会落 2 条重复笔记。

**目标**：入口只有一个（选 1 张或多张都一样），对这批图**整体**做一次整理，产出 M 条结构良好的笔记，其中 M 由题意决定而不是由图片张数决定。

**非目标**：
- 不新增“批量”入口或模式；`+ → 相册/批量` 合并为同一个动作（1 张和 20 张走同一条路）
- 不新增第 6 个 module，不新建 workflow 引擎；复用现有 `StateGraph` / `RunContext`
- 不做视频、多模态理解、跨设备同步
- 不改 `NoteDao` 的 SQL 形状（表结构变更另开迁移票，见 §9）

## 2. 场景矩阵

| 编号 | 场景 | 输入 | 期望输出 |
|---|---|---|---|
| S1 | 单图单题 | 1 页 1 题 | 1 条笔记（= 现状，不得回归） |
| S2 | **单图多题** | 1 页 4 题 | 4 条笔记，同一 `sourceSetId`，各自题型/章节 |
| S3 | **多图同题跨页** | 题干 p1 + 解答 p2 | 1 条笔记，`content` 合并，两图都记入 sources |
| S4 | **多图多题** | 3 页 × 每页 2–3 题 | M 条笔记（M = 题数，≠ 图数） |
| S5 | 混合 + 重复 | 3 页 + 其中 1 页重拍 | 去重后 M 条，重拍那张 `skipped=duplicate` |
| S6 | 降级 | 某页糊掉/OCR 空 | 该 item `failed`，其余正常出笔记，回执逐条标注 |

S2 和 S4 是本次设计的核心：**笔记粒度必须由“题”决定，不能由“图”决定**。

## 3. 概念模型

```
CaptureSet（一次整理的材料集合）
  setId: string          // 本次整理的唯一标识
  items: CaptureItem[]   // 用户选中的 N 张图，顺序 = 选择顺序
  createdAt: number

CaptureItem（一张图）
  index: number          // 0-based，也是 UI 上「第 k 张」的来源
  uri / localPath
  imageHash: string      // 文件字节 sha256，用于去重
  ocrStatus: 'pending' | 'ok' | 'empty' | 'failed'
  text: string           // OCR 全文（保留块/行边界）
  problems: ProblemDraft[]  // 本图切出的题（S1 时长度 1）

ProblemDraft（一道题）—— 最小可确认单位
  index: number
  sourceItemIndexes: number[]   // 跨页合并后可能 > 1
  rawText: string               // 必须是原文切片，可 indexOf 回查
  category / subject / chapter  // Classify + Structure 回填
  unit?: KnowledgeUnit          // 结构化结果
  fingerprint: string           // 幂等键，见 §10
  status: 'draft' | 'ready' | 'failed' | 'skipped_duplicate'
```

**D1（待拍板）笔记粒度**：1 道题 = 1 条笔记，而不是「1 次整理 = 1 条笔记」。
理由：现有复习调度（`reviewStatus` / `nextReviewAt` / 间隔天数 / SM-2 的 `easeFactor`）是挂在 note 上的；一条笔记里塞 4 道题，无法分别安排复习，知识星系的计数也会失真。

## 4. 编排：两段式（map → reduce），不新增图

现有 `CaptureGraph` 五节点保持不动，在它外面加一层**集合编排**：

```
DispatchPayload.kind === 'images'
  → CaptureSetOrchestrator
      Stage A（逐图，可有限并行，失败隔离）
        for each item:
          OcrNode（现有 Core Vision）
          Segmenter（新增，纯函数优先 + LLM 兜底）→ item.problems[]
      Stage B（集合级，串行）
        Merger（纯函数规则 + LLM 兜底）→ 合并跨页题 / 去重
        for each problem:
          Classify → Structure → TruthCheck     （复用现有节点与 KnowledgeModel）
      Stage C（人）
        确认页（§7）→ Commit（逐题 Persist）
```

**D2（待拍板）并行度**：Stage A 最多 2 张并行。端侧 OCR 是重资源，20 张全并行在 MatePad 上会触发内存回收（真机日志里已见 `memmgrservice: setPrio`、`ApplyEfficiencyResources`）。串行亦可接受，20 张 × 0.5–1.1 s OCR ≈ 10–22 s。

预算：沿用 `RunContext`（`DISPATCH_RUN_BUDGET` 目前 128），一个 set 一个 context；按 `N(图) + 3×M(题)` 折算节点调用上限，超限返回 `BUDGET_EXCEEDED` 而不是静默截断。

## 5. 切题（Segmenter）

输入是 OCR 文本，输出是题边界。**规则优先，LLM 兜底，原文可回查**：

1. **锚点正则**（覆盖大多数试卷）：
   - `^\s*(\d{1,2})\s*[.、)）]`（1. / 2、/ 3)）
   - `^\s*第\s*[一二三四五六七八九十百\d]+\s*题`
   - `^\s*[（(]\s*\d{1,2}\s*[)）]`（小题号，仅在已进入某题正文时作为子题标记，不切主边界）
2. 命中 ≥ 2 个锚点 → 按锚点切；单图只切出 1 题时**不调用 LLM**（S1 零额外成本）。
3. 无锚点或切出的段长度极不均衡（某段 > 全文 60%）→ 调 LLM 分段，prompt 只允许返回锚点位置：「返回每题的起始原文片段（首 12 字）」，回切时用 `indexOf` 定位。
4. **校验**：每段 `rawText` 必须能在 `item.text` 中 `indexOf` 命中；任一段失败 → 整图退化为 1 题（`segmentation=degraded`），宁可粗不可错。

## 6. 跨图合并（Merger）

只在同一 `CaptureSet` 内合并，按强度分三档：

| 档 | 判定 | 动作 |
|---|---|---|
| 强 | 相邻 item、题号相同、文本相似度 ≥ 0.6 | 合并：长者为正文，另一者记入 `sourceItemIndexes`，标 `continuedFrom` |
| 强 | 上一图结尾无终止符（无 `。`/`答：`/解答完成标志）且下一图开头无题号 | 判为续页，拼接 |
| 弱 | 题号不同但题干相似（重拍/歪斜） | 去重，保留 OCR 置信度高者，另一条 `skipped_duplicate` |

**D3（待拍板）不确定时不合并**：相似度落在 0.4–0.6 灰区，两段都保留并标 `NEEDS_REVIEW`，让用户在确认页手动合并。宁可多一条让用户删，也不要把两道题揉成一条让用户拆。

## 7. 用户确认（落库前的闸门）

现在 `capture()` 直接落库，用户看不到识别结果，这是要修的核心问题之一。

```
Stage B 完成 → 确认页（M 条 draft）
   每行：第 k 张图 · 题型 · 标题 · 置信度徽标 · [保留/丢弃]
   顶部：全选 / 全不选 / 已选 x/M
   底部：[确认整理]（落库）  [取消]（整批不落库）
```

- **D4（待拍板）默认勾选**：建议默认全选，但 `TruthCheck` 有 flag（`OCR置信度低` / `无明确题目` / 数字校验失败）的条目默认不勾，让用户主动放行。
- Commit 必须幂等：`commitKey = setId FQ + problemFingerprint`，重复点确认不会双写（复用 `NoteWritePort` 的 `commitKey` 语义）。
- 一图多题时，确认页按题展示而不是按图，用户能只保留其中两题。

## 8. 进度与失败隔离

状态机（problem 级，item 级是其聚合）：

```
queued → ocr → segment → merge → classify → structure → awaiting_confirm → persisting → done
                                   ↘ failed(code, retriable)
awaiting_confirm → discarded（用户不勾）
```

- 进度事件由节点自己发出（复用 `RunContext` 这条 seam：节点已经拿到 context），UI 订阅后渲染「第 2/3 张 · 正在结构化 · 已出 4 条」，而不是现在的 toast。
- 失败隔离：单图 OCR 失败只废该 item；单题结构化失败只废该题；最终回执逐条列出 `done / failed / skipped_duplicate`，并带错误码（沿用 ADR-0019 错误码表）。
- 取消：整个 set 一个 `CancellationToken`，取消后已落库的不回滚（与 ADR-0019 `cancelled(committed)` 一致），未落库的 draft 丢弃。

## 9. 数据模型（最小改动）

- 现有 `note` 表能容纳「一题一条」，但缺少来源集合信息：需要 `source_set_id` + `source_item_index` 两列（或复用现有 provenance 字段，但 `sourceImageId` 是单值，跨页合并表达不了）。
- **不新建** `capture_set` 表（初版）：set 生命周期一次会话内，跨启动恢复靠 `CaptureReceipt`（扩展成逐条）。若后续要做「整理历史」，再单开迁移票。
- 表结构变更必须单独一票 + `DatabaseHelper` 迁移，不与本 spec 的实现混在一起。

## 10. 幂等与计费

- `imageHash` = 文件字节 sha256：同一张图重复选入直接 `skipped_duplicate`，不调 LLM。
- `problemFingerprint` = 归一化文本（去空白/标点/全半角）前 200 字 + 题型：命中已有笔记则提示「已有类似笔记」→ 默认不勾。
- 计费口径：一次整理 = `N`(切题，仅在需要时) + `M`(分类) + `M`(结构化) 次调用；20 图 × 平均 2 题 ≈ 60 次调用，必须在确认页显示预估，避免用户无感知烧额度。

## 11. 验收口径

| 项 | 命令 / 样本 | 通过标准 |
|---|---|---|
| S1 不回归 | 现有 golden `capture-success` 等 18 条 | 全部零重录通过 |
| S2 单图多题 | 1 页 4 题样本 | 确认页 4 条；落库 4 条；`sourceItemIndexes` 均为 `[0]` |
| S3 跨页同题 | 题干页 + 解答页 | 1 条；`content` 含题干与解答；`sourceItemIndexes=[0,1]` |
| S4 多图多题 | 3 页混合样本 | 条数 = 题数；无跨题串行污染 |
| S5 重拍去重 | 同一页选两次 | 第二次 `skipped_duplicate`，落库不增加 |
| 切题纯函数 | `node --test` | 锚点/无锚点/退化三种输入全绿，不依赖端侧 |
| 真机 | MatePad Pro | 3 页样本：逐条状态可见、确认页可逐条勾选、落库条数与勾选一致 |

## 12. 分阶段实施

| 阶段 | 内容 | 依赖 |
|---|---|---|
| 1 | payload 支持 `kind:'images'`（N 张）+ Stage A 串行，不切题（等价今天的批量，但一个 run） | 无 |
| 2 | Segmenter（切题）+ S2 验收 | 阶段 1 |
| 3 | Merger（跨页合并 / 去重）+ S3/S5 验收 | 阶段 2 |
| 4 | 确认页 + 进度订阅（S2–S5 UI） | 阶段 2（可与 3 并行） |
| 5 | 幂等 + 逐条回执 + 计费预估 | 阶段 3、4 |

阶段 1 就能把「一个 set 一个 run」立住，是后面全部工作的地基；阶段 4 是用户直接感知的那层。

### 阶段 1 实施记录（2026-10-28）

落地形态与上表略有出入：没有新增 `kind:'images'` 载荷，而是在**集合层**加了一个入口，
`DispatchPayload` 与 `DispatchResult` 的形状都不动，切题器以后接在 set 内部。

| 位置 | 内容 |
|---|---|
| `common/models/CaptureChain.ets` | `CaptureSetRequest` / `CaptureSetItemResult` / `CaptureSetResult`：一个 set 一份逐项回执，`cancelled` 与 `failed` 分开计数 |
| `agents/core/Dispatcher.ets` | `dispatchSet()`：顺序执行、全部共享同一 `RunContext`（预算 + 取消）、单项失败不打断整批；`withRunContext()` 显式搬运 `DispatchOptions` |
| `entry/services/AiService.ets` | `captureSet(uris, text?, token?)`：逐张准备（准备失败只废该项）、一次 `dispatchSet`、结果按原始下标合回 |
| `entry/overlays/AgentFloatWindow` | 图片入口即相册多选（1..20），`runCaptureSet` 不再 `for` 循环 `capture`；回执仍写 `CaptureReceipt` |
| `entry/overlays/AgentFloatWindow`（记录） | 整理过程写进当前会话：一条 `origin:'image'` 的 ai 消息随进度原地更新，收尾写总结句并落盘；不再用 toast 汇报进度 |
| `scripts/arkts-lint/tests/v7-capture-set.test.mjs` | 4 条守卫：逐项回执顺序、失败隔离、取消不混进失败、UI 不再自循环 |

验证：`agent-gate` = `RESULT: PASS (884 tests, 0 fail)`；`node scripts/build-hsp-hap.mjs` = 4× `BUILD SUCCESSFUL`。
**真机未验**：本轮设备未连接，选图链路要由人来自选图片，未做。

仍未做（阶段 2–5）：切题器 `segmentProblems`、跨图合并、确认页、进度订阅、幂等与计费预估。

## 13. 待拍板（阻塞实现）

| 编号 | 问题 | 选项 | 建议 |
|---|---|---|---|
| D1 | 笔记粒度 | 一题一条 / 一批一条 | **一题一条**（复习调度按 note 计量） |
| D2 | Stage A 并行度 | 1 / 2 / N | **2**（端侧 OCR 内存敏感） |
| D3 | 灰区合并 | 保留两条待复核 / 自动合并 | **保留两条**（让用户删，别让用户拆） |
| D4 | 确认页默认勾选 | 全选 / 全不选 / 按置信度 | **按置信度**：无 flag 默认勾，有 flag 默认不勾 |
