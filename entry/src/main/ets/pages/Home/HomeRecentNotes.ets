// ============================================================================
// pages/Home/HomeRecentNotes.ets - recent notes list
// ============================================================================

import { TEXT, TEXT_3, S_1, S_2, S_3, S_5, F_XS, F_BASE, W_SEMIBOLD, NoteItem } from "common"
import { NoteCard } from "../../shared/organisms/NoteCard"

@Component
export struct HomeRecentNotes {
  @Prop notes: NoteItem[] = []
  @Prop compact: boolean = false

  onSelect: (note: NoteItem) => void = (_note: NoteItem): void => {}
  onSwipeUp: () => void = (): void => {}

  build() {
    Column() {
      Row() {
        Text("最近笔记")
          .fontSize(F_BASE)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT)
        Blank()
        Text(this.notes.length + " 条")
          .fontSize(F_XS)
          .fontColor(TEXT_3)
      }
      .width("100%")
      .padding({ left: S_5, right: S_5, top: this.compact ? 0 : S_1, bottom: S_1 })
      .gesture(
        PanGesture({ direction: PanDirection.Vertical })
          .onActionEnd((event: GestureEvent): void => {
            if (event.offsetY < -18) {
              this.onSwipeUp()
            }
          })
      )

      Column() {
        this.NoteRows()
        Blank().height(48)
      }
      .width("100%")
      .layoutWeight(this.compact ? 1 : 0)
      .padding({ left: S_5, right: S_5, top: 0, bottom: S_5 })
    }
    .layoutWeight(this.compact ? 1 : 0)
    .width("100%")
  }

  @Builder
  NoteRows() {
    ForEach(this.notes,
      (note: NoteItem, index: number): void => {
        NoteCard({
          note: note,
          isLast: index === this.notes.length - 1,
          onTap: (): void => { this.onSelect(note) },
        })
      },
      (note: NoteItem): string => note.id.toString()
    )
  }
}
