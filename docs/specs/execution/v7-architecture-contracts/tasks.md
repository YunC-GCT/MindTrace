# v7 契约层与 NoteAgent 迁移 · 任务清单

> 一票一个块，勾选时把证据写进 `verification-record.md`（构建输出、gate 输出、快照文件名、真机截图路径）。
> 顺序按 `plan.md` §2，不要在 #240 结论出来之前动 #241。

## #237 ADR：Subgraph 边界 + NoteCommand / NoteOutcome

- [x] `docs/adr/0019-note-command-and-outcome.md`：`NoteCommand` 五型（capture / generation(mode) / regenerate(range) / preparedCandidate(hash) / analysisOnly）
- [x] `NoteOutcome` 五终态（needsInput / readyPreview / committed(noteId, version) / failed(code, retryable) / cancelled(committed)）
- [x] 错误码表：OCR 失败、分类失败、校验失败、模型不可用（含降级标记）、版本冲突、审批哈希不匹配、取消
- [x] 修订 `docs/adr/0008-*`：新增「Subgraph 放开范围」一节（允许共享 RunContext / 禁止 runtime checkpoint 与图内 HITL）
- [x] §17.5 契约表回填 ADR 编号
- [x] `node scripts/agent-gate/index.mjs --all` PASS（由 #238 切片 A 的 `--all` 覆盖，见下）

## #238 契约层：六个 Port + adapter + 契约测试

- [x] `NoteWritePort`（`commitKey` 必填、`expectedVersion` CAS、`approvedCheckpointHash`、`NotePortError`）— 契约与纯判定在切片 A；**entry adapter 已补**：`NoteWritePortAdapter`（幂等 / CAS / 审批哈希 / 错误分流）+ `NoteWriteStoreDao`（commit 查 `note_generation_commit`，写走 NoteDao 事务）。**已知缺口**：`approvedCheckpointHash` 没有任何持久化列，带哈希的写入会被安全拒绝；放行需先定存储位置并开迁移票
- [x] `NoteReadPort`（`list` / `get` / `search` / `listByIds`；结构化错误码 `INVALID_QUERY` / `NOTE_READ_FAILED`；返回 `NoteSummary` / `NoteDetail` 投影）— 契约 `common/ports/NoteReadPort.ets`；**实现已按 ADR-0021 下沉 common**：`ports/impl/NoteReadPortAdapter` + `RdbNoteReadStore`（skill 可复用），entry 侧保留 `NoteDaoReadStore` 供精确测试
- [x] `NoteWriteDecisions` 纯判定（insert / update / duplicate / conflict / reject + ADR-0019 错误码）— 切片 A，`common/src/main/ets/ports/NoteWriteDecisions.ets`
- [x] `StudyPlanReadPort`（只承载现有待办语义；`subject` 由注入的 resolver 从 linked note 派生）+ entry 适配器 `StudyPlanPortAdapter`
- [x] `StudyPlanWritePort`（待办语义，ADR-0022 拍板后定义）：`create / update / complete` + `operationId` 幂等 + `expectedVersion` CAS；契约 `common/ports/StudyPlanPorts.ets`，适配器 `StudyPlanWritePortAdapter` + `StudyPlanWriteStoreDao`（v17：`study_plan.version` + `study_plan_op` 事务内写入）
- [x] `ArtifactStorePort`（artifactId 幂等 / 媒体类型 / URI / 校验和 / 删除 / 部分失败回滚）— 契约 `common/src/main/ets/ports/ArtifactStorePort.ets` + 适配器 `entry/src/main/ets/database/ArtifactStoreAdapter.ets`
- [x] `CardSnapshotStore` 补 `schemaVersion` / `updatedAt` / 单 key 原子替换 / 失败返回 `false` 可重试 — 切片 A（`CardSnapshotCodec` + `loadResult`）
- [x] `RunStore` 契约 + 生产实现（2026-10-30）：`run_store` / `run_event`（schema v16）+ `RunStoreAdapter`（create 幂等、update 的 committed 保护、事件序号透传、错误分流）+ `RunStoreDao`（事务内 `MAX(sequence)+1`）；契约测试 `v7-runstore.test.mjs` 8 条
- [ ] 仍缺的写侧维度：真 DAO 往返的「重复 `commitKey` 落库只生效一次」、投影落后可检测；`approvedCheckpointHash` 无持久化列，带哈希的写入当前被安全拒绝
- [x] **检索端口（Step 2a，ADR-0021）**：`NoteSearchPort` 契约（query / hit / TopK 上限 10）+ `NoteSearchRanking` 纯打分（title×4 / tags×3 / summary×2 / content×1，稳定排序）+ `RdbNoteSearchAdapter`（common，SQL 与 `note_query_rag` 等价）；契约测试 8 条
- [x] **消费方接线 Step 2b-1**：`note_query_rag` 改走 `NoteSearchPort`（端口未就绪仍返回 `store not ready`；payload 字段与 tags 编码保持旧形状）；工具文件不再保留第二套打分算法，`keyword-search-tool` 的可读性断言改为指向端口实现
- [x] **消费方接线 Step 2b-2**：`note_get` 改走 `NoteReadPort.get`；`NoteDetail` 补齐 `createdAt` / `intervalDays` / `easeFactor` / `repetitions` / `userId`，payload 字段名与 `tags`/`difficulty` 编码保持旧形状
- [x] **消费方接线 2b-3 决策**：`note_query` 的 keyword 同时命中 title/content，横跨读端口与检索端口语义；**记为工具层特例保留直查**，将来需要复用再新增 `NoteFilterPort`（已写进 ADR-0021 第 4 条）
- [x] **Step 3 证据服务注入**：`NoteEvidenceService(port?)` + `configureEvidenceReadPort`；`EntryAbility` 在 `DatabaseHelper.init` 完成后注入 `NoteReadPortAdapter(RdbNoteReadStore)`；未注入（测试 / 未配置组合根）仍走既有 SQL 路径，行为不变；**注入路径已有契约测试**：`v7-evidence-port.test.mjs`（fake port + fake 图扩展，断言 `listByIds` 被调用且行映射成 citation）；`kg_edge` 读取仍直连（`KnowledgePort` 未建）
- [x] `NoteWritePort` + `CardSnapshotCodec` 契约测试：`scripts/arkts-lint/tests/v7-note-contracts.test.mjs`
      （19 条，`node --test` 实测 `pass 19 / fail 0`，覆盖 `decideWrite` 六分支 + codec 往返/版本/bad JSON/缺字段）
- [x] 读侧契约测试（2026-10-30）：
      `v7-note-read-port.test.mjs` 13 条（过滤/排序/分页/参数校验/错误码/tags 副本/不改 store 数组/元数据边界/空关键字先校验）、
      `v7-studyplan-port.test.mjs` 6 条（排除已完成/due 排序/subject 派生/派生失败降级/错误码）、
      `v7-artifact-store.test.mjs` 11 条（幂等/冲突/删除/manifest 写失败回滚/文件删失败回滚/路径穿越/读失败）——合计 30 条全绿
- [x] 写侧契约测试（2026-10-30）：`v7-note-write-port.test.mjs` 13 条（空 commitKey / commitKey 重放 / insert / store 侧 duplicate 竞态 / VERSION_CONFLICT / expectedVersion 缺省取快照版本 / APPROVAL_HASH_MISMATCH / NOTE_NOT_FOUND / store 失败包装 / 结构化错误不被压平 / 提交前取消 / 提交后取消 / committedAt 透传）——契约测试合计 43 条全绿
- [ ] 仍缺的写侧维度：真 DAO 往返的「重复 `commitKey` 落库只生效一次」、投影落后可检测（`RunStore` 持久化迁移票）；`approvedCheckpointHash` 无持久化列，带哈希的写入当前被安全拒绝
- [x] build 5/5、gate PASS、单测 ≥ 806 —— 2026-10-30 实测：`node scripts/build-hsp-hap.mjs` 49 tasks BUILD SUCCESSFUL；
      `node scripts/agent-gate/index.mjs` → `RESULT: PASS`（`pass=998 fail=0`）

## 链路迁移（§17.6 步 5–7）

- [x] **A1：capture 持久化接端口（2026-10-30）**：`PersistNodeFactory.createWithWritePort`、`NoteAgentOptions/DispatchOptions.noteWritePort` 透传、`AiService` 经 `NoteWritePortFactory` 装配（**不直连 DAO**，写服务保留 post-commit effects）。普通 capture 合成 `capture:<noteId>` 幂等键；测试 `v7-persist-port.test.mjs` 6 条
- [x] **A2：preparedCandidate 写路径接端口（2026-10-31）**：`Dispatcher.buildPreparedGraph(dao?, noteWritePort?)` 端口优先；`AiService` 的 prepared dispatch 注入端口（`capture` / `captureSet` / `preparedCandidate` 三处统一）。**HITL 审批哈希仍未接**：没有持久化列，传了会全拒，等 v18 拍板；测试 `v7-persist-port` 8 条
- [x] **A3：调用方切 `NoteCommand`/`NoteOutcome`（2026-10-31）**：ADR-0019 契约落地
  - `common/src/main/ets/models/NoteCommandModels.ets`：`NoteCommand`（capture / generation / regenerate / preparedCandidate / analysisOnly）+ `NoteOutcome`（needsInput / readyPreview / committed / failed / cancelled）+ `DegradedMarker` + `isRetryableNoteErrorCode`（ArkTS 1.1 无对象联合，用单一 interface + `kind` 判别）
  - `agents/src/main/ets/core/dispatch/NoteOutcomeMapper.ets`：命令→旧请求 / 旧结果→终态 / 抛错→cancelled|failed；补 `APPROVAL_HASH_MISMATCH`、`PREPARED_CHECKPOINT_MISSING` 稳定码
  - `Dispatcher.dispatchCommand(command, options)` 新入口；旧 `dispatch()` 保留为迁移适配器（行为不变，#239 golden 零重录）
  - 消费方切换：`AiService.processAndPersist`（app 拍照文本 + 小艺 A2A 文本）与 `confirmDraft`（preparedCandidate）改走命令入口 + `committed` 终态
  - 测试：`v7-note-command.test.mjs` 7 条（capture committed / failed / 入口取消 / analysisOnly / generation readyPreview / 旧入口适配器 / 消费方接线）
  - **未完成**：generation/regenerate 消费方切换、`dispatchSet` 批量终态、A2A 回执直接读 `NoteOutcome` → 见 A3c
- [x] **A3b：`cancelled(committed=true)`（2026-10-31）**：ADR-0019 (e) 三位置取消落地
  - `PersistNode` 两条写路径（`NoteWritePort` / legacy DAO）写成功后检查停止条件，把 `commitResult` 留在 state 并返回 `CANCELLED`，不再抛出丢掉事务结果
  - `CaptureGraph` 图级取消用「最后节点 state（带 commitResult）」作基底；`StateGraph` 行为保持原样（未改通用内核）
  - `CaptureBranch` 命令路径回填 `cancelledCommitted/cancelledNoteId/cancelledVersion/cancelledCommitKey`；`NoteOutcomeMapper` 映射成 `cancelled(committed=true, noteId, version, commitKey)`
  - 旧 `dispatch()` 路径（`reportCancellation` 未置位）仍按 #239 golden 抛错；golden 18 条零重录
  - 测试 `v7-note-command` 9 条：新增「图内取消未写 → committed=false」「写成功后取消 → committed=true + 信封」
- [x] **A3c：generation / regenerate / analysisOnly 消费方切 `NoteOutcome`（2026-10-31）**
  - `AiService.dispatchNoteDraft` → `kind:'generation'` 命令，只认 `readyPreview`（draft + checkpointId + generation），失败/needsInput 用 `message`/`reason` 抛出；`persist` 由 mapper 按命令形状决定（不再手写 `persist: false`）
  - `AiService.regenerate…` → `kind:'regenerate'` 命令，同样只认 `readyPreview`
  - `AiService.analyzeImage` → `kind:'analysisOnly'` 命令，`readyPreview + classification`（不落库）
  - 测试：`v7-note-command` 10 条（新增消费方接线断言：五处 `dispatchCommand`、三处 `readyPreview` 判别）
  - 相关源码断言测试同步从「`persist: false` / `dispatcher.dispatch(` / `analysisOnly: true`」改为「命令 kind + mapper 规则」
- [x] **A3d：批量终态 + A2A 回执读 `NoteOutcome`（2026-10-31）**
  - 新 `NoteBatchOutcome`（total/committed/failed/cancelled/needsInput/items）+ `Dispatcher.dispatchSetCommand(commands, options, onOutcome)`：一个 set 一个 run、逐项 `NoteOutcome`、共享 RunContext、单项失败隔离、取消后剩余项记 `cancelled(committed=false)`
  - `AiService.captureSet` 切批量命令入口，UI 回执仍由 `captureItemFromOutcome` 适配 `CaptureSetItemResult`（含 code 字段）
  - `AiService.processAndPersistOutcome` + `ingestTextOutcome`：文本/A2A 入口返回终态；旧 `processAndPersist`/`ingestText` 保留为适配器
  - `AgentIngestService.ingestOutcome`；`AgentExtAbility.ingestDirectly` 直接按 `committed/failed/cancelled` 分支回执（failed 带 code/retryable，cancelled 带「是否已落库」文案）
  - 测试：`v7-note-command` 12 条（新增批量终态计数、A2A 回执读 `NoteOutcome`）
  - **真机验证（2026-10-31，设备 3XTYD24C16203663）**：重装 common/agents HSP + entry HAP 后，`python scripts/a2a-smoke/a2a_smoke.py --no-restart --text "存笔记：向量的内积" --min-reply-chars 10` 返回 `ok: true`，reply_text=`已整理入库：向量的内积（线性代数）`（17 字）；hilog `INGEST_DIRECT done subject=线性代数 title=向量的内积` + `A2A_REPLY_SENT chars=17`。冷启动首个请求受扩展进程网络栈初始化失败影响（`proxy SendRequest failed 201`，60–90s 后才返回/小艺先显示拥堵），warm 进程 17s 完成；冷启动复测（2026-10-31 14:05，重装最新产物 + `aa force-stop`）：两次冷启动 ingest 分别 16.7s / 20.0s 并均 `ok:true`；`proxy SendRequest failed 201` + `http handover manager init fail` 仍会出现但属**非致命**（随后 HTTP 200 正常）；瓶颈是 LLM 生成本身（classify ~2.3s + structure ~14s，completionTokens ~2500），此前 60–90s 挂起未复现，判断为设备网络瞬时 handover / 偶发。**结论：不是代码回归，不作阻塞项**
  - **应用内链路真机回归（2026-10-31 14:10，`node scripts/e2e-capture/run.mjs`）**：判定 **PASS** —— 2 张图采集（cold 14838ms / warm 23541ms，persist 388/426ms）、2 条 note 落库（`数学练习（一）…` / `数学练习（二）计算题`）、卡片刷新 OK、图搜 2 组查询各 hits=5；安装最新 HSP/HAP 后跑，覆盖 `CaptureBranch → NoteAgent → NoteWritePort` 与命令 seam
  - 首页 `最近笔记` 41 条，两条 E2E 新笔记置顶 → 写入 → 列表读路径真机可见；HITL 草稿确认（对话入口）：**2026-10-31 手动真机验证通过** —— AI 助手 → 发送「存笔记：洛必达法则」→ 草稿卡 → 确认入库 → 首页「最近笔记」+1（自动化仍缺 e2e 模式，`AI 助手` tab 经 `uitest` 点击未进入浮窗）；若要改善 A2A 体验，走「先回执已收到、后台整理完再推回执」的异步回执方案
  - smoke 脚本修复：`wait_reply` 过滤状态栏时钟碎片与相对时间（此前 `01, :, 35` 被误判为回复导致 `ok:false`）
- **A3 系列完成**：旧 `dispatch()` / `dispatchSet()` / `DispatchResult` 作为迁移适配器保留，等 A4 接线 `EventSink`/`RunStore` 时再统一清理
- [ ] **A4：主图** `preflight → route → invoke → verify → HITL → publish` + `EventSink`/`RunStore` 接线

### AiService 拆分（第二个 god-service，2026-10-31 开始）

> 动因：`AiService.ets` 1142 行，同时承担「compose 端口 / 图片准备 / capture 编排 / 批量 / A2A 入库 / 草稿生成 / 增量重生成 / 澄清 / 确认提交 / 索引 / 耗时日志」十余种职责。按 Dispatcher 同样手法分片，每片以 `agent-gate` 全绿 + `e2e-capture` 可跑为判据。

- [x] **切片 1（2026-10-31）**：抽出 `entry/src/main/ets/services/ai/CaptureTiming.ets`（序号分配 + `CAPTURE_TIMING` / `CAPTURE_SET_TIMING` 汇总日志）；AiService **1174 → 1142 行**
- [x] **切片 2（2026-10-31）**：抽出 `services/ai/AiServicePorts.ets` —— `requireContext` / `buildNoteDao` / `buildNoteWritePort` 组合根；AiService 删除三个私有装配方法，14 处 `requireContext`、3 处 DAO、3 处写端口调用改走 ports；AiService **1142 → 1096 行**
- [x] **切片 3（2026-10-31）**：抽出 `services/ai/DraftCommitService.ets`（`confirmDraft` / `updateDraftCheckpoint` / `resolvePendingMemoryIds` + pending 清理）；AiService 只留同名 facade 委托，**1096 → 1029 行**
- [x] **切片 4（2026-10-31）**：抽出 `services/ai/DraftPipeline.ets`（生成命令装配 / readyPreview 映射 / 恢复 / 取消 / 预算 / run 恢复事件，14 个方法，464 行）+ `services/ai/ClarificationRegistry.ets`（澄清 run 活跃表 + 失败落库，草稿与澄清两条链路共享）；AiService 只留同名 facade，**1029 → 707 行**。`retryDraft` 与澄清方法留给切片 5
- [x] **切片 5（2026-10-31）**：抽出 `services/ai/ClarificationPipeline.ets`（`resumeNoteContextClarification` / `saveNoteContextClarification` / `generateSelectedClarificationDraft` + 回滚 / `retryDraft`，322 行）；澄清生成内部改为委托 `DraftPipeline`；AiService 只留 3 个 facade，**707 → 506 行**
- [x] **切片 6（2026-10-31）**：抽出 `services/ai/CapturePipeline.ets`（`capture` / `captureSet` / `analyzeImage` / `ingestText*` / `processAndPersist*` / `captureItemFromOutcome` / `indexForSearch`，378 行）；`AiService` 收敛为纯 facade（6 组委托 + 构造/context），**506 → 250 行**（含 import；逻辑体约 200 行）。AiService 拆分完成：1174 → 250 行，新增 7 个 `services/ai/` 能力模块

### Dispatcher 拆分（A3 的前置重构，2026-10-31 开始）

> 动因：`Dispatcher.ets` 约 1790 行，`dispatchGeneration` 单方法 301 行、`dispatchIncrementalGeneration` 165 行，四个分支与生成评估逻辑混在一个类里。A3 直接加契约只会更糟，所以先按分支拆模块；每片以 #239 golden 18 条「零重录」作为等价判据。

- [x] **切片 1（2026-10-31）**：抽出 `core/dispatch/DispatchOptions`（共享选项契约）、`UnitSupport`（`copyRegeneratedUnit` / `seedTextFromRequest`）、`PreparedBranch`（preparedCandidate 全流程 + `buildGraph`）；Dispatcher **1790 → 1643 行**；golden 18 条零重录；相关源码断言测试同步指向新模块
- [x] **切片 2（2026-10-31）**：抽出 `CaptureBranch`（AgentState 组装 + NoteAgent 执行 + 四种 `DispatchResult` 外壳）与 `BatchSupport`（批量取消判定 / 跳过回执 / 共享 RunContext 选项复制）；`sourceFromPayload` 并入 `UnitSupport`；Dispatcher **1643 → 1528 行**；golden 零重录
- [x] **切片 3a（2026-10-31）**：抽出 `GenerationEvaluator`（`evaluateStandardCandidate` / `evaluateDeepCandidate` / `deepMergeIssues` / `finishStandardGeneration` / 诊断 / 终态 / 预算包装 / `bundleText`，全部静态方法）+ 三个内部接口；Dispatcher **1528 → 992 行**；golden 零重录
- [x] **切片 3b（2026-10-31）**：抽出 `GenerationBranch`（`dispatchGeneration` + `dispatchStandardGeneration` / `dispatchDeepGeneration` + `buildGenerationGraph` / `normalizeBundle` / `normalizeProvenanceIds` / `referencedPendingSourceIds` / `sourceSummary` / `emitGenerationProgress`，共 9 个静态方法，约 590 行）；Dispatcher **992 → 395 行**（≤400 目标已达成，但增量分支仍在内）；golden 零重录
- [x] **切片 3c（2026-10-31）**：抽出 `IncrementalBranch`（`dispatchIncrementalGeneration` + `incrementalResult`，约 180 行）；Dispatcher **395 → 216 行**
- [x] **切片 4（2026-10-31）**：Dispatcher 已收敛为「入口 + 路由 + 结果外壳」——`dispatch` / `dispatchSet` / `resolveRunContext` / `dispatchRequest` 四条委托，216 行；六条 dispatch 分支模块就位（`CaptureBranch` / `GenerationBranch` / `GenerationEvaluator` / `IncrementalBranch` / `PreparedBranch` / 共享 `DispatchOptions`+`BatchSupport`+`UnitSupport`）；golden 18 条零重录

> **A3 入口已就绪**：Dispatcher 契约点在 216 行薄壳上，下一步在此落 `NoteCommand` / `NoteOutcome`（ADR-0019），`DispatchResult` 降级为迁移适配器。

## #239 行为基线：四条 dispatch 路径 golden 快照

- [x] capture 快照（成功 / 模型不可用 / 空输入 / 入口取消 / 图内取消；审批哈希不匹配由 `prepared-candidate-hash-mismatch` 覆盖）
- [x] generation 三档（light / standard / deep）
- [x] regenerate（本票 14 条矩阵要求的 `VERSION_CONFLICT` / `NOTE_NOT_FOUND`；章节锁命中/未命中留给 regenerate 专项）
- [x] preparedCandidate（hash 不匹配 / preview → commit → 原样 replay 的 `commitKey` 幂等）
- [x] 快照落 `docs/specs/execution/v7-architecture-contracts/raw/`，并在 [`raw/index.md`](./raw/index.md) 补「哪条快照证明哪条行为」对照表（15 个文件）
- [x] 人为改坏一条快照，确认测试会红（验证完再改回）—— 编排会话实测：把 `capture-success.json` 的
  `storage.noteCount` 改成 99，`node --test` 报 `storage.noteCount: expected 99, actual 1`，
  `pass 17 / fail 1`；改回后 18/18 绿

> 证据：`scripts/arkts-lint/tests/v7-golden-dispatch.test.mjs`（15 条用例，含 14 条必备矩阵 + `generation-cancel-in-graph`）；
> 15 个快照全部由 `V7_GOLDEN=record node --test …` **真实录制**（连录两次字节一致），不是手写期望值；
> 默认模式读 [`raw/index.md`](./raw/index.md) 下的快照比对。生产 `.ets` 未改。

## #240 spike：父子图共享 RunContext

> 以下四条是 **2026-10-27 的 spike 结论**（未勾选＝当时未通过，不是待办）。Q1–Q3 已由 #243 修复，见本节末尾「#243 落地后复核」。

- [ ] 子图能拿到父图 `runId` / `deadline` / `CancellationToken`，且取消能冒泡 —— **FAIL**。卡在：`StateGraph` 不持 `runId` / `deadline`，全仓 workflow 层无 `RunContext`（`common/src/main/ets/workflow/StateGraph.ets:19-32`、`:55`）；token 只能靠 `AgentState.cancellationToken` 手工传递（`agents/src/main/ets/graph/AgentState.ets:52`）；`CaptureGraph` 把取消压成 `NODE_ERROR(retriable=false)`（`agents/src/main/ets/graph/CaptureGraph.ets:41-43`）。
- [ ] `maxNodeRuns` 父子累计 —— **FAIL**。卡在：`StateGraph.run()` 每次重置 `nodeRuns`（`common/src/main/ets/workflow/StateGraph.ets:58`），父子各算各的；`CaptureGraph.run` 也没有预算透传入口（`:61-64`）。
- [ ] 领域错误穿子图边界不被压成 `Error` —— **FAIL**。卡在：`CaptureGraphError` 是 interface，且 `CaptureGraph.ets:41-43` 只保留 `message`、统一改写成 `NODE_ERROR`；`kind` / `step` / `retriable` 丢失。裸 `StateGraph` 不 catch，但生产子图边界是 `CaptureGraph`。
- [x] Worker 节点只传可序列化数据 —— **PASS（静态取证，现状无适用对象）**。全仓 8 个 `.ets` / 44 处 `.addNode(` 均无 `ThreadWorker` / `workerPort`；最近的 Worker 协议是纯数据接口（`entry/src/main/ets/workers/ChatPersistenceWorker.ets:27-50`、`entry/src/main/ets/workers/ImageSearchWorker.ets:39-55`）。
- [x] 结论写 `plan.md`「spike 结论」+ `review-report.md`；任一 no → 停，回 §17 改方案 —— 结论已写入 [`spike-240-run-context.md`](./spike-240-run-context.md) 并回填 [`plan.md`](./plan.md)「spike 结论（#240）」；bundle 内无 `review-report.md`，未新建。**总判决：Q1/Q2/Q3 FAIL → 停，不进 #241。** 探针 [`scripts/spikes/v7-run-context-spike.mjs`](../../../../scripts/spikes/v7-run-context-spike.mjs) 沙箱内未跑成，已由编排会话在主机执行：`SUMMARY blocking=3 total=4`，四条 `Q<n>` 实测输出与静态取证一致，见 [`spike-240-run-context.md`](./spike-240-run-context.md) §0.1。

### #243 落地后复核（2026-10-27）

上面三个 FAIL 是 spike 当时的事实，不是待办清单。#243 按 LangGraph 的做法（运行上下文走调用参数，不进 State）把它们补上了：

- **Q1 子图拿得到父 run 的上下文** —— 已修。`RunContext`（`runId` / `parentRunId` / `deadlineAt` / `budget` / `token`）由调用方经 `DispatchOptions.runContext` 传入，capture / generation / prepared 三条图路径统一走 `Dispatcher.resolveRunContext`（`f362790` / `40bffb7` / `de7f48a`）。
- **Q2 预算父子累计** —— 已修。`StateGraph.run(initial, maxNodeRuns, context)` 在有 context 时只认 `context.budget`，且取消先于扣配额（`ef81ae7`）。
- **Q3 领域错误穿边界不被压平** —— 已修。取消 → `CancellationError`（`kind='CANCELLED'`，文案仍是 `CONVERSATION_CANCELLED`）、超时 → `DEADLINE_EXCEEDED`、节点 typed 错误保留 `step` / `kind` / `retriable`。`CaptureGraphError` 仍是 interface：升 class 会触发 `arkts-no-untyped-obj-literals` 打红 8 个节点文件（`72dd5ef`）。
- **token 移出 `AgentState`** —— `StateGraphNode` / `CaptureNode` 改为 `(state, context)`，五个捕获节点改用 `context.throwIfStopped()`（`de7f48a`）。

证据：`v7-run-context`(15) / `v7-stategraph-run-context`(7) / `v7-dispatch-run-context`(4) / `v7-capturegraph-errors`(7) / `v7-capture-state-no-token`(4) 全绿；18 份 golden **一份未重录**；`agent-gate --all` = `RESULT: PASS`（410 `.ets` / 213 docs / `pass=880`）。#241 阻塞解除。

## #241 NoteAgent 薄包装 + 迁 capture

- [x] `NoteAgent` 只包现有节点与服务，不改 prompt、不重写 `TruthCheck` — 新增 `agents/src/main/ets/agents/NoteAgent.ets`
- [x] `TruthCheck` 留在子图最后一个节点（`structure → truth_check → persist`）
- [x] `Dispatcher` 只改 capture 分支，其余三条（generation / regenerate / prepared）未动
- [x] 同切片删旧 capture 装配：`Dispatcher.buildGraph` 已删除，无 flag / 双 runtime
- [x] #239 的 capture 快照逐字段等价 — `node --test scripts/arkts-lint/tests/v7-golden-dispatch.test.mjs` → `18 pass / 0 fail`，快照零重录
- [x] build 5/5、gate PASS — `node scripts/build-hsp-hap.mjs` → 49 tasks **BUILD SUCCESSFUL**；`agent-gate` → `RESULT: PASS`（`pass=955 fail=0`）
- [ ] A2A 回归：`python scripts/a2a-smoke/a2a_smoke.py --text "整理数学题"`（A2A 经同一 capture 分支，必须复测）
- [ ] 真机 capture 流程与迁移前一致（截图或日志）

## #242 拍板：Video 范围 / ReviewAgent 领域

- [x] Video：**只产脚本，不做 mp4 renderer**（ADR-0022）；产物是文本，隐私/存储/取消按无大文件设计
- [x] ReviewAgent：**新建 `review_item` / `review_log`**，`study_plan` 保持待办（ADR-0022，含 schema 草案）
- [x] 数据问题降级：测试态不上架、无线上数据，schema v15 按 `CREATE TABLE IF NOT EXISTS`，回滚 = `DROP TABLE`
- [x] 已落 ADR-0022（`docs/adr/0022-review-and-video-scope.md`）+ §17.7 定稿

### 派生票（拍板后待开/待做）

- [x] schema v15 迁移：`review_item` / `review_log` + 3 个索引（`DatabaseHelper` v14 → v15，`CREATE IF NOT EXISTS`，回滚 = DROP）；源码级契约测试 `v7-review-schema.test.mjs` 6 条
- [x] `ReviewReadPort` 契约 + 只读实现（ADR-0021/0022）：`listDue` / `getByUnit` / `history`，limit 夹取 + 结构化错误码；`ReviewReadPortAdapter` + `RdbReviewReadStore`（common）；契约测试 `v7-review-read-port.test.mjs` 6 条
- [ ] `ReviewWritePort` 契约 + adapter + 契约测试（`schedule` / `record`，operationId 幂等；随 `ReviewAgent` 票定义，SM-2 在 `review.plan` 工具）
- [ ] `ReviewAgent` 子图：`plan → ask → grade`，SM-2 落在 `review.plan` 工具
- [ ] `MathVideoAgent` 脚本流水线：`outline → script`（产物落 App Store 文本产物）
- [x] schema v16：`run_store` / `run_event` + 2 个索引（`RunStoreDao` 生产实现，`MAX(sequence)+1` 事务内递增）；随 v7-runstore 契约测试一起验证
- [x] schema v17 + `StudyPlanWritePort`：`study_plan.version` CAS 列 + `study_plan_op` 幂等表；`StudyPlanWritePortAdapter` + `StudyPlanWriteStoreDao`（业务写入与操作记录同事务）；契约测试 `v7-studyplan-write.test.mjs` 8 条
