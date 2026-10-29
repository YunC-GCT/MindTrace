/**
 * problemSegmenter.ets — 单页 OCR 文本按题号锚点切分为题目段。
 *
 * 路径: agents/src/main/ets/graph/problemSegmenter.ets
 * 职责: 规则切题 + 原文回查自校验；规则命中不了就整页退化成一题，不做 LLM 兜底。
 * 依赖: 无（纯字符串函数，Node 侧 loader 可直接装载做契约测试）。
 *
 * 数据流:
 *   OCR item.text → segmentProblems() → SegmentResult → 阶段 2b 的跨图合并
 *
 * Why: 切题宁可粗不可错。任何一处对不上原文就整页退化成 1 题并显式标记，
 *      不允许出现「看起来切开了、实际丢了字符」的静默错误。
 *
 * 语义边界:
 *   - 锚点只认行首（允许空格 / 制表符前缀）；`（1）` 小题号不切主边界。
 *   - 无锚点 / 只有 1 个主锚点：整页一题，degraded=false（这是正常结果，不是切失败）。
 *   - 多锚点路径任一校验失败（原文回查、空段、题号非严格递增、段数 > 20）：
 *     整页一段，degraded=true 且 needsReview=true。
 *   - 段与段首尾相接，按序拼接必须等于入参 ocrText。
 *
 * ArkTS 1.1 strict 适配:
 *   - 正则集中为模块常量且不带 g 标志，exec 不会残留 lastIndex。
 *   - 所有变量、参数、返回值显式标注类型；对象字面量绑定 ProblemSegment / SegmentResult。
 *   - 只用下标 for，不用 for...of / 展开运算符 / Object.assign。
 */

export interface ProblemSegment {
  index: number;        // 页内序号，0 起
  anchor: string;       // 命中的题号原文（如 '1.' / '第3题'）；退化整页时为 ''
  rawText: string;      // 原样切片，必须能在入参 indexOf 命中
  needsReview: boolean; // 切题不确定时为 true
}

export interface SegmentResult {
  segments: ProblemSegment[];
  degraded: boolean;    // true = 整页退化成 1 题
}

// 主锚点：阿拉伯题号 / 中文题号。括号小题号刻意不在这里匹配。
// 逐行 exec，行内没有 \n，所以这里的 \s* 不会跨行。
// 尾部 (?!\d)：避开教材小节号「1.5 函数的连续性」这种小数，别把章节当题号。
const ARABIC_ANCHOR: RegExp = /^\s*(\d{1,2})\s*[.、)）](?!\d)/;
const CHINESE_ANCHOR: RegExp = /^\s*第\s*([一二三四五六七八九十百\d]+)\s*题/;

const CN_NUMERAL_CHARS: string = '零一二三四五六七八九';
// 阶段 2 的硬上限：超过 20 段宁可整页退化，也不让确认页被切碎。
const MAX_SEGMENTS: number = 20;

interface AnchorHit {
  start: number;   // 锚点所在行首在 ocrText 中的下标
  anchor: string;  // 命中原文（去首尾空白）
  number: number;  // 归一化题号，用于严格递增校验；-1 = 无法解析
}

// 中文数字只处理 1–20：一…十、十一…十九、二十；其余一律 -1（触发退化）。
function parseChineseNumber(raw: string): number {
  let value: number = -1;
  if (raw === '十') {
    value = 10;
  } else if (raw.length === 1) {
    value = CN_NUMERAL_CHARS.indexOf(raw);
  } else if (raw.length === 2) {
    const first: string = raw.substring(0, 1);
    const second: string = raw.substring(1, 2);
    if (first === '十') {
      const unit: number = CN_NUMERAL_CHARS.indexOf(second);
      value = unit >= 1 ? 10 + unit : -1;
    } else if (second === '十') {
      const tens: number = CN_NUMERAL_CHARS.indexOf(first);
      value = tens >= 1 ? tens * 10 : -1;
    }
  }
  if (value < 1 || value > 20) {
    return -1;
  }
  return value;
}

function isAsciiDigits(raw: string): boolean {
  if (raw.length === 0) {
    return false;
  }
  for (let i: number = 0; i < raw.length; i += 1) {
    const code: number = raw.charCodeAt(i);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

function parseAnchorNumber(raw: string): number {
  if (!isAsciiDigits(raw)) {
    return parseChineseNumber(raw);
  }
  let value: number = 0;
  for (let i: number = 0; i < raw.length; i += 1) {
    value = value * 10 + (raw.charCodeAt(i) - 48);
  }
  return value;
}

function matchAnchorLine(line: string, lineStart: number): AnchorHit | null {
  const arabic: RegExpExecArray | null = ARABIC_ANCHOR.exec(line);
  if (arabic !== null) {
    const hit: AnchorHit = {
      start: lineStart,
      anchor: arabic[0].trim(),
      number: parseAnchorNumber(arabic[1]),
    };
    return hit;
  }
  const chinese: RegExpExecArray | null = CHINESE_ANCHOR.exec(line);
  if (chinese !== null) {
    const hit: AnchorHit = {
      start: lineStart,
      anchor: chinese[0].trim(),
      number: parseAnchorNumber(chinese[1]),
    };
    return hit;
  }
  return null;
}

function collectAnchors(text: string): AnchorHit[] {
  const anchors: AnchorHit[] = [];
  let lineStart: number = 0;
  while (lineStart <= text.length) {
    let lineEnd: number = text.indexOf('\n', lineStart);
    if (lineEnd < 0) {
      lineEnd = text.length;
    }
    const line: string = text.substring(lineStart, lineEnd);
    const hit: AnchorHit | null = matchAnchorLine(line, lineStart);
    if (hit !== null) {
      anchors.push(hit);
    }
    if (lineEnd >= text.length) {
      break;
    }
    lineStart = lineEnd + 1;
  }
  return anchors;
}

function buildAnchoredSegments(text: string, anchors: AnchorHit[]): ProblemSegment[] {
  const segments: ProblemSegment[] = [];
  const prefix: string = text.substring(0, anchors[0].start);
  // 首个锚点前的非空正文是试卷标题 / 说明，单独作为 index 0；
  // 若只有空白，则让第一段从 0 开始，保证不丢字符。
  if (prefix.trim().length > 0) {
    const preamble: ProblemSegment = {
      index: 0,
      anchor: '',
      rawText: prefix,
      needsReview: false,
    };
    segments.push(preamble);
  }
  for (let i: number = 0; i < anchors.length; i += 1) {
    let start: number = anchors[i].start;
    if (i === 0 && segments.length === 0) {
      start = 0;
    }
    let end: number = text.length;
    if (i + 1 < anchors.length) {
      end = anchors[i + 1].start;
    }
    const segment: ProblemSegment = {
      index: segments.length,
      anchor: anchors[i].anchor,
      rawText: text.substring(start, end),
      needsReview: false,
    };
    segments.push(segment);
  }
  return segments;
}

// 逐段回查原文 + 空段检查 + 拼接连续性，一次完成。
function isReconstructable(ocrText: string, segments: ProblemSegment[]): boolean {
  let rebuilt: string = '';
  for (let i: number = 0; i < segments.length; i += 1) {
    const raw: string = segments[i].rawText;
    if (raw.trim().length === 0) {
      return false;
    }
    if (ocrText.indexOf(raw) < 0) {
      return false;
    }
    rebuilt += raw;
  }
  return rebuilt === ocrText;
}

function isStrictlyIncreasing(anchors: AnchorHit[]): boolean {
  let previous: number = -1;
  for (let i: number = 0; i < anchors.length; i += 1) {
    if (anchors[i].number <= previous) {
      return false;
    }
    previous = anchors[i].number;
  }
  return true;
}

function singleSegment(ocrText: string, degraded: boolean): SegmentResult {
  const segment: ProblemSegment = {
    index: 0,
    anchor: '',
    rawText: ocrText,
    needsReview: degraded,
  };
  const result: SegmentResult = {
    segments: [segment],
    degraded: degraded,
  };
  return result;
}

export function segmentProblems(ocrText: string): SegmentResult {
  if (ocrText.trim().length === 0) {
    const empty: SegmentResult = {
      segments: [],
      degraded: false,
    };
    return empty;
  }
  const anchors: AnchorHit[] = collectAnchors(ocrText);
  if (anchors.length < 2) {
    return singleSegment(ocrText, false);
  }
  const segments: ProblemSegment[] = buildAnchoredSegments(ocrText, anchors);
  if (!isReconstructable(ocrText, segments)
    || !isStrictlyIncreasing(anchors)
    || segments.length > MAX_SEGMENTS) {
    return singleSegment(ocrText, true);
  }
  const result: SegmentResult = {
    segments: segments,
    degraded: false,
  };
  return result;
}
