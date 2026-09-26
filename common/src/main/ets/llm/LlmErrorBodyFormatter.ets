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
    const bytes: Uint8Array = new Uint8Array(buffer);
    try {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      const decoded: string = decoder.decodeToString(bytes);
      if (decoded.length > 0 || bytes.length === 0) {
        return decoded;
      }
    } catch (_e) {
      // Fall through to the deterministic decoder below.
    }
    return LlmErrorBodyFormatter.decodeUtf8Fallback(bytes);
  }

  /** Host-side Hypium may not provide @kit.ArkTS TextDecoder; keep HTTP decoding deterministic. */
  private static decodeUtf8Fallback(bytes: Uint8Array): string {
    let output: string = '';
    let index: number = 0;
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
      index = 3;
    }
    while (index < bytes.length) {
      const first: number = bytes[index];
      if (first <= 0x7F) {
        output += String.fromCharCode(first);
        index += 1;
        continue;
      }
      if (first >= 0xC2 && first <= 0xDF && index + 1 < bytes.length) {
        const second: number = bytes[index + 1];
        if (LlmErrorBodyFormatter.isUtf8Continuation(second)) {
          const codePoint: number = ((first & 0x1F) << 6) | (second & 0x3F);
          output += String.fromCharCode(codePoint);
          index += 2;
          continue;
        }
      }
      if (first >= 0xE0 && first <= 0xEF && index + 2 < bytes.length) {
        const second: number = bytes[index + 1];
        const third: number = bytes[index + 2];
        const validSecond: boolean = LlmErrorBodyFormatter.isUtf8Continuation(second)
          && (first !== 0xE0 || second >= 0xA0)
          && (first !== 0xED || second < 0xA0);
        if (validSecond && LlmErrorBodyFormatter.isUtf8Continuation(third)) {
          const codePoint: number = ((first & 0x0F) << 12) | ((second & 0x3F) << 6) | (third & 0x3F);
          output += String.fromCharCode(codePoint);
          index += 3;
          continue;
        }
      }
      if (first >= 0xF0 && first <= 0xF4 && index + 3 < bytes.length) {
        const second: number = bytes[index + 1];
        const third: number = bytes[index + 2];
        const fourth: number = bytes[index + 3];
        const validSecond: boolean = LlmErrorBodyFormatter.isUtf8Continuation(second)
          && (first !== 0xF0 || second >= 0x90)
          && (first !== 0xF4 || second <= 0x8F);
        if (validSecond && LlmErrorBodyFormatter.isUtf8Continuation(third)
          && LlmErrorBodyFormatter.isUtf8Continuation(fourth)) {
          const codePoint: number = ((first & 0x07) << 18) | ((second & 0x3F) << 12)
            | ((third & 0x3F) << 6) | (fourth & 0x3F);
          const adjusted: number = codePoint - 0x10000;
          output += String.fromCharCode(0xD800 + (adjusted >> 10));
          output += String.fromCharCode(0xDC00 + (adjusted & 0x3FF));
          index += 4;
          continue;
        }
      }
      output += '\uFFFD';
      index += 1;
    }
    return output;
  }

  private static isUtf8Continuation(value: number): boolean {
    return (value & 0xC0) === 0x80;
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
