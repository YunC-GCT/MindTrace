/**
 * LegacyNoteNormalizer.ets — 历史笔记清理的纯函数（学科推断 / 重复分组）
 *
 * 路径: agents/src/main/ets/note/LegacyNoteNormalizer.ets
 * 职责: 用于一次性/可重复执行的旧数据清理：
 *       1) 历史笔记 subject 不在标准枚举时，先按别名归一，再按标题/章节/正文关键词推断，
 *          都失败才落「其他」；
 *       2) 把笔记按「归一化标题 + 归一化正文」分组，找出可安全删除的重复项（只删完全一致的）。
 * 依赖: agents 的 KnowledgeTaxonomy（别名归一/CANONICAL_SUBJECTS），无 IO。
 */
import { CANONICAL_SUBJECTS, normalizeSubjectName } from '../subagents/KnowledgeTaxonomy';
import { DedupeCandidate, isDuplicateOf } from './NoteDedupe';

const OTHER_SUBJECT: string = '其他';
const CONTENT_EXCERPT_LIMIT: number = 240;

export interface LegacySubjectInput {
  id: string;
  subject: string;
  chapter: string;
  title: string;
  contentExcerpt: string;
}

export interface LegacyDedupeEntry {
  id: string;
  titleKey: string;
  contentKey: string;
  createdAt: number;
}

export interface LegacyDuplicateGroup {
  keepId: string;
  removeIds: string[];
  titleKey: string;
}

const JUNIOR_KEYWORDS: string[] = [
  '一元一次', '一元二次', '二元一次', '方程', '整式', '分式', '因式分解', '平方根', '根号',
  '四则', '有理数', '绝对值', '不等式', '函数图像', '几何', '三角形', '勾股',
];

const CALCULUS_KEYWORDS: string[] = [
  '极限', '连续', '导数', '微分', '积分', '洛必达', '级数', '泰勒', '中值定理', '偏导',
];

const LINEAR_ALGEBRA_KEYWORDS: string[] = [
  '矩阵', '行列式', '向量', '特征值', '线性方程组', '秩', '线性空间', '二次型',
];

const PROBABILITY_KEYWORDS: string[] = [
  '概率', '随机变量', '期望', '方差', '分布', '统计',
];

/** 归一化/推断历史笔记的学科。返回 '' 表示无需修改（已是标准学科）。 */
export function normalizeLegacySubject(input: LegacySubjectInput): string {
  const subject: string = input.subject.trim();
  if (subject.length > 0 && CANONICAL_SUBJECTS.indexOf(subject) >= 0) {
    return '';
  }
  const alias: string = normalizeSubjectName(subject).subject.trim();
  if (alias.length > 0 && CANONICAL_SUBJECTS.indexOf(alias) >= 0 && alias !== OTHER_SUBJECT) {
    return alias;
  }
  const haystack: string = (input.chapter + ' ' + input.title + ' '
    + input.contentExcerpt.substring(0, CONTENT_EXCERPT_LIMIT));
  if (containsAny(haystack, LINEAR_ALGEBRA_KEYWORDS)) {
    return '线性代数';
  }
  if (containsAny(haystack, PROBABILITY_KEYWORDS)) {
    return '概率论';
  }
  if (containsAny(haystack, CALCULUS_KEYWORDS)) {
    return '高等数学';
  }
  if (containsAny(haystack, JUNIOR_KEYWORDS)) {
    return '初中数学';
  }
  return OTHER_SUBJECT;
}

/** 归一化文本键（去空白/标点/小写），用于精确重复判定。 */
export function normalizeKey(text: string): string {
  let out: string = '';
  const lower: string = text.toLowerCase();
  for (let i = 0; i < lower.length; i += 1) {
    const code: number = lower.charCodeAt(i);
    const isDigit: boolean = code >= 48 && code <= 57;
    const isLower: boolean = code >= 97 && code <= 122;
    const isCjk: boolean = code >= 0x4e00 && code <= 0x9fff;
    if (isDigit || isLower || isCjk) {
      out += lower.charAt(i);
    }
  }
  return out;
}

/**
 * 按「标题键 + 正文键」分组，返回可删除的重复组（保留最早创建的一条）。
 * 只处理完全一致（归一键相同）的重复，避免误删相似但不同内容的笔记。
 */
export function groupExactDuplicates(entries: LegacyDedupeEntry[]): LegacyDuplicateGroup[] {
  const groups: LegacyDuplicateGroup[] = [];
  const handled: number[] = [];
  for (let i = 0; i < entries.length; i += 1) {
    if (handled.indexOf(i) >= 0) {
      continue;
    }
    const titleKey: string = normalizeKey(entries[i].titleKey);
    const contentKey: string = normalizeKey(entries[i].contentKey);
    if (titleKey.length === 0 || contentKey.length === 0) {
      continue;
    }
    let keepId: string = entries[i].id;
    let keepCreatedAt: number = entries[i].createdAt;
    const removeIds: string[] = [];
    for (let j = i + 1; j < entries.length; j += 1) {
      if (normalizeKey(entries[j].titleKey) !== titleKey
        || normalizeKey(entries[j].contentKey) !== contentKey) {
        continue;
      }
      handled.push(j);
      if (entries[j].createdAt < keepCreatedAt) {
        removeIds.push(keepId);
        keepId = entries[j].id;
        keepCreatedAt = entries[j].createdAt;
      } else {
        removeIds.push(entries[j].id);
      }
    }
    if (removeIds.length > 0) {
      groups.push({ keepId: keepId, removeIds: removeIds, titleKey: titleKey });
    }
  }
  return groups;
}

/** 近重复分组：标题/正文相似度命中 NoteDedupe 规则即视为重复，保留最早一条。 */
export function groupNearDuplicates(entries: LegacyDedupeEntry[]): LegacyDuplicateGroup[] {
  const groups: LegacyDuplicateGroup[] = [];
  const kept: LegacyDedupeEntry[] = [];
  const removedByGroup: Map<string, string[]> = new Map<string, string[]>();
  for (let i = 0; i < entries.length; i += 1) {
    let matchedKeep: LegacyDedupeEntry | null = null;
    for (let k = 0; k < kept.length; k += 1) {
      const candidate: DedupeCandidate = { id: kept[k].id, title: kept[k].titleKey, content: kept[k].contentKey };
      if (isDuplicateOf(entries[i].titleKey, entries[i].contentKey, candidate)) {
        matchedKeep = kept[k];
        break;
      }
    }
    if (matchedKeep === null) {
      kept.push(entries[i]);
      continue;
    }
    const key: string = normalizeKey(matchedKeep.titleKey);
    const list: string[] = removedByGroup.get(key) ?? [];
    // 保留创建时间更早的一条
    if (entries[i].createdAt < matchedKeep.createdAt) {
      list.push(matchedKeep.id);
      kept[kept.indexOf(matchedKeep)] = entries[i];
    } else {
      list.push(entries[i].id);
    }
    removedByGroup.set(key, list);
  }
  removedByGroup.forEach((removeIds: string[], titleKey: string): void => {
    if (removeIds.length > 0) {
      let keepId: string = '';
      for (let i = 0; i < kept.length; i += 1) {
        if (normalizeKey(kept[i].titleKey) === titleKey) {
          keepId = kept[i].id;
          break;
        }
      }
      if (keepId.length > 0) {
        groups.push({ keepId: keepId, removeIds: removeIds, titleKey: titleKey });
      }
    }
  });
  return groups;
}

function containsAny(text: string, keywords: string[]): boolean {
  for (let i = 0; i < keywords.length; i += 1) {
    if (text.indexOf(keywords[i]) >= 0) {
      return true;
    }
  }
  return false;
}
