# Handoffs archive (frozen 2026-10-18)

> 这里存放**时间点交接 / 执行轨迹**，不是当前指引。现行流程看 `docs/agents/`，执行与验收看 `docs/specs/execution/`。
>
> 这些文档在 2026-10-18 之前位于 `docs/agents/`，与流程/指针文档混在一起。归档时只移动了位置并修正了内部相对链接，正文未改写。

| File | 原用途 | 状态 |
|---|---|---|
| [`handoff-2026-09-06.md`](./handoff-2026-09-06.md) | 复赛冲刺期 session 交接 | 历史 |
| [`handoff-langgraph-migration.md`](./handoff-langgraph-migration.md) | LangGraph 迁移计划 | **SUPERSEDED**（ADR-0008 改为自建 CaptureGraph） |
| [`backend-migration-handoff.md`](./backend-migration-handoff.md) | 后端 seam 推进路线图 | 被 spec 018 部分取代 |
| [`agent-run-timeline-handoff.md`](./agent-run-timeline-handoff.md) | Agent 运行时间线接入 | 历史（UI 与 reducer 已落地） |
| [`git-flow-setup-2026-09-04.md`](./git-flow-setup-2026-09-04.md) | Git Flow 落地清单 | 已执行；手册见 `docs/agents/git-flow-lightweight-2026-09-04.md` |
| [`llm-settings-scope-2026-09-06.md`](./llm-settings-scope-2026-09-06.md) | LLM 设置页重构 scope 决策轨迹 | 历史；设计见 `docs/specs/016-llm-settings-redesign.md` |
| [`llm-settings/`](./llm-settings/) | LLM 设置 PR0–PR2 的 4 篇执行记录 | 历史 |
| [`note-generation-fix-handoff-2026-09-20.md`](./note-generation-fix-handoff-2026-09-20.md) | 笔记生成链路修复 session 交接 | 部分结论被 ADR-0018 取代 |
| [`note-generation-failure-diagnostics-handoff-2026-09-29.md`](./note-generation-failure-diagnostics-handoff-2026-09-29.md) | 生成失败诊断取证 | 历史 |
| [`qwen-deepseek-reasoning-handoff-2026-09-12.md`](./qwen-deepseek-reasoning-handoff-2026-09-12.md) | Qwen3.5 / DeepSeek 推理开关矩阵 | 历史（设置页已按此实现） |

## 为什么冻结

交接文档只在写它的那个时间点成立；一旦代码前进，它就会与现状冲突。把它们留在 `docs/agents/` 会让新 session 把过期结论当当前指引。归档后仍可追溯“当时为什么这么做”，但当前答案只看 ADR / spec / 代码。
