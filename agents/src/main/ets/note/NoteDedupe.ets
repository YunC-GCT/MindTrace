/**
 * NoteDedupe.ets — 笔记重复判定（纯函数，无 IO）
 *
 * 路径: agents/src/main/ets/note/NoteDedupe.ets
 * 职责: 同一道题被重复拍照/重复发送时，判断是否与已有笔记重复，避免「重复整理」。
 *       判定只用归一化文本相似度，不依赖 LLM；写入口（KnowledgeUnitWriteService）调用。
 * 依赖: 无（纯字符串函数，便于 Node 契约测试）。
 *
 * 阈值（经样本校准，宁可漏判也不误杀）：
 *   - 标题归一后完全相同且长度 ≥4 → 重复；
 *   - 标题相似 ≥0.92 且 正文相似 ≥0.75 → 重复；
 *   - 正文相似 ≥0.92 → 重复。
 */
export interface DedupeCandidate {
  id: string;
  title: string;
  content: string;
}

const MIN_TITLE_CHARS: number = 4;
const TITLE_EXACT_CONTENT_MIN: number = 0.75;
const TITLE_SIMILAR_MIN: number = 0.92;
const CONTENT_DUP_MIN: number = 0.92;

/** 归一：小写 + 去掉空白/标点/markdown 记号，只留字母数字与中文。 */
export function normalizeForDedupe(text: string): string {
  let out: string = '';
  const lower: string = text.toLowerCase();
  for (let i = 0; i < lower.length; i += 1) {
    const ch: string = lower.charAt(i);
    const code: number = lower.charCodeAt(i);
    const isDigit: boolean = code >= 48 && code <= 57;
    const isLower: boolean = code >= 97 && code <= 122;
    const isCjk: boolean = code >= 0x4e00 && code <= 0x9fff;
    if (isDigit || isLower || isCjk) {
      out += ch;
    }
  }
  return out;
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

/** 判断「新笔记」是否与一条候选重复。 */
export function isDuplicateOf(title: string, content: string, candidate: DedupeCandidate): boolean {
  const titleNorm: string = normalizeForDedupe(title);
  const candidateTitle: string = normalizeForDedupe(candidate.title);
  const titleSimilarity: number = bigramSimilarity(titleNorm, candidateTitle);
  const contentSimilarity: number = bigramSimilarity(
    normalizeForDedupe(content), normalizeForDedupe(candidate.content));
  if (titleNorm.length >= MIN_TITLE_CHARS && titleNorm === candidateTitle) {
    return contentSimilarity >= TITLE_EXACT_CONTENT_MIN;
  }
  if (titleSimilarity >= TITLE_SIMILAR_MIN && contentSimilarity >= TITLE_EXACT_CONTENT_MIN) {
    return true;
  }
  return contentSimilarity >= CONTENT_DUP_MIN;
}

/** 在候选列表中找第一条重复笔记；没有返回 null。 */
export function findDuplicate(title: string, content: string, candidates: DedupeCandidate[]): DedupeCandidate | null {
  for (let i = 0; i < candidates.length; i += 1) {
    if (isDuplicateOf(title, content, candidates[i])) {
      return candidates[i];
    }
  }
  return null;
}
