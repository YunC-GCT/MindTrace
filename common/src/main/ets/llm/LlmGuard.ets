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
  /** 非 JSON 回复里救回来的字段值；正常 JSON 路径为空串。 */
  salvaged?: string;
  /** 救回方式：plain_text / multi_object / truncated。 */
  salvageMode?: string;
}

/** 救回结果的内部载体（不对外导出）。 */
interface LlmGuardSalvage {
  text: string;
  mode: string;
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
  /** 本次调用的额外重试次数；缺省保持 2（App 内聊天），A2A 显式传 0。 */
  maxRetries?: number;
  label?: string;
  /**
   * 允许从"模型没按 JSON 回"的原文里救回这个字段（聊天回复传 'answer'）。
   * 只给对话回复开：结构化链路（笔记生成等）一旦开，半成品会被当成成品落库。
   */
  salvageKey?: string;
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
      // 同一个 token 贯穿 guard/client：deadline 取消后立刻停止，不再发起下一次尝试。
      options.cancellationToken?.throwIfCancelled();
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

    const salvageKey: string = options.salvageKey !== undefined ? options.salvageKey : '';
    if (salvageKey.length > 0) {
      const rescue: LlmGuardSalvage = this.salvageValue(raw, salvageKey);
      if (rescue.text.length > 0) {
        const recovered: Record<string, Object> = {};
        recovered[salvageKey] = rescue.text;
        return {
          raw: raw,
          json: recovered,
          attempts: attempt + 1,
          issues: issues,
          salvaged: rescue.text,
          salvageMode: rescue.mode,
        };
      }
    }
    throw new Error(label + ' validation failed after ' + (attempt + 1).toString() + ' attempt(s): ' + issues.join('; '));
  }

  /**
   * 模型偶尔不按 JSON 回（纯文本、多个对象、被截断）。对话回复能直接渲染原文，
   * 所以这里尽力把 answer 捞回来；结构化链路不开 salvageKey 就仍然抛错。
   */
  private salvageValue(raw: string, key: string): LlmGuardSalvage {
    const text: string = LlmGuard.unwrapFence(raw);
    const candidates: LlmGuardJsonCandidate[] = this.scanJsonObjectCandidates(text);
    let index: number = 0;
    while (index < candidates.length) {
      const candidate: LlmGuardJsonCandidate = candidates[index];
      index += 1;
      if (!candidate.parseable || candidate.object === undefined) {
        continue;
      }
      const value: Object | undefined = candidate.object[key];
      if (typeof value === 'string' && (value as string).trim().length > 0) {
        const mode: string = candidates.length > 1 ? 'multi_object' : 'object';
        return { text: value as string, mode: mode };
      }
    }
    const truncated: string = LlmGuard.salvageTruncatedValue(text, key);
    if (truncated.length > 0) {
      return { text: truncated, mode: 'truncated' };
    }
    if (text.indexOf('{') < 0) {
      const plain: string = LlmGuard.stripOuterQuotes(text.trim());
      if (plain.length > 0) {
        return { text: plain, mode: 'plain_text' };
      }
    }
    return { text: '', mode: 'none' };
  }

  private static unwrapFence(raw: string): string {
    const open: number = raw.indexOf('```');
    if (open < 0) {
      return raw;
    }
    const bodyStart: number = raw.indexOf('\n', open);
    const close: number = raw.lastIndexOf('```');
    if (bodyStart < 0 || close <= bodyStart) {
      return raw.substring(open + 3);
    }
    return raw.substring(bodyStart + 1, close);
  }

  /** 从被截断的 JSON 里捞 "key": "已生成的部分"，转义按 JSON 规则还原。 */
  private static salvageTruncatedValue(text: string, key: string): string {
    const marker: string = '\"' + key + '\"';
    const keyAt: number = text.indexOf(marker);
    if (keyAt < 0) {
      return '';
    }
    const colon: number = text.indexOf(':', keyAt + marker.length);
    if (colon < 0) {
      return '';
    }
    const quote: number = text.indexOf('\"', colon + 1);
    if (quote < 0) {
      return '';
    }
    let out: string = '';
    let escaping: boolean = false;
    for (let i: number = quote + 1; i < text.length; i += 1) {
      const ch: string = text[i];
      if (escaping) {
        escaping = false;
        if (ch === 'n') {
          out += '\n';
        } else if (ch === 't') {
          out += '\t';
        } else if (ch === 'r') {
          continue;
        } else if (ch === 'u') {
          const code: number = Number.parseInt(text.substring(i + 1, i + 5), 16);
          if (!Number.isNaN(code)) {
            out += String.fromCharCode(code);
            i += 4;
          }
        } else {
          out += ch;
        }
        continue;
      }
      if (ch === '\\') {
        escaping = true;
        continue;
      }
      if (ch === '\"') {
        break;
      }
      out += ch;
    }
    return out.trim();
  }

  private static stripOuterQuotes(text: string): string {
    if (text.length >= 2 && text.startsWith('\"') && text.endsWith('\"')) {
      return text.substring(1, text.length - 1).trim();
    }
    return text;
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
      cancellationToken: options.cancellationToken,
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
