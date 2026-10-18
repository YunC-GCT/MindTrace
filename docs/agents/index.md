# Agent workflow docs index

> 本目录只放**流程与指针文档**：怎么协作、去哪找、怎么交付。

## 定位

| 放这里 | 不放这里 |
|---|---|
| 团队约定（git / 命名 / 安全 / issue / triage） | 一次性 session 交接、执行轨迹 → `docs/legacy/mindtrace/handoffs/` |
| 可复用流程（smoke test / CI 失败处理 / 调研模式） | 调研产物 → `docs/research/` |
| 术语表与教学入口 | 设计决策 → `docs/adr/` |
| 指向更深文档的指针 | 执行记录 → `docs/specs/execution/` |

带日期的三篇保留在本目录，因为它们是**版本化的操作文档**而不是一次性交接：`git-flow-lightweight-2026-09-04.md`（团队手册 v1.0）、`d2-capturegraph-teaching-2026-09-05.md`（教学入口，被 AGENTS 与 spec 011 引用）、`demo-script-2026-09-06.md`（复赛演示脚本）。

## 文件

| File | 作用 |
|---|---|
| [`agent-glossary.md`](./agent-glossary.md) | 通用 Agent / 架构术语（Node / Edge / State / Checkpoint / HITL…），与 `CONTEXT.md` 的项目词表分工 |
| [`api-version.md`](./api-version.md) | API 版本兼容策略与“哪些能力是 API 26 roadmap” |
| [`branch-protection.md`](./branch-protection.md) | `main` / `develop` 保护规则与 required checks |
| [`ci-failure-workflow.md`](./ci-failure-workflow.md) | CI 失败时的排查顺序与责任边界 |
| [`d2-capturegraph-teaching-2026-09-05.md`](./d2-capturegraph-teaching-2026-09-05.md) | CaptureGraph 教学版讲解（D2 落地记录） |
| [`demo-script-2026-09-06.md`](./demo-script-2026-09-06.md) | 复赛 5 分钟演示脚本与赛前检查 |
| [`domain.md`](./domain.md) | 领域建模 / spec / ADR 的写作流程 |
| [`file-header-template.md`](./file-header-template.md) | .ets 与各类文件头模板、创建新文件的编码注意事项 |
| [`git-conventions.md`](./git-conventions.md) | conventional commits、分支模型、PR 约定（权威） |
| [`git-flow-lightweight-2026-09-04.md`](./git-flow-lightweight-2026-09-04.md) | 3 人团队 Git Flow 手册（分支 / PR / 发版 / worktree 隔离） |
| [`issue-tracker.md`](./issue-tracker.md) | GitHub Issues（`gh` CLI）使用方式与模板 |
| [`naming-exceptions.md`](./naming-exceptions.md) | 命名规范的例外清单与审批方式 |
| [`security.md`](./security.md) | secrets / 签名 / 凭据存储红线 |
| [`smoke-test.md`](./smoke-test.md) | 8 步人工冒烟矩阵 |
| [`triage-labels.md`](./triage-labels.md) | 5 个 triage 标签的语义与流转 |
| [`patterns/index.md`](./patterns/index.md) | 可复用工作模式入口（add-new-adr / investigate / refactor-x / capability-to-implementation） |

## 已移出的交接文档

以下文档是时间点交接或执行轨迹，2026-10-18 统一移入 [`docs/legacy/mindtrace/handoffs/`](../legacy/mindtrace/handoffs/)，只作历史记录：

- `handoff-2026-09-06.md`、`handoff-langgraph-migration.md`（已 SUPERSEDED）
- `backend-migration-handoff.md`（已被 spec 018 取代）
- `agent-run-timeline-handoff.md`
- `git-flow-setup-2026-09-04.md`
- `llm-settings-scope-2026-09-06.md`、`llm-settings/`（4 篇 PR 记录）
- `note-generation-fix-handoff-2026-09-20.md`、`note-generation-failure-diagnostics-handoff-2026-09-29.md`
- `qwen-deepseek-reasoning-handoff-2026-09-12.md`
