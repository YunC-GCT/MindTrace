# Ticket 021 — Knowledge Graph 独立边表与 RAG 存储预留

> **Status**: implemented on `feature/knowledge-graph-rdb` (2026-09-17)
> **Source**: [`../adr/0006-knowledge-model-decomposition-plan.md`](../adr/0006-knowledge-model-decomposition-plan.md) · [`015-knowledge-model-decomposition-v2.md`](./015-knowledge-model-decomposition-v2.md)
> **Files affected**: `common/src/main/ets/DatabaseHelper.ets`, `common/src/main/ets/Index.ets`, `common/src/main/ets/models/KnowledgeGraphModels.ets`, `entry/src/main/ets/database/NoteDao.ets`, `entry/src/main/ets/database/KnowledgeRelationDao.ets`, `entry/src/main/ets/database/RagEmbeddingDao.ets`, `entry/src/main/ets/services/KnowledgeRelationService.ets`, `entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets`
> **Test files**: `scripts/arkts-lint/tests/knowledge-graph-rdb.test.mjs`

## Why this ticket

当前 `KnowledgeUnit` 使用 `prerequisites` 和 `related` 数组承载知识关系。数组适合兼容旧详情模型，但不适合表达关系来源、LLM 置信度、审核状态、关系原因和版本，也无法支持关系单独查询。

本 ticket 将知识关系拆成独立的 `kg_edge` 表，并为后续 RAG 的 chunk 与 embedding 存储预留 RDB 结构。当前目标是完成可演示的持久化基础，不提前引入 embedding 生命周期或向量检索实现。

## What we will build

### Knowledge graph relation model

共享模型新增：

```ts
KnowledgeRelation {
  id: string
  fromUnitId: string
  toUnitId: string
  relationType: 'prerequisite' | 'related' | 'derived'
  source: 'manual' | 'llm' | 'legacy'
  status: 'pending' | 'accepted' | 'rejected'
  confidence: number
  weight: number
  reason: string
  createdAt: number
  updatedAt: number
  version: number
}
```

方向约定：

- `prerequisite` 是有向关系：`前置知识点 -> 当前知识点`。
- `related` 是无门槛关联，保存前后 ID 排序后的单条边，避免 A→B 与 B→A 重复。
- `derived` 保留为后续图谱推导关系类型，本 ticket 不实现自动推导。

### `kg_edge` table

数据库 schema version 从 9 升到 10，新增：

```sql
CREATE TABLE IF NOT EXISTS kg_edge (
  id TEXT PRIMARY KEY,
  from_unit_id TEXT NOT NULL,
  to_unit_id TEXT NOT NULL,
  relation_type TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'manual',
  status TEXT NOT NULL DEFAULT 'accepted',
  confidence REAL NOT NULL DEFAULT 1.0,
  weight REAL NOT NULL DEFAULT 1.0,
  reason TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  version INTEGER NOT NULL DEFAULT 1
)
```

索引：

- `from_unit_id`
- `to_unit_id`
- `status`
- `(from_unit_id, to_unit_id, relation_type)` 唯一索引

升级时只创建表和索引，不执行旧数组回填。`kg_edge` 从空表开始。

### Unified relation write flow

手动关联和 LLM 推荐共用 `KnowledgeRelationService`：

```text
手动关联 ─┐
          ├─> KnowledgeRelationService
LLM 推荐 ─┘          │
                    v
             KnowledgeRelationDao -> kg_edge
```

写入规则：

- 手动关联：`source = manual`, `status = accepted`。
- LLM 推荐：`source = llm`, `status = pending`。
- 用户确认：`pending -> accepted`。
- 用户拒绝：`pending -> rejected`。
- 空 ID、自环关系直接拒绝。
- 新建/编辑关系只写 `kg_edge`，不再把关系写回 `KnowledgeUnit.prerequisites/related`。

### Relation queries

`KnowledgeRelationDao` 提供：

```ts
queryAcceptedEdges(): Promise<KnowledgeRelation[]>
queryPendingRelations(): Promise<KnowledgeRelation[]>
queryByUnitId(unitId: string): Promise<KnowledgeRelation[]>
acceptRelation(id: string): Promise<boolean>
rejectRelation(id: string): Promise<boolean>
```

其中 `queryByUnitId` 同时查询出边和入边，供关系详情和后续小艺只读图谱能力使用。

### Galaxy graph query

`NoteDao.queryAllGraphMetadata()` 只读取星系页面需要的元数据，不加载：

- `knowledge_unit.content`
- `knowledge_unit.embedding`

`KnowledgeGalaxyViewModel` 加载流程改为：

```text
queryAllGraphMetadata()
        +
queryAcceptedEdges()
        ↓
构建星系节点与关系线
```

生产图谱关系线只消费 `kg_edge` 中的 accepted 边。`prerequisites/related` 仍保留在 `KnowledgeUnit` 及 revision 表中，供旧详情页面和旧数据结构兼容；它们不再是新关系写入或生产图谱读取的事实源。

### RAG storage reservation

新增：

```sql
CREATE TABLE IF NOT EXISTS rag_chunk (
  id TEXT PRIMARY KEY,
  unit_id TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL,
  content_hash TEXT NOT NULL DEFAULT '',
  token_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
```

```sql
CREATE TABLE IF NOT EXISTS rag_embedding (
  id TEXT PRIMARY KEY,
  chunk_id TEXT NOT NULL,
  provider TEXT NOT NULL DEFAULT '',
  model TEXT NOT NULL DEFAULT '',
  dimension INTEGER NOT NULL DEFAULT 0,
  metric TEXT NOT NULL DEFAULT 'cosine',
  vector_json TEXT NOT NULL DEFAULT '[]',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
```

当前演示格式：

```json
[0.0123, -0.8841, 0.3312, 0.9011]
```

写入 `rag_embedding.vector_json TEXT`。`RagEmbeddingDao` 只提供 demo 保存和按 `unit_id` 联表读取，用于确认表结构和 JSON 向量格式。

## Public surface change

新增 common 导出：

- `KnowledgeRelation`
- `KnowledgeRelationType`
- `KnowledgeRelationSource`
- `KnowledgeRelationStatus`
- `RagChunk`
- `RagEmbedding`

新增 entry 服务/DAO：

- `KnowledgeRelationDao`
- `KnowledgeRelationService`
- `RagEmbeddingDao`

保留不变：

- `KnowledgeUnit.prerequisites`
- `KnowledgeUnit.related`
- `KnowledgeUnit.embedding`
- 旧 `NoteDao` 的完整知识点查询和详情渲染契约

本 ticket 不改旧数组字段的数据库定义，也不删除旧 embedding 字段。

## Migration (atomic commits)

1. **`feat(common): add graph edge and rag reservation tables`** — schema version 10、`kg_edge`、`rag_chunk`、`rag_embedding` 及索引。
2. **`feat(entry): add unified relation persistence flow`** — 关系模型 DAO、手动/LLM 统一服务和状态查询。
3. **`feat(entry): read galaxy graph from accepted edges`** — 图谱轻量元数据查询和星系关系线切换到 `kg_edge`。
4. **`test(arkts-lint): cover graph and rag storage contracts`** — 增加结构级测试。
5. **`docs(specs): document graph edge and rag storage boundary`** — 添加本 ticket 工作文档并更新索引。

## Test plan (TDD)

| Class | New tests | What each verifies |
|---|---:|---|
| `DatabaseHelper` | 2 | schema version、`kg_edge` 字段/唯一索引、RAG 两张表、JSON 向量字段，以及不执行旧数组回填 |
| `KnowledgeRelationService` | 1 | 手动 accepted、LLM pending 共用写入流程，related 去重和非法关系约束 |
| `KnowledgeRelationDao` | 1 | accepted、pending、按知识点关系单独查询接口存在 |
| `KnowledgeGalaxyViewModel` | 1 | 图谱使用轻量元数据和 accepted 边表，不再从持久化数组生成关系 |
| `RagEmbeddingDao` | 1 | demo 向量以 JSON 文本保存，不引入生命周期或相似度检索 |

结构级测试文件：

```text
scripts/arkts-lint/tests/knowledge-graph-rdb.test.mjs
```

## Reversibility

**Medium**。回退代码可以停止新关系和 RAG demo 写入，但数据库表会保留在本地数据库中。若要彻底删除表，需要单独的数据库清理/迁移版本，不作为本 ticket 的回退动作。

## Acceptance criteria

- [x] 新增独立 `kg_edge` 表及 from/to/status/type/source/confidence 等字段。
- [x] `kg_edge` 从空表开始，不执行旧 `prerequisites/related` 迁移。
- [x] 手动关联和 LLM 推荐通过同一 `KnowledgeRelationService`。
- [x] 手动关系默认 accepted，LLM 推荐默认 pending，并支持确认/拒绝。
- [x] 提供 accepted、pending、按知识点的关系单独查询。
- [x] `KnowledgeGalaxyViewModel` 优先读取 `kg_edge`，旧数组仅作为兼容字段保留。
- [x] 新增 RAG chunk/embedding 预留表，向量使用 demo JSON 文本格式。
- [x] 本 ticket 不实现 embedding 生命周期、后台生成、重试、模型切换或向量检索。
- [x] `npm --prefix scripts/arkts-lint test` 通过。
- [ ] hvigor/Hypium/真机验证：当前环境无 `hvigorw` 或 `hvigor` 命令，未执行。

## Out of scope (intentionally)

- 旧 `prerequisites/related` 数组到 `kg_edge` 的历史数据迁移。
- 删除或重命名 `KnowledgeUnit.prerequisites/related` 兼容字段。
- embedding 自动生成、更新、失效、重试、删除和模型生命周期。
- 向量数据库、RDB 原生 vector 类型、向量索引和余弦相似度检索。
- LLM 推荐结果的完整生成编排和 UI 审核页面。
- `derived` 关系的自动推导。
- 真机数据库升级和性能基准。

## Open questions (none blocking)

- 后续接入真实 embedding 时，是否将 `vector_json` 替换为二进制 blob 或外部向量索引。
- 关系是否需要增加用户/租户隔离字段。
- 知识点删除时，是否级联删除 `kg_edge`、`rag_chunk` 和 `rag_embedding`。

## Sequencing note

本 ticket 为后续知识图谱 UI 关系编辑、LLM 推荐审核和 RAG 检索提供持久化边界。后续实现应继续把关系写入 `kg_edge`，不要重新维护 `KnowledgeUnit.prerequisites/related` 作为第二套事实源。
