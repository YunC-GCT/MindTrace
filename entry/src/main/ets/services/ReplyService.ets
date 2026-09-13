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
} from 'common';
import { IntentClassifier, ReplyContext } from './IntentClassifier';

const replyLog: Logger = new Logger('ReplyService');
const CHAT_REPLY_MAX_TOKENS: number = 12000;

export interface StreamReplyResult {
  content: string;
  interrupted: boolean;
  usedFallback: boolean;
}

export type ReplyEventSink = (event: StreamEvent) => void;

export class ReplyService {
  private readonly intentClassifier: IntentClassifier;
  private readonly contentProtocol: ContentProtocol = new ContentProtocol();

  constructor(intentClassifier: IntentClassifier) {
    this.intentClassifier = intentClassifier;
  }

  async complete(context: ReplyContext): Promise<string> {
    return await this.guardedComplete(context, 'chat answer');
  }

  private async guardedComplete(context: ReplyContext, label: string): Promise<string> {
    const guarded: LlmGuardJsonResult = await new LlmGuard().callJsonWithRetry(
      this.intentClassifier.buildReplyMessages(context),
      {
        maxTokens: CHAT_REPLY_MAX_TOKENS,
        timeoutMs: 120000,
        label: label,
      },
      (json: Record<string, Object>): LlmGuardValidationResult => this.validateChatAnswerJson(json),
    );
    const answerValue: Object | undefined = guarded.json['answer'];
    const answer: string = typeof answerValue === 'string' ? answerValue : '';
    return this.normalize(answer);
  }

  async stream(
    context: ReplyContext,
    sink: ReplyEventSink,
  ): Promise<StreamReplyResult> {
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
          await client.call({
            messages: this.intentClassifier.buildStreamingReplyMessages(context),
            stream: true,
            onDelta: (event: StreamEvent): void => {
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
            timeoutMs: 120000,
          });
          break;
        } catch (e) {
          if (streamAttempts === 0 && !receivedEvent && ReplyService.isNetworkError(e)) {
            streamAttempts += 1;
            replyLog.warn('stream transport failed before first event, retrying once');
            continue;
          }
          if (e instanceof Error) {
            throw e;
          }
          throw new Error(JSON.stringify(e));
        }
      }
      if (this.shouldUseFallback(content)) {
        replyLog.warn('stream empty, using fallback');
        return await this.fallback(context);
      }
      const success: StreamReplyResult = {
        content: content,
        interrupted: false,
        usedFallback: false,
      };
      replyLog.info('stream completed thinkingEvents=' + thinkingEvents.toString()
        + ' thinkingChars=' + thinkingChars.toString()
        + ' textEvents=' + textEvents.toString()
        + ' textChars=' + textChars.toString());
      return success;
    } catch (e) {
      if (receivedEvent && !this.shouldUseFallback(content)) {
        const interrupted: StreamReplyResult = {
          content: content,
          interrupted: true,
          usedFallback: false,
        };
        replyLog.warn('stream interrupted after chars=' + content.length.toString());
        return interrupted;
      }
      if (ReplyService.isTransportError(e)) {
        if (e instanceof Error) {
          throw e;
        }
        throw new Error(JSON.stringify(e));
      }
      return await this.fallback(context);
    }
  }

  normalize(content: string): string {
    const result: ContentValidationResult = this.contentProtocol.normalizeNoteMarkdown(content);
    return result.fallbackRequired ? content : result.normalizedText;
  }

  private async fallback(
    context: ReplyContext,
  ): Promise<StreamReplyResult> {
    const content: string = await this.guardedComplete(context, 'chat answer fallback');
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
