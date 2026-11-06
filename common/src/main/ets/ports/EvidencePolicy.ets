/**
 * EvidencePolicy.ets — 证据采用策略（纯数据，无 IO）
 *
 * 路径: common/src/main/ets/ports/EvidencePolicy.ets
 * 职责: 回答「这次回答允许多大程度依赖检索到的笔记」这个由用户/调用方决定的问题，
 *       而不是让检索实现自己猜。三种模式的差别只体现在两个开关上。
 * 依赖: 无。
 *
 * 背景: 用余弦、reranker 分数、词覆盖率判断「笔记里够不够」都试过，全部不可靠
 *       （见研究日志 §44）。「够不够」是意图问题，应当由调用方显式给出。
 */
export type EvidenceMode = 'strict' | 'balanced' | 'expansive';

export interface EvidencePolicy {
  mode: EvidenceMode;
  /** 是否让模型判断候选笔记能否回答；关闭时全部候选直接采用。 */
  useJudge: boolean;
  /** 没有证据时是否仍允许回答（拓展模式为 true）。 */
  allowNoEvidence: boolean;
}

/** 现状行为：判定开启、没有证据就不注入证据。 */
export function defaultEvidencePolicy(): EvidencePolicy {
  return { mode: 'balanced', useJudge: true, allowNoEvidence: false };
}

export function evidencePolicyFor(mode: EvidenceMode): EvidencePolicy {
  if (mode === 'strict') {
    // 严格模式仍然判定，但判定服务不可用时按「没找到」处理（fail-closed）。
    return { mode: 'strict', useJudge: true, allowNoEvidence: false };
  }
  if (mode === 'expansive') {
    // 拓展模式不判定、允许无证据回答，由生成侧标注补充内容。
    return { mode: 'expansive', useJudge: false, allowNoEvidence: true };
  }
  return defaultEvidencePolicy();
}
