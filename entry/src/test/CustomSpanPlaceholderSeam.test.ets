/**
 * CustomSpanPlaceholderSeam.test.ets — #123 CustomSpan formula placeholder seam gate
 *
 * 路径: entry/src/test/CustomSpanPlaceholderSeam.test.ets
 * 职责: 验证行内公式占位 CustomSpan seam 的宽度估算、open 阶段宽度稳定、close 阶段单次重算、
 *       显示截断、回调报告计数与 gate 三态语义。纯模型/报告级断言,不实例化 CustomSpan,
 *       不依赖 LaTeX 引擎;on-device measure/draw/invalidate 由临时 harness 页证明。
 * 依赖: @ohos/hypium; main/ets/services/CustomSpanPlaceholderSeam(纯模型 + 报告 + gate 语义)
 * 数据流: 模型输入 → InlineFormulaPlaceholderModel / CustomSpanVerificationReport → Hypium 断言
 *
 * ArkTS 1.1 strict 适配:
 *   - 不使用 any/unknown、解构或内联对象字面量;显式 typed object literal 经 helper 构造。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  FORMULA_PLACEHOLDER_MAX_CHARS,
  estimatePlaceholderWidthVp,
  InlineFormulaPlaceholderModel,
  CustomSpanVerificationReport,
  PlaceholderMetrics,
  DrawSample,
} from '../main/ets/services/CustomSpanPlaceholderSeam';

const TEST_FONT_SIZE_FP: number = 16;

type CustomSpanGateStatus = 'PASS' | 'FAIL' | 'INCOMPLETE';

interface CustomSpanGateSemantics {
  status: CustomSpanGateStatus;
  renderingContractReleased: boolean;
  downstreamBlocked: boolean;
  requiredText: string;
}

function customSpanGateSemantics(status: CustomSpanGateStatus): CustomSpanGateSemantics {
  if (status === 'PASS') {
    const semantics: CustomSpanGateSemantics = {
      status: status,
      renderingContractReleased: true,
      downstreamBlocked: false,
      requiredText: 'three-state rendering contract released for downstream design consideration only',
    };
    return semantics;
  }
  if (status === 'FAIL') {
    const semantics: CustomSpanGateSemantics = {
      status: status,
      renderingContractReleased: false,
      downstreamBlocked: false,
      requiredText: 'return to rendering contract redesign; never finish-only',
    };
    return semantics;
  }
  const semantics: CustomSpanGateSemantics = {
    status: status,
    renderingContractReleased: false,
    downstreamBlocked: true,
    requiredText: 'rendering contract blocked; missing evidence recorded as blocked tasks',
  };
  return semantics;
}

function metricsOf(widthVp: number, heightVp: number): PlaceholderMetrics {
  const metrics: PlaceholderMetrics = { widthVp: widthVp, heightVp: heightVp };
  return metrics;
}

function sampleOf(x: number, lineTop: number, lineBottom: number, baseline: number): DrawSample {
  const sample: DrawSample = { x: x, lineTop: lineTop, lineBottom: lineBottom, baseline: baseline, lineHeight: 0 };
  return sample;
}

function repeatChar(ch: string, count: number): string {
  let result: string = '';
  let remaining: number = count;
  while (remaining > 0) {
    result += ch;
    remaining--;
  }
  return result;
}

export default function customSpanPlaceholderSeamTest(): void {
  describe('CustomSpanPlaceholderSeam.issue123_width_estimate', () => {
    it('should return the minimum chip width for empty content', 0, () => {
      expect(estimatePlaceholderWidthVp('', TEST_FONT_SIZE_FP)).assertEqual(16);
    });

    it('should grow monotonically with content length', 0, () => {
      const shortWidth: number = estimatePlaceholderWidthVp('abc', TEST_FONT_SIZE_FP);
      const longWidth: number = estimatePlaceholderWidthVp('abcdefgh', TEST_FONT_SIZE_FP);
      expect(longWidth > shortWidth).assertTrue();
    });

    it('should freeze FORMULA_PLACEHOLDER_MAX_CHARS at 40', 0, () => {
      expect(FORMULA_PLACEHOLDER_MAX_CHARS).assertEqual(40);
    });

    it('should cap width growth at FORMULA_PLACEHOLDER_MAX_CHARS', 0, () => {
      const atCapWidth: number = estimatePlaceholderWidthVp(repeatChar('x', FORMULA_PLACEHOLDER_MAX_CHARS), TEST_FONT_SIZE_FP);
      const overCapWidth: number =
        estimatePlaceholderWidthVp(repeatChar('x', FORMULA_PLACEHOLDER_MAX_CHARS + 20), TEST_FONT_SIZE_FP);
      expect(atCapWidth).assertEqual(overCapWidth);
    });
  });

  describe('CustomSpanPlaceholderSeam.issue123_open_width_stability', () => {
    it('should freeze the measured width across appended deltas', 0, () => {
      const model: InlineFormulaPlaceholderModel = new InlineFormulaPlaceholderModel('\\frac{a}{b}', TEST_FONT_SIZE_FP);
      const firstWidth: number = model.measureMetrics().widthVp;
      model.appendDelta('+c');
      model.appendDelta('+d');
      model.appendDelta('+e');
      expect(model.measureMetrics().widthVp).assertEqual(firstWidth);
      expect(model.measureMetrics().widthVp > 0).assertTrue();
    });

    it('should keep the phase open while deltas arrive', 0, () => {
      const model: InlineFormulaPlaceholderModel = new InlineFormulaPlaceholderModel('x', TEST_FONT_SIZE_FP);
      model.appendDelta('y');
      expect(model.phase()).assertEqual('open');
      expect(model.isClosed()).assertFalse();
    });
  });

  describe('CustomSpanPlaceholderSeam.issue123_close_transition', () => {
    it('should recompute the width exactly once on close', 0, () => {
      const model: InlineFormulaPlaceholderModel = new InlineFormulaPlaceholderModel('\\alpha', TEST_FONT_SIZE_FP);
      const openWidth: number = model.measureMetrics().widthVp;
      model.appendDelta('\\beta\\gamma\\delta');
      model.close();
      const closedWidth: number = model.measureMetrics().widthVp;
      expect(model.phase()).assertEqual('closed');
      expect(closedWidth > openWidth).assertTrue();
      expect(closedWidth).assertEqual(estimatePlaceholderWidthVp('\\alpha\\beta\\gamma\\delta', TEST_FONT_SIZE_FP));
    });

    it('should be idempotent on repeated close', 0, () => {
      const model: InlineFormulaPlaceholderModel = new InlineFormulaPlaceholderModel('a', TEST_FONT_SIZE_FP);
      model.close();
      const firstWidth: number = model.measureMetrics().widthVp;
      model.close();
      expect(model.measureMetrics().widthVp).assertEqual(firstWidth);
    });

    it('should expose a taller closed height than open height', 0, () => {
      const model: InlineFormulaPlaceholderModel = new InlineFormulaPlaceholderModel('a', TEST_FONT_SIZE_FP);
      const openHeight: number = model.measureMetrics().heightVp;
      model.close();
      expect(model.measureMetrics().heightVp > openHeight).assertTrue();
    });
  });

  describe('CustomSpanPlaceholderSeam.issue123_display_truncation', () => {
    it('should truncate over-cap content with an ellipsis', 0, () => {
      const model: InlineFormulaPlaceholderModel = new InlineFormulaPlaceholderModel('', TEST_FONT_SIZE_FP);
      model.appendDelta(repeatChar('x', FORMULA_PLACEHOLDER_MAX_CHARS + 10));
      const text: string = model.displayText();
      expect(text.length).assertEqual(FORMULA_PLACEHOLDER_MAX_CHARS + 1);
      expect(text.endsWith('…')).assertTrue();
    });

    it('should not add an ellipsis when content is within the cap', 0, () => {
      const model: InlineFormulaPlaceholderModel = new InlineFormulaPlaceholderModel('abc', TEST_FONT_SIZE_FP);
      expect(model.displayText()).assertEqual('abc');
    });
  });

  describe('CustomSpanPlaceholderSeam.issue123_report_counters', () => {
    it('should count measures, draws, and invalidations', 0, () => {
      const report: CustomSpanVerificationReport = new CustomSpanVerificationReport();
      const openMetrics: PlaceholderMetrics = metricsOf(100, 22);
      report.recordMeasure(openMetrics, 'open');
      report.recordMeasure(openMetrics, 'open');
      report.recordDraw(sampleOf(10, 4, 26, 20));
      report.recordInvalidate();
      expect(report.measureCount()).assertEqual(2);
      expect(report.drawCount()).assertEqual(1);
      expect(report.invalidateCount()).assertEqual(1);
      expect(report.lastMetrics().widthVp).assertEqual(100);
    });

    it('should derive line height from draw offsets', 0, () => {
      const report: CustomSpanVerificationReport = new CustomSpanVerificationReport();
      report.recordDraw(sampleOf(10, 4, 26, 20));
      const last: DrawSample = report.lastDrawSample();
      expect(last.lineHeight).assertEqual(22);
      expect(last.x).assertEqual(10);
    });

    it('should keep a single distinct open width across repeated open measures', 0, () => {
      const report: CustomSpanVerificationReport = new CustomSpanVerificationReport();
      report.recordMeasure(metricsOf(100, 22), 'open');
      report.recordMeasure(metricsOf(100, 22), 'open');
      report.recordMeasure(metricsOf(100, 22), 'open');
      expect(report.openWidthStable()).assertTrue();
      expect(report.closedWidthRecorded()).assertFalse();
      expect(report.widthUpdatedOnClose()).assertFalse();
    });

    it('should not report open width stability without any open measure', 0, () => {
      const report: CustomSpanVerificationReport = new CustomSpanVerificationReport();
      expect(report.openWidthStable()).assertFalse();
      expect(report.closedWidthRecorded()).assertFalse();
    });

    it('should record the close width update as a single new width', 0, () => {
      const report: CustomSpanVerificationReport = new CustomSpanVerificationReport();
      report.recordMeasure(metricsOf(100, 22), 'open');
      report.recordMeasure(metricsOf(100, 22), 'open');
      report.recordMeasure(metricsOf(140, 35), 'closed');
      expect(report.openWidthStable()).assertTrue();
      expect(report.closedWidthRecorded()).assertTrue();
      expect(report.widthUpdatedOnClose()).assertTrue();
    });

    it('should record area height changes with the signed delta', 0, () => {
      const report: CustomSpanVerificationReport = new CustomSpanVerificationReport();
      report.recordAreaChange(36.5, 36.5);
      report.recordAreaChange(49.0, 12.5);
      expect(report.areaChangeCount()).assertEqual(2);
      expect(report.lastAreaHeightVp()).assertEqual(49.0);
      expect(report.lastAreaDeltaVp()).assertEqual(12.5);
    });
  });

  describe('CustomSpanPlaceholderSeam.issue123_gate_status_template', () => {
    it('should encode PASS semantics without switching production chat', 0, () => {
      const semantics: CustomSpanGateSemantics = customSpanGateSemantics('PASS');
      expect(semantics.status).assertEqual('PASS');
      expect(semantics.renderingContractReleased).assertTrue();
      expect(semantics.downstreamBlocked).assertFalse();
      expect(semantics.requiredText).assertContain('downstream design consideration only');
    });

    it('should encode FAIL semantics with contract redesign, never finish-only', 0, () => {
      const semantics: CustomSpanGateSemantics = customSpanGateSemantics('FAIL');
      expect(semantics.status).assertEqual('FAIL');
      expect(semantics.renderingContractReleased).assertFalse();
      expect(semantics.downstreamBlocked).assertFalse();
      expect(semantics.requiredText).assertContain('redesign');
      expect(semantics.requiredText).assertContain('never finish-only');
    });

    it('should encode INCOMPLETE semantics as blocked without release', 0, () => {
      const semantics: CustomSpanGateSemantics = customSpanGateSemantics('INCOMPLETE');
      expect(semantics.status).assertEqual('INCOMPLETE');
      expect(semantics.renderingContractReleased).assertFalse();
      expect(semantics.downstreamBlocked).assertTrue();
      expect(semantics.requiredText).assertContain('blocked');
    });
  });
}
