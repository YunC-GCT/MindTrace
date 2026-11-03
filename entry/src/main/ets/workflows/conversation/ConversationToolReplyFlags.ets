/**
 * ConversationToolReplyFlags.ets — Chat 工具回复开关（spec 041）
 *
 * 路径: entry/src/main/ets/workflows/conversation/ConversationToolReplyFlags.ets
 * 职责: 控制 conversation workflow 是否走 tool_reply 节点（ToolLoop + ToolCatalog 只读工具）。
 *       默认 false：行为与现有 ReplyService 完全一致；开启前需真机验证工具调用与结果展示。
 * 依赖: 无。
 */
export const CHAT_TOOL_REPLY_ENABLED: boolean = false;

export class ConversationToolReplyFlags {
  private static enabled: boolean = CHAT_TOOL_REPLY_ENABLED;

  static isEnabled(): boolean {
    return ConversationToolReplyFlags.enabled;
  }

  /** 仅 e2e / 灰度验证使用；生产默认由 CHAT_TOOL_REPLY_ENABLED 决定。 */
  static setEnabled(value: boolean): void {
    ConversationToolReplyFlags.enabled = value;
  }
}
