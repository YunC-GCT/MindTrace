/**
 * problemMerger.ets — 同一 CaptureSet 内跨图题目合并与重拍去重。
 *
 * 路径: agents/src/main/ets/graph/problemMerger.ets
 * 职责: 对已按 (imageIndex, segmentIndex) 排好序的段做三档合并；灰区不猜，留给用户确认。
 * 依赖: ./problemSegmenter（同一份题号 / 原文契约，仅类型引用）。
 *
 * 数据流:
 *   problemSegmenter.SegmentResult（逐图扁平化）→ mergeProblems() → MergedProblem[]
 *
 * Why: 续页、同题号重识别、重拍去重都是确定性规则，能在端侧零成本解决；
 *      相似度落在 0.4–0.6 的灰区必须保留两条并标 NEEDS_REVIEW，
 *      宁可多一条让用户删，也不要把两道题揉成一条让用户拆。
 *
 * 合并顺序（对每一对「上一条累积结果 vs 当前段」）:
 *   1. 续页 → 2. 同题号强合并 → 3. fingerprint / 高相似度去重 → 4. 灰区 → 5. 独立。
 *
 * ArkTS 1.1 strict 适配:
 *   - 所有变量、参数、返回值显式标注类型；对象字面量绑定 SourceSegment / MergedProblem。
 *   - 只用下标 for，不用 for...of / 展开运算符 / Object.assign / 解构。
 *   - sources 每次写入都 copySource()，不共享调用方对象引用。
 */

import { ProblemSegment } from './problemSegmenter';

export interface SourceSegment {
  imageIndex: number;   // 来自第几张图，0 起
  segmentIndex: number; // 图内段序，0 起
  anchor: string;
  text: string;
  needsReview: boolean;
}

export interface MergedProblem {
  index: number;             // 合并后序号，0 起、连续
  text: string;
  sources: SourceSegment[];
  needsReview: boolean;
  fingerprint: string;       // normalizeForFingerprint(text)
}

// 常见中英文标点（fingerprint 只保留文字 / 数字）。
const PUNCTUATION_CHARS: string = '，。！？；：、,.!?;:()（）[]【】{}「」『』"\'“”‘’—…·《》〈〉<>/\\|~`@#$%^&*+_=-～';

// 与 segmenter 的主锚点同形；fingerprint 场景允许 \s* 吃掉行首空白 / 空行。
const CHINESE_ANCHOR_LINE: RegExp = /^\s*第\s*[一二三四五六七八九十百\d]+\s*题/gm;
const PAREN_ANCHOR_LINE: RegExp = /^\s*[（(]\s*\d{1,2}\s*[)）]/gm;
const ARABIC_ANCHOR_LINE: RegExp = /^\s*\d{1,2}\s*[.、)）]/gm;

function isWhitespaceChar(char: string): boolean {
  return char === ' '
    || char === '\t'
    || char === '\n'
    || char === '\r'
    || char === '\f'
    || char === '\v'
    || char === '\u3000';
}

function stripWhitespace(text: string): string {
  let output: string = '';
  for (let i: number = 0; i < text.length; i += 1) {
    const char: string = text.substring(i, i + 1);
    if (!isWhitespaceChar(char)) {
      output += char;
    }
  }
  return output;
}

// 字符二元组集合（去重后），供 Jaccard 使用。
function bigrams(text: string): string[] {
  const grams: string[] = [];
  for (let i: number = 0; i + 1 < text.length; i += 1) {
    const gram: string = text.substring(i, i + 2);
    if (grams.indexOf(gram) < 0) {
      grams.push(gram);
    }
  }
  return grams;
}

export function similarity(a: string, b: string): number {
  const left: string = stripWhitespace(a);
  const right: string = stripWhitespace(b);
  // 任一侧去空白后不足 2 字：退化为相等判断，不做二元组。
  if (left.length < 2 || right.length < 2) {
    return left === right ? 1 : 0;
  }
  const leftGrams: string[] = bigrams(left);
  const rightGrams: string[] = bigrams(right);
  let intersection: number = 0;
  for (let i: number = 0; i < leftGrams.length; i += 1) {
    if (rightGrams.indexOf(leftGrams[i]) >= 0) {
      intersection += 1;
    }
  }
  const union: number = leftGrams.length + rightGrams.length - intersection;
  if (union === 0) {
    return left === right ? 1 : 0;
  }
  return intersection / union;
}

// 只去掉行首题号锚点（含括号小题号），正文中的数字不动。
function stripAnchorMarkers(text: string): string {
  let output: string = text;
  output = output.replace(CHINESE_ANCHOR_LINE, '');
  output = output.replace(PAREN_ANCHOR_LINE, '');
  output = output.replace(ARABIC_ANCHOR_LINE, '');
  return output;
}

export function normalizeForFingerprint(text: string): string {
  const stripped: string = stripAnchorMarkers(text);
  let output: string = '';
  for (let i: number = 0; i < stripped.length; i += 1) {
    const char: string = stripped.substring(i, i + 1);
    if (isWhitespaceChar(char)) {
      continue;
    }
    if (PUNCTUATION_CHARS.indexOf(char) >= 0) {
      continue;
    }
    output += char;
  }
  return output.toLowerCase();
}

function copySource(source: SourceSegment): SourceSegment {
  const copy: SourceSegment = {
    imageIndex: source.imageIndex,
    segmentIndex: source.segmentIndex,
    anchor: source.anchor,
    text: source.text,
    needsReview: source.needsReview,
  };
  return copy;
}

function createMerged(index: number, source: SourceSegment, needsReview: boolean): MergedProblem {
  const sources: SourceSegment[] = [copySource(source)];
  const problem: MergedProblem = {
    index: index,
    text: source.text,
    sources: sources,
    needsReview: needsReview,
    fingerprint: normalizeForFingerprint(source.text),
  };
  return problem;
}

function lastSource(problem: MergedProblem): SourceSegment {
  return problem.sources[problem.sources.length - 1];
}

function endsWithTerminator(text: string): boolean {
  const tail: string = text.trim();
  if (tail.length === 0) {
    return false;
  }
  if (tail.endsWith('答：') || tail.endsWith('答:')) {
    return true;
  }
  const last: string = tail.substring(tail.length - 1);
  return last === '。'
    || last === '！'
    || last === '？'
    || last === '!'
    || last === '?'
    || last === '.';
}

// 续页：下一张图紧邻、本段没有题号、上一段正文没有终止符。
function isContinuation(problem: MergedProblem, current: SourceSegment): boolean {
  const last: SourceSegment = lastSource(problem);
  if (current.imageIndex !== last.imageIndex + 1) {
    return false;
  }
  if (current.anchor !== '') {
    return false;
  }
  return !endsWithTerminator(problem.text);
}

export function mergeProblems(inputs: SourceSegment[]): MergedProblem[] {
  const merged: MergedProblem[] = [];
  for (let i: number = 0; i < inputs.length; i += 1) {
    const current: SourceSegment = inputs[i];
    if (merged.length === 0) {
      merged.push(createMerged(0, current, current.needsReview));
      continue;
    }
    const previous: MergedProblem = merged[merged.length - 1];
    const previousAnchor: string = lastSource(previous).anchor;

    // 1. 续页：拼接正文 + 追加来源；任一侧需复核则结果需复核。
    if (isContinuation(previous, current)) {
      previous.text = previous.text + '\n' + current.text;
      previous.sources.push(copySource(current));
      previous.needsReview = previous.needsReview || current.needsReview;
      previous.fingerprint = normalizeForFingerprint(previous.text);
      continue;
    }

    const score: number = similarity(previous.text, current.text);

    // 2. 同题号强合并：长者为正文。
    if (current.anchor !== '' && current.anchor === previousAnchor && score >= 0.6) {
      previous.text = current.text.length > previous.text.length ? current.text : previous.text;
      previous.sources.push(copySource(current));
      previous.needsReview = previous.needsReview || current.needsReview;
      previous.fingerprint = normalizeForFingerprint(previous.text);
      continue;
    }

    // 3. 重拍 / 歪斜去重：归一化 fingerprint 相同，或相似度 >= 0.8。
    //    needsReview 保持上一条不变（本档不额外增加复核负担）。
    // 只有当两段题号一致（含都为空）时才允许「高相似度即视为重拍」；
    // 题号不同的两道题即便题干很像也是两道题，不能靠 0.8 静默吞掉一条。
    const currentFingerprint: string = normalizeForFingerprint(current.text);
    const sameAnchor: boolean = current.anchor === previousAnchor;
    if (previous.fingerprint === currentFingerprint || (sameAnchor && score >= 0.8)) {
      previous.text = current.text.length > previous.text.length ? current.text : previous.text;
      previous.sources.push(copySource(current));
      previous.fingerprint = normalizeForFingerprint(previous.text);
      continue;
    }

    // 4. 灰区：题号相同（含都为空）且相似度 0.4–0.6，不合并，两条都标复核。
    if (current.anchor === previousAnchor && score >= 0.4 && score < 0.6) {
      previous.needsReview = true;
      merged.push(createMerged(merged.length, current, true));
      continue;
    }

    // 5. 其余独立成条。
    merged.push(createMerged(merged.length, current, current.needsReview));
  }
  for (let i: number = 0; i < merged.length; i += 1) {
    merged[i].index = i;
  }
  return merged;
}
