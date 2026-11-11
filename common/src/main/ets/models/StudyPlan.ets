// ============================================================================
//  model/StudyPlan.ets — 学习计划数据模型（纯数据结构，无 UI 依赖）
//  ----------------------------------------------------------------------------
//  职责: 定义学习计划项的数据结构。@Observed 使属性变化能被 ViewModel 追踪。
//  来源: 基于 swiftui-to-arkui TodoItem 模式适配 MindTrace 领域
//
//  对接: 暂无 RDB 持久化 — 当前使用内存存储，后续可对接 NoteDao 扩展表
//  ============================================================================

import { uuid } from "../utils/uuid"

@Observed
export class StudyPlanItem {
  id: string = ""
  title: string = ""
  isDone: boolean = false
  /** 优先级: 1=高 2=中 3=低，默认 2 */
  priority: number = 2
  /** 关联的知识单元 ID（可选，对接 KnowledgeUnit） */
  linkedNoteId: string = ""
  /** 创建时间戳 (ms) */
  createdAt: number = 0
  /** 截止时间戳 (ms)，0 表示无截止 */
  dueDate: number = 0

  constructor(title: string, priority: number = 2) {
    this.id = uuid()
    this.title = title
    this.priority = priority
    this.createdAt = Date.now()
  }

  // ---- 工厂方法：从 DB 行重建（不调用构造器的 uuid/Date.now） ----
  static fromRow(
    id: string,
    title: string,
    isDone: boolean,
    priority: number,
    linkedNoteId: string,
    createdAt: number,
    dueDate: number,
  ): StudyPlanItem {
    const item: StudyPlanItem = new StudyPlanItem("")
    item.id = id
    item.title = title
    item.isDone = isDone
    item.priority = priority
    item.linkedNoteId = linkedNoteId
    item.createdAt = createdAt
    item.dueDate = dueDate
    return item
  }
}
