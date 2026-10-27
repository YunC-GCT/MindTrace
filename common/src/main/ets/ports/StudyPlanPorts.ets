/**
 * StudyPlanPorts.ets — 学习计划读侧契约（现状待办语义，不是复习计划）
 *
 * 路径: common/src/main/ets/ports/StudyPlanPorts.ets
 * 职责: 只固定 `study_plan` 当前“待办”读侧的形状；不定义写侧、不定义复习评分/掌握度。
 * 依赖: 无（零 Kit、零模型依赖）
 *
 * 数据流（目标态，尚未接线）:
 *   UI / ViewModel → StudyPlanReadPort.listPending / get → entry 适配器 → study_plan 表
 *
 * 领域边界:
 *   - 现状 `study_plan` 是待办表（id / title / is_done / priority / linked_note_id / created_at /
 *     due_date），没有 subject 列。`subject` 在适配器里只能由 linked note 派生，或返回空串；
 *     本切片不新增列。
 *   - `study_plan` 升级为间隔复习计划（review_item / review_log、评分、掌握度）必须等 #242 拍板，
 *     本切片不预埋复习字段，也不定义 StudyPlanWritePort。
 *
 * ArkTS 1.1 strict 适配:
 *   - 纯 interface + 字符串字段，布尔字段用 done，不使用索引签名或对象字面量类型。
 *   - 与既有 models/StudyPlan.ets 的 @Observed UI 类同名，barrel 导出时使用
 *     StudyPlanPendingItem 这个别名，避免覆盖既有导出。
 */

// 读侧的待办项。dueAt 是截止时间戳（ms），0 表示无截止；done 对应 is_done。
export interface StudyPlanItem {
  id: string;
  subject: string;
  title: string;
  dueAt: number;
  done: boolean;
}

// barrel 导出名：既有的 models/StudyPlan.StudyPlanItem 是 UI @Observed 类，不能重名。
export type StudyPlanPendingItem = StudyPlanItem;

// 读侧端口：只读待办，不提供写入/复习评分能力。
export interface StudyPlanReadPort {
  listPending(subject?: string): Promise<StudyPlanItem[]>;
  get(id: string): Promise<StudyPlanItem | null>;
}
