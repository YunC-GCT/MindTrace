/**
 * AppIntentRouter.ets — App 内 agent 意图路由（规则优先 + LLM 兜底 + 低置信追问）
 *
 * 路径: entry/src/main/ets/services/AppIntentRouter.ets
 * 职责: 统一 App 对话（文字/图片）的意图判定：先走 AppIntentRules 本地规则；
 *       规则无法判定时，用 LLM 返回 {intent,confidence,reason}（LlmGuard 校验），
 *       置信度 <0.6 转 clarify；LLM 不可用/失败回退 chat（不误触发写笔记）。
 * 依赖: AppIntentRules、common LlmGuard / LlmConfig / ChatMessage。
 */
import { ChatMessage, LlmConfig, LlmGuard } from 'common';
import type { CancellationToken, LlmGuardValidationResult } from 'common';
import {
  AppIntentDecision,
  buildAppIntentPrompt,
  classifyAppIntentLocal,
  parseAppIntentJson,
  validateAppIntentJson,
} from './AppIntentRules';

const INTENT_LLM_TIMEOUT_MS: number = 20000;
const INTENT_LLM_MAX_TOKENS: number = 120;

export class AppIntentRouter {
  // 懒加载：构造时不实例化 LlmGuard（工作流单测会 mock common，构造期不应触发 kit 依赖）。
  private guard: LlmGuard | null = null;

  constructor(guard?: LlmGuard) {
    this.guard = guard !== undefined ? guard : null;
  }

  private resolveGuard(): LlmGuard | null {
    if (this.guard === null) {
      try {
        this.guard = new LlmGuard();
      } catch (e) {
        return null;
      }
    }
    return this.guard;
  }

  /** 两阶段判定：规则命中即返回；否则 LLM；LLM 失败回退 chat。 */
  async classify(text: string, hasImage: boolean, cancellationToken?: CancellationToken): Promise<AppIntentDecision> {
    const local: AppIntentDecision | undefined = classifyAppIntentLocal(text, hasImage);
    if (local !== undefined) {
      AppIntentRouter.trace(local, hasImage);
      return local;
    }
    try {
      const guard: LlmGuard | null = this.resolveGuard();
      if (guard === null) {
        const fallback: AppIntentDecision = { kind: 'chat', source: 'fallback', confidence: 0.3, reason: 'guard-unavailable' };
        AppIntentRouter.trace(fallback, hasImage);
        return fallback;
      }
      const configured: boolean = await LlmConfig.getInstance().isConfigured();
      if (!configured) {
        const fallback: AppIntentDecision = { kind: 'chat', source: 'fallback', confidence: 0.3, reason: 'llm-not-configured' };
        AppIntentRouter.trace(fallback, hasImage);
        return fallback;
      }
      const messages: ChatMessage[] = [
        { role: 'system', content: buildAppIntentPrompt() },
        { role: 'user', content: (hasImage ? '[用户附了一张图片] ' : '') + text },
      ];
      const result = await guard.callJsonWithRetry(messages, {
        maxTokens: INTENT_LLM_MAX_TOKENS,
        timeoutMs: INTENT_LLM_TIMEOUT_MS,
        responseFormat: { type: 'json_object' },
        label: 'app intent classification',
        cancellationToken: cancellationToken,
      }, (json: Record<string, Object>): LlmGuardValidationResult => {
        const issues: string[] = validateAppIntentJson(json);
        const result: LlmGuardValidationResult = { ok: issues.length === 0, issues: issues };
        return result;
      });
      const decision: AppIntentDecision = parseAppIntentJson(result.json);
      AppIntentRouter.trace(decision, hasImage);
      return decision;
    } catch (e) {
      cancellationToken?.throwIfCancelled();
      const fallback: AppIntentDecision = { kind: 'chat', source: 'fallback', confidence: 0.3, reason: 'llm-failed' };
      AppIntentRouter.trace(fallback, hasImage);
      return fallback;
    }
  }

  private static trace(decision: AppIntentDecision, hasImage: boolean): void {
    console.info('[AppIntent] kind=' + decision.kind + ' source=' + decision.source
      + ' confidence=' + decision.confidence.toString()
      + ' hasImage=' + (hasImage ? '1' : '0') + ' reason=' + decision.reason);
  }
}
