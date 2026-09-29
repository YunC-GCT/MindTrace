/**
 * AgentFloatWindowLayout.ets — 对话浮窗底部停靠策略
 * 路径: entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindowLayout.ets
 * 职责: 键盘打开时与键盘上缘相接，关闭时保留原有停靠高度。
 * 依赖: 无；所有高度均为 vp。
 * 数据流: keyboardHeightChange → keyboardHeight → 浮窗 translate。
 */
const RESTING_BOTTOM_INSET: number = 74;

export function agentSheetBottomInset(keyboardHeight: number): number {
  return keyboardHeight > 0 ? keyboardHeight : RESTING_BOTTOM_INSET;
}
