# v7 契约层与 NoteAgent 迁移 · 任务清单

> 一票一个块，勾选时把证据写进 `verification-record.md`（构建输出、gate 输出、快照文件名、真机截图路径）。
> 顺序按 `plan.md` §2，不要在 #240 结论出来之前动 #241。

## #237 ADR：Subgraph 边界 + NoteCommand / NoteOutcome

- [x] `docs/adr/0019-note-command-and-outcome.md`：`NoteCommand` 五型（capture / generation(mode) / regenerate(range) / preparedCandidate(hash) / analysisOnly）
- [x] `NoteOutcome` 五终态（needsInput / readyPreview / committed(noteId, version) / failed(code, retryable) / cancelled(committed)）
- [x] 错误码表：OCR 失败、分类失败、校验失败、模型不可用（含降级标记）、版本冲突、审批哈希不匹配、取消
- [x] 修订 `docs/adr/0008-*`：新增「Subgraph 放开范围」一节（允许共享 RunContext / 禁止 runtime checkpoint 与图内 HITL）
- [x] §17.5 契约表回填 ADR 编号
- [ ] `node scripts/agent-gate/index.mjs --all` PASS

## #238 契约层：六个 Port + adapter + 契约测试

- [x] `NoteWritePort`（`commitKey` 必填、`expectedVersion` CAS、`approvedCheckpointHash`、`NotePortError`）— 切片 A，`common/src/main/ets/ports/NoteWritePort.ets`
- [ ] `NoteReadPort`（切片 A 未覆盖，仍待做）
- [x] `NoteWriteDecisions` 纯判定（insert / update / duplicate / conflict / reject + ADR-0019 错误码）— 切片 A，`common/src/main/ets/ports/NoteWriteDecisions.ets`
- [x] `StudyPlanReadPort`（只承载现有待办语义；`subject` 现状无列，需由 linked note 派生）— 切片 A
- [ ] `StudyPlanWritePort`（升级为复习计划前不定义，等 #242 拍板）
- [ ] `ArtifactStorePort`（artifactId / 媒体类型 / URI / 校验和 / 删除 / 部分失败清理）
- [x] `CardSnapshotStore` 补 `schemaVersion` / `updatedAt` / 单 key 原子替换 / 失败返回 `false` 可重试 — 切片 A（`CardSnapshotCodec` + `loadResult`）
- [x] `RunStore` 接口契约（runId / parentRunId / status / checkpoint / committedNoteId / committedVersion / updatedAt）— 切片 A，`common/src/main/ets/ports/RunStore.ets`
- [ ] **未决：RunStore 生产适配器需单开迁移票** — `parentRunId` / 事件序号 / 五终态落库三项目前**没有存储列**（`DatabaseHelper` 13 张表里没有 `run_event`）；本切片不实现生产适配器、不伪造持久化。
- [ ] `skill/SkillAbility` 与 `entry/NoteEvidenceService` 去掉直连 RDB，改走 Port（行为不变）
- [x] `NoteWritePort` + `CardSnapshotCodec` 契约测试：`scripts/arkts-lint/tests/v7-note-contracts.test.mjs`
      （19 条，`node --test` 实测 `pass 19 / fail 0`，覆盖 `decideWrite` 六分支 + codec 往返/版本/bad JSON/缺字段）
- [ ] 其余 Port（`NoteReadPort` / `StudyPlanWritePort` / `ArtifactStorePort` / `RunStore` 持久化）四条契约测试：重复 `commitKey` 只生效一次、`expectedVersion` 落后返回冲突、取消提交前/后语义、投影落后可检测
- [x] build 5/5、gate PASS、单测 ≥ 806 —— 编排会话实测：`node scripts/build-hsp-hap.mjs` 全 5 步成功；
      `node scripts/agent-gate/index.mjs --all` → `RESULT: PASS`（407 `.ets`、212 docs、unit-tests `pass=843 fail=0`）

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

- [ ] `NoteAgent` 只包现有节点与服务，不改 prompt、不重写 `TruthCheck`
- [ ] `TruthCheck` 留在子图最后一个节点
- [ ] `Dispatcher` 只改 capture 分支，其余三条保持原样
- [ ] 同切片删旧 capture 装配，不留 flag / 双 runtime
- [ ] #239 的 capture 快照逐字段等价
- [ ] build 5/5、gate PASS、真机 capture 流程与迁移前一致（截图或日志）

## #242 拍板：Video 范围 / ReviewAgent 领域

- [ ] Video：只产脚本 vs mp4；产物隐私 / 存储配额 / 取消语义
- [ ] ReviewAgent：升级 `study_plan`（含迁移与回滚）还是新建 `review_item` / `review_log`（含 schema 草案）
- [ ] 两个决定都回答「v1 已上架用户数据怎么办」
- [ ] 落 ADR 或 §17.7 定稿，再开实现票
