/**
 * FallbackDetailView.ets - source-order note detail renderer
 *
 * Path: entry/src/main/ets/overlays/NoteDetailOverlay/renderers/FallbackDetailView.ets
 * Responsibility: Render unmatched/manual notes in their original section order.
 * Dependencies: DetailRenderModel, MarkdownRenderer, DetailMetaFooter.
 *
 * ArkTS 1.1 strict:
 *   - Explicit typed values throughout
 *   - No C-style for loops
 *   - ForEach uses stable section keys
 */

import {
  TEXT, TEXT_2, TEXT_3, BORDER,
  S_1, S_2, S_3, S_4,
  F_XS, F_SM,
  W_BOLD, W_SEMIBOLD,
} from 'common'
import {
  DetailRenderModel,
  DetailSectionData,
  emptyDetailRenderModel,
  fallbackMainText,
} from '../model/DetailRenderModel'
import { MarkdownRenderer } from '../../../shared/molecules/MarkdownRenderer'
import { DetailMetaFooter } from '../components/DetailMetaFooter'

const TITLE_SUMMARY: string = '\u6458\u8981'
const TITLE_BODY: string = '\u6b63\u6587'
const LABEL_SOURCE: string = '\u539f\u6587'

function fallbackTextHash(text: string): string {
  let hash: number = 5381
  let index: number = 0
  while (index < text.length) {
    hash = ((hash << 5) + hash + text.charCodeAt(index)) | 0
    index += 1
  }
  const positive: number = hash < 0 ? -hash : hash
  return text.length.toString() + ':' + positive.toString()
}

function fallbackModelKey(model: DetailRenderModel): string {
  return model.category + '|' + fallbackTextHash(model.summary) + '|' + fallbackTextHash(model.body)
}

@Component
export struct FallbackDetailView {
  @Prop @Watch('onModelChanged') model: DetailRenderModel = emptyDetailRenderModel()
  @State visibleStage: number = 0
  private renderKey: string = ''
  private renderSeq: number = 0

  aboutToAppear(): void {
    this.resetFallbackFlow()
  }

  aboutToDisappear(): void {
    this.renderSeq += 1
  }

  onModelChanged(): void {
    this.resetFallbackFlow()
  }

  build() {
    Column() {
      if (this.hasReadableSections()) {
        ForEach(this.model.sections,
          (section: DetailSectionData, index: number): void => {
            if (section.normalizedTitle !== 'original' && this.shouldShowSection(index)) {
              this.SourceSection(section.title, section.content, index)
            }
          },
          (section: DetailSectionData): string => section.key
        )
      } else {
        this.SourceSection(this.model.summary.length > 0 ? TITLE_SUMMARY : TITLE_BODY, fallbackMainText(this.model), 0)
      }

      if (this.visibleStage >= 3) {
        DetailMetaFooter({ model: this.model })
        Blank().height(80)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: S_2, bottom: S_2 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SourceLabel(index: number) {
    Row() {
      Text(LABEL_SOURCE)
        .fontSize(F_XS)
        .fontWeight(W_BOLD)
        .fontColor(TEXT_3)
        .letterSpacing(0)

      Text((index + 1).toString())
        .fontSize(F_XS)
        .fontWeight(W_BOLD)
        .fontColor(TEXT_3)
        .letterSpacing(0)
        .margin({ left: S_1 })
    }
    .padding({ left: S_2, right: S_2, top: S_1, bottom: S_1 })
    .border({ width: 0.5, color: BORDER })
    .borderRadius(6)
    .margin({ bottom: S_2 })
  }

  @Builder
  SourceSection(title: string, content: string, index: number) {
    if (content.trim().length > 0) {
      Column() {
        this.SourceLabel(index)
        Text(title.trim().length > 0 ? title.trim() : TITLE_BODY)
          .fontSize(F_SM)
          .fontWeight(index === 0 ? W_BOLD : W_SEMIBOLD)
          .fontColor(index === 0 ? TEXT : TEXT_2)
          .width('100%')
          .margin({ bottom: S_2 })
        MarkdownRenderer({ text: content, progressive: true })
      }
      .width('100%')
      .padding({ top: index === 0 ? S_3 : S_4, bottom: index === 0 ? S_4 : S_3 })
      .border({ width: { bottom: 0.5 }, color: BORDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  private shouldShowSection = (index: number): boolean => {
    if (index === 0) {
      return true
    }
    if (index === 1) {
      return this.visibleStage >= 1
    }
    if (index === 2) {
      return this.visibleStage >= 2
    }
    return this.visibleStage >= 3
  }

  private hasReadableSections = (): boolean => {
    for (const section of this.model.sections) {
      if (section.normalizedTitle !== 'original' && section.content.trim().length > 0) {
        return true
      }
    }
    return false
  }

  private resetFallbackFlow = (): void => {
    const key: string = fallbackModelKey(this.model)
    if (key === this.renderKey) {
      return
    }
    this.renderKey = key
    this.renderSeq += 1
    const seq: number = this.renderSeq
    this.visibleStage = 0
    this.scheduleFallbackStage(seq, 1, 60)
    this.scheduleFallbackStage(seq, 2, 140)
    this.scheduleFallbackStage(seq, 3, 240)
  }

  private scheduleFallbackStage = (seq: number, stage: number, delay: number): void => {
    setTimeout((): void => {
      if (seq !== this.renderSeq) {
        return
      }
      if (this.visibleStage < stage) {
        this.visibleStage = stage
      }
    }, delay)
  }
}
