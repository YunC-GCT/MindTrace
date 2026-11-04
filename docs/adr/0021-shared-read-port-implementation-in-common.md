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
3. 全文检索（`note_query_rag`）**不进 `NoteReadPort`**，由独立 `NoteSearchPort` 承载（已落地，`ports/impl/NoteSearchRanking` + `RdbNoteSearchAdapter`）；读端口的 `search` 只匹配元数据。
4. **`note_query` 暂留工具层特例**（2026-10-30 决策）：它的 keyword 同时命中 `title` 与 `content`，横跨「读端口（元数据）」与「检索端口（必须有关键词）」的语义边界，硬映射会改变行为。现状保留直查并在文件头标注；若将来需要复用，应新增 `NoteFilterPort`（带 `reviewStatus` 等过滤面的查询端口），而不是扩宽 `NoteReadPort`。

## Consequences

- 好处：`skill` 终于有一条不依赖 `entry` 的读路径；读实现只有一份，不会出现两套 row mapping 漂移。
- 代价：`common` 进一步变重；`ports/impl/` 必须有明确准入——只允许「跨 HAP 需要 + 只读」的实现进 common。
- 对 §17.5 的修订：原文「实现 entry」改为「读实现 common / 写实现 entry」。
- 迁移顺序：先只读（`NoteReadPort` / `StudyPlanReadPort`），再工具层（`NoteQueryTools` 注入端口），写路径不动。

## Considered Options

- **组合根注入**：只在 `entry` 内成立；`skill` 仍要自带实现，等于两套映射。
- **写实现也放 common**：`agents` 能 import common，直接破坏「编排层不写库」。
- **新建 `infra` module**：违反红线 5（不新建第 6 个 module）。

## 补充：barrel 边界与例外说明（2026-11-04）

`common` 的模块准入在 2026-11-04 收紧为「≥2 个模块或 ≥2 个进程真实使用，且不含业务阈值 / 用户文案 / 配色」（见 [`AGENTS.md`](../../AGENTS.md) §模块归属判据）。**本 ADR 允许的只读实现是这个准入规则的有意例外**，不是漏网：

- 例外内容：`common/src/main/ets/ports/impl/`（`NoteReadPortAdapter` / `RdbNoteReadStore` / `RdbNoteSearchAdapter` / `ReviewReadPortAdapter` / `RdbReviewReadStore`）与 `tools/NoteQueryTools`。
- 理由：`skill` / `cardservice` 两个 HAP 依赖 `common` 而不依赖 `entry`，只读投影必须跨 HAP 共享；这条在 §Context 已论证。
- 代价控制：**这些实现不进 `common/Index.ets` barrel**，消费方（`EntryAbility`、`ohosTest`）按文件深路径引用；`ToolCatalog.createReadOnlyRegistry()` 是工具层的唯一正门。这样即便文件在 common，也不会被每个 `import 'common'` 顺带加载。

同时明确一条**新边界**（与上面的例外区分）：

| 能力 | 契约 | 实现 | 原因 |
|---|---|---|---|
| 只读投影（笔记 / 复习 / 检索排序） | `common/ports/` | `common/ports/impl/` | 跨 HAP 共享（本 ADR） |
| 证据检索 / 图谱扩展 | `common/ports/NoteEvidenceDataPorts` | `entry/services/RagNoteEvidenceSearch`、`RdbNoteGraph` | 依赖 FTS / 工具兜底 / `KnowledgeRelationDao`，只有 entry 消费 |
| 写路径 | `common/ports/NoteWritePort` | `entry/database/` | 只有应用进程能写库 |

判断顺序：**先看有没有第二个 HAP 要用，再看实现是否只读**；两者都成立才进 `common/ports/impl/`，否则留在 `entry`。
