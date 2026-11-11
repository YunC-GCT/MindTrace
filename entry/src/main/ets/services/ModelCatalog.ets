/**
 * ModelCatalog.ets — 模型目录的 UI 侧门面
 *
 * 路径: entry/src/main/ets/services/ModelCatalog.ets
 * 职责: 让 pages / overlays 在 UI 层规则下取得模型选择器，避免直连 agents
 * 依赖: agents/src/main/ets/chat/Index
 *
 * 数据流:
 *   AiSettings / 浮层 → ModelCatalog → agents 的 chat 子模块
 */
export { ModelSelector } from 'agents/src/main/ets/chat/Index';
export type { ModelAvailability } from 'agents/src/main/ets/chat/Index';
