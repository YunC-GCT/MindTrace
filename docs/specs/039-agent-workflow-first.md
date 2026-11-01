# 039 — Agent 编排收口：CommandExecutor + CommandRouter + 四条 workflow

> **Status**: proposed (2026-11-01) — **S1/S2 已落地**（2026-11-01）；S3（事件树）待做
> **Related**: [ADR-0008](../adr/0008-capturegraph-self-built-runtime.md) · [ADR-0019](../adr/0019-note-command-and-outcome.md) · [ADR-0021](../adr/0021-shared-read-port-implementation-in-common.md) · [spec 038](./038-write-job-scheduler.md) · [架构提案](../architecture/agent-architecture-proposal-2026-11-01.md) · [v7 外评审](../architecture/review-v7-2026-10-27.md)
> **Code**: `agents/src/main/ets/core/Dispatcher.ets` · `agents/src/main/ets/core/dispatch/`（DispatchGraph / CaptureBranch / RunEventSink） · `agents/src/main/ets/agents/NoteAgent.ets` · `entry/src/main/ets/services/ai/{AiServicePorts,CapturePipeline,DraftPipeline,DraftCommitService}.ets` · `common/src/main/ets/workflow/StateGraph.ets`
> **Verified by**: 基线 `node scripts/agent-gate/index.mjs` → `RESULT: PASS`（pass=1165 / 0 lint error / 0 边界违规）；本 spec 的验收命令见 §7，实施后逐条回填

## 1. Why this ticket

`Dispatcher` 现在同时承担：命令分派、六阶段推进、四条分支判断、`run` 事件与终态落定。六阶段里 `route`（直接 `next: 'invoke'`）和 `hitl`（直接 `next: 'publish'`）没有行为，真正的分支判断埋在 `invoke → invokeCommand → dispatchRequest`；`NoteAgent` 只被 `CaptureBranch` 当函数调，不是图节点。结果是一条 capture 要走五层：`DispatchGraph → invoke → CaptureBranch → NoteAgent → CaptureGraph → StateGraph`。

这不是「分层不够」，是「名实不符」：没有 LLM 路由、没有生产 tool loop、没有 checkpoint，却按 Agent 主图的形状组织代码。评审与后续开发都会被这层壳误导（[提案 §1–§2](../architecture/agent-architecture-proposal-2026-11-01.md)）。

本 spec 把编排层收敛成 **执行器 + 路由 + 每命令一条 workflow**，行为保持不变（golden 兜底）。

## 2. What we will build

### 2.1 目标形状

```ts
// agents/src/main/ets/core/CommandExecutor.ets
export class CommandExecutor {
  async execute(command: NoteCommand, options: DispatchOptions): Promise<NoteOutcome>;
}

// agents/src/main/ets/core/CommandRouter.ets
export type NoteWorkflowId = 'capture' | 'generation' | 'regenerate' | 'prepared';
export class CommandRouter {
  preflight(command: NoteCommand, options: DispatchOptions): Promise<DispatchStageResult>;
  resolve(command: NoteCommand): NoteWorkflowId;
}
```

四条 workflow 统一签名为 `run(command, context): Promise<NoteOutcome>`：

| workflow | 文件 | 负责 |
|---|---|---|
| `NoteCaptureWorkflow` | `agents/src/main/ets/workflows/NoteCaptureWorkflow.ets` | capture / captureSet：`ocr → classify →（structure）→ truth_check →（persist）→ END` |
| `NoteGenerationWorkflow` | `workflows/NoteGenerationWorkflow.ets` | generation 三档 + verify → `readyPreview` |
| `NoteRegenerateWorkflow` | `workflows/NoteRegenerateWorkflow.ets` | regenerate(range)：版本冲突 / 章节锁 |
| `NotePreparedWorkflow` | `workflows/NotePreparedWorkflow.ets` | preparedCandidate：hash/checkpoint 校验 → commit |

`NoteAgent` 改名为 `NoteCaptureWorkflow`（`NoteAgent.ets` → `workflows/NoteCaptureWorkflow.ets`）；`GenerateBranch` / `PreparedBranch` / `IncrementalBranch` 的内容迁进对应 workflow，文件删除。

### 2.2 职责切分（硬边界）

| 组件 | 只做 | 不做 |
|---|---|---|
| `CommandExecutor` | 建 run、解析 `RunContext`、发 `run.started/terminal`、调 workflow、异常 → 五终态、`settle` run | 不判断分支、不碰 DAO |
| `CommandRouter` | 命令形状校验、取消检查、审批哈希前置、`kind → workflow` | 不执行节点、不写库 |
| workflow | 图装配 + 节点执行 + 自己阶段的 verify | 不直接调另一条 workflow、不发 run 级事件 |
| `CaptureBranch` 等 | —（删除） | — |
| `DispatchGraph` | —（删除） | — |

决策（本 spec 生效）：

1. **命名**：`Dispatcher` → `CommandExecutor` + `CommandRouter`；只改 `agents/core` 与 4 个调用点，不修改 `NoteCommand`/`NoteOutcome` 契约。
2. **verify / publish 归属**：`verify`（committed 信封校验）与 `publish`（`settle` + terminal 事件）收进 `CommandExecutor`；capture 的 truth_check 留在 workflow。
3. **runId**：沿用 `runId = command.operationId`（`RunStoreEventSink` 已经这么用），不新增 ID。
4. **ToolLoop**：本 spec **不接、不删**，留给 spec 040；只在 gate 里标「0 生产引用」为已知项。
5. **事件**：S3 扩 `RunEventSink`；node 事件由 workflow 经注入的 sink 发，run 事件由 executor 发。

## 3. Public surface change

- **不变**：`NoteCommand` / `NoteOutcome`（ADR-0019）、8 个端口与适配器（ADR-0021）、`RunContext`、`dispatchCommand` 的调用方签名（`AiService` 等只改 import 名）。
- **内部变**：`Dispatcher` 类与文件、`CaptureBranch` / `GenerationBranch` / `PreparedBranch` / `IncrementalBranch` / `DispatchGraph` 文件、`NoteAgent` 类名。
- **import 面**：`entry/services/ai/*` 4 处 + `agents/Index.ets` 导出；无跨 module 协议变化。
- **不动**：A2A 的 35s / 90s deadline、单帧快照、inbox 语义；WriteJob 调度器（spec 038）。

## 4. Migration（原子、无双跑）

| 切片 | 动作 | 删除 | 提交 |
|---|---|---|---|
| S0 | 本文档 + 提案链接 + 命名决策落地文档 | — | `docs(spec): 039 ...` |
| S1 | 抽 `CommandExecutor`（run/settle/错误映射）+ `CommandRouter`（preflight/route）；四条 workflow 骨架就位；`Dispatcher` 文件删除 | `DispatchGraph.ets`（六阶段）、`route`/`hitl` 空阶段 | `refactor(agents): 拆执行器与路由` |
| S2 | `NoteCaptureWorkflow` 接管 capture；删 `CaptureBranch`；`NoteAgent` 文件改名 | `CaptureBranch.ets`、`NoteAgent.ets` | `refactor(agents): capture 收口到 workflow` |
| S3 | 事件 schema：`node.started/ended`、`tool.called/result`、`approval.*`、`commit.*`；`runId` 贯通；`scheduler-report` 解析 | — | `feat(observability): run 事件树` |

每个切片必须同 commit 删旧实现；禁止新旧 runtime 并行或长期 flag（ADR-0008）。

## 5. Test plan (TDD)

**先红后绿**（新增测试先建，再实现）：

| 测试 | 覆盖 |
|---|---|
| `v7-command-executor.test.mjs`（新，≥6 条） | 建 run 且 `runId=operationId`；`run.started` 先于 `run.terminal`；异常 → `failed`；`cancelled` 保留；budget/deadline 透传；`settle` 只发一次 |
| `v7-command-router.test.mjs`（新，≥5 条） | 四 kind → 四 workflow；未知 kind 拒绝；取消前置；审批哈希前置；路由不写库（fake port 零调用） |
| `v7-golden-dispatch.test.mjs`（现有 18 条） | **必须零重录**：S1/S2 后 `git diff` 对 `raw/` 为空 |
| `v7-note-command.test.mjs`（现有 16 条） | 五终态与取消信封不变 |
| `v7-persist-port.test.mjs`（现有 8 条） | 写端口路径不变 |
| `v7-run-events.test.mjs`（S3 新增，≥6 条） | 事件字段、顺序、`runId` 必填、payload 不含正文 |
| AST guard（S1 新增） | 门禁断言：`agents/workflows/*` 不 import 另一 workflow；`entry/services/ai` 只 import `CommandExecutor` |

## 6. Reversibility

**低风险**：每切片一个 revertable commit；`NoteCommand/NoteOutcome` 与端口不变；golden 18 条是行为锚点。回退 S1/S2 只需 revert 两个 commit，`Dispatcher` 与 `CaptureBranch` 恢复即可（无数据迁移）。

## 7. Acceptance criteria

- [ ] `node scripts/agent-gate/index.mjs` → `RESULT: PASS`
- [ ] golden 18 条**零重录**（`raw/` 无 diff），`node --test scripts/arkts-lint/tests/v7-golden-dispatch.test.mjs` 全绿
- [ ] 新增测试 ≥17 条，总单测数 ≥ 1165（不下降）
- [ ] `python scripts/a2a-smoke/a2a_smoke.py --text "整理数学题"` → `ok: true`
- [ ] 真机 `e2e-capture` PASS（2 图，persist 耗时与迁移前同量级）；`e2e=schedulerProbe/schedulerIntegration` 不回归
- [ ] `agents/` 不出现 `DispatchGraph` / `CaptureBranch` / `NoteAgent` 引用；`Dispatcher` 引用清零
- [ ] 文档同步：`docs/system-architecture-layered.md` §17.2、`docs/adr/0008` Reversibility 段（`Dispatcher.buildGraph` → `CommandExecutor`）、`docs/specs/018` 现状段、v7 执行包 index 状态
- [ ] 无 `.ets` 双 runtime / 双写路径 / 新 flag

## 8. Sequence（提交清单）

1. `docs(spec): 039 agent 编排收口（执行器 + 路由 + 四 workflow）`
2. `refactor(agents): CommandExecutor + CommandRouter，删除六阶段 DispatchGraph`（S1）
3. `refactor(agents): capture 收口到 NoteCaptureWorkflow，删 CaptureBranch`（S2）
4. `feat(observability): run 事件树（node/tool/approval/commit）`（S3）
5. `docs(architecture): §17 与 ADR-0008 同步执行器/路由术语`（随 2–4 更新）

## 9. Out of scope

- **S4 / spec 040**：ChatWorkflow 接 `ToolLoop`；A2A 收敛到同一 executor；`IngestGateway` 端口；删除/保留 ToolLoop 的最终决策。
- **S5**：runtime checkpoint / interrupt / 持久队列 / 跨进程 handoff（需新 ADR，ADR-0008 仍禁止）。
- 子图即节点（ADR-0008 已放开，但无第二消费者，不预建）。
- 服务层拆分（`entry/services` 104 个文件）、skill 越层、KnowledgePort、Review/Video 的 workflow。
- 任何协议、数据模型、表结构变化。

## 10. 与分层架构的关系（实施顺序）

**结论：先做本 spec（全链路收口），分层作为约束同步守，不先做分层大扫除。**

| 判断 | 说明 |
|---|---|
| 分层现状已够用 | 4 条模块边界 + process-boundary 0 违规；端口 8 个；缺的不是边界，是 L2 编排的实现形态 |
| L2 收口 = S1/S2 | 「分层先推进」实际要改的正是 Dispatcher/CaptureBranch，与本 spec 完全重叠；分开做会互相冲突 |
| 先做会失控 | 若先拆 `entry/services` 或搬模块，S1 的 import 面会二次变动，golden 与 A2A 回归成本翻倍 |
| 分层剩余项排后 | services 拆分、skill 越层、KnowledgePort、Review 端口 → S3 之后（或与 S3 并行，互不冲突） |
| 顺序 | **S1 → S2 → S3**；S4 另行立 spec；S5 需 ADR |

## 11. 已知风险

| 风险 | 缓解 |
|---|---|
| 拆 `Dispatcher` 时错误码/终态漂移 | golden 18 零重录 + `v7-note-command` + A2A smoke 三重判据；逐条比对 `raw/` |
| A2A 35s deadline 下多一层 executor | executor 只做建 run + 转发，实测开销可忽略；真机 smoke 覆盖 |
| 审批哈希前置迁到 router 后语义变化 | 保持现实现：`preflightApproval` 原样迁入 `CommandRouter.preflight`，测试覆盖拒绝路径 |
| 文件改名导致 import 漏改 | `agents/Index.ets` 统一导出 + gate 全量编译/单测；提交前 `grep -r "Dispatcher"` 清零 |
| S3 事件量增大 | 事件 best-effort（同 WriteJob sink），失败只告警；不落正文 |

## 12. 文档同步清单（随切片）

- `docs/system-architecture-layered.md` §17.2（主图描述改成「执行器 + 路由 + workflow」）与 §17.3（差距 1 改为「已收口」）
- `docs/adr/0008-capturegraph-self-built-runtime.md` Reversibility 段（`Dispatcher.buildGraph` → `CommandExecutor.execute`）
- `docs/specs/018-agent-workflow-architecture.md` 现状段
- `docs/specs/execution/v7-architecture-contracts/index.md` 状态行
- `docs/agents/phase-tracker.md`（若影响验收口径）

## 13. 执行记录

### S1（2026-11-01 完成）

- 新增 `agents/src/main/ets/core/CommandExecutor.ets`（run 生命周期：start/terminal 事件、runId=operationId、preflight→workflow→verify→settle、异常→五终态）与 `CommandRouter.ets`（取消/审批哈希前置 + `kind → workflow` 路由）；
- 新增 `agents/src/main/ets/workflows/`：`WorkflowContext` + `NoteCaptureWorkflow` / `NoteGenerationWorkflow` / `NoteRegenerateWorkflow` / `NotePreparedWorkflow`（S1 骨架：分别委托 CaptureBranch / GenerationBranch / IncrementalBranch / PreparedBranch）；
- 删除 `core/Dispatcher.ets` 与 `core/dispatch/DispatchGraph.ets`；`agents/Index.ets` 改导出 `CommandExecutor` / `CommandRouter`；entry `services/ai/*` 与 `AiService` 的构造/类型改 `CommandExecutor`（方法名 `dispatchCommand/dispatchSetCommand` 不变）；
- 测试：新增 `v7-command-executor`（7 条）+ `v7-command-router`（7 条）；`v7-dispatch-graph`（直接测已删除骨架）由这两个文件替代；旧测试的 Dispatcher 引用与断言改指新执行器/路由/workflow；
- 验证：`node scripts/agent-gate/index.mjs --all` → **RESULT: PASS（pass=1171 fail=0）**；golden `raw/` **零 diff**；`node scripts/build-hsp-hap.mjs` 成功；
- 偏差（记录在案）：Generation/Regenerate/Prepared 三条 workflow 本轮只做骨架委托，分支文件内容迁移推迟；S2 完成 capture 收口后再评估是否把三分支内容收进 workflow（验收不要求其删除）。

### S2（2026-11-01 完成）

- `NoteCaptureWorkflow` 接管 capture：原 `CaptureBranch` 的终态映射（失败/analysisOnly/缺 unit/cancelled/committed）与 `NoteAgent.buildGraph` 的图装配合并进 workflow；
- 删除 `agents/src/main/ets/core/dispatch/CaptureBranch.ets` 与 `agents/src/main/ets/agents/NoteAgent.ets`（五层调用 `DispatchGraph→invoke→CaptureBranch→NoteAgent→CaptureGraph` 降为 `CommandExecutor→NoteCaptureWorkflow→CaptureGraph`）；
- 测试：`dispatcher-capturegraph` 重写为 `NoteCaptureWorkflow` 图装配/委托契约；`v7-capture-set`、`v7-subject-vocabulary`、`image-draft-source` 的旧路径断言改指 workflow；
- 验证：`node scripts/agent-gate/index.mjs --all` → **RESULT: PASS（pass=1169 fail=0）**；golden `raw/` **零 diff**；`node scripts/build-hsp-hap.mjs` 成功；agents/ 内 `DispatchGraph|CaptureBranch|NoteAgent|Dispatcher` 引用清零（含注释）；
- **真机验证受阻（需解锁）**：设备锁屏，`aa start` 被拒；`e2e=captureSet` 与 `a2a_smoke.py` 待设备解锁后补跑（不影响 S2 代码/单测/golden 判据）。

### 下一步

- S3：事件 schema（node/tool/approval/commit）+ runId 贯通 + scheduler-report 解析；之后补真机 captureSet/a2a smoke。

