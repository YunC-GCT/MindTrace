# GitHub Issue / PR 对账（2026-10-18）

> 快照来源：`gh issue list --state all`（105 条）+ `gh pr list --state all`（112 条），仓库 `YunC-GCT/MindTrace`。
> 这是一次**状态对账**，不改变任何技术结论；处置建议在 §5。

> **执行后状态（同日）**：open 36 / closed 69。本轮关闭 37 个 issue（16 个已完成 + 10 个失效 spec + 11 个核验通过），#62 转 `ready-for-human`；PR #216 仍待 review。原始快照与处置依据保留在下方。

## 1. 总览

| 项 | 数量 |
|---|---|
| Issue 总数 | 105（open 73 / closed 32） |
| PR 总数 | 112（merged 98 / closed-unmerged 13 / open 1） |
| PR base 分支 | develop 98 · main 11 · 其他 3 |
| 默认分支 | `main`（`develop` 领先 913 commits，`main` 领先 develop 1 commit） |

标签分布（open issues）：

| 标签 | 数量 |
|---|---|
| `ready-for-agent` | 57 |
| `P1` | 23 |
| `enhancement` | 17 |
| `conversation-isolation` | 16 |
| `P2` | 11 |
| `P0` | 10 |
| `ready-for-human` | 9 |
| `refactor` | 9 |
| `P3` | 8 |
| `needs-triage` | 3 |
| `bug` | 2 |
| `needs-info` | 2 |
| `docs` | 1 |

## 2. 关键发现

1. **默认分支是 `main`，日常 PR 合入 `develop`。** GitHub 的 `Closes #N` 只在合入默认分支时自动关闭，所以一批已完成 issue 仍保持 open。
2. **16 个 open issue 已被合并 PR 用 closing keyword 明确声明关闭**（#145/#146/#147/#151/#153/#164/#165/#173/#174/#177/#178 ← #179；#183/#184/#186/#187 ← #193；#190 ← #194）。
3. **31 个 open issue 超过 30 天没有任何更新**；其中 10 个（#63–#72）指向一份 2026-09-07 已 revert 的 spec：`docs/specs/016-frontend-post-demo-polish.md`。当前 016 是 `016-llm-settings-redesign.md`，前端组件规范是 012。
4. **#93 的标题写“Spec 018”，但多端 UI 适配现在是 spec 022**（018 已是 agent workflow 架构）。
5. **唯一 open PR #216**（`feature/210-knowledge-model-behavior-baseline`）mergeable，但 `mergeStateStatus=BLOCKED`、`reviewDecision=REVIEW_REQUIRED`，缺 review 而不是缺代码。
6. **#11 是 Wayfinder map，评论明确写“issue 保持 OPEN”**，不要按普通 ticket 关闭。
7. **#62 的修复（PR #58）已在模拟器验证通过**，剩余拍照/相册入口的真机验收；当前仍是 `needs-triage + P0`，标签与实际状态不符。

## 3. Open issues 全量对账

| # | 标题 | 标签 | 最后更新 | 天数 | 相关 merged PR | 正文 spec 引用 | 建议 |
|---|---|---|---|---|---|---|---|
| #11 | [Wayfinder] D4 Kit 替换边界：鸿蒙 Kit 采用范围 |  | 2026-09-07 | 41 | #19, #24 | — | D · 保持 |
| #62 | OcrNode payload 断链修复 (已 PR #58) | bug, needs-triage, P0 | 2026-09-08 | 40 | — | — | B · 转人工验证 |
| #63 | 前端摸底 9 件套落地 (C1-C7 候选清单) | needs-triage, P1, docs | 2026-09-07 | 41 | — | 12, 16 | C · 重定界 |
| #64 | spec 016 评审后前端改造方案 (8 PR / 3 Phase) | enhancement, needs-triage, P1 | 2026-09-07 | 41 | — | — | C · 重定界 |
| #65 | MotionPolicy 动效收口 (spec 016 PR-A, C7 Strong) | enhancement, ready-for-agent, P1 | 2026-09-07 | 41 | — | — | C · 重定界 |
| #66 | MathTextRenderer 重分层 (spec 016 PR-B, C1 Strong) | ready-for-agent, P1, refactor | 2026-09-07 | 41 | — | — | C · 重定界 |
| #67 | IconButton 原子上收 + MathPreviewText 升分子 (spec 016 PR-C, C5) | ready-for-agent, P1, refactor | 2026-09-07 | 41 | — | 12 | C · 重定界 |
| #68 | i18n 骨架扩展 en/ 目录 + ResourceManager (spec 016 PR-D) | enhancement, ready-for-agent, P2 | 2026-09-07 | 41 | — | — | C · 重定界 |
| #69 | ErrorBanner 业务迁移 25 处 catch (spec 016 PR-E) | ready-for-agent, P1, refactor | 2026-09-07 | 41 | — | — | C · 重定界 |
| #70 | a11y 接入 5 类组件 (spec 016 PR-F) | enhancement, ready-for-agent, P2 | 2026-09-07 | 41 | — | — | C · 重定界 |
| #71 | Suspense / skeleton 接入 (spec 016 PR-G) | enhancement, ready-for-agent, P2 | 2026-09-07 | 41 | — | — | C · 重定界 |
| #72 | 性能上限: WebviewPool + LazyForEach 收口 (spec 016 PR-H) | ready-for-agent, P2, refactor | 2026-09-07 | 41 | — | — | C · 重定界 |
| #73 | 新功能 N2: 错题本自动归档 | enhancement, needs-info, P3 | 2026-09-07 | 41 | — | — | D · 未来功能 |
| #74 | 新功能 N3: 学习计划自动生成 | enhancement, needs-info, P3 | 2026-09-07 | 41 | #75 | — | D · 未来功能 |
| #82 | B2 refactor: AddCustomVendorCfg interface dedup(导出 from VendorPicker) | ready-for-agent, P3, refactor | 2026-09-08 | 40 | — | 17 | D · 保持 |
| #84 | B2 refactor: VM getCurrent* 折叠为 findCurrentVendor resolver | ready-for-agent, P3, refactor | 2026-09-08 | 40 | — | 17 | D · 保持 |
| #85 | B2 refactor: VendorPicker/VM Speculative Generality 清理 (3 sites: providers field / onEdit / openAddCustomVendor) | ready-for-agent, P3, refactor | 2026-09-08 | 40 | — | 17 | D · 保持 |
| #92 | Ticket #83 follow-up: 第二轮双轴审查(2-axis review) 验证 follow-up fixes |  | 2026-09-09 | 39 | #94 | 17 | D · 保持 |
| #93 | feat(entry): HarmonyOS 多端 UI 适配（Spec 018） | enhancement, ready-for-agent, P2 | 2026-09-09 | 39 | — | 18 | D · 保持 |
| #96 | feat: 增量式可验证笔记生成 | ready-for-agent | 2026-09-10 | 38 | #106, #107, #108, #109 | — | B · 核验后关闭 |
| #97 | feat(entry): 统一 KnowledgeUnit 写入与版本事务 | ready-for-agent | 2026-09-10 | 38 | #106, #107, #109 | — | B · 核验后关闭 |
| #98 | feat(agents): 生成严格校验的 light 草稿 | ready-for-agent | 2026-09-10 | 38 | #106, #107, #109 | — | B · 核验后关闭 |
| #99 | feat(entry): 预览并确认 AI 笔记草稿 | ready-for-agent | 2026-09-10 | 38 | #107, #109 | — | B · 核验后关闭 |
| #100 | feat(entry): 恢复草稿并精确消费生成来源 | ready-for-agent | 2026-09-10 | 38 | #107, #109 | — | B · 核验后关闭 |
| #101 | feat(agents): 验证 Evidence 并生成 standard 草稿 | ready-for-agent | 2026-09-10 | 38 | #107, #109 | — | B · 核验后关闭 |
| #102 | feat(agents): 受限修复并回滚最佳笔记候选 | ready-for-agent | 2026-09-10 | 38 | #107, #109 | — | B · 核验后关闭 |
| #103 | feat(agents): 结构优先生成 deep 长文笔记 | ready-for-agent | 2026-09-10 | 38 | #107, #109 | — | B · 核验后关闭 |
| #104 | feat(entry): 按新要求增量重生成已保存笔记 | ready-for-agent | 2026-09-10 | 38 | #107, #109 | — | B · 核验后关闭 |
| #105 | test: 验收增量式可验证笔记生成全链路 | ready-for-agent | 2026-09-10 | 38 | #107, #108, #109 | — | B · 核验后关闭 |
| #115 | hardening(chat reply): graceful stream/non-stream truncation fallback | enhancement, ready-for-agent, P2 | 2026-09-13 | 35 | #125 | — | B · 核验后关闭 |
| #118 | feat(entry): chat streaming incremental Markdown and LaTeX rendering | ready-for-agent | 2026-09-13 | 35 | #133 | 19, 20 | B · 核验后关闭 |
| #139 | perf(entry): ticket-1 renderer performance follow-up | ready-for-agent, P0 | 2026-09-21 | 27 | — | 21 | D · 保持 |
| #140 | feat(entry): ticket-1 RendererScheduler and RenderTick | ready-for-human, P0 | 2026-09-21 | 27 | — | 21 | D · 保持 |
| #141 | feat(entry): ticket-5 file-backed chat history persistence | ready-for-human, P0 | 2026-09-21 | 27 | — | 21 | D · 保持 |
| #142 | feat(entry): ticket-2 StreamingReplyDocument and native Reply Body projection | ready-for-human, P0 | 2026-09-21 | 27 | — | 21 | D · 保持 |
| #143 | feat(entry): ticket-3 integrate streaming chat list and geometry contract | ready-for-human, P0 | 2026-09-21 | 27 | — | 21 | D · 保持 |
| #144 | feat(entry): ticket-4 retire legacy chat renderer and isolate cache/accessibility | ready-for-human, P0 | 2026-09-21 | 27 | — | 21 | D · 保持 |
| #145 | fix(entry): bind conversation runs and callbacks to the originating session | ready-for-agent, P0, conversation-isolation | 2026-09-23 | 25 | #179 | — | A · 关闭 |
| #146 | fix(entry): cascade session deletion across file history and RDB memory | ready-for-agent, P0, conversation-isolation | 2026-09-23 | 25 | #179 | — | A · 关闭 |
| #147 | fix(entry): cooperatively cancel the originating conversation run | ready-for-human, P1, conversation-isolation | 2026-09-24 | 24 | #179 | 18 | A · 关闭 |
| #148 | perf(entry): coalesce chat snapshots before persistence materialization | enhancement, ready-for-agent, P2 | 2026-09-23 | 25 | — | 21 | D · 保持 |
| #149 | fix(entry): centralize conversation identity generation and boundary validation | ready-for-agent, P1, conversation-isolation | 2026-09-23 | 25 | — | — | D · 保持 |
| #150 | fix(entry): harden the versioned chat history decoder | ready-for-agent, P3, conversation-isolation | 2026-09-23 | 25 | — | — | D · 保持 |
| #151 | feat(entry): persist chat message origin, outcome, and context eligibility | ready-for-agent, P2, conversation-isolation | 2026-09-23 | 25 | #179 | 23 | A · 关闭 |
| #153 | feat(entry): add bounded multi-session conversation concurrency | ready-for-human, P1, conversation-isolation | 2026-09-24 | 24 | #179 | 18 | A · 关闭 |
| #154 | feat(entry): add manual chat session retention and cascade pruning | ready-for-agent, P3, conversation-isolation | 2026-09-23 | 25 | — | — | D · 保持 |
| #155 | refactor(entry): add version-aware chat snapshot decoder diagnostics | ready-for-agent, P3, conversation-isolation | 2026-09-23 | 25 | — | 21 | D · 保持 |
| #163 | fix(entry): bind conversation note drafts to their originating session | ready-for-agent, P1, conversation-isolation | 2026-09-23 | 25 | — | — | D · 保持 |
| #164 | fix(entry): isolate composer attachments and draft UI state per session | ready-for-agent, P1, conversation-isolation | 2026-09-23 | 25 | #179 | — | A · 关闭 |
| #165 | fix(entry): make chat context projection correlated and idempotent | ready-for-agent, P1, conversation-isolation | 2026-09-23 | 25 | #179 | — | A · 关闭 |
| #173 | fix(entry): route legacy detached drafts through explicit recovery | ready-for-agent, P0, conversation-isolation | 2026-09-26 | 22 | #179 | — | A · 关闭 |
| #174 | feat(entry): project workflow status and errors into the agent run timeline | ready-for-agent, P1, conversation-isolation | 2026-09-26 | 22 | #179 | 23 | A · 关闭 |
| #175 | chore(repo): align ArkTS headers and documentation path hygiene | ready-for-agent, P2 | 2026-09-26 | 22 | — | — | D · 保持 |
| #176 | fix(entry): make Review/Galaxy adapters ArkUI-1 compliant | ready-for-human, P2 | 2026-09-26 | 22 | — | — | D · 保持 |
| #177 | refactor(entry): shrink AgentChatService to a workflow facade | ready-for-agent, P1, refactor, conversation-isolation | 2026-09-26 | 22 | #179 | — | A · 关闭 |
| #178 | fix(entry): remove note-generation route leakage from chat run state | ready-for-agent, P2, conversation-isolation | 2026-09-26 | 22 | #179 | — | A · 关闭 |
| #182 | perf(entry): reduce NoteDetail render jank | enhancement, ready-for-agent, P1 | 2026-09-27 | 21 | #193 | 21, 22 | D · 保持 |
| #183 | feat(entry): auto-expand NoteDetail with visible-first scheduling | enhancement, ready-for-agent, P1 | 2026-09-27 | 21 | #193 | — | A · 关闭 |
| #184 | test(entry): lock NoteDetail MM-MD-v1 formula rendering contract | enhancement, ready-for-agent, P1 | 2026-09-27 | 21 | #193 | — | A · 关闭 |
| #185 | perf(entry): establish NoteDetail render baseline and state-scope metrics | enhancement, ready-for-agent, P1 | 2026-09-27 | 21 | — | — | D · 保持 |
| #186 | refactor(entry): scope NoteDetail rendering to an instance session | ready-for-agent, P1, refactor | 2026-09-27 | 21 | #193 | — | A · 关闭 |
| #187 | perf(entry): budget NoteDetail formula Web work and normalize cache | enhancement, ready-for-agent, P1 | 2026-09-27 | 21 | #193 | — | A · 关闭 |
| #188 | test(entry): validate formula-heavy NoteDetail performance on device | enhancement, ready-for-human, P1 | 2026-09-27 | 21 | — | — | D · 保持 |
| #189 | perf(entry): evaluate WebKeepAlive on target devices | enhancement, ready-for-agent, P1 | 2026-09-27 | 21 | — | — | D · 保持 |
| #190 | fix(note-generation): verifier failure triggers empty repair and repeated fingerprint | bug, ready-for-agent, P1 | 2026-09-28 | 20 | #194 | — | A · 关闭 |
| #209 | refactor(agents): extract KnowledgeModel internals without interface change | ready-for-agent | 2026-10-13 | 5 | — | — | D · 进行中 |
| #210 | test(agents): 建立 KnowledgeModel 行为基线与所有权守卫 | ready-for-agent | 2026-10-13 | 5 | — | — | D · 进行中 |
| #211 | refactor(agents): 提取 CaptureStructurer 并保持 Capture 行为 | ready-for-agent | 2026-10-13 | 5 | — | — | D · 进行中 |
| #212 | refactor(agents): 提取 DraftComposer 并保持 light/standard 行为 | ready-for-agent | 2026-10-13 | 5 | — | — | D · 进行中 |
| #213 | refactor(agents): 提取 DeepDraftComposer 并保持 deep 行为 | ready-for-agent | 2026-10-13 | 5 | — | — | D · 进行中 |
| #214 | refactor(agents): 提取 IncrementalPatchComposer 并保持增量改写行为 | ready-for-agent | 2026-10-13 | 5 | — | — | D · 进行中 |
| #215 | test(agents): 完成 KnowledgeModel 第一阶段集成验收 | ready-for-agent | 2026-10-13 | 5 | — | — | D · 进行中 |
| #217 | fix(note-generation): 统一草稿生命周期，修复重试检查点冲突与恢复确认不一致 | ready-for-agent | 2026-10-14 | 4 | — | — | D · 进行中 |

分组计数：D · 保持 24 · B · 转人工验证 1 · C · 重定界 10 · D · 未来功能 2 · B · 核验后关闭 12 · A · 关闭 16 · D · 进行中 8

## 4. PR 历史

### 4.1 合并主干上的几个大 PR

| PR | 合入 | base | 内容 |
|---|---|---|---|
| #179 | 2026-09-26 | develop | conversation isolation 11 个 issue 一次性收口（#145–#178 子集） |
| #193 | 2026-09-28 | develop | NoteDetail 渐进渲染 / 公式预算（#183/#184/#186/#187） |
| #194 | 2026-09-29 | develop | note verifier 只读化（#190） |
| #216 | **open** | develop | KnowledgeModel 业务拆分 + 增量保存修复；等 review |

### 4.2 closed-unmerged PR（13 个）

| PR | 标题 | 最后状态 |
|---|---|---|
| #191 | test(entry): reproduce verifier empty repair failure (#190) | closed |
| #170 | fix(note-generation): relax optional evidence gates | closed |
| #160 | fix(agents): stabilize note generation fallbacks | closed |
| #157 | fix(agents): stabilize note generation pipeline | closed |
| #131 | Feature/knowledge graph rdb | closed |
| #129 | Develop | closed |
| #87 | fix(common): LlmConfig normalizeModel/normalizeEndpoint vendor-aware + vm.save 迁移 | closed |
| #86 | feat(entry): PR2-T2 VendorPicker + polish (5 UI fix + UX 简化) | closed |
| #79 | feat(common): PR2-T1 - 5 厂商预设 + LlmConfig vendorId/customVendorConfig 字段 (spec 016) | closed |
| #76 | docs(agents): add backend-migration-handoff for teammate接手 | closed |
| #60 | fix(entry): 评审前最低修复包 — i18n 打磨 + 错误分级骨架 | closed |
| #18 | feat(agents): introduce CaptureGraph runtime and D2 dispatcher refactor | closed |
| #3 | docs(agents): adopt Git Flow lightweight for 3-person team | closed |

这些 PR 没有合入，代码以后续 PR 或本地分支为准；不要把它们当已交付证据。

## 5. 处置建议

| 组 | 数量 | 对象 | 建议动作 |
|---|---|---|---|
| A · 已完成未关闭 | 16 | #145/#146/#147/#151/#153/#164/#165/#173/#174/#177/#178/#183/#184/#186/#187/#190 | 关闭，评论写明“merged to develop via #179/#193/#194”；`main` 发版时不再重复处理 |
| B · 核验后关闭 | 12 | #96–#105、#115、#118 | 先按 spec 018 / 019 / 024 的验收记录逐条核验，再关闭；不要只凭 PR 提及就关 |
| B · 转人工 | 1 | #62 | 去掉 `needs-triage`，加 `ready-for-human`，评论指向 2026-09-08 模拟器验证记录与真机缺口 |
| C · 重定界 | 10 | #63–#72 | spec 016 前端稿已 revert；关闭为 `wontfix` 或重新挂到 spec 012 下的新 ticket，二选一，不要继续挂失效路径 |
| D · 保持（含未来/进行中） | 34 | #11、#73/#74、#209–#217、其余 | #11 按评论保持 OPEN；#73/#74 等产品决策；#209–#217 跟随 PR #216 |

## 6. 复现

```bash
gh issue list --repo YunC-GCT/MindTrace --state all --limit 300 \
  --json number,title,state,labels,updatedAt,body,comments
gh pr list --repo YunC-GCT/MindTrace --state all --limit 300 \
  --json number,title,state,mergedAt,baseRefName,headRefName,body
```

## 7. 与文档层的关系

- spec 覆盖状态以 [`docs/specs/index.md`](../specs/index.md) 为准；本文件只对账 GitHub 状态。
- 已删除的 spec / research 路径见 [`docs/legacy/mindtrace/index.md`](../legacy/mindtrace/index.md) 与 [`docs/research/index.md`](./index.md) 的 “Superseded / removed”。
- 仓库的 issue/PR 操作约定见 [`docs/agents/issue-tracker.md`](../agents/issue-tracker.md)。

## 8. 本轮已执行（2026-10-18）

| 组 | 关闭数 | Issue | 依据 |
|---|---|---|---|
| A · 已完成 | 16 | #145/#146/#147/#151/#153/#164/#165/#173/#174/#177/#178（#179）· #183/#184/#186/#187（#193）· #190（#194） | 合并 PR 的 closing keyword |
| B · 核验通过 | 11 | #96–#104 · #115 · #118 | 代码 + 测试均在 develop（见各 issue 关闭评论） |
| C · 失效 spec | 10 | #63–#72 | spec 016 前端稿 2026-09-07 已 revert |
| 标签修正 | — | #62 | `needs-triage` → `ready-for-human`，保留 P0 |

**未动**：#105（真机全链路验收）、#11（Wayfinder map，评论明确保持 OPEN）、#73/#74（P3 产品决策）、#209–#217（跟随 PR #216）。
