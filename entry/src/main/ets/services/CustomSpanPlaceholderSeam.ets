/**
 * CustomSpanPlaceholderSeam.ets — 行内公式 CustomSpan 占位模型与验证报告
 *
 * 路径: entry/src/main/ets/services/CustomSpanPlaceholderSeam.ets
 * 职责: 提供公式占位宽度估算、open/closed 状态模型和测试报告计数。
 * 依赖: 无外部模块。
 * 数据流: 公式文本 delta → InlineFormulaPlaceholderModel → PlaceholderMetrics / CustomSpanVerificationReport
 * ArkTS 1.1 strict 适配: 使用显式接口与类字段，避免结构化推断。
 */
export const FORMULA_PLACEHOLDER_MAX_CHARS: number = 40;

const PLACEHOLDER_PADDING_VP: number = 16;
const PLACEHOLDER_CHAR_WIDTH: number = 0.62;
const OPEN_HEIGHT_FACTOR: number = 1.4;
const CLOSED_HEIGHT_FACTOR: number = 2.2;

export type PlaceholderPhase = 'open' | 'closed';

export interface PlaceholderMetrics {
  widthVp: number;
  heightVp: number;
}

export interface DrawSample {
  x: number;
  lineTop: number;
  lineBottom: number;
  baseline: number;
  lineHeight: number;
}

function cappedText(content: string): string {
  return content.length <= FORMULA_PLACEHOLDER_MAX_CHARS
    ? content
    : content.substring(0, FORMULA_PLACEHOLDER_MAX_CHARS);
}

function appendDistinct(values: number[], value: number): void {
  if (values.length === 0 || values[values.length - 1] !== value) {
    values.push(value);
  }
}

export function estimatePlaceholderWidthVp(content: string, fontSizeFp: number): number {
  const visibleChars: number = Math.min(content.length, FORMULA_PLACEHOLDER_MAX_CHARS);
  return PLACEHOLDER_PADDING_VP + visibleChars * fontSizeFp * PLACEHOLDER_CHAR_WIDTH;
}

export class InlineFormulaPlaceholderModel {
  private phase_: PlaceholderPhase = 'open';
  private content_: string = '';
  private truncated_: boolean = false;
  private readonly fontSizeFp_: number;
  private readonly openWidthVp_: number;
  private closedWidthVp_: number;
  private readonly openHeightVp_: number;
  private readonly closedHeightVp_: number;

  constructor(initialContent: string, fontSizeFp: number) {
    this.fontSizeFp_ = fontSizeFp;
    this.truncated_ = initialContent.length > FORMULA_PLACEHOLDER_MAX_CHARS;
    this.content_ = cappedText(initialContent);
    this.openWidthVp_ = estimatePlaceholderWidthVp(this.content_, this.fontSizeFp_);
    this.closedWidthVp_ = this.openWidthVp_;
    this.openHeightVp_ = this.fontSizeFp_ * OPEN_HEIGHT_FACTOR;
    this.closedHeightVp_ = this.fontSizeFp_ * CLOSED_HEIGHT_FACTOR;
  }

  appendDelta(delta: string): void {
    if (this.phase_ === 'closed') {
      return;
    }
    const merged: string = this.content_ + delta;
    if (merged.length > FORMULA_PLACEHOLDER_MAX_CHARS) {
      this.truncated_ = true;
    }
    this.content_ = cappedText(merged);
  }

  close(): void {
    if (this.phase_ === 'closed') {
      return;
    }
    this.phase_ = 'closed';
    this.closedWidthVp_ = estimatePlaceholderWidthVp(this.content_, this.fontSizeFp_);
  }

  measureMetrics(): PlaceholderMetrics {
    const metrics: PlaceholderMetrics = {
      widthVp: this.phase_ === 'open' ? this.openWidthVp_ : this.closedWidthVp_,
      heightVp: this.phase_ === 'open' ? this.openHeightVp_ : this.closedHeightVp_,
    };
    return metrics;
  }

  displayText(): string {
    return this.truncated_ ? this.content_ + '…' : this.content_;
  }

  phase(): PlaceholderPhase {
    return this.phase_;
  }

  isClosed(): boolean {
    return this.phase_ === 'closed';
  }

  contentLength(): number {
    return this.content_.length;
  }
}

export class CustomSpanVerificationReport {
  private measureCount_: number = 0;
  private drawCount_: number = 0;
  private invalidateCount_: number = 0;
  private areaChangeCount_: number = 0;
  private lastMetrics_: PlaceholderMetrics = { widthVp: 0, heightVp: 0 };
  private lastDrawSample_: DrawSample = { x: 0, lineTop: 0, lineBottom: 0, baseline: 0, lineHeight: 0 };
  private lastAreaHeightVp_: number = 0;
  private lastAreaDeltaVp_: number = 0;
  private openWidths_: number[] = [];
  private closedWidths_: number[] = [];

  recordMeasure(metrics: PlaceholderMetrics, phase: PlaceholderPhase): void {
    this.measureCount_ += 1;
    this.lastMetrics_ = { widthVp: metrics.widthVp, heightVp: metrics.heightVp };
    if (phase === 'open') {
      appendDistinct(this.openWidths_, metrics.widthVp);
    } else {
      appendDistinct(this.closedWidths_, metrics.widthVp);
    }
  }

  recordDraw(sample: DrawSample): void {
    this.drawCount_ += 1;
    this.lastDrawSample_ = {
      x: sample.x,
      lineTop: sample.lineTop,
      lineBottom: sample.lineBottom,
      baseline: sample.baseline,
      lineHeight: sample.lineBottom - sample.lineTop,
    };
  }

  recordInvalidate(): void {
    this.invalidateCount_ += 1;
  }

  recordAreaChange(heightVp: number, deltaVp: number): void {
    this.areaChangeCount_ += 1;
    this.lastAreaHeightVp_ = heightVp;
    this.lastAreaDeltaVp_ = deltaVp;
  }

  measureCount(): number {
    return this.measureCount_;
  }

  drawCount(): number {
    return this.drawCount_;
  }

  invalidateCount(): number {
    return this.invalidateCount_;
  }

  areaChangeCount(): number {
    return this.areaChangeCount_;
  }

  lastMetrics(): PlaceholderMetrics {
    return this.lastMetrics_;
  }

  lastDrawSample(): DrawSample {
    return this.lastDrawSample_;
  }

  lastAreaHeightVp(): number {
    return this.lastAreaHeightVp_;
  }

  lastAreaDeltaVp(): number {
    return this.lastAreaDeltaVp_;
  }

  openWidthStable(): boolean {
    return this.openWidths_.length === 1;
  }

  closedWidthRecorded(): boolean {
    return this.closedWidths_.length >= 1;
  }

  widthUpdatedOnClose(): boolean {
    return this.openWidths_.length >= 1 && this.closedWidths_.length >= 1
      && this.openWidths_[0] !== this.closedWidths_[0];
  }
}
