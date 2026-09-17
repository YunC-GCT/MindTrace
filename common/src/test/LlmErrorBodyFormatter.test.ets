/**
 * LlmErrorBodyFormatter.test.ets — LLM HTTP 错误响应体格式化回归测试
 *
 * 路径: common/src/test/LlmErrorBodyFormatter.test.ets
 * 职责: 锁定 HTTP 400 错误体 ArrayBuffer 不再显示 [object ArrayBuffer]
 * 依赖: @ohos/hypium; common LlmErrorBodyFormatter
 */
import { describe, it, expect } from '@ohos/hypium';
import { LlmErrorBodyFormatter } from '../main/ets/llm/LlmErrorBodyFormatter';
import type { LlmErrorBodyFormatOptions } from '../main/ets/llm/LlmErrorBodyFormatter';

const utf8ErrorBytes: number[] = [123, 34, 101, 114, 114, 111, 114, 34, 58, 123, 34, 109, 101, 115, 115, 97, 103, 101, 34, 58, 34, 229, 143, 130, 230, 149, 176, 233, 148, 153, 232, 175, 175, 34, 125, 125];

class UnreadableErrorBody {
}

function arrayBufferFromBytes(bytes: number[]): ArrayBuffer {
  const view: Uint8Array = new Uint8Array(bytes.length);
  for (let index = 0; index < bytes.length; index += 1) {
    view[index] = bytes[index];
  }
  return view.buffer;
}

export default function llmErrorBodyFormatterTest(): void {
  describe('LlmErrorBodyFormatter', () => {
    it('decodes_utf8_array_buffer_without_object_array_buffer', 0, () => {
      const options: LlmErrorBodyFormatOptions = {
        statusCode: 400,
        body: arrayBufferFromBytes(utf8ErrorBytes),
        contentType: 'application/json',
      };
      const message: string = LlmErrorBodyFormatter.format(options);
      expect(message.includes('LLM API error 400')).assertTrue();
      expect(message.includes('参数错误')).assertTrue();
      expect(message.includes('[object ArrayBuffer]')).assertFalse();
    });

    it('keeps_multibyte_utf8_array_buffer_readable_for_http_400', 0, () => {
      const options: LlmErrorBodyFormatOptions = {
        statusCode: 400,
        body: arrayBufferFromBytes(utf8ErrorBytes),
        contentType: 'application/json; charset=utf-8',
      };
      const message: string = LlmErrorBodyFormatter.format(options);
      expect(message.includes('400')).assertTrue();
      expect(message.includes('参数错误')).assertTrue();
      expect(message.includes('ArrayBuffer')).assertFalse();
    });

    it('formats_plain_text_error_body', 0, () => {
      const options: LlmErrorBodyFormatOptions = {
        statusCode: 400,
        body: 'bad request: model rejected the prompt',
        contentType: 'text/plain',
      };
      const message: string = LlmErrorBodyFormatter.format(options);
      expect(message.includes('LLM API error 400')).assertTrue();
      expect(message.includes('bad request')).assertTrue();
      expect(message.includes('[object Object]')).assertFalse();
    });

    it('summarizes_json_error_message', 0, () => {
      const options: LlmErrorBodyFormatOptions = {
        statusCode: 400,
        body: '{"error":{"message":"invalid messages field","type":"invalid_request_error"}}',
        contentType: 'application/json',
      };
      const message: string = LlmErrorBodyFormatter.format(options);
      expect(message.includes('LLM API error 400')).assertTrue();
      expect(message.includes('invalid messages field')).assertTrue();
      expect(message.includes('invalid_request_error')).assertFalse();
    });

    it('falls_back_for_empty_error_body', 0, () => {
      const options: LlmErrorBodyFormatOptions = {
        statusCode: 400,
        body: '',
        contentType: 'text/plain',
      };
      const message: string = LlmErrorBodyFormatter.format(options);
      expect(message.includes('LLM API error 400')).assertTrue();
      expect(message.includes('empty error response body')).assertTrue();
      expect(message.includes('[object ArrayBuffer]')).assertFalse();
    });

    it('falls_back_for_unreadable_object_body', 0, () => {
      const options: LlmErrorBodyFormatOptions = {
        statusCode: 400,
        body: new UnreadableErrorBody(),
        contentType: 'application/octet-stream',
      };
      const message: string = LlmErrorBodyFormatter.format(options);
      expect(message.includes('LLM API error 400')).assertTrue();
      expect(message.includes('empty error response body')).assertTrue();
      expect(message.includes('[object Object]')).assertFalse();
    });

    it('redacts_api_key_authorization_cookie_bearer_and_endpoint', 0, () => {
      const options: LlmErrorBodyFormatOptions = {
        statusCode: 400,
        body: '{"error":{"message":"Authorization: Bearer sk-test-secret-12345 Cookie=session=abc api_key=sk-test-secret-67890 endpoint=https://api.example.test/chat/completions"}}',
        contentType: 'application/json',
      };
      const message: string = LlmErrorBodyFormatter.format(options);
      expect(message.includes('LLM API error 400')).assertTrue();
      expect(message.includes('<REDACTED>')).assertTrue();
      expect(message.includes('sk-test-secret')).assertFalse();
      expect(message.includes('session=abc')).assertFalse();
      expect(message.includes('https://api.example.test')).assertFalse();
      expect(message.includes('Bearer sk-')).assertFalse();
    });
  });
}
