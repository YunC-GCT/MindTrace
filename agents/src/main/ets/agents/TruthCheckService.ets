// MindTrace - TruthCheckService
// 2026-09-05 · D2 Ticket #3 · 真值检查服务
// spec 015 PR1 (2026-09-06): 真值检查实现自 KnowledgeModel 实体化搬入 (纯提取, 行为零变化);
// 现由 CaptureGraph TruthCheckNode 作为唯一 workflow 步骤调用。
import { MvpTruthCheckItem, MvpTruthCheckResult } from '../models/TruthCheckResult';

// truthCheck internal interfaces (moved from KnowledgeModel.ets, spec 015 PR1)
interface BracePairingResult {
  valid: boolean;
  errors: string[];
  correctedText: string;
}

interface LatexCheckDetail {
  hasError: boolean;
  issues: string[];
  correctedBody: string;
}

interface DivisionByZeroCheck {
  hasIssue: boolean;
  issues: string[];
}

interface EquationCheckResult {
  hasIssue: boolean;
  issues: string[];
}

export class TruthCheckService {
  // CaptureGraph TruthCheckNode 调用面 (保持不变)
  check(input: string): MvpTruthCheckResult {
    return this.truthCheck(input);
  }

  /**
   * 本地保守校验：括号/LaTeX 语法和独立表达式的明显错误。
   * 带上下文的推导、反证和错误示例由独立 verifier 判断，不能靠子串断定真伪。
   *
   * @param ocrText - 输入文本
   * @returns MvpTruthCheckResult（检验结果 + 自动修正）
   */
  truthCheck(ocrText: string): MvpTruthCheckResult {
    if (!ocrText || ocrText.trim().length === 0) {
      const emptyItem: MvpTruthCheckItem = {
        checkName: 'emptyInput',
        passed: false,
        issues: ['input text is empty'],
      };
      return {
        truthFlag: false,
        details: [emptyItem],
        correctedText: undefined,
      };
    }

    const details: MvpTruthCheckItem[] = [];
    let corrected: string = ocrText;
    let allPassed: boolean = true;

    const braceResult: BracePairingResult = this.checkBracePairing(corrected);
    const braceItem: MvpTruthCheckItem = {
      checkName: 'bracketPair',
      passed: braceResult.valid,
      issues: braceResult.errors,
    };
    details.push(braceItem);
    if (!braceResult.valid) {
      allPassed = false;
      corrected = braceResult.correctedText;
    }

    const divByZero: DivisionByZeroCheck = this.checkDivisionByZero(corrected);
    const divItem: MvpTruthCheckItem = {
      checkName: 'divisionByZero',
      passed: !divByZero.hasIssue,
      issues: divByZero.issues,
    };
    details.push(divItem);
    if (divByZero.hasIssue) {
      allPassed = false;
    }

    const eqResult: EquationCheckResult = this.checkEquation(corrected);
    const eqItem: MvpTruthCheckItem = {
      checkName: 'equationCheck',
      passed: !eqResult.hasIssue,
      issues: eqResult.issues,
    };
    details.push(eqItem);
    if (eqResult.hasIssue) {
      allPassed = false;
    }

    const latexDetail: LatexCheckDetail = this.checkLatexInternal(corrected);
    const latexItem: MvpTruthCheckItem = {
      checkName: 'latexSyntax',
      passed: !latexDetail.hasError,
      issues: latexDetail.issues,
    };
    details.push(latexItem);
    if (latexDetail.hasError) {
      allPassed = false;
    }
    if (latexDetail.correctedBody !== corrected) {
      corrected = latexDetail.correctedBody;
    }

    return {
      truthFlag: allPassed,
      details: details,
      correctedText: corrected !== ocrText ? corrected : undefined,
    };
  }

  checkBracePairing(text: string): BracePairingResult {
    const errors: string[] = [];
    let braceDepth: number = 0;
    let result: string = '';
    let idx: number = 0;

    while (idx < text.length) {
      const ch: string = text[idx];
      if (ch === '\\' && idx + 1 < text.length) {
        result += ch + text[idx + 1];
        idx += 2;
        continue;
      }
      if (ch === '{') {
        braceDepth = braceDepth + 1;
        result = result + ch;
      } else if (ch === '}') {
        braceDepth = braceDepth - 1;
        if (braceDepth < 0) {
          errors.push('extra closing brace at position ' + String(idx));
          braceDepth = 0;
        } else {
          result = result + ch;
        }
      } else {
        result = result + ch;
      }
      idx = idx + 1;
    }

    if (braceDepth > 0) {
      errors.push('missing closing brace count: ' + String(braceDepth));
      let fillCount: number = 0;
      while (fillCount < braceDepth) {
        result = result + '}';
        fillCount = fillCount + 1;
      }
    }

    return {
      valid: errors.length === 0,
      errors: errors,
      correctedText: result,
    };
  }

  checkDivisionByZero(text: string): DivisionByZeroCheck {
    const issues: string[] = [];
    const expression: string = this.standaloneExpression(text);
    if (/^[+-]?\d+(?:\.\d+)?\s*\/\s*[+-]?0(?:\.0+)?$/.test(expression)) {
      issues.push('division by zero in standalone expression: ' + expression);
    }
    return {
      hasIssue: issues.length > 0,
      issues: issues,
    };
  }
  checkEquation(text: string): EquationCheckResult {
    const issues: string[] = [];
    const expression: string = this.standaloneExpression(text).replace(/\s+/g, '');
    const contradictions: string[] = ['1=0', '0=1', '2=1', '1=2', '0=2', '2=0'];
    for (const contradiction of contradictions) {
      if (expression === contradiction) {
        issues.push('contradictory equation: ' + contradiction);
      }
    }
    return {
      hasIssue: issues.length > 0,
      issues: issues,
    };
  }
  checkLatexInternal(body: string): LatexCheckDetail {
    const issues: string[] = [];
    let corrected: string = body;

    const braceResult: BracePairingResult = this.checkBracePairing(corrected);
    if (!braceResult.valid) {
      for (const error of braceResult.errors) {
        issues.push(error);
      }
      corrected = braceResult.correctedText;
    }

    const leftCount: number = this.countOccurrences(corrected, '\\left');
    const rightCount: number = this.countOccurrences(corrected, '\\right');
    if (leftCount !== rightCount) {
      issues.push('\\left and \\right count mismatch: ' + String(leftCount) + ':' + String(rightCount));
    }

    const latexFixes: string[][] = [
      ['\\fract{', '\\frac{'],
      ['\\sqt{', '\\sqrt{'],
    ];
    for (const fix of latexFixes) {
      const before: string = corrected;
      const target: string = fix[0];
      const replacement: string = fix[1];
      if (corrected.indexOf(target) !== -1) {
        corrected = corrected.split(target).join(replacement);
        if (corrected !== before) {
          issues.push('auto fixed: ' + target + ' -> ' + replacement);
        }
      }
    }

    // 不猜测积分变量或补写 dx；微元与公式的语义正确性由 verifier 校验。

    return {
      hasError: issues.length > 0,
      issues: issues,
      correctedBody: corrected,
    };
  }
  // === Utility methods ===

  private standaloneExpression(text: string): string {
    return text.trim().replace(/^\${1,2}|\${1,2}$/g, '').trim();
  }

  private countOccurrences(text: string, pattern: string): number {
    let count: number = 0;
    let pos: number = text.indexOf(pattern);
    while (pos !== -1) {
      // 匹配完整命令，不能把 \rightarrow / \leftarrow 当成定界符。
      const next: string = text.charAt(pos + pattern.length);
      if (!/[a-zA-Z]/.test(next)) {
        count = count + 1;
      }
      pos = text.indexOf(pattern, pos + 1);
    }
    return count;
  }

}
