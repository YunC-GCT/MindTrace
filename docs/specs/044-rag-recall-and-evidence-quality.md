# 044 — RAG 召回质量与证据质量

> **Status**: proposed (2026-11-05)
> **Source**: [037-rag-retrieval-data-augmentation.md](./037-rag-retrieval-data-augmentation.md)（R2–R3 已落地，R5 未做）· [ADR-0018](../adr/0018-note-evidence-provenance.md) · [ADR-0021](../adr/0021-shared-read-port-implementation-in-common.md)
> **Files affected**: `common/src/main/ets/utils/NoteRetrievalQuery.ets` · `common/src/main/ets/ports/impl/NoteSearchRanking.ets` · `common/src/main/ets/ports/impl/RdbNoteSearchAdapter.ets` · `entry/src/main/ets/services/RagQueryPlan.ets` · `entry/src/main/ets/services/RagRetrievalService.ets` · `entry/src/main/ets/services/RagNoteEvidenceSearch.ets` · `agents/src/main/ets/evidence/NoteEvidenceService.ets` · `entry/src/main/ets/debug/DebugCaptureRunner.ets` · `entry/src/main/ets/entryability/EntryAbility.ets`
> **Test files**: `scripts/arkts-lint/tests/v7-rag-retrieval.test.mjs` · `scripts/arkts-lint/tests/rag-query-terms.test.mjs`（新）· `scripts/arkts-lint/tests/rag-ranking.test.mjs`（新）· `scripts/arkts-lint/tests/rag-eval.test.mjs`（新）

## 1. Why this ticket

2026-11-05 真机验证暴露出召回问题（review 文档 §25）：

| 查询 | 库里的笔记 | 结果 |
|---|---|---|
| `一加一等于几` | `一加一等于二` | 未命中 |
| `9+9 的加法计算怎么算` | `9+9 的加法计算` | 未命中 |
| `连续性` | `函数在一点连续的定义` | 命中 |

根因是**两条召回路径都拿用户整句做字面匹配**：

- [RagQueryPlan.ets](../../entry/src/main/ets/services/RagQueryPlan.ets) 在 ≥3 字时把整句送进 `note_fts MATCH ?`（trigram 短语匹配）；
- FTS 无命中后回退的 `note_query_rag`（[RdbNoteSearchAdapter.ets](../../common/src/main/ets/ports/impl/RdbNoteSearchAdapter.ets)）用 `instr(字段, 整句)`。

因此只要用户带了疑问词或语序不同，就必然未命中。037 的验收只覆盖了「能用」（`连续性` / `极限` 两条固定查询），没有覆盖召回率，也没有评测集，改参数无法判断好坏。

**本 spec 只解决词法召回与证据质量，不做向量检索。**

## 2. What we will build

### 2.1 查询归一与关键词拆分（纯函数）

新增 `common/src/main/ets/utils/QueryTerms.ets`：

```ts
export interface QueryTermPlan {
  raw: string;        // 原句（trim 后）
  terms: string[];    // 1..N 个关键词，按长度降序；去重
  normalized: string; // 全角转半角、小写、空白折叠后的原句
}

export function planQueryTerms(query: string): QueryTermPlan;
```

规则（确定性、无模型）：

1. 全角 → 半角；英文小写；连续空白折叠
2. 剥离疑问/语气尾巴：`怎么算`、`是多少`、`是什么`、`等于几`、`等于多少`、`怎么做`、`请问`、`帮我`、`一下`
3. 按标点与停用词切分：`的`、`了`、`吗`、`呢`、`和`、`与`、`把`、`这`、`那`、`个`
4. 保留数学片段（`9+9`、`x^2`、`3x+5`），不拆运算符
5. `terms` 长度 ≥1；若拆分后为空，回退为归一后的原句
6. 去重后按长度降序，最多 3 个词

### 2.2 FTS 召回：整句优先，词 OR 兜底

`RagQueryPlan` 产出的 plan 增加 `terms`，SQL 变成两段：

```
整句命中：WHERE note_fts MATCH ?                       -- 绑定 raw
词 OR：  WHERE note_fts MATCH '"t1" OR "t2" OR "t3"'   -- 绑定 terms
```

`RagRetrievalService.search` 先跑整句，`hits.length > 0` 直接返回（**已能命中的查询行为完全不变**）；否则跑词 OR。短词（<3 字，trigram 无法匹配）走现有 LIKE。

### 2.3 工具召回对齐

`RdbNoteSearchAdapter.search` 改为对每个 term 生成一组 `instr` 条件 OR：

```sql
(instr(lower(title), t1) > 0 OR instr(lower(content), t1) > 0 OR ...)
OR (instr(lower(title), t2) > 0 OR ...)
```

`NoteSearchRanking` 扩展打分：`score = Σ(字段权重 × 命中次数)`，并新增「命中词数」权重（`distinctTermBonus = 2`），避免 `计算` 这类泛词把无关笔记顶上来。原单 needle 入口保留，避免影响既有调用方。

### 2.4 证据打包与预算

`NoteEvidenceService.build` 现在固定取 topK 并拼接全部 context。改为按字符预算打包：

```ts
export interface NoteEvidenceOptions {
  topK?: number;
  maxContextChars?: number; // 默认 2400，替代隐式上限
}
```

- 按分数降序填充，超出预算截断并写 `reason='budget-truncated'`
- 同 noteId 只保留最高分片段（避免多 chunk 重复）
- 保持 `citations` 与 `contextText` 一一对应

### 2.5 引用覆盖率校验

_answer 里出现的 `[noteId=...]` 必须落在 citations 内_（现有 `sanitizeAnswer` 已删除非法引用）。增加一条可观测指标：

```
[RAG] citations=N answerRefs=M validRefs=K droppedRefs=D coverage=K/M
```

覆盖率低于阈值只记日志，不改变回答（P0 不阻断）。

### 2.6 召回评测集（Node + 真机）

- `scripts/rag-eval/queries.json`：20–30 条 `{query, expectNoteIds[], note}`，覆盖：短句、带疑问词、公式、同义词、无答案负样本
- `scripts/arkts-lint/tests/rag-eval.test.mjs`：对纯函数（归一 + 排序）跑离线断言；
- `entry` 新增 `e2e=ragEval` 探针：读取内置评测集，逐条调用 `NoteEvidenceService.build`，输出 `hit@1 / hit@5 / miss` 汇总，作为真机验收证据。

## 3. Public surface change

| 变更 | 影响 |
|---|---|
| `QueryTermPlan` / `planQueryTerms` 新增 | 纯新增，无破坏 |
| `RagQueryPlan.terms` 新增字段 | 仅 `RagRetrievalService` 消费 |
| `NoteEvidenceOptions.maxContextChars` 新增 | 可选，默认值保持现状语义 |
| `NoteSearchRanking` 新增加权函数 | 原函数保留，`NoteQueryTools` 行为不变 |
| `e2e=ragEval` 新探针 | 仅调试入口 |

不改变：`NoteEvidencePort` / `NoteSearchPort` 契约、A2A、conversation 图结构。

## 4. Migration (atomic commits)

1. **`feat(rag): 查询归一与关键词拆分`** — 新增 `QueryTerms` 纯函数 + 单测；不改调用方
2. **`feat(rag): 整句优先、词 OR 兜底的 FTS 召回`** — `RagQueryPlan` / `RagRetrievalService` 接线；既有命中路径不变
3. **`feat(rag): 工具召回与多词融合排序`** — `RdbNoteSearchAdapter` / `NoteSearchRanking`
4. **`feat(rag): 证据预算与引用覆盖率`** — `NoteEvidenceService` + 日志
5. **`test(rag): 召回评测集与 ragEval 真机探针`** — 评测数据 + 探针 + 汇总输出

每个提交独立可回滚；1–2 完成后即可真机验证收益，3–5 不阻塞。

## 5. Test plan (TDD)

| 对象 | 新增测试 | 验证内容 |
|---|---|---|
| `planQueryTerms` | 8 | 疑问词剥离、数学片段保留、空输入回退、去重、最多 3 词 |
| `RagQueryPlan` | 4 | 整句 SQL 与词 OR SQL 的绑定参数顺序；短词走 LIKE |
| `NoteSearchRanking` | 5 | 多词加权、命中词数加成、字段权重不变、稳定排序 |
| `NoteEvidenceService` | 3 | 预算截断、同 noteId 去重、citations 与 context 对齐 |
| `rag-eval` | 1 组 | 评测集离线断言（归一后至少命中 expectNoteIds 之一） |

真机：`node scripts/device-runner.mjs e2e ragEval --wait 120`，记录 `hit@1 / hit@5 / miss`。

## 6. Reversibility

**Low。** 全部是纯函数 + SQL 拼接，且新召回只在「整句未命中」时触发；已能命中的查询路径不变。回滚任一提交不影响数据（无 schema 变更）。

## 7. Acceptance criteria

- [ ] `一加一等于几` → 命中 `一加一等于二`；`9+9 的加法计算怎么算` → 命中 `9+9 的加法计算`
- [ ] 既有查询（`连续性` / `极限`）结果不变，`citations=7 degraded=0` 不回归
- [ ] 评测集 `hit@5 ≥ 0.85`，负样本不产生引用（无假阳性）
- [ ] `NoteEvidenceService` 在 `maxContextChars` 内打包，citations 与 context 对齐
- [ ] `node scripts/agent-gate/index.mjs` PASS（含 process-boundary / hypium-check）
- [ ] 真机 `e2e=ragEval` 输出汇总，数值记录进 review 文档

## 8. Out of scope

- 向量检索 / embedding 接入（037 R5，需先解决 embedding 来源，另立 spec）
- rerank 模型、LLM 查询改写（引入延迟与非确定性，与本 spec 的确定性定位冲突）
- 95 条「有 FTS 无 chunk」旧笔记回填（与向量通道一起做）
- 工具循环（041）的超时/容错/流式问题——单独处理，不混在本 spec

## 9. Open questions

- 停用词表是否需要覆盖数学语境里的 `计算` / `求` / `证明`（视评测集结果调整）
- 证据预算默认 2400 字符是否合适（当前实测 contextChars=1603，先留余量）
- 评测集的 `expectNoteIds` 如何随笔记更新维护（先手工维护，后续可生成）

## 10. Sequencing note

本 spec 是 037 的「召回质量」补篇，不依赖向量通道；完成后 041 的工具循环也能复用同一套 query plan，避免对话前置检索与工具检索继续分叉。
