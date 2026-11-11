/**
 * EvidenceJudgePort.ets — 证据采用判定端口
 *
 * 路径: common/src/main/ets/ports/EvidenceJudgePort.ets
 * 职责: 让「候选笔记能不能回答这个问题」的判定从检索实现里独立出来，
 *       由组合根注入具体实现（当前是 LLM 判定），也可在测试里替换成桩。
 * 依赖: ./EvidencePolicy（判定行为随策略变化）。
 *
 * 约束: 端口不含 Kit、不含 IO；实现方负责超时与降级，端口只表达结果。
 *       判定失败时是否放行由策略决定——严格模式 fail-closed，其余 fail-open。
 */
import type { EvidencePolicy } from './EvidencePolicy';

export interface EvidenceCandidateRef {
  noteId: string;
  text: string;
}

export interface EvidenceJudgement {
  /** 被采用的 noteId 列表；空数组表示全部拒绝。 */
  adopted: string[];
  /** 被拒绝的候选数量。 */
  rejected: number;
  /** adopted / rejected / judge-unavailable / judge-skipped，用于日志与展示。 */
  reason: string;
}

export interface EvidenceJudgePort {
  judge(query: string, candidates: EvidenceCandidateRef[], policy: EvidencePolicy): Promise<EvidenceJudgement>;
}
