/**
 * GenerationJsonCaller.ets — 知识生成路径统一 JSON 调用 seam
 *
 * 路径: agents/src/main/ets/agents/GenerationJsonCaller.ets
 * 职责: 统一 KnowledgeModel 六条生成路线 (light / incremental / deep / evidence /
 *   standard / verifier) 的 LLM JSON 调用生命周期 — 传输错误包装、截断识别、
 *   JSON 候选提取与选择、schema/domain 两段校验、守门重试 (buildGuardRetryMessage)、
 *   统一 GenerationJsonError (kind + retriable + cause)
 * 依赖: common (LlmClient / LlmGuard / LlmError / buildGuardRetryMessage / TRUNCATION_MARKER)
 *
 * 数据流:
 *   KnowledgeModel 路线方法 → callJson(messages, options, schemaValidator, domainValidator?)
 *     → invokeClient (传输 LlmError → GenerationJsonError[LLM_TRANSPORT])
 *     → 截断检查 (TRUNCATION_MARKER → GenerationJsonError[LLM_TRUNCATED])
 *     → LlmGuard.extractJsonObjectWithDetails (+ 路线 candidateSelector)
 *     → schemaValidator (守门重试 → GenerationJsonError[JSON_SCHEMA_ERROR])
 *     → domainValidator (守门重试 → GenerationJsonError[DOMAIN_VALIDATION_ERROR])
 *     → 已校验 Record<string, Object> 返回, 路线自行做领域解析
 *
 * 设计要点 (spec 策略文档 §13.12):
 *   - 不改 common/LlmGuard 本体; 复用其公开提取/候选/重试消息工具
 *   - maxRetries 默认 2, 与 LlmGuard.callJsonWithRetry 对齐
 *   - candidateSelector 未命中 = 路线策略已检视全部候选 → 终止不重试
 *     (保持 standard 路线多候选 fail-fast 旧行为)
 *   - 传输错误不在本层重试 (与 LlmGuard 行为一致), retriable 交给上游决策
 *
 * ArkTS 1.1 strict 适配:
 *   - 无 any/unknown; Record 访问走 Object | undefined + Array.isArray 守卫
 *   - 候选 object 由 LlmGuard 预解析, 避免二次 JSON.parse
 */

import {
  LlmClient,
  LlmGuard,
  LlmError,
  buildGuardRetryMessage,
  TRUNCATION_MARKER,
} from 'common';
import type {
  ChatMessage,
  LlmCallRequest,
  LlmCallResult,
  LlmCaller,
  LlmGuardJsonCandidate,
  LlmGuardJsonExtractionResult,
  LlmGuardValidationResult,
  LlmJsonValidator,
  LlmResponseFormat,
} from 'common';

/** 生成路径统一错误类别 (spec §13.5 / §13.12) */
export type GenerationJsonErrorKind =
  | 'LLM_TRANSPORT'           // LlmClient 抛错 (网络/超时/配置/流中断), cause 保留原 LlmError
  | 'LLM_TRUNCATED'           // 响应被 max_tokens 截断 (TRUNCATION_MARKER)
  | 'JSON_EXTRACTION_ERROR'   // 顶层无 JSON 对象 / 多候选歧义 / 选择器未命中
  | 'JSON_PARSE_ERROR'        // 候选 JSON.parse 失败
  | 'JSON_SCHEMA_ERROR'       // schemaValidator (形状) 最终未通过
  | 'DOMAIN_VALIDATION_ERROR'; // domainValidator (领域语义) 最终未通过

/** 传输类错误中可由上游重试的 LlmErrorKind */
const TRANSPORT_RETRIABLE_KINDS: string[] = ['NETWORK_ERROR', 'TIMEOUT', 'STREAM_FAILED'];
const DEFAULT_MAX_RETRIES: number = 2;

export class GenerationJsonError extends Error {
  public kind: GenerationJsonErrorKind;
  public retriable: boolean;
  public cause?: Object;

  constructor(kind: GenerationJsonErrorKind, message: string, retriable: boolean, cause?: Object) {
    super(message);
    this.kind = kind;
    this.retriable = retriable;
    this.cause = cause;
    this.name = 'GenerationJsonError';
  }
}

/** 路线级候选选择策略: 检视全部候选后返回命中者, 未命中返回 undefined (终止) */
export type JsonCandidateSelector =
  (extraction: LlmGuardJsonExtractionResult) => LlmGuardJsonCandidate | undefined;

/** 领域语义校验: 返回 issue 描述数组, 空数组 = 通过 */
export type DomainJsonValidator = (json: Record<string, Object>) => string[];

export interface GenerationJsonCallOptions {
  label: string;
  maxTokens: number;
  timeoutMs: number;
  responseFormat?: LlmResponseFormat;
  maxRetries?: number;
  candidateSelector?: JsonCandidateSelector;
}

export class GenerationJsonCaller {
  private client: LlmCaller;
  private guard: LlmGuard;

  constructor(client?: LlmCaller, guard?: LlmGuard) {
    this.client = client ?? new LlmClient();
    this.guard = guard ?? new LlmGuard(this.client);
  }

  /**
   * 统一 JSON 调用: LLM 请求 → 截断识别 → JSON 提取/选择 → schema 校验
   * (重试) → domain 校验 (重试) → 返回已校验的解析结果。
   *
   * 终止路径 (不进入守门重试):
   *   - 传输 LlmError → GenerationJsonError(LLM_TRANSPORT, retriable 按 kind 映射)
   *   - 截断 → GenerationJsonError(LLM_TRUNCATED, retriable=false)
   *   - candidateSelector 未命中 → GenerationJsonError(JSON_EXTRACTION_ERROR, retriable=false)
   */
  async callJson(
    messages: ChatMessage[],
    options: GenerationJsonCallOptions,
    schemaValidator: LlmJsonValidator,
    domainValidator?: DomainJsonValidator,
  ): Promise<Record<string, Object>> {
    const maxRetries: number = options.maxRetries !== undefined ? options.maxRetries : DEFAULT_MAX_RETRIES;
    const label: string = options.label.length > 0 ? options.label : 'generation JSON';
    const guardedMessages: ChatMessage[] = messages.slice(0);
    let lastFailureKind: GenerationJsonErrorKind = 'JSON_EXTRACTION_ERROR';
    let lastIssues: string[] = ['no attempt made'];
    let attempt: number = 0;

    while (attempt <= maxRetries) {
      const callResult: LlmCallResult = await this.invokeClient(guardedMessages, options, label);
      const raw: string = callResult.text ?? '';
      if (raw.trim().endsWith(TRUNCATION_MARKER)) {
        throw new GenerationJsonError(
          'LLM_TRUNCATED',
          label + ' response truncated by max_tokens',
          false,
        );
      }
      const extraction: LlmGuardJsonExtractionResult = this.guard.extractJsonObjectWithDetails(raw);
      const candidate: LlmGuardJsonCandidate | undefined = this.selectCandidate(extraction, options.candidateSelector);
      if (candidate !== undefined && candidate.object !== undefined) {
        const parsed: Record<string, Object> = candidate.object;
        const schema: LlmGuardValidationResult = schemaValidator(parsed);
        if (schema.ok) {
          if (domainValidator === undefined) {
            return parsed;
          }
          const domainIssues: string[] = domainValidator(parsed);
          if (domainIssues.length === 0) {
            return parsed;
          }
          lastFailureKind = 'DOMAIN_VALIDATION_ERROR';
          lastIssues = domainIssues;
        } else {
          lastFailureKind = 'JSON_SCHEMA_ERROR';
          lastIssues = schema.issues;
        }
      } else if (options.candidateSelector !== undefined) {
        throw new GenerationJsonError(
          'JSON_EXTRACTION_ERROR',
          this.formatExtractionFailure(label, extraction),
          false,
        );
      } else {
        lastFailureKind = extraction.category === 'parse_error' ? 'JSON_PARSE_ERROR' : 'JSON_EXTRACTION_ERROR';
        lastIssues = [this.formatExtractionFailure(label, extraction)];
      }
      if (attempt >= maxRetries) {
        break;
      }
      guardedMessages.push({ role: 'assistant', content: raw });
      guardedMessages.push(buildGuardRetryMessage(label, lastIssues));
      attempt += 1;
    }
    throw new GenerationJsonError(
      lastFailureKind,
      label + ' failed after ' + String(attempt + 1) + ' attempts: ' + lastIssues.join('; '),
      false,
    );
  }

  private async invokeClient(
    messages: ChatMessage[],
    options: GenerationJsonCallOptions,
    label: string,
  ): Promise<LlmCallResult> {
    // 生成路线只要纯 JSON: 显式关闭 thinking, 防止 reasoning (deepseek reasoning_effort=high)
    // 烧光 max_tokens 预算导致正文截断 (finish_reason=length, 2026-09-19 冒烟实测)。
    const request: LlmCallRequest = {
      messages: messages,
      maxTokens: options.maxTokens,
      timeoutMs: options.timeoutMs,
      responseFormat: options.responseFormat,
      enableThinking: false,
    };
    try {
      return await this.client.call(request);
    } catch (e) {
      if (e instanceof LlmError) {
        const transportError: LlmError = e;
        const retriable: boolean = TRANSPORT_RETRIABLE_KINDS.includes(transportError.kind);
        throw new GenerationJsonError(
          'LLM_TRANSPORT',
          label + ' transport failed: [' + transportError.kind + '] ' + transportError.message,
          retriable,
          transportError,
        );
      }
      const cause: Error | undefined = e instanceof Error ? e : undefined;
      throw new GenerationJsonError(
        'LLM_TRANSPORT',
        label + ' transport failed: ' + (e instanceof Error ? e.message : String(e)),
        false,
        cause,
      );
    }
  }

  private selectCandidate(
    extraction: LlmGuardJsonExtractionResult,
    selector?: JsonCandidateSelector,
  ): LlmGuardJsonCandidate | undefined {
    if (selector !== undefined) {
      return selector(extraction);
    }
    if (extraction.success) {
      return extraction.candidates[0];
    }
    return undefined;
  }

  private formatExtractionFailure(label: string, extraction: LlmGuardJsonExtractionResult): string {
    return label + ' JSON extraction failed: category=' + extraction.category
      + ', candidates=' + String(extraction.candidates.length)
      + ', detail=' + extraction.detail
      + ', preview=' + extraction.preview;
  }
}
