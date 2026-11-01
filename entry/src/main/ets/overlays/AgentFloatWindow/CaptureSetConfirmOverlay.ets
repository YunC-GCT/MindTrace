/**
 * CaptureSetConfirmOverlay.ets — 036 阶段 4：批量整理的入库前确认页
 *
 * 路径: overlays/AgentFloatWindow/CaptureSetConfirmOverlay.ets
 * 职责: 展示 previewCaptureSet 识别出的「题」列表（一图多题/多图多题），逐题勾选后再入库；
 *       needsReview（退化/灰区）默认不勾选，用户主动放行。
 * 依赖: common UI tokens + CaptureSetProblem 类型。
 */
import {
  BG_DARK,
  BORDER,
  GLASS_10,
  MINT,
  OVERLAY_MASK_SOLID,
  R_LG,
  R_MD,
  S_1,
  S_2,
  S_3,
  S_4,
  S_5,
  TEXT,
  TEXT_2,
  TEXT_3,
  W_MEDIUM,
  W_SEMIBOLD,
} from 'common'
import type { CaptureSetProblem } from 'common'

const PREVIEW_LIMIT: number = 42;

@Component
export struct CaptureSetConfirmOverlay {
  @Prop imageCount: number = 0
  @Prop failedCount: number = 0
  @Prop problems: CaptureSetProblem[] = []
  onConfirm: (selected: number[]) => void = (_selected: number[]): void => {}
  onCancel: () => void = (): void => {}

  @State selected: number[] = []

  aboutToAppear(): void {
    const initial: number[] = []
    for (let i = 0; i < this.problems.length; i++) {
      if (!this.problems[i].needsReview) {
        initial.push(this.problems[i].index)
      }
    }
    this.selected = initial
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(OVERLAY_MASK_SOLID)
        .onClick((): void => { this.onCancel() })

      Column() {
        Row() {
          Column() {
            Text('确认识别边界')
              .fontSize(16)
              .fontColor(TEXT)
              .fontWeight(W_SEMIBOLD)
              .width('100%')
            Text(this.subtitleText())
              .fontSize(11)
              .fontColor(TEXT_3)
              .margin({ top: S_1 })
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Row() {
            Text(this.selected.length.toString() + '/' + this.problems.length.toString())
              .fontSize(12)
              .fontColor(MINT)
              .fontWeight(W_MEDIUM)
            Text(this.allSelected() ? '取消全选' : '全选')
              .fontSize(12)
              .fontColor(MINT)
              .margin({ left: S_3 })
              .onClick((): void => { this.toggleAll() })
          }
        }
        .width('100%')
        .padding({ left: S_4, right: S_4, top: S_4, bottom: S_2 })

        if (this.failedCount > 0) {
          Text('另有 ' + this.failedCount.toString() + ' 张图未能识别，会被跳过')
            .fontSize(11)
            .fontColor(TEXT_2)
            .width('100%')
            .padding({ left: S_4, right: S_4, bottom: S_2 })
        }

        Scroll() {
          Column() {
            ForEach(this.problems, (problem: CaptureSetProblem): void => {
              this.problemRow(problem)
            }, (problem: CaptureSetProblem): string => 'problem-' + problem.index.toString())
          }
          .width('100%')
        }
        .constraintSize({ maxHeight: 520 })
        .scrollBar(BarState.Off)

        Row() {
          Button('取消')
            .fontSize(14)
            .fontColor(TEXT_2)
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .height(44)
            .onClick((): void => { this.onCancel() })
          Button(this.confirmLabel())
            .fontSize(14)
            .fontColor(BG_DARK)
            .fontWeight(W_SEMIBOLD)
            .backgroundColor(MINT)
            .layoutWeight(2)
            .height(44)
            .enabled(this.selected.length > 0)
            .opacity(this.selected.length > 0 ? 1 : 0.4)
            .onClick((): void => { this.onConfirm(this.selected) })
        }
        .width('100%')
        .padding({ left: S_3, right: S_3, top: S_2, bottom: S_3 })
      }
      .width('92%')
      .constraintSize({ maxHeight: '80%' })
      .backgroundColor(BG_DARK)
      .borderRadius(R_LG)
      .border({ width: 1, color: BORDER })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  problemRow(problem: CaptureSetProblem) {
    Row() {
      Checkbox({ name: 'capture-problem-' + problem.index.toString() })
        .select(this.isSelected(problem.index))
        .selectedColor(MINT)
        .width(20)
        .height(20)
        .onChange((value: boolean): void => { this.toggle(problem.index, value) })

      Column() {
        Row() {
          Text(this.problemTitle(problem))
            .fontSize(13)
            .fontColor(TEXT)
            .fontWeight(W_MEDIUM)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (problem.needsReview) {
            Text('待复核')
              .fontSize(10)
              .fontColor(TEXT_2)
              .backgroundColor(GLASS_10)
              .borderRadius(R_MD)
              .padding({ left: S_1, right: S_1, top: 1, bottom: 1 })
          }
        }
        .width('100%')

        Text(this.problemPreview(problem))
          .fontSize(11)
          .fontColor(TEXT_2)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: S_1 })
          .width('100%')

        Text(this.problemSource(problem))
          .fontSize(10)
          .fontColor(TEXT_3)
          .margin({ top: 1 })
          .width('100%')
      }
      .layoutWeight(1)
      .margin({ left: S_2 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: S_4, right: S_4, top: S_2, bottom: S_2 })
    .onClick((): void => { this.toggle(problem.index, !this.isSelected(problem.index)) })
  }

  private isSelected(index: number): boolean {
    return this.selected.indexOf(index) >= 0
  }

  private toggle(index: number, value: boolean): void {
    const next: number[] = []
    for (let i = 0; i < this.selected.length; i++) {
      if (this.selected[i] !== index) {
        next.push(this.selected[i])
      }
    }
    if (value) {
      next.push(index)
    }
    this.selected = next
  }

  private subtitleText(): string {
    const reviewCount: number = this.problems.length - this.selectedReviewFreeCount();
    const base: string = this.imageCount.toString() + ' 张图识别出 ' + this.problems.length.toString()
      + ' 道题；取消勾选不需要入库的题';
    return reviewCount > 0 ? base + '（' + reviewCount.toString() + ' 道待复核默认不勾选）' : base;
  }

  private selectedReviewFreeCount(): number {
    let count: number = 0;
    for (let i = 0; i < this.problems.length; i++) {
      if (!this.problems[i].needsReview) {
        count += 1;
      }
    }
    return count;
  }

  private allSelected(): boolean {
    return this.problems.length > 0 && this.selected.length === this.problems.length;
  }

  private toggleAll(): void {
    if (this.allSelected()) {
      this.selected = [];
      return;
    }
    const all: number[] = [];
    for (let i = 0; i < this.problems.length; i++) {
      all.push(this.problems[i].index);
    }
    this.selected = all;
  }

  private confirmLabel(): string {
    return '确认整理（' + this.selected.length.toString() + ' 题）'
  }

  private problemTitle(problem: CaptureSetProblem): string {
    const anchor: string = problem.anchors.length > 0 ? problem.anchors.join(' / ') : '无题号'
    return '第 ' + (problem.index + 1).toString() + ' 题 · ' + anchor
  }

  private problemPreview(problem: CaptureSetProblem): string {
    const text: string = problem.text.replace(/\s+/g, ' ').trim()
    return text.length > PREVIEW_LIMIT ? text.substring(0, PREVIEW_LIMIT) + '…' : text
  }

  private problemSource(problem: CaptureSetProblem): string {
    const labels: string[] = []
    for (let i = 0; i < problem.sourceImageIndexes.length; i++) {
      labels.push('第 ' + (problem.sourceImageIndexes[i] + 1).toString() + ' 张图')
    }
    return '来源：' + (labels.length > 0 ? labels.join(' + ') : '未知')
  }
}
