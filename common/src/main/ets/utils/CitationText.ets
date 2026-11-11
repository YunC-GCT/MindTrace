/**
 * CitationText.ets — 引用标记的展示清洗（纯函数，无 IO）
 *
 * 路径: common/src/main/ets/utils/CitationText.ets
 * 职责: 从用户可见文本里去掉内部引用标记 `[noteId=... version=...]`。
 *       引用校验仍在证据层完成，这里只影响展示。
 * 依赖: 无。
 */
export function stripCitationMarkers(text: string): string {
  const complete: string = text.replace(/\[noteId=[^\]]*\]\s*/g, '');
  // 流式过程中可能只到达半个标记（`[noteId=...` 还没闭合），先隐藏尾部残片。
  return complete.replace(/\[noteId=[^\]]*$/, '');
}
