# Execution bundles index

> 本目录存放**执行记录**，不存放设计决策。设计决策在 `docs/specs/NNN-*.md` 与 `docs/adr/`。

## 一个 bundle 里有什么

| 文件 | 作用 |
|---|---|
| `spec.md` | 冻结范围与验收条件（写实现前） |
| `plan.md` | 实施计划与文件级落点 |
| `tasks.md` | 勾选式任务与逐项证据 |
| `verification-record.md` / `verification-report.md` | 实际执行的验证结果（结论以它为准，不以 `spec.md` 的 Draft 字样为准） |
| `delivery-checklist.md` / `review-report.md` | 交付清单 / code review 结论（部分 bundle 才有） |
| `raw/` | 原始测量数据（如渲染基准 JSONL），测试会直接读取，移动目录时必须同步改测试路径 |

## Bundles

| Bundle | 对应设计规格 / issue | 内容 | 状态（bundle 头部记录） |
|---|---|---|---|
| [`019-reasoning-process-display-p0/`](./019-reasoning-process-display-p0/) | [spec 019](../019-reasoning-process-display-p0.md) · #111 | spec / plan / tasks / verification-report / delivery-checklist / review-report | Draft（执行记录已归档） |
| [`021-review-remediation/`](./021-review-remediation/) | [spec 021](../021-chat-streaming-incremental-rendering.md) · #140 / #141 | spec / plan / tasks | Draft |
| [`097-knowledge-unit-write-service/`](./097-knowledge-unit-write-service/) | Issue #97 · [CONTEXT KnowledgeUnitWriteService](../../../CONTEXT.md) | spec / plan / tasks | 无 Status 行 |
| [`098-light-note-generation/`](./098-light-note-generation/) | Issue #98 | spec / plan / tasks | 无 Status 行 |
| [`entry-arkts-compile-fix/`](./entry-arkts-compile-fix/) | Entry ArkTS 编译修复 | verification-record | 仅验证记录 |
| [`restore-arkweb-warmup/`](./restore-arkweb-warmup/) | #119 · [ADR-0017](../../adr/0017-renderer-scheduler-budget-baseline.md) | spec / plan / tasks | Draft |
| [`ticket-0-2-stable-chat-key-refresh/`](./ticket-0-2-stable-chat-key-refresh/) | #120 | spec / plan / tasks / verification-record | `INCOMPLETE`（未放行） |
| [`ticket-0-3-chat-filesdir-seam/`](./ticket-0-3-chat-filesdir-seam/) | chat filesDir seam | spec / plan / tasks / verification-record | `PASS` |
| [`ticket-0-5-customspan-placeholder-seam/`](./ticket-0-5-customspan-placeholder-seam/) | CustomSpan placeholder seam | spec / plan / tasks / verification-record | Draft |
| [`ticket-0-6-chat-render-fixtures-budgets/`](./ticket-0-6-chat-render-fixtures-budgets/) | #124 · [ADR-0017](../../adr/0017-renderer-scheduler-budget-baseline.md) | spec / plan / tasks / verification-record / `raw/*.jsonl` | Draft（ticket-0 证据完整） |
| [`note-generation-stability/`](./note-generation-stability/) | 2026-09-21 笔记生成稳定性计划 | plan | 仅计划 |

`feature.json` 是 Spec-Kit 工具的元数据，不是 bundle。

## 新增 bundle 的规则

1. 目录名用 kebab-case，优先复用设计规格的 `NNN-slug`：`execution/019-reasoning-process-display-p0/`。
2. 文件名固定为 `spec.md` / `plan.md` / `tasks.md` / `verification-record.md`，不另起别名。
3. 设计变更写回 `docs/specs/NNN-*.md` 或 ADR，不在 bundle 里改设计。
4. `raw/` 只放可复现的原始数据；测试或文档引用它的路径时，移动目录必须同 commit 修正引用。
5. 完成且不再维护的 bundle 保留在原位（它是可追溯证据），不要删；只有内容被新 bundle 完全取代时才加 `## Superseded` 说明。

## 与旧位置的关系

2026-10-18 之前，这些 bundle 位于仓库根 `spec/`，不在 `docs/` 的命名与链接守门范围内。迁移后 `naming-lint` 与 `link-check` 会覆盖本目录；外部引用（ADR-0017、docs/specs/021、Node 测试）已同步改为 `docs/specs/execution/...`。
