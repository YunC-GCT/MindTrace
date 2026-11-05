/**
 * NoteSearchRanking.ets — 检索打分与摘录的纯函数（无 Kit、无 IO）
 *
 * 路径: common/src/main/ets/ports/impl/NoteSearchRanking.ets
 * 职责: 把候选行按确定性权重打分、稳定排序、截断 TopK，并生成正文摘录；
 *       供 RdbNoteSearchAdapter 使用，也可被未来的向量实现复用（只换召回，不换排序口径）。
 * 依赖: ../NoteSearchPort（命中形状）；无 Kit、无数据库。
 *
 * 打分口径（与既有 note_query_rag 工具一致，切换实现不得改变输出）:
 *   score = titleHits×4 + tagHits×3 + summaryHits×2 + contentHits×1
 *   排序 = 分数降序 → updatedAt 降序 → noteId 升序
 *   摘录 = 命中位置前 60 字符起、取 160 字符；两端截断加省略号
 */

export const RAG_TITLE_WEIGHT: number = 4;
export const RAG_TAG_WEIGHT: number = 3;
export const RAG_SUMMARY_WEIGHT: number = 2;
export const RAG_DISTINCT_TERM_BONUS: number = 2;
export const RAG_TITLE_TOKEN_WEIGHT: number = 6;
export const RAG_TAG_TOKEN_WEIGHT: number = 4;
export const RAG_SUMMARY_TOKEN_WEIGHT: number = 3;
export const RAG_CONTENT_TOKEN_WEIGHT: number = 1;
export const RAG_COVERAGE_SCALE: number = 10;
export const RAG_MAX_QUERY_TOKENS: number = 24;
export const RAG_EXCERPT_LEAD: number = 60;
export const RAG_EXCERPT_LENGTH: number = 160;

// 检索候选：SQL 取回的原始行 + 打分工位。
export interface ScoredCandidate {
  noteId: string;
  title: string;
  version: number;
  subject: string;
  chapter: string;
  tags: string;
  summary: string;
  content: string;
  updatedAt: number;
  score: number;
  matchedFields: string[];
  excerpt: string;
}

// 非重叠子串计数；大小写由调用方先归一化。
export function countOccurrences(haystack: string, needle: string): number {
  if (needle.length === 0) {
    return 0;
  }
  let count: number = 0;
  let index: number = haystack.indexOf(needle);
  while (index >= 0) {
    count += 1;
    index = haystack.indexOf(needle, index + needle.length);
  }
  return count;
}

// 正文摘录：命中位置前后取窗口；无正文时退回摘要；两端截断显式加省略号。
export function buildExcerpt(content: string, summary: string, needle: string): string {
  const trimmedContent: string = content.trim();
  const source: string = trimmedContent.length > 0 ? content : summary;
  if (source.length === 0) {
    return '';
  }
  const hit: number = needle.length === 0 ? -1 : source.toLowerCase().indexOf(needle);
  let start: number = 0;
  if (hit > RAG_EXCERPT_LEAD) {
    start = hit - RAG_EXCERPT_LEAD;
  }
  let end: number = start + RAG_EXCERPT_LENGTH;
  if (end > source.length) {
    end = source.length;
  }
  let excerpt: string = source.substring(start, end).replace(/\s+/g, ' ').trim();
  if (start > 0) {
    excerpt = '…' + excerpt;
  }
  if (end < source.length) {
    excerpt = excerpt + '…';
  }
  return excerpt;
}

// 稳定排序：分数降序 → 更新时间降序 → noteId 升序。
export function compareHits(left: ScoredCandidate, right: ScoredCandidate): number {
  if (left.score !== right.score) {
    return right.score - left.score;
  }
  if (left.updatedAt !== right.updatedAt) {
    return right.updatedAt - left.updatedAt;
  }
  if (left.noteId < right.noteId) {
    return -1;
  }
  if (left.noteId > right.noteId) {
    return 1;
  }
  return 0;
}

// 打分 + 排序 + 截断；score<=0 的候选不返回（避免"没有命中"被当成命中）。
export function rankNoteHits(rows: ScoredCandidate[], needle: string, topK: number): ScoredCandidate[] {
  const scored: ScoredCandidate[] = [];
  for (const row of rows) {
    const titleHits: number = countOccurrences(row.title.toLowerCase(), needle);
    const tagHits: number = countOccurrences(row.tags.toLowerCase(), needle);
    const summaryHits: number = countOccurrences(row.summary.toLowerCase(), needle);
    const contentHits: number = countOccurrences(row.content.toLowerCase(), needle);
    const score: number = titleHits * RAG_TITLE_WEIGHT
      + tagHits * RAG_TAG_WEIGHT
      + summaryHits * RAG_SUMMARY_WEIGHT
      + contentHits;
    if (score <= 0) {
      continue;
    }
    row.score = score;
    const matched: string[] = [];
    if (titleHits > 0) {
      matched.push('title');
    }
    if (tagHits > 0) {
      matched.push('tags');
    }
    if (summaryHits > 0) {
      matched.push('summary');
    }
    if (contentHits > 0) {
      matched.push('content');
    }
    row.matchedFields = matched;
    row.excerpt = buildExcerpt(row.content, row.summary, needle);
    scored.push(row);
  }
  scored.sort((left: ScoredCandidate, right: ScoredCandidate): number => compareHits(left, right));
  const ranked: ScoredCandidate[] = [];
  for (let index = 0; index < scored.length && index < topK; index += 1) {
    ranked.push(scored[index]);
  }
  return ranked;
}

// 044 R3: 多词召回打分。单词权重与 rankNoteHits 一致，另加「命中词数」加成，
// 避免「计算」这类泛词把只命中一个词的长笔记顶过真正相关的多词命中。
// 2026-11-05 升级：按查询词覆盖度打分而不是词频——标题命中权重最高，
// 长笔记/旧笔记不会因为正文长而占优，也不会因为更新晚而挤掉真正相关的旧知。
export function rankNoteHitsByTerms(rows: ScoredCandidate[], terms: string[], topK: number): ScoredCandidate[] {
  const tokens: string[] = buildQueryTokens(terms);
  const scored: ScoredCandidate[] = [];
  for (const row of rows) {
    const title: string = row.title.toLowerCase();
    const tags: string = row.tags.toLowerCase();
    const summary: string = row.summary.toLowerCase();
    const content: string = row.content.toLowerCase();
    let titleMatched: number = 0;
    let tagMatched: number = 0;
    let summaryMatched: number = 0;
    let contentMatched: number = 0;
    let matchedDistinct: number = 0;
    let bestNeedle: string = '';
    for (let i = 0; i < tokens.length; i += 1) {
      const token: string = tokens[i];
      let hit: boolean = false;
      if (title.indexOf(token) >= 0) {
        titleMatched += 1;
        hit = true;
      }
      if (tags.indexOf(token) >= 0) {
        tagMatched += 1;
        hit = true;
      }
      if (summary.indexOf(token) >= 0) {
        summaryMatched += 1;
        hit = true;
      }
      if (content.indexOf(token) >= 0) {
        contentMatched += 1;
        hit = true;
      }
      if (hit) {
        matchedDistinct += 1;
        if (bestNeedle.length === 0 || token.length > bestNeedle.length) {
          bestNeedle = token;
        }
      }
    }
    if (matchedDistinct === 0) {
      continue;
    }
    const coverage: number = tokens.length === 0 ? 0 : matchedDistinct / tokens.length;
    row.score = titleMatched * RAG_TITLE_TOKEN_WEIGHT
      + tagMatched * RAG_TAG_TOKEN_WEIGHT
      + summaryMatched * RAG_SUMMARY_TOKEN_WEIGHT
      + contentMatched * RAG_CONTENT_TOKEN_WEIGHT
      + (matchedDistinct - 1) * RAG_DISTINCT_TERM_BONUS
      + Math.round(coverage * RAG_COVERAGE_SCALE);
    const matched: string[] = [];
    if (titleMatched > 0) {
      matched.push('title');
    }
    if (tagMatched > 0) {
      matched.push('tags');
    }
    if (summaryMatched > 0) {
      matched.push('summary');
    }
    if (contentMatched > 0) {
      matched.push('content');
    }
    row.matchedFields = matched;
    row.excerpt = buildExcerpt(row.content, row.summary, bestNeedle);
    scored.push(row);
  }
  scored.sort((left: ScoredCandidate, right: ScoredCandidate): number => compareHits(left, right));
  const ranked: ScoredCandidate[] = [];
  for (let index = 0; index < scored.length && index < topK; index += 1) {
    ranked.push(scored[index]);
  }
  return ranked;
}

/** 查询词 → 检索 token：中文长词补二元组（覆盖换序与「的」等结构差异），拉丁/公式整词保留。 */
export function buildQueryTokens(terms: string[]): string[] {
  const tokens: string[] = [];
  for (let i = 0; i < terms.length; i += 1) {
    const term: string = terms[i].trim().toLowerCase();
    if (term.length === 0) {
      continue;
    }
    addToken(tokens, term);
    if (isCjkOnly(term) && term.length > 2) {
      for (let k = 0; k + 1 < term.length; k += 1) {
        addToken(tokens, term.substring(k, k + 2));
      }
    }
  }
  return tokens.slice(0, RAG_MAX_QUERY_TOKENS);
}

function addToken(tokens: string[], token: string): void {
  if (token.length > 0 && tokens.indexOf(token) < 0 && tokens.length < RAG_MAX_QUERY_TOKENS) {
    tokens.push(token);
  }
}

function isCjkOnly(text: string): boolean {
  for (let i = 0; i < text.length; i += 1) {
    const code: number = text.charCodeAt(i);
    if (code < 0x4e00 || code > 0x9fff) {
      return false;
    }
  }
  return true;
}
