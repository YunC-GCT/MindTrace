/**
 * ToolResultBudget.ets — 工具结果的预算裁剪（纯函数，无 IO）
 *
 * 路径: common/src/main/ets/workflow/tool-calling/ToolResultBudget.ets
 * 职责: 工具结果超过字符预算时，优先保留 JSON 结构：
 *       - `{ hits: [...] }` / `{ notes: [...] }` 等对象：从尾部丢弃数组条目并标注 truncated/dropped/count；
 *       - 顶层数组（如 note_query 的 `[...]`）：丢弃尾部条目；
 *       - 仍超预算时缩短超长字符串字段。
 *       保证回喂给模型的仍是可解析 JSON，而不是半截字符串。
 * 依赖: 无。
 */
export interface ToolBudgetResult {
  content: string;
  truncated: boolean;
  dropped: number;
}

const JSON_STRING_MAX_CHARS: number = 400;
const STRING_ELLIPSIS: string = '…';

export function fitToolResult(content: string, maxChars: number): ToolBudgetResult {
  if (content.length <= maxChars) {
    const unchanged: ToolBudgetResult = { content: content, truncated: false, dropped: 0 };
    return unchanged;
  }
  const trimmed: string = content.trim();
  if (trimmed.length > 0 && (trimmed.charAt(0) === '{' || trimmed.charAt(0) === '[')) {
    try {
      const parsed: Object = JSON.parse(trimmed) as Object;
      if (parsed !== null && typeof parsed === 'object') {
        if (isArrayLike(parsed)) {
          return fitJsonArray(parsed as Object[], maxChars);
        }
        return fitJsonObject(parsed as Record<string, Object>, maxChars);
      }
    } catch (e) {
      // 非法 JSON：退回字符截断
    }
  }
  return cutString(content, maxChars);
}

function isArrayLike(value: Object | undefined): boolean {
  if (value === undefined || value === null || typeof value !== 'object') {
    return false;
  }
  const items: Object[] = value as Object[];
  return typeof items.length === 'number' && typeof items.push === 'function';
}

function fitJsonArray(items: Object[], maxChars: number): ToolBudgetResult {
  let dropped: number = 0;
  while (items.length > 1 && JSON.stringify(items).length > maxChars) {
    items.pop();
    dropped += 1;
  }
  shortenLongStrings(items);
  const serialized: string = JSON.stringify(items);
  if (serialized.length <= maxChars) {
    const result: ToolBudgetResult = { content: serialized, truncated: true, dropped: dropped };
    return result;
  }
  const cut: ToolBudgetResult = cutString(serialized, maxChars);
  const result: ToolBudgetResult = { content: cut.content, truncated: true, dropped: dropped };
  return result;
}

function fitJsonObject(record: Record<string, Object>, maxChars: number): ToolBudgetResult {
  let dropped: number = 0;
  const keys: string[] = Object.keys(record);
  let listKey: string = '';
  for (let i = 0; i < keys.length; i += 1) {
    if (isArrayLike(record[keys[i]])) {
      listKey = keys[i];
      break;
    }
  }
  if (listKey.length > 0) {
    const items: Object[] = record[listKey] as Object[];
    while (items.length > 1 && JSON.stringify(record).length > maxChars) {
      items.pop();
      dropped += 1;
    }
    record['truncated'] = true;
    record['dropped'] = dropped;
    record['count'] = items.length;
    // 元数据本身也占字符：补一轮，直到含元数据的序列化结果也进预算。
    while (items.length > 1 && JSON.stringify(record).length > maxChars) {
      items.pop();
      dropped += 1;
      record['dropped'] = dropped;
      record['count'] = items.length;
    }
    shortenLongStrings(items);
  } else {
    shortenLongStrings([record]);
    record['truncated'] = true;
  }
  const serialized: string = JSON.stringify(record);
  if (serialized.length <= maxChars) {
    const result: ToolBudgetResult = { content: serialized, truncated: true, dropped: dropped };
    return result;
  }
  const cut: ToolBudgetResult = cutString(serialized, maxChars);
  const result: ToolBudgetResult = { content: cut.content, truncated: true, dropped: dropped };
  return result;
}

/** 缩短对象里的超长字符串字段（单层），保留结构。 */
function shortenLongStrings(items: Object[]): void {
  for (let i = 0; i < items.length; i += 1) {
    const item: Object = items[i];
    if (item === null || typeof item !== 'object' || isArrayLike(item)) {
      continue;
    }
    const record: Record<string, Object> = item as Record<string, Object>;
    const keys: string[] = Object.keys(record);
    for (let k = 0; k < keys.length; k += 1) {
      const value: Object = record[keys[k]];
      if (typeof value === 'string' && (value as string).length > JSON_STRING_MAX_CHARS) {
        record[keys[k]] = (value as string).substring(0, JSON_STRING_MAX_CHARS) + STRING_ELLIPSIS;
      }
    }
  }
}

function cutString(content: string, maxChars: number): ToolBudgetResult {
  const result: ToolBudgetResult = {
    content: content.substring(0, maxChars) + '…[truncated]',
    truncated: true,
    dropped: 0,
  };
  return result;
}
