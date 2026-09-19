/**
 * ImagePreviewBar.ets — 图片预览行 (可点预览 + X 删除)
 *
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/ImagePreviewBar.ets
 * 职责: 发送前显示已选图片缩略图 + 提示文字 + ✕ 删除
 *       点击缩略图 → 全屏预览 (再点关闭)
 *       ✕ 按钮 → 调 onClear 清除 (由 vm.clearImagePreview 处理)
 * 依赖: common; 图标: SymbolGlyph 系统
 *
 * 视觉:
 *   ┌──┐                              [✕]
 *   │📷│ 已选图片,可补充文字后发送    [✕]
 *   │  │
 *   └─✕┘ (✕ 浮在缩略图右上)
 *
 *   ↑点缩略图 → 全屏预览 (点空白处关闭)
 */

import {
  BG_DARK, BORDER, TEXT, TEXT_3,
  S_2, S_3, R_FULL,
  F_XS,
} from 'common';

@Component
export struct ImagePreviewBar {
  @Prop imagePreview: string = '';
  @State showFullPreview: boolean = false;
  onClear: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 主内容 (Row)
      if (this.imagePreview.length > 0) {
        Row() {
          this.thumbnailWithDelete()

          Text('已选图片，可补充文字后发送')
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .margin({ left: S_3 })
            .layoutWeight(1)

          Blank()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: S_3, right: S_3, top: S_2, bottom: S_2 })
      }

      // 全屏预览覆盖 (fullScreenCover)
      if (this.showFullPreview) {
        this.fullPreviewBuilder()
      }
    }
    .width('100%')
  }

  @Builder
  thumbnailWithDelete() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 缩略图 (点 → 全屏预览)
      Image(this.imagePreview)
        .width(48)
        .height(48)
        .borderRadius(8)
        .objectFit(ImageFit.Cover)
        .border({ width: 1, color: BORDER })
        .onClick((): void => {
          this.showFullPreview = true;
        });

      // ✕ 删除按钮 (浮在缩略图右上)
      SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
        .fontSize(18)
        .fontColor([TEXT])
        .margin({ top: -6, right: -6 })
        .onClick((): void => {
          this.onClear();
        });
    }
    .width(48)
    .height(48);
  }

  @Builder
  fullPreviewBuilder() {
    Stack() {
      Image(this.imagePreview)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .backgroundColor(BG_DARK)
        .onClick((): void => {
          this.showFullPreview = false;
        });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_DARK);
  }
}
