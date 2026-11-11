/**
 * SubjectGrid.ets — 学科入口列表
 *
 * 路径: pages/Notes/SubjectGrid.ets
 * 职责: 根据 viewMode 渲染一级 Notes 页的学科入口，支持块视图和列视图。
 * 依赖: SubjectCard、NotesViewModel.SubjectGroup
 *
 * 数据流:
 *   NotesPage.subjectViewMode / NotesViewModel.subjectGroups
 *     → SubjectGrid
 *       → SubjectCard
 *
 * ArkTS 1.1 strict 适配:
 *   - 无 any/unknown
 *   - 无 C 风格 for
 *   - struct 内无普通方法
 */

import { S_2, S_4 } from "common"
import { SubjectGroup } from "../../viewmodels/NotesViewModel"
import { SubjectCard } from "./SubjectCard"

@Component
export struct SubjectGrid {
  @Prop groups: SubjectGroup[] = []
  @Prop viewMode: string = "block"
  onSelect: (subject: string) => void = (_subject: string): void => {}

  build() {
    Scroll() {
      Column() {
        Grid() {
          ForEach(this.groups,
            (group: SubjectGroup): void => {
              GridItem() {
                SubjectCard({
                  subject: group.subject,
                  color: group.color,
                  count: group.count,
                  previewTitles: group.previewTitles,
                  viewMode: this.viewMode,
                  onTap: (): void => this.onSelect(group.subject),
                })
              }
            },
            (group: SubjectGroup): string => group.subject + "_" + group.count.toString()
          )
        }
        .width("100%")
        .columnsTemplate(this.viewMode === "list" ? "1fr" : "1fr 1fr")
        .columnsGap(S_2)
        .rowsGap(S_2)
      }
      .width("100%")
      .constraintSize({ minHeight: "100%" })
      .padding({ left: S_4, right: S_4, bottom: 96 })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .width("100%")
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}
