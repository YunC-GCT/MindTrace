// MindTrace - LLM Provider 预设常量(PR2-T1)
// 位置: common/src/main/ets/llm/providers.ets
// 责任: 5 厂商预设(2026-09 一手信源调研)+ 工厂函数
// 用途: LlmConfig.getEndpoint() / getModel() 解析 vendorId
//
// 调研依据(2026-09):
//   DeepSeek  : https://api-docs.deepseek.com/         defaultModel=deepseek-v4-pro
//   通义千问(Qwen): https://help.aliyun.com/zh/model-studio/.../compatibility-of-openai-with-dashscope
//                                                       defaultModel=qwen3-max
//   智谱 GLM:    https://docs.bigmodel.cn/cn/guide/start/model-overview
//                                                       defaultModel=glm-5.3
//   Kimi(月之暗面): https://platform.moonshot.cn/docs/api-reference  defaultModel=kimi-k2.6
//   豆包 Doubao:  https://www.volcengine.com/docs/82379/1099455   defaultModel=doubao-seed-1.6
//
// 协议: 全部 OpenAI 兼容(PR2-T1 范围 Q2=A 不变,不支持 Anthropic)
// 设计: 静态 const 数组,不用 JSON(避免 build 复杂度)+ 工厂 findProvider 简单线性查找(n=5)

export interface ProviderConfig {
  id: string;                    // 'deepseek' | 'tongyi' | 'glm' | 'kimi' | 'doubao' | 'custom'
  vendorName: string;            // 显示名 e.g. 'DeepSeek', '通义千问(Qwen)'
  baseUrl: string;               // OpenAI 兼容 base URL
  defaultModel: string;          // 该 vendor 当前推荐模型
  protocolKind: 'openai-compatible';
  docsUrl: string;
}

export const PROVIDERS: ProviderConfig[] = [
  {
    id: 'deepseek',
    vendorName: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    defaultModel: 'deepseek-v4-pro',
    protocolKind: 'openai-compatible',
    docsUrl: 'https://api-docs.deepseek.com/',
  },
  {
    id: 'tongyi',
    vendorName: '通义千问(Qwen)',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModel: 'qwen3-max',
    protocolKind: 'openai-compatible',
    docsUrl: 'https://help.aliyun.com/zh/model-studio/developer-reference/compatibility-of-openai-with-dashscope',
  },
  {
    id: 'glm',
    vendorName: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4/',
    defaultModel: 'glm-5.3',
    protocolKind: 'openai-compatible',
    docsUrl: 'https://docs.bigmodel.cn/cn/guide/start/model-overview',
  },
  {
    id: 'kimi',
    vendorName: '月之暗面 Kimi',
    baseUrl: 'https://api.moonshot.cn/v1',
    defaultModel: 'kimi-k2.6',
    protocolKind: 'openai-compatible',
    docsUrl: 'https://platform.moonshot.cn/docs/api-reference',
  },
  {
    id: 'doubao',
    vendorName: '字节豆包(Doubao)',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    defaultModel: 'doubao-seed-1.6',
    protocolKind: 'openai-compatible',
    docsUrl: 'https://www.volcengine.com/docs/82379',
  },
];

export const DEFAULT_VENDOR_ID: string = 'deepseek';

export interface CustomVendorConfig {
  vendorName: string;  // 用户填的显示名
  baseUrl: string;      // 用户填的 base URL
  model: string;        // 用户填的 model id
}

export function findProvider(id: string): ProviderConfig | null {
  for (const p of PROVIDERS) {
    if (p.id === id) {
      return p;
    }
  }
  return null;
}
