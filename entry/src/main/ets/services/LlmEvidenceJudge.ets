/**
 * LlmEvidenceJudge.ets — 证据是否「答得上」的 LLM 判定
 *
 * 路径: entry/src/main/ets/services/LlmEvidenceJudge.ets
 * 职责: 检索出候选笔记后，让模型判断这些笔记能不能回答用户的提问。
 *       语料里没有对应主题时返回 NO，调用方据此不注入证据——
 *       拿无关片段硬答比说「没找到」危害更大。
 * 依赖: common LlmClient / LlmConfig。
 *
 * 约束:
 *   - 这是本轮唯一被证实能分开「能回答 / 答不上」的信号：
 *     余弦、reranker 分数、词覆盖率都试过，均重叠（见研究日志 §44）；
 *   - **只汇报事实，不决定策略**：`evaluate` 返回 yes/no/unavailable，
 *     放行还是拒绝交给调用方按 EvidencePolicy 决定（严格模式 fail-closed）；
 *   - 超时 1.5s，给 A2A 的 2.5s 证据预算留出余量。
 */
import { LlmClient, LlmConfig } from 'common';
import type { ChatMessage, LlmCallResult } from 'common';

const JUDGE_TIMEOUT_MS: number = 1500;
const COOLDOWN_MS: number = 60000;
const MAX_DOCS: number = 4;
const MAX_DOC_CHARS: number = 120;

const SYSTEM_PROMPT: string = '你是检索结果审核员。判断给出的笔记能否帮助回答用户的问题。'
  + '只要笔记涉及该问题的主题、包含相关概念或定理，就回答 YES，即使措辞完全不同。'
  + '只有当笔记与该问题完全无关（属于别的学科或别的话题）时才回答 NO。'
  + '只输出 YES 或 NO，不要解释。';

/** 判定结果：yes / no / unavailable（超时、未配置、解析失败、冷却中）。 */
export type EvidenceJudgeStatus = 'yes' | 'no' | 'unavailable';

export class LlmEvidenceJudge {
  private static cooldownUntil: number = 0;

  /** 判定并返回状态；任何异常都归为 unavailable，由调用方按策略决定放行还是拒绝。 */
  static async evaluate(query: string, documents: string[]): Promise<EvidenceJudgeStatus> {
    const trimmed: string = query.trim();
    if (trimmed.length === 0 || documents.length === 0 || Date.now() < LlmEvidenceJudge.cooldownUntil) {
      return 'unavailable';
    }
    const configured: boolean = await LlmConfig.getInstance().isConfigured();
    if (!configured) {
      return 'unavailable';
    }
    const lines: string[] = [];
    for (let i = 0; i < documents.length && i < MAX_DOCS; i += 1) {
      const text: string = documents[i];
      lines.push((i + 1).toString() + '. '
        + (text.length > MAX_DOC_CHARS ? text.substring(0, MAX_DOC_CHARS) : text));
    }
    const messages: ChatMessage[] = [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: '问题：' + trimmed + '\n笔记：\n' + lines.join('\n') },
    ];
    try {
      const result: LlmCallResult = await new LlmClient().call({
        messages: messages,
        temperature: 0,
        maxTokens: 8,
        timeoutMs: JUDGE_TIMEOUT_MS,
        enableThinking: false,
      });
      const text: string = (result.text !== undefined ? result.text : '').trim().toUpperCase();
      if (text.indexOf('NO') >= 0) {
        return 'no';
      }
      return 'yes';
    } catch (e) {
      LlmEvidenceJudge.cooldownUntil = Date.now() + COOLDOWN_MS;
      console.warn('evidence judge failed: ' + (e as Error).message);
      return 'unavailable';
    }
  }

  /** 兼容旧调用：不可用按「能回答」处理（fail-open）。新代码请用 evaluate + 策略。 */
  static async isAnswerable(query: string, documents: string[]): Promise<boolean> {
    const status: EvidenceJudgeStatus = await LlmEvidenceJudge.evaluate(query, documents);
    return status !== 'no';
  }
}
