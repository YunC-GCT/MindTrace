# Execution archive — 2026-09 残包

> 2026-10-30 合并：4 个只有骨架或单文件的执行包并入本文件，原目录已删除（原文见 git 历史）。
> 本文件不是设计规格——设计落点在代码与 `docs/specs/NNN-*.md`。

| 原目录 | 是什么 | 结局 |
|---|---|---|
| `097-knowledge-unit-write-service/` | Issue #97 的执行包（spec 16 行 / plan 18 行 / tasks 33 行） | **已交付** |
| `098-light-note-generation/` | Issue #98 的执行包（spec 23 行 / plan 17 行 / tasks 31 行） | **已交付** |
| `entry-arkts-compile-fix/` | 2026-09-16 Entry ArkTS 编译修复（只有 verification-record，158 行） | **一次性编译记录，无后续** |
| `note-generation-stability/` | 2026-09-21 笔记生成稳定性（只有 plan，588 行） | **计划已归档** |

## #97 统一 KnowledgeUnit 写入

验收条件（原文摘要）：手写新建 / 手写更新 / AI 落库走同一个写入口；KnowledgeUnit 与 revision 同事务；按 note ID + 期望版本更新，未命中返回 `VERSION_CONFLICT`；revision 可按 note ID + 版本查询，保留完整 KnowledgeUnit 与生成元数据；迁移时幂等回填历史行；提交后副作用失败只报 warning。

落点：`common/src/main/ets/models/KnowledgeUnitWriteModels.ets`、`entry/src/main/ets/adapters/NoteDaoAdapter.ets`、`entry/src/main/ets/database/NoteDao.ets`（`note_revision` 表）、`common/src/main/ets/DatabaseHelper.ets`（建表与迁移）。

## #98 light 草稿与可恢复生成

验收条件（原文摘要）：`Dispatcher.dispatch` 仍是唯一 Capture 入口，接受带类型的 `NoteGenerationRequest`；来源片段保序且带稳定 ID / 指纹 / 原文；短材料或单来源确定性选 `light`；`KnowledgeModel` 拥有 light Structure，模型流量一律走 `LlmClient.call`；`persist=false` 时零写库，只留可恢复产物。

落点：`entry/src/main/ets/database/NoteGenerationRepository.ets`、`entry/src/main/ets/services/NoteGenerationRepositoryFactory.ets`、`entry/src/main/ets/services/AiService.ets`。

## entry-arkts-compile-fix

2026-09-16 的一次性编译核查：`arkts_check entry/src/main/ets/services/AiService.ets` 与 `.../adapters/NoteDaoAdapter.ets` 均返回 `Result: No errors found in 1 file(s).`；T019–T022 验证任务始终未执行。没有计划、没有任务清单，不构成可复用的执行包。

## note-generation-stability

588 行实施计划，目标是把 light/standard/deep 三条路由里靠模型输出的结构字段改成确定性回退（`common/src/main/ets/models/NoteGenerationModels.ets` 的归一化助手），保持 `ConversationWorkflow → AiService → Dispatcher → KnowledgeModel` 公开流程不变。计划本身完整，缺 spec / tasks / verification 三件，已移入 [`../../../legacy/mindtrace/note-generation-stability-plan-2026-09-21.md`)](../../legacy/mindtrace/note-generation-stability-plan-2026-09-21.md)。
