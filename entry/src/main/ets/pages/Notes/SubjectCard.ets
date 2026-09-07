/**
 * SubjectCard.ets — 学科入口卡片
 *
 * 路径: pages/Notes/SubjectCard.ets
 * 职责: 渲染 Notes 一级页的学科入口，支持块视图和列视图。
 * 依赖: common 视觉令牌
 *
 * 数据流:
 *   SubjectGrid(group, viewMode)
 *     → SubjectCard
 *       → onTap(subject)
 *
 * ArkTS 1.1 strict 适配:
 *   - 无 any/unknown
 *   - 无 C 风格 for
 *   - struct 内只使用 @Builder
 */

import {
  BG_CARD, BORDER, GLASS_8, TEXT, TEXT_2, TEXT_3, TEXT_4,
  S_1, S_2, S_3, S_4,
  R_MD, R_LG,
  F_XS, F_SM, F_MD,
  W_BOLD, W_SEMIBOLD,
  glassSurfaceColor,
} from "common"
import { MathPreviewText } from "../../shared/atoms/MathPreviewText"

function subjectMark(subject: string): string {
  const trimmed: string = subject.trim()
  return trimmed.length > 0 ? trimmed.substring(0, 1) : "记"
}

function fallbackColor(color: string): string {
  return color.length > 0 ? color : BORDER
}

function firstPreview(previewTitles: string[]): string {
  return previewTitles.length > 0 ? previewTitles[0] : "暂无预览"
}

@Component
export struct SubjectCard {
  @Prop subject: string = ""
  @Prop color: string = ""
  @Prop count: number = 0
  @Prop previewTitles: string[] = []
  @Prop viewMode: string = "block"
  onTap: () => void = (): void => {}

  build() {
    if (this.viewMode === "list") {
      this.ListRow()
    } else {
      this.BlockCard()
    }
  }

  @Builder
  SubjectBadge(size: number, fontSize: number) {
    Stack() {
      Circle({ width: size, height: size })
        .fill(glassSurfaceColor(fallbackColor(this.color)))
        .stroke(glassSurfaceColor(fallbackColor(this.color)))
        .strokeWidth(1)
      Circle({ width: size - 12, height: size - 12 })
        .fill(glassSurfaceColor(fallbackColor(this.color)))
      Text(subjectMark(this.subject))
        .fontSize(fontSize)
        .fontWeight(W_BOLD)
        .fontColor(fallbackColor(this.color))
    }
    .width(size)
    .height(size)
    .alignContent(Alignment.Center)
  }

  @Builder
  BlockCard() {
    Column() {
      Row() {
        this.SubjectBadge(38, F_MD - 1)
        Blank()
        Text(this.count.toString() + " 条")
          .fontSize(F_XS)
          .fontColor(TEXT_3)
      }
      .width("100%")
      .alignItems(VerticalAlign.Center)

      Text(this.subject)
        .fontSize(F_MD - 1)
        .fontWeight(W_SEMIBOLD)
        .fontColor(TEXT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width("100%")
        .margin({ top: S_3 })

      MathPreviewText({
        text: firstPreview(this.previewTitles),
        textColor: TEXT_4,
        fontSize: F_XS,
        lineHeightValue: 17,
        maxLines: 2,
        minHeight: 32,
      })
        .width("100%")
        .margin({ top: S_1 })
    }
    .width("100%")
    .height(116)
    .padding({ left: S_3, right: S_3, top: S_3, bottom: S_3 })
    .backgroundColor(BG_CARD)
    .linearGradient({
      angle: 145,
      colors: [
        [GLASS_8, 0],
        [glassSurfaceColor(fallbackColor(this.color)), 0.28],
        [BG_CARD, 1],
      ],
    })
    .border({ width: 0.5, color: glassSurfaceColor(fallbackColor(this.color)) })
    .borderRadius(R_LG)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .onClick((): void => this.onTap())
  }

  @Builder
  ListRow() {
    Row() {
      Row() {
        this.SubjectBadge(36, F_SM + 1)
      }
      .margin({ right: S_3 })

      Column() {
        Row() {
          Text(this.subject)
            .fontSize(F_SM + 1)
            .fontWeight(W_SEMIBOLD)
            .fontColor(TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(this.count.toString() + " 条")
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .margin({ left: S_2 })
            .flexShrink(0)
        }
        .width("100%")
        .alignItems(VerticalAlign.Center)

        MathPreviewText({
          text: firstPreview(this.previewTitles),
          textColor: TEXT_4,
          fontSize: F_XS,
          lineHeightValue: 17,
          maxLines: 1,
          minHeight: 18,
        })
          .width("100%")
          .margin({ top: S_1 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text("›")
        .fontSize(F_MD)
        .fontColor(TEXT_2)
        .margin({ left: S_2 })
    }
    .width("100%")
    .height(72)
    .padding({ left: S_4, right: S_4, top: S_2, bottom: S_2 })
    .backgroundColor(BG_CARD)
    .linearGradient({
      angle: 145,
      colors: [
        [GLASS_8, 0],
        [glassSurfaceColor(fallbackColor(this.color)), 0.24],
        [BG_CARD, 1],
      ],
    })
    .border({ width: 0.5, color: glassSurfaceColor(fallbackColor(this.color)) })
    .borderRadius(R_MD)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => this.onTap())
  }
}
