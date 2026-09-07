/**
 * NotesViewModel.ets - notes page data logic
 *
 * Path: entry/src/main/ets/viewmodels/NotesViewModel.ets
 * Responsibility: Load note snapshots, grouped subject data, detail records, and delete notes for Notes UI.
 * Dependencies: NoteDao, UiDataCacheService.
 *
 * Data flow:
 *   NotesPage / SubjectDetailPage -> NotesViewModel -> UiDataCacheService -> NoteDao on miss
 *
 * ArkTS 1.1 strict:
 *   - Explicit types throughout
 *   - Iteration uses for...of
 */

import { relationalStore } from '@kit.ArkData'
import { DatabaseHelper, KnowledgeUnit, NoteItem } from "common"
import { NoteDao } from "../database/NoteDao"
import {
  NotesSnapshot,
  SubjectGroup,
  UiDataCacheService,
} from "../services/UiDataCacheService"

export { SubjectGroup } from "../services/UiDataCacheService"

@Observed
export class NotesViewModel {
  notes: NoteItem[] = []
  units: KnowledgeUnit[] = []
  subjectGroups: SubjectGroup[] = []
  weeklyNewCount: number = 0

  async loadNotes(context: Context): Promise<boolean> {
    try {
      const version: number = UiDataCacheService.currentNotesVersion()
      const snapshot: NotesSnapshot = await UiDataCacheService.loadNotesSnapshot(context, version)
      this.units = snapshot.units
      this.notes = snapshot.notes
      const cachedGroups: SubjectGroup[] | null = UiDataCacheService.getSubjectGroups(version)
      if (cachedGroups !== null) {
        this.subjectGroups = cachedGroups
      } else {
        this.subjectGroups = this.groupBySubject(this.notes)
        UiDataCacheService.setSubjectGroups(version, this.subjectGroups)
      }
      this.weeklyNewCount = this.countRecentNotes(this.notes, 7)
      return true
    } catch (e) {
      console.warn("[NotesViewModel] loadNotes failed: " + ((e as Error).message ?? String(e)))
      this.units = []
      this.notes = []
      this.subjectGroups = []
      this.weeklyNewCount = 0
      return false
    }
  }

  async loadNote(context: Context, id: string): Promise<KnowledgeUnit | null> {
    if (id.length === 0) {
      return null
    }
    try {
      return await UiDataCacheService.loadDetail(context, id, UiDataCacheService.currentNotesVersion())
    } catch (e) {
      console.warn("[NotesViewModel] loadNote failed: " + ((e as Error).message ?? String(e)))
      return null
    }
  }

  async deleteNote(context: Context, id: string): Promise<boolean> {
    try {
      UiDataCacheService.invalidateNote(id)
      const store: relationalStore.RdbStore = await DatabaseHelper.init(context)
      await new NoteDao(store).deleteById(id)
      const version: number = UiDataCacheService.currentNotesVersion()
      AppStorage.setOrCreate("notesVersion", version + 1)
      return await this.loadNotes(context)
    } catch (e) {
      console.warn("[NotesViewModel] deleteNote failed: " + ((e as Error).message ?? String(e)))
      return false
    }
  }

  groupBySubject(notes: NoteItem[]): SubjectGroup[] {
    return UiDataCacheService.buildSubjectGroups(notes)
  }

  notesForSubject(subject: string): NoteItem[] {
    for (const group of this.subjectGroups) {
      if (group.subject === subject) {
        return group.notes
      }
    }
    return []
  }

  private countRecentNotes(notes: NoteItem[], days: number): number {
    const now: number = Date.now()
    const windowMs: number = days * 86400000
    let count: number = 0
    for (const note of notes) {
      const ts: number = new Date(note.date).getTime()
      if (ts === ts && now - ts >= 0 && now - ts <= windowMs) {
        count += 1
      }
    }
    return count
  }
}
