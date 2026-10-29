/**
 * KnowledgeTaxonomy.ets — 学科名归一 + 标题去复核标记。
 *
 * 路径: agents/src/main/ets/agents/KnowledgeTaxonomy.ets
 * 职责: 把 LLM 自由生成的 subject / title 收敛到可枚举的学科名，并把「复核提示」
 *       从标题里剥出去交给 needsUserInput，而不是让它们长在标题上。
 * 依赖: 无（纯字符串函数，Node 侧 loader 可直接装载做契约测试）。
 *
 * 数据流:
 *   CaptureStructurer.normalizeSubject / normalizeTitle → 本文件 → 落库前最后一次清洗
 *
 * Why: prompt 里写的是「学科名称由你自主判断」，模型每次都会重新发明一遍：
 *      同一门课同时出现「最优化」「最优化方法」「数学（优化理论/运筹学）」；
 *      复核提示「（OCR 信息不完整）」也会被写进 title，直接显示在笔记列表里。
 *      这类漂移不能靠改 prompt 解决——prompt 只能提高概率，归一必须在落库前做。
 *
 * 语义边界:
 *   - 只做「映射到已有学科」，不发明新学科：认不出来就保留原文（去括号修饰后的头部）。
 *   - 括号里更具体时以括号为准：「数学（优化理论/运筹学）」→ 最优化方法。
 *   - 标题只剥「复核类」括号：OCR / 待确认 / 待核对 / 待补 / 信息不完整 / 待人工 / 待定。
 *     分值（10 分）、年份（2024）、人名等正常括号一律保留。
 *   - 被剥掉的标记原文回传给调用方，由调用方记 needsUserInput，信息不丢。
 *
 * ArkTS 1.1 strict 适配:
 *   - 正则集中为模块常量且不带 g 标志；多处替换用「循环到稳定」而不是全局标志。
 *   - 所有变量、参数、返回值显式标注类型；对象字面量绑定 interface。
 *   - 只用下标 for，不用 for...of / 展开运算符 / Object.assign。
 */

export interface SubjectNormalization {
  subject: string;   // 归一后的学科名；无法识别时是清理后的原文
  changed: boolean;  // 与入参（trim 后）相比是否发生过变化
}

export interface TitleSanitization {
  title: string;         // 剥掉复核标记后的标题；可能为空字符串
  stripped: string[];    // 被剥掉的括号原文（含括号），按出现顺序
}

interface SubjectAlias {
  canonical: string;
  aliases: string[];
}

/** 可枚举学科名：UI 的学科筛选、知识星系都按这套名字分组 */
export const CANONICAL_SUBJECTS: string[] = [
  '数学分析',
  '高等数学',
  '线性代数',
  '解析几何',
  '概率论',
  '最优化方法',
  '数值分析',
  '离散数学',
  '初中数学',
  '高中数学',
  '其它',
];

// aliases 里越长的名字越优先，避免「概率」抢在「概率论与数理统计」前面。
const SUBJECT_ALIASES: SubjectAlias[] = [
  {
    canonical: '最优化方法',
    aliases: ['最优化方法', '最优化理论', '最优化', '优化理论', '优化方法', '运筹学', '运筹优化',
      '运筹', '数学规划', '非线性规划', '凸优化'],
  },
  { canonical: '数学分析', aliases: ['数学分析'] },
  { canonical: '高等数学', aliases: ['高等数学', '高数', '微积分'] },
  { canonical: '线性代数', aliases: ['线性代数', '线代', '矩阵论'] },
  { canonical: '解析几何', aliases: ['解析几何', '空间解析几何'] },
  { canonical: '概率论', aliases: ['概率论与数理统计', '概率统计', '概率论', '概率'] },
  { canonical: '数值分析', aliases: ['数值分析', '数值计算方法', '计算方法'] },
  { canonical: '离散数学', aliases: ['离散数学'] },
  { canonical: '初中数学', aliases: ['初中数学'] },
  { canonical: '高中数学', aliases: ['高中数学'] },
  { canonical: '其它', aliases: ['其它', '其他', '未知学科'] },
];

// 复核类标记的判定词；命中就把整个括号从标题里摘掉。
const REVIEW_MARKER_WORDS: string[] = [
  'ocr', '待确认', '待核对', '待补', '待人工', '待定', '未确认', '信息不完整', '识别不完整',
  // 模型不会只用一套说法：「隐式公式无法识别项」和「OCR 信息不完整」是同一件事
  '无法识别', '未识别', '无法确定', '识别不清',
];

// 标题首尾允许被吞掉的分隔符。
const SEPARATOR_PATTERN = /[\s\u3000·・、,，;；:：\-—]+$/;
const LEADING_SEPARATOR_PATTERN = /^[\s\u3000·・、,，;；:：\-—]+/;
const MULTI_SPACE_PATTERN = /[\s\u3000]{2,}/;

/** 判断括号内容是不是复核提示（不看大小写）。 */
function isReviewMarker(inner: string): boolean {
  const lower: string = inner.toLowerCase();
  for (let i = 0; i < REVIEW_MARKER_WORDS.length; i++) {
    if (lower.indexOf(REVIEW_MARKER_WORDS[i]) >= 0) {
      return true;
    }
  }
  return false;
}

/** 找第一个括号段的结束位置；找不到返回 -1。 */
function findClosing(text: string, openIndex: number): number {
  const open: string = text.charAt(openIndex);
  const close: string = open === '（' ? '）' : ')';
  return text.indexOf(close, openIndex + 1);
}

/** 取出所有括号内容，用 / 连接（供匹配学科别名用）。 */
function bracketContents(text: string): string {
  const parts: string[] = [];
  let i: number = 0;
  while (i < text.length) {
    const ch: string = text.charAt(i);
    if (ch === '（' || ch === '(') {
      const end: number = findClosing(text, i);
      if (end < 0) {
        break;
      }
      const inner: string = text.substring(i + 1, end).trim();
      if (inner.length > 0) {
        parts.push(inner);
      }
      i = end + 1;
      continue;
    }
    i += 1;
  }
  return parts.join('/');
}

/** 去掉所有括号段，只留头部。 */
function stripBrackets(text: string): string {
  let out: string = '';
  let i: number = 0;
  while (i < text.length) {
    const ch: string = text.charAt(i);
    if (ch === '（' || ch === '(') {
      const end: number = findClosing(text, i);
      if (end < 0) {
        break;
      }
      i = end + 1;
      continue;
    }
    out += ch;
    i += 1;
  }
  return out;
}

function collapseSpaces(text: string): string {
  let result: string = text;
  while (MULTI_SPACE_PATTERN.test(result)) {
    result = result.replace(MULTI_SPACE_PATTERN, ' ');
  }
  return result;
}

/** 把一段文本匹配到可枚举学科名；匹配不到返回空字符串。 */
function matchSubjectName(text: string): string {
  const target: string = text.trim();
  if (target.length === 0) {
    return '';
  }
  for (let i = 0; i < CANONICAL_SUBJECTS.length; i++) {
    if (target === CANONICAL_SUBJECTS[i]) {
      return CANONICAL_SUBJECTS[i];
    }
  }
  let best: string = '';
  let bestLength: number = 0;
  for (let i = 0; i < SUBJECT_ALIASES.length; i++) {
    const rule: SubjectAlias = SUBJECT_ALIASES[i];
    for (let j = 0; j < rule.aliases.length; j++) {
      const alias: string = rule.aliases[j];
      if (target.indexOf(alias) >= 0 && alias.length > bestLength) {
        best = rule.canonical;
        bestLength = alias.length;
      }
    }
  }
  return best;
}

/**
 * 学科名归一。
 *
 * 顺序：括号内（更具体）→ 整体原文 → 去括号后的头部 → 清洗后的原文。
 * 认不出来时返回头部原文并把 changed=false，绝不自造学科名。
 */
export function normalizeSubjectName(raw: string, fallback: string = ''): SubjectNormalization {
  const trimmed: string = raw.trim();
  if (trimmed.length === 0 || trimmed === 'null' || trimmed === 'undefined' || trimmed === '未知') {
    const inherited: string = fallback.trim();
    return { subject: inherited, changed: false };
  }
  const inner: string = bracketContents(trimmed);
  const head: string = stripBrackets(trimmed).trim();
  let canonical: string = '';
  if (inner.length > 0) {
    canonical = matchSubjectName(inner);
  }
  if (canonical.length === 0) {
    canonical = matchSubjectName(trimmed);
  }
  if (canonical.length === 0) {
    canonical = matchSubjectName(head);
  }
  if (canonical.length > 0) {
    return { subject: canonical, changed: canonical !== trimmed };
  }
  const kept: string = head.length > 0 ? head : trimmed;
  return { subject: kept, changed: kept !== trimmed };
}

/**
 * 标题去复核标记。
 *
 * 只摘「复核类」括号；正常括号（分值、年份、题号）原样保留。
 * 末尾被截断的括号（比如模型写了一半）整段丢弃，并把原文记进 stripped。
 */
export interface SubjectResolution {
  subject: string;
  /** canonical=命中内置学科名；existing=复用库里已有学科；new=确实没有，要新建 */
  decision: 'canonical' | 'existing' | 'new';
  /** decision=new 时给的近似候选（最多 3 个），供 UI 让用户改选 */
  candidates: string[];
}

function sharedCharCount(a: string, b: string): number {
  let count: number = 0;
  for (let i = 0; i < a.length; i++) {
    const ch: string = a.charAt(i);
    if (b.indexOf(ch) >= 0) {
      count += 1;
    }
  }
  return count;
}

/**
 * 分类 agent 的学科裁决：先认内置学科，再认库里已有的学科，最后才允许新建。
 *
 * 用户要的正是这个判断——同一门课已经在库里出现过的名字必须复用，
 * 否则「最优化」和「最优化方法」会长期并存；只有确实没见过才新建，
 * 并返回近似候选，让 UI 有机会让用户改选。
 */
export function resolveSubjectName(raw: string, known: string[]): SubjectResolution {
  const trimmed: string = raw.trim();
  const normalized: SubjectNormalization = normalizeSubjectName(trimmed);
  if (CANONICAL_SUBJECTS.indexOf(normalized.subject) >= 0) {
    return { subject: normalized.subject, decision: 'canonical', candidates: [] };
  }
  if (trimmed.length > 0 && known.indexOf(trimmed) >= 0) {
    return { subject: trimmed, decision: 'existing', candidates: [] };
  }
  // 「高等数学」已在库里、模型写「高等数学（下）」时，包含关系就是最可靠的复用信号
  for (let i = 0; i < known.length; i++) {
    const candidate: string = known[i].trim();
    if (candidate.length < 2) {
      continue;
    }
    if (trimmed.indexOf(candidate) >= 0 || candidate.indexOf(trimmed) >= 0) {
      return { subject: candidate, decision: 'existing', candidates: [] };
    }
  }
  const scored: string[] = known.slice(0);
  scored.sort((a: string, b: string): number => sharedCharCount(b, trimmed) - sharedCharCount(a, trimmed));
  const candidates: string[] = [];
  for (let i = 0; i < scored.length && candidates.length < 3; i++) {
    const item: string = scored[i].trim();
    if (item.length > 0 && sharedCharCount(item, trimmed) >= 2) {
      candidates.push(item);
    }
  }
  const subject: string = trimmed.length > 0 ? trimmed : normalized.subject;
  return { subject: subject, decision: 'new', candidates: candidates };
}

export function sanitizeNoteTitle(raw: string): TitleSanitization {
  const source: string = raw.trim();
  const stripped: string[] = [];
  let kept: string = '';
  let i: number = 0;
  while (i < source.length) {
    const ch: string = source.charAt(i);
    if (ch === '（' || ch === '(') {
      const end: number = findClosing(source, i);
      if (end < 0) {
        stripped.push(source.substring(i));
        break;
      }
      const inner: string = source.substring(i + 1, end);
      if (isReviewMarker(inner)) {
        stripped.push(source.substring(i, end + 1));
      } else {
        kept += source.substring(i, end + 1);
      }
      i = end + 1;
      continue;
    }
    kept += ch;
    i += 1;
  }
  let title: string = collapseSpaces(kept).trim();
  title = title.replace(LEADING_SEPARATOR_PATTERN, '');
  title = title.replace(SEPARATOR_PATTERN, '');
  const result: TitleSanitization = { title: title.trim(), stripped: stripped };
  return result;
}
