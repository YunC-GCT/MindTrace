# 037 — RAG 检索：复用 DataAugmentationKit 的 retrieval / knowledgeProcessor

> Status: 立项（2026-10-31）· 主线: v1 整理链路收尾 · 上游: ADR-0019 / 036 / ADR-0021
> 结论先行：**鸿蒙有现成 RAG/检索 Kit**，`@kit.DataAugmentationKit` = `retrieval`（RDB 检索）+ `knowledgeProcessor`（知识库切分/加工）+ `rag`（检索增强生成）+ `localChatModel`。
> 本项目走「`retrieval` 复用既有 RDB + 现有云端 LLM」路线，不依赖受限的 `localChatModel` 与 `rag` 生成。

## 1. 为什么是 retrieval Kit（而不是自研向量检索）

| 能力 | Kit 提供 | 项目现状 | 结论 |
|---|---|---|---|
| RDB 全文检索（BM25/倒排） | `retrieval.getRetriever(RetrievalConfig)` → `Retriever.retrieveRdb(query, condition)`；`ChannelType.INVERTED_INDEX_DATABASE`；直接用 `relationalStore.StoreConfig` 打开我们的 `MindTrace.db` | 已有 `rag_chunk` / `rag_embedding` 表（v16 schema），但**无运行时检索** | **直接复用**：FTS 表 + Kit 检索 |
| 向量检索 | `ChannelType.VECTOR_DATABASE` + `VectorRecallCondition` / rerank | 无 embedding 服务；`localChatModel` 在手机/平板不可用（MRO-W00 实测 false） | 二期，需先解决 embedding 来源 |
| 知识库加工（chunk→知识条目） | `knowledgeProcessor.getKnowledgeProcessor(context, config)` + `process` | 无 | 二期（可省，自己切分更快） |
| RAG 生成（检索→LLM 回答） | `@hms.data.rag`（`Rag`/`ask`，依赖系统能力/端侧模型） | 已有云端 LLM（`LlmClient`）稳定可用 | **不用** Kit 生成；检索上下文注入现有 LLM 提示 |

关键结论：
- **检索是数据层能力**（`@syscap SystemCapability.DataAugmentation.Retrieval`，`@since 6.0.0(20)`），项目 `compatibleSdkVersion 6.1.1(24)`、设备 7.0.0 覆盖；不依赖端侧大模型。
- Kit 返回 `RdbRecords.records: ItemInfo[]`（`primaryKey` / `columns` / `score`），足够映射到现有 `NoteEvidenceCitation`。

## 2. 复用点：`NoteEvidenceService` 已经是现成的证据管线

`entry/services/NoteEvidenceService.ets` 已实现：
`build(query)` → `queryHits`（当前走 MCP `note.search` 工具）→ citations/relations → `formatContext` → `evidenceContext` 注入 `IntentClassifier` → 回答带引用 + `sanitizeAnswer` 引用校验。
`ConversationWorkflow` 与 `NoteReviewService` 都已消费它。

因此 RAG 不需要新造注入管线，**只需要把 `queryHits` 的召回换成 Kit 检索**（保留格式化/引用/降级逻辑）：

```
NoteEvidenceService.build(query)
  ├─ [新] RagRetrievalService.search(query, topK)   // @kit.DataAugmentationKit retrieval，BM25
  │     └─ 命中 → join knowledge_unit 补 title/subject/chapter/version → NoteEvidenceCitation
  └─ [fallback] 现有 note.search 工具（Kit 不可用 / 表未就绪 / 查询异常时降级，reason='rag-fallback'）
```

## 3. 数据与写入路径

- **FTS 表**（schema v19，幂等）：
  ```sql
  CREATE VIRTUAL TABLE IF NOT EXISTS note_fts USING fts5(
    title, content, unit_id UNINDEXED, subject UNINDEXED, chapter UNINDEXED
  );
  ```
  回填：v19 迁移后用 `knowledge_unit` 全量重建一次（幂等 `INSERT`）。
- **写入同步**：`KnowledgeUnitWriteService.create/update/delete` 成功后同步 `note_fts`（delete+insert，单事务；失败只记日志，不阻塞笔记写入）。
- **检索**：`RagRetrievalService.search` 用 `InvertedIndexRecallCondition(ftsTableName:'note_fts', fromClause:'note_fts', primaryKey:['unit_id'], responseColumns:['title','content','subject','chapter'])`，`resultCount=topK`，RRF 默认。
- **约束（红线）**：`@kit.DataAugmentationKit` **只在 entry 进程 import**，不经过 `common`/`agents` barrel（延续 AGENTS.md 红线 11：受限 Kit 不得进扩展进程；A2A 扩展进程不加载 RAG）。

## 4. 分片计划

| 切片 | 内容 | 验收 |
|---|---|---|
| R1 | `RagRetrievalService.probe`（getRetriever + FTS5 建表/插入/检索）+ `e2e=ragProbe` 真机探针 | 真机日志：`stage=rag-probe ok=1 hits>=1` |
| R2 | schema v19：`note_fts` + 迁移回填；写路径同步（create/update/delete） | 单测（schema/同步 SQL）+ 真机笔记写入后检索命中 |
| R3 | `NoteEvidenceService.queryHits` 切换到 Kit（保留 fallback） | 单测（映射/降级）+ 真机问「我之前记的极限题」命中引用 |
| R4 | 生成侧注入：`NoteGenerationContextBuilder` 加入相关笔记片段 | 生成笔记时 prompt 含检索片段 |
| R5 | `knowledgeProcessor`/向量通道评估（需先解决 embedding 来源） | 文档结论 |

## 5. 真机探针状态（2026-10-31）

- 设备：`3XTYD24C16203663`（MRO-W00 / HarmonyOS 7.0.0，API 26）；项目 `compatibleSdkVersion 6.1.1(24)`，API 覆盖 `@since 6.0.0(20)`。
- 已观测（修正）：此前的「getRetriever 挂起」实为**锁屏后应用被冻结**（JS 定时器停摆）；解锁后 `getRetriever` **14ms 成功**。已修 `scripts/device-runner.mjs`：e2e 前 `power-shell wakeup` + 把休眠时间拉到 30 分钟；`--cold` 改为「先正常启动预热 6s，再带 `--ps` 走 onNewWant 触发」，避免冷启动早期 IO 竞争卡住。
- **自管 FTS5 可用（结论）**：`note_fts` FTS5 表 + `tokenize='trigram'`，真机查询 `MATCH '连续性'` 命中 1 条、耗时 58ms。注意 trigram 要求查询 ≥3 字符（2 字查询需 LIKE fallback）。
- **Kit `retrieveRdb` 尚未可用**：`getRetriever` OK，但 `retrieveRdb` 两种参数档均报 `1021201002 Retrieval: The value of the numerical parameter is outside the constrained range`（默认策略 / 显式 BM25 策略都复现）；根因待查（可能与 FTS 表结构/UNINDEXED 列/策略权重范围有关）。
- **决策**：RAG 检索一期走**自管 FTS5**（可控、已验证）；Kit 保留为可选加速通道（恢复后一行开关切回），不阻塞主链路。

## 6. 风险

| 风险 | 处理 |
|---|---|
| FTS5 在 HarmonyOS RDB 不可用 | R1 探针先验证；不可用则退回 Kit 的倒排索引需建表方式（查文档）或自研 LIKE 检索 |
| Kit 在扩展进程不可用/崩溃 | 只在 entry import；A2A 链路不调用 |
| 数据库被 Kit 独立打开导致锁 | Kit 使用同一 `StoreConfig`（name/securityLevel）；写入路径短事务，失败降级 |
| 检索结果与 `note.search` 语义差异 | 保留 fallback + `degraded/reason` 标记，UI 可见 |
