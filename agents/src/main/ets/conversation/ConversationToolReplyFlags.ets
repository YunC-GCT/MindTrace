/**
 * ConversationToolReplyFlags.ets — Chat 工具回复开关（spec 041 / 044 后续）
 *
 * 路径: agents/src/main/ets/conversation/ConversationToolReplyFlags.ets
 * 职责: 控制 conversation workflow 是否走 tool_reply 节点（ToolLoop + ToolCatalog 只读工具）。
 *       默认开启，但只有明确的「查/复习我的笔记」意图才触发；普通知识问答继续走流式回复，
 *       避免为了工具能力把首字延迟从 ~800ms 拉长到整包返回。
 * 依赖: 无。
 */
export const CHAT_TOOL_REPLY_ENABLED: boolean = true;

// 只有这些意图才值得放弃流式：用户在问「我保存过什么」，而不是通用数学知识。
const NOTE_TOOL_KEYWORDS: string[] = [
  '笔记', '知识库', '错题', '复习', '我保存', '保存过', '我记得', '之前记', '查一下我', '找一下我',
];

export class ConversationToolReplyFlags {
  private static enabled: boolean = CHAT_TOOL_REPLY_ENABLED;

  static isEnabled(): boolean {
    return ConversationToolReplyFlags.enabled;
  }

  /** 仅 e2e / 灰度验证使用；生产默认由 CHAT_TOOL_REPLY_ENABLED 决定。 */
  static setEnabled(value: boolean): void {
    ConversationToolReplyFlags.enabled = value;
  }

  /** 意图闸门：命中笔记检索关键词才走非流式工具链。 */
  static shouldUseTools(userContent: string): boolean {
    const text: string = userContent.trim();
    if (text.length === 0) {
      return false;
    }
    for (let i = 0; i < NOTE_TOOL_KEYWORDS.length; i += 1) {
      if (text.indexOf(NOTE_TOOL_KEYWORDS[i]) >= 0) {
        return true;
      }
    }
    return false;
  }
}
