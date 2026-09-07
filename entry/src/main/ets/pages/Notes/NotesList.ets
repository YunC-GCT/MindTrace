// ============================================================================
//  pages/Notes/NotesList.ets — 笔记列表
//  ----------------------------------------------------------------------------
//  职责: 用 List 容器(支持懒加载)渲染所有笔记,每项是 NoteCard。
//
//  布局:
//    List(ListItem × N + ListItem 底部留白)
//
//  依赖:
//    shared: NoteCard
//
//  Props:
//    notes:    NoteItem[] (从 NotesPage 注入)
//    onSelect: 笔记卡片点击回调
//  ============================================================================

import { NoteItem } from "common"
import { NoteCard } from "../../shared/organisms/NoteCard"

@Component
export struct NotesList {
  // 笔记数据
  @Prop notes: NoteItem[] = []

  // 笔记点击回调
  onSelect: (note: NoteItem) => void = (_note: NoteItem): void => {}

  build() {
    List() {
      // 笔记卡片(最后一条不画分隔线)
      ForEach(this.notes,
        (note: NoteItem, idx: number): void => {
          ListItem() {
            NoteCard({
              note: note,
              isLast: idx === this.notes.length - 1,
              onTap: (): void => { this.onSelect(note) },
            })
          }
        },
        // ForEach keyGenerator 必填
        (note: NoteItem): string => note.id.toString()
      )
      // FAB 底部留白
      ListItem() {
        Column() { Blank().height(80) }
      }
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }
}
