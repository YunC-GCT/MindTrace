// MindTrace - ErrorBanner 全错误横幅原子 (评审前 1.5 项 / fix/demo-polish-2026-09-06)
//
// 设计:
//   - 顶部固定, 全宽, 三档 severity (info 蓝 / warn 琥珀 / error 红)
//   - 默认 1s 入场, 内容展示 5s 自动消失 (info) / 8s (warn) / 持续 (error 需用户手动关)
//   - 三件套: [图标+severity指示] [title + message] [action按钮(可选)]
//   - 消费 ErrorBus.publish 事件, 单组件订阅不需业务层每个页面订阅
//
// 集成:
//   entry/src/main/ets/pages/Index.ets 在 aboutToAppear 订阅 ErrorBus,
//     AppStorage 不掺和 (错误是 UI 短期状态, 不持久化)

import { AppError, ErrorSeverity, ErrorBus, TEXT, TEXT_2, TEXT_3, BORDER } from 'common';

@Component
export struct ErrorBanner {
  @State current: AppError | null = null;
  @State visible: boolean = false;
  private dismissTimer: number = -1;
  private unsubscribe: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsubscribe = ErrorBus.subscribe((err: AppError): void => {
      this.show(err);
    });
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
    if (this.dismissTimer !== -1) {
      clearTimeout(this.dismissTimer);
      this.dismissTimer = -1;
    }
  }

  private show = (err: AppError): void => {
    if (this.dismissTimer !== -1) {
      clearTimeout(this.dismissTimer);
      this.dismissTimer = -1;
    }
    this.current = err;
    this.visible = true;
    // info 5s 自动消失, warn 8s, error 不自动消失
    const ttl: number = err.severity === 'info' ? 5000 : (err.severity === 'warn' ? 8000 : -1);
    if (ttl > 0) {
      this.dismissTimer = setTimeout((): void => {
        this.dismiss();
      }, ttl);
    }
  };

  private dismiss = (): void => {
    this.visible = false;
    if (this.dismissTimer !== -1) {
      clearTimeout(this.dismissTimer);
      this.dismissTimer = -1;
    }
    // 250ms 后清空 (留出淡出动画时间, 此版本无动画直接清)
    setTimeout((): void => {
      this.current = null;
    }, 250);
  };

  private severityBg = (severity: ErrorSeverity): string => {
    if (severity === 'info') {
      return 'rgba(91, 227, 176, 0.15)';
    }
    if (severity === 'warn') {
      return 'rgba(251, 191, 36, 0.15)';
    }
    return 'rgba(239, 68, 68, 0.18)';
  };

  private severityBorder = (severity: ErrorSeverity): string => {
    if (severity === 'info') {
      return '#5BE3B0';
    }
    if (severity === 'warn') {
      return '#FBBF24';
    }
    return '#EF4444';
  };

  private severityIcon = (severity: ErrorSeverity): string => {
    if (severity === 'info') {
      return 'i';
    }
    if (severity === 'warn') {
      return '!';
    }
    return 'x';
  };

  build() {
    if (this.current === null) {
      Blank();
    } else {
      Stack() {
        Row() {
          Text(this.severityIcon(this.current.severity))
            .fontSize(16)
            .fontWeight(700)
            .fontColor(this.severityBorder(this.current.severity))
            .width(24)
            .height(24)
            .textAlign(TextAlign.Center)
            .borderRadius(12)
            .backgroundColor(this.severityBg(this.current.severity))

          Column() {
            Text(this.current.title)
              .fontSize(14)
              .fontWeight(600)
              .fontColor(TEXT)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.current.message.length > 0) {
              Text(this.current.message)
                .fontSize(12)
                .fontColor(TEXT_2)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 2 })
            }
          }
          .layoutWeight(1)
          .margin({ left: 12 })
          .alignItems(HorizontalAlign.Start)

          if (this.current.action !== 'none' && this.current.actionLabel !== undefined) {
            Text(this.current.actionLabel)
              .fontSize(13)
              .fontColor(this.severityBorder(this.current.severity))
              .fontWeight(600)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(6)
              .border({ width: 1, color: this.severityBorder(this.current.severity) })
              .onClick((): void => {
                this.handleAction();
              })
          }

          Text('×')
            .fontSize(20)
            .fontColor(TEXT_3)
            .fontWeight(400)
            .padding({ left: 12 })
            .onClick((): void => {
              this.dismiss();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor(this.severityBg(this.current.severity))
        .border({ width: { bottom: 1 }, color: this.severityBorder(this.current.severity) })
      }
      .width('100%')
      .opacity(this.visible ? 1 : 0)
    }
  }

  private handleAction = (): void => {
    // MVP: action 仅为占位 — 后续集成 router / 业务 callback
    this.dismiss();
  };
}
