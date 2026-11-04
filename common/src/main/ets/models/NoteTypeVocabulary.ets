/**
 * NoteTypeVocabulary.ets — 笔记类型词表与归一化
 *
 * 路径: common/src/main/ets/models/NoteTypeVocabulary.ets
 * 职责: 定义 5 类笔记类型（概念/定理/公式/证明题/计算题）、旧称别名与归一化判定；
 *       不含任何取色或渲染逻辑
 * 依赖: 无
 *
 * 数据流:
 *   生成/校验（agents）与列表筛选（entry） → normalizeNoteType → NoteType
 */
export const NOTE_TYPE_ALL_KEY: string = 'all';
export const NOTE_TYPE_KEYS: string[] = ['概念', '定理', '公式', '证明题', '计算题'];

const NOTE_TYPE_ALIASES: Record<string, string> = {
  '证明': '证明题',
  '计算': '计算题',
};

export function noteTypeFilterKeys(): string[] {
  const keys: string[] = [NOTE_TYPE_ALL_KEY];
  for (const key of NOTE_TYPE_KEYS) {
    keys.push(key);
  }
  return keys;
}

export function normalizeNoteType(t: string): string {
  const type: string = t.trim();
  const mapped: string | undefined = NOTE_TYPE_ALIASES[type];
  return mapped !== undefined ? mapped : type;
}

export function isKnownNoteType(t: string): boolean {
  return NOTE_TYPE_KEYS.indexOf(normalizeNoteType(t)) >= 0;
}
