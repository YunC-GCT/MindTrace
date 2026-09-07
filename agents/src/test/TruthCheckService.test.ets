/**
 * TruthCheckService.test.ets — spec 015 PR1: 真值检查服务实体化后的服务级测试。
 * 覆盖 4 项检查 (括号配对 / 除零 / 方程 / LaTeX) + truthCheck 聚合行为。
 */

import { describe, it, expect } from '@ohos/hypium';
import { TruthCheckService } from '../main/ets/agents/TruthCheckService';
import { MvpTruthCheckResult } from '../main/ets/models/TruthCheckResult';

function createService(): TruthCheckService {
  return new TruthCheckService();
}

export default function truthCheckServiceTest(): void {
  describe('TruthCheckService.truth_check_test', () => {
    it('checkBracePairing_valid_latex_passes', 0, () => {
      const s: TruthCheckService = createService();
      const r = s.checkBracePairing('\\frac{1}{2}');
      expect(r.valid).assertTrue();
    });

    it('checkBracePairing_missing_brace_is_patched', 0, () => {
      const s: TruthCheckService = createService();
      const r = s.checkBracePairing('\\frac{1}{2');
      expect(r.correctedText).assertEqual('\\frac{1}{2}');
    });

    it('checkDivisionByZero_detects_slash_zero', 0, () => {
      const s: TruthCheckService = createService();
      const r = s.checkDivisionByZero('1/0');
      expect(r.hasIssue).assertTrue();
    });

    it('checkEquation_detects_contradiction', 0, () => {
      const s: TruthCheckService = createService();
      const r = s.checkEquation('1=0');
      expect(r.hasIssue).assertTrue();
    });

    it('checkLatexInternal_autofixes_fract', 0, () => {
      const s: TruthCheckService = createService();
      const r = s.checkLatexInternal('\\fract{1}{2}');
      expect(r.correctedBody).assertEqual('\\frac{1}{2}');
      expect(r.hasError).assertTrue();
    });

    it('truthCheck_empty_text_fails', 0, () => {
      const s: TruthCheckService = createService();
      const r: MvpTruthCheckResult = s.check('');
      expect(r.truthFlag).assertFalse();
    });

    it('truthCheck_returns_four_details', 0, () => {
      const s: TruthCheckService = createService();
      const r: MvpTruthCheckResult = s.check('a+b=c');
      expect(r.details.length).assertEqual(4);
    });
  });
}
