// ============================================================================
//  database/StudyPlanDao.ets — 学习计划数据访问层
//  ----------------------------------------------------------------------------
//  职责: study_plan 表 CRUD，模式对齐 NoteDao
//  依赖: relationalStore + common/models/StudyPlan.ets
//  ============================================================================

import { relationalStore } from "@kit.ArkData"
import { StudyPlanItem } from "common"

export class StudyPlanDao {
  private store: relationalStore.RdbStore

  constructor(store: relationalStore.RdbStore) {
    this.store = store
  }

  // ---- 插入一条学习计划 ----
  async insert(item: StudyPlanItem): Promise<number> {
    const bucket: relationalStore.ValuesBucket = {
      "id": item.id,
      "title": item.title,
      "is_done": item.isDone ? 1 : 0,
      "priority": item.priority,
      "linked_note_id": item.linkedNoteId,
      "created_at": item.createdAt,
      "due_date": item.dueDate,
    }
    return new Promise<number>((resolve, reject) => {
      this.store.insert("study_plan", bucket, (err: Error, rowId: number) => {
        if (err) {
          reject(new Error("StudyPlanDao.insert failed: " + err.message))
          return
        }
        resolve(rowId)
      })
    })
  }

  // ---- 查询全部 ----
  async queryAll(): Promise<StudyPlanItem[]> {
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates("study_plan")
    predicates.orderByDesc("created_at")

    return new Promise<StudyPlanItem[]>((resolve, reject) => {
      this.store.query(predicates, ["*"], (err: Error, rs: relationalStore.ResultSet) => {
        if (err) {
          reject(new Error("StudyPlanDao.queryAll failed: " + err.message))
          return
        }
        const items: StudyPlanItem[] = []
        if (rs.goToFirstRow()) {
          do {
            items.push(StudyPlanDao.rowToItem(rs))
          } while (rs.goToNextRow())
        }
        rs.close()
        resolve(items)
      })
    })
  }

  // ---- 更新完成状态 ----
  async updateDone(id: string, isDone: boolean): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      "is_done": isDone ? 1 : 0,
    }
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates("study_plan")
    predicates.equalTo("id", id)

    return new Promise<void>((resolve, reject) => {
      this.store.update(bucket, predicates, (err: Error, _rows: number) => {
        if (err) {
          reject(new Error("StudyPlanDao.updateDone failed: " + err.message))
          return
        }
        resolve()
      })
    })
  }

  // ---- 更新标题 ----
  async updateTitle(id: string, title: string): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      "title": title,
    }
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates("study_plan")
    predicates.equalTo("id", id)

    return new Promise<void>((resolve, reject) => {
      this.store.update(bucket, predicates, (err: Error, _rows: number) => {
        if (err) {
          reject(new Error("StudyPlanDao.updateTitle failed: " + err.message))
          return
        }
        resolve()
      })
    })
  }

  // ---- 置顶：复用 created_at 做排序锚点 ----
  async updateCreatedAt(id: string, createdAt: number): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      "created_at": createdAt,
    }
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates("study_plan")
    predicates.equalTo("id", id)

    return new Promise<void>((resolve, reject) => {
      this.store.update(bucket, predicates, (err: Error, _rows: number) => {
        if (err) {
          reject(new Error("StudyPlanDao.updateCreatedAt failed: " + err.message))
          return
        }
        resolve()
      })
    })
  }

  // ---- 删除 ----
  async deleteById(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates("study_plan")
    predicates.equalTo("id", id)

    return new Promise<void>((resolve, reject) => {
      this.store.delete(predicates, (err: Error, _rows: number) => {
        if (err) {
          reject(new Error("StudyPlanDao.deleteById failed: " + err.message))
          return
        }
        resolve()
      })
    })
  }

  // ---- 行映射（使用 fromRow 工厂方法，避免浪费 uuid/Date.now 调用） ----
  private static rowToItem(rs: relationalStore.ResultSet): StudyPlanItem {
    return StudyPlanItem.fromRow(
      rs.getString(rs.getColumnIndex("id")),
      rs.getString(rs.getColumnIndex("title")),
      rs.getLong(rs.getColumnIndex("is_done")) === 1,
      rs.getLong(rs.getColumnIndex("priority")) as number,
      rs.getString(rs.getColumnIndex("linked_note_id")),
      rs.getLong(rs.getColumnIndex("created_at")) as number,
      rs.getLong(rs.getColumnIndex("due_date")) as number,
    )
  }
}
