/**
 * SubjectNoteList.ets - subject detail note list
 *
 * Path: entry/src/main/ets/pages/Notes/SubjectNoteList.ets
 * Responsibility: Lazily render filtered subject notes with List/ListItem while preserving NoteCard styling.
 * Dependencies: common.NoteItem, shared/organisms/NoteCard.
 *
 * Data flow:
 *   SubjectDetailPage.filteredNotes -> SubjectNoteList -> NoteCard -> onSelect(note)
 *
 * ArkTS 1.1 strict:
 *   - Explicit types throughout
 *   - Struct logic uses lifecycle, watch callback, and arrow callbacks
 */

import { BG_CARD, BORDER, R_LG, S_4, NoteItem } from "common"
import { NoteCard } from "../../shared/organisms/NoteCard"

function safeIndex(index: number | undefined): number {
  return index === undefined ? 0 : index
}

class SubjectNoteDataSource implements IDataSource {
  private notes: NoteItem[] = []
  private listeners: DataChangeListener[] = []
  private fallback: NoteItem = new NoteItem(0, "", "", "", "", 0, "", [], "")

  constructor(notes: NoteItem[]) {
    this.notes = notes.slice(0)
  }

  totalCount(): number {
    return this.notes.length
  }

  getData(index: number): NoteItem {
    const note: NoteItem | undefined = this.notes[index]
    return note === undefined ? this.fallback : note
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener)
  }

  setNotes(notes: NoteItem[]): void {
    this.notes = notes.slice(0)
    this.notifyReload()
  }

  private notifyReload(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded()
    }
  }
}

@Component
export struct SubjectNoteList {
  @Prop @Watch("onNotesChanged") notes: NoteItem[] = []
  private dataSource: SubjectNoteDataSource = new SubjectNoteDataSource([])
  onSelect: (note: NoteItem) => void = (_note: NoteItem): void => {}

  aboutToAppear(): void {
    this.dataSource.setNotes(this.notes)
  }

  onNotesChanged(): void {
    this.dataSource.setNotes(this.notes)
  }

  build() {
    List() {
      LazyForEach(this.dataSource,
        (note: NoteItem, index: number | undefined): void => {
          ListItem() {
            Column() {
              NoteCard({
                note: note,
                isLast: safeIndex(index) === this.notes.length - 1,
                onTap: (): void => this.onSelect(note),
              })
            }
            .width("100%")
            .padding({ left: S_4, right: S_4 })
            .backgroundColor(BG_CARD)
            .border({ width: { left: 0.5, right: 0.5, top: safeIndex(index) === 0 ? 0.5 : 0, bottom: safeIndex(index) === this.notes.length - 1 ? 0.5 : 0 }, color: BORDER })
            .borderRadius(safeIndex(index) === 0 || safeIndex(index) === this.notes.length - 1 ? R_LG : 0)
          }
        },
        (note: NoteItem): string => note.id.toString()
      )

      ListItem() {
        Column() { Blank().height(96) }
      }
    }
    .layoutWeight(1)
    .width("100%")
    .padding({ left: 10, right: 10, bottom: 20 })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}
