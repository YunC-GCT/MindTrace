import { LlmClient } from './LlmClient';
import { buildGuardRetryMessage } from './LlmOutputRules';
import type { ChatMessage, LlmCallOptions, LlmCallRequest, LlmCallResult } from './LlmTypes';

export interface LlmCaller {
  call(request: LlmCallRequest): Promise<LlmCallResult>;
}

export interface LlmGuardValidationResult {
  ok: boolean;
  issues: string[];
}

export interface LlmGuardJsonResult {
  raw: string;
  json: Record<string, Object>;
  attempts: number;
  issues: string[];
}

export type LlmJsonValidator = (json: Record<string, Object>) => LlmGuardValidationResult;

export interface LlmGuardJsonOptions extends LlmCallOptions {
  maxRetries?: number;
  label?: string;
}

const DEFAULT_MAX_RETRIES: number = 2;

export class LlmGuard {
  private client: LlmCaller;

  constructor(client?: LlmCaller) {
    this.client = client ?? new LlmClient();
  }

  async callJsonWithRetry(
    messages: ChatMessage[],
    options: LlmGuardJsonOptions,
    validator: LlmJsonValidator,
  ): Promise<LlmGuardJsonResult> {
    const maxRetries: number = options.maxRetries !== undefined ? options.maxRetries : DEFAULT_MAX_RETRIES;
    const label: string = options.label !== undefined && options.label.length > 0 ? options.label : 'LLM JSON';
    const guardedMessages: ChatMessage[] = messages.slice(0);
    let issues: string[] = [];
    let raw: string = '';
    let attempt: number = 0;

    while (attempt <= maxRetries) {
      const callResult: LlmCallResult = await this.client.call(this.toCallRequest(guardedMessages, options));
      raw = callResult.text ?? '';
      const parsed: LlmGuardJsonResult = this.parseAndValidate(raw, attempt + 1, validator);
      if (parsed.issues.length === 0) {
        return parsed;
      }
      issues = parsed.issues;
      if (attempt >= maxRetries) {
        break;
      }
      guardedMessages.push({ role: 'assistant', content: raw });
      guardedMessages.push(buildGuardRetryMessage(label, issues));
      attempt += 1;
    }

    throw new Error(label + ' validation failed after retry: ' + issues.join('; '));
  }

  validateJsonText(raw: string, validator: LlmJsonValidator): LlmGuardJsonResult {
    return this.parseAndValidate(raw, 1, validator);
  }

  extractJsonObject(raw: string): string {
    const trimmed: string = raw.trim();
    const codeMatch: RegExpMatchArray | null = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
    let source: string = trimmed;
    if (codeMatch !== null && codeMatch.length >= 2) {
      source = codeMatch[1].trim();
    }
    const braceMatch: RegExpMatchArray | null = source.match(/\{[\s\S]*\}/);
    if (braceMatch !== null && braceMatch.length > 0) {
      return braceMatch[0];
    }
    return '';
  }

  private parseAndValidate(
    raw: string,
    attempts: number,
    validator: LlmJsonValidator,
  ): LlmGuardJsonResult {
    const jsonText: string = this.extractJsonObject(raw);
    if (jsonText.length === 0) {
      return {
        raw: raw,
        json: {},
        attempts: attempts,
        issues: ['missing_json_object'],
      };
    }
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(jsonText) as Record<string, Object>;
    } catch (e) {
      return {
        raw: raw,
        json: {},
        attempts: attempts,
        issues: ['invalid_json: ' + ((e as Error).message ?? String(e))],
      };
    }
    const validation: LlmGuardValidationResult = validator(parsed);
    return {
      raw: raw,
      json: parsed,
      attempts: attempts,
      issues: validation.ok ? [] : validation.issues,
    };
  }

  private toCallRequest(messages: ChatMessage[], options: LlmGuardJsonOptions): LlmCallRequest {
    const request: LlmCallRequest = {
      messages: messages,
      temperature: options.temperature,
      maxTokens: options.maxTokens,
      model: options.model,
      timeoutMs: options.timeoutMs,
      responseFormat: options.responseFormat ?? { type: 'json_object' },
    };
    return request;
  }
}
