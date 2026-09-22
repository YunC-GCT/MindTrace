/**
 * LlmErrorBodyFormatter.test.ets — LLM HTTP 响应体解码/格式化回归测试
 *
 * 路径: common/src/test/LlmErrorBodyFormatter.test.ets
 * 职责: 锁定两条解码路径的行为边界 —
 *   - format(): 错误分支专用, 256 字符预览 + 敏感信息脱敏 (用户可见);
 *   - decodeFull(): 成功分支专用, 完整解码无截断无脱敏 (JSON.parse 输入)。
 * 背景: 2026-09-19 冒烟发现 LlmClient 成功分支误用 format() 导致非流式响应
 *       被 256 字符截断, 全部非流式 LLM 调用报 PARSE_ERROR (P0)。
 * 依赖: @ohos/hypium; common LlmErrorBodyFormatter
 */
import { describe, it, expect } from '@ohos/hypium';
import { LlmErrorBodyFormatter } from '../main/ets/llm/LlmErrorBodyFormatter';

const utf8ErrorBytes: number[] = [123, 34, 101, 114, 114, 111, 114, 34, 58, 34, 229, 143,
  130, 230, 149, 176, 233, 148, 153, 232, 175, 175, 34, 125];

/** format() 预览上限须与实现常量一致 (256 字符 + '...' 后缀) */
const BODY_PREVIEW_LIMIT: number = 256;

function arrayBufferFromBytes(bytes: number[]): ArrayBuffer {
  const view: Uint8Array = new Uint8Array(bytes.length);
  for (let index = 0; index < bytes.length; index += 1) {
    view[index] = bytes[index];
  }
  return view.buffer;
}

function buildLongJsonBody(targetLength: number): string {
  let body: string = '{"choices":[{"message":{"role":"assistant","content":"';
  while (body.length < targetLength) {
    body += 'abcdefghijklmnopqrstuvwxyz0123456789';
  }
  body += '"}}]}';
  return body;
}

export default function llmErrorBodyFormatterTest(): void {
  describe('LlmErrorBodyFormatter', () => {
    it('decode_full_keeps_long_body_without_truncation', 0, () => {
      const body: string = buildLongJsonBody(1200);
      const decoded: string = LlmErrorBodyFormatter.decodeFull(body);
      expect(decoded.length).assertEqual(body.length);
      expect(decoded.endsWith('"}}]}')).assertTrue();
      expect(decoded.includes('...')).assertFalse();
    });

    it('decode_full_does_not_redact_content', 0, () => {
      const body: string = '{"error":"Authorization: Bearer sk-test-secret-12345"}';
      const decoded: string = LlmErrorBodyFormatter.decodeFull(body);
      expect(decoded).assertEqual(body);
      expect(decoded.includes('sk-test-secret-12345')).assertTrue();
      expect(JSON.parse(decoded) !== undefined).assertTrue();
    });

    it('decode_full_decodes_utf8_array_buffer', 0, () => {
      const decoded: string = LlmErrorBodyFormatter.decodeFull(arrayBufferFromBytes(utf8ErrorBytes));
      expect(decoded).assertEqual('{"error":"参数错误"}');
    });

    it('decode_full_returns_empty_for_undefined_body', 0, () => {
      expect(LlmErrorBodyFormatter.decodeFull(undefined)).assertEqual('');
      expect(LlmErrorBodyFormatter.decodeFull(null)).assertEqual('');
    });

    it('format_truncates_long_body_to_preview_limit', 0, () => {
      const body: string = buildLongJsonBody(1200);
      const preview: string = LlmErrorBodyFormatter.format(body);
      expect(preview.length <= BODY_PREVIEW_LIMIT + 3).assertTrue();
      expect(preview.endsWith('...')).assertTrue();
      expect(preview.startsWith(body.substring(0, 10))).assertTrue();
    });

    it('format_redacts_bearer_and_api_key_in_error_body', 0, () => {
      const preview: string = LlmErrorBodyFormatter
        .format('Authorization: Bearer sk-test-secret-12345 api_key=sk-test-secret-67890');
      expect(preview.includes('[REDACTED]')).assertTrue();
      expect(preview.includes('sk-test-secret')).assertFalse();
    });

    it('format_keeps_short_body_intact', 0, () => {
      const preview: string = LlmErrorBodyFormatter.format('{"error":"参数错误"}');
      expect(preview).assertEqual('{"error":"参数错误"}');
    });
  });
}
