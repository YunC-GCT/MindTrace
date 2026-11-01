/**
 * StructuredSections.ets — 结构化字段的「标准表单」契约（纯函数）
 *
 * 路径: agents/src/main/ets/agents/StructuredSections.ets
 * 职责: 1) 定义五类笔记的标准字段（标题集合与同义词），
 *       2) 把模型返回的 fields 规范化成标准标签、补齐顺序，
 *       3) 校验缺字段（交给 LlmGuard 触发重试，避免「表单内容纰漏」）。
 * 依赖: 无（纯字符串，便于 Node 契约测试）。
 */

export interface FlatField {
  key: string;
  label: string;
  value: string;
}

const CATEGORY_CONCEPT: string = '概念';
const CATEGORY_THEOREM: string = '定理';
const CATEGORY_FORMULA: string = '公式';
const CATEGORY_PROOF: string = '证明题';
const CATEGORY_COMPUTATION: string = '计算题';

/** 五类笔记的标准字段（顺序即展示顺序）。 */
export function requiredSectionLabels(category: string): string[] {
  if (category === CATEGORY_THEOREM) {
    return ['陈述', '条件', '结论', '证明思路', '应用'];
  }
  if (category === CATEGORY_FORMULA) {
    return ['表达式', '参数', '适用范围', '推导', '备注'];
  }
  if (category === CATEGORY_PROOF) {
    return ['命题', '已知', '证明过程', '关键思路', '结论'];
  }
  if (category === CATEGORY_COMPUTATION) {
    return ['问题', '步骤', '答案', '方法总结', '常见错误'];
  }
  return ['定义', '性质', '示例', '相关概念'];
}

/** 同义词 → 标准标签（按类别区分，避免「陈述/命题」串类）。 */
function synonymTable(category: string): Map<string, string> {
  const map: Map<string, string> = new Map<string, string>();
  const labels: string[] = requiredSectionLabels(category);
  for (let i = 0; i < labels.length; i += 1) {
    map.set(labels[i], labels[i]);
  }
  if (category === CATEGORY_CONCEPT) {
    addAliases(map, '定义', ['定义', '概念定义', '基本定义', '定义与含义']);
    addAliases(map, '性质', ['性质', '基本性质', '特点', '特征']);
    addAliases(map, '示例', ['示例', '例子', '例题', '举例', '例']);
    addAliases(map, '相关概念', ['相关概念', '关联概念', '相关知识点', '联系']);
  } else if (category === CATEGORY_THEOREM) {
    addAliases(map, '陈述', ['陈述', '定理陈述', '定理内容', '内容', '命题陈述']);
    addAliases(map, '条件', ['条件', '前提', '前提条件', '适用条件']);
    addAliases(map, '结论', ['结论', '定理结论', '结果']);
    addAliases(map, '证明思路', ['证明思路', '思路', '证明概要', '证明方法']);
    addAliases(map, '应用', ['应用', '应用场景', '用途', '使用场景']);
  } else if (category === CATEGORY_FORMULA) {
    addAliases(map, '表达式', ['表达式', '公式', '公式表达式', '公式内容']);
    addAliases(map, '参数', ['参数', '参数说明', '变量说明', '符号说明']);
    addAliases(map, '适用范围', ['适用范围', '适用条件', '使用条件']);
    addAliases(map, '推导', ['推导', '推导过程', '证明过程', '来源']);
    addAliases(map, '备注', ['备注', '说明', '注意事项', '补充说明']);
  } else if (category === CATEGORY_PROOF) {
    addAliases(map, '命题', ['命题', '题目', '原题', '命题内容']);
    addAliases(map, '已知', ['已知', '已知条件', '条件']);
    addAliases(map, '证明过程', ['证明过程', '证明', '过程', '证明步骤']);
    addAliases(map, '关键思路', ['关键思路', '思路', '核心思路', '关键步骤']);
    addAliases(map, '结论', ['结论', '证明结论', '结论说明']);
  } else if (category === CATEGORY_COMPUTATION) {
    addAliases(map, '问题', ['问题', '题目', '原题', '问题描述']);
    addAliases(map, '步骤', ['步骤', '解题步骤', '解答步骤', '过程']);
    addAliases(map, '答案', ['答案', '结果', '最终答案', '解', '答案解析', '答案与解析']);
    addAliases(map, '方法总结', ['方法总结', '方法', '解题方法', '总结']);
    addAliases(map, '常见错误', ['常见错误', '易错点', '易错', '错误分析']);
  }
  return map;
}

function addAliases(map: Map<string, string>, canonical: string, aliases: string[]): void {
  for (let i = 0; i < aliases.length; i += 1) {
    map.set(normalizeLabel(aliases[i]), canonical);
  }
}

function normalizeLabel(text: string): string {
  return text.replace(/\s+/g, '').replace(/[：:（）()【】\[\]-]/g, '');
}

/** 模型字段 → 标准标签；匹配不上返回空串（由调用方决定丢弃或保留）。 */
export function canonicalSectionLabel(category: string, key: string, label: string): string {
  const map: Map<string, string> = synonymTable(category);
  const byLabel: string | undefined = map.get(normalizeLabel(label));
  if (byLabel !== undefined) {
    return byLabel;
  }
  const byKey: string | undefined = map.get(normalizeLabel(key));
  if (byKey !== undefined) {
    return byKey;
  }
  return '';
}

/** 缺哪些标准字段（空值/占位符也算缺）。 */
export function missingSectionLabels(category: string, fields: FlatField[]): string[] {
  const required: string[] = requiredSectionLabels(category);
  const present: string[] = [];
  for (let i = 0; i < fields.length; i += 1) {
    const canonical: string = canonicalSectionLabel(category, fields[i].key, fields[i].label);
    if (canonical.length > 0 && !isPlaceholderValue(fields[i].value) && present.indexOf(canonical) < 0) {
      present.push(canonical);
    }
  }
  const missing: string[] = [];
  for (let i = 0; i < required.length; i += 1) {
    if (present.indexOf(required[i]) < 0) {
      missing.push(required[i]);
    }
  }
  return missing;
}

/** 规范化 fields：标准字段按标准顺序在前，未识别的非空字段按原顺序追加，空/占位值丢弃。 */
export function normalizeStructuredFields(category: string, fields: FlatField[]): FlatField[] {
  const required: string[] = requiredSectionLabels(category);
  const result: FlatField[] = [];
  for (let r = 0; r < required.length; r += 1) {
    const canonical: string = required[r];
    for (let i = 0; i < fields.length; i += 1) {
      const matched: string = canonicalSectionLabel(category, fields[i].key, fields[i].label);
      if (matched !== canonical || isPlaceholderValue(fields[i].value)) {
        continue;
      }
      result.push({ key: canonical, label: canonical, value: fields[i].value.trim() });
      break;
    }
  }
  for (let i = 0; i < fields.length; i += 1) {
    const canonical: string = canonicalSectionLabel(category, fields[i].key, fields[i].label);
    if (canonical.length > 0 || isPlaceholderValue(fields[i].value)) {
      continue;
    }
    const label: string = fields[i].label.trim().length > 0 ? fields[i].label.trim() : fields[i].key.trim();
    result.push({ key: fields[i].key, label: label, value: fields[i].value.trim() });
  }
  return result;
}

/** 空值/占位符（模型偷懒时常见）判定。 */
export function isPlaceholderValue(value: string): boolean {
  const trimmed: string = value.trim();
  if (trimmed.length === 0) {
    return true;
  }
  const lower: string = trimmed.toLowerCase();
  const placeholders: string[] = ['无', '暂无', '略', '待补充', 'n/a', 'na', 'null', 'undefined', '-'];
  return placeholders.indexOf(lower) >= 0;
}
