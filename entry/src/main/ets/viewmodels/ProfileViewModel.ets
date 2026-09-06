// ============================================================================
//  viewmodels/ProfileViewModel.ets - profile stats logic
// ----------------------------------------------------------------------------
//  Owns profile summary counts and data loading.
// ============================================================================

import { relationalStore } from '@kit.ArkData'
import { DatabaseHelper, KnowledgeUnit, ReviewStatus } from "common"
import { NoteDao } from "../database/NoteDao"

@Observed
export class ProfileViewModel {
  notes: number = 0
  avg: number = 0
  today: number = 0

  async loadStats(context: Context): Promise<boolean> {
    try {
      const store: relationalStore.RdbStore = await DatabaseHelper.init(context)
      const units: KnowledgeUnit[] = await new NoteDao(store).queryAll()
      this.notes = units.length
      this.today = this.countToday(units)
      this.avg = this.calcAvg(units)
      return true
    } catch (_e) {
      this.notes = 0
      this.avg = 0
      this.today = 0
      return false
    }
  }

  private countToday(units: KnowledgeUnit[]): number {
    const now: Date = new Date()
    const start: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    const startMs: number = start.getTime()
    const endMs: number = startMs + 86400000
    let count: number = 0
    for (const unit of units) {
      if (unit.createdAt >= startMs && unit.createdAt < endMs) {
        count++
      }
    }
    return count
  }

  private calcAvg(units: KnowledgeUnit[]): number {
    if (units.length === 0) { return 0 }
    let total: number = 0
    for (const unit of units) {
      if (unit.reviewStatus === ReviewStatus.GRADUATED) { total += 95 }
      else if (unit.reviewStatus === ReviewStatus.REVIEW) { total += 86 }
      else if (unit.reviewStatus === ReviewStatus.LEARNING) { total += 72 }
      else if (unit.reviewStatus === ReviewStatus.LAPSED) { total += 45 }
      else { total += 64 }
    }
    return Math.round(total / units.length)
  }
}
