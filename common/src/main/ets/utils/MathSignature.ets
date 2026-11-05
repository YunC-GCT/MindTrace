/**
 * MathSignature.ets — 数学题面签名提取（纯函数，无 IO）
 *
 * 路径: common/src/main/ets/utils/MathSignature.ets
 * 职责: 把一道数学题归一成可比较的签名，例如「计算 21 加 21」与「两个 21 的和」
 *       都得到 add(21,21)。用于笔记去重与检索加权，补足通用词面相似度抓不住
 *       「同一道题换一种说法」的问题。
 * 依赖: 无。
 */
const CN_DIGITS: string = '零一二三四五六七八九十百千';

/** 中文数字段转阿拉伯数字：八十 → 80，二十一 → 21，一百零五 → 105。 */
export function cnNumeralToArabic(run: string): string {
  let section: number = 0;
  let number: number = 0;
  for (let i = 0; i < run.length; i += 1) {
    const ch: string = run.charAt(i);
    const digit: number = CN_DIGITS.indexOf(ch);
    if (digit >= 0 && digit <= 9) {
      number = digit;
    } else if (ch === '十') {
      section += (number === 0 ? 1 : number) * 10;
      number = 0;
    } else if (ch === '百') {
      section += (number === 0 ? 1 : number) * 100;
      number = 0;
    } else if (ch === '千') {
      section += (number === 0 ? 1 : number) * 1000;
      number = 0;
    }
  }
  return (section + number).toString();
}

/** 中文数字段整体替换为阿拉伯数字，并统一全角符号。 */
export function normalizeMathText(text: string): string {
  const lower: string = text.toLowerCase();
  let out: string = '';
  let numeralRun: string = '';
  for (let i = 0; i < lower.length; i += 1) {
    const ch: string = lower.charAt(i);
    if (CN_DIGITS.indexOf(ch) >= 0) {
      numeralRun += ch;
      continue;
    }
    if (numeralRun.length > 0) {
      out += cnNumeralToArabic(numeralRun);
      numeralRun = '';
    }
    if (ch === '×' || ch === '＊') {
      out += '*';
    } else if (ch === '÷' || ch === '／') {
      out += '/';
    } else if (ch === '－' || ch === '—') {
      out += '-';
    } else if (ch === '＋') {
      out += '+';
    } else if (ch === '＝') {
      out += '=';
    } else if (ch !== ' ' && ch !== '\n' && ch !== '\t') {
      out += ch;
    }
  }
  if (numeralRun.length > 0) {
    out += cnNumeralToArabic(numeralRun);
  }
  return out;
}

/**
 * 提取算式签名。返回空串表示没有可识别的算式。
 * 只覆盖常见表述，宁可少匹配也不误判。
 */
export function extractMathSignature(text: string): string {
  const normalized: string = normalizeMathText(text);
  const phrase: string = extractPhraseSignature(normalized);
  if (phrase.length > 0) {
    return phrase;
  }
  const expression: string = extractExpressionSignature(normalized);
  return expression;
}

function extractPhraseSignature(text: string): string {
  const twoSum: RegExpMatchArray | null = text.match(/两个(\d+)的和/);
  if (twoSum !== null) {
    return 'add(' + twoSum[1] + ',' + twoSum[1] + ')';
  }
  const twoProduct: RegExpMatchArray | null = text.match(/两个(\d+)的积/);
  if (twoProduct !== null) {
    return 'mul(' + twoProduct[1] + ',' + twoProduct[1] + ')';
  }
  const sum: RegExpMatchArray | null = text.match(/(\d+)加(\d+)/);
  if (sum !== null) {
    return 'add(' + sum[1] + ',' + sum[2] + ')';
  }
  const diff: RegExpMatchArray | null = text.match(/(\d+)减(\d+)/);
  if (diff !== null) {
    return 'sub(' + diff[1] + ',' + diff[2] + ')';
  }
  const product: RegExpMatchArray | null = text.match(/(\d+)乘(\d+)/);
  if (product !== null) {
    return 'mul(' + product[1] + ',' + product[2] + ')';
  }
  const quotient: RegExpMatchArray | null = text.match(/(\d+)除以(\d+)/);
  if (quotient !== null) {
    return 'div(' + quotient[1] + ',' + quotient[2] + ')';
  }
  const square: RegExpMatchArray | null = text.match(/(\d+)的平方/);
  if (square !== null) {
    return 'sq(' + square[1] + ')';
  }
  return '';
}

/** 含运算符的阿拉伯算式：按运算符切分并递归构建，保持优先级结构。 */
function extractExpressionSignature(text: string): string {
  const match: RegExpMatchArray | null = text.match(/(\d+(?:[+\-*/]\d+)+)/);
  if (match === null) {
    return '';
  }
  const expression: string = match[1];
  // 简单优先级：先 * /，再 + -；同级左结合。
  let tokens: string[] = splitExpression(expression);
  if (tokens.length < 3) {
    return '';
  }
  tokens = foldOperators(tokens, ['*', '/']);
  tokens = foldOperators(tokens, ['+', '-']);
  return tokens.length === 1 ? tokens[0] : '';
}

function splitExpression(expression: string): string[] {
  const tokens: string[] = [];
  let current: string = '';
  for (let i = 0; i < expression.length; i += 1) {
    const ch: string = expression.charAt(i);
    if (ch === '+' || ch === '-' || ch === '*' || ch === '/') {
      if (current.length > 0) {
        tokens.push(current);
        current = '';
      }
      tokens.push(ch);
    } else {
      current += ch;
    }
  }
  if (current.length > 0) {
    tokens.push(current);
  }
  return tokens;
}

function foldOperators(tokens: string[], operators: string[]): string[] {
  let current: string[] = tokens.slice(0);
  let index: number = 1;
  while (index < current.length - 1) {
    const op: string = current[index];
    if (operators.indexOf(op) >= 0) {
      const left: string = current[index - 1];
      const right: string = current[index + 1];
      const folded: string = opName(op) + '(' + left + ',' + right + ')';
      const next: string[] = [];
      for (let i = 0; i < index - 1; i += 1) {
        next.push(current[i]);
      }
      next.push(folded);
      for (let i = index + 2; i < current.length; i += 1) {
        next.push(current[i]);
      }
      current = next;
      index = 1;
      continue;
    }
    index += 2;
  }
  return current;
}

function opName(op: string): string {
  if (op === '+') {
    return 'add';
  }
  if (op === '-') {
    return 'sub';
  }
  if (op === '*') {
    return 'mul';
  }
  return 'div';
}
