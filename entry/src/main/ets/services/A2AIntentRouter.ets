/**
 * A2AIntentRouter.ets — A2A 请求意图路由（纯函数，无 IO）
 *
 * 路径: entry/src/main/ets/services/A2AIntentRouter.ets
 * 职责: 把「小艺请求（文本 + 是否带图 + 是否有未完成计划）」收敛成一个显式意图：
 *       probe / plan_continue / plan_waiting / ocr / pick_card / text_ingest / chat / empty。
 *       取代散落在 AgentExtAbility 里的 indexOf 关键词判断（shouldEnqueue / wantsPickCard 保留为兼容封装）。
 * 依赖: 无（纯函数，便于 Node 契约测试）。
 *
 * 设计要点：
 *   - 有未完成 checkpoint 计划时，任何「继续/第N题/全部/取消」都优先推进计划；
 *   - 带图片 → ocr（先 OCR，再进 checkpoint，不直接写库）；
 *   - 明确说「拍题/选图」但没图 → pick_card（引导卡片）；
 *   - 明确说「存笔记/整理成笔记…」→ text_ingest（文字走 036 切题/计划）；
 *   - 其余 → chat（正常对话回答，不误触发写作）。
 */
import { parseA2APlanCommand } from './A2APlanModels';

export const INTENT_PROBE: string = 'probe';
export const INTENT_PLAN_CONTINUE: string = 'plan_continue';
export const INTENT_PLAN_WAITING: string = 'plan_waiting';
export const INTENT_OCR: string = 'ocr';
export const INTENT_PICK_CARD: string = 'pick_card';
export const INTENT_TEXT_INGEST: string = 'text_ingest';
export const INTENT_CHAT: string = 'chat';
export const INTENT_EMPTY: string = 'empty';

export interface A2AIntent {
  kind: string;
  /** 便于日志/排障的原因（纯文本，不含用户隐私以外的内容） */
  reason: string;
}

/** 显式「存成笔记」指令短语。 */
const INGEST_PHRASES: string[] = [
  '存笔记',
  '记笔记',
  '整理成笔记',
  '存为笔记',
  '存到笔记',
  '记录到笔记',
  '笔记入库',
  '存进笔记',
  '整理一下这',
  '整理这道',
  '整理这几',
  '把这道题',
  '把这几道',
  '帮我整理',
];

/** 「拍题/选图」指令短语（无图时出卡片）。 */
const PICK_PHRASES: string[] = [
  '拍题',
  '拍图',
  '拍照',
  '整理图片',
  '整理照片',
  '上传图片',
  '发图片',
  '选图',
];

const MIN_TEXT_INGEST_CHARS: number = 8;

/**
 * 路由入口。
 * @param query 用户文本（可能为空）
 * @param hasImages 请求里是否有图片 part
 * @param hasPendingPlan 是否存在未完成的整理 checkpoint
 */
export function routeA2AIntent(query: string, hasImages: boolean, hasPendingPlan: boolean): A2AIntent {
  const text: string = query.trim();
  if (text.indexOf('识别探针') >= 0) {
    return { kind: INTENT_PROBE, reason: 'probe-keyword' };
  }
  if (hasPendingPlan) {
    const command = parseA2APlanCommand(text);
    if (command.kind !== 'none') {
      return { kind: INTENT_PLAN_CONTINUE, reason: 'plan-command:' + command.kind };
    }
    return { kind: INTENT_PLAN_WAITING, reason: 'pending-plan' };
  }
  if (hasImages) {
    return { kind: INTENT_OCR, reason: 'has-image-parts' };
  }
  if (text.length === 0) {
    return { kind: INTENT_EMPTY, reason: 'no-content' };
  }
  if (matchesAny(text, PICK_PHRASES)) {
    return { kind: INTENT_PICK_CARD, reason: 'pick-phrase' };
  }
  if (text.length >= MIN_TEXT_INGEST_CHARS && matchesAny(text, INGEST_PHRASES)) {
    return { kind: INTENT_TEXT_INGEST, reason: 'ingest-phrase' };
  }
  return { kind: INTENT_CHAT, reason: 'default-chat' };
}

function matchesAny(text: string, phrases: string[]): boolean {
  for (let i = 0; i < phrases.length; i += 1) {
    if (text.indexOf(phrases[i]) >= 0) {
      return true;
    }
  }
  return false;
}
