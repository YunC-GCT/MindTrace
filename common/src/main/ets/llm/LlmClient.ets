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
import { BusinessError } from '@kit.BasicServicesKit';
import { LlmConfig } from './LlmConfig';
import { ModelCapability, resolveModelCapability } from './ModelCapabilities';
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

// buildThinkingFields 的解析结果:
//   enabled — 本次请求最终是否处于思考模式 (供首字节看门狗分档)
//   effort  — 实际写入的推理强度; 空串表示本次没有该字段
interface ThinkingFieldsResult {
  enabled: boolean;
  effort: string;
}

export class LlmClient {
  private config: LlmConfig;

  constructor() {
    this.config = LlmConfig.getInstance();
  }

  // 唯一公共入口 (ADR-0004 / spec 005): request.stream 选择 JSON / SSE 流式适配路径
  public async call(request: LlmCallRequest): Promise<LlmCallResult> {
    request.cancellationToken?.throwIfCancelled();
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
    // issue #226: 思考字段不再按「流式/非流式」一刀切, 而是按模型能力决定。
    //   toggle      — 默认关闭, request.enableThinking 显式 true 才开;
    //   always_on   — 强制开启, 绝不写 disabled;
    //   unsupported — 一个思考字段都不写, 沿用服务端默认。
    const capability: ModelCapability = resolveModelCapability(
      this.config.getVendorId(), model);

    const body: LlmRequestBody = {
      model: model,
      messages: request.messages,
      max_tokens: maxTokens,
      stream: false,
    };
    const thinking: ThinkingFieldsResult = this.buildThinkingFields(body, capability, request);
    // DeepSeek 思考模式不支持 temperature, 仅在本次未开启思考时设置。
    const isDeepSeek: boolean = model.toLowerCase().indexOf('deepseek') >= 0;
    if (!isDeepSeek || !thinking.enabled) {
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

    // 3. 发 HTTP POST
    const endpointUrl: string = this.resolveEndpointUrl(this.config.getEndpoint());
    const effortText: string = thinking.effort.length > 0 ? thinking.effort : 'none';
    console.info('[LlmClient] request vendor=' + this.config.getVendorId() + ' model=' + model + ' thinking=' + capability.thinking + ' effort=' + effortText + ' stream=false');
    const httpRequest = http.createHttp();
    let response: http.HttpResponse;
    const removeCancellation: (() => void) | undefined = request.cancellationToken?.onCancel((): void => {
      httpRequest.destroy();
    });
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
      removeCancellation?.();
      request.cancellationToken?.throwIfCancelled();
      throw new LlmError(`LLM network error: ${(e as Error).message ?? String(e)}`, 'NETWORK_ERROR');
    }
    removeCancellation?.();
    request.cancellationToken?.throwIfCancelled();
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

  // issue #226: 流式与非流式共用的思考字段构造。
  //   toggle      — request.enableThinking 显式 true 才开; 开了才写 reasoning_effort;
  //                 关了按厂商写 thinking:{type:'disabled'} (DeepSeek) / enable_thinking:false (Qwen)。
  //   always_on   — 强制开启, 绝不写 disabled; reasoning_effort 取 request.reasoningEffort ?? 'medium'。
  //   unsupported — 一个字段都不写。
  private buildThinkingFields(
    body: LlmRequestBody,
    capability: ModelCapability,
    request: LlmCallRequest,
  ): ThinkingFieldsResult {
    const modelLower: string = body.model.trim().toLowerCase();
    const isDeepSeek: boolean = modelLower.indexOf('deepseek') >= 0;
    const isQwen: boolean = modelLower.indexOf('qwen') >= 0;

    if (capability.thinking === 'toggle') {
      const enableThinking: boolean = request.enableThinking === true;
      if (enableThinking) {
        const effort: string = this.pickEffort(capability, request.reasoningEffort, 'high');
        if (effort.length > 0) {
          body.reasoning_effort = effort;
        }
        if (isDeepSeek) {
          const thinkingCfg: LlmThinkingConfig = { type: 'enabled' };
          body.thinking = thinkingCfg;
        }
        if (isQwen) {
          body.enable_thinking = enableThinking;
        }
        const onResult: ThinkingFieldsResult = { enabled: true, effort: effort };
        return onResult;
      }
      if (isDeepSeek) {
        const thinkingCfg: LlmThinkingConfig = { type: 'disabled' };
        body.thinking = thinkingCfg;
      }
      if (isQwen) {
        body.enable_thinking = enableThinking;
      }
      const offResult: ThinkingFieldsResult = { enabled: false, effort: '' };
      return offResult;
    }

    if (capability.thinking === 'always_on') {
      // 推理模型常开: 不写 thinking 开关字段, 只把推理强度显式化。
      const effort: string = this.pickEffort(capability, request.reasoningEffort, 'medium');
      if (effort.length > 0) {
        body.reasoning_effort = effort;
      }
      const forcedResult: ThinkingFieldsResult = { enabled: true, effort: effort };
      return forcedResult;
    }

    // unsupported: 不表态, 服务端默认即最终行为。
    const noneResult: ThinkingFieldsResult = { enabled: false, effort: '' };
    return noneResult;
  }

  // 请求里的推理强度合法且受支持才采用, 否则回落到该能力的默认档。
  private pickEffort(
    capability: ModelCapability,
    requested: string | undefined,
    fallback: string,
  ): string {
    const efforts: string[] = capability.efforts;
    if (efforts.length === 0) {
      return '';
    }
    if (requested !== undefined && efforts.indexOf(requested) >= 0) {
      return requested;
    }
    if (efforts.indexOf(fallback) >= 0) {
      return fallback;
    }
    return efforts[0];
  }

  private streamCallbackCode(data: number | undefined): string {
    if (data === undefined || data === null) {
      return 'undefined';
    }
    return data.toString();
  }

  // catch 到的值不一定是 Error(可能是 null/string), 统一转成可打印文本, 自身绝不抛
  private static describeError(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    return String(e);
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
    // issue #226: 昨天「流式默认关思考」的收敛 —— 只有可开关 (toggle) 的模型才默认关;
    // always_on 模型不能被写成 disabled, unsupported 不写任何思考字段。
    // 首字节变慢由下面的看门狗按能力分档补偿, 不再靠粗暴关闭思考。
    const capability: ModelCapability = resolveModelCapability(
      this.config.getVendorId(), model);

    const body: LlmRequestBody = {
      model: model,
      messages: request.messages,
      max_tokens: maxTokens,
      stream: true,
    };

    const thinking: ThinkingFieldsResult = this.buildThinkingFields(body, capability, request);

    // DeepSeek 思考模式不支持 temperature, 仅在本次未开启思考时设置。
    const isDeepSeek: boolean = model.toLowerCase().indexOf('deepseek') >= 0;
    if (!isDeepSeek || !thinking.enabled) {
      body.temperature = temperature;
    }

    if (request.responseFormat !== undefined) {
      body.response_format = request.responseFormat;
    }

    const bodyJson: string = JSON.stringify(body);

    // 3. 创建 HttpRequest 并发起流式请求
    const endpointUrl: string = this.resolveEndpointUrl(this.config.getEndpoint());
    const llmLog: Logger = new Logger('LlmClient');
    const effortText: string = thinking.effort.length > 0 ? thinking.effort : 'none';
    llmLog.info('request vendor=' + this.config.getVendorId() + ' model=' + model
      + ' thinking=' + capability.thinking + ' effort=' + effortText + ' stream=true');
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
        request.cancellationToken?.throwIfCancelled();
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
      let timer: number = 0;
      let firstByteTimer: number = 0;
      let removeCancellation: (() => void) | undefined = undefined;
      timer = setTimeout((): void => {
        if (!streamEnded) {
          streamEnded = true;
          clearTimeout(timer);
          clearTimeout(firstByteTimer);
          removeCancellation?.();
          httpRequest.destroy();
          console.warn('[LlmClient] stream timeout after ' + timeoutMs.toString() + 'ms');
          reject(new LlmError('LLM stream timed out after ' + timeoutMs.toString() + 'ms', 'TIMEOUT') as Error);
        }
      }, timeoutMs);

      // 首字节看门狗按能力分档 (issue #226):
      //   toggle 本次关闭 / unsupported → 30s (首字节本就该快);
      //   toggle 本次开启 / always_on  → 60s (思维链先于首个可见 token 生成)。
      const thinkingActive: boolean = capability.thinking === 'always_on'
        || (capability.thinking === 'toggle' && thinking.enabled);
      const firstByteWatchdogMs: number = thinkingActive ? 60000 : 30000;
      firstByteTimer = setTimeout((): void => {
        if (!streamEnded && !dataReceived) {
          streamEnded = true;
          clearTimeout(timer);
          removeCancellation?.();
          httpRequest.destroy();
          console.warn('[LlmClient] no first byte within ' + firstByteWatchdogMs.toString() + 'ms');
          reject(new LlmError('LLM stream no data', 'STREAM_FAILED') as Error);
        }
      }, firstByteWatchdogMs);

      removeCancellation = request.cancellationToken?.onCancel((): void => {
        if (streamEnded) {
          return;
        }
        streamEnded = true;
        clearTimeout(timer);
        clearTimeout(firstByteTimer);
        httpRequest.destroy();
        reject(new Error('CONVERSATION_CANCELLED'));
      });

      // 订阅流式数据事件
      // 真机: dataReceive 回调里任何未捕获异常都会被服务端翻译成
      // "Failed to write the received data to the disk or application code=undefined",
      // 整条流当场报废。所以这里必须吞掉全部异常, 只打日志。
      httpRequest.on('dataReceive', (chunk: ArrayBuffer): void => {
        try {
          if (streamEnded) { return; }
          dataReceived = true;
          clearTimeout(firstByteTimer);
          const chunkBytes: number = chunk.byteLength;
          const text: string = LlmClient.arrayBufferToString(chunk);
          chunkCount += 1;
          receivedBytes += chunkBytes;
          if (chunkCount === 1) {
            const rawPreview: string = text.substring(0, 120);
            const redactedPreview: string = LlmErrorBodyFormatter
              .redactSensitiveText(rawPreview)
              .replace(/\r?\n/g, '\\n');
            llmLog.info('first data bytes=' + chunkBytes.toString()
              + ' chars=' + text.length.toString()
              + ' preview=' + redactedPreview);
          }
          sseLineBuffer += text;
          sseLineBuffer = this.processSseBuffer(sseLineBuffer, trackedEventSink);
        } catch (e) {
          console.warn('[LlmClient] dataReceive error: ' + LlmClient.describeError(e));
          try {
            if (request.cancellationToken?.isCancelled() === true) {
              if (!streamEnded) {
                streamEnded = true;
                clearTimeout(timer);
                clearTimeout(firstByteTimer);
                removeCancellation?.();
                httpRequest.destroy();
                reject(new Error('CONVERSATION_CANCELLED'));
              }
              return;
            }
          } catch (cancelError) {
            // 取消状态读取/清理本身失败也不能向上抛, 否则同样毁掉整条流
            console.warn('[LlmClient] dataReceive cancel cleanup error: '
              + LlmClient.describeError(cancelError));
          }
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
        removeCancellation?.();
        // 处理 buffer 中剩余数据
        if (sseLineBuffer.trim().length > 0) {
          request.cancellationToken?.throwIfCancelled();
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
          'Accept': 'text/event-stream',
          'Authorization': 'Bearer ' + apiKey,
        },
        extraData: bodyJson,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
      }, (err: Error, data: number | undefined): void => {
        const errCode: number | undefined = err ? (err as BusinessError).code : undefined;
        llmLog.info('requestInStream cb err=' + (err ? err.message : 'null')
          + ' errCode=' + this.streamCallbackCode(errCode)
          + ' code=' + this.streamCallbackCode(data));
        if (err) {
          console.error('[LlmClient] stream err: ' + err.message
            + ' errCode=' + this.streamCallbackCode(errCode));
          if (!streamEnded) {
            streamEnded = true;
            clearTimeout(timer);
            clearTimeout(firstByteTimer);
            removeCancellation?.();
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
            clearTimeout(firstByteTimer);
            removeCancellation?.();
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
