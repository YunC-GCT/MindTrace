/**
 * NoteSuggestionModels.ets — 笔记生成/合并建议（纯数据，无 IO）
 *
 * 路径: common/src/main/ets/models/NoteSuggestionModels.ets
 * 职责: 当系统认为「应该新建/合并笔记」时，把这个判断表达成一条建议，
 *       由会话层发出去；用户确认之前不写任何东西。
 * 依赖: 无。
 *
 * 约束: 建议只是事件，不是命令——本轮只记录与展示，不落库、不触发写入。
 *       粒度（原子/汇总）与条数都随建议携带，供后续 UI 直接呈现。
 */
export type NoteSuggestionAction = 'create' | 'append' | 'merge';
export type NoteSuggestionKind = 'atomic' | 'summary' | 'normal';

export interface NoteSuggestion {
  action: NoteSuggestionAction;
  /** 建议生成的笔记粒度：原子笔记 / 汇总笔记 / 普通笔记。 */
  noteKind: NoteSuggestionKind;
  /** 建议生成的条数；merge/append 固定为 1。 */
  count: number;
  /** 触发原因，用于日志与后续展示（draft-ready / duplicate-on-confirm 等）。 */
  reason: string;
  /** merge 时的目标笔记 id。 */
  sourceNoteId?: string;
}
