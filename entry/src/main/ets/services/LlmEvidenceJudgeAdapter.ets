/**
 * LlmEvidenceJudgeAdapter.ets — 把 LLM 判定适配成 EvidenceJudgePort
 *
 * 路径: entry/src/main/ets/services/LlmEvidenceJudgeAdapter.ets
 * 职责: 把 `LlmEvidenceJudge.evaluate` 的 yes/no/unavailable 翻译成端口的
 *       adopted/rejected 结果，并按策略决定「判定不可用时放行还是拒绝」。
 * 依赖: common（EvidenceJudgePort / EvidencePolicy）、./LlmEvidenceJudge。
 *
 * 约束: 策略只在适配器里解释一次——严格模式 fail-closed，其余 fail-open，
 *       与 §44 的实测结论保持一致。
 */
import type {
  EvidenceCandidateRef,
  EvidenceJudgePort,
  EvidenceJudgement,
  EvidencePolicy,
} from 'common';
import { EvidenceJudgeStatus, LlmEvidenceJudge } from './LlmEvidenceJudge';

export class LlmEvidenceJudgeAdapter implements EvidenceJudgePort {
  async judge(query: string, candidates: EvidenceCandidateRef[],
    policy: EvidencePolicy): Promise<EvidenceJudgement> {
    if (candidates.length === 0) {
      return { adopted: [], rejected: 0, reason: 'empty' };
    }
    const ids: string[] = [];
    const documents: string[] = [];
    for (let i = 0; i < candidates.length; i += 1) {
      ids.push(candidates[i].noteId);
      documents.push(candidates[i].text);
    }
    const status: EvidenceJudgeStatus = await LlmEvidenceJudge.evaluate(query, documents);
    if (status === 'no') {
      return { adopted: [], rejected: ids.length, reason: 'rejected' };
    }
    if (status === 'unavailable') {
      // 严格模式：判定不可用就当没找到；其余模式保留证据，宁可多给也不要误拒。
      if (policy.mode === 'strict') {
        return { adopted: [], rejected: ids.length, reason: 'judge-unavailable' };
      }
      return { adopted: ids, rejected: 0, reason: 'judge-unavailable-open' };
    }
    return { adopted: ids, rejected: 0, reason: 'adopted' };
  }
}
