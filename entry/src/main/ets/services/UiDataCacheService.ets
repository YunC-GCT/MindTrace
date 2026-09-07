/**
 * UiDataCacheService.ets - process-local UI data cache and preload queue
 *
 * Path: entry/src/main/ets/services/UiDataCacheService.ets
 * Responsibility: Cache note snapshots, subject groups, note details, and study plan snapshots between UI pages.
 * Dependencies: common models, NoteDao, StudyPlanDao, NoteItemMapper.
 *
 * Data flow:
 *   ViewModel -> UiDataCacheService -> DAO only on cache miss
 *   Page preload hint -> PreloadQueue -> UiDataCacheService
 *
 * ArkTS 1.1 strict:
 *   - Explicit types throughout
 *   - No C-style loop
 *   - LRU eviction uses while loops and explicit classes
 */

import { relationalStore } from '@kit.ArkData'
import { DatabaseHelper, KnowledgeUnit, NoteItem, StudyPlanItem, subjectColor } from "common"
import { NoteDao } from "../database/NoteDao"
import { StudyPlanDao } from "../database/StudyPlanDao"
import { unitsToNoteItems } from "../utils/NoteItemMapper"
import { uiCacheLog, uiCacheWarn } from "../utils/UiCacheDebug"

export class SubjectGroup {
  subject: string = ""
  color: string = ""
  count: number = 0
  notes: NoteItem[] = []
  previewTitles: string[] = []

  constructor(subject: string, color: string, count: number, notes: NoteItem[], previewTitles: string[]) {
    this.subject = subject
    this.color = color
    this.count = count
    this.notes = notes
    this.previewTitles = previewTitles
  }
}

export class NotesSnapshot {
  version: number = 0
  units: KnowledgeUnit[] = []
  notes: NoteItem[] = []

  constructor(version: number, units: KnowledgeUnit[], notes: NoteItem[]) {
    this.version = version
    this.units = units
    this.notes = notes
  }
}

export class SubjectGroupsSnapshot {
  version: number = 0
  groups: SubjectGroup[] = []

  constructor(version: number, groups: SubjectGroup[]) {
    this.version = version
    this.groups = groups
  }
}

export class StudyPlanSnapshot {
  version: number = 0
  items: StudyPlanItem[] = []

  constructor(version: number, items: StudyPlanItem[]) {
    this.version = version
    this.items = items
  }
}

class DetailCacheEntry {
  id: string = ""
  key: string = ""
  unit: KnowledgeUnit | null = null
  touched: number = 0
  size: number = 0

  constructor(id: string, key: string, unit: KnowledgeUnit, touched: number) {
    this.id = id
    this.key = key
    this.unit = unit
    this.touched = touched
    this.size = UiDataCacheService.estimateDetailSize(unit)
  }
}

class PreloadTask {
  key: string = ""
  task: () => Promise<void> = async (): Promise<void> => {}

  constructor(key: string, task: () => Promise<void>) {
    this.key = key
    this.task = task
  }
}

class DetailLoadingEntry {
  id: string = ""
  version: number = 0
  promise: Promise<KnowledgeUnit | null> = Promise.resolve(null)

  constructor(id: string, version: number, promise: Promise<KnowledgeUnit | null>) {
    this.id = id
    this.version = version
    this.promise = promise
  }
}

const UI_DETAIL_LIMIT: number = 8
const UI_DETAIL_TEXT_LIMIT: number = 512 * 1024
const UI_PRELOAD_DELAY_MS: number = 360

export class UiDataCacheService {
  private static notesSnapshot: NotesSnapshot | null = null
  private static subjectGroupsSnapshot: SubjectGroupsSnapshot | null = null
  private static studyPlanSnapshot: StudyPlanSnapshot | null = null
  private static notesLoadingVersion: number = -1
  private static notesLoadingPromise: Promise<NotesSnapshot> | null = null
  private static studyPlanLoading: Promise<StudyPlanSnapshot> | null = null
  private static detailLoadingEntries: DetailLoadingEntry[] = []
  private static studyPlanVersion: number = 0
  private static detailEntries: DetailCacheEntry[] = []
  private static detailClock: number = 0

  static currentNotesVersion(): number {
    return AppStorage.get<number>("notesVersion") ?? 0
  }

  static currentStudyPlanVersion(): number {
    return UiDataCacheService.studyPlanVersion
  }

  static getNotesSnapshot(version: number): NotesSnapshot | null {
    if (UiDataCacheService.notesSnapshot !== null && UiDataCacheService.notesSnapshot.version === version) {
      uiCacheLog("[UiDataCache] notes hit version=" + version.toString())
      return UiDataCacheService.notesSnapshot
    }
    uiCacheLog("[UiDataCache] notes miss version=" + version.toString())
    return null
  }

  static setNotesSnapshot(version: number, units: KnowledgeUnit[]): NotesSnapshot {
    const snapshot: NotesSnapshot = new NotesSnapshot(version, units.slice(0), unitsToNoteItems(units))
    UiDataCacheService.notesSnapshot = snapshot
    uiCacheLog("[UiDataCache] notes store version=" + version.toString() + " count=" + units.length.toString())
    return snapshot
  }

  static invalidateNotesSnapshots(): void {
    UiDataCacheService.notesSnapshot = null
    UiDataCacheService.subjectGroupsSnapshot = null
    uiCacheLog("[UiDataCache] notes invalidate")
  }

  static getSubjectGroups(version: number): SubjectGroup[] | null {
    if (UiDataCacheService.subjectGroupsSnapshot !== null && UiDataCacheService.subjectGroupsSnapshot.version === version) {
      uiCacheLog("[UiDataCache] subjectGroups hit version=" + version.toString())
      return UiDataCacheService.subjectGroupsSnapshot.groups
    }
    uiCacheLog("[UiDataCache] subjectGroups miss version=" + version.toString())
    return null
  }

  static setSubjectGroups(version: number, groups: SubjectGroup[]): void {
    UiDataCacheService.subjectGroupsSnapshot = new SubjectGroupsSnapshot(version, groups.slice(0))
    uiCacheLog("[UiDataCache] subjectGroups store version=" + version.toString() + " count=" + groups.length.toString())
  }

  static getDetailById(id: string, version: number): KnowledgeUnit | null {
    const nowKeyPrefix: string = id + "|"
    for (const entry of UiDataCacheService.detailEntries) {
      if (entry.id === id && entry.key.indexOf(nowKeyPrefix) === 0 && entry.key.endsWith("|" + version.toString())) {
        entry.touched = UiDataCacheService.nextDetailTick()
        uiCacheLog("[UiDataCache] detail hit id=" + id)
        return entry.unit
      }
    }
    uiCacheLog("[UiDataCache] detail miss id=" + id)
    return null
  }

  static setDetail(unit: KnowledgeUnit, version: number): void {
    const key: string = UiDataCacheService.detailKey(unit, version)
    const touched: number = UiDataCacheService.nextDetailTick()
    for (const entry of UiDataCacheService.detailEntries) {
      if (entry.key === key) {
        entry.unit = unit
        entry.touched = touched
        entry.size = UiDataCacheService.estimateDetailSize(unit)
        UiDataCacheService.trimDetailCache()
        return
      }
    }
    UiDataCacheService.removeDetailById(unit.id)
    UiDataCacheService.detailEntries.push(new DetailCacheEntry(unit.id, key, unit, touched))
    UiDataCacheService.trimDetailCache()
  }

  static invalidateNote(id: string): void {
    UiDataCacheService.removeDetailById(id)
    UiDataCacheService.invalidateNotesSnapshots()
  }

  static getStudyPlanSnapshot(): StudyPlanSnapshot | null {
    if (UiDataCacheService.studyPlanSnapshot !== null
      && UiDataCacheService.studyPlanSnapshot.version === UiDataCacheService.studyPlanVersion) {
      uiCacheLog("[UiDataCache] studyPlan hit version=" + UiDataCacheService.studyPlanVersion.toString())
      return UiDataCacheService.studyPlanSnapshot
    }
    uiCacheLog("[UiDataCache] studyPlan miss version=" + UiDataCacheService.studyPlanVersion.toString())
    return null
  }

  static setStudyPlanSnapshot(items: StudyPlanItem[]): StudyPlanSnapshot {
    const snapshot: StudyPlanSnapshot = new StudyPlanSnapshot(UiDataCacheService.studyPlanVersion, items.slice(0))
    UiDataCacheService.studyPlanSnapshot = snapshot
    uiCacheLog("[UiDataCache] studyPlan store version=" + snapshot.version.toString() + " count=" + items.length.toString())
    return snapshot
  }

  static bumpStudyPlanVersion(): void {
    UiDataCacheService.studyPlanVersion += 1
    UiDataCacheService.studyPlanSnapshot = null
    uiCacheLog("[UiDataCache] studyPlan invalidate version=" + UiDataCacheService.studyPlanVersion.toString())
  }

  static buildSubjectGroups(notes: NoteItem[]): SubjectGroup[] {
    const subjectNames: string[] = []
    const subjectNotes: NoteItem[][] = []

    for (const note of notes) {
      const subject: string = UiDataCacheService.resolveSubject(note)
      let idx: number = subjectNames.indexOf(subject)
      if (idx < 0) {
        subjectNames.push(subject)
        subjectNotes.push([])
        idx = subjectNames.length - 1
      }
      subjectNotes[idx].push(note)
    }

    const groups: SubjectGroup[] = []
    let subjectIndex: number = 0
    while (subjectIndex < subjectNames.length) {
      const sortedNotes: NoteItem[] = UiDataCacheService.sortByDateDesc(subjectNotes[subjectIndex])
      const previewTitles: string[] = []
      const previewCount: number = Math.min(3, sortedNotes.length)
      let previewIndex: number = 0
      while (previewIndex < previewCount) {
        previewTitles.push(sortedNotes[previewIndex].title)
        previewIndex += 1
      }
      groups.push(new SubjectGroup(
        subjectNames[subjectIndex],
        subjectColor(subjectNames[subjectIndex], subjectIndex),
        sortedNotes.length,
        sortedNotes,
        previewTitles,
      ))
      subjectIndex += 1
    }

    return UiDataCacheService.sortGroups(groups)
  }

  static async loadNotesSnapshot(context: Context, version: number): Promise<NotesSnapshot> {
    const cached: NotesSnapshot | null = UiDataCacheService.getNotesSnapshot(version)
    if (cached !== null) {
      return cached
    }
    if (UiDataCacheService.notesLoadingPromise !== null && UiDataCacheService.notesLoadingVersion === version) {
      uiCacheLog("[UiDataCache] notes join version=" + version.toString())
      return UiDataCacheService.notesLoadingPromise
    }
    UiDataCacheService.notesLoadingVersion = version
    const promise: Promise<NotesSnapshot> = UiDataCacheService.queryNotesSnapshot(context, version)
    UiDataCacheService.notesLoadingPromise = promise
    try {
      return await promise
    } finally {
      UiDataCacheService.notesLoadingPromise = null
      UiDataCacheService.notesLoadingVersion = -1
    }
  }

  private static async queryNotesSnapshot(context: Context, version: number): Promise<NotesSnapshot> {
    const store: relationalStore.RdbStore = await DatabaseHelper.init(context)
    const units: KnowledgeUnit[] = await new NoteDao(store).queryAllMetadata()
    return UiDataCacheService.setNotesSnapshot(version, units)
  }

  static async loadDetail(context: Context, id: string, version: number): Promise<KnowledgeUnit | null> {
    const cached: KnowledgeUnit | null = UiDataCacheService.getDetailById(id, version)
    if (cached !== null) {
      return cached
    }
    const loading: DetailLoadingEntry | null = UiDataCacheService.findDetailLoading(id, version)
    if (loading !== null) {
      uiCacheLog("[UiDataCache] detail join id=" + id)
      return loading.promise
    }
    const promise: Promise<KnowledgeUnit | null> = UiDataCacheService.queryDetail(context, id, version)
    UiDataCacheService.detailLoadingEntries.push(new DetailLoadingEntry(id, version, promise))
    try {
      return await promise
    } finally {
      UiDataCacheService.removeDetailLoading(id, version)
    }
  }

  private static async queryDetail(context: Context, id: string, version: number): Promise<KnowledgeUnit | null> {
    const store: relationalStore.RdbStore = await DatabaseHelper.init(context)
    const unit: KnowledgeUnit | null = await new NoteDao(store).queryById(id)
    if (unit !== null) {
      UiDataCacheService.setDetail(unit, version)
    }
    return unit
  }

  private static findDetailLoading(id: string, version: number): DetailLoadingEntry | null {
    for (const entry of UiDataCacheService.detailLoadingEntries) {
      if (entry.id === id && entry.version === version) {
        return entry
      }
    }
    return null
  }

  private static removeDetailLoading(id: string, version: number): void {
    UiDataCacheService.detailLoadingEntries = UiDataCacheService.detailLoadingEntries
      .filter((entry: DetailLoadingEntry): boolean => entry.id !== id || entry.version !== version)
  }

  static async loadStudyPlanSnapshot(context: Context): Promise<StudyPlanSnapshot> {
    const cached: StudyPlanSnapshot | null = UiDataCacheService.getStudyPlanSnapshot()
    if (cached !== null) {
      return cached
    }
    if (UiDataCacheService.studyPlanLoading !== null) {
      uiCacheLog("[UiDataCache] studyPlan join")
      return UiDataCacheService.studyPlanLoading
    }
    const promise: Promise<StudyPlanSnapshot> = UiDataCacheService.queryStudyPlanSnapshot(context)
    UiDataCacheService.studyPlanLoading = promise
    try {
      return await promise
    } finally {
      UiDataCacheService.studyPlanLoading = null
    }
  }

  private static async queryStudyPlanSnapshot(context: Context): Promise<StudyPlanSnapshot> {
    const store: relationalStore.RdbStore = await DatabaseHelper.init(context)
    const items: StudyPlanItem[] = await new StudyPlanDao(store).queryAll()
    return UiDataCacheService.setStudyPlanSnapshot(items)
  }

  static estimateDetailSize(unit: KnowledgeUnit): number {
    return unit.title.length
      + unit.summary.length
      + unit.content.length
      + unit.tags.join("").length
      + unit.prerequisites.join("").length
      + unit.related.join("").length
      + unit.embedding.length * 8
  }

  private static detailKey(unit: KnowledgeUnit, version: number): string {
    return unit.id + "|" + unit.updatedAt.toString() + "|" + unit.version.toString() + "|" + version.toString()
  }

  private static nextDetailTick(): number {
    UiDataCacheService.detailClock += 1
    return UiDataCacheService.detailClock
  }

  private static removeDetailById(id: string): void {
    let index: number = UiDataCacheService.detailEntries.length - 1
    while (index >= 0) {
      if (UiDataCacheService.detailEntries[index].id === id) {
        UiDataCacheService.detailEntries.splice(index, 1)
      }
      index -= 1
    }
  }

  private static trimDetailCache(): void {
    while (UiDataCacheService.detailEntries.length > UI_DETAIL_LIMIT) {
      UiDataCacheService.removeOldestDetailEntry()
    }
    while (UiDataCacheService.detailTextSize() > UI_DETAIL_TEXT_LIMIT
      && UiDataCacheService.detailEntries.length > 0) {
      UiDataCacheService.removeOldestDetailEntry()
    }
  }

  private static removeOldestDetailEntry(): void {
    if (UiDataCacheService.detailEntries.length === 0) {
      return
    }
    let oldestIndex: number = 0
    let oldestTick: number = UiDataCacheService.detailEntries[0].touched
    let index: number = 1
    while (index < UiDataCacheService.detailEntries.length) {
      if (UiDataCacheService.detailEntries[index].touched < oldestTick) {
        oldestTick = UiDataCacheService.detailEntries[index].touched
        oldestIndex = index
      }
      index += 1
    }
    const removed: DetailCacheEntry = UiDataCacheService.detailEntries[oldestIndex]
    UiDataCacheService.detailEntries.splice(oldestIndex, 1)
    uiCacheLog("[UiDataCache] evict detail id=" + removed.id)
  }

  private static detailTextSize(): number {
    let total: number = 0
    for (const entry of UiDataCacheService.detailEntries) {
      total += entry.size
    }
    return total
  }

  private static resolveSubject(note: NoteItem): string {
    const subject: string = note.subject.trim()
    return subject.length > 0 ? subject : "未分类"
  }

  private static sortByDateDesc(notes: NoteItem[]): NoteItem[] {
    const sorted: NoteItem[] = notes.slice(0)
    sorted.sort((a: NoteItem, b: NoteItem): number => {
      return new Date(b.date).getTime() - new Date(a.date).getTime()
    })
    return sorted
  }

  private static sortGroups(groups: SubjectGroup[]): SubjectGroup[] {
    const sorted: SubjectGroup[] = groups.slice(0)
    sorted.sort((a: SubjectGroup, b: SubjectGroup): number => b.count - a.count)
    return sorted
  }
}

class PreloadQueueService {
  private queue: PreloadTask[] = []
  private active: boolean = false
  private queuedKeys: string[] = []

  enqueue(key: string, task: () => Promise<void>): void {
    if (this.queuedKeys.indexOf(key) >= 0) {
      uiCacheLog("[UiDataCache] preload skip key=" + key)
      return
    }
    this.queuedKeys.push(key)
    this.queue.push(new PreloadTask(key, task))
    this.drain()
  }

  private drain(): void {
    if (this.active) {
      return
    }
    const next: PreloadTask | null = this.shiftTask()
    if (next === null) {
      return
    }
    this.active = true
    uiCacheLog("[UiDataCache] preload start key=" + next.key)
    next.task()
      .then((): void => {
        uiCacheLog("[UiDataCache] preload done key=" + next.key)
      })
      .catch((e: Error): void => {
        uiCacheWarn("[UiDataCache] preload failed key=" + next.key + ": " + (e.message ?? String(e)))
      })
      .finally((): void => {
        this.removeQueuedKey(next.key)
        setTimeout((): void => {
          this.active = false
          this.drain()
        }, UI_PRELOAD_DELAY_MS)
      })
  }

  private shiftTask(): PreloadTask | null {
    if (this.queue.length === 0) {
      return null
    }
    const next: PreloadTask | undefined = this.queue.shift()
    return next === undefined ? null : next
  }

  private removeQueuedKey(key: string): void {
    this.queuedKeys = this.queuedKeys.filter((item: string): boolean => item !== key)
  }
}

const UI_PRELOAD_QUEUE: PreloadQueueService = new PreloadQueueService()

export class PreloadQueue {
  static preloadHome(context: Context): void {
    const version: number = UiDataCacheService.currentNotesVersion()
    UI_PRELOAD_QUEUE.enqueue("notes|" + version.toString(), async (): Promise<void> => {
      await UiDataCacheService.loadNotesSnapshot(context, version)
    })
    UI_PRELOAD_QUEUE.enqueue("studyPlan", async (): Promise<void> => {
      await UiDataCacheService.loadStudyPlanSnapshot(context)
    })
  }
}
