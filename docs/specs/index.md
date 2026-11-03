# Specs index

This directory holds **implementation specs** for the P0/P1 tickets identified in the
2026-09-01 audit ([`docs/legacy/mindtrace/audit-full-2026-09-01.md`](../legacy/mindtrace/audit-full-2026-09-01.md)). Each spec is derived from
an ADR (`docs/adr/`) and follows the same template.

## 编号约定

**spec 编号是文档序号，与 GitHub issue 号无关。** 003–015 标题里的 `Ticket #3` / `#7` / `#11` 指的是 2026-09-01 审计报告里的 ticket 序号（[`audit-full-2026-09-01.md`](../legacy/mindtrace/audit-full-2026-09-01.md)）；GitHub 上恰好也有 `#9` / `#10` / `#11`，但那是 Wayfinder 的 D2/D3/D4，与 spec 009/010/011 不是一回事。要查一张票的实况，看下表的 **GitHub** 列，别按 spec 编号去搜 issue。

**状态口径**：以 spec 头部 + 代码实测为准。GitHub 的 `CLOSED` 不能当交付证据——2026-10-18 10:45–10:48 两分钟内批量关闭了 37 张票，其中有的从未落过代码（例：`#65 MotionPolicy` 在 git 历史里 0 命中）。

## Coverage map

| Ticket | Spec | ADR | Status |
|--------|------|-----|--------|
| **#3** | [`spec-003-knowledge-model-decomposition.md`](../legacy/mindtrace/spec-003-knowledge-model-decomposition.md) | [`0006`](../adr/0006-knowledge-model-decomposition-plan.md) | **superseded by [`015`](./015-knowledge-model-decomposition-v2.md)**，原文 2026-10-30 归档 legacy（2026-09-06；ADR-0006 amended） |
| **#4** | [`004-dispatcher-single-entry.md`](./004-dispatcher-single-entry.md) | [`0003`](../adr/0003-dispatcher-single-entry-design.md) | **implemented** (D2, 2026-09-05) |
| **#5** | [`005-llm-client-consolidation.md`](./005-llm-client-consolidation.md) | [`0004`](../adr/0004-llm-call-layer-consolidation.md) | **implemented** (2026-09-06) |
| **#7** | [`spec-007-agent-chat-service-decomposition.md`](../legacy/mindtrace/spec-007-agent-chat-service-decomposition.md) | (implicit) | **terminal shape superseded by 018**，原文 2026-10-30 归档 legacy — IntentClassifier/ChatStatusMachine retained; ConversationWorkflow owns orchestration; AgentChatService 约 70 LOC facade |
| **#9** | [`009-llm-config-throw-on-silent-override.md`](./009-llm-config-throw-on-silent-override.md) | (implicit, defensive coding principle) | **implemented** (TDD) |
| **#10** | [`010-mcp-to-tools-rename.md`](./010-mcp-to-tools-rename.md) | [`0005`](../adr/0005-mcp-to-tools-rename.md) | **reverted** (2026-09-06, [ADR-0010](../adr/0010-mcp-tools-semantics.md) — OcrTool 是 MCP 工具, `mcp/` 保留) |
| **#11 / D2** | [`011-capturegraph-arkts-refactor.md`](./011-capturegraph-arkts-refactor.md) | [`0008`](../adr/0008-capturegraph-self-built-runtime.md) | **implemented** (D2, 2026-09-05; see [teaching doc](../agents/d2-capturegraph-teaching-2026-09-05.md)) |
| **#12 / D3** | [`012-frontend-component-model.md`](./012-frontend-component-model.md) | (spec-driven) | **in progress** — `shared/components` split into atoms/molecules/organisms; overlay/service migration pending |
| **#13 / D4** | [`013-kit-adoption-boundary.md`](./013-kit-adoption-boundary.md) | [`0009`](../adr/0009-kit-facade-injection-boundary.md) | **P0 implemented** (2026-09-10 — Reminder/BackgroundTask/FormCard real adapters + composition root; Reminder UI entry remains deferred) |
| **F1 / 体检 2026-09-06** | [`014-tool-calling-protocol.md`](./014-tool-calling-protocol.md) | [`0012`](../adr/0012-tool-calling-protocol.md) | **implemented** (2026-09-06 — 协议/ToolRegistry/ToolLoop + P1 只读工具 note_query/note_get/review_due_query) |
| **#3 / v2** | [`015-knowledge-model-decomposition-v2.md`](./015-knowledge-model-decomposition-v2.md) | [`0006`](../adr/0006-knowledge-model-decomposition-plan.md) (amended) | **done** (PR1-PR3, 2026-09-06 — 三协作服务拆出, KnowledgeModel 保留为编排 agent) |
| **LLM settings redesign** | [`016-llm-settings-redesign.md`](./016-llm-settings-redesign.md) | [`0013`](../adr/0013-llm-provider-presets.md) · [`0014`](../adr/0014-asset-store-kit-migration.md) | **implemented via 017** (2026-09-06 设计 · 2026-09-08 六个 sub-task 落地；代码 `pages/AiSettings/AiSettingsPage.ets` + `VendorPicker.ets` + `viewmodels/AiSettingsViewModel.ets`；`#83` 已闭) |
| **PR2-T2 cleanup** | [`017-llm-settings-cleanup.md`](./017-llm-settings-cleanup.md) | (implicit, spec 016 后续;承接 ticket #9) | **implemented** (2026-09-08 — L1–L6 六个 sub-tasks 完成) |
| **Agent workflow architecture** | [`018-agent-workflow-architecture.md`](./018-agent-workflow-architecture.md) | [`0008`](../adr/0008-capturegraph-self-built-runtime.md) (scope clarified) | **implemented, device acceptance pending** (2026-09-10 — shared StateGraph + Capture/ToolCalling/Conversation/Skill workflows; single backend) |
| **Reasoning display P0** | [`019-reasoning-process-display-p0.md`](./019-reasoning-process-display-p0.md) | [`0015`](../adr/0015-structured-stream-events.md) | **implemented & accepted** (2026-09-13 — `StreamEvent` 已在 14 个文件；`#110`–`#114` 验收通过；bundle `verification-report.md` 末尾 `Final status: PASS`；头部已同步) |
| **Reply body contract** | [`020-reply-body-contract.md`](./020-reply-body-contract.md) | [`0016`](../adr/0016-reply-contract-by-transport.md) | **partial** (2026-09-12 设计；`ReplyService` + `StreamingReplyDocument` 已落地，但 `ReplyBody` 作为独立类型未引入——契约当前靠 transport 分流实现；P2 LlmGuard 容错提取已随 #115 关闭) |
| **Chat streaming render** | [`021-chat-streaming-incremental-rendering.md`](./021-chat-streaming-incremental-rendering.md) | [`0017`](../adr/0017-renderer-scheduler-budget-baseline.md) | **implemented in develop; device acceptance pending** (2026-10-18 — RendererScheduler / RenderTick / StreamingReplyDocument landed 2026-09-18/19; #118 closed; execution records [`execution/ticket-0-*`](./execution/)） |
| **022 / multi-device UI** | [`022-multi-device-ui-adaptation.md`](./022-multi-device-ui-adaptation.md) | (implicit; research + codebase-design) | **ready; implementation deferred** (2026-09-08 — tracking issue `#93`，该 issue 标题误写「Spec 018」) |
| **Agent run timeline** | [`023-agent-run-timeline-foundation.md`](./023-agent-run-timeline-foundation.md) | [`0015`](../adr/0015-structured-stream-events.md) | **foundation implemented; workflow emission pending** (2026-09-21 — `RunEvent` / `AgentRunEvent` 已在 5 个文件；workflow 主动上报仍未接) |
| **NoteDetail render performance** | [`024-note-detail-render-performance.md`](./024-note-detail-render-performance.md) | [`0017`](../adr/0017-renderer-scheduler-budget-baseline.md) · [`021`](./021-chat-streaming-incremental-rendering.md) | **in progress** (2026-09-28 — #182/#185 evidence landed; #189 emulator A/B keeps WebKeepAlive default-off; #188 blocked by #187 + target-device evidence) |
| **Knowledge graph RDB** | [`026-knowledge-graph-rdb.md`](./026-knowledge-graph-rdb.md) | [`0006`](../adr/0006-knowledge-model-decomposition-plan.md) · [`015`](./015-knowledge-model-decomposition-v2.md) | **implemented (merged to develop)** (2026-09-17 — 空 `kg_edge`、统一关系写入、accepted 边图谱查询、RAG demo 预留表) |
| **Note review answer** | [`027-note-review-answer.md`](./027-note-review-answer.md) | [`0018`](../adr/0018-note-evidence-provenance.md) | **implemented, 验收未记录** (2026-09-26 — `services/NoteReviewService.ets` 已存在并被 ConversationWorkflow 调用；真机验收记录缺失) |
| **v1 端A2A** | [`031-xiaoyi-batch-capture-entry.md`](./031-xiaoyi-batch-capture-entry.md) | (spec-driven, 端A2A 协议在 [skill]) | **in progress** (2026-10-23 — P1 半屏浮窗入口 / P2 多选 / P3 落库；T5 异步取消除外) |
| **模型网关 + 端A2A 运行时** | [`032-model-gateway-and-a2a-runtime.md`](./032-model-gateway-and-a2a-runtime.md) | (spec-driven，依据两份 research) | **partial** (2026-10-24 — 构建顺序 / 单帧快照 / 端侧能力位已落地，#219–#223 已闭；`services/ModelRouter.ets` 接进 `ConversationWorkflowPorts`，#220 关闭；「网关注册表」仍未定型) |
| **进程边界** | [`033-process-boundaries.md`](./033-process-boundaries.md) | (spec-driven，依据 2026-10-24 事故) | **accepted, S1 落地** (2026-10-24 — 可见性矩阵 + 受限 Kit 清单已进 gate，每轮 `process-boundary` 都在跑；S2/S3 待定。与正文头部口径已统一) |
| **#230 文搜图线程隔离** | [`034-image-search-isolation.md`](./034-image-search-isolation.md) | (spec-driven，依据 2026-10-25 真机阻塞实测) | **implemented** (2026-10-25 — Worker 常驻 + 5s 降级，真机两轮 PASS，见 §8) |
| **v1 收尾：回执 + 合规** | [`035-v1-closeout-receipt-and-compliance.md`](./035-v1-closeout-receipt-and-compliance.md) | (spec-driven，依据 phase-tracker P4 回执 / P5 合规缺口) | **proposed** (2026-10-25 — 回执落盘 + 最小 Markdown 导出与 AI 标识) |
| **多图汇总整理** | [`036-multi-image-single-pass-consolidation.md`](./036-multi-image-single-pass-consolidation.md) | (spec-driven，依据 P2 多选入口 + 一图多题 / 多图多题场景) | **阶段 1 落地，2–5 未动** (2026-10-28 — `0c60f21` 提交 `segmentProblems` / `mergeProblems` 纯函数；`AgentState` 字段、接线、确认闸门未做；D1–D4 待拍板) |

## Execution bundles

`docs/specs/execution/` holds the execution record for a spec or ticket: `spec.md`（冻结范围）、`plan.md`（实施计划）、`tasks.md`（勾选任务）、`verification-record.md` / `verification-report.md`（证据）、`raw/`（原始测量数据）。设计决策仍写在编号 spec 里；这里只记录“怎么改的、验到哪一步”。索引见 [`execution/index.md`](./execution/index.md)。

## P0 tickets without spec

| Ticket | Status |
|--------|--------|
| **#1** (doc expiry) | meta — not a refactor, just self-referential cleanup |

## Implementation status (2026-09-06)

Done:
- **#4** Dispatcher single-entry — landed with D2
- **#5** LlmClient consolidation — 单一 `call(request)`, 真 SSE 流式, 死路已删
- **#9** LlmConfig throw-on-silent-override — TDD
- **D2 / spec 011** end-to-end — CaptureGraph + 5 nodes + conditional persist edge, Dispatcher 旧 API 已删

Remaining (recommended order):
1. ~~**#7** AgentChatService decomposition~~ — terminal shape superseded and implemented by spec 018 ConversationWorkflow
2. ~~**F1 / spec 014 P1**~~ — implemented (2026-09-06); write tools gated on F2 write-path unification

After all of these, the architecture matches ADR intent:
- ✅ Dispatcher has 1 public method
- ✅ LlmClient has 1 public method (call + adapters)
- ✅ KnowledgeModel slimmed to orchestrating agent + 3 collaborator services (spec 015)
- ✅ AgentChatService is a ~70 LOC UI facade; ConversationWorkflow owns orchestration
- 🚫 `mcp/` stays — ADR-0005 superseded by [ADR-0010](../adr/0010-mcp-tools-semantics.md); `tools/` reserved for CRUD tools

## How to read a spec

Each spec has these sections:

1. **Why this ticket** — context, the problem, the gap
2. **What we will build** — the new shape (types, classes, signatures)
3. **Public surface change** — what's breaking, what isn't
4. **Migration** — atomic PR sequence, file moves
5. **Test plan (TDD)** — what tests to write
6. **Reversibility** — how hard to undo
7. **Acceptance criteria** — explicit checklist
8. **Sequence** — concrete commit list
9. **Out of scope** — explicit non-goals

## Specs

- [`036-multi-image-single-pass-consolidation.md`](./036-multi-image-single-pass-consolidation.md) — 一次整理：1..N 张图 → 多题汇总（一图多题/多图多题/确认页）
- [`038-write-job-scheduler.md`](./038-write-job-scheduler.md) — 笔记写入工作调度器：WriteJob 双通道队列/并发/观测（S0 实验 + S1 MVP）
- [`037-rag-retrieval-data-augmentation.md`](./037-rag-retrieval-data-augmentation.md) — RAG 检索：复用 DataAugmentationKit retrieval（FTS/BM25）+ 现有 LLM
- [`039-agent-workflow-first.md`](./039-agent-workflow-first.md) — Agent 编排收口：CommandExecutor + CommandRouter + 四条 workflow（S1–S3，golden 零重录；四条 workflow 均为实体实现）
- [`040-writejob-persistence-cross-process.md`](./040-writejob-persistence-cross-process.md) — WriteJob 持久队列：agent_job v20 + 队列单执行者 + 跨进程 handoff（038 S3）；A2A 单次整理内联
- [`041-chat-tool-loop.md`](./041-chat-tool-loop.md) — Chat 工具回复：ToolLoop 接入 conversation workflow（默认关闭，无行为变更）
- [`042-a2a-error-taxonomy.md`](./042-a2a-error-taxonomy.md) — A2A 错误码 / 分类 / 用户文案统一映射
- [`043-data-retention.md`](./043-data-retention.md) — 数据保留与清理：A2A 上下文 7 天 / run 与 job 历史 30 天

## Conventions in these specs

- **Atomic PRs only** — each commit is revertable
- **TDD red→green→refactor** — test first, then implementation
- **TDD at the AST level** — when feasible, write Node tests that parse the .ets file's AST and assert structure (sees tests run in the arkts-lint framework, not in DevEco)
- **No new ADRs** — every spec is derived from an existing ADR (or marked "implicit" when the ADR is the same philosophy applied to a sibling class)
- **No global renames** — each spec stays local to its ticket scope

## Cross-references

- [`docs/legacy/mindtrace/audit-full-2026-09-01.md`](../legacy/mindtrace/audit-full-2026-09-01.md) — original audit (archived)
- [`docs/legacy/mindtrace/deep-dive-2026-09-01.md`](../legacy/mindtrace/deep-dive-2026-09-01.md) — 7 largest files analyzed (archived)
- [`docs/adr/`](../adr/) — Architecture Decision Records (the "why")
- [`docs/specs/`](./) — this directory (the "what" + "how")
- [`CONTEXT.md`](../../CONTEXT.md) — project glossary
- [`AGENTS.md`](../../AGENTS.md) — agent entry point
- [`.github/workflows/arkts-lint.yml`](../../.github/workflows/arkts-lint.yml) — CI guardrail
