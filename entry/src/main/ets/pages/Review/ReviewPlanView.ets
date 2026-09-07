import {
  BG_CARD, BORDER, GLASS_8, MINT, PINK, TEXT, TEXT_3,
  S_2, S_3, S_4, S_5,
  R_LG, R_FULL,
  F_XS, F_SM, F_BASE,
  W_SEMIBOLD,
  StudyPlanItem,
} from "common"
import { StudyPlanViewModel } from "../../viewmodels/StudyPlanViewModel"
import { AppIcon } from "../../shared/atoms/AppIcon"
import { ReviewPlanRow } from "./ReviewPlanRow"

@Component
export struct ReviewPlanView {
  @ObjectLink vm: StudyPlanViewModel
  @Prop planItems: StudyPlanItem[] = []
  @Prop liveIds: string[] = []
  @Prop showAddPlan: boolean = false
  @Prop addTitle: string = ""
  onPromote: (item: StudyPlanItem) => void = (_item: StudyPlanItem): void => {}
  onPromoteTop: (item: StudyPlanItem) => void = (_item: StudyPlanItem): void => {}
  onDemote: (item: StudyPlanItem) => void = (_item: StudyPlanItem): void => {}
  onCrossToReview: (item: StudyPlanItem) => void = (_item: StudyPlanItem): void => {}
  onMoveLive: (item: StudyPlanItem, direction: number) => void = (_item: StudyPlanItem, _direction: number): void => {}
  onMoveReview: (item: StudyPlanItem, direction: number) => void = (_item: StudyPlanItem, _direction: number): void => {}
  onRemovePlan: (item: StudyPlanItem) => void = (_item: StudyPlanItem): void => {}
  onAddTitleChange: (value: string) => void = (_value: string): void => {}
  onSubmitAdd: () => void = (): void => {}
  onCancelAdd: () => void = (): void => {}

  private activeItems(): StudyPlanItem[] {
    return this.planItems
  }

  private liveItems(): StudyPlanItem[] {
    const result: StudyPlanItem[] = []
    const activeItems: StudyPlanItem[] = this.activeItems()
    this.liveIds.forEach((id: string): void => {
      const found: StudyPlanItem | undefined = activeItems.find((item: StudyPlanItem): boolean => item.id === id && !item.isDone)
      if (found !== undefined) {
        result.push(found)
      }
    })
    return result
  }

  private reviewItems(): StudyPlanItem[] {
    const result: StudyPlanItem[] = []
    this.activeItems().forEach((item: StudyPlanItem): void => {
      if (this.liveIds.indexOf(item.id) < 0) {
        result.push(item)
      }
    })
    return result
  }

  private reserveHeight(): number {
    const liveCount: number = this.liveItems().length
    if (liveCount <= 0) {
      return 110
    }
    if (liveCount === 1) {
      return 50
    }
    return 0
  }

  private priorityText(priority: number): string {
    if (priority <= 1) {
      return "高优先级"
    }
    if (priority >= 3) {
      return "低优先级"
    }
    return "中优先级"
  }

  private tagText(priority: number): string {
    if (priority <= 1) {
      return "重点"
    }
    if (priority >= 3) {
      return "巩固"
    }
    return "复习"
  }

  private metaText(item: StudyPlanItem): string {
    if (this.vm.items.length === 0) {
      return "预览计划 · 可加入实时队列"
    }
    if (item.linkedNoteId.length > 0) {
      return "关联笔记 · " + this.priorityText(item.priority)
    }
    return "待关联笔记 · " + this.priorityText(item.priority)
  }

  build() {
    Column() {
      Column() {
        Row({ space: S_3 }) {
          Text("实时队列")
            .fontSize(F_BASE + 1)
            .fontWeight(W_SEMIBOLD)
            .fontColor(TEXT)
            .layoutWeight(1)

          Text("拖动条目排序 / 跨队列")
            .fontSize(F_XS)
            .fontColor(TEXT_3)
        }
        .width("100%")
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: S_3 })

        Column({ space: S_2 }) {
          if (this.liveItems().length === 0) {
            Row() {
              Text("复习队列条目上拖越界会进入这里")
                .fontSize(F_SM)
                .fontColor(TEXT_3)
            }
            .width("100%")
            .height(56)
            .padding({ left: S_3, right: S_3 })
            .backgroundColor(GLASS_8)
            .border({ width: 0.5, color: BORDER })
            .borderRadius(R_LG)
            .alignItems(VerticalAlign.Center)
          } else {
            ForEach(this.liveItems(),
              (item: StudyPlanItem, index: number): void => {
                ReviewPlanRow({
                  title: item.title,
                  meta: "实时计划 " + (index + 1).toString() + "/" + this.liveItems().length.toString(),
                  tag: this.tagText(item.priority),
                  tone: index % 3,
                  actionIcon: "chevron-down",
                  actionColor: TEXT_3,
                  deleteIcon: "trash",
                  deleteColor: PINK,
                  onAction: (): void => this.onDemote(item),
                  onMoveUp: (): void => this.onMoveLive(item, -1),
                  onMoveDown: (): void => this.onMoveLive(item, 1),
                  onCrossDown: (): void => this.onCrossToReview(item),
                  onRemovePlan: (): void => this.onRemovePlan(item),
                })
              },
              (item: StudyPlanItem): string => item.id
            )
          }

          if (this.reserveHeight() > 0) {
            Blank()
              .height(this.reserveHeight())
          }
        }
        .width("100%")
      }
      .width("100%")
      .padding({ left: S_5, right: S_5, top: S_4, bottom: S_4 })
      .linearGradient({
        angle: 180,
        colors: [
          ["#145BE3B0", 0],
          ["#08000000", 1],
        ],
      })

      Row()
        .width("100%")
        .height(18)
        .linearGradient({
          angle: 180,
          colors: [
            ["#08000000", 0],
            [GLASS_8, 1],
          ],
        })
        .border({ width: { top: 0.5 }, color: BORDER })

      Column() {
        Text("复习队列")
          .fontSize(F_BASE + 1)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT)
          .margin({ bottom: S_3 })

        if (this.showAddPlan) {
          Row({ space: S_2 }) {
            TextInput({ placeholder: "新增复习计划...", text: this.addTitle })
              .onChange((value: string): void => this.onAddTitleChange(value))
              .onSubmit((): void => this.onSubmitAdd())
              .layoutWeight(1)
              .height(42)
              .borderRadius(R_FULL)
              .backgroundColor(BG_CARD)
              .padding({ left: S_3, right: S_3 })
              .fontColor(TEXT)
              .placeholderColor(TEXT_3)

            Button() {
              AppIcon({ name: "check", iconSize: F_SM + 7, color: MINT, strokeWidth: 2 })
            }
            .width(42)
            .height(42)
            .borderRadius(R_FULL)
            .backgroundColor(GLASS_8)
            .enabled(this.addTitle.trim().length > 0)
            .onClick((): void => this.onSubmitAdd())

            Button() {
              AppIcon({ name: "close", iconSize: F_SM + 7, color: TEXT_3, strokeWidth: 2 })
            }
            .width(42)
            .height(42)
            .borderRadius(R_FULL)
            .backgroundColor(GLASS_8)
            .onClick((): void => this.onCancelAdd())
          }
          .width("100%")
          .margin({ bottom: S_3 })
        }

        if (this.reviewItems().length === 0) {
          Row() {
            Text(this.vm.items.length === 0 ? "测试计划已全部进入实时队列" : "复习队列已清空")
              .fontSize(F_SM)
              .fontColor(TEXT_3)
          }
          .width("100%")
          .height(56)
          .padding({ left: S_3, right: S_3 })
          .backgroundColor(BG_CARD)
          .border({ width: 0.5, color: BORDER })
          .borderRadius(R_LG)
          .alignItems(VerticalAlign.Center)
        } else {
          Column({ space: S_2 }) {
            ForEach(this.reviewItems(),
              (item: StudyPlanItem, index: number): void => {
                ReviewPlanRow({
                  title: item.title,
                  meta: this.metaText(item),
                  tag: this.tagText(item.priority),
                  tone: (index + 1) % 3,
                  actionIcon: "chevron-up",
                  actionColor: MINT,
                  deleteIcon: "trash",
                  deleteColor: PINK,
                  onAction: (): void => this.onPromote(item),
                  onMoveUp: (): void => this.onMoveReview(item, -1),
                  onMoveDown: (): void => this.onMoveReview(item, 1),
                  onCrossUp: (): void => this.onPromoteTop(item),
                  onRemovePlan: (): void => this.onRemovePlan(item),
                })
              },
              (item: StudyPlanItem): string => item.id
            )
          }
          .width("100%")
          .layoutWeight(1)
        }

        Text(this.vm.items.length === 0 ? "预览数据；点击 + 新增复习计划" : "拖动条目调整顺序；大幅上/下拖可跨队列")
          .fontSize(F_XS)
          .fontColor(TEXT_3)
          .margin({ top: S_2, left: 2 })
      }
      .width("100%")
      .layoutWeight(1)
      .padding({ left: S_5, right: S_5, top: S_4, bottom: S_4 })
      .backgroundColor(GLASS_8)
    }
    .width("100%")
    .layoutWeight(1)
  }
}
