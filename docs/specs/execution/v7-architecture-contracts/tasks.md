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

- [ ] `NoteReadPort` / `NoteWritePort`（含 `approvedCheckpointHash`）
- [ ] `StudyPlanReadPort` / `StudyPlanWritePort`（只承载现有待办语义）
- [ ] `ArtifactStorePort`（artifactId / 媒体类型 / URI / 校验和 / 删除 / 部分失败清理）
- [ ] `CardSnapshotStore` 补 `schemaVersion` / `updatedAt` / 原子替换 / 可重试
- [ ] `RunStore`（runId / parentRunId / eventId / 单调 sequence / status+version / checkpoint / 恢复与取消）
- [ ] `skill/SkillAbility` 与 `entry/NoteEvidenceService` 去掉直连 RDB，改走 Port（行为不变）
- [ ] 每 Port 四条契约测试：重复 `commitKey` 只生效一次、`expectedVersion` 落后返回冲突、取消提交前/后语义、投影落后可检测
- [ ] build 5/5、gate PASS、单测 ≥ 806

## #239 行为基线：四条 dispatch 路径 golden 快照

- [ ] capture 快照（成功 / 模型不可用 / 校验失败 / 取消 / 审批哈希不匹配）
- [ ] generation 三档（light / standard / deep）
- [ ] regenerate（章节锁命中与未命中）
- [ ] preparedCandidate（hash 匹配与不匹配）
- [ ] 快照落 `docs/specs/execution/v7-architecture-contracts/raw/`，并在本文补「哪条快照证明哪条行为」对照表
- [ ] 人为改坏一条快照，确认测试会红（验证完再改回）

## #240 spike：父子图共享 RunContext

- [ ] 子图能拿到父图 `runId` / `deadline` / `CancellationToken`，且取消能冒泡
- [ ] `maxNodeRuns` 父子累计
- [ ] 领域错误穿子图边界不被压成 `Error`
- [ ] Worker 节点只传可序列化数据
- [ ] 结论写 `plan.md`「spike 结论」+ `review-report.md`；任一 no → 停，回 §17 改方案

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
