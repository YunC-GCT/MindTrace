// ============================================================================
//  pages/Notes/SubjectDetailPage.ets - subject-level notes page
// ============================================================================

import { BG_DARK, KnowledgeUnit, normalizeNoteType, NOTE_TYPE_ALL_KEY, NoteItem, Toast } from "common"
import { promptAction, router } from "@kit.ArkUI"
import { NoteDetailOverlay } from "../../overlays/NoteDetailOverlay/NoteDetailOverlay"
import { NotesViewModel } from "../../viewmodels/NotesViewModel"
import { SubjectHeader } from "./SubjectHeader"
import { TypeTabRow } from "./TypeTabRow"
import { SubjectNoteList } from "./SubjectNoteList"
import { SubjectTypeEmpty } from "./SubjectTypeEmpty"
import { unitToNoteItem } from "../../utils/NoteItemMapper"
import { invalidateDetailRender } from "../../overlays/NoteDetailOverlay/model/DetailRenderCache"

@Entry
@Component
struct SubjectDetailPage {
  @StorageProp("statusBarHeight") sbh: number = 0
  @StorageProp("notesVersion") @Watch("onNotesVersionChange") notesVersion: number = 0
  @State subject: string = ""
  @State activeType: string = NOTE_TYPE_ALL_KEY
  @State vm: NotesViewModel = new NotesViewModel()
  @State selectedNote: NoteItem | null = null
  @State selectedUnit: KnowledgeUnit | null = null
  private loadedReloadKey: string = ""
  private loadingReloadKey: string = ""

  aboutToAppear(): void {
    this.readParams()
    this.reloadNotes()
  }

  onPageShow(): void {
    this.readParams()
    this.reloadNotes()
  }

  onNotesVersionChange(): void {
    this.reloadNotes()
  }

  private readParams(): void {
    const params = router.getParams() as Record<string, Object>
    const subjectParam: Object | undefined = params["subject"]
    if (typeof subjectParam === "string") {
      this.subject = subjectParam
    }
  }

  private reloadNotes(): void {
    const version: number = AppStorage.get<number>("notesVersion") ?? 0
    const reloadKey: string = version.toString() + "|" + this.subject
    if (this.loadedReloadKey === reloadKey || this.loadingReloadKey === reloadKey) {
      return
    }
    this.loadingReloadKey = reloadKey
    this.vm.loadNotes(getContext(this)).then((ok: boolean): void => {
      if (!ok) {
        try { promptAction.showToast({ message: Toast.NOTE_LOAD_FAILED, duration: 1500 }) } catch (_e) {}
        return
      }
      this.ensureSubject()
      this.loadedReloadKey = version.toString() + "|" + this.subject
    }).finally((): void => {
      if (this.loadingReloadKey === reloadKey) {
        this.loadingReloadKey = ""
      }
    })
  }

  private ensureSubject(): void {
    if (this.vm.subjectGroups.length === 0) {
      this.subject = ""
      return
    }
    if (this.hasSubject(this.subject)) {
      return
    }
    this.subject = this.vm.subjectGroups[0].subject
    this.activeType = NOTE_TYPE_ALL_KEY
  }

  private hasSubject(subject: string): boolean {
    for (const group of this.vm.subjectGroups) {
      if (group.subject === subject) {
        return true
      }
    }
    return false
  }

  private subjectNotes(): NoteItem[] {
    return this.vm.notesForSubject(this.subject)
  }

  private filteredNotes(): NoteItem[] {
    const notes: NoteItem[] = this.subjectNotes()
    if (this.activeType === NOTE_TYPE_ALL_KEY) {
      return notes
    }
    const result: NoteItem[] = []
    for (const note of notes) {
      if (normalizeNoteType(note.type) === this.activeType) {
        result.push(note)
      }
    }
    return result
  }

  private openDetail = (note: NoteItem): void => {
    this.selectedNote = note
    this.selectedUnit = null
    this.vm.loadNote(getContext(this), note.rawId).then((unit: KnowledgeUnit | null): void => {
      if (this.selectedNote !== null && this.selectedNote.id === note.id) {
        this.selectedUnit = unit
      }
    })
  }

  private closeDetail = (): void => {
    this.selectedNote = null
    this.selectedUnit = null
  }

  private handleSaved = (unit: KnowledgeUnit): void => {
    this.selectedNote = unitToNoteItem(unit)
    this.selectedUnit = unit
  }

  private deleteNote = async (id: string): Promise<void> => {
    const ok: boolean = await this.vm.deleteNote(getContext(this), id)
    if (ok) {
      invalidateDetailRender(id)
      this.selectedNote = null
      this.selectedUnit = null
      try { promptAction.showToast({ message: Toast.NOTE_DELETED, duration: 1200 }) } catch (_e) {}
    } else {
      try { promptAction.showToast({ message: Toast.NOTE_DELETE_FAILED, duration: 1500 }) } catch (_e) {}
    }
  }

  build() {
    Stack() {
      Column() {
        SubjectHeader({
          statusBarHeight: this.sbh,
          subject: this.subject,
          count: this.subjectNotes().length,
          onBack: (): void => router.back(),
        })

        TypeTabRow({
          activeType: this.activeType,
          notes: this.subjectNotes(),
          onSelect: (type: string): void => { this.activeType = type },
        })

        if (this.filteredNotes().length === 0) {
          Scroll() {
            Column() {
              SubjectTypeEmpty({ activeType: this.activeType })
              Blank().height(96)
            }
            .width("100%")
            .constraintSize({ minHeight: "100%" })
            .padding({ left: 10, right: 10, bottom: 20 })
            .justifyContent(FlexAlign.Start)
            .alignItems(HorizontalAlign.Start)
          }
          .layoutWeight(1)
          .width("100%")
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        } else {
          SubjectNoteList({
            notes: this.filteredNotes(),
            onSelect: this.openDetail,
          })
        }
      }
      .width("100%")
      .height("100%")
      .backgroundColor(BG_DARK)

      if (this.selectedNote !== null) {
        NoteDetailOverlay({
          note: this.selectedNote,
          unit: this.selectedUnit,
          units: this.vm.units,
          onClose: this.closeDetail,
          onDelete: this.deleteNote,
          onSaved: this.handleSaved,
        })
      }
    }
    .width("100%")
    .height("100%")
    .backgroundColor(BG_DARK)
  }
}
