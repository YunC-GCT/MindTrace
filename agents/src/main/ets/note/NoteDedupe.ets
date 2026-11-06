/**
 * NoteDedupe.ets — 笔记重复判定（纯函数，无 IO）
 *
 * 路径: agents/src/main/ets/note/NoteDedupe.ets
 * 职责: 同一道题被重复拍照/重复发送时，判断是否与已有笔记重复，避免「重复整理」。
 *       判定只用归一化文本相似度，不依赖 LLM；写入口（KnowledgeUnitWriteService）调用。
 * 依赖: 无（纯字符串函数，便于 Node 契约测试）。
 *
 * 阈值（经样本校准，宁可漏判也不误杀）：
 *   - 标题归一后完全相同且长度 ≥6 → 重复（重新生成正文措辞会变，不能靠正文相似度）；
 *   - 标题归一后完全相同且长度 ≥4 → 正文相似 ≥0.75 判重；
 *   - 标题相似 ≥0.92 且 正文相似 ≥0.75 → 重复；
 *   - 短标题被长标题完整包含（长度比 ≥0.75）且正文相似 ≥0.6 → 重复；
 *   - 数学签名相同（如「计算 21 加 21」与「两个 21 的和」都得到 add(21,21)）→ 重复；
 *   - 正文相似 ≥0.92 → 重复。
 */
import { extractMathSignature } from 'common';

export interface DedupeCandidate {
  id: string;
  title: string;
  content: string;
  /** 笔记类型（normal / atomic / summary）；缺省 normal。不同类型之间不判重。 */
  kind?: string;
}

const MIN_TITLE_CHARS: number = 4;
// 标题归一后达到该长度且完全相同，视为同一主题：重新生成会得到不同措辞的正文，
// 不能再用正文相似度兜底（实测同一道「计算 21 加 21」被整理出 4 条）。
const TITLE_TOPIC_MIN_CHARS: number = 6;
const TITLE_EXACT_CONTENT_MIN: number = 0.75;
const TITLE_SIMILAR_MIN: number = 0.92;
const CONTENT_DUP_MIN: number = 0.92;
const CONTAINMENT_MIN_RATIO: number = 0.75;
const CONTAINMENT_CONTENT_MIN: number = 0.6;
export const SIMILARITY_HARD_DUPLICATE: number = 0.9;
export const SIMILARITY_GRAY_MIN: number = 0.5;
// 结构助词/连词不携带主题信息，去掉后「泰勒公式的余项估计」与「泰勒公式余项估计」等价。
const STRUCTURAL_CHARS: string[] = ['的', '了', '与', '和', '及', '之', '其'];
const CN_NUMERAL_CHARS: string = '零一二三四五六七八九十百千';

/**
 * 归一：小写 + 去掉空白/标点/markdown 记号/结构助词 + 中文数字转阿拉伯数字。
 * 中文数字归一很重要：同一道「80 加 80」可能被整理成「八十加八十」。
 */
export function normalizeForDedupe(text: string): string {
  let out: string = '';
  const lower: string = text.toLowerCase();
  let numeralRun: string = '';
  for (let i = 0; i < lower.length; i += 1) {
    const ch: string = lower.charAt(i);
    const code: number = lower.charCodeAt(i);
    const isDigit: boolean = code >= 48 && code <= 57;
    const isLower: boolean = code >= 97 && code <= 122;
    const isCjk: boolean = code >= 0x4e00 && code <= 0x9fff;
    if (CN_NUMERAL_CHARS.indexOf(ch) >= 0) {
      numeralRun += ch;
      continue;
    }
    if (numeralRun.length > 0) {
      out += cnNumeralToArabic(numeralRun);
      numeralRun = '';
    }
    if ((isDigit || isLower || isCjk) && STRUCTURAL_CHARS.indexOf(ch) < 0) {
      out += ch;
    }
  }
  if (numeralRun.length > 0) {
    out += cnNumeralToArabic(numeralRun);
  }
  return out;
}

/** 中文数字段转阿拉伯数字：八十 → 80，二十一 → 21，一百零五 → 105。 */
export function cnNumeralToArabic(run: string): string {
  let section: number = 0;
  let number: number = 0;
  for (let i = 0; i < run.length; i += 1) {
    const ch: string = run.charAt(i);
    const digit: number = CN_NUMERAL_CHARS.indexOf(ch);
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

/** 字二元组 Jaccard 相似度；空串返回 0。 */
export function bigramSimilarity(left: string, right: string): number {
  if (left.length === 0 || right.length === 0) {
    return 0;
  }
  if (left === right) {
    return 1;
  }
  const leftSet: string[] = bigrams(left);
  const rightSet: string[] = bigrams(right);
  if (leftSet.length === 0 || rightSet.length === 0) {
    return left === right ? 1 : 0;
  }
  let inter: number = 0;
  for (let i = 0; i < leftSet.length; i += 1) {
    if (rightSet.indexOf(leftSet[i]) >= 0) {
      inter += 1;
    }
  }
  const union: number = leftSet.length + rightSet.length - inter;
  return union === 0 ? 0 : inter / union;
}

function bigrams(text: string): string[] {
  const list: string[] = [];
  for (let i = 0; i + 1 < text.length; i += 1) {
    list.push(text.substring(i, i + 2));
  }
  return list;
}

/** 二元组包含度：交集 / 较短集合大小，对长度差异比 Jaccard 更宽容。 */
export function bigramContainment(left: string, right: string): number {
  if (left.length === 0 || right.length === 0) {
    return 0;
  }
  const leftSet: string[] = bigrams(left);
  const rightSet: string[] = bigrams(right);
  let inter: number = 0;
  for (let i = 0; i < leftSet.length; i += 1) {
    if (rightSet.indexOf(leftSet[i]) >= 0) {
      inter += 1;
    }
  }
  const minSize: number = Math.min(leftSet.length, rightSet.length);
  return minSize === 0 ? 0 : inter / minSize;
}

function digitsOf(text: string): string {
  let digits: string = '';
  for (let i = 0; i < text.length; i += 1) {
    const code: number = text.charCodeAt(i);
    if (code >= 48 && code <= 57) {
      digits += text.charAt(i);
    }
  }
  return digits;
}

/** 判断「新笔记」是否与一条候选重复。 */
export function isDuplicateOf(title: string, content: string, candidate: DedupeCandidate,
  kind: string = 'normal'): boolean {
  // 原子笔记与汇总笔记允许同标题共存，类型不同直接不判重。
  const candidateKind: string = candidate.kind === undefined ? 'normal' : candidate.kind;
  if (candidateKind !== kind) {
    return false;
  }
  const titleNorm: string = normalizeForDedupe(title);
  const candidateTitle: string = normalizeForDedupe(candidate.title);
  const titleSimilarity: number = bigramSimilarity(titleNorm, candidateTitle);
  const contentSimilarity: number = bigramSimilarity(
    normalizeForDedupe(content), normalizeForDedupe(candidate.content));
  if (titleNorm.length >= TITLE_TOPIC_MIN_CHARS && titleNorm === candidateTitle) {
    return true;
  }
  if (titleNorm.length >= MIN_TITLE_CHARS && titleNorm === candidateTitle) {
    return contentSimilarity >= TITLE_EXACT_CONTENT_MIN;
  }
  if (titleSimilarity >= TITLE_SIMILAR_MIN && contentSimilarity >= TITLE_EXACT_CONTENT_MIN) {
    return true;
  }
  // 主题包含：较短标题被完整包含且长度接近，正文也有实质重合，视为同一主题的重复整理。
  if (titleNorm.length >= MIN_TITLE_CHARS && candidateTitle.length >= MIN_TITLE_CHARS) {
    const shorter: string = titleNorm.length <= candidateTitle.length ? titleNorm : candidateTitle;
    const longer: string = titleNorm.length <= candidateTitle.length ? candidateTitle : titleNorm;
    const ratio: number = shorter.length / longer.length;
    if (ratio >= CONTAINMENT_MIN_RATIO && longer.indexOf(shorter) >= 0
      && contentSimilarity >= CONTAINMENT_CONTENT_MIN) {
      return true;
    }
  }
  // 数学签名：同一道题换一种说法（「计算 21 加 21」vs「两个 21 的和」）。
  // 只看标题：正文里出现的算式可能只是题组里的一个例子，用正文签名会跨题误杀。
  const signature: string = extractMathSignature(title);
  if (signature.length > 0 && signature === extractMathSignature(candidate.title)) {
    return true;
  }
  // 数学签名（数字序列）：标题里的数字序列相同（如 80 加 80 vs 八十加八十）。
  const digits: string = digitsOf(titleNorm);
  if (digits.length >= 2 && digits === digitsOf(candidateTitle)
    && (bigramContainment(titleNorm, candidateTitle) >= 0.5
      || contentSimilarity >= 0.5)) {
    return true;
  }
  return contentSimilarity >= CONTENT_DUP_MIN;
}

/** 在候选列表中找第一条重复笔记；没有返回 null。 */
export function findDuplicate(title: string, content: string, candidates: DedupeCandidate[],
  kind: string = 'normal'): DedupeCandidate | null {
  for (let i = 0; i < candidates.length; i += 1) {
    if (isDuplicateOf(title, content, candidates[i], kind)) {
      return candidates[i];
    }
  }
  return null;
}

/**
 * 连续相似度（0..1），供灰区仲裁使用：
 * 确定性规则命中的给高分，其余按标题相似度 / 包含度 / 正文相似度加权。
 */
export function similarityScore(title: string, content: string,
  candidateTitle: string, candidateContent: string): number {
  const titleNorm: string = normalizeForDedupe(title);
  const candidateNorm: string = normalizeForDedupe(candidateTitle);
  if (titleNorm.length > 0 && titleNorm === candidateNorm) {
    return 1;
  }
  if (titleNorm.length >= MIN_TITLE_CHARS) {
    const signature: string = extractMathSignature(title);
    if (signature.length > 0 && signature === extractMathSignature(candidateTitle)) {
      return 0.95;
    }
    const digits: string = digitsOf(titleNorm);
    if (digits.length >= 2 && digits === digitsOf(candidateNorm)) {
      return 0.9;
    }
  }
  const titleSimilarity: number = bigramSimilarity(titleNorm, candidateNorm);
  const containment: number = bigramContainment(titleNorm, candidateNorm);
  const contentSimilarity: number = bigramSimilarity(
    normalizeForDedupe(content), normalizeForDedupe(candidateContent));
  return 0.45 * titleSimilarity + 0.2 * containment + 0.35 * contentSimilarity;
}
