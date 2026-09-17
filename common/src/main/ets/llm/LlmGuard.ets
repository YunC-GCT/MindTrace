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

export interface LlmGuardJsonCandidate {
  index: number;
  start: number;
  end: number;
  text: string;
  parseable: boolean;
  parseError?: string;
  object?: Record<string, Object>;
}

export interface LlmGuardJsonExtractionResult {
  success: boolean;
  jsonText: string;
  candidates: LlmGuardJsonCandidate[];
  category: string;
  detail: string;
  preview: string;
}

export type LlmJsonValidator = (json: Record<string, Object>) => LlmGuardValidationResult;

export interface LlmGuardJsonOptions extends LlmCallOptions {
  maxRetries?: number;
  label?: string;
}

const DEFAULT_MAX_RETRIES: number = 2;
const DEFAULT_JSON_PREVIEW_LIMIT: number = 180;

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
    return this.extractJsonObjectWithDetails(raw).jsonText;
  }

  extractJsonObjectWithDetails(raw: string, previewLimit: number = DEFAULT_JSON_PREVIEW_LIMIT): LlmGuardJsonExtractionResult {
    const candidates: LlmGuardJsonCandidate[] = this.scanJsonObjectCandidates(raw);
    const preview: string = this.safePreview(raw, previewLimit);
    if (candidates.length === 0) {
      const trimmed: string = raw.trim();
      let category: string = 'missing';
      let detail: string = 'none';
      if (trimmed.startsWith('[') || trimmed === 'null' || trimmed === 'true' || trimmed === 'false'
        || this.startsWithNumber(trimmed) || trimmed.startsWith('"')) {
        category = 'non_object';
        detail = 'top_level_not_object';
      } else if (trimmed.indexOf('{') >= 0) {
        category = 'truncated';
        detail = 'incomplete_object';
      }
      return {
        success: false,
        jsonText: '',
        candidates: candidates,
        category: category,
        detail: detail,
        preview: preview,
      };
    }
    if (candidates.length > 1) {
      return {
        success: false,
        jsonText: '',
        candidates: candidates,
        category: 'ambiguous',
        detail: 'multiple',
        preview: preview,
      };
    }
    const candidate: LlmGuardJsonCandidate = candidates[0];
    if (!candidate.parseable) {
      return {
        success: false,
        jsonText: '',
        candidates: candidates,
        category: 'parse_error',
        detail: candidate.parseError ?? 'invalid_json',
        preview: preview,
      };
    }
    return {
      success: true,
      jsonText: candidate.text,
      candidates: candidates,
      category: 'ok',
      detail: 'single',
      preview: preview,
    };
  }

  scanJsonObjectCandidates(raw: string): LlmGuardJsonCandidate[] {
    const candidates: LlmGuardJsonCandidate[] = [];
    let objectDepth: number = 0;
    let arrayDepth: number = 0;
    let start: number = -1;
    let inString: boolean = false;
    let escaping: boolean = false;
    for (let index: number = 0; index < raw.length; index += 1) {
      const ch: string = raw[index];
      if (inString) {
        if (escaping) {
          escaping = false;
        } else if (ch === '\\') {
          escaping = true;
        } else if (ch === '"') {
          inString = false;
        }
        continue;
      }
      if (ch === '"') {
        inString = true;
        continue;
      }
      if (objectDepth === 0) {
        if (ch === '[') {
          arrayDepth += 1;
          continue;
        }
        if (ch === ']' && arrayDepth > 0) {
          arrayDepth -= 1;
          continue;
        }
      }
      if (ch === '{') {
        if (objectDepth === 0 && arrayDepth === 0) {
          start = index;
        }
        objectDepth += 1;
      } else if (ch === '}' && objectDepth > 0) {
        objectDepth -= 1;
        if (objectDepth === 0 && start >= 0) {
          const text: string = raw.substring(start, index + 1);
          candidates.push(this.buildJsonCandidate(candidates.length, start, index + 1, text));
          start = -1;
        }
      }
    }
    return candidates;
  }

  private parseAndValidate(
    raw: string,
    attempts: number,
    validator: LlmJsonValidator,
  ): LlmGuardJsonResult {
    const extraction: LlmGuardJsonExtractionResult = this.extractJsonObjectWithDetails(raw);
    if (!extraction.success) {
      return {
        raw: raw,
        json: {},
        attempts: attempts,
        issues: [this.formatJsonExtractionFailure('JSON object', extraction)],
      };
    }
    const jsonText: string = extraction.jsonText;
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
      enableThinking: options.enableThinking,
    };
    return request;
  }

  private buildJsonCandidate(index: number, start: number, end: number, text: string): LlmGuardJsonCandidate {
    try {
      const parsed: Object = JSON.parse(text) as Object;
      if (parsed === null || Array.isArray(parsed) || typeof parsed !== 'object') {
        return {
          index: index,
          start: start,
          end: end,
          text: text,
          parseable: false,
          parseError: 'non_object',
        };
      }
      return {
        index: index,
        start: start,
        end: end,
        text: text,
        parseable: true,
        object: parsed as Record<string, Object>,
      };
    } catch (e) {
      return {
        index: index,
        start: start,
        end: end,
        text: text,
        parseable: false,
        parseError: (e as Error).message ?? String(e),
      };
    }
  }

  private formatJsonExtractionFailure(label: string, extraction: LlmGuardJsonExtractionResult): string {
    return label + ' extraction failed: category=' + extraction.category
      + ', candidates=' + extraction.candidates.length.toString()
      + ', detail=' + extraction.detail
      + ', preview=' + extraction.preview;
  }

  private safePreview(raw: string, limit: number): string {
    const compact: string = raw.replace(new RegExp('[\\r\\n\\t]+', 'g'), ' ').trim();
    let preview: string = compact.length > limit ? compact.substring(0, limit) : compact;
    preview = preview.split('sk-').join('sk-***');
    preview = preview.split('Bearer ').join('Bearer ***');
    return preview;
  }

  private startsWithNumber(text: string): boolean {
    if (text.length === 0) {
      return false;
    }
    const code: number = text.charCodeAt(0);
    return (code >= 48 && code <= 57) || text.startsWith('-');
  }
}
