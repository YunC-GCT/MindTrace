/**
 * A2APlanModels.ets — A2A 多题「识别规划 + 一题一题来」的纯模型/文案
 *
 * 路径: entry/src/main/ets/services/A2APlanModels.ets
 * 职责: 多题文本进入 A2A 后先生成「整理规划」（题数/质量/每题目录），
 *       支持用户回复「继续 / 第 N 题 / 全部 / 取消」逐题推进。
 *       纯函数（无 IO、无 Context），便于 Node 契约测试。
 * 依赖: agents 的 planCaptureSet（036 同款切题）。
 */
import { planCaptureSet } from 'agents';
import type { PlannedProblem, SetImageText, SetPlan } from 'agents';

/** 规划中的一道题。 */
export interface A2APlanItem {
  index: number;
  anchor: string;
  text: string;
  needsReview: boolean;
  /** 来源图片下标（纯文字输入为空数组） */
  sourceImages: number[];
}

/** 待推进的整理计划。 */
export interface A2APlan {
  taskId: string;
  createdAt: number;
  items: A2APlanItem[];
  /** 已整理完成的题号（index） */
  done: number[];
}

/** 用户对计划的指令。 */
export interface A2APlanCommand {
  kind: string;
  index: number;
}

export const PLAN_CMD_START: string = 'start';
export const PLAN_CMD_ALL: string = 'all';
export const PLAN_CMD_CANCEL: string = 'cancel';
export const PLAN_CMD_INDEX: string = 'index';
export const PLAN_CMD_NONE: string = 'none';

const PREVIEW_LIMIT: number = 36;

/** 把一段文本按题切分成规划项（>1 时调用方才应保存计划并回摘要）。 */
export function buildA2APlanItems(text: string): A2APlanItem[] {
  const pages: SetImageText[] = [{ imageIndex: 0, text: text }];
  return buildA2APlanItemsFromPages(pages);
}

/** 把多页 OCR 文本按题切分成规划项（图片入口用；保留来源图下标）。 */
export function buildA2APlanItemsFromPages(pages: SetImageText[]): A2APlanItem[] {
  const plan: SetPlan = planCaptureSet(pages);
  const items: A2APlanItem[] = [];
  for (let i = 0; i < plan.problems.length; i += 1) {
    const problem: PlannedProblem = plan.problems[i];
    const anchor: string = problem.anchors.length > 0 ? problem.anchors.join(' / ') : '无题号';
    const item: A2APlanItem = {
      index: problem.index,
      anchor: anchor,
      text: problem.text,
      needsReview: problem.needsReview,
      sourceImages: problem.sourceImageIndexes,
    };
    items.push(item);
  }
  return items;
}

/** 解析用户回复：继续/开始、第N题、全部、取消。 */
export function parseA2APlanCommand(query: string): A2APlanCommand {
  const text: string = query.trim();
  const lower: string = text.toLowerCase();
  if (text.length === 0) {
    return { kind: PLAN_CMD_NONE, index: -1 };
  }
  if (lower.indexOf('取消') >= 0 || lower.indexOf('算了') >= 0) {
    return { kind: PLAN_CMD_CANCEL, index: -1 };
  }
  if (lower === '全部' || lower.indexOf('全部整理') >= 0 || lower.indexOf('都整理') >= 0
    || lower.indexOf('一起整理') >= 0) {
    return { kind: PLAN_CMD_ALL, index: -1 };
  }
  if (lower.indexOf('继续') >= 0 || lower.indexOf('开始') >= 0 || lower.indexOf('下一题') >= 0
    || lower === '好' || lower === '可以' || lower === '嗯') {
    return { kind: PLAN_CMD_START, index: -1 };
  }
  const match: RegExpMatchArray | null = text.match(/第\s*(\d+)\s*题/);
  if (match !== null) {
    const index: number = Number(match[1]);
    if (index > 0) {
      return { kind: PLAN_CMD_INDEX, index: index };
    }
  }
  if (/^\d+$/.test(text) && Number(text) > 0) {
    return { kind: PLAN_CMD_INDEX, index: Number(text) };
  }
  return { kind: PLAN_CMD_NONE, index: -1 };
}

/** 下一道未完成的题（按题序）；无则返回 undefined。 */
export function nextPlanItem(plan: A2APlan): A2APlanItem | undefined {
  for (let i = 0; i < plan.items.length; i += 1) {
    if (plan.done.indexOf(plan.items[i].index) < 0) {
      return plan.items[i];
    }
  }
  return undefined;
}

/** 剩余未整理题数。 */
export function remainingPlanCount(plan: A2APlan): number {
  let count: number = 0;
  for (let i = 0; i < plan.items.length; i += 1) {
    if (plan.done.indexOf(plan.items[i].index) < 0) {
      count += 1;
    }
  }
  return count;
}

export function reviewCountOf(items: A2APlanItem[]): number {
  let count: number = 0;
  for (let i = 0; i < items.length; i += 1) {
    if (items[i].needsReview) {
      count += 1;
    }
  }
  return count;
}

/**
 * 识别摘要 + 整理规划（首次收到多题文本时回给用户；不触发 LLM，秒回）。
 * 例：识别到 3 道题，约 128 字（待复核 1 道）：
 * 1. [1.] 求方程…（约 42 字，正常）
 * 2. [2.] 已知函数…（约 39 字，待复核）
 * 回复「继续」按顺序整理，或「第 2 题」只整理某题；「全部」转待整理；「取消」放弃。
 */
export function formatA2APlanSummary(plan: A2APlan): string {
  const chars: number = totalChars(plan.items);
  const review: number = reviewCountOf(plan.items);
  const lines: string[] = [];
  lines.push('识别到 ' + plan.items.length.toString() + ' 道题，约 ' + chars.toString() + ' 字'
    + (review > 0 ? '（待复核 ' + review.toString() + ' 道）' : '') + '：');
  for (let i = 0; i < plan.items.length; i += 1) {
    const item: A2APlanItem = plan.items[i];
    const source: string = item.sourceImages.length > 0
      ? '第 ' + (item.sourceImages[0] + 1).toString() + ' 张图' : '文字';
    lines.push((i + 1).toString() + '. [' + item.anchor + '] ' + previewOf(item.text)
      + '（' + source + '，约 ' + item.text.length.toString() + ' 字，'
      + (item.needsReview ? '待复核' : '正常') + '）');
  }
  lines.push('回复「继续」按顺序一题一题整理；「第 2 题」只整理某题；「全部」转待整理；「取消」放弃。');
  return lines.join('\n');
}

/** 单题完成回执 + 进度。 */
export function formatA2APlanProgress(plan: A2APlan, item: A2APlanItem, title: string, subject: string): string {
  const remaining: number = remainingPlanCount(plan);
  const doneCount: number = plan.done.length;
  const lines: string[] = [];
  lines.push('第 ' + (item.index + 1).toString() + ' 题已整理入库：' + title
    + (subject.length > 0 ? '（' + subject + '）' : ''));
  lines.push('进度 ' + doneCount.toString() + '/' + plan.items.length.toString()
    + (remaining > 0
      ? '，还剩 ' + remaining.toString() + ' 题。回复「继续」整理下一题，或「第 N 题」/「全部」/「取消」。'
      : '，全部整理完成 ✅')); 
  return lines.join('\n');
}

function totalChars(items: A2APlanItem[]): number {
  let total: number = 0;
  for (let i = 0; i < items.length; i += 1) {
    total += items[i].text.length;
  }
  return total;
}

function previewOf(text: string): string {
  const oneLine: string = text.replace(/\s+/g, ' ').trim();
  return oneLine.length > PREVIEW_LIMIT ? oneLine.substring(0, PREVIEW_LIMIT) + '…' : oneLine;
}
