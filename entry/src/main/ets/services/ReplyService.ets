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
  Logger,
} from 'common';
import type {
  ContentValidationResult,
  LlmCallResult,
  LlmGuardJsonResult,
  LlmGuardValidationResult,
} from 'common';
import { IntentClassifier } from './IntentClassifier';

const replyLog: Logger = new Logger('ReplyService');

export interface StreamReplyResult {
  content: string;
  interrupted: boolean;
  usedFallback: boolean;
}

export type ReplyDeltaSink = (delta: string, kind: 'reasoning' | 'content') => void;

export class ReplyService {
  private readonly intentClassifier: IntentClassifier;
  private readonly contentProtocol: ContentProtocol = new ContentProtocol();

  constructor(intentClassifier: IntentClassifier) {
    this.intentClassifier = intentClassifier;
  }

  async complete(memoryContext: string, profileContext: string, userContent: string): Promise<string> {
    const guarded: LlmGuardJsonResult = await new LlmGuard().callJsonWithRetry(
      this.intentClassifier.buildReplyMessages(memoryContext, profileContext, userContent),
      {
        maxTokens: 4096,
        timeoutMs: 120000,
        label: 'chat answer',
        enableThinking: false,
      },
      (json: Record<string, Object>): LlmGuardValidationResult => this.validateChatAnswerJson(json),
    );
    const answerValue: Object | undefined = guarded.json['answer'];
    const answer: string = typeof answerValue === 'string' ? answerValue : '';
    return this.normalize(answer);
  }

  async stream(
    memoryContext: string,
    profileContext: string,
    userContent: string,
    sink: ReplyDeltaSink,
  ): Promise<StreamReplyResult> {
    const client: LlmClient = new LlmClient();
    let content: string = '';
    try {
      await client.call({
        messages: this.intentClassifier.buildReplyMessages(memoryContext, profileContext, userContent),
        stream: true,
        onDelta: (delta: string, kind: 'reasoning' | 'content'): void => {
          content += delta;
          sink(delta, kind);
        },
        maxTokens: 4096,
        timeoutMs: 120000,
        enableThinking: false,
      });
      if (content.trim().length === 0) {
        replyLog.warn('stream empty, using fallback');
        return await this.fallback(client, memoryContext, profileContext, userContent);
      }
      const success: StreamReplyResult = {
        content: content,
        interrupted: false,
        usedFallback: false,
      };
      replyLog.info('stream completed chars=' + content.length.toString());
      return success;
    } catch (e) {
      if (content.length > 0) {
        const interrupted: StreamReplyResult = {
          content: content,
          interrupted: true,
          usedFallback: false,
        };
        replyLog.warn('stream interrupted after chars=' + content.length.toString());
        return interrupted;
      }
      return await this.fallback(client, memoryContext, profileContext, userContent);
    }
  }

  normalize(content: string): string {
    const result: ContentValidationResult = this.contentProtocol.normalizeNoteMarkdown(content);
    return result.fallbackRequired ? content : result.normalizedText;
  }

  private async fallback(
    client: LlmClient,
    memoryContext: string,
    profileContext: string,
    userContent: string,
  ): Promise<StreamReplyResult> {
    const fallback: LlmCallResult = await client.call({
      messages: this.intentClassifier.buildReplyMessages(memoryContext, profileContext, userContent),
      maxTokens: 4096,
      timeoutMs: 120000,
      enableThinking: false,
    });
    const fallbackResult: StreamReplyResult = {
      content: fallback.text ?? '',
      interrupted: false,
      usedFallback: true,
    };
    replyLog.info('stream fallback completed chars=' + fallbackResult.content.length.toString());
    return fallbackResult;
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
