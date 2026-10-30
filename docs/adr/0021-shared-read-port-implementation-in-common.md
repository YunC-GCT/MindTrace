# 只读端口的实现放 common，写实现留 entry

## Status

accepted（2026-10-30）

## Context

§17.5 原口径是「接口 common，实现 entry」。但本仓库是 **3 HAP + 2 HSP** 拓扑，且红线明确不新建第 6 个 module：

- `skill` HAP 只能依赖 `common` 与 `agents`（`skill/oh-package.json5`），**import 不到 `entry` 里的适配器**；
- `entry` 里的 `NoteDao` 是写路径 DAO（事务 + commit 记录），给只读场景复用会把写能力带进读路径；
- `common` 已经持有 `@kit.ArkData` 与 `DatabaseHelper`，把只读实现放进去不新增任何 Kit 边界；
- Node 契约测试会直接装载 service/适配器源码，value-import 带 `@kit.ArkData` 的 entry 实现会让 loader `MODULE_NOT_FOUND`。

## Decision

按「读写分离」而不是「模块一刀切」：

| 层 | 归属 | 说明 |
|---|---|---|
| 契约（Port / DTO） | `common/src/main/ets/ports/` | 不变 |
| 只读实现（投影、只读 SQL） | `common/src/main/ets/ports/impl/` | `skill` / `cardservice` / `entry` 都能用 |
| 写实现（事务、commitKey、审批） | `entry/src/main/ets/database/` | 只有应用进程能写库，`agents` 永不 import |
| 文件/沙箱产物实现 | `entry` | 产物路径属应用沙箱 |

补充约束：

1. **`agents` 只能 import `ports/`，永不 import `ports/impl/`** —— 编排层不碰 RDB，写路径必须由调用方注入。
2. 只读端口返回**投影**（`NoteSummary` / `NoteDetail`），不返回整行 `KnowledgeUnit`；避免把写模型泄漏给只读消费者。
3. 全文检索（`note_query_rag`）**不进 `NoteReadPort`**，另行定义 `NoteSearchPort`；读端口的 `search` 只匹配元数据。

## Consequences

- 好处：`skill` 终于有一条不依赖 `entry` 的读路径；读实现只有一份，不会出现两套 row mapping 漂移。
- 代价：`common` 进一步变重；`ports/impl/` 必须有明确准入——只允许「跨 HAP 需要 + 只读」的实现进 common。
- 对 §17.5 的修订：原文「实现 entry」改为「读实现 common / 写实现 entry」。
- 迁移顺序：先只读（`NoteReadPort` / `StudyPlanReadPort`），再工具层（`NoteQueryTools` 注入端口），写路径不动。

## Considered Options

- **组合根注入**：只在 `entry` 内成立；`skill` 仍要自带实现，等于两套映射。
- **写实现也放 common**：`agents` 能 import common，直接破坏「编排层不写库」。
- **新建 `infra` module**：违反红线 5（不新建第 6 个 module）。
