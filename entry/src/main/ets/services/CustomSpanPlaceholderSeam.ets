/**
 * CustomSpanPlaceholderSeam.ets — 行内公式占位 CustomSpan seam(ticket-0.5, #123)
 *
 * 路径: entry/src/main/ets/services/CustomSpanPlaceholderSeam.ets
 * 职责: 验证行内公式占位符所需的 CustomSpan seam —— 初始宽度估算、open 阶段宽度稳定、
 *       close 阶段 invalidate 驱动的单次宽度/高度更新、draw 回调样本记录。
 * 数据流: delta/close 输入 → InlineFormulaPlaceholderModel(纯状态机) → InlineFormulaPlaceholderSpan
 *         (CustomSpan 适配器: onMeasure/onDraw/invalidate) → CustomSpanVerificationReport(回调证据)
 * 依赖: @kit.ArkUI(CustomSpan 基类, ambient 声明); @kit.ArkGraphics2D(drawing/common2D, 仅占位绘制);
 *       @kit.PerformanceAnalysisKit(hilog, 回调证据)。
 * 边界: 不依赖 LaTeX 引擎,不导入 KaTeX/MathTextParser/ContentProtocol;ticket-2 之前不接入生产 chat 路径。
 *
 * 单位契约: CustomSpanMetrics 为 vp;CustomSpanDrawInfo 的 x/lineTop/lineBottom/baseline 为 px。
 *
 * ArkTS 1.1 strict 适配:
 *   - 类内分离: 纯模型/报告与 CustomSpan 适配器各自成类,模型不使用 ArkUI 运行时,可被 Hypium 直接测试。
 *   - 不使用 any/unknown、解构或内联对象类型;显式 typed object literal。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common2D, drawing } from '@kit.ArkGraphics2D';

const DOMAIN: number = 0xA001;
const LOG_TAG: string = 'CustomSpanSeam';

export const FORMULA_PLACEHOLDER_MAX_CHARS: number = 40;
const PLACEHOLDER_CHIP_PADDING_VP: number = 16;
const PLACEHOLDER_CHAR_WIDTH_FACTOR: number = 0.62;
const OPEN_HEIGHT_FACTOR: number = 1.4;
const CLOSED_HEIGHT_FACTOR: number = 2.2;
const ELLIPSIS: string = '…';

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

function capContent(content: string): string {
  if (content.length <= FORMULA_PLACEHOLDER_MAX_CHARS) {
    return content;
  }
  return content.substring(0, FORMULA_PLACEHOLDER_MAX_CHARS);
}

function appendDistinct(values: number[], next: number): void {
  if (values.length === 0) {
    values.push(next);
    return;
  }
  const lastIndex: number = values.length - 1;
  if (values[lastIndex] !== next) {
    values.push(next);
  }
}

/**
 * 纯宽度估算: 占位 chip 内边距 + 截断后的可见字符数 × fontSizeFp × 字符宽度系数。
 * 确定性、有界;open 阶段只调用一次,close 阶段用最终内容重算一次。
 */
export function estimatePlaceholderWidthVp(content: string, fontSizeFp: number): number {
  const visibleChars: number = Math.min(content.length, FORMULA_PLACEHOLDER_MAX_CHARS);
  return PLACEHOLDER_CHIP_PADDING_VP + visibleChars * fontSizeFp * PLACEHOLDER_CHAR_WIDTH_FACTOR;
}

/**
 * 纯占位状态机: open(宽度冻结) → closed(宽度单次重算)。
 * 不依赖 ArkUI 运行时,可被 Hypium 单元测试直接覆盖。
 */
export class InlineFormulaPlaceholderModel {
  private phase_: PlaceholderPhase = 'open';
  private content_: string = '';
  private truncated_: boolean = false;
  private fontSizeFp_: number = 16;
  private openWidthVp_: number = 0;
  private closedWidthVp_: number = 0;
  private openHeightVp_: number = 0;
  private closedHeightVp_: number = 0;

  constructor(initialContent: string, fontSizeFp: number) {
    this.fontSizeFp_ = fontSizeFp;
    this.truncated_ = initialContent.length > FORMULA_PLACEHOLDER_MAX_CHARS;
    this.content_ = capContent(initialContent);
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
    this.content_ = capContent(merged);
  }

  close(): void {
    if (this.phase_ === 'closed') {
      return;
    }
    this.phase_ = 'closed';
    this.closedWidthVp_ = estimatePlaceholderWidthVp(this.content_, this.fontSizeFp_);
  }

  measureMetrics(): PlaceholderMetrics {
    const widthVp: number = this.phase_ === 'open' ? this.openWidthVp_ : this.closedWidthVp_;
    const heightVp: number = this.phase_ === 'open' ? this.openHeightVp_ : this.closedHeightVp_;
    const metrics: PlaceholderMetrics = { widthVp: widthVp, heightVp: heightVp };
    return metrics;
  }

  displayText(): string {
    if (this.truncated_) {
      return this.content_ + ELLIPSIS;
    }
    return this.content_;
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

/**
 * 回调证据报告: measure/draw/invalidate/areaChange 计数 + 最后一次指标 + open/closed 去重宽度集合。
 * open 宽度稳定 = open 集合恰好一个值(至少观察到一次 open measure 且宽度未变);
 * close 更新 = closed 集合至少一个值且与 open 不同。
 * areaChange 记录 Text 级高度变化(vp),供后续 GeometryChanged 设计引用。
 */
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
    this.measureCount_++;
    this.lastMetrics_ = metrics;
    if (phase === 'open') {
      appendDistinct(this.openWidths_, metrics.widthVp);
    } else {
      appendDistinct(this.closedWidths_, metrics.widthVp);
    }
  }

  recordDraw(sample: DrawSample): void {
    this.drawCount_++;
    const recorded: DrawSample = {
      x: sample.x,
      lineTop: sample.lineTop,
      lineBottom: sample.lineBottom,
      baseline: sample.baseline,
      lineHeight: sample.lineBottom - sample.lineTop,
    };
    this.lastDrawSample_ = recorded;
  }

  recordInvalidate(): void {
    this.invalidateCount_++;
  }

  recordAreaChange(heightVp: number, deltaVp: number): void {
    this.areaChangeCount_++;
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
    return this.closedWidths_.length >= 1 && this.openWidths_.length >= 1 &&
      this.closedWidths_[0] !== this.openWidths_[0];
  }
}

/**
 * CustomSpan 适配器: 委托模型给出测量值,回调全部记录进报告并镜像 hilog。
 * 同一实例通过 invalidate() 驱动框架重测量/重绘制;不替换 Text 组件或属性字符串。
 */
export class InlineFormulaPlaceholderSpan extends CustomSpan {
  readonly model: InlineFormulaPlaceholderModel;
  readonly report: CustomSpanVerificationReport;
  private vp2px_: (vp: number) => number;

  constructor(model: InlineFormulaPlaceholderModel,
              report: CustomSpanVerificationReport,
              vp2px: (vp: number) => number) {
    super();
    this.model = model;
    this.report = report;
    this.vp2px_ = vp2px;
  }

  onMeasure(measureInfo: CustomSpanMeasureInfo): CustomSpanMetrics {
    const metrics: PlaceholderMetrics = this.model.measureMetrics();
    this.report.recordMeasure(metrics, this.model.phase());
    hilog.info(DOMAIN, LOG_TAG, 'measure widthVp=%{public}s heightVp=%{public}s phase=%{public}s fontSizeFp=%{public}s',
      metrics.widthVp.toFixed(2), metrics.heightVp.toFixed(2), this.model.phase(), measureInfo.fontSize.toFixed(2));
    const spanMetrics: CustomSpanMetrics = { width: metrics.widthVp, height: metrics.heightVp };
    return spanMetrics;
  }

  onDraw(context: DrawContext, drawInfo: CustomSpanDrawInfo): void {
    const sample: DrawSample = {
      x: drawInfo.x,
      lineTop: drawInfo.lineTop,
      lineBottom: drawInfo.lineBottom,
      baseline: drawInfo.baseline,
      lineHeight: 0,
    };
    this.report.recordDraw(sample);
    hilog.info(DOMAIN, LOG_TAG, 'draw x=%{public}d lineTop=%{public}d lineBottom=%{public}d baseline=%{public}d',
      drawInfo.x, drawInfo.lineTop, drawInfo.lineBottom, drawInfo.baseline);
    this.drawChip(context, drawInfo);
  }

  invalidate(): void {
    this.report.recordInvalidate();
    hilog.info(DOMAIN, LOG_TAG, 'invalidate total=%{public}d', this.report.invalidateCount());
    super.invalidate();
  }

  appendDelta(delta: string): void {
    this.model.appendDelta(delta);
  }

  close(): void {
    this.model.close();
  }

  private drawChip(context: DrawContext, drawInfo: CustomSpanDrawInfo): void {
    const metrics: PlaceholderMetrics = this.model.measureMetrics();
    const widthPx: number = this.vp2px_(metrics.widthVp);
    const canvas = context.canvas;
    const chipColor: common2D.Color = { alpha: 60, red: 128, green: 128, blue: 128 };
    const brush: drawing.Brush = new drawing.Brush();
    brush.setColor(chipColor);
    const rect: common2D.Rect = {
      left: drawInfo.x + 2,
      top: drawInfo.lineTop + 2,
      right: drawInfo.x + widthPx - 2,
      bottom: drawInfo.lineBottom - 2,
    };
    canvas.attachBrush(brush);
    canvas.drawRect(rect);
    canvas.detachBrush();
    const displayText: string = this.model.displayText();
    if (displayText.length > 0) {
      const font: drawing.Font = new drawing.Font();
      font.setSize(this.vp2px_(metrics.heightVp) * 0.45);
      const textBlob: drawing.TextBlob = drawing.TextBlob.makeFromString(displayText, font,
        drawing.TextEncoding.TEXT_ENCODING_UTF8);
      canvas.drawTextBlob(textBlob, drawInfo.x + 6, drawInfo.baseline - 2);
    }
  }
}
