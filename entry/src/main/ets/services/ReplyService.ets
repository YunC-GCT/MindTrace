/**
 * ReplyService.ets — LLM 流式回复 + 非流式回退
 *
 * 路径: entry/src/main/ets/services/ReplyService.ets
 * 职责: 封装 chat 流的 SSE 解析和 fallback,提供 complete 与 stream 两种回复路径
 * 依赖: common ContentProtocol/LlmClient/LlmGuard/Logger; ./IntentClassifier
 *
 * 数据流:
 *   ConversationWorkflow → ReplyService.stream/complete → LlmClient
 *
 * ArkTS 1.1 strict 适配:
 *   - 所有 async 方法都明确 Promise<...> 返回类型
 *   - 日志仅含 run/draft/lengths 元数据,不打印正文
 */
import {
  ContentProtocol,
  LlmClient,
  LlmGuard,
  LlmError,
  Logger,
} from 'common';
import type {
  ContentValidationResult,
  LlmGuardJsonResult,
  LlmGuardValidationResult,
  StreamEvent,
  CancellationToken,
} from 'common';
import { IntentClassifier, ReplyContext } from './IntentClassifier';
import type { ReplyStyle } from './ReplyStyleRules';
import { DebugFaults } from './DebugFaults';
import type { DebugFault } from './DebugFaults';

const replyLog: Logger = new Logger('ReplyService');
const CHAT_REPLY_MAX_TOKENS: number = 12000;
const CHAT_REPLY_TIMEOUT_MS: number = 120000;
const CHAT_REPLY_MAX_RETRIES: number = 2;
const STREAM_FAILURE_THRESHOLD: number = 2;

/**
 * 单次 complete 调用的预算覆盖（只影响本次调用，不改 LlmGuard/LlmClient 默认值）。
 * A2A 走 25 s / 0 retry / 4096 output；App 内聊天继续用 CHAT_REPLY_POLICY。
 */
export interface LlmCallPolicy {
  maxTokens: number;
  timeoutMs: number;
  maxRetries: number;
  /** 可选：本次调用的模型覆盖（A2A 显式降级到 catalog 默认时使用）。 */
  model?: string;
}

/** App 内聊天默认策略：120000 ms / 2 retry 保持不变（计划 §4.2 末段）。 */
export const CHAT_REPLY_POLICY: LlmCallPolicy = {
  maxTokens: CHAT_REPLY_MAX_TOKENS,
  timeoutMs: CHAT_REPLY_TIMEOUT_MS,
  maxRetries: CHAT_REPLY_MAX_RETRIES,
};

export interface StreamReplyResult {
  content: string;
  interrupted: boolean;
  usedFallback: boolean;
}

export type ReplyEventSink = (event: StreamEvent) => void;

export class ReplyService {
  private readonly intentClassifier: IntentClassifier;
  private readonly contentProtocol: ContentProtocol = new ContentProtocol();
  // 进程内流式熔断: 连续传输层失败达到阈值后, 本进程后续 stream() 跳过 SSE 直接走非流式 fallback。
  private static streamTransportFailures: number = 0;
  private static streamDisabled: boolean = false;

  constructor(intentClassifier: IntentClassifier) {
    this.intentClassifier = intentClassifier;
  }

  async complete(
    context: ReplyContext,
    cancellationToken?: CancellationToken,
    policy?: LlmCallPolicy,
    style: ReplyStyle = 'markdown',
  ): Promise<string> {
    return await this.guardedComplete(context, 'chat answer', cancellationToken, policy, style);
  }

  private async guardedComplete(
    context: ReplyContext,
    label: string,
    cancellationToken?: CancellationToken,
    policy?: LlmCallPolicy,
    style: ReplyStyle = 'markdown',
  ): Promise<string> {
    cancellationToken?.throwIfCancelled();
    const effectivePolicy: LlmCallPolicy = policy !== undefined ? policy : CHAT_REPLY_POLICY;
    const userContentLen: number = context.userContent.length;
    const memoryLen: number = context.memoryContext.length;
    const evidenceLen: number = context.evidenceContext.length;
    replyLog.info('[ReplyCtx] userContentLen=' + userContentLen.toString()
      + ' memoryLen=' + memoryLen.toString()
      + ' evidenceLen=' + evidenceLen.toString()
      + ' timeoutMs=' + effectivePolicy.timeoutMs.toString()
      + ' maxRetries=' + effectivePolicy.maxRetries.toString()
      + ' maxTokens=' + effectivePolicy.maxTokens.toString());
    if (userContentLen === 0) {
      replyLog.warn('[ReplyCtx] WARN empty userContent');
    }
    const guarded: LlmGuardJsonResult = await new LlmGuard().callJsonWithRetry(
      this.intentClassifier.buildReplyMessages(context, style),
      {
        maxTokens: effectivePolicy.maxTokens,
        timeoutMs: effectivePolicy.timeoutMs,
        maxRetries: effectivePolicy.maxRetries,
        model: effectivePolicy.model,
        // 小艺链路的预算是按「不思考」算的（25s 内层 / 35s deadline）：
        // ModelSpec 默认值（DeepSeek 官方默认开思考）不能接管这里。
        enableThinking: false,
        label: label,
        // 聊天回复能直接渲染原文：模型偶尔不按 JSON 回（纯文本/多个对象/被截断），
        // 与其把整条回复变成「模型暂时不可用」，不如把 answer 捞回来。
        // 只在这一条链路上开；笔记生成等结构化调用不开。
        salvageKey: 'answer',
        cancellationToken: cancellationToken,
      },
      (json: Record<string, Object>): LlmGuardValidationResult => this.validateChatAnswerJson(json),
    );
    const answerValue: Object | undefined = guarded.json['answer'];
    const answer: string = typeof answerValue === 'string' ? answerValue : '';
    const salvaged: string = guarded.salvaged !== undefined ? guarded.salvaged : '';
    if (salvaged.length > 0) {
      replyLog.warn('[ReplyCtx] json salvage mode=' + (guarded.salvageMode ?? 'unknown')
        + ' chars=' + salvaged.length.toString() + ' issues=' + guarded.issues.join('; '));
    }
    replyLog.info('complete attempts=' + guarded.attempts.toString());
    return this.normalize(answer);
  }

  async stream(
    context: ReplyContext,
    sink: ReplyEventSink,
    cancellationToken?: CancellationToken,
  ): Promise<StreamReplyResult> {
    cancellationToken?.throwIfCancelled();
    // #224 调试注入: 首次调用懒加载档位; 'none' 时下面所有返回原样透传。
    await DebugFaults.load();
    if (ReplyService.streamDisabled) {
      replyLog.warn('[StreamCircuit] open, skip SSE');
      return this.applyDebugFault(await this.fallback(context, cancellationToken));
    }
    const client: LlmClient = new LlmClient();
    let content: string = '';
    let receivedEvent: boolean = false;
    let thinkingEvents: number = 0;
    let thinkingChars: number = 0;
    let textEvents: number = 0;
    let textChars: number = 0;
    let streamAttempts: number = 0;
    try {
      while (streamAttempts < 2) {
        try {
          // 聊天首字节优先: 显式关闭思考。不能依赖 LlmClient 的默认值——
          // 默认值现在来自该型号的 ModelSpec（DeepSeek 官方默认是开启思考），
          // 不传就会把首字节拖成思考档。思考模式只留给显式传 enableThinking: true 的调用方。
          await client.call({
            messages: this.intentClassifier.buildStreamingReplyMessages(context),
            stream: true,
            enableThinking: false,
            onDelta: (event: StreamEvent): void => {
              cancellationToken?.throwIfCancelled();
              receivedEvent = true;
              if (event.type === 'thinking') {
                thinkingEvents += 1;
                thinkingChars += event.delta.length;
              } else if (event.type === 'text') {
                textEvents += 1;
                textChars += event.delta.length;
                content += event.delta;
              }
              sink(event);
            },
            maxTokens: CHAT_REPLY_MAX_TOKENS,
            timeoutMs: CHAT_REPLY_TIMEOUT_MS,
            cancellationToken: cancellationToken,
          });
          if (receivedEvent) {
            ReplyService.resetTransportFailures();
          }
          break;
        } catch (e) {
          if (streamAttempts === 0 && !receivedEvent && ReplyService.isNetworkError(e)) {
            streamAttempts += 1;
            replyLog.warn('stream transport failed before first event, retrying once');
            continue;
          }
          if (e instanceof LlmError) {
            throw new LlmError(e.message, e.kind);
          }
          if (e instanceof Error) {
            throw new Error(e.message);
          }
          throw new Error(JSON.stringify(e));
        }
      }
      if (this.shouldUseFallback(content)) {
        if (!receivedEvent) {
          ReplyService.recordTransportFailure();
        }
        replyLog.warn('stream empty, using fallback');
        cancellationToken?.throwIfCancelled();
        return this.applyDebugFault(await this.fallback(context, cancellationToken));
      }
      const success: StreamReplyResult = {
        content: this.normalize(content),
        interrupted: false,
        usedFallback: false,
      };
      replyLog.info('stream completed thinkingEvents=' + thinkingEvents.toString()
        + ' thinkingChars=' + thinkingChars.toString()
        + ' textEvents=' + textEvents.toString()
        + ' textChars=' + textChars.toString());
      return this.applyDebugFault(success);
    } catch (e) {
      cancellationToken?.throwIfCancelled();
      if (receivedEvent) {
        ReplyService.resetTransportFailures();
      }
      if (receivedEvent && !this.shouldUseFallback(content)) {
        const interrupted: StreamReplyResult = {
          content: this.normalize(content),
          interrupted: true,
          usedFallback: false,
        };
        replyLog.warn('stream interrupted after chars=' + content.length.toString());
        return this.applyDebugFault(interrupted);
      }
      if (ReplyService.isTransportError(e)) {
        ReplyService.recordTransportFailure();
        if (e instanceof LlmError) {
          throw new LlmError(e.message, e.kind);
        }
        if (e instanceof Error) {
          throw new Error(e.message);
        }
        throw new Error(JSON.stringify(e));
      }
      cancellationToken?.throwIfCancelled();
      return this.applyDebugFault(await this.fallback(context, cancellationToken));
    }
  }

  /**
   * #224 调试故障注入（只在 stream() 最终返回前调用，默认 'none' 时原样返回）。
   * - empty: content 置空 + interrupted=false → ConversationWorkflow 走 reason=empty 恢复；
   * - interrupted: content 保留 + interrupted=true → 走 reason=interrupted 恢复；
   * - none: 返回原对象，生产行为不变。
   */
  private applyDebugFault(result: StreamReplyResult): StreamReplyResult {
    const fault: DebugFault = DebugFaults.current();
    if (fault === 'empty') {
      replyLog.warn('[DebugFault] injected=empty');
      const injected: StreamReplyResult = {
        content: '',
        interrupted: false,
        usedFallback: result.usedFallback,
      };
      return injected;
    }
    if (fault === 'interrupted') {
      replyLog.warn('[DebugFault] injected=interrupted');
      const injected: StreamReplyResult = {
        content: result.content,
        interrupted: true,
        // 强制走恢复分支: ConversationWorkflow 在 usedFallback && !empty 时会提前返回。
        usedFallback: false,
      };
      return injected;
    }
    return result;
  }

  normalize(content: string): string {
    const result: ContentValidationResult = this.contentProtocol.normalizeNoteMarkdown(content);
    return result.fallbackRequired ? content : result.normalizedText;
  }

  private async fallback(
    context: ReplyContext,
    cancellationToken?: CancellationToken,
  ): Promise<StreamReplyResult> {
    const content: string = cancellationToken === undefined
      ? await this.guardedComplete(context, 'chat answer fallback')
      : await this.guardedComplete(context, 'chat answer fallback', cancellationToken);
    const fallbackResult: StreamReplyResult = {
      content: content,
      interrupted: false,
      usedFallback: true,
    };
    replyLog.info('stream fallback completed chars=' + fallbackResult.content.length.toString());
    return fallbackResult;
  }

  private shouldUseFallback(content: string): boolean {
    return content.trim().length === 0;
  }

  private static isNetworkError(e: Object): boolean {
    if (e instanceof LlmError) {
      return e.kind === 'NETWORK_ERROR' || e.kind === 'TIMEOUT';
    }
    return false;
  }

  private static isTransportError(e: Object): boolean {
    if (e instanceof LlmError) {
      return e.kind === 'NETWORK_ERROR' || e.kind === 'TIMEOUT' || e.kind === 'STREAM_FAILED';
    }
    return false;
  }

  /** CLOSED → OPEN: 连续传输层失败达到阈值后熔断, 本进程不再发起 SSE。 */
  private static recordTransportFailure(): void {
    ReplyService.streamTransportFailures += 1;
    if (ReplyService.streamTransportFailures >= STREAM_FAILURE_THRESHOLD && !ReplyService.streamDisabled) {
      ReplyService.streamDisabled = true;
      replyLog.warn('[StreamCircuit] open consecutive=' + ReplyService.streamTransportFailures.toString()
        + ' threshold=' + STREAM_FAILURE_THRESHOLD.toString());
      return;
    }
    replyLog.warn('[StreamCircuit] transport failure consecutive=' + ReplyService.streamTransportFailures.toString());
  }

  /** 收到至少 1 个 SSE chunk 即视为传输恢复, 连续失败计数清零 (OPEN 状态不因本次调用关闭)。 */
  private static resetTransportFailures(): void {
    if (ReplyService.streamTransportFailures > 0) {
      replyLog.info('[StreamCircuit] sse chunk received, failure count reset from '
        + ReplyService.streamTransportFailures.toString() + ' to 0');
    }
    ReplyService.streamTransportFailures = 0;
  }

  private validateChatAnswerJson(json: Record<string, Object>): LlmGuardValidationResult {
    const issues: string[] = [];
    const answerValue: Object | undefined = json['answer'];
    if (typeof answerValue !== 'string' || answerValue.trim().length === 0) {
      issues.push('answer must be a non-empty string containing the final Markdown reply');
      return { ok: false, issues: issues };
    }
    const answer: string = answerValue.trim();
    if (this.hasFormulaInCodeBlock(answer)) {
      issues.push('do not wrap formulas in Markdown code fences; use $...$ or independent $$ blocks');
    }
    if (this.hasMermaidCodeBlock(answer)) {
      issues.push('Mermaid blocks are not supported in answer');
    }
    const contentResult: ContentValidationResult = this.contentProtocol.validateNoteMarkdown(answer);
    if (!contentResult.ok) {
      issues.push('answer violates MM-MD-v1: ' + contentResult.issues.join(','));
    }
    return { ok: issues.length === 0, issues: issues };
  }

  private hasFormulaInCodeBlock(text: string): boolean {
    let inCode: boolean = false;
    for (const line of text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n')) {
      const trimmed: string = line.trim();
      if (trimmed.indexOf('```') === 0) {
        inCode = !inCode;
      } else if (inCode && this.contentProtocol.hasFormulaSyntax(line)) {
        return true;
      }
    }
    return false;
  }

  private hasMermaidCodeBlock(text: string): boolean {
    for (const line of text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n')) {
      if (line.trim().toLowerCase() === '```mermaid') {
        return true;
      }
    }
    return false;
  }

}
