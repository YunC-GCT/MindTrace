/**
 * ModelCapabilities.ets — 按模型名解析「思考模式」能力
 *
 * 路径: common/src/main/ets/llm/ModelCapabilities.ets
 * 职责: 把「能不能开思考 / 怎么开 / 能不能调推理强度」从 LlmClient 内的厂商分支
 *       收敛成一张显式能力表, 供流式与非流式两条传输路径共用 (issue #226)。
 * 依赖: 无
 *
 * 数据流:
 *   LlmClient.callJsonInternal / LlmClient.callStreamInternal
 *     → resolveModelCapability(vendorId, model)
 *     → buildThinkingFields(body, capability, request)
 *
 * 规则 (issue #226, 按优先级):
 *   - deepseek 系 (model 含 'deepseek')          → toggle + low/medium/high
 *   - qwen 系     (model 含 'qwen')              → toggle, 只有 enable_thinking 开关
 *   - o1 / o3 / reasoner (前缀 o1/o3 或含 reasoner) → always_on + low/medium/high
 *   - 其它                                        → unsupported, 一个思考字段都不写
 *
 * 未知模型为什么不猜: 猜错的两个方向代价不对称 —— 把 always_on 模型写成 disabled
 * 会让请求直接失败或降智, 给不支持思考的模型塞 thinking/reasoning_effort 可能 400;
 * 而不写字段最坏只是沿用服务端默认。所以 unsupported 的语义是「不表态」, 不是「关掉」。
 */

export type ThinkingMode = 'toggle' | 'always_on' | 'unsupported';

export interface ModelCapability {
  thinking: ThinkingMode;
  efforts: string[];   // 可调推理强度; 空数组表示不支持
}

export function resolveModelCapability(vendorId: string, model: string): ModelCapability {
  const modelLower: string = model.trim().toLowerCase();
  // vendorId 保留在签名里: #226 的族群判定全部由 model 名承载, 但调用方已经掌握
  // vendor 上下文; 将来某个厂商需要整族覆盖时在这里加, 不必再改 LlmClient 调用点。

  // deepseek 系
  if (modelLower.indexOf('deepseek') >= 0) {
    const deepseekCapability: ModelCapability = {
      thinking: 'toggle',
      efforts: ['low', 'medium', 'high'],
    };
    return deepseekCapability;
  }
  // qwen 系: 只有 enable_thinking 开关, 没有 reasoning_effort 分档。
  if (modelLower.indexOf('qwen') >= 0) {
    const qwenCapability: ModelCapability = {
      thinking: 'toggle',
      efforts: [],
    };
    return qwenCapability;
  }
  // o1 / o3 / reasoner: 推理常开, 不提供关闭开关。
  if (
    modelLower.startsWith('o1') ||
    modelLower.startsWith('o3') ||
    modelLower.indexOf('reasoner') >= 0
  ) {
    const alwaysOnCapability: ModelCapability = {
      thinking: 'always_on',
      efforts: ['low', 'medium', 'high'],
    };
    return alwaysOnCapability;
  }
  // 未知模型: 不猜, 一个思考字段都不写。
  const unsupportedCapability: ModelCapability = {
    thinking: 'unsupported',
    efforts: [],
  };
  return unsupportedCapability;
}
