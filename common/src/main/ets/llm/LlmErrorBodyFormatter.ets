// MindTrace - LLM HTTP 错误体格式化器
// 位置: common/src/main/ets/llm/LlmErrorBodyFormatter.ets
// 责任: 把 http.HttpResponse.result（ArrayBuffer | Object | string）解码成 user-visible 字符串,
//       并对常见敏感 token (Bearer / api-key= / sk-...) 做 redact,
//       防止 LLM API 错误消息把 endpoint / Authorization / api-key 泄露到 UI / 日志。
// 用途: LlmClient API_ERROR 分支调用 LlmErrorBodyFormatter.format(response.result);
//       LlmClient 成功分支调用 LlmErrorBodyFormatter.decodeFull(response.result) 后 JSON.parse。
//
// ArkTS 1.1 严格语法:
//   - 无 any / unknown
//   - 不抛 Record<string, T>
//   - 不依赖 dynamic indexing (obj[k])

import { util } from '@kit.ArkTS';

export class LlmErrorBodyFormatter {
  private static readonly BODY_PREVIEW_MAX_CHARS: number = 256;

  /**
   * 完整解码 HTTP 响应体 (无截断 / 无脱敏), 供 LlmClient 成功分支 JSON.parse 使用。
   * format() 面向用户可见错误信息 (256 字符预览 + 敏感信息脱敏);
   * decodeFull() 必须保留原始字节, 否则响应体被截断会导致 JSON.parse 失败。
   */
  public static decodeFull(result: Object | ArrayBuffer | string | undefined | null): string {
    if (result === undefined || result === null) {
      return '';
    }
    if (typeof result === 'string') {
      return result;
    }
    if (result instanceof ArrayBuffer) {
      return LlmErrorBodyFormatter.decodeArrayBuffer(result);
    }
    return LlmErrorBodyFormatter.stringifyObject(result);
  }

  public static format(result: Object | ArrayBuffer | string | undefined | null): string {
    if (result === undefined || result === null) {
      return '';
    }
    if (typeof result === 'string') {
      return LlmErrorBodyFormatter.preview(LlmErrorBodyFormatter.redactSensitiveText(result));
    }
    if (result instanceof ArrayBuffer) {
      const decoded: string = LlmErrorBodyFormatter.decodeArrayBuffer(result);
      return LlmErrorBodyFormatter.preview(LlmErrorBodyFormatter.redactSensitiveText(decoded));
    }
    const serialized: string = LlmErrorBodyFormatter.stringifyObject(result);
    return LlmErrorBodyFormatter.preview(LlmErrorBodyFormatter.redactSensitiveText(serialized));
  }

  public static redactSensitiveText(value: string): string {
    let redacted: string = value;
    redacted = redacted.replace(new RegExp('Bearer\\s+[^\\s,;]+', 'gi'), 'Bearer [REDACTED]');
    redacted = redacted.replace(new RegExp('(api[-_]key|x-api-key|authorization)\\s*[:=]\\s*[^\\s,;]+', 'gi'), '$1=[REDACTED]');
    redacted = redacted.replace(new RegExp('sk-[A-Za-z0-9_-]+', 'g'), 'sk-[REDACTED]');
    return redacted;
  }

  private static decodeArrayBuffer(buffer: ArrayBuffer): string {
    try {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      return decoder.decodeToString(new Uint8Array(buffer));
    } catch (_e) {
      return '';
    }
  }

  private static stringifyObject(value: Object): string {
    try {
      return JSON.stringify(value);
    } catch (_e) {
      return '';
    }
  }

  private static preview(value: string): string {
    if (value.length <= LlmErrorBodyFormatter.BODY_PREVIEW_MAX_CHARS) {
      return value;
    }
    return value.substring(0, LlmErrorBodyFormatter.BODY_PREVIEW_MAX_CHARS) + '...';
  }
}
