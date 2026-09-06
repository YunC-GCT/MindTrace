// MindTrace - LLM HTTP 客户端(OpenAI 兼容协议)
// 位置: common/src/main/ets/llm/LlmClient.ets
// 责任: Z (Mavis)
// 创建: 2026-07-14 — 主 Agent 业务 LLM 调用基础设施
//
// 用法 (spec 005: 唯一公共入口 call(request)):
//   const client = new LlmClient();
//   // 非流式: 返回完整文本
//   const result: LlmCallResult = await client.call({
//     messages: [
//       { role: 'system', content: '...' },
//       { role: 'user', content: '...' },
//     ],
//   });
//   const text: string = result.text ?? '';
//   // 流式: 真 SSE (requestInStream), 每 token 触发 onDelta
//   await client.call({
//     messages: [...],
//     stream: true,
//     onDelta: (delta: string, kind: 'reasoning' | 'content'): void => { ... },
//   });
//
// 设计:
//   - 端点 / model / temperature / max_tokens / timeout 全部从 LlmConfig 单例读
//   - 单次调用可用 request 字段覆盖默认
//   - 错误统一抛 LlmError(kind: NO_API_KEY / NETWORK_ERROR / API_ERROR / PARSE_ERROR / EMPTY_RESPONSE / TIMEOUT / STREAM_FAILED)
//
// ArkTS 1.1 严格语法:
//   - 无 any / unknown
//   - 显式类型
//   - 不抛 Record<string, T>

import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { LlmConfig } from './LlmConfig';
import {
  LlmRequestBody,
  LlmResponse,
  LlmResponseChoice,
  LlmStreamChunk,
  LlmStreamDelta,
  LlmStreamCallback,
  LlmThinkingConfig,
  LlmCallRequest,
  LlmCallResult,
  LlmError,
} from './LlmTypes';

export class LlmClient {
  private config: LlmConfig;

  constructor() {
    this.config = LlmConfig.getInstance();
  }

  // 唯一公共入口 (ADR-0004 / spec 005): request.stream 选择 JSON / SSE 流式适配路径
  public async call(request: LlmCallRequest): Promise<LlmCallResult> {
    if (request.stream === true) {
      if (request.onDelta === undefined) {
        throw new LlmError('call: stream=true requires onDelta callback', 'STREAM_FAILED');
      }
      await this.callStreamInternal(request, request.onDelta);
      const streamedResult: LlmCallResult = { streamed: true };
      return streamedResult;
    }
    const text: string = await this.callJsonInternal(request);
    const jsonResult: LlmCallResult = { text: text, streamed: false };
    return jsonResult;
  }

  // ===== 内部 =====

  // JSON 适配路径 (原 call): request() + 手动 JSON 解析, 返回首条 message.content
  private async callJsonInternal(request: LlmCallRequest): Promise<string> {
    // 1. 校验 API key
    const apiKey: string | null = await this.config.getApiKey();
    if (apiKey === null) {
      throw new LlmError('API key not configured. Set it in Settings first.', 'NO_API_KEY');
    }

    // 2. 构造请求体(request 字段优先, 默认从 LlmConfig)
    const model: string = this.pickStr(request.model, this.config.getModel());
    const temperature: number = this.pickNum(request.temperature, this.config.getTemperature());
    const maxTokens: number = this.pickNum(request.maxTokens, this.config.getMaxTokens());
    const timeoutMs: number = this.pickNum(request.timeoutMs, this.config.getTimeoutMs());

    const body: LlmRequestBody = {
      model: model,
      messages: request.messages,
      temperature: temperature,
      max_tokens: maxTokens,
      stream: false,
    };
    if (request.responseFormat !== undefined) {
      body.response_format = request.responseFormat;
    }

    // 3. 发 HTTP POST
    const endpointUrl: string = this.resolveEndpointUrl(this.config.getEndpoint());
    const httpRequest = http.createHttp();
    let response: http.HttpResponse;
    try {
      response = await httpRequest.request(endpointUrl, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`,
        },
        extraData: JSON.stringify(body),
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
      });
    } catch (e) {
      httpRequest.destroy();
      throw new LlmError(`LLM network error: ${(e as Error).message ?? String(e)}`, 'NETWORK_ERROR');
    }
    httpRequest.destroy();

    // 4. 状态码校验
    if (response.responseCode !== 200) {
      const errBody: string = (response.result as string) ?? '';
      throw new LlmError(`LLM API error ${response.responseCode}: ${errBody}`, 'API_ERROR');
    }

    // 5. 解析 JSON
    const raw: string = response.result as string;
    let parsed: LlmResponse;
    try {
      parsed = JSON.parse(raw) as LlmResponse;
    } catch (e) {
      throw new LlmError(`LLM response parse error: ${(e as Error).message ?? String(e)}`, 'PARSE_ERROR');
    }

    // 6. 提取 content
    console.info('[LlmClient] raw response: ' + JSON.stringify(parsed).substring(0, 800));
    if (parsed.choices.length > 0 && parsed.choices[0].finish_reason === 'length') {
      throw new LlmError('LLM response truncated by max_tokens', 'API_ERROR');
    }
    return this.extractContent(parsed);
  }

  private extractContent(parsed: LlmResponse): string {
    if (parsed.choices.length === 0) {
      throw new LlmError('LLM returned empty choices', 'EMPTY_RESPONSE');
    }
    const first: LlmResponseChoice = parsed.choices[0];
    if (first.message === undefined || first.message === null) {
      throw new LlmError('LLM returned empty message', 'EMPTY_RESPONSE');
    }
    const content: string = first.message.content;
    if (content === undefined || content === null || content.length === 0) {
      // 推理模型: 实际内容可能在 reasoning_content
      const reasoning: string = first.message.reasoning_content ?? '';
      if (reasoning.length > 0) { return reasoning; }
      throw new LlmError('LLM returned empty content', 'EMPTY_RESPONSE');
    }
    return content;
  }

  // opts?.xxx 返回 string | undefined,转回 string 或用默认
  private pickStr(v: string | undefined, fallback: string): string {
    if (v === undefined || v === null || v.length === 0) {
      return fallback;
    }
    return v;
  }

  // opts?.xxx 返回 number | undefined,转回 number 或用默认
  private pickNum(v: number | undefined, fallback: number): number {
    if (v === undefined || v === null) {
      return fallback;
    }
    return v;
  }

  private resolveEndpointUrl(baseUrl: string): string {
    const endpoint: string = baseUrl.trim();
    if (endpoint.length === 0) {
      return 'https://api.deepseek.com/chat/completions';
    }
    const lower: string = endpoint.toLowerCase();
    if (lower.indexOf('/anthropic') >= 0) {
      throw new LlmError(
        'Anthropic base_url is not supported by this OpenAI-compatible client. Use https://api.deepseek.com',
        'API_ERROR',
      );
    }
    if (lower.indexOf('/chat/completions') >= 0) {
      return endpoint;
    }
    return endpoint.replace(/\/+$/, '') + '/chat/completions';
  }

  /**
   * SSE 流式适配路径 (原 callStream)
   *
   * 使用 HarmonyOS requestInStream + on('dataReceive') 逐块接收 SSE 事件。
   * 每收到一个有效 token 即触发 onDelta 回调，实现逐字实时渲染。
   */
  private async callStreamInternal(
    request: LlmCallRequest,
    onDelta: LlmStreamCallback,
  ): Promise<void> {
    // 1. 校验 API key
    const apiKey: string | null = await this.config.getApiKey();
    if (apiKey === null) {
      throw new LlmError('API key not configured. Set it in Settings first.', 'NO_API_KEY');
    }

    // 2. 构造请求体
    const model: string = this.pickStr(request.model, this.config.getModel());
    const temperature: number = this.pickNum(request.temperature, this.config.getTemperature());
    const maxTokens: number = this.pickNum(request.maxTokens, this.config.getMaxTokens());
    const timeoutMs: number = this.pickNum(request.timeoutMs, this.config.getTimeoutMs());
    const enableThinking: boolean = request.enableThinking === true;

    // 构造 body (Record 避免 redacted 匹配问题)
    const bodyObj: Record<string, Object> = {
    };

    // 手动设置字段以避免 redacted 字段匹配
    bodyObj['model'] = model;
    bodyObj['messages'] = request.messages as Object;
    bodyObj['stream'] = true;
    bodyObj['max_tokens'] = maxTokens;

    // DeepSeek 思考模式不支持 temperature,仅在非思考模式下设置
    if (!enableThinking) {
      bodyObj['temperature'] = temperature;
    }

    if (enableThinking) {
      const thinkingCfg: LlmThinkingConfig = { type: 'enabled' };
      bodyObj['thinking'] = thinkingCfg as Object;
      bodyObj['reasoning_effort'] = 'high';
    }

    if (request.responseFormat !== undefined) {
      bodyObj['response_format'] = request.responseFormat as Object;
    }

    const bodyJson: string = JSON.stringify(bodyObj);

    // 3. 创建 HttpRequest 并发起流式请求
    const endpointUrl: string = this.resolveEndpointUrl(this.config.getEndpoint());
    const httpRequest = http.createHttp();

    return new Promise<void>((resolve: (value: void) => void, reject: (reason: Error) => void): void => {
      let sseLineBuffer: string = '';
      let streamEnded: boolean = false;
      let dataReceived: boolean = false;

      // 超时保护 (2 分钟总超时)
      const timer: number = setTimeout((): void => {
        if (!streamEnded) {
          streamEnded = true;
          httpRequest.destroy();
          console.warn('[LlmClient] stream timeout after ' + timeoutMs.toString() + 'ms');
          reject(new LlmError('LLM stream timed out after ' + timeoutMs.toString() + 'ms', 'TIMEOUT') as Error);
        }
      }, timeoutMs);

      // 首字节超时: 8 秒内无数据则降级
      const firstByteTimer: number = setTimeout((): void => {
        if (!streamEnded && !dataReceived) {
          streamEnded = true;
          clearTimeout(timer);
          httpRequest.destroy();
          console.warn('[LlmClient] no data received within 8s, triggering fallback');
          reject(new LlmError('LLM stream no data', 'STREAM_FAILED') as Error);
        }
      }, 8000);

      // 订阅流式数据事件
      httpRequest.on('dataReceive', (chunk: ArrayBuffer): void => {
        if (streamEnded) { return; }
        dataReceived = true;
        clearTimeout(firstByteTimer);
        try {
          const text: string = LlmClient.arrayBufferToString(chunk);
          console.info('[LlmClient] dataReceive: ' + text.length.toString() + ' bytes');
          sseLineBuffer += text;
          sseLineBuffer = this.processSseBuffer(sseLineBuffer, onDelta);
        } catch (e) {
          console.warn('[LlmClient] dataReceive error: ' + ((e as Error).message ?? String(e)));
        }
      });

      // 流结束
      httpRequest.on('dataEnd', (): void => {
        if (streamEnded) {
          return;
        }
        streamEnded = true;
        clearTimeout(timer);
        clearTimeout(firstByteTimer);
        console.info('[LlmClient] dataEnd, buffer: ' + sseLineBuffer.length.toString());

        // 处理 buffer 中剩余数据
        if (sseLineBuffer.trim().length > 0) {
          this.processSseBufferFinal(sseLineBuffer, onDelta);
        }

        httpRequest.destroy();
        resolve();
      });

      // 发起流式请求
      httpRequest.requestInStream(endpointUrl, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + apiKey,
        },
        extraData: bodyJson,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
      }, (err: Error, data: number): void => {
        console.info('[LlmClient] requestInStream cb: err=' + (err ? err.message : 'null') + ' code=' + data.toString());
        if (err) {
          console.error('[LlmClient] stream err: ' + err.message);
          if (!streamEnded) {
            streamEnded = true;
            clearTimeout(timer);
            clearTimeout(firstByteTimer);
            httpRequest.destroy();
            reject(new LlmError(
              'LLM stream request failed: ' + err.message,
              'STREAM_FAILED',
            ) as Error);
          }
          return;
        }
        const responseCode: number = data;
        if (responseCode !== 200) {
          if (!streamEnded) {
            streamEnded = true;
            clearTimeout(timer);
            httpRequest.destroy();
            reject(new LlmError(
              'LLM stream API error ' + responseCode.toString(),
              'API_ERROR',
            ) as Error);
          }
        }
        // 200 响应: dataReceive 事件将逐步接收数据
      });
    });
  }

  /**
   * 处理 SSE 行缓冲,解析完整的 SSE events 并触发 onDelta
   * 返回未处理完的剩余 buffer
   */
  private processSseBuffer(
    buffer: string,
    onDelta: LlmStreamCallback,
  ): string {
    let remaining: string = buffer;

    // 查找完整的 SSE event (以 \n\n 分隔)
    while (true) {
      const doubleNewlineIdx: number = remaining.indexOf('\n\n');
      if (doubleNewlineIdx < 0) {
        // 没有完整 event,保留剩余
        break;
      }

      const eventText: string = remaining.substring(0, doubleNewlineIdx + 2);
      remaining = remaining.substring(doubleNewlineIdx + 2);

      // 解析该 event 中的每一行
      const lines: string[] = eventText.split('\n');
      for (const line of lines) {
        const trimmed: string = line.trim();
        if (trimmed.length === 0) {
          continue;
        }
        if (trimmed.indexOf('data: ') !== 0) {
          continue;
        }

        const dataStr: string = trimmed.substring(6);
        if (dataStr === '[DONE]') {
          continue; // 流结束信号,由 dataEnd 事件处理
        }

        // 解析 JSON chunk
        try {
          this.tryEmitSseDelta(dataStr, onDelta);
        } catch (e) {
          // 不完整的 JSON (跨 TCP 包),放回 buffer 等待更多数据
          return eventText + remaining;
        }
      }
    }

    return remaining;
  }

  /**
   * 流结束时处理 buffer 中可能残留的最后一段数据
   */
  private processSseBufferFinal(buffer: string, onDelta: LlmStreamCallback): void {
    const trimmed: string = buffer.trim();
    if (trimmed.length === 0) {
      return;
    }
    const lines: string[] = trimmed.split('\n');
    for (const line of lines) {
      const dataPrefix: string = 'data: ';
      const prefixIdx: number = line.indexOf(dataPrefix);
      if (prefixIdx < 0) {
        continue;
      }
      const dataStr: string = line.substring(prefixIdx + dataPrefix.length).trim();
      if (dataStr === '[DONE]' || dataStr.length === 0) {
        continue;
      }
      try {
        this.tryEmitSseDelta(dataStr, onDelta);
      } catch (e) {
        // 最终残留数据解析失败,静默丢弃
      }
    }
  }

  /**
   * 解析单行 SSE data 并触发 onDelta (JSON 解析失败则抛异常)
   */
  private tryEmitSseDelta(dataStr: string, onDelta: LlmStreamCallback): void {
    const chunk: LlmStreamChunk = JSON.parse(dataStr) as LlmStreamChunk;
    if (chunk.choices.length === 0) {
      return;
    }
    const delta: LlmStreamDelta = chunk.choices[0].delta;
    // DeepSeek 思考模式: reasoning_content 先于 content 到达
    if (delta.reasoning_content !== undefined && delta.reasoning_content.length > 0) {
      onDelta(delta.reasoning_content, 'reasoning');
    }
    if (delta.content !== undefined && delta.content.length > 0) {
      onDelta(delta.content, 'content');
    }
  }

  /**
   * ArrayBuffer → string (UTF-8)
   */
  private static arrayBufferToString(buffer: ArrayBuffer): string {
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    const uint8View: Uint8Array = new Uint8Array(buffer);
    return decoder.decodeWithStream(uint8View, { stream: true });
  }
}
