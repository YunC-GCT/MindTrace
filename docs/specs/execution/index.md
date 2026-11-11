# Execution bundles index

> 本目录存放**执行记录**，不存放设计决策。设计决策在 `docs/specs/NNN-*.md` 与 `docs/adr/`。

## 一个 bundle 里有什么

| 文件 | 作用 |
|---|---|
| `spec.md` | 冻结范围与验收条件（写实现前）。**头部的 `Status: Draft` 是 Spec-Kit 模板样板，不作为结论**；结论看 `verification-*` |
| `plan.md` | 实施计划与文件级落点 |
| `tasks.md` | 勾选式任务与逐项证据 |
| `verification-record.md` / `verification-report.md` | 实际执行的验证结果（结论以它为准，不以 `spec.md` 的 Draft 字样为准） |
| `delivery-checklist.md` / `review-report.md` | 交付清单 / code review 结论（部分 bundle 才有） |
| `raw/` | 原始测量数据（如渲染基准 JSONL），测试会直接读取，移动目录时必须同步改测试路径 |

## Bundles

| Bundle | 设计规格 | GitHub | 内容 | 状态（以包内 verification 为准） |
|---|---|---|---|---|
| [`019-reasoning-process-display-p0/`](./019-reasoning-process-display-p0/) | [spec 019](../019-reasoning-process-display-p0.md) | `#111` **closed** 2026-09-13 | spec / plan / tasks / verification-report / delivery-checklist / review-report | **`PASS`**（`Final status: PASS`；`spec.md` 的 Draft 是模板样板） |
| [`021-review-remediation/`](./021-review-remediation/) | [spec 021](../021-chat-streaming-incremental-rendering.md) | `#140` / `#141` **open** | spec / plan / tasks | Draft，**无 verification**（未收官） |
| [`restore-arkweb-warmup/`](./restore-arkweb-warmup/) | [ADR-0017](../../adr/0017-renderer-scheduler-budget-baseline.md) | `#119` **closed** 2026-09-17 | spec / plan / tasks | Draft，**无 verification**（票已闭、包未收尾） |
| [`ticket-0-2-stable-chat-key-refresh/`](./ticket-0-2-stable-chat-key-refresh/) | spec 021 §验证 | `#120` **closed** 2026-09-17 | spec / plan / tasks / verification-record | **`PASS`**（2026-09-14 复核覆盖了 spec 头部的 `INCOMPLETE`；只放行「下游设计可考虑」，生产聊天路径未改） |
| [`ticket-0-3-chat-filesdir-seam/`](./ticket-0-3-chat-filesdir-seam/) | spec 021 §验证 | `#121` **closed** 2026-09-17 | spec / plan / tasks / verification-record | **`PASS`** |
| [`ticket-0-5-customspan-placeholder-seam/`](./ticket-0-5-customspan-placeholder-seam/) | spec 021 §验证 | `#123` **closed** 2026-09-15 | spec / plan / tasks / verification-record | **`PASS`** |
| [`ticket-0-6-chat-render-fixtures-budgets/`](./ticket-0-6-chat-render-fixtures-budgets/) | [ADR-0017](../../adr/0017-renderer-scheduler-budget-baseline.md) | `#124` **closed** 2026-09-17 | spec / plan / tasks / verification-record / `raw/*.jsonl` | **`PASS`**（4×20 raw 证据） |
| [`v7-architecture-contracts/`](./v7-architecture-contracts/) | [#237–#242](https://github.com/YunC-GCT/MindTrace/issues/237) · [§17 目标态](../../system-architecture-layered.md) | `#237`–`#242` 全部 **open** | plan（含交接说明）/ tasks | `in-progress`（2026-10-30：#237/#239 完成 · #238 约 60% · #241 切片 1 完成，待真机） |
| [`archive-2026-09.md`](./archive-2026-09.md) | #97 / #98 / 编译修复 / 生成稳定性 | `#97` `#98` **closed** 2026-10-18（批量） | 合并记录（4 个残包） | — |

`feature.json` 是 Spec-Kit 工具的元数据，不是 bundle。`archive-2026-09.md` 是 4 个残包的合并记录，不是在执行包。

## 新增 bundle 的规则

1. 目录名用 kebab-case，优先复用设计规格的 `NNN-slug`：`execution/019-reasoning-process-display-p0/`。
2. 文件名固定为 `spec.md` / `plan.md` / `tasks.md` / `verification-record.md`，不另起别名。
3. 设计变更写回 `docs/specs/NNN-*.md` 或 ADR，不在 bundle 里改设计。
4. `raw/` 只放可复现的原始数据；测试或文档引用它的路径时，移动目录必须同 commit 修正引用。
5. 完成且不再维护的 bundle 保留在原位（它是可追溯证据），不要删；只有内容被新 bundle 完全取代时才加 `## Superseded` 说明。
6. **只有 verification-record 的不算 bundle**（没有 spec/plan/tasks 的施工记录），并入 `archive-YYYY-MM.md`；`spec.md` 头部 `Status: Draft` 是 Spec-Kit 样板，不作为结论。

## 与旧位置的关系

2026-10-18 之前，这些 bundle 位于仓库根 `spec/`，不在 `docs/` 的命名与链接守门范围内。迁移后 `naming-lint` 与 `link-check` 会覆盖本目录；外部引用（ADR-0017、docs/specs/021、Node 测试）已同步改为 `docs/specs/execution/...`。
