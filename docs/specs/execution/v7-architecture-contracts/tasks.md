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
- [ ] `StudyPlanWritePort`（升级为复习计划前不定义，等 #242 拍板）
- [x] `ArtifactStorePort`（artifactId 幂等 / 媒体类型 / URI / 校验和 / 删除 / 部分失败回滚）— 契约 `common/src/main/ets/ports/ArtifactStorePort.ets` + 适配器 `entry/src/main/ets/database/ArtifactStoreAdapter.ets`
- [x] `CardSnapshotStore` 补 `schemaVersion` / `updatedAt` / 单 key 原子替换 / 失败返回 `false` 可重试 — 切片 A（`CardSnapshotCodec` + `loadResult`）
- [x] `RunStore` 接口契约（runId / parentRunId / status / checkpoint / committedNoteId / committedVersion / updatedAt）— 切片 A，`common/src/main/ets/ports/RunStore.ets`
- [ ] **未决：RunStore 生产适配器需单开迁移票** — `parentRunId` / 事件序号 / 五终态落库三项目前**没有存储列**（`DatabaseHelper` 13 张表里没有 `run_event`）；本切片不实现生产适配器、不伪造持久化。
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

- [ ] schema v15 迁移：`review_item` / `review_log` + 索引 + 回滚（`DatabaseHelper` v14 → v15）
- [ ] `ReviewReadPort` / `ReviewWritePort` 契约 + adapter + 契约测试（按 #238 六必填项）
- [ ] `ReviewAgent` 子图：`plan → ask → grade`，SM-2 落在 `review.plan` 工具
- [ ] `MathVideoAgent` 脚本流水线：`outline → script`（产物落 App Store 文本产物）
- [ ] `RunStore` 迁移票（`run_event` 表 + 五终态列）—— #238 最后一个待自证缺口
