export type LatexRiskLevel = 'none' | 'fixable' | 'fallback';
export type LatexRenderMode = 'native' | 'katex' | 'plainFallback';
export type LatexSegmentKind = 'text' | 'inlineMath' | 'displayMath' | 'fallbackText';

export interface RenderSegment {
  kind: LatexSegmentKind;
  source: string;
  normalized: string;
  safeToRender: boolean;
}

export interface LatexRiskResult {
  rawText: string;
  normalizedText: string;
  riskLevel: LatexRiskLevel;
  issues: string[];
  fixes: string[];
  renderMode: LatexRenderMode;
  segments: RenderSegment[];
}

export class LatexRiskNormalizer {
  normalize(rawText: string): LatexRiskResult {
    const raw: string = rawText;
    const issues: string[] = [];
    const fixes: string[] = [];
    const normalizedLines: string[] = [];
    const lines: string[] = raw.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
    let inCode: boolean = false;
    let inDisplay: boolean = false;
    let displayFence: string = '';

    for (const line of lines) {
      const trimmed: string = line.trim();
      if (trimmed.indexOf('```') === 0) {
        inCode = !inCode;
        normalizedLines.push(line);
        continue;
      }
      if (inCode) {
        normalizedLines.push(line);
        continue;
      }
      if (inDisplay) {
        const isClose: boolean = displayFence === '$$' && trimmed === '$$'
          || displayFence === '\\[' && trimmed === '\\]';
        if (isClose) {
          normalizedLines.push(line);
          inDisplay = false;
          displayFence = '';
        } else {
          const cleaned: string = this.removeNestedDollars(line, issues, fixes);
          normalizedLines.push(this.normalizeDifferentialDx(cleaned, issues, fixes));
        }
        continue;
      }
      if (trimmed === '$$' || trimmed === '\\[') {
        normalizedLines.push(line);
        inDisplay = true;
        displayFence = trimmed;
        continue;
      }
      normalizedLines.push(this.normalizeLine(line, issues, fixes));
    }

    const normalized: string = normalizedLines.join('\n').trim();
    this.detectFallbackRisk(normalized, issues);
    const hasFormula: boolean = this.hasFormulaSignal(normalized);
    const fallback: boolean = this.hasIssue(issues, 'unclosed_brace')
      || this.hasIssue(issues, 'unclosed_display_delimiter')
      || this.hasIssue(issues, 'unclosed_inline_delimiter')
      || this.hasIssue(issues, 'unknown_command');
    const riskLevel: LatexRiskLevel = fallback ? 'fallback' : (fixes.length > 0 ? 'fixable' : 'none');
    const renderMode: LatexRenderMode = fallback ? 'plainFallback' : (hasFormula ? 'katex' : 'native');
    return {
      rawText: raw,
      normalizedText: normalized,
      riskLevel: riskLevel,
      issues: this.unique(issues),
      fixes: this.unique(fixes),
      renderMode: renderMode,
      segments: this.buildSegments(raw, normalized, renderMode),
    };
  }

  private normalizeLine(line: string, issues: string[], fixes: string[]): string {
    let result: string = line;
    const trimmed: string = line.trim();
    if (trimmed.length === 0) {
      return line;
    }
    if (this.isDisplayWrapped(trimmed)) {
      const inner: string = trimmed.substring(2, trimmed.length - 2).trim();
      const cleaned: string = this.removeNestedDollars(inner, issues, fixes);
      const dxFixed: string = this.normalizeDifferentialDx(cleaned, issues, fixes);
      return '$$' + dxFixed + '$$';
    }
    if (this.looksLikeBareDisplayFormula(trimmed)) {
      issues.push('bare_display_formula');
      fixes.push('wrap_display_delimiter');
      const cleaned: string = this.normalizeDifferentialDx(
        this.removeNestedDollars(trimmed, issues, fixes),
        issues,
        fixes,
      );
      return '$$' + cleaned + '$$';
    }
    result = this.wrapBareShortSymbols(result, issues, fixes);
    return result;
  }

  private isDisplayWrapped(text: string): boolean {
    return text.indexOf('$$') === 0 && text.lastIndexOf('$$') === text.length - 2 && text.length > 4;
  }

  private looksLikeBareDisplayFormula(text: string): boolean {
    // 1. 行首即 LaTeX 命令 → 裸展示公式, 即使行内嵌有 $...$ 片段 (如 \int ... ($n \neq -1$))
    if (text.indexOf('\\int') === 0
      || text.indexOf('\\sum') === 0
      || text.indexOf('\\lim') === 0
      || text.indexOf('\\frac') === 0
      || text.indexOf('\\sqrt') === 0
      || text.indexOf('\\begin') === 0) {
      return true;
    }
    // 2. 行首是文本且含成对行内 $ → 公式已定界, 不是裸展示
    //    (旧守卫只查 $$ / $ 开头, 曾把 '文本 $\Phi...\frac...$' 误判损坏成 $$...$$)
    const first: number = this.nextUnescapedDollar(text, 0);
    if (first >= 0) {
      const second: number = this.nextUnescapedDollar(text, first + 1);
      if (second >= 0) {
        return false;
      }
      if (first === 0) {
        return false;
      }
    }
    // 3. 无 $ 定界的 'f(x)=\frac...' 形态 → 裸展示
    return text.indexOf('=') >= 0 && (
      text.indexOf('\\frac') >= 0 ||
      text.indexOf('\\sqrt') >= 0 ||
      text.indexOf('\\int') >= 0 ||
      text.indexOf('\\sum') >= 0 ||
      text.indexOf('\\lim') >= 0 ||
      text.indexOf('\\begin') >= 0
    );
  }
  private removeNestedDollars(text: string, issues: string[], fixes: string[]): string {
    if (text.indexOf('$') < 0) {
      return text;
    }
    issues.push('nested_dollar_in_display');
    fixes.push('remove_nested_dollar');
    return text.split('$').join('');
  }

  private normalizeDifferentialDx(text: string, issues: string[], fixes: string[]): string {
    let result: string = text;
    const beforeComma: string = result;
    result = result.replace(/(^|[^\\]),\s*d([a-zA-Z])/g, '$1\\,d$2');
    if (result !== beforeComma) {
      issues.push('loose_differential');
      fixes.push('normalize_differential_dx');
    }
    const beforeSpace: string = result;
    result = result.replace(/([^\\,])\s+d([xyztruv])(\s|$)/g, '$1\\,d$2$3');
    if (result !== beforeSpace) {
      issues.push('loose_differential');
      fixes.push('normalize_differential_dx');
    }
    return result;
  }

  private wrapBareShortSymbols(text: string, issues: string[], fixes: string[]): string {
    if (text.indexOf('\\(') >= 0 || text.indexOf('\\[') >= 0) {
      return text;
    }
    let result: string = '';
    let cursor: number = 0;
    let openIndex: number = this.nextUnescapedDollar(text, cursor);
    while (openIndex >= 0) {
      const closeIndex: number = this.nextUnescapedDollar(text, openIndex + 1);
      if (closeIndex < 0) {
        return result + this.wrapBareCommands(text.substring(cursor), issues, fixes);
      }
      result += this.wrapBareCommands(text.substring(cursor, openIndex), issues, fixes);
      result += text.substring(openIndex, closeIndex + 1);
      cursor = closeIndex + 1;
      openIndex = this.nextUnescapedDollar(text, cursor);
    }
    return result + this.wrapBareCommands(text.substring(cursor), issues, fixes);
  }

  private wrapBareCommands(text: string, issues: string[], fixes: string[]): string {
    const commands: string[] = ['\\mu', '\\sigma', '\\theta', '\\alpha', '\\beta'];
    let result: string = text;
    for (const command of commands) {
      if (result.indexOf(command) >= 0) {
        result = result.split(command).join('$' + command + '$');
        issues.push('bare_inline_symbol');
        fixes.push('wrap_inline_symbol');
      }
    }
    return result;
  }

  private nextUnescapedDollar(text: string, start: number): number {
    let index: number = text.indexOf('$', start);
    while (index >= 0) {
      if (!this.isEscapedAt(text, index)) {
        return index;
      }
      index = text.indexOf('$', index + 1);
    }
    return -1;
  }

  private detectFallbackRisk(text: string, issues: string[]): void {
    const lines: string[] = text.split('\n');
    const displayLines: string[] = [];
    let inCode: boolean = false;
    let inDisplay: boolean = false;
    let displayFence: string = '';
    for (const line of lines) {
      const trimmed: string = line.trim();
      if (trimmed.indexOf('```') === 0) {
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        continue;
      }
      if (inDisplay) {
        const isClose: boolean = displayFence === '$$' && trimmed === '$$'
          || displayFence === '\\[' && trimmed === '\\]';
        if (isClose) {
          this.detectFormulaBodyRisk(displayLines.join('\n'), issues);
          displayLines.splice(0, displayLines.length);
          inDisplay = false;
          displayFence = '';
        } else {
          displayLines.push(line);
        }
        continue;
      }
      if (trimmed === '$$' || trimmed === '\\[') {
        inDisplay = true;
        displayFence = trimmed;
        continue;
      }
      if (this.isDisplayWrapped(trimmed)) {
        this.detectFormulaBodyRisk(trimmed.substring(2, trimmed.length - 2), issues);
        continue;
      }
      this.detectInlineRisk(line, issues);
    }
    if (inDisplay) {
      issues.push('unclosed_display_delimiter');
    }
  }

  private detectInlineRisk(line: string, issues: string[]): void {
    let cursor: number = 0;
    let openIndex: number = line.indexOf('$', cursor);
    while (openIndex >= 0) {
      const closeIndex: number = line.indexOf('$', openIndex + 1);
      if (closeIndex < 0) {
        issues.push('unclosed_inline_delimiter');
        return;
      }
      this.detectFormulaBodyRisk(line.substring(openIndex + 1, closeIndex), issues);
      cursor = closeIndex + 1;
      openIndex = line.indexOf('$', cursor);
    }
    const compatOpen: number = line.indexOf('\\(');
    if (compatOpen >= 0) {
      const compatClose: number = line.indexOf('\\)', compatOpen + 2);
      if (compatClose < 0) {
        issues.push('unclosed_inline_delimiter');
      } else {
        this.detectFormulaBodyRisk(line.substring(compatOpen + 2, compatClose), issues);
      }
    }
  }

  private detectFormulaBodyRisk(body: string, issues: string[]): void {
    let braceDepth: number = 0;
    let index: number = 0;
    while (index < body.length) {
      const char: string = body.charAt(index);
      if (char === '{' && !this.isEscapedAt(body, index)) {
        braceDepth += 1;
      } else if (char === '}' && !this.isEscapedAt(body, index)) {
        braceDepth -= 1;
        if (braceDepth < 0) {
          issues.push('unclosed_brace');
          braceDepth = 0;
        }
      }
      index += 1;
    }
    if (braceDepth !== 0) {
      issues.push('unclosed_brace');
    }
    if (body.indexOf('\\unknown') >= 0) {
      issues.push('unknown_command');
    }
  }

  private isEscapedAt(text: string, index: number): boolean {
    let slashCount: number = 0;
    let slashIndex: number = index - 1;
    while (slashIndex >= 0 && text.charAt(slashIndex) === '\\') {
      slashCount += 1;
      slashIndex -= 1;
    }
    return slashCount % 2 !== 0;
  }

  private hasFormulaSignal(text: string): boolean {
    let inCode: boolean = false;
    for (const line of text.split('\n')) {
      const trimmed: string = line.trim();
      if (trimmed.indexOf('```') === 0) {
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        continue;
      }
      if (line.indexOf('$') >= 0
        || line.indexOf('\\frac') >= 0
        || line.indexOf('\\sqrt') >= 0
        || line.indexOf('\\int') >= 0
        || line.indexOf('\\sum') >= 0
        || line.indexOf('\\lim') >= 0
        || line.indexOf('\\begin') >= 0) {
        return true;
      }
    }
    return false;
  }

  private buildSegments(raw: string, normalized: string, renderMode: LatexRenderMode): RenderSegment[] {
    const safe: boolean = renderMode !== 'plainFallback';
    const kind: LatexSegmentKind = renderMode === 'katex'
      ? 'displayMath'
      : (renderMode === 'plainFallback' ? 'fallbackText' : 'text');
    return [{
      kind: kind,
      source: raw,
      normalized: normalized,
      safeToRender: safe,
    }];
  }

  private hasIssue(issues: string[], issue: string): boolean {
    return issues.indexOf(issue) >= 0;
  }

  private unique(values: string[]): string[] {
    const result: string[] = [];
    for (const value of values) {
      if (result.indexOf(value) < 0) {
        result.push(value);
      }
    }
    return result;
  }
}
