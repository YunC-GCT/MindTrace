/**
 * RagQueryPlan.ets — RAG 检索查询规划（纯函数，无 IO）
 *
 * 路径: entry/src/main/ets/services/RagQueryPlan.ets
 * 职责: 依据查询长度选执行策略：≥3 字走 FTS5 trigram MATCH（BM25 排序）；<3 字 trigram 无法命中，
 *       退化为 LIKE 子串扫描（笔记量小，可接受）。
 * 依赖: 无（纯函数，便于 Node 侧契约测试）。
 */
export interface RagQueryPlan {
  mode: string;
  sql: string;
}

const FTS_SQL: string =
  'SELECT unit_id, title, content, subject, chapter FROM note_fts '
  + 'WHERE note_fts MATCH ? ORDER BY rank LIMIT ?';
const LIKE_SQL: string =
  'SELECT unit_id, title, content, subject, chapter FROM note_fts '
  + 'WHERE content LIKE ? OR title LIKE ? LIMIT ?';

export function planRagQuery(query: string): RagQueryPlan {
  const trimmed: string = query.trim();
  const plan: RagQueryPlan = trimmed.length >= 3
    ? { mode: 'fts', sql: FTS_SQL }
    : { mode: 'like', sql: LIKE_SQL };
  return plan;
}
