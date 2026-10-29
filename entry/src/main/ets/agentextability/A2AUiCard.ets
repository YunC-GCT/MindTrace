/**
 * A2AUiCard.ets — 端A2A 回执里的官方 UI 卡片指令与跳转指令（纯字符串构造）
 *
 * 路径: entry/src/main/ets/agentextability/A2AUiCard.ets
 * 职责: 按《端A2A协议消息指令定义 / 扩展数据结构定义》构造
 *       Part.data.uiExtensionCard 与 {data:{jump:{executeIntent,deepLink}}} 指令，
 *       并提供「用户想要拍题/选图」的本地意图判定。
 * 依赖: 无（纯函数，不 import 任何 @kit.*，可被 node:test 直接 transpile 执行）
 *
 * 数据流:
 *   AgentExtAbility.sendAnswer(query) -> wantsPickCard(query) -> buildPickCardPartJson(query)
 *     -> TaskSnapshot.buildTaskSnapshotWithCard(..., cardPartJson) -> hostProxy.sendData()
 *   后续（本轮只导出、不接 state 帧）: buildJumpDirective() -> uiSession.config.jump
 *
 * 协议契约（官方文档原文，别自创字段）:
 *   part = {"data":{"uiExtensionCard":{cardId,bundleName,moduleName,abilityName,payload}}}
 *   cardId / bundleName 必填；payload 必须是字符串（不是对象）。
 *   jump 只在 state 帧可用，且同一帧先 executeIntent、再 deepLink。
 *
 * 历史（docs/specs/031-xiaoyi-batch-capture-entry.md §4.9）:
 *   上一轮只发了 {uiExtensionCard:{payload:{...}}}，缺 cardId / bundleName，
 *   小艺报 1011 start_ability_fail，并对失败卡片以约 12 次/秒重试。
 *   本轮补齐必填字段，并由 AgentExtAbility 的 UI_CARD_ENABLED 开关做一次性保护。
 */

/** 卡片 id：小艺用它定位 AgentUIExtAbility 暴露的卡片 */
export const CARD_ID: string = 'mindtrace-pick';
/** 宿主应用包名 */
export const MT_BUNDLE: string = 'com.example.mindtrace';
/** 宿主 HAP 模块名 */
export const MT_MODULE: string = 'entry';
/** agentUI 扩展类名（module.json5 已注册） */
export const MT_ABILITY: string = 'AgentUIExtAbility';

/** 卡片 payload 的形状：小艺原样透传到 ability.want.params.payload */
interface PickCardPayload {
  query: string;
  source: string;
  v: number;
}

/**
 * 命中任一关键词即认为用户想拍题/选图。
 * ArkTS 禁用正则字面量，统一用 indexOf 判断。
 */
const PICK_KEYWORDS: string[] = [
  '拍题',
  '拍图',
  '拍照',
  '整理图片',
  '整理照片',
  '上传图片',
  '发图片',
  '选图',
];

export function wantsPickCard(query: string): boolean {
  for (let i = 0; i < PICK_KEYWORDS.length; i++) {
    if (query.indexOf(PICK_KEYWORDS[i]) >= 0) {
      return true;
    }
  }
  return false;
}

/**
 * 构造卡片 part（已序列化的 JSON，可直接拼进 parts[]）。
 * payload 内是 {"query":原样,"source":"xiaoyi","v":1}；外层再 JSON.stringify 一次，
 * 保证 payload 一定是字符串（官方要求），引号/换行由 JSON.stringify 转义。
 */
export function buildPickCardPartJson(query: string): string {
  const payload: PickCardPayload = {
    query: query,
    source: 'xiaoyi',
    v: 1,
  };
  const payloadJson: string = JSON.stringify(payload);
  return '{"data":{"uiExtensionCard":{"cardId":"' + CARD_ID
    + '","bundleName":"' + MT_BUNDLE
    + '","moduleName":"' + MT_MODULE
    + '","abilityName":"' + MT_ABILITY
    + '","payload":' + JSON.stringify(payloadJson) + '}}}';
}

/**
 * 构造 jump 指令（state 帧用法）。本轮只导出、不接：
 * 两种跳转可共存，客户端先 executeIntent，再 deepLink 兜底。
 */
export function buildJumpDirective(): string {
  return '{"data":{"jump":{"executeIntent":{"bundleName":"' + MT_BUNDLE
    + '","intentName":"com.example.mindtrace.PICK","executeMode":"foreground"},'
    + '"deepLink":{"url":"mindtrace://pick","appName":"MindTrace","appPackage":"'
    + MT_BUNDLE + '"}}}}';
}
