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
//   // 流式: 真 SSE (requestInStream), 每个结构化事件经 onDelta 交付
//   await client.call({
//     messages: [...],
//     stream: true,
//     onDelta: (event: StreamEvent): void => { ... },
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
import { LlmErrorBodyFormatter } from './LlmErrorBodyFormatter';
import { LlmResponseParser, TRUNCATION_MARKER } from './LlmResponseParser';
import { Logger } from '../utils/logger';
import {
  LlmRequestBody,
  LlmResponse,
  LlmStreamChunk,
  LlmStreamChoice,
  LlmStreamDelta,
  LlmStreamCallback,
  StreamEvent,
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
    return await this.callJsonInternal(request);
  }
  // ===== 内部 =====

  // JSON 适配路径 (原 call): request() + 手动 JSON 解析, 返回 text 与可选 toolCalls
  private async callJsonInternal(request: LlmCallRequest): Promise<LlmCallResult> {
    // 1. 校验 API key — PR2-T2 L3 (2026-09-08): per-vendor key(否则 fallback 全局)
    const apiKey: string | null = await this.config.getApiKey(this.config.getVendorId());
    if (apiKey === null) {
      throw new LlmError('API key not configured. Set it in Settings first.', 'NO_API_KEY');
    }

    // 2. 构造请求体(request 字段优先, 默认从 LlmConfig)
    const model: string = this.pickStr(request.model, this.config.getModel());
    const temperature: number = this.pickNum(request.temperature, this.config.getTemperature());
    const maxTokens: number = this.pickNum(request.maxTokens, this.config.getMaxTokens());
    const timeoutMs: number = this.pickNum(request.timeoutMs, this.config.getTimeoutMs());
    // 非流式调用默认关闭 thinking (2026-09-19): 非流式路径不回传 reasoning_content,
    // thinking 只会烧 max_tokens 预算 (deepseek reasoning_effort=high 实测 512/800/6000
    // 预算全被思维链耗尽, finish_reason=length 截断)。需要思考的流式聊天走 requestInStream;
    // 显式传 enableThinking 的调用方不受此默认影响。
    const enableThinking: boolean = request.enableThinking !== undefined
      ? request.enableThinking
      : false;
    const isDeepSeek: boolean = model.toLowerCase().indexOf('deepseek') >= 0;
    const isQwen: boolean = model.toLowerCase().indexOf('qwen') >= 0;

    const body: LlmRequestBody = {
      model: model,
      messages: request.messages,
      max_tokens: maxTokens,
      stream: false,
    };
    if (!isDeepSeek || !enableThinking) {
      body.temperature = temperature;
    }
    // response_format is the single transport seam for provider-declared
    // json_schema support; unsupported providers receive json_object instead.
    if (request.responseFormat !== undefined) {
      body.response_format = request.responseFormat;
    }
    if (request.tools !== undefined) {
      body.tools = request.tools;
    }
    if (request.tool_choice !== undefined) {
      body.tool_choice = request.tool_choice;
    }
    if (isDeepSeek) {
      const thinkingCfg: LlmThinkingConfig = { type: enableThinking ? 'enabled' : 'disabled' };
      body.thinking = thinkingCfg;
      if (enableThinking) {
        body.reasoning_effort = 'high';
      }
    }
    if (isQwen) {
      body.enable_thinking = enableThinking;
    }

    // 3. 发 HTTP POST
    const endpointUrl: string = this.resolveEndpointUrl(this.config.getEndpoint());
    console.info('[LlmClient] request vendor=' + this.config.getVendorId() + ' model=' + model + ' stream=false');
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
        expectDataType: http.HttpDataType.STRING,
      });
    } catch (e) {
      httpRequest.destroy();
      throw new LlmError(`LLM network error: ${(e as Error).message ?? String(e)}`, 'NETWORK_ERROR');
    }
    httpRequest.destroy();

    // 4. 状态码校验
    if (response.responseCode !== 200) {
      const errBody: string = LlmErrorBodyFormatter.format(response.result);
      throw new LlmError(`LLM API error ${response.responseCode}: ${errBody}`, 'API_ERROR');
    }

    // 5. 解析 JSON (decodeFull: 保留完整响应体, 不能用 format() 的 256 字符预览截断)
    const raw: string = LlmErrorBodyFormatter.decodeFull(response.result);
    let parsed: LlmResponse;
    try {
      parsed = JSON.parse(raw) as LlmResponse;
    } catch (e) {
      throw new LlmError(`LLM response parse error: ${(e as Error).message ?? String(e)}`, 'PARSE_ERROR');
    }

    // 6. 提取 content / tool_calls
    const promptTokens: number = parsed.usage?.prompt_tokens ?? 0;
    const completionTokens: number = parsed.usage?.completion_tokens ?? 0;
    console.info('[LlmClient] response choices=' + parsed.choices.length.toString()
      + ' promptTokens=' + promptTokens.toString()
      + ' completionTokens=' + completionTokens.toString());
    return LlmResponseParser.buildCallResult(parsed);
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

  private streamCallbackCode(data: number | undefined): string {
    if (data === undefined || data === null) {
      return 'undefined';
    }
    return data.toString();
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
   * 每收到一个有效结构化事件即触发回调，实现逐字实时渲染。
   */
  private async callStreamInternal(
    request: LlmCallRequest,
    onEvent: LlmStreamCallback,
  ): Promise<void> {
    // 1. 校验 API key — PR2-T2 L3 (2026-09-08): per-vendor key
    const apiKey: string | null = await this.config.getApiKey(this.config.getVendorId());
    if (apiKey === null) {
      throw new LlmError('API key not configured. Set it in Settings first.', 'NO_API_KEY');
    }

    // 2. 构造请求体
    const model: string = this.pickStr(request.model, this.config.getModel());
    const temperature: number = this.pickNum(request.temperature, this.config.getTemperature());
    const maxTokens: number = this.pickNum(request.maxTokens, this.config.getMaxTokens());
    const timeoutMs: number = this.pickNum(request.timeoutMs, this.config.getTimeoutMs());
    const enableThinking: boolean = request.enableThinking !== undefined
      ? request.enableThinking
      : this.config.getEnableThinking();
    const isDeepSeek: boolean = model.toLowerCase().indexOf('deepseek') >= 0;
    const isQwen: boolean = model.toLowerCase().indexOf('qwen') >= 0;

    // 构造 body (Record 避免 redacted 匹配问题)
    const bodyObj: Record<string, Object> = {
    };

    // 手动设置字段以避免 redacted 字段匹配
    bodyObj['model'] = model;
    bodyObj['messages'] = request.messages as Object;
    bodyObj['stream'] = true;
    bodyObj['max_tokens'] = maxTokens;

    // DeepSeek 思考模式不支持 temperature,仅在非思考模式下设置
    if (!isDeepSeek || !enableThinking) {
      bodyObj['temperature'] = temperature;
    }

    if (isDeepSeek) {
      const thinkingCfg: LlmThinkingConfig = { type: enableThinking ? 'enabled' : 'disabled' };
      bodyObj['thinking'] = thinkingCfg as Object;
      if (enableThinking) {
        bodyObj['reasoning_effort'] = 'high';
      }
    }

    if (isQwen) {
      bodyObj['enable_thinking'] = enableThinking;
    }

    if (request.responseFormat !== undefined) {
      bodyObj['response_format'] = request.responseFormat as Object;
    }

    const bodyJson: string = JSON.stringify(bodyObj);

    // 3. 创建 HttpRequest 并发起流式请求
    const endpointUrl: string = this.resolveEndpointUrl(this.config.getEndpoint());
    const llmLog: Logger = new Logger('LlmClient');
    llmLog.info('request vendor=' + this.config.getVendorId() + ' model=' + model
      + ' thinking=' + enableThinking.toString() + ' qwen=' + isQwen.toString() + ' stream=true');
    const httpRequest = http.createHttp();

    return new Promise<void>((resolve: (value: void) => void, reject: (reason: Error) => void): void => {
      let sseLineBuffer: string = '';
      let streamEnded: boolean = false;
      let dataReceived: boolean = false;
      let chunkCount: number = 0;
      let receivedBytes: number = 0;
      let thinkingEvents: number = 0;
      let thinkingChars: number = 0;
      let textEvents: number = 0;
      let textChars: number = 0;
      const trackedEventSink: LlmStreamCallback = (event: StreamEvent): void => {
        if (event.type === 'thinking') {
          thinkingEvents += 1;
          thinkingChars += event.delta.length;
        } else if (event.type === 'text') {
          textEvents += 1;
          textChars += event.delta.length;
        }
        onEvent(event);
      };

      // 超时保护 (2 分钟总超时)
      const timer: number = setTimeout((): void => {
        if (!streamEnded) {
          streamEnded = true;
          httpRequest.destroy();
          console.warn('[LlmClient] stream timeout after ' + timeoutMs.toString() + 'ms');
          reject(new LlmError('LLM stream timed out after ' + timeoutMs.toString() + 'ms', 'TIMEOUT') as Error);
        }
      }, timeoutMs);

      // 首字节超时: 30 秒内无数据则降级(2026-09-07 PR1j: deepseek-v4-pro 思考模式
      // thinking_content 阶段可能 10-20 秒才发出第一个 chunk,8 秒不够)
      const firstByteTimer: number = setTimeout((): void => {
        if (!streamEnded && !dataReceived) {
          streamEnded = true;
          clearTimeout(timer);
          httpRequest.destroy();
          console.warn('[LlmClient] no data received within 30s, triggering fallback');
          reject(new LlmError('LLM stream no data', 'STREAM_FAILED') as Error);
        }
      }, 30000);

      // 订阅流式数据事件
      httpRequest.on('dataReceive', (chunk: ArrayBuffer): void => {
        if (streamEnded) { return; }
        dataReceived = true;
        clearTimeout(firstByteTimer);
        try {
          const text: string = LlmClient.arrayBufferToString(chunk);
          chunkCount += 1;
          receivedBytes += text.length;
          sseLineBuffer += text;
          sseLineBuffer = this.processSseBuffer(sseLineBuffer, trackedEventSink);
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
        // 处理 buffer 中剩余数据
        if (sseLineBuffer.trim().length > 0) {
          this.processSseBufferFinal(sseLineBuffer, trackedEventSink);
        }

        llmLog.info('stream completed chunks=' + chunkCount.toString()
          + ' bytes=' + receivedBytes.toString()
          + ' thinkingEvents=' + thinkingEvents.toString()
          + ' thinkingChars=' + thinkingChars.toString()
          + ' textEvents=' + textEvents.toString()
          + ' textChars=' + textChars.toString()
          + ' remaining=' + sseLineBuffer.length.toString());

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
      }, (err: Error, data: number | undefined): void => {
        llmLog.info('requestInStream cb err=' + (err ? err.message : 'null') + ' code=' + this.streamCallbackCode(data));
        if (err) {
          console.error('[LlmClient] stream err: ' + err.message);
          if (!streamEnded) {
            streamEnded = true;
            clearTimeout(timer);
            clearTimeout(firstByteTimer);
            httpRequest.destroy();
            reject(new LlmError(
              'LLM stream request failed: ' + err.message,
              'NETWORK_ERROR',
            ) as Error);
          }
          return;
        }
        const responseCode: number = data ?? 0;
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
   * 处理 SSE 行缓冲,解析完整的 SSE events 并触发结构化事件回调
   * 返回未处理完的剩余 buffer
   */
  private processSseBuffer(
    buffer: string,
    onEvent: LlmStreamCallback,
  ): string {
    let remaining: string = buffer;

    // 查找完整的 SSE event (以 \n 分隔 — OpenAI/DeepSeek 兼容格式)
    // 修复 2026-09-07 PR1k: OpenAI/DeepSeek 实际 SSE 格式是 data: {...}\n 每个行一个 event
    //   不是 SSE 标准的 \n\n 双换行分隔。LlmClient 之前找 \n\n 永远找不到 event 边界,
    //   buffer 累积到 dataEnd 还没 emit 0 次。
    //   (参考 OpenAI 官方社区: https://community.openai.com/t/80861)
    while (true) {
      const singleNewlineIdx: number = remaining.indexOf('\n');
      if (singleNewlineIdx < 0) {
        // 没有完整 event 行,保留剩余
        break;
      }

      const eventText: string = remaining.substring(0, singleNewlineIdx);
      remaining = remaining.substring(singleNewlineIdx + 1);

      // 解析该 event 行
      const trimmed: string = eventText.trim();
      if (trimmed.length === 0) {
        continue;
      }
      if (trimmed.indexOf('data:') !== 0) {
        continue;
      }

      const dataStr: string = trimmed.substring(5).trim();
      if (dataStr === '[DONE]') {
        continue; // 流结束信号,由 dataEnd 事件处理
      }

      // 解析 JSON chunk
      try {
        this.emitSseEvents(dataStr, onEvent);
      } catch (e) {
        // 不完整的 JSON (跨 TCP 包),放回 buffer 等待更多数据
        return eventText + '\n' + remaining;
      }
    }

    return remaining;
  }

  /**
   * 流结束时处理 buffer 中可能残留的最后一段数据
   */
  private processSseBufferFinal(buffer: string, onEvent: LlmStreamCallback): void {
    const trimmed: string = buffer.trim();
    if (trimmed.length === 0) {
      return;
    }
    const lines: string[] = trimmed.split('\n');
    for (const line of lines) {
      const dataPrefix: string = 'data:';
      const prefixIdx: number = line.indexOf(dataPrefix);
      if (prefixIdx < 0) {
        continue;
      }
      const dataStr: string = line.substring(prefixIdx + dataPrefix.length).trim();
      if (dataStr === '[DONE]' || dataStr.length === 0) {
        continue;
      }
      try {
        this.emitSseEvents(dataStr, onEvent);
      } catch (e) {
        // 最终残留数据解析失败,静默丢弃
      }
    }
  }

  /**
   * 解析单行 SSE data 并触发结构化事件回调 (JSON 解析失败则抛异常)。
   * #111: reasoning_content emit thinking,content emit text;不再把 thinking 伪装为 text。
   */
  private emitSseEvents(dataStr: string, onEvent: LlmStreamCallback): void {
    const events: StreamEvent[] = LlmClient.parseStreamEventsFromSseData(dataStr);
    for (const event of events) {
      onEvent(event);
    }
  }

  /**
   * Seam A: 单条 SSE data JSON payload -> 结构化 StreamEvent 数组。
   * 有效 JSON 中 choices 为空或 delta 为 null 时返回空数组;非法/不完整 JSON 保持抛出供 buffer 重试。
   */
  public static parseStreamEventsFromSseData(dataStr: string): StreamEvent[] {
    const chunk: LlmStreamChunk = JSON.parse(dataStr) as LlmStreamChunk;
    if (chunk.choices.length === 0) {
      return [];
    }
    const events: StreamEvent[] = [];
    const choice: LlmStreamChoice = chunk.choices[0];
    const delta: LlmStreamDelta | null = choice.delta;
    if (delta !== undefined && delta !== null) {
      const reasoning: string = delta.reasoning_content ?? '';
      if (reasoning.length > 0) {
        const thinkingEvent: StreamEvent = { type: 'thinking', delta: reasoning };
        events.push(thinkingEvent);
      }
      const content: string = delta.content ?? '';
      if (content.length > 0) {
        const textEvent: StreamEvent = { type: 'text', delta: content };
        events.push(textEvent);
      }
    }
    if (choice.finish_reason === 'length') {
      const truncationEvent: StreamEvent = { type: 'text', delta: '\n\n' + TRUNCATION_MARKER };
      events.push(truncationEvent);
    }
    return events;
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
