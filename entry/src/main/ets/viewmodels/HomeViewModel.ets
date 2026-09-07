// ============================================================================
//  viewmodels/HomeViewModel.ets - home page data logic
// ============================================================================

import { relationalStore } from '@kit.ArkData'
import { DatabaseHelper, KnowledgeUnit, NoteItem } from "common"
import { NoteDao } from "../database/NoteDao"
import { NotesSnapshot, PreloadQueue, UiDataCacheService } from "../services/UiDataCacheService"

@Observed
export class HomeViewModel {
  notes: NoteItem[] = []
  units: KnowledgeUnit[] = []
  greeting: string = ""
  dateText: string = ""
  avg: number = 0
  today: number = 0

  async init(context: Context): Promise<boolean> {
    this.greeting = this.greet()
    this.dateText = this.dateStr()
    return this.loadNotes(context)
  }

  async loadNotes(context: Context): Promise<boolean> {
    try {
      const version: number = UiDataCacheService.currentNotesVersion()
      const snapshot: NotesSnapshot = await UiDataCacheService.loadNotesSnapshot(context, version)
      this.units = snapshot.units
      this.notes = snapshot.notes
      this.refreshStats()
      PreloadQueue.preloadHome(context)
      return true
    } catch (e) {
      console.warn("[HomeViewModel] loadNotes failed: " + ((e as Error).message ?? String(e)))
      this.units = []
      this.notes = []
      this.refreshStats()
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
      console.warn("[HomeViewModel] loadNote failed: " + ((e as Error).message ?? String(e)))
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
      console.warn("[HomeViewModel] deleteNote failed: " + ((e as Error).message ?? String(e)))
      return false
    }
  }

  private refreshStats(): void {
    this.avg = this.notes.length > 0
      ? Math.round(this.notes.reduce((total: number, note: NoteItem): number => total + note.conf, 0) / this.notes.length * 100)
      : 0
    const today: string = this.todayKey()
    this.today = this.notes.filter((note: NoteItem): boolean => note.date === today).length
  }

  private greet(): string {
    const hour: number = new Date().getHours()
    if (hour < 6) { return "凌晨好" }
    if (hour < 11) { return "上午好" }
    if (hour < 13) { return "中午好" }
    if (hour < 18) { return "下午好" }
    return "晚上好"
  }

  private pad2(value: number): string {
    return value < 10 ? "0" + value.toString() : value.toString()
  }

  private dateStr(): string {
    const date: Date = new Date()
    const weekDays: string[] = ["日", "一", "二", "三", "四", "五", "六"]
    return date.getFullYear().toString() + "年" +
      this.pad2(date.getMonth() + 1) + "月" +
      this.pad2(date.getDate()) + "日 · 周" +
      weekDays[date.getDay()]
  }

  private todayKey(): string {
    const now: Date = new Date()
    return now.getFullYear().toString() + "-" + this.pad2(now.getMonth() + 1) + "-" + this.pad2(now.getDate())
  }
}
