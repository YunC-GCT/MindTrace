/**
 * RagQueryPlan.ets — RAG 检索查询规划（纯函数，无 IO）
 *
 * 路径: entry/src/main/ets/services/RagQueryPlan.ets
 * 职责: 依据查询长度选执行策略：≥3 字走 FTS5 trigram MATCH（BM25 排序）；<3 字 trigram 无法命中，
 *       退化为 LIKE 子串扫描（笔记量小，可接受）。
 *       另提供词 OR 兜底计划（044 R2）：整句未命中时，用拆分出的关键词做多词召回。
 * 依赖: 无（纯函数，便于 Node 侧契约测试）。
 */
export interface RagQueryPlan {
  mode: string;
  sql: string;
}

export interface RagTermQueryPlan {
  mode: string;
  sql: string;
  /** 依次绑定到 SQL 占位符；最后一个固定是 topK。 */
  bindValues: Array<string | number>;
}

const FTS_SQL: string =
  'SELECT unit_id, title, content, subject, chapter FROM note_fts '
  + 'WHERE note_fts MATCH ? ORDER BY rank LIMIT ?';
const LIKE_SQL: string =
  'SELECT unit_id, title, content, subject, chapter FROM note_fts '
  + 'WHERE content LIKE ? OR title LIKE ? LIMIT ?';
const FTS_TERM_SQL: string =
  'SELECT unit_id, title, content, subject, chapter FROM note_fts '
  + 'WHERE note_fts MATCH ? ORDER BY rank LIMIT ?';

export function planRagQuery(query: string): RagQueryPlan {
  const trimmed: string = query.trim();
  const plan: RagQueryPlan = trimmed.length >= 3
    ? { mode: 'fts', sql: FTS_SQL }
    : { mode: 'like', sql: LIKE_SQL };
  return plan;
}

/**
 * 词 OR 兜底计划：trigram 要求每个词 ≥3 字，够长的词做 MATCH OR；
 * 全部词都太短时退化为逐词 LIKE。
 * 返回 null 表示没有可用词（调用方不再发第二次查询）。
 */
export function planTermQuery(terms: string[], topK: number): RagTermQueryPlan | null {
  const unique: string[] = [];
  for (let i = 0; i < terms.length; i += 1) {
    const term: string = terms[i].trim();
    if (term.length > 0 && unique.indexOf(term) < 0) {
      unique.push(term);
    }
  }
  if (unique.length === 0) {
    return null;
  }
  const matchTerms: string[] = [];
  for (let i = 0; i < unique.length; i += 1) {
    if (unique[i].length >= 3) {
      matchTerms.push(unique[i]);
    }
  }
  if (matchTerms.length > 0) {
    const expressions: string[] = [];
    for (let i = 0; i < matchTerms.length; i += 1) {
      expressions.push('"' + matchTerms[i].split('"').join('""') + '"');
    }
    const plan: RagTermQueryPlan = {
      mode: 'fts',
      sql: FTS_TERM_SQL,
      bindValues: [expressions.join(' OR '), topK],
    };
    return plan;
  }
  return planShortTermQuery(unique, topK);
}

/**
 * 短词 LIKE 计划：只取 <3 字的词（trigram 无法 MATCH）。
 * 词 OR 的 FTS 计划没命中时，再试短词，避免「数列极限的定义」这类长词未命中、
 * 短词「定义」本可命中的查询直接 miss。
 */
export function planShortTermQuery(terms: string[], topK: number): RagTermQueryPlan | null {
  const unique: string[] = [];
  for (let i = 0; i < terms.length; i += 1) {
    const term: string = terms[i].trim();
    if (term.length > 0 && term.length < 3 && unique.indexOf(term) < 0) {
      unique.push(term);
    }
  }
  if (unique.length === 0) {
    return null;
  }
  const clauses: string[] = [];
  const binds: Array<string | number> = [];
  for (let i = 0; i < unique.length; i += 1) {
    clauses.push('(content LIKE ? OR title LIKE ?)');
    const pattern: string = '%' + unique[i] + '%';
    binds.push(pattern, pattern);
  }
  binds.push(topK);
  const plan: RagTermQueryPlan = {
    mode: 'like',
    sql: 'SELECT unit_id, title, content, subject, chapter FROM note_fts '
      + 'WHERE ' + clauses.join(' OR ') + ' LIMIT ?',
    bindValues: binds,
  };
  return plan;
}
