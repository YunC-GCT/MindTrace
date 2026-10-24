# Architecture snapshots index

> 本目录存放**某一时点的架构快照**：链路总览、工具清单、迁移基线、窗口布局策略。
> 与 `docs/research/` 的区别：research 是调研过程与证据，architecture 是对当前实现的稳定描述。
> `Design proposals` 区是例外：描述目标态设计，不代表当前实现。

| File | Date | 内容 |
|---|---|---|
| [`agent-tool-chain-2026-09-06.md`](./agent-tool-chain-2026-09-06.md) | 2026-09-06 | Agent tool 派发链总览（Conversation → ToolLoop → ToolRegistry） |
| [`agent-tools-inventory-2026-09-06.md`](./agent-tools-inventory-2026-09-06.md) | 2026-09-06 | 工具清单与增删查改边界（F7） |
| [`langgraph-migration-baseline-2026-09-09.md`](./langgraph-migration-baseline-2026-09-09.md) | 2026-09-09 | LangGraph 迁移前基线 |
| [`langgraph-terminology-map-2026-09-09.md`](./langgraph-terminology-map-2026-09-09.md) | 2026-09-09 | LangGraph 术语 ↔ 本项目命名对照 |
| [`window-layout-strategy-2026-09-08.md`](./window-layout-strategy-2026-09-08.md) | 2026-09-08 | 窗口 / 浮层布局策略 |

## Design proposals (target state)

> 目标态设计提案，不代表当前实现；用于评审 / 交接给外部 Agent。

| File | Date | 内容 |
|---|---|---|
| [`agent-application-architecture-design-2026-10-20.md`](./agent-application-architecture-design-2026-10-20.md) | 2026-10-20 | 应用 / Agent / 信息流目标态：Dispatcher 主 Agent、子图、自研 LangGraph 风格内核 |

## 命名与维护

- 文件名：`{scope}-{YYYY-MM-DD}.md`（见 `docs/style/naming-conventions.md` §3.6）
- 架构变化时**新建**快照并把旧文件标注 `Superseded by ...`，不要原地改写历史判断
- 当前权威结论仍以 `docs/adr/` + `docs/specs/018-agent-workflow-architecture.md` 为准；本目录是描述性快照
