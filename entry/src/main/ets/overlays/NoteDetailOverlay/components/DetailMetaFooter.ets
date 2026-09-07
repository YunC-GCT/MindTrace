/**
 * DetailMetaFooter.ets — 详情页底部元信息收束区
 *
 * 路径: entry/src/main/ets/overlays/NoteDetailOverlay/components/DetailMetaFooter.ets
 * 职责: 集中展示 tags / prerequisites / related / source / review，避免散落在正文中。
 * 依赖: common tokens, ChipTag, DetailRenderModel
 *
 * 数据流:
 *   DetailRenderModel → DetailMetaFooter
 *
 * ArkTS 1.1 strict 适配:
 *   - ForEach 使用稳定 key
 *   - struct 内无普通方法
 */

import {
  TEXT_2, TEXT_3, BORDER,
  S_2, S_3, S_4,
  F_SM, F_XS,
  W_BOLD,
} from 'common'
import { ChipTag } from '../ChipTag'
import {
  DetailRenderModel,
  emptyDetailRenderModel,
  hasDetailMeta,
  originalSectionText,
} from '../model/DetailRenderModel'
import { detailLinesSignature, detailTextSignature } from './DetailSection'
import { DETAIL_RENDER_PRIORITY_META, enqueueDetailRender } from './DetailRenderQueue'
import { MarkdownRenderer } from '../../../shared/molecules/MarkdownRenderer'
import { AppIcon } from '../../../shared/atoms/AppIcon'

@Component
export struct DetailMetaFooter {
  @Prop @Watch('onModelChanged') model: DetailRenderModel = emptyDetailRenderModel()
  @State contentReady: boolean = false
  @State originalExpanded: boolean = false
  @State originalText: string = ''
  private contentRenderKey: string = ''
  private renderSeq: number = 0

  aboutToAppear(): void {
    this.resetContentRender()
  }

  aboutToDisappear(): void {
    this.renderSeq += 1
  }

  onModelChanged(): void {
    this.resetContentRender()
  }

  build() {
    if (this.contentReady) {
      Column() {
        if (this.model.tags.length > 0) {
          this.ChipGroup('标签', this.model.tags, 'tag_')
        }

        if (this.model.prerequisites.length > 0) {
          this.ChipGroup('前置知识', this.model.prerequisites, 'pre_')
        }

        if (this.model.related.length > 0) {
          this.ChipGroup('关联知识', this.model.related, 'rel_')
        }

        if (this.model.sourceLabel.length > 0) {
          this.MetaLine('来源', this.model.sourceLabel)
        }

        if (this.model.reviewLine.length > 0) {
          this.MetaLine('复习', this.model.reviewLine)
        }

        if (this.originalText.length > 0) {
          this.OriginalMaterial(this.originalText)
        }
      }
      .width('100%')
      .padding({ top: S_4, bottom: S_3 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  ChipGroup(title: string, items: string[], prefix: string) {
    Column() {
      Text(title)
        .fontSize(F_XS)
        .fontWeight(W_BOLD)
        .fontColor(TEXT_3)
        .width('100%')
        .margin({ bottom: S_2 })

      Flex({
        direction: FlexDirection.Row,
        wrap: FlexWrap.Wrap,
        justifyContent: FlexAlign.Start,
        alignItems: ItemAlign.Center,
      }) {
        ForEach(items,
          (label: string): void => {
            Row() {
              ChipTag({ label: label, variant: 'tag' })
            }
            .margin({ right: S_2, bottom: S_2 })
          },
          (label: string): string => prefix + label
        )
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: S_2 })
  }

  @Builder
  MetaLine(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(F_XS)
        .fontWeight(W_BOLD)
        .fontColor(TEXT_3)
        .width(52)

      Text(value)
        .fontSize(F_SM)
        .fontColor(TEXT_2)
        .lineHeight(20)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: S_2 })
  }

  @Builder
  OriginalMaterial(content: string) {
    Column() {
      Row() {
        Text('原始材料')
          .fontSize(F_SM)
          .fontWeight(W_BOLD)
          .fontColor(TEXT_2)
          .layoutWeight(1)

        AppIcon({
          name: this.originalExpanded ? 'chevron-up' : 'chevron-down',
          iconSize: F_SM,
          color: TEXT_3,
          strokeWidth: 1.8,
        })
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.originalExpanded = !this.originalExpanded
      })

      if (this.originalExpanded) {
        MarkdownRenderer({ text: content, progressive: true })
      }
    }
    .width('100%')
    .border({ width: { top: 0.5 }, color: BORDER })
    .alignItems(HorizontalAlign.Start)
  }

  private resetContentRender = (): void => {
    const originalText: string = originalSectionText(this.model)
    const key: string = this.modelSignature(originalText)
    if (key === this.contentRenderKey) {
      return
    }
    this.contentRenderKey = key
    this.originalExpanded = false
    this.originalText = originalText
    this.renderSeq += 1
    const seq: number = this.renderSeq
    if (!hasDetailMeta(this.model)) {
      this.contentReady = false
      return
    }
    this.contentReady = false
    enqueueDetailRender(key, DETAIL_RENDER_PRIORITY_META, (): void => {
      if (seq !== this.renderSeq) {
        return
      }
      this.contentReady = true
    })
  }

  private modelSignature = (originalText: string): string => {
    return detailLinesSignature(this.model.tags)
      + '|' + detailLinesSignature(this.model.prerequisites)
      + '|' + detailLinesSignature(this.model.related)
      + '|' + detailTextSignature(this.model.sourceLabel)
      + '|' + detailTextSignature(this.model.reviewLine)
      + '|' + detailTextSignature(originalText)
  }
}
