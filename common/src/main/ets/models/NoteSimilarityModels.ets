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

/** 灰区仲裁：确定性规则拿不准时，用模型判断两条笔记是否同一道题。 */
export interface NoteSimilarityJudgePort {
  isSameNote(leftTitle: string, leftContent: string, rightTitle: string, rightContent: string): Promise<boolean>;
}
