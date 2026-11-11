# ADR-0023: RAG 检索一期采用本机 FTS5 + 既有证据注入链路

- **状态**: accepted
- **日期**: 2026-11-01
- **相关**: [`docs/specs/037-rag-retrieval-data-augmentation.md`](../specs/037-rag-retrieval-data-augmentation.md)、ADR-0018（证据可溯源）、ADR-0019（NoteCommand/NoteOutcome）、ADR-0021（读端口在 common / 写在 entry）

## 背景

产品需要一个「回答/生成时能引用用户已保存笔记」的 RAG 轨道：

1. 对话回答要能带引用（笔记标题 + 版本来得及校验引用真伪）；
2. 生成新笔记时能参考相关旧笔记（注入 source bundle）；
3. 数据结构上已有 `rag_chunk` / `rag_embedding` 表（v16 预留），但运行时没有任何读写；
4. 鸿蒙提供 `@kit.DataAugmentationKit`（`retrieval` / `knowledgeProcessor` / `rag` / `localChatModel`），需要判断能否直接复用。

## 决策

**一期检索走「本机 SQLite FTS5（`note_fts`）+ 既有 `NoteEvidenceService` 证据链路」**：

| 层 | 决策 |
|---|---|
| 索引 | schema v19 新增 `note_fts`（`tokenize='trigram'`）；`rag_chunk` 按 400 字确定性切块同步写入（`rag_embedding` 预留，待 embedding 来源接入） |
| 查询 | 查询 ≥3 字走 FTS5 `MATCH`（`ORDER BY rank`）；<3 字走 `LIKE` 子串 fallback（trigram 限制） |
| 写入 | `KnowledgeUnitWriteService` 四条写路径（`create` / `update` / `createWithCommitKey` / `updateWithCommitKey`）统一在事务提交后尽力同步索引；失败只告警，不阻塞主写 |
| 证据注入 | `NoteEvidenceService.queryHits` 优先本地检索 → join `knowledge_unit` 补 version → `NoteEvidenceCitation`；本地不可用/无命中回退既有 `note_query_rag` 工具 |
| 生成注入 | `DraftPipeline.generateNoteDraftWithSources` 取 topK=2 相关旧笔记（clip 400 字）作为 `existing_note` SourceFragment 注入 |
| 受限 Kit | `@kit.DataAugmentationKit` 只允许在 entry UI 进程使用（红线 11）；Kit 探针独立为 `RagKitProbe.ets`，生产检索链路不 import 该 Kit |

## 备选方案与取舍

| 方案 | 结论 | 原因 |
|---|---|---|
| A. DataAugmentationKit `retrieval` 直接作检索通道 | **暂不采用（保留为可选加速通道）** | 真机 `getRetriever` 14ms 成功，但 `retrieveRdb` 两种参数档均报 `1021201002 数值参数越界`，根因未定位；不让未稳定能力阻塞主链路 |
| B. `@hms.data.rag` / `localChatModel` 端侧生成 | **不采用** | 端侧模型在手机/平板不可用（历史真机 false），且会改变现有云端 LLM + 引用校验链路 |
| C. 继续只用 MCP `note.search` | **不采用（保留为 fallback）** | 依赖工具层与外部进程，延迟不可控；且无法在生成侧直接拿到稳定片段 |
| D. 本机 FTS5（本 ADR 采用） | **采用** | 无外部依赖、真机已验证（97 条回填、查询 17ms、证据 20ms/7 引用）、可精确控制写入同步与降级 |

## 后果

**正面**

- RAG 链路完全可控：索引格式、查询策略、降级行为都在仓库内；
- 生成/对话/复习三处注入复用同一检索与引用校验，引用可溯源（ADR-0018）；
- 真机已验证：`连续性` FTS 5 命中、`极限` LIKE 5 命中、`ragChunks=4 / ftsRows=98` 写同步、幂等提交重复确认不双写。

**负面 / 约束**

- trigram 对 **2 字查询无效**，必须保留 LIKE fallback；英文/数字混合查询行为需按 trigram 规则理解；
- 中文分词质量依赖 trigram（无词边界），排序质量弱于专业分词；后续可在 `rag_chunk` 上接入切词或向量通道提升；
- 索引写入在事务提交后执行，极端情况下（崩溃）可能出现短暂不一致；已由「查询失败降级 + 迁移回填」兜底；
- `rag_embedding` 一期为空，向量检索不可用。

## 验证

| 项 | 证据 |
|---|---|
| 设备 | 3XTYD24C16203663（MRO-W00 / HarmonyOS 7.0.0） |
| 迁移回填 | 97 条历史笔记 → `note_fts` |
| 检索 | `e2e=ragSearch`：`q=连续性` hits=5 / `q=极限` hits=5 / 17ms |
| 证据注入 | `stage=rag-evidence citations=7 degraded=0 contextChars=1603` / 20ms |
| 写同步 | `stage=rag-index ragChunks=4 ftsRows=98`（新写 1 条笔记后） |
| 生成注入 | `e2e=draft` 生成 + 确认通过（draft 8.9s / confirm 1.2s） |

## 未来工作（触发条件）

1. **Kit `retrieveRdb` 错误定位后**：可在 `RagRetrievalService` 后加一个可选通道，仍以本地 FTS5 为基线；
2. **接入 embedding 来源后**：写 `rag_embedding`，检索改「FTS + 向量」混合排序；
3. **检索质量不足时**：评估 `knowledgeProcessor` 切词或接入第三方分词。
