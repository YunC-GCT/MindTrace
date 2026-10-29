---
name: 增量式可验证笔记生成
概要: 在现有 ConversationWorkflow → Dispatcher → CaptureGraph → KnowledgeModel → TruthCheck → NoteDaoAdapter 单后端链路上，增加分层路由、结构优先长文处理、证据化记忆提取、受限迭代、候选检查点、预览确认和持久化后增量重生成；不引入第二套后端或新运行时。
todos:
  - id: contract-and-spec
    content: 固化领域模型、稳定测试 seam 和架构约束，新增规格并澄清领域检查点不等于 StateGraph runtime checkpoint
    status: pending
  - id: generation-storage
    content: 新增生成 run、source、checkpoint、revision 的 RDB 表、DAO 和仓库，并建立幂等迁移
    status: pending
  - id: typed-source-memory
    content: 将笔记记忆读取从 32000 字符平铺文本升级为带来源 ID、顺序和指纹的 SourceBundle
    status: pending
  - id: note-generation-workflow
    content: 在 KnowledgeModel 的 Structure 职责内接入独立 NoteGenerationWorkflow，完成轻量/标准/深度路由和结构优先生成
    status: pending
  - id: verification-loop
    content: 实现证据提取验证、过程门禁、JSON Schema、受限修复、递减收益检测和最佳检查点回滚
    status: pending
  - id: dispatcher-draft-commit
    content: 扩展 Dispatcher 单入口支持生成草稿和提交已确认候选，所有 KnowledgeUnit 写入继续经过 TruthCheckNode 与 PersistNode
    status: pending
  - id: preview-confirmation
    content: 原子切换 Conversation 笔记分支为草稿预览/确认保存，删除旧的二次摘要后立即入库路径
    status: pending
  - id: incremental-regeneration
    content: 支持基于已保存版本和新要求只重生成受影响章节，保留用户编辑并用乐观锁提交新 revision
    status: pending
  - id: full-verification
    content: 完成 ArkTS 检查、行为测试、迁移测试、完整构建与真机生成/取消/更新/回滚验收
    status: pending
---

# 增量式可验证笔记生成实施方案

## Goal

在不推翻现有 Agent workflow 架构的前提下，把当前“完整会话 → 一次摘要 → 再次 Structure → 立即持久化”的有损路径升级为可落地的增量生成系统：

- 简单材料走轻链路，复杂或长材料才进入结构优先的深链路。
- 记忆先提取为可追溯证据，再经过迭代验证，不把未经证实的摘要直接当事实。
- 每个阶段执行显式不变量检查；分数只用于观测和候选比较，不能代替过程门禁。
- 修复循环有轮数、token、无进展和重复问题上限；恶化时回滚到最佳候选检查点。
- 所有 LLM 结构化输出受 JSON Schema 和显式 ArkTS 领域校验共同约束。
- AI 生成结果先形成可恢复草稿并由用户预览，确认后才写入 `knowledge_unit`。
- 已保存笔记可基于新要求只重生成受影响章节，保留用户修改、版本历史和来源映射。

采用当前业界成熟的组合模式：层级式 outline-first 长文生成、evidence ledger、generator/verifier 分离、bounded evaluator-optimizer loop、immutable best-checkpoint、strict structured output、optimistic concurrency 和 revisioned artifacts。

## Scope / Non-goals

### Scope

1. 对话与图片待整理材料生成笔记。
2. 短材料、普通会话、长会话和证明/推导类材料的分层处理。
3. 生成草稿、预览编辑、确认创建、取消草稿。
4. 已保存 AI 笔记的定向增量重生成与版本冲突处理。
5. 生成过程、来源、检查点、验证报告和持久化 revision 的存储。
6. 与现有 MM-MD-v1、KnowledgeUnit、复习状态、知识图谱字段和卡片刷新兼容。

### Non-goals

- 不引入 Python、LangGraphJS、LangChain runtime 或远程 sidecar。
- 不建立新旧笔记生成双轨、feature flag、shadow run、双读或双写。
- 不创建第二套 KnowledgeUnit DAO；`NoteDao` 仍是唯一 RDB 实现。
- 不开放写类 AgentTool；增量重生成仍由 Conversation/笔记详情 UI 触发。
- 不实现无界自主循环、并行 fan-out、通用多智能体辩论或后台自动续跑。
- 不把本次候选检查点实现为 StateGraph runtime Checkpoint/Interrupt；预览确认是两个持久化的业务 run。
- 不重做笔记详情的视觉体系；只增加草稿、差异、验证状态和确认动作。

## Current State And Constraints

- 当前生产链路是 `ConversationWorkflow → ReplyService.summarizeNoteMaterial → AiService.captureText → Dispatcher.dispatch → CaptureGraph → KnowledgeModel → TruthCheckNode → PersistNode → NoteDaoAdapter`。
- `ReplyService` 先把会话压缩成文本，随后 `TypeClassifier.preprocessText` 还可能把 Structure 输入截到约 6000 字符；这是内容不充分的主要损失点。
- `AgentMemoryService.getContextForNoteGeneration()` 把 summary、pending material 和最近 100 条消息平铺并最终截到 32000 字符，来源 ID、精确顺序和引用关系丢失。
- `KnowledgeModel` 是唯一 Structure owner；`TruthCheckNode` 是唯一 TruthCheck 生产调用点；`Dispatcher.dispatch` 是 Capture 唯一公开入口。
- `persist:false + analysisOnly:false` 已能完成 Structure/TruthCheck 并返回未写库的 `KnowledgeUnit`，可作为草稿生成基础。
- 当前 `KnowledgeUnit` 有 `version`，但 `NoteDao.update()` 仅按 ID 更新，没有乐观锁；也没有 revision、草稿、来源或检查点表。
- `NoteDetailOverlay` 已支持标题、摘要、正文和标签编辑，但 `isCreating` 只创建空白手工笔记，不能载入 AI draft。
- 当前工作树已有大规模未提交 workflow 改造。实施时必须先读取最新文件和 diff，不得 reset、覆盖或夹带无关改动；除非用户明确要求，不 commit、不 push。
- 所有 `.ets` 改动遵守 ArkTS 1.1 strict：显式命名接口、无 `any/unknown`、无解构、无动态对象布局、State 字段逐项复制、跨模块完整导入。

## Design

### 1. 保持单后端，新增一个 Structure 内部领域 workflow

新增 `NoteGenerationWorkflow`，但不新增公开后端：

- 外部仍只调用 `Dispatcher.dispatch`。
- CaptureGraph 仍负责 Capture、Classify、Structure、TruthCheck、Persist。
- `StructureNode` 把可选的 `NoteGenerationRequest` 传给 `KnowledgeModel`。
- `KnowledgeModel` 保持 Structure owner；复杂生成委托其内部的 `NoteGenerationWorkflow.run(request)`，普通 OCR/text Structure 仍走同一实现入口。
- `NoteGenerationWorkflow` 使用现有 `StateGraph<State, Step>`，拥有独立 State，不复用或扩张为超级 `AgentState`。
- Conversation 只负责收集用户要求、调用 Dispatcher、展示结果，不复制生成、检查或持久化逻辑。

这满足“多个 workflow、一个生产后端”：新 workflow 是 Structure 的深实现，不拥有 LLM transport、TruthCheck 或 DAO。

### 2. 类型化生成契约

在 common 新增命名类型，禁止用大段字符串隐式传协议：

- `NoteGenerationRequest`
  - `mode: create | regenerate`
  - `runId/sessionId`
  - `requirement`
  - `sources: SourceFragment[]`
  - 可选 `baseUnit/baseRevisionManifest`
- `NoteRequirement`
  - 原始 `instruction`
  - `detailLevel: concise | standard | detailed`
  - `mustInclude[]/mustAvoid[]`
  - `targetSectionIds[]`
  - `preserveUserEdits`
- `SourceFragment`
  - 稳定 `id`、`kind`、原始记录 ID、顺序、文本、非安全用途稳定指纹
- `EvidenceItem`
  - `claim | formula | step | example | definition`
  - 目标章节、来源引用、证据片段、验证状态
- `NoteDraftDocument`
  - 标题/摘要/标签/Subject/NoteType/Chapter/Difficulty
  - 稳定 `sections[]`，每节含 `sectionId/key/label/content/sourceRefs/locked/baseHash`
- `ProcessIssue`
  - 阶段、错误码、`hard | soft`、关联来源/章节、是否可修复
- `VerificationReport`
  - schema/invariant 结果、显式 issue 列表、must-include 覆盖、证据覆盖、跨章节一致性
- `NoteGenerationCheckpoint`
  - parent、迭代号、候选文档、证据、验证报告、指标、是否被接受
- `NoteGenerationResult`
  - route、status、best checkpoint、候选 `KnowledgeUnit`、manifest、未解决项和 stop reason

生成模型中使用 `noteType` 表达五类语义，最后兼容映射到现有 `KnowledgeUnit.category` 字段，避免继续扩大 category/Subject 歧义。

### 3. 记忆提取与迭代验证

把 `AgentMemoryService.getContextForNoteGeneration()` 的平铺文本改为新增的类型化 `getNoteSourceBundle()`；旧 reply context 不受影响。

来源顺序：

1. 用户本轮生成/更新要求。
2. 未消费的 OCR/pending material，保留 memory row ID 和图片来源。
3. 按时间顺序的原始 user/assistant 消息。
4. session summary 只作为检索导航和缺失上下文补充，不能覆盖原始消息事实。
5. regenerate 时加入当前 KnowledgeUnit、最近 revision manifest 和用户手改章节。

Evidence 提取采用“提取 → 确定性验证 → 独立 verifier → 只重提失败项”：

1. `extract_evidence` 把来源拆成原子定义、公式、步骤、例子和结论，每项必须声明 source reference 和目标章节。
2. 本地验证 source ID 存在、证据片段可在规范化源文本中定位、公式未丢失、顺序合法、must-include 有映射。
3. verifier 使用与 generator 分离的提示词，只判断 `supported/contradicted/ambiguous` 并返回明确 issue，不输出笼统总分。
4. 仅对 contradicted、ambiguous 和覆盖缺口重提；已验证 EvidenceItem 冻结，不重复消耗 token。
5. 如果缺少用户才能提供的信息，进入 `needs_input`，返回问题列表，不编造、不持久化。

日志只记录 run ID、阶段、数量、字符数、issue code 和 token 统计，不记录正文、证据片段或凭据。

### 4. 分层路由与结构优先长文策略

`NoteGenerationPolicy` 使用确定性信号先路由，并把选择写入 run 以便复现：

| Route | 典型条件 | 生成策略 | 默认修复上限 |
|---|---|---|---|
| light | 单主题、来源不超过约 6000 字符、无复杂推导/OCR 歧义、用户未要求详细 | Evidence 单轮提取，直接生成完整 Draft，本地门禁；有硬问题时最多升级一次 | 1 |
| standard | 普通多轮会话、约 6000–32000 字符、包含公式/例子或明确完整性要求 | Outline → Evidence → 整体 Draft → 验证/定向修复 | 2 |
| deep | 超过约 32000 字符、多主题、证明/长推导、多个 OCR 材料、明确“完整/详细”或 regenerate 跨章节 | 语义分段 → 层级 Outline → 来源到章节映射 → 逐章节生成 → 全局一致性检查 | 4 |

具体阈值集中在一个 policy 中并可测试，不散落在 Node。

长文不再先做通用摘要，也不在进入 Outline 前静默截断：

- 按消息、OCR 页、标题、公式块和题目边界做语义分段，而非固定字符切块。
- 先生成稳定 section ID 的 Outline 和 source-to-section plan。
- 每个章节只读取相关原始 SourceFragment 和共享 formula/glossary ledger。
- deep 路径通过 `draft_section` 自循环顺序生成章节，避免并发章节使用不同术语或结论；不需要 TaskPool。
- 合并后执行跨章节重复、矛盾、引用、公式符号和 must-include 检查。
- 超过配置的总来源预算时进入 `needs_input` 请求用户缩小范围，禁止静默丢尾部。

### 5. NoteGenerationWorkflow State、Node 与 Edge

State 只保存领域数据，不保存 UIAbilityContext、DAO、callback 或 LlmClient：

- request、route、policy budget
- outline、evidence ledger、current section index
- current draft、verification report
- checkpoints、best checkpoint ID
- repair round、token usage、issue fingerprints
- stop reason、error、current step

推荐拓扑：

```text
START → route
route → extract_evidence                         (light)
route → build_outline → extract_evidence         (standard/deep)
extract_evidence → verify_evidence
verify_evidence → repair_evidence → verify_evidence   (可修复且有预算)
verify_evidence → draft_document                      (light/standard)
verify_evidence → draft_section ↺                    (deep，逐章节)
draft_document / draft_section完成 → verify_draft
verify_draft → finalize                              (全部硬门禁通过)
verify_draft → repair_draft → verify_draft            (仍有收益和预算)
verify_draft → rollback_best                         (递减收益或预算耗尽)
rollback_best → finalize                             (最佳候选无硬错误)
rollback_best → needs_input                          (最佳候选仍有硬错误)
finalize / needs_input → END
```

共享 StateGraph 的 `maxNodeRuns` 继续作为最后保险；业务循环由 route policy 的 repair/token budget 控制。

### 6. 过程验证，而非只做输出评分

每个阶段都返回可执行门禁：

- source gate：来源非空、顺序稳定、无重复 ID、无静默截断。
- outline gate：每个 must-include 有章节落点，重要来源没有 orphan，section ID 唯一。
- evidence gate：来源存在、证据可定位、公式/步骤保持、无 contradicted item。
- draft gate：JSON Schema、领域字段、NoteType 标准章节、MM-MD-v1、公式语法、来源覆盖、无 unsupported claim。
- merge gate：锁定章节字节不变、目标章节才发生变化、全局术语/符号一致。
- final TruthCheck gate：`TruthCheckNode` 接收 capture text、KnowledgeUnit 和可选 generation report，成为写库前唯一最终裁决点。
- commit gate：run/checkpoint/hash 一致、用户已确认、base version 未变化。

`coverage` 等数值只用于展示、遥测和最佳候选比较。任何 schema error、contradiction、must-include 缺失、锁定章节变化或版本冲突都属于 hard issue，不能被平均分抵消。

### 7. 受限迭代、递减收益与检查点回滚

每次 schema-valid 候选产生不可变 checkpoint。最佳候选按以下词典序选择，而非单一总分：

1. schema/hard issue 是否为零。
2. contradicted/unsupported 数量是否更少。
3. must-include 覆盖是否更高。
4. Evidence 覆盖是否更高。
5. 是否保持锁定章节不变。
6. 前述相同时选择 token 成本更低、改动范围更小的候选。

递减收益默认规则：连续两轮同时满足“hard issue 未减少、must-include 覆盖提升小于 0.02、Evidence 覆盖提升小于 0.02”，或 issue fingerprint 重复，即停止修复；不得继续烧 token。

停止后的处理：

- best checkpoint 无 hard issue：回滚到 best，带 soft warning 进入预览。
- best checkpoint 仍有 hard issue：进入 `needs_input`，不构造 fallback KnowledgeUnit。
- 达到 route repair 上限、总 token 预算或 StateGraph 节点上限：同样执行 best-checkpoint 判断。
- 新候选比 best 更差时仍可记录为 rejected checkpoint，但不替换当前 best。

这些是 NoteGeneration 领域检查点，不修改 StateGraph runtime，也不保持一个跨 UI 生命周期悬挂的图。

### 8. JSON Schema 约束

为以下 LLM 输出建立版本化 JSON Schema：Requirement、Outline、EvidenceLedger、DraftDocument、VerificationReport、RepairPatch。

约束规则：

- `required` 列全字段，`additionalProperties: false`。
- route、NoteType、issue severity/status 使用 enum。
- 数组设置合理 `minItems/maxItems`，字符串限制空值和最大长度。
- section/source/evidence 使用稳定 ID；RepairPatch 只能引用已存在 section ID。
- RepairPatch 表达“替换哪个章节/字段”，禁止模型返回整篇自由文本覆盖锁定内容。

扩展 `LlmCallRequest/LlmGuard`：

- 已知 provider 支持 strict structured output 时发送 `json_schema` response format。
- custom/不支持 provider 继续使用同一 `LlmClient` 的 `json_object` transport，但把同一 schema contract 注入提示词并执行本地 schema subset 校验。
- provider 能力由 `ProviderConfig` 声明，custom 默认 false；不得靠失败后切换另一后端。
- JSON Schema 只保证形状；NoteType 字段集、Evidence 真伪、MM-MD-v1、公式和业务不变量继续由显式 ArkTS validator 判断。
- schema/领域校验失败时，`LlmGuard` 的 repair prompt 只携带错误列表和无效 JSON，避免每轮重复发送全部长文。

### 9. 草稿、预览、确认和精确持久化

生成与提交拆成两个 Dispatcher run，不保持 runtime Interrupt：

1. Conversation 组装 `NoteGenerationRequest`。
2. `AiService.generateNoteDraft()` 调用 `Dispatcher.dispatch`，设置 `persist:false`。
3. CaptureGraph 完成 Structure 和最终 TruthCheck，返回 `NoteGenerationResult` 与候选 KnowledgeUnit。
4. entry 把 run、sources 和 checkpoints 写入生成 artifact 表，状态为 `ready_preview`。
5. Conversation 通过 typed event 只传 `runId` 和预览摘要；`ConversationState` 可增加 `noteRunId/draftStatus`，不塞入服务实例或大对象。
6. `AgentFloatWindow` 打开现有 `NoteDetailOverlay` 的 generated-draft 模式，预填候选并展示未解决 soft issues、来源数和变更章节。
7. 用户可编辑；编辑形成 `user_edit` checkpoint，改动章节默认标记 locked。
8. 用户确认后，`AiService.commitNoteDraft(runId, checkpointId)` 加载精确候选，通过 `Dispatcher.dispatch` 的 prepared-unit payload 再执行最终 TruthCheck → Persist。
9. 成功后才更新 notesVersion、缓存/卡片，并按 source ID 标记本次真正消费的 pending material；取消则保持 pending material 未消费。

扩展 `DispatchPayload` 增加严格区分的 `note_generation` 和 `prepared_unit` 形状。prepared-unit 路由不得重新调用 KnowledgeModel，避免用户预览内容和最终入库内容不同；但必须重新执行最终 TruthCheck 和 commit gate。

### 10. 唯一写入 owner、事务与 revision

新增 entry-side `KnowledgeUnitWriteService` 作为唯一写入协调模块：

- `NoteDaoAdapter` 委托它处理 AI create/update。
- `NoteEditService` 也委托它处理手工编辑，消除验证、缓存和卡片副作用分散。
- `NoteDao` 仍是唯一 `knowledge_unit` RDB 实现。
- `PersistNode` 仍是 AI KnowledgeUnit 写入唯一 workflow Node。

将 `NoteDaoInterface` 收敛为类型化 save command：create/update、expectedVersion、run/checkpoint metadata。更新时使用 `id + expectedVersion` predicate 并检查受影响行数；冲突返回 `VERSION_CONFLICT`，不覆盖新版本。

一次确认提交在同一 RDB transaction 中完成：

1. 校验并 create/update `knowledge_unit`。
2. 插入不可变 `note_revision` 快照。
3. 将 generation run 标记为 saved 并关联 note/version。
4. commit；任一步失败 rollback。

事务完成后再做 cache invalidation、notesVersion 和 card snapshot 刷新。副作用失败记录为可恢复警告，不能把已提交事务误报为未保存。

### 11. RDB 增量表设计

保持现有 `knowledge_unit` 结构和查询兼容，只把生成元数据放入旁表；数据库版本从 4 递增并通过 `CREATE TABLE IF NOT EXISTS`/索引做幂等迁移。

- `note_generation_run`
  - run/session/target note/base version、route/status、instruction、requirement JSON、best checkpoint、stop reason、时间。
- `note_generation_source`
  - source ID、run ID、kind、origin ID、sequence、fingerprint、原始文本。
- `note_generation_checkpoint`
  - checkpoint/parent/run、iteration/stage、DraftDocument/Evidence/Verification/Metrics JSON、accepted/rejected、时间。
- `note_revision`
  - revision ID、note ID、note version、run/checkpoint、KnowledgeUnit JSON、generation manifest、用户要求、changed section IDs、时间。

为 run status、target note/version、source run/sequence、checkpoint run/iteration 和 revision note/version 建索引。来源快照和 generation metadata 不放入 `KnowledgeUnit.content`，避免列表/复习读取膨胀。

### 12. 持久化后的增量重生成

从笔记详情增加“AI 增量完善”动作，或由 Conversation 在明确选中 note ID 后发起；不得根据模糊标题静默猜目标笔记。

1. 加载当前完整 KnowledgeUnit、最新 revision manifest 和 base version。
2. 将新 instruction 解析为 target sections/must-include/detail level。
3. 对当前 content 按稳定 section ID 解析；与上次生成 hash 不同的章节视为用户编辑并默认 locked。
4. `ChangePlanner` 只选择受新要求影响的章节；未选中和 locked 章节原样复制。
5. 只为目标章节读取相关旧 Evidence 和新增 SourceFragment；需要新证据时增量提取并验证。
6. 生成 RepairPatch 或 replacement sections，合并后执行 changed-section gate 与全局一致性 gate。
7. 预览展示新增/修改/保持章节，不立即写库。
8. 确认时以 `expectedVersion` 更新；冲突时加载最新版本重新规划并要求再次预览。
9. 成功后写入新 revision，`version + 1`；保留 reviewStatus、复习计划、关系字段和 createdAt，更新 updatedAt；正文变化时清空待重建 embedding，不能沿用旧向量。

旧的 revision 和 generation source 保留用于后续定向重生成和审计；默认 UI 不要求实现完整历史浏览，但仓库接口必须支持按 note/version 查询。

## Key Files

### 现有核心文件

- [docs/specs/018-agent-workflow-architecture.md](../../../specs/018-agent-workflow-architecture.md)
- [docs/adr/0008-capturegraph-self-built-runtime.md](../../../adr/0008-capturegraph-self-built-runtime.md)
- [entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets](../../../../entry/src/main/ets/workflows/conversation/ConversationWorkflow.ets)
- [entry/src/main/ets/workflows/conversation/ConversationState.ets](../../../../entry/src/main/ets/workflows/conversation/ConversationState.ets)
- [entry/src/main/ets/services/AgentMemoryService.ets](../../../../entry/src/main/ets/services/AgentMemoryService.ets)
- [entry/src/main/ets/services/ReplyService.ets](../../../../entry/src/main/ets/services/ReplyService.ets)
- [entry/src/main/ets/services/AiService.ets](../../../../entry/src/main/ets/services/AiService.ets)
- [agents/src/main/ets/core/Dispatcher.ets](../../../../agents/src/main/ets/core/Dispatcher.ets)
- [agents/src/main/ets/graph/AgentState.ets](../../../../agents/src/main/ets/graph/AgentState.ets)
- [agents/src/main/ets/graph/nodes/StructureNode.ets](../../../../agents/src/main/ets/graph/nodes/StructureNode.ets)
- [agents/src/main/ets/graph/nodes/TruthCheckNode.ets](../../../../agents/src/main/ets/graph/nodes/TruthCheckNode.ets)
- [agents/src/main/ets/graph/nodes/PersistNode.ets](../../../../agents/src/main/ets/graph/nodes/PersistNode.ets)
- [agents/src/main/ets/agents/KnowledgeModel.ets](../../../../agents/src/main/ets/agents/KnowledgeModel.ets)
- [agents/src/main/ets/agents/PromptBuilder.ets](../../../../agents/src/main/ets/agents/PromptBuilder.ets)
- [common/src/main/ets/llm/LlmGuard.ets](../../../../common/src/main/ets/llm/LlmGuard.ets)
- [common/src/main/ets/llm/LlmTypes.ets](../../../../common/src/main/ets/llm/LlmTypes.ets)
- [common/src/main/ets/DatabaseHelper.ets](../../../../common/src/main/ets/DatabaseHelper.ets)
- [entry/src/main/ets/database/NoteDao.ets](../../../../entry/src/main/ets/database/NoteDao.ets)
- [entry/src/main/ets/adapters/NoteDaoAdapter.ets](../../../../entry/src/main/ets/adapters/NoteDaoAdapter.ets)
- [entry/src/main/ets/services/NoteEditService.ets](../../../../entry/src/main/ets/services/NoteEditService.ets)
- [entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailOverlay.ets](../../../../entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailOverlay.ets)
- [entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets](../../../../entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets)

### 建议新增文件

- `docs/specs/019-incremental-note-generation.md`
- [common/src/main/ets/models/NoteGenerationModels.ets](../../../../common/src/main/ets/models/NoteGenerationModels.ets)
- `agents/src/main/ets/workflows/note-generation/NoteGenerationState.ets`
- `agents/src/main/ets/workflows/note-generation/NoteGenerationWorkflow.ets`
- `agents/src/main/ets/workflows/note-generation/NoteGenerationPolicy.ets`
- `agents/src/main/ets/workflows/note-generation/NoteSchemaContracts.ets`
- `agents/src/main/ets/workflows/note-generation/NoteGenerationVerifier.ets`
- `agents/src/main/ets/workflows/note-generation/NoteChangePlanner.ets`
- `agents/src/main/ets/workflows/note-generation/nodes/*.ets`：route、outline、evidence、draft-section、verify、repair、rollback、finalize Node factories。
- `entry/src/main/ets/services/NoteSourceService.ets`
- [entry/src/main/ets/services/KnowledgeUnitWriteService.ets](../../../../entry/src/main/ets/services/KnowledgeUnitWriteService.ets)
- `entry/src/main/ets/services/NoteGenerationRepository.ets`
- `entry/src/main/ets/database/NoteGenerationDao.ets`
- `entry/src/main/ets/database/NoteRevisionDao.ets`

## Execution Sequence

### Slice 1 — 规格、测试 seam 与类型契约

1. 新增 spec 019，并更新 specs index、CONTEXT 和 ADR-0008：说明本次引入的是 NoteGeneration 领域 artifact checkpoint 与两次 run 的预览确认，不是 StateGraph runtime checkpoint/Interrupt。
2. 先确认并锁定行为测试 seam：`Dispatcher.dispatch`、`ConversationWorkflow/AgentChatService`、`NoteGenerationRepository`、`KnowledgeUnitWriteService`；测试不读取私有 Node Map。
3. 新增 `NoteGenerationModels.ets` 和 common export；使用命名接口、判别联合和显式 copy/factory。
4. 增加 source guard，确保 Conversation 不 import CaptureGraph/AgentState，agents 不 import entry，新 workflow 不直接实例化 NoteDao。

### Slice 2 — 存储与版本基础

1. 先写 v4→v5 迁移测试和 DAO round-trip 测试。
2. 在 DatabaseHelper 添加四张旁表和索引，保持 `knowledge_unit` 不变。
3. 实现 NoteGenerationDao、NoteRevisionDao、NoteGenerationRepository。
4. 将 NoteDao update 改为带 expectedVersion 的更新并检查 rows；先覆盖成功和 VERSION_CONFLICT。
5. 新增 KnowledgeUnitWriteService，NoteDaoAdapter 与 NoteEditService 单向委托；事务提交后统一处理缓存、notesVersion 和卡片刷新。

### Slice 3 — 类型化来源和无损记忆输入

1. 为 `AgentMemoryService.getNoteSourceBundle()` 写行为测试：顺序、source ID、pending material、summary 降级、无静默 32000 截断。
2. NoteSourceService 把用户要求、RDB 消息、pending OCR、summary 和 regenerate base 组装成 SourceFragment。
3. 将 pending material 消费从“整个 session 全标记”改为按 source/memory ID 标记。
4. 保留现有 reply context 方法，避免普通聊天上下文膨胀。

### Slice 4 — JSON Schema 与生成 workflow

1. 先以 fake LlmCaller 写 light tracer bullet：短材料生成 schema-valid draft，`persist:false` 不触发 DAO。
2. 扩展 LlmTypes/LlmGuard/provider capability，建立 schema subset + 显式领域 validator。
3. 实现 NoteGenerationPolicy、State、workflow 和 Node；所有 State 更新逐字段复制。
4. 将 KnowledgeModel 的现有 prompt/normalize/content assembly 复用到 DraftDocument → KnowledgeUnit 转换，不能建立第二套 KnowledgeUnit assembler。
5. StructureNode 写入 `knowledgeUnit + generationReport`，TruthCheckNode 保留唯一最终裁决权。

### Slice 5 — 标准/深度路线与受限迭代

1. 用已知长文 fixture 写 outline/source mapping/evidence 测试，再实现 standard/deep。
2. 增加 evidence 本地校验与独立 verifier；只重提 rejected/ambiguous/gap。
3. 实现 deep 逐章节循环和全局一致性 gate。
4. 实现 checkpoint comparator、issue fingerprint、递减收益、token/repair budget 和 rollback。
5. 覆盖 pass、repair-success、diminishing rollback、budget exhaustion、needs-input 五种终止。

### Slice 6 — 原子切换草稿预览和确认提交

1. 扩展 DispatchPayload/AgentState/DispatchResult 支持 note_generation 和 prepared_unit；普通 text/image/file 行为保持不变。
2. AiService 增加 generate draft/commit draft adapter，但仍只调用 Dispatcher。
3. Conversation note branch 改为 typed source → draft → event；同一切片删除 `ReplyService.summarizeNoteMaterial` 和旧的立即 `captureText` 持久化逻辑，禁止双轨。
4. 扩展 ConversationState/callback、ChatModels、AgentFloatWindow 和 NoteDetailOverlay generated-draft mode。
5. confirm 重新经过 Dispatcher final TruthCheck → Persist；cancel 不写 KnowledgeUnit、不消费来源。

### Slice 7 — 持久化后增量重生成

1. 为 section ID/hash、用户改动锁定、target section planner 写纯行为测试。
2. 从详情页传明确 note ID、base version 和新要求；Conversation 模糊指令无法唯一定位时要求用户选择。
3. 只生成目标章节 Patch，合并时断言 locked/untargeted 章节不变。
4. 预览差异后以 expectedVersion 提交；事务中写新 KnowledgeUnit version 和 revision。
5. 覆盖冲突、取消、保留复习状态、清空过期 embedding 和重新生成后再次增量更新。

### Slice 8 — 清理和验收

1. 删除旧平铺摘要生成路径、重复 validator、直接 NoteDao 写入和 session 全量 pending consume。
2. 补齐新 `.ets` 文件头、命名校验、no-BOM 和 Index exports。
3. 执行完整验证矩阵并真机记录 run/route/checkpoint/commit 日志，不打印内容或凭据。

## Verification

| 类别 | 验证内容 | 方法 |
|---|---|---|
| ArkTS 编译前检查 | 所有新增/修改 `.ets` 的 strict 语法、类型、import、State copy | 每批 `.ets` 修改后运行 `arkts_check`；必须零 error |
| Policy 单元测试 | light/standard/deep 路由、升级、budget、递减收益、best checkpoint | Hypium 或可执行 ArkTS 单元测试，使用固定 fixture |
| Schema 单元测试 | required/additionalProperties/enum/section ID/Patch target；schema 通过但领域失败 | 通过 LlmGuard/SchemaGuard 稳定接口测试 |
| Memory 集成测试 | typed source 顺序、来源 ID、OCR、summary 优先级、长文不静默截断、按 ID 消费 | AgentMemoryService/NoteSourceService seam |
| Workflow 行为测试 | light pass、standard 多轮补全、deep section loop、rollback、needs_input | NoteGenerationWorkflow 入口 + fake LlmCaller；不断言私有 Node Map |
| Capture 集成测试 | generate draft 不写库；prepared confirm 精确写入预览候选；TruthCheck 失败不写库 | `Dispatcher.dispatch` + fake NoteDaoInterface |
| Persistence 测试 | v4→v5 数据保留、四表 round-trip、transaction rollback、revision、version conflict | RDB/Hypium 集成测试 |
| Conversation 测试 | 笔记意图只触发一次生成、返回 draft event、取消不保存、确认后才 bump notesVersion | AgentChatService/ConversationWorkflow callback seam |
| Incremental 测试 | 只改目标章节、锁定用户编辑不变、全局校验、base version 冲突、新 revision 可再次生成 | NoteChangePlanner + Dispatcher + repository |
| 架构守门 | 唯一 Dispatcher、KnowledgeModel/TruthCheck/Persist ownership、无第二 DAO/旧生成体 | 扩展现有 `scripts/arkts-lint/tests/` source guards |
| 全量仓库 | 既有 316+ 行为测试、项目 lint、命名、diff | 全量 Node tests、ArkTS lint、naming-lint、diff check 全绿 |
| 完整构建 | common/agents/entry/cardservice/skill 集成 | debug 产品完整 build 成功；既有 deprecated warning 单独记录 |
| 真机短材料 | 问答 → 生成 → 预览 → 编辑 → 确认 → 重启仍存在 | MatePad Pro 13，检查 run/checkpoint/Dispatcher/NoteDao 日志 |
| 真机长材料 | 多消息/公式/证明触发 deep，覆盖要求且无尾部丢失 | 检查 route、section 数、Evidence 覆盖、停止原因 |
| 真机回滚 | 注入重复问题/无改善 fixture，停止并选择 best checkpoint | UI 显示 soft warning 或 needs_input，不无限循环 |
| 真机增量更新 | 给已保存笔记新增例子/推导，只改目标章节并产生新 version | 预览 diff、确认、旧 revision 保留、复习状态不丢 |

验收必须检查外部行为，而不能用“模型返回了一个高分”替代：预览内容、来源覆盖、显式 issue、实际数据库版本和重启后查询结果都要成立。

## Risks And Compatibility

- **Provider JSON Schema 差异**：custom vendor 可能不支持 strict response format。通过 provider capability 决定是否发送 constrained decoding；本地 schema + 领域 validator 永远执行，不切换第二后端。
- **成本与延迟**：deep 按章节可能较慢。通过 light/standard/deep 分层、冻结已验证 Evidence、只修目标章节、总 token budget 和递减收益停止控制成本。
- **长上下文限制**：不能把全量来源一次塞给模型。Outline 和 source-to-section plan 必须先建立，每次只读取相关原文；超预算时显式 needs_input。
- **验证器误判**：verifier 不能拥有最终写入权；本地 hard invariant 与 TruthCheck 才是最终 gate，验证报告保留 evidence 供预览。
- **用户编辑覆盖**：旧自由 Markdown 可能无法完美恢复 section ID。首次 regenerate 需解析章节并与 revision hash 对比；无法可靠映射的内容整体锁定并要求用户选范围。
- **并发更新**：当前 `version` 非真实乐观锁。必须先完成 expectedVersion predicate 和 conflict 行为，再开放 regenerate commit。
- **迁移风险**：旁表迁移必须幂等，先在已有 v4 数据副本验证；新表失败不能破坏现有 knowledge_unit。
- **事务后副作用**：卡片/缓存刷新不得与 RDB 成功混为一谈；提交成功后刷新失败应可重试，不误报保存失败。
- **ArkTS strict**：复杂 schema/State 易诱发动态访问和 object literal 类型问题；采用命名接口、Record 仅用于 JSON seam、显式 factory/copy，并在每个文件修改后运行 `arkts_check`。
- **生命周期**：不承诺应用退后台后继续长 LLM run；run 状态需可恢复，重新进入时显示 failed/incomplete 并允许重试，禁止重复 commit。
- **权限**：不新增系统权限；继续使用现有网络和 RDB 能力。

## Rollback

- 每个 Slice 保持可独立 revert，但生产调用点切换与旧业务体删除必须同一 Slice，绝不保留双轨开关。
- 新增 RDB 表是旁表；回滚代码时不删除表、不触碰现有 `knowledge_unit` 数据，旧版本会忽略旁表。
- 草稿尚未确认时可将 run 标记 cancelled；不会产生 KnowledgeUnit，无数据回滚需求。
- 确认事务失败时由 RDB rollback 保持旧 note/version/revision；不得用补偿式第二次写入。
- 增量更新出现 VERSION_CONFLICT 时保留草稿/checkpoint，重新读取最新 note 并要求再次预览，不覆盖或自动合并。
- 若新生成链路无法通过真机验收，整体 revert Conversation 切换 Slice，恢复此前单链路代码；不要在生产保留 runtime fallback 或 feature flag。
