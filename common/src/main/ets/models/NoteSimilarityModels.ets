/**
 * NoteSimilarityModels.ets — 相似度候选与仲裁契约（纯模型，无 IO）
 *
 * 路径: common/src/main/ets/models/NoteSimilarityModels.ets
 * 职责: 写入查重时跨层传递的候选笔记形状，以及灰区语义仲裁端口。
 * 依赖: 无。
 */
export interface NoteSimilarityCandidate {
  id: string;
  title: string;
  content: string;
}

/**
 * 仲裁结论：
 * - same：同一道题 / 同一知识点，且没有实质新内容 → 拦下，不重复写入
 * - supplement：同一主题，但新笔记有已有笔记没有的内容 → 照常写入，另发合并建议
 * - different：不同主题 → 照常写入
 */
export type NoteSimilarityVerdictKind = 'same' | 'supplement' | 'different';

export interface NoteSimilarityVerdict {
  kind: NoteSimilarityVerdictKind;
  /** 一句话理由，用于日志与后续展示。 */
  reason: string;
}

/**
 * 灰区仲裁：确定性规则拿不准时，让模型判断两条笔记是什么关系。
 * 由模型自己决定「要不要拦」——同题且无用新信息才拦，同题但有补充则放行并建议合并。
 */
export interface NoteSimilarityJudgePort {
  judge(leftTitle: string, leftContent: string, rightTitle: string, rightContent: string): Promise<NoteSimilarityVerdict>;
}
