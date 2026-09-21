/**
 * GenerationJsonCaller.test.ets — 统一 JSON 调用 seam 行为测试
 *
 * 路径: agents/src/test/GenerationJsonCaller.test.ets
 * 职责: 验证 callJson 的完整生命周期分支 — 成功 / schema·domain 守门重试 /
 *   重试耗尽错误类别 / 截断识别 / 传输错误映射 / candidateSelector 终止语义
 * 依赖: @ohos/hypium, common (LlmError / TRUNCATION_MARKER / LlmCaller 类型)
 *
 * 数据流:
 *   FakeCaller(脚本化回复) → GenerationJsonCaller.callJson → GenerationJsonError / parsed json 断言
 *
 * ArkTS 1.1 strict 适配:
 *   - FakeCaller / ThrowingCaller 用类实现 LlmCaller, 避免对象字面量结构类型
 *   - catch 分支用 instanceof GenerationJsonError 收窄后断言
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  GenerationJsonCaller,
  GenerationJsonError,
  DomainJsonValidator,
  JsonCandidateSelector,
} from '../main/ets/agents/GenerationJsonCaller';
import { LlmError, TRUNCATION_MARKER } from 'common';
import type {
  ChatMessage,
  LlmCallRequest,
  LlmCallResult,
  LlmCaller,
  LlmGuardJsonExtractionResult,
  LlmGuardValidationResult,
} from 'common';

class FakeCaller implements LlmCaller {
  public calls: ChatMessage[][] = [];
  private replies: string[];
  private index: number = 0;

  constructor(replies: string[]) {
    this.replies = replies;
  }

  async call(request: LlmCallRequest): Promise<LlmCallResult> {
    this.calls.push(request.messages.slice(0));
    const reply: string = this.replies[this.index] ?? this.replies[this.replies.length - 1];
    this.index += 1;
    const result: LlmCallResult = { text: reply, streamed: false };
    return result;
  }
}

class ThrowingCaller implements LlmCaller {
  public calls: number = 0;
  public error: LlmError;

  constructor(error: LlmError) {
    this.error = error;
  }

  async call(request: LlmCallRequest): Promise<LlmCallResult> {
    this.calls += 1;
    throw this.error;
  }
}

function messages(): ChatMessage[] {
  return [
    { role: 'system', content: 'Return JSON only.' },
    { role: 'user', content: 'generate' },
  ];
}

function okFlagValidator(json: Record<string, Object>): LlmGuardValidationResult {
  const value: Object | undefined = json['ok'];
  if (typeof value === 'boolean' && value === true) {
    return { ok: true, issues: [] };
  }
  return { ok: false, issues: ['ok must be true'] };
}

function flagDomainValidator(json: Record<string, Object>): string[] {
  const value: Object | undefined = json['flag'];
  if (typeof value === 'string' && value === 'pass') {
    return [];
  }
  return ['flag must be "pass"'];
}

async function captureError(promise: Promise<Record<string, Object>>): Promise<GenerationJsonError | undefined> {
  try {
    await promise;
    return undefined;
  } catch (e) {
    if (e instanceof GenerationJsonError) {
      return e;
    }
    return undefined;
  }
}

export default function generationJsonCallerTest(): void {
  describe('GenerationJsonCaller.lifecycle', () => {
    it('success_first_attempt_returns_parsed_json', 0, async () => {
      const fake: FakeCaller = new FakeCaller(['{"ok":true}']);
      const caller: GenerationJsonCaller = new GenerationJsonCaller(fake);
      const parsed: Record<string, Object> = await caller.callJson(
        messages(), { label: 'unit', maxTokens: 100, timeoutMs: 1000 }, okFlagValidator,
      );
      expect(parsed['ok']).assertEqual(true);
      expect(fake.calls.length).assertEqual(1);
    });

    it('schema_failure_retries_with_guard_message_then_succeeds', 0, async () => {
      const fake: FakeCaller = new FakeCaller(['{"ok":false}', '{"ok":true}']);
      const caller: GenerationJsonCaller = new GenerationJsonCaller(fake);
      const parsed: Record<string, Object> = await caller.callJson(
        messages(), { label: 'unit', maxTokens: 100, timeoutMs: 1000 }, okFlagValidator,
      );
      expect(parsed['ok']).assertEqual(true);
      expect(fake.calls.length).assertEqual(2);
      expect(fake.calls[1].length > fake.calls[0].length).assertTrue();
      const retryMessage: ChatMessage = fake.calls[1][fake.calls[1].length - 1];
      expect(retryMessage.role).assertEqual('user');
      expect(retryMessage.content).assertContain('ok must be true');
      expect(fake.calls[1][fake.calls[1].length - 2].role).assertEqual('assistant');
    });

    it('schema_failure_exhausts_retries_throws_json_schema_error', 0, async () => {
      const fake: FakeCaller = new FakeCaller(['{"ok":false}']);
      const caller: GenerationJsonCaller = new GenerationJsonCaller(fake);
      const err: GenerationJsonError | undefined = await captureError(caller.callJson(
        messages(), { label: 'unit', maxTokens: 100, timeoutMs: 1000 }, okFlagValidator,
      ));
      expect(err !== undefined).assertTrue();
      expect(err?.kind).assertEqual('JSON_SCHEMA_ERROR');
      expect(err?.retriable).assertFalse();
      expect(fake.calls.length).assertEqual(3);
      expect(err?.message).assertContain('after 3 attempts');
    });

    it('domain_failure_retries_then_succeeds', 0, async () => {
      const fake: FakeCaller = new FakeCaller(['{"ok":true,"flag":"bad"}', '{"ok":true,"flag":"pass"}']);
      const caller: GenerationJsonCaller = new GenerationJsonCaller(fake);
      const domain: DomainJsonValidator = flagDomainValidator;
      const parsed: Record<string, Object> = await caller.callJson(
        messages(), { label: 'unit', maxTokens: 100, timeoutMs: 1000 }, okFlagValidator, domain,
      );
      expect(parsed['flag']).assertEqual('pass');
      expect(fake.calls.length).assertEqual(2);
    });

    it('domain_failure_exhausts_retries_throws_domain_validation_error', 0, async () => {
      const fake: FakeCaller = new FakeCaller(['{"ok":true,"flag":"bad"}']);
      const caller: GenerationJsonCaller = new GenerationJsonCaller(fake);
      const domain: DomainJsonValidator = flagDomainValidator;
      const err: GenerationJsonError | undefined = await captureError(caller.callJson(
        messages(), { label: 'unit', maxTokens: 100, timeoutMs: 1000 }, okFlagValidator, domain,
      ));
      expect(err !== undefined).assertTrue();
      expect(err?.kind).assertEqual('DOMAIN_VALIDATION_ERROR');
      expect(err?.retriable).assertFalse();
      expect(fake.calls.length).assertEqual(3);
    });

    it('missing_json_exhausts_retries_throws_json_extraction_error', 0, async () => {
      const fake: FakeCaller = new FakeCaller(['no json at all']);
      const caller: GenerationJsonCaller = new GenerationJsonCaller(fake);
      const err: GenerationJsonError | undefined = await captureError(caller.callJson(
        messages(), { label: 'unit', maxTokens: 100, timeoutMs: 1000 }, okFlagValidator,
      ));
      expect(err !== undefined).assertTrue();
      expect(err?.kind).assertEqual('JSON_EXTRACTION_ERROR');
      expect(err?.retriable).assertFalse();
      expect(err?.message).assertContain('category=missing');
    });

    it('ambiguous_candidates_retry_then_single_candidate_succeeds', 0, async () => {
      const fake: FakeCaller = new FakeCaller(['{"a":1} then {"b":2}', '{"ok":true}']);
      const caller: GenerationJsonCaller = new GenerationJsonCaller(fake);
      const parsed: Record<string, Object> = await caller.callJson(
        messages(), { label: 'unit', maxTokens: 100, timeoutMs: 1000 }, okFlagValidator,
      );
      expect(parsed['ok']).assertEqual(true);
      expect(fake.calls.length).assertEqual(2);
    });

    it('transport_network_error_maps_retriable_with_cause', 0, async () => {
      const throwing: ThrowingCaller = new ThrowingCaller(new LlmError('connection refused', 'NETWORK_ERROR'));
      const caller: GenerationJsonCaller = new GenerationJsonCaller(throwing);
      const err: GenerationJsonError | undefined = await captureError(caller.callJson(
        messages(), { label: 'unit', maxTokens: 100, timeoutMs: 1000 }, okFlagValidator,
      ));
      expect(err !== undefined).assertTrue();
      expect(err?.kind).assertEqual('LLM_TRANSPORT');
      expect(err?.retriable).assertTrue();
      expect(err?.cause instanceof LlmError).assertTrue();
      expect(throwing.calls).assertEqual(1);
    });

    it('transport_api_error_maps_not_retriable', 0, async () => {
      const throwing: ThrowingCaller = new ThrowingCaller(new LlmError('http 500', 'API_ERROR'));
      const caller: GenerationJsonCaller = new GenerationJsonCaller(throwing);
      const err: GenerationJsonError | undefined = await captureError(caller.callJson(
        messages(), { label: 'unit', maxTokens: 100, timeoutMs: 1000 }, okFlagValidator,
      ));
      expect(err !== undefined).assertTrue();
      expect(err?.kind).assertEqual('LLM_TRANSPORT');
      expect(err?.retriable).assertFalse();
    });

    it('truncation_marker_throws_llm_truncated', 0, async () => {
      const fake: FakeCaller = new FakeCaller(['{"ok":true}\n\n' + TRUNCATION_MARKER]);
      const caller: GenerationJsonCaller = new GenerationJsonCaller(fake);
      const err: GenerationJsonError | undefined = await captureError(caller.callJson(
        messages(), { label: 'unit', maxTokens: 100, timeoutMs: 1000 }, okFlagValidator,
      ));
      expect(err !== undefined).assertTrue();
      expect(err?.kind).assertEqual('LLM_TRUNCATED');
      expect(err?.retriable).assertFalse();
      expect(err?.message).assertContain('truncated by max_tokens');
      expect(fake.calls.length).assertEqual(1);
    });

    it('candidate_selector_miss_is_terminal_single_call', 0, async () => {
      const fake: FakeCaller = new FakeCaller(['{"meta":1} then {"other":2}']);
      const caller: GenerationJsonCaller = new GenerationJsonCaller(fake);
      const missSelector: JsonCandidateSelector =
        (_extraction: LlmGuardJsonExtractionResult): undefined => undefined;
      const err: GenerationJsonError | undefined = await captureError(caller.callJson(
        messages(),
        { label: 'unit', maxTokens: 100, timeoutMs: 1000, candidateSelector: missSelector },
        okFlagValidator,
      ));
      expect(err !== undefined).assertTrue();
      expect(err?.kind).assertEqual('JSON_EXTRACTION_ERROR');
      expect(fake.calls.length).assertEqual(1);
    });

    it('candidate_selector_hit_returns_selected_candidate', 0, async () => {
      const fake: FakeCaller = new FakeCaller(['prefix {"meta":1} middle {"ok":true} suffix']);
      const caller: GenerationJsonCaller = new GenerationJsonCaller(fake);
      const selector: JsonCandidateSelector =
        (extraction: LlmGuardJsonExtractionResult) => {
          for (const candidate of extraction.candidates) {
            if (candidate.object !== undefined && candidate.object['ok'] === true) {
              return candidate;
            }
          }
          return undefined;
        };
      const parsed: Record<string, Object> = await caller.callJson(
        messages(),
        { label: 'unit', maxTokens: 100, timeoutMs: 1000, candidateSelector: selector },
        okFlagValidator,
      );
      expect(parsed['ok']).assertEqual(true);
      expect(fake.calls.length).assertEqual(1);
    });

    it('max_retries_zero_limits_to_single_attempt', 0, async () => {
      const fake: FakeCaller = new FakeCaller(['{"ok":false}']);
      const caller: GenerationJsonCaller = new GenerationJsonCaller(fake);
      const err: GenerationJsonError | undefined = await captureError(caller.callJson(
        messages(), { label: 'unit', maxTokens: 100, timeoutMs: 1000, maxRetries: 0 }, okFlagValidator,
      ));
      expect(err !== undefined).assertTrue();
      expect(err?.kind).assertEqual('JSON_SCHEMA_ERROR');
      expect(fake.calls.length).assertEqual(1);
      expect(err?.message).assertContain('after 1 attempts');
    });
  });
}
